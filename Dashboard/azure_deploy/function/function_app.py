"""
VOC Insights Agent — Azure Function proxy
=========================================
Streams questions to the Snowflake Cortex Agents REST endpoint and aggregates
the SSE response into a single JSON payload the widget can render.

The stored agent (SNOWFLAKE_INTELLIGENCE.AGENTS.VOC_INSIGHTS_AGENT) owns its
orchestrator model (claude-opus-4-6), tools (voc_analyst Cortex Analyst +
voc_feedback_search Cortex Search), and instructions. The Function is a thin
auth + aggregation layer.

Endpoints
---------
POST /api/chat    — one call, returns final text + last data + suggestions
GET  /api/health  — liveness probe
POST /api/summary — no-op kept for backwards compatibility with the old frontend

Required App Settings
---------------------
SNOWFLAKE_ACCOUNT, SNOWFLAKE_USER, SNOWFLAKE_PRIVATE_KEY
(Optional) SNOWFLAKE_PRIVATE_KEY_PASSPHRASE if the .p8 file is encrypted.
SNOWFLAKE_ROLE, SNOWFLAKE_WAREHOUSE, SNOWFLAKE_DATABASE, SNOWFLAKE_SCHEMA
(used only by the legacy direct-SQL fallback)
"""

from __future__ import annotations

import base64
import hashlib
import json
import logging
import os
import re
import threading
import time
from datetime import date, datetime
from decimal import Decimal
from typing import Any

import azure.functions as func
import jwt
import requests
import snowflake.connector
from cryptography.hazmat.backends import default_backend
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.serialization import load_pem_private_key

# ─── CONFIG ──────────────────────────────────────────────────────────────────

SF_ACCOUNT   = os.environ["SNOWFLAKE_ACCOUNT"]
SF_USER      = os.environ["SNOWFLAKE_USER"]
SF_ROLE      = os.environ["SNOWFLAKE_ROLE"]
SF_WAREHOUSE = os.environ["SNOWFLAKE_WAREHOUSE"]
SF_DATABASE  = os.environ["SNOWFLAKE_DATABASE"]
SF_SCHEMA    = os.environ["SNOWFLAKE_SCHEMA"]
SF_PRIVATE_KEY_PEM        = os.environ["SNOWFLAKE_PRIVATE_KEY"]
SF_PRIVATE_KEY_PASSPHRASE = os.environ.get("SNOWFLAKE_PRIVATE_KEY_PASSPHRASE")

# Stored agent fully-qualified name. Owns the orchestrator model + tools + instructions.
AGENT_DATABASE = "SNOWFLAKE_INTELLIGENCE"
AGENT_SCHEMA   = "AGENTS"
AGENT_NAME     = "VOC_INSIGHTS_AGENT"

# Agent runs can take 20-60s (multi-step planning + 2-4 SQL queries). Be generous.
AGENT_TIMEOUT_SEC = 90

MAX_HISTORY = 10

# ─── RESPONSE CACHE (15-minute TTL) ──────────────────────────────────────────

_RESPONSE_CACHE: dict = {}
_CACHE_TTL    = 900
_CACHE_LOCK   = threading.Lock()

def _cache_key(question: str, history: list) -> str:
    norm_q = re.sub(r"\s+", " ", question.strip().lower())
    recent = json.dumps(history[-4:], sort_keys=True) if history else ""
    return hashlib.md5(f"{norm_q}|{recent}".encode()).hexdigest()

def _cache_get(key: str):
    with _CACHE_LOCK:
        entry = _RESPONSE_CACHE.get(key)
        if entry and time.time() - entry["ts"] < _CACHE_TTL:
            return entry["value"]
        if entry:
            del _RESPONSE_CACHE[key]
    return None

def _cache_set(key: str, value: dict) -> None:
    with _CACHE_LOCK:
        now     = time.time()
        expired = [k for k, v in _RESPONSE_CACHE.items() if now - v["ts"] >= _CACHE_TTL]
        for k in expired:
            del _RESPONSE_CACHE[k]
        if len(_RESPONSE_CACHE) < 200:
            _RESPONSE_CACHE[key] = {"ts": now, "value": value}

