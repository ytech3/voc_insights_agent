"""Build Sales Opportunity Excel for VOC May 15-20, 2026 (Homestand 3, 6 games).

Pulls data directly from Snowflake, applies cohort filters, generates
SALES_BRIEFING fan profiles, and outputs a two-sheet Excel:
  - Sheet1: All raw survey data (full columns from the view)
  - Sheet2: Key columns + SALES_BRIEFING for the filtered cohort

Cohort filters (same as May 1-6 build):
  - PURCHASE_INTENT_DESC == "Yes, I do"
  - ATTEND_NUM_PLAN_DESC in the four 5+ game buckets
  - TB_ADDON_6 != "1" (no service recovery / staff follow-up needed)
  - BUYER_TYPE not in {Full Season Ticket, Full Season Plan, Weekday Plan,
    Weekend Plan, Sunday Plan, Flexible Season Member Ticket, Premium Ticket,
    Sponsor, Employee Ticket}
  - EMAIL domain is a personal-email domain (drop corporate domains)
  - PREVIOUS_PURCHASE_DESC != "Yes"
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from build_may0106_sales_opp import (  # noqa: E402
    filter_cohort,
    build_briefing,
    get_snowflake_connection,
)
import pandas as pd  # noqa: E402

OUT = Path(r"C:\Users\ytaketani\Music\ytaketani\voc_insights_agent\sales_marketing_opp\VOC_05152026_05202026.xlsx")

DATE_FROM = "2026-05-15"
DATE_TO = "2026-05-20"


def fetch_data() -> pd.DataFrame:
    """Pull all rows from the view for the May 15-20, 2026 homestand."""
    query = f"""
    SELECT *
    FROM TBRDP_DW_PROD.IM_RPT.V_SBL_QUALTRICS_VOC_POST_ATTENDANCE_FULL_CORTEX_AI
    WHERE GAME_DATE BETWEEN '{DATE_FROM}' AND '{DATE_TO}'
    """
    print(f"Connecting to Snowflake (window {DATE_FROM} -> {DATE_TO})...")
    conn = get_snowflake_connection()
    print("Fetching data...")
    cur = conn.cursor()
    cur.execute(query)
    cols = [desc[0] for desc in cur.description]
    rows = cur.fetchall()
    cur.close()
    conn.close()
    df = pd.DataFrame(rows, columns=cols)
    print(f"  Fetched {len(df):,} rows x {len(df.columns)} columns")
    if "GAME_DATE" in df.columns and len(df):
        game_counts = df.groupby("GAME_DATE").size().sort_index()
        print("\n  Rows per game date:")
        for d, n in game_counts.items():
            print(f"    {d}: {n:,}")
        print(f"  Distinct GAMEPKs: {df['GAMEPK'].nunique() if 'GAMEPK' in df.columns else 'n/a'}")
    return df


def main() -> None:
    df_all = fetch_data()
    cohort = filter_cohort(df_all.copy()).copy()

    print("\nGenerating SALES_BRIEFING profiles...")
    cohort["SALES_BRIEFING"] = cohort.apply(build_briefing, axis=1)
    print(f"  Generated {len(cohort):,} briefings")

    sheet2_cols = [
        "FINANCIAL_ID", "ATTENDING_ID", "ATTEND_NUM_PLAN_DESC",
        "EMAIL", "FIRST_NAME", "LAST_NAME",
        "GAMEPK", "GAME_DATE", "GAME_SHORTHAND",
        "TICKET_ID", "SALES_BRIEFING",
    ]
    sheet2_data = cohort[sheet2_cols].copy()

    # Strip timezone info from datetime columns (Excel can't store tz-aware)
    TZ_COLUMNS = ["_FIVETRAN_SYNCED", "SYSTEM_START_DATE", "SYSTEM_END_DATE",
                  "SYSTEM_CREATE_DATE", "SYSTEM_UPDATE_DATE"]
    for col in TZ_COLUMNS:
        if col in df_all.columns:
            df_all[col] = df_all[col].astype(str).replace("NaT", "")
    for col in df_all.select_dtypes(include=["datetimetz"]).columns:
        df_all[col] = df_all[col].dt.tz_convert(None)
    for col in sheet2_data.select_dtypes(include=["datetimetz"]).columns:
        sheet2_data[col] = sheet2_data[col].dt.tz_convert(None)

    print(f"\nWriting Excel to {OUT}...")
    with pd.ExcelWriter(OUT, engine="openpyxl") as writer:
        df_all.to_excel(writer, sheet_name="Sheet1", index=False)
        sheet2_data.to_excel(writer, sheet_name="Sheet2", index=False)

    print(f"\nDone! Wrote {OUT}")
    print(f"  Sheet1: {len(df_all):,} rows x {len(df_all.columns)} columns (all respondents)")
    print(f"  Sheet2: {len(sheet2_data):,} rows x {len(sheet2_cols)} columns (filtered cohort + briefings)")

    for i in range(min(3, len(cohort))):
        r = cohort.iloc[i]
        print("\n" + "=" * 78)
        print(f"Row {i} -- {r.get('FIRST_NAME', '?')} {r.get('LAST_NAME', '?')}  ({r.get('EMAIL', '?')})")
        print("=" * 78)
        print(r["SALES_BRIEFING"])


if __name__ == "__main__":
    main()
