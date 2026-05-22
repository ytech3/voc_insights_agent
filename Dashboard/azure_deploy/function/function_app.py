"""
VOC Insights Agent — Azure Function proxy
=========================================
Bridges the Tableau-embedded chat widget to Snowflake Cortex AI.

Endpoints
---------
POST /api/chat    — main chat endpoint (routes to Cortex Analyst or Cortex Search)
GET  /api/health  — liveness probe (used to warm cold starts on widget load)

Required App Settings
---------------------
SNOWFLAKE_ACCOUNT, SNOWFLAKE_USER, SNOWFLAKE_PRIVATE_KEY,
SNOWFLAKE_ROLE, SNOWFLAKE_WAREHOUSE, SNOWFLAKE_DATABASE, SNOWFLAKE_SCHEMA
(Optional) SNOWFLAKE_PRIVATE_KEY_PASSPHRASE if the .p8 file is encrypted.
"""

from __future__ import annotations

import base64
import hashlib
import json
import logging
import os
import re
import tempfile
import threading
import time
from datetime import date, datetime
from decimal import Decimal
from pathlib import Path
from typing import Any

import azure.functions as func
import jwt
import requests
import snowflake.connector
import yaml
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

SEMANTIC_MODEL          = "@TBRDP_DW_PROD.LOAD.CORTEX_SEMANTIC_MODELS/voc_semantic_model.yaml"
SEMANTIC_MODEL_FILE     = "voc_semantic_model.yaml"
# Optional local path (set as App Setting / local.settings.json). When present, we
# read the YAML from disk instead of downloading from the stage — useful for testing.
SEMANTIC_MODEL_LOCAL    = os.environ.get("SEMANTIC_MODEL_LOCAL_PATH")
ANALYST_PATH            = "/api/v2/cortex/analyst/message"

# Cortex Complete model used to summarize SQL results into natural language.
# claude-haiku-4-5: fast Claude (~2.6s on this account), good quality prose.
# Bump to claude-sonnet-4-5 for slightly better prose at +~1s latency.
# Non-Claude alternate: llama3.1-70b (~2.5s) similar quality at lower cost.
COMPLETE_MODEL = "claude-haiku-4-5"

MAX_HISTORY   = 10
SQL_ROW_LIMIT = 200

def _summarize_sample_size(kind: str, total_rows: int) -> int:
    """Dynamic row budget for Cortex Complete by result type.
    Feedback needs more rows for theme coverage; chart/metric can show all up to cap."""
    if kind == "feedback":
        return min(total_rows, 20)
    return min(total_rows, 15)

# ─── RESPONSE CACHE (15-minute TTL) ──────────────────────────────────────────
# Identical questions within the same session hit cache instead of Cortex Analyst.
# Keyed on (normalized question + last 4 history turns). Max 200 entries; expired
# entries are evicted lazily on each write.

_RESPONSE_CACHE: dict = {}
_CACHE_TTL    = 900   # seconds
_CACHE_LOCK   = threading.Lock()

def _cache_key(question: str, history: list) -> str:
    norm_q  = re.sub(r"\s+", " ", question.strip().lower())
    recent  = json.dumps(history[-4:], sort_keys=True) if history else ""
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

# ─── PRIVATE KEY (loaded once per cold start) ────────────────────────────────

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
    # JWT iss/sub uses the account identifier without region/cloud suffix.
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

# ─── CORTEX ANALYST ──────────────────────────────────────────────────────────

VERBOSE_MARKERS = (
    "The following SQL expressions",
    "The SQL generated initially",
    "Your semantic model is larger",
    "The following synonyms are duplicated",
    "ℹ️ The following SQL expressions",
)

def _split_analyst_text(raw: str) -> tuple:
    cut = len(raw)
    for marker in VERBOSE_MARKERS:
        idx = raw.find(marker)
        if 0 < idx < cut:
            cut = idx
    return raw[:cut].strip(), raw[cut:].strip()