logger = logging.getLogger("voc-agent")

# ─── PRIVATE KEY + JWT (unchanged from the Analyst-era implementation) ───────

def _load_private_key():
    pwd = SF_PRIVATE_KEY_PASSPHRASE.encode("utf-8") if SF_PRIVATE_KEY_PASSPHRASE else None
    return load_pem_private_key(
        SF_PRIVATE_KEY_PEM.encode("utf-8"),
        password=pwd,
        backend=default_backend(),
    )

PRIVATE_KEY = _load_private_key()
PRIVATE_KEY_DER = PRIVATE_KEY.private_bytes(
    encoding=serialization.Encoding.DER,
    format=serialization.PrivateFormat.PKCS8,
    encryption_algorithm=serialization.NoEncryption(),
)

def _account_locator() -> str:
    return SF_ACCOUNT.split(".")[0].upper()

def _public_key_fingerprint() -> str:
    pub_der = PRIVATE_KEY.public_key().public_bytes(
        encoding=serialization.Encoding.DER,
        format=serialization.PublicFormat.SubjectPublicKeyInfo,
    )
    digest = hashlib.sha256(pub_der).digest()
    return "SHA256:" + base64.b64encode(digest).decode("utf-8")

PUBLIC_KEY_FP  = _public_key_fingerprint()
QUALIFIED_USER = f"{_account_locator()}.{SF_USER.upper()}"

def _make_jwt(lifetime_sec: int = 3600) -> str:
    now = int(time.time())
    payload = {
        "iss": f"{QUALIFIED_USER}.{PUBLIC_KEY_FP}",
        "sub": QUALIFIED_USER,
        "iat": now,
        "exp": now + lifetime_sec,
    }
    return jwt.encode(payload, PRIVATE_KEY, algorithm="RS256")

# ─── SNOWFLAKE CONNECTOR (kept for any direct-SQL fallbacks; mostly unused) ──

def _connect():
    return snowflake.connector.connect(
        user=SF_USER,
        account=SF_ACCOUNT,
        private_key=PRIVATE_KEY_DER,
        role=SF_ROLE,
        warehouse=SF_WAREHOUSE,
        database=SF_DATABASE,
        schema=SF_SCHEMA,
        client_session_keep_alive=True,
        session_parameters={"QUERY_TAG": "VOC_AZURE_PROXY"},
    )

_CONN_LOCK = threading.Lock()
_CONN = None

def _get_connection():
    global _CONN
    with _CONN_LOCK:
        if _CONN is None or _CONN.is_closed():
            _CONN = _connect()
        return _CONN

def _reset_connection():
    global _CONN
    with _CONN_LOCK:
        if _CONN is not None:
            try: _CONN.close()
            except Exception: pass
            _CONN = None

# ─── DATA-SHAPE DETECTION (drives chart/feedback/hero rendering in frontend) ──

TEXT_COLUMN_HINTS = {
    "SENTENCE_TEXT", "FEEDBACK_TEXT", "COMMENT", "COMMENTS", "FREE_TEXT",
    "VERBATIM", "OVERALL_NUMRAT_OT", "OVERALL_FEEDBACK",
}
TEXT_COLUMN_PREFIXES = ("TB_ADDON_8_",)
TEXT_COLUMN_SUFFIXES = (
    "_FEEDBACK", "_COMMENT", "_COMMENTS", "_TEXT",
    "_SPECIFY", "_VERBATIM", "_NUMRAT_OT",
)

def _has_text_column(cols_upper: list) -> bool:
    if any(c in TEXT_COLUMN_HINTS for c in cols_upper):
        return True
    if any(c.startswith(p) for c in cols_upper for p in TEXT_COLUMN_PREFIXES):
        return True
    return any(c.endswith(s) for c in cols_upper for s in TEXT_COLUMN_SUFFIXES)

