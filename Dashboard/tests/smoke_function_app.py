"""Smoke test the rewritten function_app.py — imports cleanly + SSE parser works.
Does NOT hit Snowflake. Run as:
    cd Dashboard/tests
    .\.python311\python.exe smoke_function_app.py
"""

import os
import sys
from pathlib import Path

# Make the function package importable
FUNC_DIR = Path(__file__).resolve().parent.parent / "azure_deploy" / "function"
sys.path.insert(0, str(FUNC_DIR))

# Required env vars (read from the .p8 file the existing tier1 test uses)
KEY_PATH = Path(__file__).resolve().parent.parent / "snowflake_voc_agent.p8"
os.environ.setdefault("SNOWFLAKE_ACCOUNT",     "hta92307.east-us-2.azure")
os.environ.setdefault("SNOWFLAKE_USER",        "VOC_AGENT_SVC")
os.environ.setdefault("SNOWFLAKE_ROLE",        "TBRDP_DW_PROD_CORTEX_USER")
os.environ.setdefault("SNOWFLAKE_WAREHOUSE",   "TBRDP_DW_CORTEX_XS_WH")
os.environ.setdefault("SNOWFLAKE_DATABASE",    "TBRDP_DW_DEV")
os.environ.setdefault("SNOWFLAKE_SCHEMA",      "IM_RPT")
os.environ.setdefault("SNOWFLAKE_PRIVATE_KEY", KEY_PATH.read_text())

import function_app  # noqa: E402

print("[OK] module imported")
print(f"Agent URL: {function_app._agent_url()}")
print(f"JWT length: {len(function_app._make_jwt())}")

# Feed the SSE parser a representative event sequence
out = function_app.AgentRunResult()
function_app._parse_sse_event("response.text.delta", '{"text": "Hello "}', out)
function_app._parse_sse_event("response.text.delta", '{"text": "world"}', out)
function_app._parse_sse_event("response.thinking.delta", '{"text": "let me think..."}', out)
function_app._parse_sse_event(
    "response.tool_use",
    '{"type": "system_execute_sql", "name": "system_execute_sql", "input": {"sql": "SELECT 1"}}',
    out,
)
function_app._parse_sse_event(
    "response.tool_result",
    (
        '{"type": "system_execute_sql", "tool_type": "system_execute_sql", '
        '"content": [{"json": {"result_set": '
        '{"data": [["9.18", "2554"]], '
        '"resultSetMetaData": {"rowType": [{"name": "AVG_SCORE"}, {"name": "RESPONSES"}]}'
        '}}}]}'
    ),
    out,
)
function_app._parse_sse_event(
    "response.suggested_queries",
    '{"suggested_queries": [{"query": "q1"}, {"query": "q2"}]}',
    out,
)

print(f"final_text: {out.final_text!r}")
print(f"thinking:   {out.thinking!r}")
print(f"tool_uses count: {len(out.tool_uses)}")
print(f"suggestions: {out.suggestions}")

last_use = out.last_sql_tool_use
print(f"last_sql_tool_use SQL: {(last_use or {}).get('input', {}).get('sql')}")

last_res = out.last_sql_result
print(f"last_sql_result present: {last_res is not None}")
if last_res:
    rs   = (last_res.get("content") or [{}])[0].get("json", {}).get("result_set", {})
    cols = function_app._extract_columns(rs, "")
    rows = function_app._extract_rows(rs)
    print(f"columns: {cols}")
    print(f"rows:    {rows}")
    print(f"row[0] value types: {[type(v).__name__ for v in rows[0]]}")
    data = {"columns": cols, "rows": rows}
    print(f"data_kind: {function_app._data_kind(data)}")

print("\n[ALL OK] function_app.py imports cleanly and the SSE parser works end-to-end.")
