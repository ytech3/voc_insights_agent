"""
Append new 4/12 NYY briefings to the master file, using the Qualtrics
source-of-truth for accurate FINANCIAL_ID, ORDER_ID, TICKET_ID (with pv_30_ prefix).
"""
import csv
import sys
from pathlib import Path

import pandas as pd

MASTER_PATH = Path(r"C:\Users\ytaketani\Downloads\Homestand_1_CRM_SalesBriefing_UPDATED (1).csv")
LOCAL_BRIEFING = Path(r"C:\Users\ytaketani\voc_insights_agent\game_report\Homestand_1_CRM_SalesBriefing.csv")
SOT_PATH = Path(r"C:\Users\ytaketani\voc_insights_agent\game_report\2026 SGT Post-Attendance Survey (MLB-VOC)_April 14, 2026_10.26.csv")

# ── Read master ──
master = pd.read_csv(MASTER_PATH, dtype=str, encoding="utf-8", encoding_errors="replace")
master_fids = set(master["FINANCIAL_ID"].astype(str))
print(f"Master: {len(master)} rows")

# ── Read local briefings (the 209 new Apr 12 rows) ──
local = pd.read_csv(LOCAL_BRIEFING, dtype=str, encoding="utf-8", encoding_errors="replace")
apr12 = local[local["SALES_BRIEFING"].str.contains("Apr 12", na=False)].copy()
print(f"New Apr 12 briefings: {len(apr12)}")

# ── Read source of truth (skip Qualtrics question-text + ImportId rows) ──
sot = pd.read_csv(SOT_PATH, dtype=str, encoding="utf-8", encoding_errors="replace", skiprows=[1, 2])
print(f"Source of truth: {len(sot)} rows")

# Build SOT lookup: stripped financial_id -> (financial_id, order_id, ticket_id)
def strip_prefix(val):
    if pd.isna(val):
        return val
    return str(val).replace("pv_30_", "", 1)

sot["_fid_clean"] = sot["financial_id"].map(strip_prefix)
sot["_tid_clean"] = sot["ticket_id"].map(strip_prefix)
# Build lookup keyed on (financial_id_clean, ticket_id_clean)
sot_lookup = {}
for _, r in sot.iterrows():
    key = (str(r["_fid_clean"]), str(r["_tid_clean"]))
    sot_lookup[key] = {
        "financial_id": r["financial_id"],
        "order_id": r["order_id"],
        "ticket_id": r["ticket_id"],
    }

# ── Map correct IDs onto the new rows ──
matched = 0
unmatched = []
for idx in apr12.index:
    fid_clean = str(apr12.at[idx, "FINANCIAL_ID"])
    tid_clean = str(apr12.at[idx, "TICKET_ID"])
    key = (fid_clean, tid_clean)
    if key in sot_lookup:
        apr12.at[idx, "FINANCIAL_ID"] = sot_lookup[key]["financial_id"]
        apr12.at[idx, "ORDER_ID"] = sot_lookup[key]["order_id"]
        apr12.at[idx, "TICKET_ID"] = sot_lookup[key]["ticket_id"]
        matched += 1
    else:
        # Fallback: match on financial_id only (take first match)
        fid_only = {k: v for k, v in sot_lookup.items() if k[0] == fid_clean}
        if fid_only:
            first_match = next(iter(fid_only.values()))
            apr12.at[idx, "FINANCIAL_ID"] = first_match["financial_id"]
            apr12.at[idx, "ORDER_ID"] = first_match["order_id"]
            apr12.at[idx, "TICKET_ID"] = first_match["ticket_id"]
            matched += 1
        else:
            # Last resort: add pv_30_ prefix to existing values
            apr12.at[idx, "FINANCIAL_ID"] = f"pv_30_{fid_clean}"
            apr12.at[idx, "ORDER_ID"] = f"pv_30_{apr12.at[idx, 'ORDER_ID']}"
            apr12.at[idx, "TICKET_ID"] = f"pv_30_{tid_clean}"
            unmatched.append((fid_clean, apr12.at[idx, "FIRST_NAME"], apr12.at[idx, "LAST_NAME"]))

print(f"ID match from SOT: {matched}/{len(apr12)}")
if unmatched:
    print(f"Unmatched: {unmatched[:10]}")

# ── Filter out any that are somehow already in master ──
apr12_new = apr12[~apr12["FINANCIAL_ID"].isin(master_fids)]
print(f"After dedup vs master: {len(apr12_new)} to append")

# ── Ensure column order matches master ──
output_cols = list(master.columns)
for col in output_cols:
    if col not in apr12_new.columns:
        apr12_new[col] = ""
append_df = apr12_new[output_cols].copy()

# ── Append and write ──
combined = pd.concat([master, append_df], ignore_index=True)
combined.to_csv(MASTER_PATH, index=False, quoting=csv.QUOTE_MINIMAL, encoding="utf-8")

print(f"Appended {len(append_df)} rows -> master now {len(combined)} rows")
print(f"Wrote {MASTER_PATH}")

# Spot check
for i in range(min(3, len(append_df))):
    row = append_df.iloc[i]
    print(f"\n  {row['FIRST_NAME']} {row['LAST_NAME']} | FID={row['FINANCIAL_ID']} | OID={row['ORDER_ID']} | TID={row['TICKET_ID']}")
