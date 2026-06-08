"""
Generates azure_deploy/function/local.settings.json so the Function App can be
started locally via `func start`. Embeds the contents of snowflake_voc_agent.p8
as the SNOWFLAKE_PRIVATE_KEY value.

The output file is gitignored via .funcignore — do not commit it.

Usage:
    python make_local_settings.py
"""
import json
from pathlib import Path

ROOT     = Path(__file__).resolve().parent.parent
KEY_PATH = ROOT / "snowflake_voc_agent.p8"
OUT_PATH = ROOT / "azure_deploy" / "function" / "local.settings.json"

if not KEY_PATH.exists():
    raise SystemExit(f"Key not found: {KEY_PATH}")

YAML_PATH = ROOT.parent / "voc_semantic_model.yaml"  # project-root copy for local testing

settings = {
    "IsEncrypted": False,
    "Values": {
        "AzureWebJobsStorage":     "",
        "FUNCTIONS_WORKER_RUNTIME": "python",
        "SNOWFLAKE_ACCOUNT":   "hta92307.east-us-2.azure",
        "SNOWFLAKE_USER":      "VOC_AGENT_SVC",
        "SNOWFLAKE_PRIVATE_KEY": KEY_PATH.read_text(),
        "SNOWFLAKE_ROLE":      "TBRDP_DW_PROD_CORTEX_USER",
        "SNOWFLAKE_WAREHOUSE": "TBRDP_DW_CORTEX_XS_WH",
        "SNOWFLAKE_DATABASE":  "TBRDP_DW_DEV",
        "SNOWFLAKE_SCHEMA":    "IM_RPT",
        # Read semantic model from local disk instead of fetching from stage —
        # faster startup for local testing. In Azure deployment, omit this to
        # download from the stage at first /api/summary call.
        "SEMANTIC_MODEL_LOCAL_PATH": str(YAML_PATH),
    },
    "Host": {
        "LocalHttpPort":    7071,
        "CORS":             "*",
        "CORSCredentials":  False,
    },
}

OUT_PATH.write_text(json.dumps(settings, indent=2))
print(f"Wrote {OUT_PATH}")
print("WARNING: this file embeds the private key. Do not commit. (.funcignore excludes it.)")