def _parse_analyst(data: dict) -> tuple:
    text, sql, suggestions = "", None, []
    for block in data.get("message", {}).get("content", []):
        t = block.get("type")
        if t == "text":
            text = block.get("text", "")
        elif t == "sql":
            sql = block.get("statement", "")
        elif t == "suggestions":
            suggestions = block.get("suggestions", [])
    warnings = [w.get("message", "") for w in data.get("warnings", [])]
    return text, sql, suggestions, warnings

def call_analyst(question: str, history: list) -> dict:
    hist = list(history[-MAX_HISTORY * 2:])
    hist.append({
        "role": "user",
        "content": [{"type": "text", "text": question}],
    })
    url = f"https://{SF_ACCOUNT}.snowflakecomputing.com{ANALYST_PATH}"
    headers = {
        "Authorization": f"Bearer {_make_jwt()}",
        "X-Snowflake-Authorization-Token-Type": "KEYPAIR_JWT",
        "Content-Type": "application/json",
        "Accept": "application/json",
    }
    body = {"messages": hist, "semantic_model_file": SEMANTIC_MODEL}
    resp = requests.post(url, headers=headers, json=body, timeout=45)
    if resp.status_code != 200:
        raise RuntimeError(
            f"Cortex Analyst HTTP {resp.status_code}: {resp.text[:500]}"
        )
    return resp.json()

# ─── SNOWFLAKE CONNECTOR (for SQL execution + Cortex Complete) ───────────────

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

# Module-level connection cache. Saves ~2-3s/request after the first by avoiding
# the Snowflake auth handshake every time. Azure Function workers reuse module
# state between invocations, so the cache survives across requests.
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

def _jsonable(v: Any) -> Any:
    if v is None or isinstance(v, (bool, int, str)):
        return v
    if isinstance(v, float):
        return round(v, 2)
    if isinstance(v, Decimal):
        return round(float(v), 2)
    if isinstance(v, (datetime, date)):
        return v.isoformat()
    return str(v)

def run_sql(cur, sql: str) -> dict:
    clean = sql.strip().rstrip(";")
    if "limit" not in clean.lower():
        clean = f"SELECT * FROM ({clean}) _r LIMIT {SQL_ROW_LIMIT}"
    cur.execute(clean)
    cols = [c[0] for c in cur.description]
    rows = [[_jsonable(v) for v in row] for row in cur.fetchall()]
    return {"columns": cols, "rows": rows}

# ─── SEMANTIC MODEL METADATA (column descriptions for summary prompt) ───────
# Cortex Complete only sees raw SQL result numbers. Without the YAML's column
# descriptions, it can't know things like "scale: 1=satisfied … 4=dissatisfied
# (lower is better)" and will produce dangerously wrong summaries. Here we load
# the YAML once, build a {column_name: description} dict, and feed the relevant
# entries into the summary prompt at query time.

_YAML_COLUMNS_CACHE = None
_YAML_LOCK = threading.Lock()

def _extract_column_descriptions(model: dict) -> dict:
    """Walk all tables → dimensions/facts/measures/time_dimensions and pull out
    {NAME (uppercase): enriched description}. Uppercase keys make SQL string matching easy.
    sample_values and is_enum are appended to the description so Cortex Complete gets
    full context on categorical fields (valid values, scale orientation) without
    changing the rest of the pipeline."""
    out = {}
    for table in (model or {}).get("tables", []) or []:
        for category in ("dimensions", "facts", "measures", "time_dimensions", "metrics"):
            for col in (table.get(category) or []):
                name = (col.get("name") or "").strip().upper()
                desc = (col.get("description") or "").strip()
                if not name or not desc:
                    continue
                sample_values = col.get("sample_values") or []
                is_enum = col.get("is_enum", False)
                if is_enum and sample_values:
                    desc = f"{desc} Valid values: {', '.join(str(v) for v in sample_values)}."
                elif sample_values:
                    desc = f"{desc} Example values: {', '.join(str(v) for v in sample_values[:5])}."
                out[name] = desc
    return out

