"""
Probe — is the Cortex Agents REST endpoint reachable with our service account?

Calls POST /api/v2/cortex/agent:run with an inline agent definition
(Cortex Analyst tool only) and streams the server-sent-events response.

If this prints a non-empty stream with no HTTP error, the endpoint works for
this account and role, and we can move forward with Option 1.

Usage:
    cd Dashboard/tests
    .\.python311\python.exe probe_agent_rest.py
    # Optional: probe a named agent instead of inline mode
    .\.python311\python.exe probe_agent_rest.py --agent SNOWFLAKE_INTELLIGENCE.AGENTS.VOC_INSIGHTS_AGENT
"""

from __future__ import annotations

import argparse
import base64
import hashlib
import json
import sys
import time
from pathlib import Path

import jwt
import requests
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.serialization import load_pem_private_key

# ─── Config (must match what's deployed in Azure App Settings) ───────────────
SF_ACCOUNT     = "hta92307.east-us-2.azure"
SF_USER        = "VOC_AGENT_SVC"
SF_ROLE        = "TBRDP_DW_PROD_CORTEX_USER"
SF_WAREHOUSE   = "TBRDP_DW_CORTEX_XS_WH"
SEMANTIC_MODEL = "@TBRDP_DW_PROD.LOAD.CORTEX_SEMANTIC_MODELS/voc_semantic_model.yaml"

KEY_PATH       = Path(__file__).resolve().parent.parent / "snowflake_voc_agent.p8"
TEST_QUESTION  = "What was the average overall satisfaction last homestand?"

# ─── JWT (same logic as function_app.py / tier1_smoke.py) ────────────────────

def load_key():
    if not KEY_PATH.exists():
        sys.exit(f"FAIL: key file not found at {KEY_PATH}")
    return load_pem_private_key(KEY_PATH.read_bytes(), password=None)

def fingerprint(pk) -> str:
    pub = pk.public_key().public_bytes(
        encoding=serialization.Encoding.DER,
        format=serialization.PublicFormat.SubjectPublicKeyInfo,
    )
    return "SHA256:" + base64.b64encode(hashlib.sha256(pub).digest()).decode()

def make_jwt(pk) -> str:
    locator   = SF_ACCOUNT.split(".")[0].upper()
    qual_user = f"{locator}.{SF_USER.upper()}"
    now       = int(time.time())
    payload   = {
        "iss": f"{qual_user}.{fingerprint(pk)}",
        "sub": qual_user,
        "iat": now,
        "exp": now + 3600,
    }
    return jwt.encode(payload, pk, algorithm="RS256")

# ─── Request body builders ───────────────────────────────────────────────────

# Full inline spec lifted from DESC AGENT (2026-05-23). Field NAMES match Snowflake's
# REST schema: `models.orchestration` (not `model`), `instructions.response/orchestration`
# (not `response_instruction`), tools wrapped in `tool_spec`, tool_resources keyed by name.
VOC_AGENT_SPEC = {
    "models": {"orchestration": "claude-opus-4-6"},
    "instructions": {
        "response": (
            "You are a helpful analytics assistant for Tampa Bay Rays operations. "
            "Every response MUST include supporting data metrics: total response count, "
            "percentage breakdown, date range analyzed, and segment sizes when comparing groups. "
            "Format numbers with 2 decimal places for currency and percentages. "
            "Use clear, business-friendly language. When showing satisfaction scores, mention "
            "the 0-10 scale. Highlight actionable insights when relevant. If showing spending "
            "data, always clarify if it is per-person or total."
        ),
        "orchestration": (
            "DEFAULT TOOL: voc_analyst (Cortex Analyst). PRIMARY tool — use for the vast "
            "majority of questions. The survey data contains hundreds of structured columns "
            "with pre-calculated satisfaction ratings (0-10 scales), NPS scores, spending, "
            "attendance, and multiple-choice responses.\n\n"
            "ONLY use voc_feedback_search (Cortex Search) when the user EXPLICITLY asks "
            "about open-text feedback using phrases like 'what did fans say about...', "
            "'fan comments', 'qualitative feedback', 'verbatim responses', 'in their own words'. "
            "If the user does NOT use such language, DO NOT use voc_feedback_search.\n\n"
            "Default to all available seasons (2023 onward) unless user specifies otherwise."
        ),
    },
    "tools": [
        {
            "tool_spec": {
                "type": "cortex_analyst_text_to_sql",
                "name": "voc_analyst",
                "description": (
                    "PRIMARY TOOL. Semantic model for Voice of Customer post-attendance "
                    "survey data with 400+ structured columns including satisfaction ratings "
                    "(0-10 scales), NPS, spending, attendance patterns, demographics. "
                    "Use for ALL quantitative analysis and as the default tool for any question."
                ),
            }
        },
        {
            "tool_spec": {
                "type": "cortex_search",
                "name": "voc_feedback_search",
                "description": (
                    "SECONDARY TOOL — use ONLY when user explicitly asks about open-text "
                    "feedback, fan comments, written responses, qualitative feedback, or "
                    "verbatim quotes. Semantic search across fan open-text feedback."
                ),
            }
        },
    ],
    "tool_resources": {
        "voc_analyst": {
            "execution_environment": {
                "type": "warehouse",
                "warehouse": "TBRDP_DW_CORTEX_XS_WH",
            },
            "semantic_model_file": SEMANTIC_MODEL,
        },
        "voc_feedback_search": {
            "search_service": "TBRDP_DW_DEV.IM_RPT.VOC_FEEDBACK_SEARCH",
            "max_results": 10,
        },
    },
}

