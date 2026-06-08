"""Add EMAIL column to Homestand_1_CRM_SalesBriefing.csv by matching on FINANCIAL_ID from Homestand_1_CRM.csv."""
import pandas as pd
from pathlib import Path

here = Path(__file__).parent
briefing_path = here / "Homestand_1_CRM_SalesBriefing.csv"
crm_path = here / "Homestand_1_CRM.csv"

briefing = pd.read_csv(briefing_path, dtype=str, encoding="utf-8", encoding_errors="replace")
crm = pd.read_csv(crm_path, dtype=str, encoding="utf-8", encoding_errors="replace")

print(f"Briefing rows: {len(briefing)}")
print(f"CRM rows: {len(crm)}")

# Build lookup: FINANCIAL_ID -> EMAIL. CRM uses a "pv_30_" prefix; briefing uses the bare numeric id.
def normalize(fid):
    if pd.isna(fid):
        return fid
    return str(fid).replace("pv_30_", "", 1)

crm["_FID"] = crm["FINANCIAL_ID"].map(normalize)
email_lookup = dict(zip(crm["_FID"], crm["EMAIL"]))

briefing["EMAIL"] = briefing["FINANCIAL_ID"].map(normalize).map(email_lookup)

matched = briefing["EMAIL"].notna().sum()
print(f"Matched emails: {matched} / {len(briefing)}")

# Reorder so EMAIL sits near the name/id columns (after LAST_NAME)
cols = list(briefing.columns)
cols.remove("EMAIL")
insert_at = cols.index("LAST_NAME") + 1
cols.insert(insert_at, "EMAIL")
briefing = briefing[cols]

briefing.to_csv(briefing_path, index=False, encoding="utf-8")
print(f"Wrote {briefing_path}")