def _download_yaml_from_stage(cur) -> dict:
    tmpdir   = tempfile.mkdtemp(prefix="voc_yaml_")
    file_uri = "file://" + tmpdir.replace("\\", "/").rstrip("/") + "/"
    cur.execute(f"GET {SEMANTIC_MODEL} '{file_uri}'")
    # Snowflake may auto-gzip on PUT; handle both .yaml and .yaml.gz
    yaml_path = Path(tmpdir) / SEMANTIC_MODEL_FILE
    gz_path   = yaml_path.with_name(yaml_path.name + ".gz")
    if gz_path.exists():
        import gzip
        with gzip.open(gz_path, "rt", encoding="utf-8") as f:
            return yaml.safe_load(f) or {}
    with open(yaml_path, "r", encoding="utf-8") as f:
        return yaml.safe_load(f) or {}

def _get_yaml_columns() -> dict:
    """Lazy-loaded column-description cache. Tries local file first (if env var
    SEMANTIC_MODEL_LOCAL_PATH is set), else downloads from the Snowflake stage."""
    global _YAML_COLUMNS_CACHE
    with _YAML_LOCK:
        if _YAML_COLUMNS_CACHE is not None:
            return _YAML_COLUMNS_CACHE
        try:
            if SEMANTIC_MODEL_LOCAL and Path(SEMANTIC_MODEL_LOCAL).exists():
                with open(SEMANTIC_MODEL_LOCAL, "r", encoding="utf-8") as f:
                    model = yaml.safe_load(f) or {}
                logger.info("Loaded semantic model from local: %s", SEMANTIC_MODEL_LOCAL)
            else:
                conn = _get_connection()
                with conn.cursor() as cur:
                    model = _download_yaml_from_stage(cur)
                logger.info("Loaded semantic model from Snowflake stage: %s", SEMANTIC_MODEL)
            _YAML_COLUMNS_CACHE = _extract_column_descriptions(model)
            logger.info("Cached %d column descriptions from semantic model", len(_YAML_COLUMNS_CACHE))
        except Exception as e:
            logger.warning("Could not load semantic model YAML, summaries will lack scale context: %s", e)
            _YAML_COLUMNS_CACHE = {}
        return _YAML_COLUMNS_CACHE

def _relevant_column_descriptions(sql: str) -> dict:
    """Return {col: description} for every YAML column whose name appears in the SQL."""
    all_cols = _get_yaml_columns()
    if not sql or not all_cols:
        return {}
    sql_upper = sql.upper()
    # Word-boundary match so 'GAME_DATE' doesn't accidentally match 'GAME_DATE_ID' etc.
    return {
        name: desc
        for name, desc in all_cols.items()
        if re.search(rf"\b{re.escape(name)}\b", sql_upper)
    }

def _prewarm():
    """Load YAML + open Snowflake connection in the background at module load.
    Eliminates cold-start latency on the first /api/chat and /api/summary calls."""
    try:
        _get_connection()
        logger.info("Background pre-warm: Snowflake connection ready")
    except Exception as e:
        logger.warning("Background pre-warm (connection) failed: %s", e)
    try:
        _get_yaml_columns()
        logger.info("Background pre-warm: YAML column cache ready")
    except Exception as e:
        logger.warning("Background pre-warm (YAML) failed: %s", e)

threading.Thread(target=_prewarm, daemon=True, name="voc-prewarm").start()

# ─── DATA-SHAPE DETECTION ────────────────────────────────────────────────────

TEXT_COLUMN_HINTS = {
    "SENTENCE_TEXT", "FEEDBACK_TEXT", "COMMENT", "COMMENTS", "FREE_TEXT",
    "VERBATIM", "OVERALL_NUMRAT_OT", "OVERALL_FEEDBACK",
}

# Prefix patterns for Qualtrics-style numbered open-text questions (TB_ADDON_8_1 … _11).
TEXT_COLUMN_PREFIXES = ("TB_ADDON_8_",)