def _data_kind(data: dict) -> str:
    """Classify SQL result shape: 'feedback' | 'chart' | 'metric'."""
    if not data or not data.get("rows"):
        return "metric"
    cols = [c.upper() for c in data.get("columns", [])]
    rows = data.get("rows", [])
    if _has_text_column(cols):
        return "feedback"
    if len(cols) >= 2 and 2 <= len(rows) <= 25:
        first  = [r[0] for r in rows if r and len(r) > 0]
        second = [r[1] for r in rows if r and len(r) > 1]
        first_categorical = first and not all(isinstance(v, (int, float)) for v in first if v is not None)
        second_numeric    = second and all(
            (v is None or isinstance(v, (int, float))) for v in second
        ) and any(isinstance(v, (int, float)) for v in second)
        if first_categorical and second_numeric:
            return "chart"
    return "metric"

# ─── CORTEX AGENTS REST CLIENT ───────────────────────────────────────────────

def _agent_url() -> str:
    """Stored-agent invocation endpoint (NOT /api/v2/cortex/agent:run — that's inline only)."""
    return (
        f"https://{SF_ACCOUNT}.snowflakecomputing.com"
        f"/api/v2/databases/{AGENT_DATABASE}/schemas/{AGENT_SCHEMA}/agents/{AGENT_NAME}:run"
    )

def _coerce_numeric(v: Any) -> Any:
    """Snowflake returns numeric column values as strings in the JSON result set
    (e.g. "9.18" instead of 9.18). Coerce for the data-shape classifier."""
    if not isinstance(v, str):
        return v
    s = v.strip()
    if not s or s.lower() in ("null", "none"):
        return None
    # Avoid coercing date strings or anything with letters
    if re.match(r"^-?\d+(\.\d+)?$", s):
        try:
            f = float(s)
            return int(f) if f.is_integer() else round(f, 2)
        except ValueError:
            return v
    return v

def _extract_columns(result_set: dict, sql: str = "") -> list:
    """Pull column names from Snowflake's resultSetMetaData. Falls back to
    parsing the SELECT clause or generic col_N labels."""
    meta = (result_set or {}).get("resultSetMetaData") or {}
    row_type = meta.get("rowType") or []
    if row_type:
        return [(rt.get("name") or f"col_{i}") for i, rt in enumerate(row_type)]
    # Fallback: try to pull aliases from the SQL (best-effort, won't always work)
    if sql:
        m = re.search(r"^\s*SELECT\s+(.+?)\s+FROM\s", sql, re.IGNORECASE | re.DOTALL)
        if m:
            parts = [p.strip() for p in m.group(1).split(",")]
            names = []
            for p in parts:
                alias_m = re.search(r"\bAS\s+([A-Za-z_][A-Za-z0-9_]*)\s*$", p, re.IGNORECASE)
                if alias_m:
                    names.append(alias_m.group(1).upper())
                else:
                    last = re.split(r"\s+", p)[-1]
                    names.append(re.sub(r"[^A-Za-z0-9_]", "", last).upper() or f"col_{len(names)}")
            if names:
                return names
    # Last resort — infer column count from the first row
    rows = (result_set or {}).get("data") or []
    n = len(rows[0]) if rows else 0
    return [f"col_{i}" for i in range(n)]

def _extract_rows(result_set: dict) -> list:
    raw = (result_set or {}).get("data") or []
    out = []
    for row in raw:
        out.append([_coerce_numeric(v) for v in row])
    return out

def _build_messages(question: str, history: list) -> list:
    """Build the messages array for the agent. Trims history to MAX_HISTORY turns."""
    msgs = list(history[-MAX_HISTORY * 2:]) if history else []
    msgs.append({
        "role": "user",
        "content": [{"type": "text", "text": question}],
    })
    return msgs

