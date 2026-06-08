"""
Tier 1 — Snowflake credential smoke test.

Loads snowflake_voc_agent.p8, generates a JWT, and calls the Cortex Analyst
REST API. If this passes, the Azure Function will almost certainly work
since it uses the exact same JWT mechanic.

Usage:
    python tier1_smoke.py
"""

from __future__ import annotations

import base64
import hashlib
import json
import sys
import time
from pathlib import Path

import jwt                                       # pip install pyjwt
import requests                                  # pip install requests
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.serialization import load_pem_private_key

# ─── Config (mirrors what IT put in Azure App Settings) ─────────────────────
SF_ACCOUNT   = "hta92307.east-us-2.azure"
SF_USER      = "VOC_AGENT_SVC"
SF_ROLE      = "TBRDP_DW_PROD_CORTEX_USER"
SF_WAREHOUSE = "TBRDP_DW_CORTEX_XS_WH"
SF_DATABASE  = "TBRDP_DW_DEV"
SF_SCHEMA    = "IM_RPT"

KEY_PATH       = Path(__file__).resolve().parent.parent / "snowflake_voc_agent.p8"
SEMANTIC_MODEL = "@TBRDP_DW_PROD.LOAD.CORTEX_SEMANTIC_MODELS/voc_semantic_model.yaml"
TEST_QUESTION  = "What was the average overall satisfaction last homestand?"


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


def call_analyst(token: str, question: str):
    url = f"https://{SF_ACCOUNT}.snowflakecomputing.com/api/v2/cortex/analyst/message"
    return requests.post(
        url,
        headers={
            "Authorization": f"Bearer {token}",
            "X-Snowflake-Authorization-Token-Type": "KEYPAIR_JWT",
            "Content-Type": "application/json",
            "Accept": "application/json",
        },
        json={
            "messages": [
                {"role": "user", "content": [{"type": "text", "text": question}]}
            ],
            "semantic_model_file": SEMANTIC_MODEL,
        },
        timeout=60,
    )


def main():
    print("=" * 70)
    print("Tier 1 smoke test — Snowflake Cortex Analyst credential check")
    print("=" * 70)
    print(f"Account : {SF_ACCOUNT}")
    print(f"User    : {SF_USER}")
    print(f"Role    : {SF_ROLE}")
    print(f"Key file: {KEY_PATH}")

    pk = load_key()
    fp = fingerprint(pk)
    print(f"\n[OK] Loaded private key. Public-key fingerprint: {fp}")

    token = make_jwt(pk)
    print(f"[OK] Generated JWT (length {len(token)} chars).")

    print(f"\n[..] POST Cortex Analyst with question:")
    print(f"     {TEST_QUESTION!r}")
    resp = call_analyst(token, TEST_QUESTION)
    print(f"[..] HTTP {resp.status_code}")

    if resp.status_code != 200:
        print(f"\nFAIL: Cortex Analyst returned non-200:\n{resp.text[:1500]}")
        sys.exit(2)

    data = resp.json()
    print(f"[OK] Cortex Analyst responded.")

    for block in data.get("message", {}).get("content", []):
        t = block.get("type")
        if t == "text":
            print("\n--- TEXT ---")
            print(block.get("text", "")[:800])
        elif t == "sql":
            print("\n--- SQL (generated) ---")
            print(block.get("statement", "")[:800])
        elif t == "suggestions":
            print("\n--- SUGGESTIONS ---")
            for s in block.get("suggestions", []):
                print(f"  - {s}")

    warnings = data.get("warnings", [])
    if warnings:
        print("\n--- WARNINGS ---")
        for w in warnings:
            print(f"  ! {w.get('message', '')}")

    print("\n" + "=" * 70)
    print("PASS — Tier 1 successful. JWT auth + Cortex Analyst access are working.")
    print("=" * 70)


if __name__ == "__main__":
    main()