# Suffix patterns covering Qualtrics-style free-text columns.
# NOTE: _DESC is intentionally excluded — those columns hold short categorical enum
# values (e.g. "Highly Satisfied"), not free-form prose. Including _DESC caused
# satisfaction-distribution queries to render as feedback cards instead of charts.
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
    """Classify SQL result shape so the frontend + summarizer can react.
    Returns one of: 'feedback' (free-text rows), 'chart' (categorical x numeric),
    'metric' (everything else — table or single value)."""
    if not data or not data.get("rows"):
        return "metric"
    cols = [c.upper() for c in data.get("columns", [])]
    rows = data.get("rows", [])

    # 1. Free-text column present → qualitative feedback
    if _has_text_column(cols):
        return "feedback"

    # 2. >=2 cols, 2-25 rows, first column categorical (string/date), second numeric → chartable.
    #    Extra trailing columns (e.g. total_responses) are kept in the data for the table view,
    #    but the bar chart only uses the first two.
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

# ─── CORTEX COMPLETE (natural-language summary of SQL results) ───────────────

def _markdown_table(data: dict, max_rows: int = 15) -> str:
    cols = data.get("columns", [])
    rows = data.get("rows", [])[:max_rows]
    if not cols:
        return ""
    out = ["| " + " | ".join(cols) + " |",
           "|" + "|".join(["---"] * len(cols)) + "|"]
    for r in rows:
        out.append("| " + " | ".join("" if v is None else str(v) for v in r) + " |")
    return "\n".join(out)

def _column_metadata_block(descriptions: dict) -> str:
    """Render the column descriptions section of the summary prompt."""
    if not descriptions:
        return ""
    lines = ["", "Column definitions (READ CAREFULLY — these are authoritative):"]
    for col, desc in descriptions.items():
        lines.append(f"- {col}: {desc}")
    return "\n".join(lines) + "\n"

def _data_context_block(data: dict) -> str:
    """Inject SEASON and date-range context into the summary prompt so Cortex
    Complete knows which time period it's describing without us having to ask."""
    if not data:
        return ""
    cols_upper = [c.upper() for c in data.get("columns", [])]
    rows       = data.get("rows", [])
    if not rows:
        return ""
    parts = []
    if "SEASON" in cols_upper:
        idx     = cols_upper.index("SEASON")
        seasons = sorted({r[idx] for r in rows if r and len(r) > idx and r[idx] is not None})
        if seasons:
            parts.append(
                f"Season: {seasons[0]}" if len(seasons) == 1
                else f"Seasons covered: {', '.join(str(s) for s in seasons)}"
            )
    for col_name in ("GAME_DATE", "SURVEY_DATE"):
        if col_name in cols_upper:
            idx   = cols_upper.index(col_name)
            dates = sorted({r[idx] for r in rows if r and len(r) > idx and r[idx] is not None})
            if dates:
                parts.append(
                    f"Date: {dates[0]}" if len(dates) == 1
                    else f"Date range: {dates[0]} to {dates[-1]}"
                )
            break
    return ("\nData context: " + " | ".join(parts) + "\n") if parts else ""

NPS_HINT = (
    "NPS context: NPS_SCORE is 0-10. Promoters=9-10, Passives=7-8, Detractors=0-6. "
    "Net Promoter Score = %Promoters − %Detractors (range: −100 to +100). Higher is better.\n"
)

def _detect_result_patterns(data: dict, sql: str) -> list:
    """Return extra hint strings to append to the summary prompt when special
    column patterns are detected (NPS, multi-season comparisons)."""
    hints      = []
    cols_upper = [c.upper() for c in (data or {}).get("columns", [])]
    if any(c in cols_upper for c in ("NPS_SCORE", "NPS_SEGMENT", "TB_ADDON_9_NPS_GROUP")):
        hints.append(NPS_HINT)
    if "SEASON" in cols_upper:
        idx     = cols_upper.index("SEASON")
        rows    = (data or {}).get("rows", [])
        seasons = {r[idx] for r in rows if r and len(r) > idx and r[idx] is not None}
        if len(seasons) > 1:
            hints.append(
                "Multi-season comparison: call out which season scored higher/lower "
                "and the magnitude of change.\n"
            )
    return hints

