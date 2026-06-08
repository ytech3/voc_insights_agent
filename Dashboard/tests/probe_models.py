"""Probe which Cortex Complete models are available in this Snowflake account."""

import json, sys, time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "azure_deploy" / "function"))

# Load env from local.settings.json
import os
settings = json.loads((ROOT / "azure_deploy" / "function" / "local.settings.json").read_text())
for k, v in settings["Values"].items():
    os.environ.setdefault(k, v)

import function_app as fa

CANDIDATES = [
    "claude-3-5-sonnet",
    "claude-3-5-sonnet-v2",
    "claude-3-5-haiku",
    "claude-sonnet-4-5",
    "claude-sonnet-4",
    "claude-4-sonnet",
    "claude-haiku-4-5",
    "llama3.1-70b",
    "llama3.1-8b",
    "mixtral-8x7b",
    "mistral-large2",
    "mistral-7b",
]

with fa._connect() as conn:
    with conn.cursor() as cur:
        for m in CANDIDATES:
            t0 = time.time()
            try:
                cur.execute(
                    "SELECT SNOWFLAKE.CORTEX.COMPLETE(%s, %s)",
                    (m, "Say hi in 5 words."),
                )
                row = cur.fetchone()
                dt = time.time() - t0
                print(f"  OK  ({dt:5.2f}s)  {m:25s}  ->  {(row[0] or '').strip()[:60]}")
            except Exception as e:
                msg = str(e)
                if "unavailable" in msg or "not supported" in msg:
                    print(f"  --  unavailable      {m:25s}")
                else:
                    print(f"  ER  ({time.time()-t0:.1f}s) {m:25s}  ->  {msg[:120]}")