def inline_body(question: str) -> dict:
    """Full VOC agent spec embedded inline. Posts to /api/v2/cortex/agent:run."""
    return {
        **VOC_AGENT_SPEC,
        "messages": [
            {"role": "user", "content": [{"type": "text", "text": question}]}
        ],
    }

def stored_body(question: str) -> dict:
    """Body for a stored-agent run. The agent's tools/model/instructions come from
    the CREATE AGENT object, so the body only carries the conversation."""
    return {
        "messages": [
            {"role": "user", "content": [{"type": "text", "text": question}]}
        ],
    }

def stored_agent_url(agent_fqn: str) -> str:
    """Stored agents use a resource-path endpoint, NOT /api/v2/cortex/agent:run.
    Splits 'DB.SCHEMA.AGENT' into the path: /api/v2/databases/DB/schemas/SCHEMA/agents/AGENT:run"""
    parts = agent_fqn.split(".")
    if len(parts) != 3:
        sys.exit(f"FAIL: --agent expects DB.SCHEMA.NAME, got {agent_fqn!r}")
    db, schema, name = parts
    return (f"https://{SF_ACCOUNT}.snowflakecomputing.com"
            f"/api/v2/databases/{db}/schemas/{schema}/agents/{name}:run")

# ─── SSE streaming ───────────────────────────────────────────────────────────

def stream_response(resp):
    """Cortex Agents returns server-sent events. Parse and print each one."""
    event_count = 0
    for raw in resp.iter_lines(decode_unicode=True):
        if not raw:
            continue
        if raw.startswith("data: "):
            payload = raw[len("data: "):]
            if payload.strip() == "[DONE]":
                print("\n[stream end]")
                break
            try:
                ev = json.loads(payload)
            except json.JSONDecodeError:
                print(f"  raw: {payload[:200]}")
                continue
            event_count += 1
            etype = ev.get("type") or ev.get("event") or "unknown"
            print(f"  [{event_count:02d}] type={etype}")
            if etype in ("message_delta", "response.delta", "delta"):
                delta = ev.get("delta") or ev.get("content") or ""
                if isinstance(delta, str) and delta:
                    print(f"       text: {delta[:200]}")
            elif etype in ("tool_use", "tool_call", "response.tool_use"):
                print(f"       tool: {json.dumps(ev, default=str)[:300]}")
            elif etype in ("tool_result", "response.tool_result"):
                print(f"       result: {json.dumps(ev, default=str)[:300]}")
            else:
                print(f"       data: {json.dumps(ev, default=str)[:300]}")
        elif raw.startswith("event: "):
            print(f"  event-line: {raw}")
        else:
            print(f"  other: {raw[:200]}")
    return event_count

# ─── Main ─────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--agent", help="Fully-qualified agent name (DB.SCHEMA.AGENT). "
                                         "Omit to use inline mode.")
    parser.add_argument("--question", default=TEST_QUESTION,
                        help="Test question to send.")
    args = parser.parse_args()

    print("=" * 70)
    print("Cortex Agents REST probe — /api/v2/cortex/agent:run")
    print("=" * 70)
    print(f"Account : {SF_ACCOUNT}")
    print(f"User    : {SF_USER}")
    print(f"Role    : {SF_ROLE}")
    print(f"Mode    : {'NAMED (' + args.agent + ')' if args.agent else 'INLINE'}")
    print(f"Question: {args.question!r}")

    pk    = load_key()
    token = make_jwt(pk)
    print(f"\n[OK] JWT generated ({len(token)} chars).")

    if args.agent:
        url  = stored_agent_url(args.agent)
        body = stored_body(args.question)
    else:
        url  = f"https://{SF_ACCOUNT}.snowflakecomputing.com/api/v2/cortex/agent:run"
        body = inline_body(args.question)

    headers = {
        "Authorization": f"Bearer {token}",
        "X-Snowflake-Authorization-Token-Type": "KEYPAIR_JWT",
        "Content-Type": "application/json",
        "Accept": "text/event-stream",
    }

    print(f"\n[..] POST {url}")
    print(f"     body keys: {list(body.keys())}")

    try:
        resp = requests.post(url, headers=headers, json=body, stream=True, timeout=90)
    except requests.RequestException as e:
        sys.exit(f"FAIL: network error reaching Cortex Agents endpoint: {e}")

    print(f"[..] HTTP {resp.status_code}")

    if resp.status_code == 404:
        print("\nFAIL: 404 — Cortex Agents REST endpoint not enabled on this account, "
              "or the URL has changed. This is the main thing to check with Snowflake support.")
        print(f"\nResponse body: {resp.text[:1500]}")
        sys.exit(2)

    if resp.status_code == 403:
        print("\nFAIL: 403 — service account doesn't have access. "
              "Check that GRANT USAGE ON AGENT (step 3) ran, and that the role has "
              "DATABASE ROLE SNOWFLAKE.CORTEX_USER.")
        print(f"\nResponse body: {resp.text[:1500]}")
        sys.exit(3)

    if resp.status_code != 200:
        print(f"\nFAIL: non-200 response.\n{resp.text[:1500]}")
        sys.exit(4)

    print("[OK] Endpoint responded 200, streaming events:\n")
    n = stream_response(resp)
    print(f"\n[OK] Received {n} stream events.")
    print("\n" + "=" * 70)
    print("PASS — Cortex Agents REST endpoint is reachable. Option 1 is feasible.")
    print("=" * 70)

if __name__ == "__main__":
    main()