# This block goes at the top of every prompt. It is the most important
# instruction we send — without it, summaries can confidently invert the meaning
# of "lower is better" scales.
SCALE_GUARDRAIL = (
    "CRITICAL INSTRUCTIONS — read the column definitions carefully before writing:\n"
    "1. Each numeric column has a defined SCALE and ORIENTATION. Some scales are "
    '"higher is better" (e.g., 0-10 satisfaction) and some are "lower is better" '
    '(e.g., 1=Highly Satisfied → 4=Highly Dissatisfied). Match your language to the '
    "scale orientation in the column definition. Re-read the definition before "
    "characterizing values as 'high', 'good', 'low', 'poor', etc.\n"
    "2. If a column definition says 'lower is better', then a LOWER average is GOOD "
    "and a HIGHER average is BAD — say so. Do not describe a 3.4 on a 1-4 "
    "'lower-is-better' scale as 'high satisfaction'; it is mostly dissatisfied.\n"
    "3. If a column does not have a clear scale in the definitions below, do NOT "
    "invent one. Describe the number as the raw value.\n"
)

def _summarize_prompt(question: str, interpretation: str, data: dict,
                      kind: str, descriptions: dict, sql: str = "") -> str:
    total_rows   = len(data.get("rows", []))
    sample_size  = _summarize_sample_size(kind, total_rows)
    shown        = sample_size
    table_md     = _markdown_table(data, max_rows=sample_size)
    meta_block   = _column_metadata_block(descriptions)
    ctx_block    = _data_context_block(data)
    pattern_hints = "".join(_detect_result_patterns(data, sql))

    if kind == "feedback":
        return (
            "You are a Voice-of-Customer analytics assistant for the Tampa Bay Rays. "
            "Summarize the key themes and overall sentiment from these fan comments.\n\n"
            + SCALE_GUARDRAIL
            + pattern_hints
            + meta_block
            + ctx_block
            + f"\nUser question: {question}\n\n"
            + f"Fan comments ({total_rows} total"
            + (f", showing first {shown}" if total_rows > shown else "")
            + "):\n"
            + table_md
            + "\n\nWrite 2 to 4 sentences. Lead with the dominant sentiment or theme. "
            "Mention 1-3 specific recurring topics or phrases from the comments. "
            "Conversational tone. Do NOT repeat the question. Do NOT add preambles "
            "like 'Based on the comments' or apologies. Just give the summary. "
            "Number format: write percentages as at most 2 decimal places, dropping "
            "trailing zeros — e.g., 80%, 80.1%, 80.23%. Never write long decimals."
        )

    return (
        "You are a Voice-of-Customer analytics assistant for the Tampa Bay Rays "
        "baseball team. Write a brief, direct natural-language answer to the user's "
        "question based on the SQL results below.\n\n"
        + SCALE_GUARDRAIL
        + pattern_hints
        + meta_block
        + ctx_block
        + f"\nUser question: {question}\n\n"
        + f"How the system interpreted the question: {interpretation}\n\n"
        + f"Results ({total_rows} row(s) total"
        + (f", showing first {shown}" if total_rows > shown else "")
        + "):\n"
        + table_md
        + "\n\nWrite 1 to 3 sentences. Be specific with numbers AND with what those "
        "numbers mean on each column's scale. Use a conversational, professional tone. "
        "Do NOT repeat the question. Do NOT add disclaimers or preambles like 'Based "
        "on the data'. Just give the answer. "
        "Number format: write percentages as at most 2 decimal places, dropping "
        "trailing zeros — e.g., 80%, 80.1%, 80.23%. Never write long decimals."
    )

def _is_single_value(data: dict) -> bool:
    """1 row x 1 column → the value itself is the answer; frontend renders a hero
    number, so we skip Cortex Complete entirely (saves ~5-10s)."""
    rows = data.get("rows", [])
    cols = data.get("columns", [])
    return len(rows) == 1 and len(cols) == 1

