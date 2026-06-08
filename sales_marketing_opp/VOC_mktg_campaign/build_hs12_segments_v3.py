"""
HS12 high-satisfaction marketing segmentation — v3 (4 buckets).

Audience:  OVERALL_NUMRAT in (8,9,10) AND TB_ADDON_6 != 1
Output:    HS12_marketing_segments_v3.xlsx — 4 tabs + summary

Priority (first match wins → mutually exclusive):
  1. Families (kids)         — HS_KIDS or NON_HS_KIDS = 1
  2. Multi-Gen Reunion       — ADULT_KIDS or OTHERFAM (no kids)
  3. Couples                 — SPOUSE (no kids, no adult-fam)
  4. Social / Crew           — catch-all (friends/business/alone/other/unknown)
"""

import pandas as pd

SRC = r"C:/Users/ytaketani/Downloads/HS12.csv"
OUT = r"C:/Users/ytaketani/voc_insights_agent/HS12_marketing_segments_v3.xlsx"

df = pd.read_csv(SRC, low_memory=False)
aud = df[(df["OVERALL_NUMRAT"].isin([8, 9, 10])) & (df["TB_ADDON_6"] != 1)].copy()

def is1(col):
    return pd.to_numeric(aud[col], errors="coerce") == 1

aud["AGE_NUM"] = pd.to_numeric(aud["AGE"], errors="coerce")

has_kid    = is1("ATTEND_WITH_CATEGORY_HS_KIDS") | is1("ATTEND_WITH_CATEGORY_NON_HS_KIDS")
has_adult_relative = is1("ATTEND_WITH_CATEGORY_ADULT_KIDS") | is1("ATTEND_WITH_CATEGORY_OTHERFAM")
has_spouse = is1("ATTEND_WITH_CATEGORY_SPOUSE")

aud["SEGMENT"] = "Unassigned"
aud.loc[has_kid, "SEGMENT"] = "1. Families (kids)"
aud.loc[(aud["SEGMENT"] == "Unassigned") & has_adult_relative, "SEGMENT"] = "2. Multi-Gen Reunion"
aud.loc[(aud["SEGMENT"] == "Unassigned") & has_spouse, "SEGMENT"] = "3. Couples"
aud.loc[aud["SEGMENT"] == "Unassigned", "SEGMENT"] = "4. Social / Crew"

assert (aud["SEGMENT"] != "Unassigned").all(), "Some fans unassigned"

food_tags = ["ALCOHOL","NONALCOHOL","HOTDOG","PRETZELS","POPCORN","NUTS",
             "FRIES","CHICKEN","ICECREAM","PIZZA","NACHOS","BURGERS","SANDWICH","SAUSAGE"]
for t in food_tags:
    aud[f"BOUGHT_{t.title()}"] = (pd.to_numeric(aud[f"CONCESS_TYPE_{t}"], errors="coerce") == 1).astype(int)

aud["TOP_FOODS"] = aud[[f"BOUGHT_{t.title()}" for t in food_tags]].apply(
    lambda r: ", ".join([col.replace("BOUGHT_", "") for col, v in r.items() if v == 1]), axis=1)

export_cols = [
    "SEGMENT",
    "ATTENDING_ID","EMAIL","FIRST_NAME","LAST_NAME","CITY","STATE",
    "AGE_NUM","GENDER_ID_DESC","HHI_ID_DESC",
    "OVERALL_NUMRAT","TEAM_AVIDITY_DESC","TEAM_FAVORITE","PREVIOUS_PURCHASE_DESC",
    "ATTEND_WITH_CATEGORY_SPOUSE","ATTEND_WITH_CATEGORY_ADULT_KIDS",
    "ATTEND_WITH_CATEGORY_HS_KIDS","ATTEND_WITH_CATEGORY_NON_HS_KIDS",
    "ATTEND_WITH_CATEGORY_OTHERFAM","ATTEND_WITH_CATEGORY_FRIENDS",
    "ATTEND_WITH_CATEGORY_BUSINESS","ATTEND_WITH_CATEGORY_ALONE",
    "ATTEND_WITH_CATEGORY_OTHER",
    "TOP_FOODS",
] + [f"BOUGHT_{t.title()}" for t in food_tags]

export_cols = [c for c in export_cols if c in aud.columns]
out_df = aud[export_cols].rename(columns={"AGE_NUM": "AGE"})

summary = (
    out_df.groupby("SEGMENT")
          .agg(
              fans=("EMAIL", "size"),
              with_email=("EMAIL", lambda s: s.notna().sum()),
              median_age=("AGE", "median"),
              pct_55_plus=("AGE", lambda s: round((s >= 55).mean() * 100, 1)),
              pct_rated_9_10=("OVERALL_NUMRAT", lambda s: round((s >= 9).mean() * 100, 1)),
              pct_prior_buyer=("PREVIOUS_PURCHASE_DESC", lambda s: round((s == "Yes").mean() * 100, 1)),
              pct_passionate=("TEAM_AVIDITY_DESC", lambda s: round((s == "5 (passionate fan)").mean() * 100, 1)),
          )
          .reset_index()
          .sort_values("SEGMENT")
)
summary.loc[len(summary)] = [
    "TOTAL",
    len(out_df),
    out_df["EMAIL"].notna().sum(),
    out_df["AGE"].median(),
    round((out_df["AGE"] >= 55).mean() * 100, 1),
    round((out_df["OVERALL_NUMRAT"] >= 9).mean() * 100, 1),
    round((out_df["PREVIOUS_PURCHASE_DESC"] == "Yes").mean() * 100, 1),
    round((out_df["TEAM_AVIDITY_DESC"] == "5 (passionate fan)").mean() * 100, 1),
]

print("=== Segment sizes ===")
print(summary.to_string(index=False))

with pd.ExcelWriter(OUT, engine="openpyxl") as xw:
    summary.to_excel(xw, sheet_name="Summary", index=False)
    for seg, sub in out_df.groupby("SEGMENT"):
        sheet = seg.split(".", 1)[0].strip() + " - " + seg.split(".", 1)[1].strip()
        for ch in r'/\?*[]:':
            sheet = sheet.replace(ch, "-")
        sheet = sheet[:31]
        sub.sort_values("ATTENDING_ID").to_excel(xw, sheet_name=sheet, index=False)

print(f"\nWrote: {OUT}")
print(f"Total fans: {len(out_df)}  ·  with email: {out_df['EMAIL'].notna().sum()}")