class AgentRunResult:
    """Aggregated output from one /agents/<name>:run SSE stream."""
    def __init__(self):
        self.text_parts: list[str]    = []
        self.thinking_parts: list[str] = []
        self.tool_uses: list[dict]     = []   # ALL tool invocations
        self.tool_results: list[dict]  = []   # ALL tool results, paired with tool_use_id
        self.suggestions: list[str]    = []
        self.status_messages: list[str] = []
        self.error: str | None         = None

    @property
    def final_text(self) -> str:
        return "".join(self.text_parts).strip()

    @property
    def thinking(self) -> str:
        return "".join(self.thinking_parts).strip()

    @property
    def last_sql_tool_use(self) -> dict | None:
        """The last system_execute_sql tool call — its SQL is what produced the answer."""
        for tu in reversed(self.tool_uses):
            if tu.get("type") == "system_execute_sql" or tu.get("name") == "system_execute_sql":
                return tu
        return None

    @property
    def last_sql_result(self) -> dict | None:
        """The last system_execute_sql tool result with rows. Earlier results are exploratory."""
        for tr in reversed(self.tool_results):
            if tr.get("type") == "system_execute_sql" or tr.get("tool_type") == "system_execute_sql":
                payload = (tr.get("content") or [{}])[0]
                rs = (payload.get("json") or {}).get("result_set") or {}
                if rs.get("data"):
                    return tr
        return None


def _parse_sse_event(event_name: str, raw_data: str, out: AgentRunResult) -> None:
    """Mutate `out` based on one SSE event line. Tolerates unknown event types."""
    try:
        ev = json.loads(raw_data)
    except json.JSONDecodeError:
        return  # ignore malformed event payloads

    if event_name == "response.text.delta":
        txt = ev.get("text") or ev.get("delta") or ""
        if txt:
            out.text_parts.append(txt)
    elif event_name == "response.text":
        # Full aggregate of text deltas — ignore so we don't double-count
        pass
    elif event_name == "response.thinking.delta":
        txt = ev.get("text") or ""
        if txt:
            out.thinking_parts.append(txt)
    elif event_name == "response.thinking":
        # Full aggregate — ignore
        pass
    elif event_name == "response.tool_use":
        out.tool_uses.append(ev)
    elif event_name == "response.tool_result":
        out.tool_results.append(ev)
    elif event_name == "response.status":
        msg = ev.get("message")
        if msg:
            out.status_messages.append(msg)
    elif event_name == "response.suggested_queries":
        for q in (ev.get("suggested_queries") or []):
            if q.get("query"):
                out.suggestions.append(q["query"])
    elif event_name == "error":
        out.error = ev.get("message", "unknown error")
    # response, response.tool_result.status, done — ignored on purpose


def call_agent(question: str, history: list) -> AgentRunResult:
    """POST to the stored-agent endpoint, parse SSE, return aggregated result."""
    url = _agent_url()
    headers = {
        "Authorization": f"Bearer {_make_jwt()}",
        "X-Snowflake-Authorization-Token-Type": "KEYPAIR_JWT",
        "Content-Type": "application/json",
        "Accept": "text/event-stream",
    }
    body = {"messages": _build_messages(question, history)}

    out = AgentRunResult()

    try:
        resp = requests.post(
            url, headers=headers, json=body, stream=True, timeout=AGENT_TIMEOUT_SEC,
        )
    except requests.RequestException as e:
        out.error = f"network error: {e}"
        return out

    if resp.status_code != 200:
        out.error = f"agent:run HTTP {resp.status_code}: {resp.text[:500]}"
        return out

    current_event = None
    for raw in resp.iter_lines(decode_unicode=True):
        if not raw:
            continue
        if raw.startswith("event: "):
            current_event = raw[len("event: "):].strip()
        elif raw.startswith("data: ") and current_event:
            payload = raw[len("data: "):]
            if payload.strip() == "[DONE]":
                break
            _parse_sse_event(current_event, payload, out)
            current_event = None
        # ":keep-alive" comments and other lines are ignored

    return out

# ─── PRE-WARM (best-effort, runs once per cold start) ────────────────────────

def _prewarm():
    try:
        _get_connection()
        logger.info("Background pre-warm: Snowflake connection ready")
    except Exception as e:
        logger.warning("Background pre-warm failed: %s", e)

