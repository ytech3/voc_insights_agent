"""
Append new 4/12 NYY fans to Homestand_1_CRM_SalesBriefing.csv.
Reuses the briefing logic from build_sales_briefing.py.

Handles data-quality issues in the new export where some fields
contain undecoded numeric survey codes (82, 84, 85, 87, 88, 89).
"""
import csv
import re
import sys
from pathlib import Path

import pandas as pd

sys.path.insert(0, str(Path(__file__).parent))
from build_sales_briefing import build_briefing

BRIEFING_PATH = Path(__file__).parent / "Homestand_1_CRM_SalesBriefing.csv"
NEW_DATA_PATH = Path(r"C:\Users\ytaketani\Downloads\Untitled 88_2026-04-14-1013.csv")

# Known numeric codes that appear in place of text values
NUMERIC_CODES = {"81", "82", "83", "84", "85", "86", "87", "88", "89"}


def strip_prefix(val):
    if pd.isna(val):
        return val
    return str(val).replace("pv_30_", "", 1)


def clean_numeric_code(val):
    """Return None if value is a known numeric survey code."""
    if pd.isna(val):
        return val
    s = str(val).strip()
    if s in NUMERIC_CODES:
        return ""
    return s


def clean_team_interest(val):
    """Remove numeric codes from comma-separated team interest list."""
    if pd.isna(val):
        return val
    parts = [p.strip() for p in str(val).split(",")]
    cleaned = [p for p in parts if p and p not in NUMERIC_CODES]
    return ", ".join(cleaned) if cleaned else ""


# ── Read existing briefing (only keep the original rows, not prior appended) ──
existing = pd.read_csv(BRIEFING_PATH, dtype=str, encoding="utf-8", encoding_errors="replace")

# Check if prior run already appended Apr 12 rows -- if so, remove them
apr12_mask = existing["SALES_BRIEFING"].str.contains("Apr 12", na=False)
if apr12_mask.any():
    print(f"Removing {apr12_mask.sum()} previously appended Apr 12 rows")
    existing = existing[~apr12_mask].copy()

existing_fids = set(existing["FINANCIAL_ID"].astype(str))
print(f"Existing briefing (base): {len(existing)} rows")

# ── Read new data ──
new = pd.read_csv(NEW_DATA_PATH, dtype=str, encoding="utf-8", encoding_errors="replace")
print(f"New data file: {len(new)} rows")

# ── Clean data-quality issues ──
# Use FAVORITE_TEAM_CLEAN instead of TEAM_FAVORITE (new export has numeric codes)
if "FAVORITE_TEAM_CLEAN" in new.columns:
    new["TEAM_FAVORITE"] = new["FAVORITE_TEAM_CLEAN"]

# Clean numeric codes from specific fields
new["TEAM_INTEREST"] = new["TEAM_INTEREST"].map(clean_team_interest)
new["MERCH_NUMRAT"] = new["MERCH_NUMRAT"].map(clean_numeric_code)
new["MERCH_NO_DESC"] = new["MERCH_NO_DESC"].map(clean_numeric_code)

# Normalize FINANCIAL_ID for comparison
new["_FID_CLEAN"] = new["FINANCIAL_ID"].map(strip_prefix)

# Filter: only 4/12 NYY fans not already in briefing
mask_game = new["GAME_SHORTHAND"].str.contains("Apr 12", na=False)
mask_new = ~new["_FID_CLEAN"].isin(existing_fids)
to_add = new[mask_game & mask_new].copy()
print(f"Fans from 4/12 NYY game not in existing briefing: {len(to_add)}")

if len(to_add) == 0:
    print("Nothing to append.")
    sys.exit(0)

# ── Build briefings ──
to_add["SALES_BRIEFING"] = to_add.apply(build_briefing, axis=1)

# Fix em-dash encoding: replace unicode em-dash with ASCII --
to_add["SALES_BRIEFING"] = to_add["SALES_BRIEFING"].str.replace("\u2014", "--", regex=False)

# ── Normalize IDs ──
for col in ["FINANCIAL_ID", "ORDER_ID", "TICKET_ID"]:
    if col in to_add.columns:
        to_add[col] = to_add[col].map(strip_prefix)

# ── Select only the columns in the existing briefing ──
output_cols = list(existing.columns)
for col in output_cols:
    if col not in to_add.columns:
        to_add[col] = ""

append_df = to_add[output_cols].copy()

# ── Append and write ──
combined = pd.concat([existing, append_df], ignore_index=True)
combined.to_csv(BRIEFING_PATH, index=False, quoting=csv.QUOTE_MINIMAL, encoding="utf-8")

print(f"Appended {len(append_df)} new rows -> total now {len(combined)} rows")
print(f"Wrote {BRIEFING_PATH}")

# Show samples
for i in range(min(3, len(append_df))):
    row = append_df.iloc[i]
    print(f"\n{'='*60}")
    print(f"{row.get('FIRST_NAME', '?')} {row.get('LAST_NAME', '?')} | {row.get('EMAIL','')}")
    print(f"{'='*60}")
    print(row["SALES_BRIEFING"][:600])
    print()
