"""
Tier 2 — Number-formatting + new-feature unit tests.

Phase 1 (always runs): pure logic tests — no Snowflake, no Azure needed.
  - _jsonable() rounds long floats/Decimals to ≤2 decimal places
  - _summarize_sample_size() returns correct row budget by kind
  - _data_context_block() extracts SEASON and date range correctly
  - _detect_result_patterns() flags NPS and multi-season data
  - _cache_key() is stable and differs on distinct inputs

Phase 2 (--url <endpoint>): live smoke against the deployed Azure Function.
  - GET  /api/health         → {"status": "ok"}
  - POST /api/chat           → valid response with no long decimals in data
  - POST /api/summary        → non-empty summary string

Usage:
    # Unit tests only
    python tier2_format_test.py

    # Unit tests + live smoke (replace URL with your function's base URL)
    python tier2_format_test.py --url https://rays-voc-proxy.azurewebsites.net
    # or against local Function host:
    python tier2_format_test.py --url http://localhost:7071
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from decimal import Decimal
from pathlib import Path

ROOT         = Path(__file__).resolve().parent.parent
FUNCTION_DIR = ROOT / "azure_deploy" / "function"
SETTINGS     = FUNCTION_DIR / "local.settings.json"

# ─── Load env from local.settings.json before importing function_app ────────
if SETTINGS.exists():
    cfg = json.loads(SETTINGS.read_text())
    for k, v in cfg.get("Values", {}).items():
        os.environ.setdefault(k, v)

sys.path.insert(0, str(FUNCTION_DIR))

# Import only the pure helper functions (no Azure runtime needed).
from function_app import (
    _cache_key,
    _data_context_block,
    _detect_result_patterns,
    _jsonable,
    _summarize_sample_size,
)

# ─── Helpers ─────────────────────────────────────────────────────────────────

PASS = "[PASS]"
FAIL = "[FAIL]"
failures: list[str] = []


def check(label: str, condition: bool, detail: str = "") -> None:
    if condition:
        print(f"  {PASS} {label}")
    else:
        msg = f"  {FAIL} {label}" + (f" — {detail}" if detail else "")
        print(msg)
        failures.append(label)


def max_decimals(v) -> int:
    if not isinstance(v, float):
        return 0
    s = str(v)
    return len(s.split(".")[1]) if "." in s else 0


# ─── Phase 1: unit tests ─────────────────────────────────────────────────────

def test_jsonable():
    print("\n[_jsonable — number rounding]")
    # Long percentage float must be rounded to ≤2 places
    v = _jsonable(80.46758384758569)
    check("long float rounds to <=2 decimal places", max_decimals(v) <= 2, f"got {v}")
    check("long float rounds correctly (80.47)", v == 80.47, f"got {v}")

    # Long Decimal (e.g. from Snowflake NUMERIC column)
    v2 = _jsonable(Decimal("42.987654321"))
    check("Decimal rounds to <=2 decimal places", max_decimals(v2) <= 2, f"got {v2}")

    # Integers must pass through untouched
    check("int passthrough", _jsonable(42) == 42)
    check("zero passthrough", _jsonable(0) == 0)

    # None / bool / str passthrough
    check("None passthrough", _jsonable(None) is None)
    check("bool True passthrough", _jsonable(True) is True)
    check("str passthrough", _jsonable("hello") == "hello")

    # Clean floats (already ≤2 places) must not be corrupted
    check("3.47 unchanged", _jsonable(3.47) == 3.47)
    check("1.0 unchanged", _jsonable(1.0) == 1.0)


def test_summarize_sample_size():
    print("\n[_summarize_sample_size — dynamic row budget]")
    check("feedback 5 rows = 5",   _summarize_sample_size("feedback", 5)   == 5)
    check("feedback 20 rows = 20", _summarize_sample_size("feedback", 20)  == 20)
    check("feedback 100 rows = 20",_summarize_sample_size("feedback", 100) == 20)
    check("chart 8 rows = 8",      _summarize_sample_size("chart", 8)      == 8)
    check("chart 20 rows = 15",    _summarize_sample_size("chart", 20)     == 15)
    check("metric 3 rows = 3",     _summarize_sample_size("metric", 3)     == 3)
    check("metric 50 rows = 15",   _summarize_sample_size("metric", 50)    == 15)


def test_data_context_block():
    print("\n[_data_context_block — season / date extraction]")

    # Single season
    data = {"columns": ["SEASON", "AVG_SAT"], "rows": [[2026, 3.2], [2026, 3.4]]}
    block = _data_context_block(data)
    check("single season present", "Season: 2026" in block, repr(block))
    check("no date when absent", "Date" not in block, repr(block))

    # Multi-season
    data2 = {"columns": ["SEASON", "AVG_SAT"], "rows": [[2024, 3.1], [2026, 3.2]]}
    block2 = _data_context_block(data2)
    check("multi-season label", "Seasons covered:" in block2, repr(block2))
    check("both seasons listed", "2024" in block2 and "2026" in block2, repr(block2))

    # Date range
    data3 = {
        "columns": ["GAME_DATE", "SCORE"],
        "rows": [["2026-04-04", 3.1], ["2026-04-08", 3.3], ["2026-04-12", 3.2]],
    }
    block3 = _data_context_block(data3)
    check("date range label", "Date range:" in block3, repr(block3))
    check("start date", "2026-04-04" in block3, repr(block3))
    check("end date", "2026-04-12" in block3, repr(block3))

    # No time columns → empty string
    data4 = {"columns": ["CATEGORY", "COUNT"], "rows": [["A", 10]]}
    check("no context when no time cols", _data_context_block(data4) == "", "non-empty")

    # Empty data → empty string
    check("empty data → empty", _data_context_block({}) == "")


def test_detect_result_patterns():
    print("\n[_detect_result_patterns — NPS + multi-season hints]")

    # NPS column present
    nps_data = {"columns": ["NPS_SCORE", "COUNT"], "rows": [[9, 120], [7, 80]]}
    hints = _detect_result_patterns(nps_data, "SELECT NPS_SCORE FROM ...")
    nps_hit = any("Promoter" in h for h in hints)
    check("NPS_SCORE triggers NPS hint", nps_hit, str(hints))

    nps_data2 = {"columns": ["NPS_SEGMENT", "PCT"], "rows": [["Promoter", 60]]}
    hints2 = _detect_result_patterns(nps_data2, "")
    check("NPS_SEGMENT triggers NPS hint", any("Promoter" in h for h in hints2))

    # No NPS columns → no NPS hint
    plain = {"columns": ["GAME_DATE", "OVERALL_NUMRAT"], "rows": [["2026-04-04", 3.2]]}
    check("no NPS cols → no NPS hint", not any("Promoter" in h for h in _detect_result_patterns(plain, "")))

    # Multi-season
    ms_data = {"columns": ["SEASON", "AVG"], "rows": [[2024, 3.1], [2026, 3.3]]}
    hints3 = _detect_result_patterns(ms_data, "")
    check("multi-season hint present", any("season" in h.lower() for h in hints3), str(hints3))

    # Single season → no multi-season hint
    ss_data = {"columns": ["SEASON", "AVG"], "rows": [[2026, 3.3], [2026, 3.1]]}
    hints4 = _detect_result_patterns(ss_data, "")
    check("single season → no multi-season hint", not any("season" in h.lower() for h in hints4), str(hints4))


def test_cache_key():
    print("\n[_cache_key — stability and isolation]")
    k1 = _cache_key("What was overall satisfaction?", [])
    k2 = _cache_key("What was overall satisfaction?", [])
    check("same question → same key", k1 == k2)

    k3 = _cache_key("  What  was  overall  satisfaction?  ", [])
    check("normalised whitespace → same key", k1 == k3)

    k4 = _cache_key("What was overall satisfaction?", [])
    k5 = _cache_key("What was NPS last homestand?", [])
    check("different questions → different keys", k4 != k5)

    history = [{"role": "user", "content": [{"type": "text", "text": "prior q"}]}]
    k6 = _cache_key("What was overall satisfaction?", history)
    check("different history → different key", k1 != k6)


# ─── Phase 2: live endpoint smoke ────────────────────────────────────────────

def test_live(base_url: str):
    try:
        import requests
    except ImportError:
        print("\n[SKIP] 'requests' not installed — skipping live tests.")
        return

    base_url = base_url.rstrip("/")
    print(f"\n[Live smoke — {base_url}]")

    # Health
    try:
        r = requests.get(f"{base_url}/api/health", timeout=15)
        check("GET /api/health → 200", r.status_code == 200, f"HTTP {r.status_code}")
        body = r.json()
        check("health body has status=ok", body.get("status") == "ok", str(body))
    except Exception as e:
        check("GET /api/health reachable", False, str(e))
        print("  (skipping further live tests — health failed)")
        return

    # Chat — percentage question
    question = "What percentage of fans gave each satisfaction rating for overall experience in 2026?"
    try:
        r2 = requests.post(
            f"{base_url}/api/chat",
            json={"question": question, "history": []},
            timeout=60,
        )
        check("POST /api/chat → 200", r2.status_code == 200, f"HTTP {r2.status_code}")
        chat_body = r2.json()
        check("chat body has type=analyst", chat_body.get("type") == "analyst", str(list(chat_body.keys())))

        # Verify no long decimals in the returned data rows
        data = chat_body.get("data") or {}
        rows = data.get("rows") or []
        long_decimal_found = False
        bad_value = None
        for row in rows:
            for cell in (row or []):
                if isinstance(cell, float) and max_decimals(cell) > 2:
                    long_decimal_found = True
                    bad_value = cell
                    break
        check("no long decimals in data rows", not long_decimal_found,
              f"found {bad_value} — rounding not applied")

        sql_failed = chat_body.get("sql_failed", False)
        if sql_failed:
            print("  [WARN] sql_failed=True — data may be empty; rounding check was vacuous")

    except Exception as e:
        check("POST /api/chat succeeded", False, str(e))
        return

    # Summary
    if chat_body.get("data") and not chat_body.get("sql_failed"):
        try:
            r3 = requests.post(
                f"{base_url}/api/summary",
                json={
                    "question":       question,
                    "interpretation": chat_body.get("interpretation", ""),
                    "data":           chat_body.get("data"),
                    "data_kind":      chat_body.get("data_kind", "metric"),
                    "sql":            chat_body.get("sql", ""),
                },
                timeout=30,
            )
            check("POST /api/summary → 200", r3.status_code == 200, f"HTTP {r3.status_code}")
            summary_text = r3.json().get("summary", "")
            check("summary is non-empty", bool(summary_text), "empty string returned")
            if summary_text:
                print(f"  [INFO] Summary preview: {summary_text[:200]}")
        except Exception as e:
            check("POST /api/summary succeeded", False, str(e))


# ─── Entry point ─────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(description="VOC Agent format + smoke tests")
    parser.add_argument("--url", metavar="BASE_URL",
                        help="Base URL of the Azure Function (e.g. https://rays-voc-proxy.azurewebsites.net)")
    args = parser.parse_args()

    print("=" * 70)
    print("Tier 2 — Number formatting + feature unit tests")
    print("=" * 70)

    test_jsonable()
    test_summarize_sample_size()
    test_data_context_block()
    test_detect_result_patterns()
    test_cache_key()

    if args.url:
        test_live(args.url)

    print("\n" + "=" * 70)
    if failures:
        print(f"FAIL — {len(failures)} test(s) failed: {', '.join(failures)}")
        sys.exit(1)
    else:
        live_note = f" + live smoke at {args.url}" if args.url else " (unit only)"
        print(f"PASS — all tests passed{live_note}")
    print("=" * 70)


if __name__ == "__main__":
    main()