threading.Thread(target=_prewarm, daemon=True, name="voc-prewarm").start()

# ─── HTTP APP ────────────────────────────────────────────────────────────────

app = func.FunctionApp(http_auth_level=func.AuthLevel.ANONYMOUS)

def _json(payload: dict, status: int = 200) -> func.HttpResponse:
    return func.HttpResponse(
        json.dumps(payload, ensure_ascii=False),
        status_code=status,
        mimetype="application/json",
    )

@app.route(route="health", methods=["GET"])
def health(req: func.HttpRequest) -> func.HttpResponse:
    try:
        _get_connection()
    except Exception as e:
        logger.warning("Health check connection warm-up failed: %s", e)
    return _json({"status": "ok", "account": _account_locator()})

@app.route(route="chat", methods=["POST"])
def chat(req: func.HttpRequest) -> func.HttpResponse:
    try:
        body = req.get_json()
    except ValueError:
        return _json({"error": "invalid JSON body"}, 400)

    question = (body.get("question") or "").strip()
    history  = body.get("history") or []
    if not question:
        return _json({"error": "question is required"}, 400)

    ck = _cache_key(question, history)
    cached = _cache_get(ck)
    if cached is not None:
        logger.info("Cache hit for question: %.80s", question)
        return _json(cached)

    try:
        result = call_agent(question, history)
    except Exception as e:
        logger.exception("agent:run call failed")
        return _json({"error": str(e)[:500]}, 500)

    if result.error:
        logger.warning("agent:run returned error: %s", result.error)
        return _json({"error": result.error[:500]}, 502)

    # Extract the last SQL + data — the answer query, not the exploratory ones
    last_tool_use   = result.last_sql_tool_use
    last_sql        = ((last_tool_use or {}).get("input") or {}).get("sql") if last_tool_use else None
    last_tool_res   = result.last_sql_result
    data            = None
    if last_tool_res:
        payload = (last_tool_res.get("content") or [{}])[0]
        rs      = (payload.get("json") or {}).get("result_set") or {}
        data    = {
            "columns": _extract_columns(rs, last_sql or ""),
            "rows":    _extract_rows(rs),
        }

    data_kind  = _data_kind(data) if data else "metric"
    sql_failed = data is None and last_sql is not None  # tool ran but produced no rows

    # Payload shape kept backwards-compatible with the existing frontend:
    # `interpretation` is what the bubble displays on first paint, so we put the
    # agent's final text there. `summary` carries the same string so the old
    # /api/summary async-swap codepath also lands on the right text if invoked.
    # `type: "agent"` causes the frontend's willStream check to be false →
    # no second /api/summary fetch is attempted.
    payload = {
        "type":           "agent",
        "summary":        result.final_text,
        "interpretation": result.final_text,           # ← shown in chat bubble
        "details":        result.thinking,             # chain-of-thought (Tech details)
        "sql":            last_sql,
        "data":           data,
        "data_kind":      data_kind,
        "suggestions":    result.suggestions[:3],
        "warnings":       [],
        "sql_failed":     sql_failed,
        "history_update": [
            {"role": "user", "content": [{"type": "text", "text": question}]},
            {"role": "assistant", "content": [{"type": "text", "text": result.final_text}]},
        ],
        # Diagnostic — frontend can ignore; useful for debugging the new pipeline
        "agent_meta": {
            "status_messages": result.status_messages,
            "tool_use_count":  len(result.tool_uses),
        },
    }
    _cache_set(ck, payload)
    return _json(payload)


@app.route(route="summary", methods=["POST"])
def summary_endpoint(req: func.HttpRequest) -> func.HttpResponse:
    """Backwards-compatibility no-op. The old frontend POSTs here after /api/chat
    to fetch the prose summary. Under the new agent:run pipeline the summary is
    already in /api/chat's payload, so this endpoint just returns empty —
    the frontend already handles an empty summary gracefully."""
    return _json({"summary": ""})