def summarize(cur, question: str, interpretation: str, data: dict, kind: str,
              sql: str = "") -> str:
    """Use Cortex Complete to write a natural-language answer based on SQL results.
    Pulls column descriptions from the semantic-model YAML so the model knows each
    column's scale and orientation (critical for "lower is better" metrics)."""
    if not data or not data.get("rows"):
        return ""
    if _is_single_value(data):
        return ""  # the hero number IS the answer; no summary needed
    descriptions = _relevant_column_descriptions(sql)
    prompt = _summarize_prompt(question, interpretation, data, kind, descriptions, sql)
    try:
        cur.execute(
            "SELECT SNOWFLAKE.CORTEX.COMPLETE(%s, %s)",
            (COMPLETE_MODEL, prompt),
        )
        row = cur.fetchone()
        return (row[0] or "").strip() if row else ""
    except Exception as e:
        logger.warning("Cortex Complete summarization failed: %s", e)
        return ""

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
        _get_connection()  # pre-warm Snowflake session on widget load
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

    # Return cached result for repeated identical questions (15-min TTL).
    ck = _cache_key(question, history)
    cached = _cache_get(ck)
    if cached is not None:
        logger.info("Cache hit for question: %.80s", question)
        return _json(cached)

    try:
        raw = call_analyst(question, history)
        text, sql, suggestions, warnings = _parse_analyst(raw)
        interpretation, details = _split_analyst_text(text)

        data       = None
        data_kind  = "metric"
        sql_failed = False
        # Summary is fetched asynchronously by the frontend from /api/summary so
        # the data table and interpretation render before Cortex Complete returns.

        if sql:
            try:
                conn = _get_connection()
                with conn.cursor() as cur:
                    try:
                        data = run_sql(cur, sql)
                    except Exception as e:
                        logger.warning("analyst SQL execution failed: %s", e)
                        sql_failed = True
                    if data:
                        data_kind = _data_kind(data)
            except snowflake.connector.errors.OperationalError as e:
                # Cached session expired — drop it so the next request reconnects fresh
                logger.info("Snowflake session error, dropping cached connection: %s", e)
                _reset_connection()
                sql_failed = True

        history_update = [
            {"role": "user", "content": [{"type": "text", "text": question}]},
        ]
        if "message" in raw:
            history_update.append(raw["message"])

        payload = {
            "type":           "analyst",
            "summary":        "",              # filled in by /api/summary (async)
            "interpretation": interpretation,  # one-liner: how Cortex understood Q
            "details":        details,         # verbose markers stripped from text
            "sql":            None if sql_failed else sql,
            "data":           data,
            "data_kind":      data_kind,       # 'metric' | 'feedback' | 'chart'
            "suggestions":    suggestions,
            "warnings":       warnings,
            "sql_failed":     sql_failed,
            "history_update": history_update,
        }
        if not sql_failed:
            _cache_set(ck, payload)
        return _json(payload)

    except Exception as e:
        logger.exception("chat handler failed")
        return _json({"error": str(e)[:500]}, 500)


@app.route(route="summary", methods=["POST"])
def summary_endpoint(req: func.HttpRequest) -> func.HttpResponse:
    """Streaming-companion endpoint. Frontend calls this immediately after /api/chat
    so the user sees data instantly while the summary cooks in the background."""
    try:
        body = req.get_json()
    except ValueError:
        return _json({"error": "invalid JSON body"}, 400)

    question       = (body.get("question") or "").strip()
    interpretation = body.get("interpretation") or ""
    data           = body.get("data") or {}
    data_kind      = body.get("data_kind") or "metric"
    sql            = body.get("sql") or ""

    if not data or not data.get("rows"):
        return _json({"summary": ""})

    try:
        conn = _get_connection()
        with conn.cursor() as cur:
            summary = summarize(cur, question, interpretation, data, data_kind, sql)
        return _json({"summary": summary})
    except snowflake.connector.errors.OperationalError as e:
        logger.info("Snowflake session error in /api/summary, resetting: %s", e)
        _reset_connection()
        return _json({"error": "session expired"}, 500)
    except Exception as e:
        logger.exception("summary handler failed")
        return _json({"error": str(e)[:500]}, 500)
