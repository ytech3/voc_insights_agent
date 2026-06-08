"""Build Sales Opportunity Excel for VOC May 1-6, 2026.

Pulls data directly from Snowflake, applies cohort filters, generates
SALES_BRIEFING fan profiles, and outputs a two-sheet Excel:
  - Sheet1: All raw survey data (full columns from the view)
  - Sheet2: Key columns + SALES_BRIEFING for the filtered cohort

Cohort filters:
  - PURCHASE_INTENT_DESC == "Yes, I do"
  - ATTEND_NUM_PLAN_DESC in the four 5+ game buckets
  - TB_ADDON_6 != "1" (no service recovery / staff follow-up needed)
  - BUYER_TYPE not in {Full Season Ticket, Full Season Plan, Weekday Plan,
    Weekend Plan, Sunday Plan, Flexible Season Member Ticket, Premium Ticket,
    Sponsor, Employee Ticket}
  - EMAIL domain is a personal-email domain (drop corporate domains)
"""

from pathlib import Path
import pandas as pd
import snowflake.connector
import os

OUT = Path(r"C:\Users\ytaketani\voc_insights_agent\sales_marketing_opp\VOC_05012026_05062026.xlsx")

# ---------- Snowflake connection ----------

def get_snowflake_connection():
    """Connect using externalbrowser auth (same as cortex CLI)."""
    return snowflake.connector.connect(
        account="hta92307.east-us-2.azure",
        user="YTAKETANI@RAYSBASEBALL.COM",
        authenticator="externalbrowser",
        database="TBRDP_DW_PROD",
        schema="IM_RPT",
        warehouse="TBRDP_DW_CORTEX_XS_WH",
    )


def fetch_data() -> pd.DataFrame:
    """Pull all rows from the view for May 1-6, 2026."""
    query = """
    SELECT *
    FROM TBRDP_DW_PROD.IM_RPT.V_SBL_QUALTRICS_VOC_POST_ATTENDANCE_FULL_CORTEX_AI
    WHERE GAME_DATE BETWEEN '2026-05-01' AND '2026-05-06'
    """
    print("Connecting to Snowflake...")
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
    return df


# ---------- Cohort filter constants ----------

PLAN_5PLUS = {
    "Between 6 and 10 games",
    "Between 11 and 15 games",
    "Between 16 and 20 games",
    "Over 20 games",
}

EXCLUDED_BUYER_TYPES = {
    "Full Season Ticket", "Full Season Plan",
    "Weekday Plan", "Weekend Plan", "Sunday Plan",
    "Flexible Season Member Ticket", "Premium Ticket",
    "Sponsor", "Employee Ticket",
}

PERSONAL_DOMAINS = {
    "gmail.com", "yahoo.com", "hotmail.com", "outlook.com", "icloud.com",
    "me.com", "aol.com", "comcast.net", "sbcglobal.net", "verizon.net",
    "att.net", "bellsouth.net", "cox.net", "msn.com", "live.com",
    "ymail.com", "rocketmail.com", "mac.com", "earthlink.net", "mail.com",
    "protonmail.com", "pm.me", "gmx.com", "tampabay.rr.com", "rr.com",
    "charter.net", "juno.com", "roadrunner.com", "optonline.net",
    "frontier.com", "windstream.net", "centurylink.net", "spectrum.net",
    "embarqmail.com", "twc.com", "netzero.net", "mindspring.com",
    "yahoo.co.uk", "outlook.es",
}

MISSING = {"", "nan", "NaN", "N/A", "None", "I prefer not to say"}

SENTINEL_CODES = {"81", "82", "83", "84", "85", "86", "87", "88", "89", "90"}

SAT_1_5 = {
    "1": "Highly satisfied",
    "2": "Somewhat satisfied",
    "3": "Somewhat dissatisfied",
    "4": "Highly dissatisfied",
    "5": "N/A",
}


# ---------- Helper functions ----------

def is_missing(v) -> bool:
    if v is None:
        return True
    s = str(v).strip()
    return s in MISSING or s.lower() == "nan"


def clean(v):
    if is_missing(v):
        return None
    s = str(v).strip()
    # Strip trailing .0 from numeric strings (e.g., "69.0" -> "69")
    if s.endswith(".0") and s[:-2].isdigit():
        return s[:-2]
    return s


def clean_rating(v):
    c = clean(v)
    if c is None or c in SENTINEL_CODES:
        return None
    return c


def clean_freetext(v):
    return clean_rating(v)


def decode_sat_1_5(v):
    c = clean_rating(v)
    return SAT_1_5.get(c, c)


def is_truthy_flag(v) -> bool:
    c = clean(v)
    return c is not None and c not in {"0", "0.0", "False", "false"}


def email_domain(e) -> str:
    if not e or "@" not in str(e):
        return ""
    return str(e).split("@", 1)[1].strip().lower()


def pronouns(gender) -> dict:
    g = (str(gender) if gender else "").strip().lower()
    if g == "woman":
        return {"subj": "She", "poss": "her"}
    if g == "man":
        return {"subj": "He", "poss": "his"}
    return {"subj": "They", "poss": "their"}


def gender_noun(gender):
    g = (str(gender) if gender else "").strip().lower()
    if g == "woman":
        return "woman"
    if g == "man":
        return "man"
    if gender:
        return "fan"
    return None


# ---------- Attend-with flags ----------

ATTEND_WITH_FLAGS = [
    ("ATTEND_WITH_CATEGORY_SPOUSE", "Spouse"),
    ("ATTEND_WITH_CATEGORY_ADULT_KIDS", "Adult + Kids"),
    ("ATTEND_WITH_CATEGORY_HS_KIDS", "Adult + Kids"),
    ("ATTEND_WITH_CATEGORY_NON_HS_KIDS", "Adult + Kids"),
    ("ATTEND_WITH_CATEGORY_YOUNG_KIDS", "Young Kids"),
    ("ATTEND_WITH_CATEGORY_OTHERFAM", "Other Family"),
    ("ATTEND_WITH_CATEGORY_FRIENDS", "Friends"),
    ("ATTEND_WITH_CATEGORY_BUSINESS", "Business"),
    ("ATTEND_WITH_CATEGORY_ALONE", "Alone"),
    ("ATTEND_WITH_CATEGORY_OTHER", "Other"),
]


def attended_with(row) -> list:
    labels = []
    seen = set()
    for col, label in ATTEND_WITH_FLAGS:
        if is_truthy_flag(row.get(col)) and label not in seen:
            seen.add(label)
            labels.append(label)
    return labels


# ---------- Food flags ----------

FOOD_FLAGS = [
    ("CONCESS_TYPE_ALCOHOL", "Alcoholic beverage", "CONCESS_QUALITY_ALCOHOL_DESC"),
    ("CONCESS_TYPE_NONALCOHOL", "Non-alcoholic beverage", "CONCESS_QUALITY_NONALCOHOL_DESC"),
    ("CONCESS_TYPE_BURGERS", "Burgers", "CONCESS_QUALITY_BURGERS_DESC"),
    ("CONCESS_TYPE_CHICKEN", "Chicken", "CONCESS_QUALITY_CHICKEN_DESC"),
    ("CONCESS_TYPE_FRIES", "Fries", "CONCESS_QUALITY_FRIES_DESC"),
    ("CONCESS_TYPE_HOTDOG", "Hot dogs", "CONCESS_QUALITY_HOTDOG_DESC"),
    ("CONCESS_TYPE_ICECREAM", "Ice cream", "CONCESS_QUALITY_ICECREAM_DESC"),
    ("CONCESS_TYPE_NACHOS", "Nachos", "CONCESS_QUALITY_NACHOS_DESC"),
    ("CONCESS_TYPE_NUTS", "Nuts", "CONCESS_QUALITY_NUTS_DESC"),
    ("CONCESS_TYPE_PIZZA", "Pizza", "CONCESS_QUALITY_PIZZA_DESC"),
    ("CONCESS_TYPE_POPCORN", "Popcorn", "CONCESS_QUALITY_POPCORN_DESC"),
    ("CONCESS_TYPE_PRETZELS", "Pretzels", "CONCESS_QUALITY_PRETZELS_DESC"),
    ("CONCESS_TYPE_SALAD", "Salad", "CONCESS_QUALITY_SALAD_DESC"),
    ("CONCESS_TYPE_SANDWICH", "Sandwich", "CONCESS_QUALITY_SANDWICH_DESC"),
    ("CONCESS_TYPE_SAUSAGE", "Sausage", "CONCESS_QUALITY_SAUSAGE_DESC"),
]


def food_items(row) -> list:
    items = []
    for flag_col, label, qual_col in FOOD_FLAGS:
        if is_truthy_flag(row.get(flag_col)):
            qual = clean_rating(row.get(qual_col))
            items.append(f"{label} ({qual})" if qual else label)
    for txt_col, qual_col in [
        ("CONCESS_TYPE_OTHER_DESSERT_SPECIFY", "CONCESS_QUALITY_OTHER_DESSERT_DESC"),
        ("CONCESS_TYPE_OTHER_ENTREE_SPECIFY", "CONCESS_QUALITY_OTHER_ENTREE_DESC"),
    ]:
        v = clean_freetext(row.get(txt_col))
        if v:
            qual = clean_rating(row.get(qual_col))
            items.append(f"{v} ({qual})" if qual else v)
    return items


# ---------- Rating areas ----------

NUMRAT_LABELS = [
    ("CONCESS_NUMRAT", "Concessions"),
    ("ENTERTAIN_NUMRAT", "Entertainment"),
    ("MERCH_NUMRAT", "Merch"),
    ("PARKING_NUMRAT", "Parking"),
    ("SEATVIEW_NUMRAT", "Seat view"),
    ("STAFF_NUMRAT", "Staff"),
    ("GE_NUMRAT", "Gameday entry"),
]


def ten_out_of_ten_areas(row) -> list:
    out = []
    for col, label in NUMRAT_LABELS:
        v = clean_rating(row.get(col))
        if v and str(v).split(" ")[0] == "10":
            out.append(label)
    return out


HS_LABELS = [
    ("BRANDHEALTH_GRID_ACCESSIBLE_DESC", "Brand: Accessible"),
    ("BRANDHEALTH_GRID_CHAMPION_DESC", "Brand: Champions"),
    ("BRANDHEALTH_GRID_DIVERSITY_DESC", "Brand: Diversity"),
    ("BRANDHEALTH_GRID_EMOTIONAL_DESC", "Brand: Emotional connection"),
    ("BRANDHEALTH_GRID_EXCITING_DESC", "Brand: Exciting"),
    ("BRANDHEALTH_GRID_FAMFRIENDLY_DESC", "Brand: Family-friendly"),
    ("BRANDHEALTH_GRID_POSINFLUENCE_DESC", "Brand: Positive influence"),
    ("BRANDHEALTH_GRID_RIGHTDIRECTION_DESC", "Brand: Right direction"),
    ("BRANDHEALTH_GRID_SAFE_DESC", "Brand: Safe"),
    ("BRANDHEALTH_GRID_SUSTAINABILITY_DESC", "Brand: Sustainability"),
    ("BRANDHEALTH_GRID_TRENDY_DESC", "Brand: Trendy"),
    ("BRANDHEALTH_GRID_WELCOME_DESC", "Brand: Welcoming"),
    ("CONCESS_GRID_CLEAN_DESC", "Concessions cleanliness"),
    ("CONCESS_GRID_CUSTSERV_DESC", "Concessions customer service"),
    ("CONCESS_GRID_SELECTION_DESC", "Concessions selection"),
    ("CONCESS_GRID_VALUE_DESC", "Concessions value"),
    ("ENTERTAIN_GRID_GAMES_DESC", "In-game games"),
    ("ENTERTAIN_GRID_KIDS_ACTIVITIES_DESC", "Kids activities"),
    ("ENTERTAIN_GRID_MUSIC_DESC", "Music"),
    ("ENTERTAIN_GRID_PLAYER_CONTENT_DESC", "Player content"),
    ("ENTERTAIN_GRID_PREGAME_CONTENT_DESC", "Pregame content"),
    ("ENTERTAIN_GRID_SCOREBOARD_DESC", "Scoreboard"),
    ("ENTERTAIN_GRID_THEME_DESC", "In-game theme"),
    ("MERCH_GRID_CUSTSERV_DESC", "Merch customer service"),
    ("MERCH_GRID_MERCHQUALITY_DESC", "Merch quality"),
    ("MERCH_GRID_PRICE_DESC", "Merch price"),
    ("MERCH_GRID_SELECTION_DESC", "Merch selection"),
    ("MERCH_GRID_WAIT_DESC", "Merch wait"),
    ("MOBILE_ORDER_GRID_ACCURACY_DESC", "Mobile order accuracy"),
    ("MOBILE_ORDER_GRID_EASY_DESC", "Mobile order ease"),
    ("MOBILE_ORDER_GRID_FUTURE_DESC", "Mobile order future use"),
    ("MOBILE_ORDER_GRID_TIMEFRAME_DESC", "Mobile order timing"),
    ("STAFF_GRID_ACCESSIBILITY_DESC", "Staff: Accessibility"),
    ("STAFF_GRID_CONCESSIONS_DESC", "Staff: Concessions"),
    ("STAFF_GRID_FAN_SERVICES_DESC", "Staff: Fan services"),
    ("STAFF_GRID_MERCH_DESC", "Staff: Merch"),
    ("STAFF_GRID_PARKING_DESC", "Staff: Parking"),
    ("STAFF_GRID_SECURITY_DESC", "Staff: Security"),
    ("STAFF_GRID_USHER_DESC", "Staff: Ushers"),
    ("WALK_OUT_GRID_EASY_DESC", "Walk-out ease"),
    ("WALK_OUT_GRID_SELECTION_DESC", "Walk-out exits"),
    ("WALK_OUT_GRID_TIMEFRAME_DESC", "Walk-out timing"),
    ("GIVEAWAY_SAT_DESC", "Giveaway"),
    ("THEME_SAT_DESC", "Theme night"),
    ("TIX_OFFER_SAT_DESC", "Ticket offer"),
]


def highly_satisfied_areas(row) -> list:
    out = []
    for col, label in HS_LABELS:
        v = clean_rating(row.get(col))
        if v and str(v).lower() == "highly satisfied":
            out.append(label)
    if clean_rating(row.get("PREPARED_SAT")) == "1":
        out.append("Pre-game info from team")
    return out


# ---------- Briefing builders ----------

def build_paragraph(row) -> str:
    first_name = clean(row.get("FIRST_NAME")) or "This fan"
    age = clean(row.get("AGE"))
    gender_raw = clean(row.get("GENDER_ID_DESC"))
    overall = clean_rating(row.get("OVERALL_NUMRAT"))
    with_list = attended_with(row)
    fav = clean(row.get("FAVORITE_TEAM_CLEAN"))
    avidity = clean(row.get("TEAM_AVIDITY_DESC"))
    ot = clean_freetext(row.get("OVERALL_NUMRAT_OT"))
    pro = pronouns(gender_raw)
    gnoun = gender_noun(gender_raw)

    if age and gnoun:
        intro = f"{first_name} is a {age}-year-old {gnoun}"
    elif age:
        intro = f"{first_name} is {age} years old"
    elif gnoun:
        intro = f"{first_name} is a {gnoun}"
    else:
        intro = first_name

    if with_list and overall:
        sentence1 = (
            f"{intro} who attended with {', '.join(with_list).lower()} "
            f"and rated {pro['poss']} overall experience {overall}/10."
        )
    elif with_list:
        sentence1 = f"{intro} who attended with {', '.join(with_list).lower()}."
    elif overall:
        sentence1 = f"{intro} and rated {pro['poss']} overall experience {overall}/10."
    else:
        sentence1 = f"{intro} completed the post-game VOC survey."

    fandom_clause = ""
    if fav and avidity:
        fandom_clause = f"identifies as a {fav} fan (avidity {avidity})"
    elif fav:
        fandom_clause = f"identifies as a {fav} fan"
    elif avidity:
        fandom_clause = f"self-reported team avidity of {avidity}"

    verbatim_clause = ""
    if ot:
        verbatim_clause = (
            f"left a detailed comment -- see verbatim below for {pro['poss']} exact words"
        )

    parts = [p for p in (fandom_clause, verbatim_clause) if p]
    sentence2 = ""
    if parts:
        sentence2 = " " + pro["subj"] + " " + " and ".join(parts) + "."

    return (sentence1 + sentence2).strip()


def build_bullets(row) -> list:
    bullets = []

    game = clean(row.get("GAME_SHORTHAND"))
    if game:
        bullets.append(f"- Game: {game}")

    price_raw = clean(row.get("AVERAGE_TIX_PRICE"))
    if price_raw is not None:
        try:
            bullets.append(f"- Order Price: ${float(price_raw):,.2f}")
        except ValueError:
            bullets.append(f"- Order Price: {price_raw}")

    age = clean(row.get("AGE"))
    gender = clean(row.get("GENDER_ID_DESC"))
    demo_line = [x for x in (age, gender) if x]
    if demo_line:
        bullets.append(f"- Demographics: {', '.join(demo_line)}")

    with_list = attended_with(row)
    if with_list:
        bullets.append(f"- Attended with: {', '.join(with_list)}")

    fav = clean(row.get("FAVORITE_TEAM_CLEAN"))
    if fav:
        bullets.append(f"- Favorite team: {fav}")

    interest = clean(row.get("TEAM_INTEREST"))
    if interest:
        bullets.append(f"- Teams of interest: {interest}")

    avidity = clean(row.get("TEAM_AVIDITY_DESC"))
    if avidity:
        bullets.append(f"- Team avidity: {avidity}")

    pkg = clean(row.get("PACKAGE_SIZE"))
    price_scale = clean(row.get("PRICE_SCALE"))
    if pkg or price_scale:
        parts = []
        if pkg:
            parts.append(pkg)
        if price_scale:
            parts.append(f"price scale {price_scale}")
        bullets.append(f"- Package size / price scale: {' / '.join(parts)}")

    overall = clean_rating(row.get("OVERALL_NUMRAT"))
    if overall:
        bullets.append(f"- Overall experience rating: {overall}/10")

    foods = food_items(row)
    if foods:
        bullets.append(f"- Food purchased & satisfaction: {', '.join(foods)}")

    cnum = clean_rating(row.get("CONCESS_NUMRAT"))
    sub_metrics = []
    for name, col, decoder in [
        ("clean", "CONCESS_GRID_CLEAN_DESC", clean_rating),
        ("service", "CONCESS_GRID_CUSTSERV_DESC", clean_rating),
        ("selection", "CONCESS_GRID_SELECTION_DESC", clean_rating),
        ("value", "CONCESS_GRID_VALUE_DESC", clean_rating),
        ("speed", "CONCESS_GRID_SPEED", decode_sat_1_5),
    ]:
        v = decoder(row.get(col))
        if v:
            sub_metrics.append(f"{name}: {v}")
    if cnum or sub_metrics:
        if cnum and sub_metrics:
            bullets.append(f"- Concessions overall: {cnum}/10 -- {', '.join(sub_metrics)}")
        elif cnum:
            bullets.append(f"- Concessions overall: {cnum}/10")
        else:
            bullets.append(f"- Concessions: {', '.join(sub_metrics)}")

    tens = ten_out_of_ten_areas(row)
    if tens:
        bullets.append(f"- Other 10/10 ratings: {', '.join(tens)}")

    hs = highly_satisfied_areas(row)
    if hs:
        bullets.append(f"- Highly satisfied with: {', '.join(hs)}")

    merch_screen = clean(row.get("MERCH_SCREENER_DESC"))
    merch_no = clean(row.get("MERCH_NO_DESC"))
    merch_no_other = clean_freetext(row.get("MERCH_NO_OTHERSPECIFY"))
    merch_num = clean_rating(row.get("MERCH_NUMRAT"))
    purchased = bool(merch_screen and str(merch_screen).lower().startswith("yes"))
    if purchased:
        parts = []
        if merch_num:
            parts.append(f"rated {str(merch_num).split(' ')[0]}/10")
        for name, col in [
            ("quality", "MERCH_GRID_MERCHQUALITY_DESC"),
            ("price", "MERCH_GRID_PRICE_DESC"),
            ("selection", "MERCH_GRID_SELECTION_DESC"),
            ("service", "MERCH_GRID_CUSTSERV_DESC"),
            ("wait", "MERCH_GRID_WAIT_DESC"),
        ]:
            v = clean_rating(row.get(col))
            if v:
                parts.append(f"{name}: {v}")
        bullets.append(
            f"- Merch: Purchased -- {'; '.join(parts)}" if parts else "- Merch: Purchased"
        )
    elif merch_no or merch_no_other:
        reason_parts = []
        if merch_no:
            reason_parts.append(f'"{merch_no}"')
        if merch_no_other:
            reason_parts.append(f'"{merch_no_other}"')
        bullets.append(f"- Merch: Did not purchase -- reason: {' / '.join(reason_parts)}")

    rank1 = clean(row.get("INCENTIVES_RANK_1_DESC"))
    if rank1:
        bullets.append(f'- Top Incentive: "{rank1}"')

    ot = clean_freetext(row.get("OVERALL_NUMRAT_OT"))
    if ot:
        bullets.append(f'- Overall comment: "{ot}"')

    topics = clean(row.get("OVERALL_NUMRAT_OT_PARENT_TOPICS"))
    if topics:
        bullets.append(f"- Comment topics: {topics}")

    inc_ot = clean_freetext(row.get("INCENTIVES_OT"))
    if inc_ot and not str(inc_ot).strip().isdigit():
        bullets.append(f'- Incentives feedback: "{inc_ot}"')

    return bullets


def build_briefing(row) -> str:
    return build_paragraph(row) + "\n" + "\n".join(build_bullets(row))


# ---------- Cohort filter ----------

def filter_cohort(df: pd.DataFrame) -> pd.DataFrame:
    # Convert columns to string for consistent comparison
    df["PURCHASE_INTENT_DESC"] = df["PURCHASE_INTENT_DESC"].astype(str)
    df["ATTEND_NUM_PLAN_DESC"] = df["ATTEND_NUM_PLAN_DESC"].astype(str)
    df["TB_ADDON_6"] = df["TB_ADDON_6"].astype(str)
    df["BUYER_TYPE"] = df["BUYER_TYPE"].astype(str)
    df["EMAIL"] = df["EMAIL"].astype(str)
    df["PREVIOUS_PURCHASE_DESC"] = df["PREVIOUS_PURCHASE_DESC"].astype(str)

    n0 = len(df)
    df = df[df["PURCHASE_INTENT_DESC"] == "Yes, I do"]
    n1 = len(df)
    df = df[df["ATTEND_NUM_PLAN_DESC"].isin(PLAN_5PLUS)]
    n2 = len(df)
    # Filter out TB_ADDON_6 == 1 (service recovery / staff follow-up needed)
    df = df[~df["TB_ADDON_6"].isin({"1", "1.0"})]
    n3 = len(df)
    df = df[~df["BUYER_TYPE"].isin(EXCLUDED_BUYER_TYPES)]
    n4 = len(df)
    df = df[df["EMAIL"].map(email_domain).isin(PERSONAL_DOMAINS)]
    n5 = len(df)
    # Filter out previous purchasers (PREVIOUS_PURCHASE_DESC == "Yes")
    df = df[df["PREVIOUS_PURCHASE_DESC"] != "Yes"]
    n6 = len(df)

    print("\nCohort funnel:")
    print(f"  Total rows                                : {n0:,}")
    print(f"  + PURCHASE_INTENT_DESC == 'Yes, I do'      : {n1:,}")
    print(f"  + ATTEND_NUM_PLAN_DESC in 5+ buckets       : {n2:,}")
    print(f"  + TB_ADDON_6 != 1 (no service recovery)    : {n3:,}")
    print(f"  + BUYER_TYPE excludes STH/Flex/Corp/Emp    : {n4:,}")
    print(f"  + EMAIL domain is personal                 : {n5:,}")
    print(f"  + PREVIOUS_PURCHASE_DESC != 'Yes'          : {n6:,}")
    return df


# ---------- Summary builder ----------

def build_summary(cohort: pd.DataFrame) -> pd.DataFrame:
    """Build the summary breakdown by ATTEND_NUM_PLAN_DESC with assignment labels."""
    assignment_map = {
        "Between 6 and 10 games": "Ticket Sales Rep",
        "Between 11 and 15 games": "Account Executive",
        "Between 16 and 20 games": "Account Executive",
        "Over 20 games": "Account Executive",
    }

    summary_rows = []
    summary_rows.append({
        "": None,
        "Game plan on attending": "Game plan on attending",
        "# of respondants": "# of respondants",
        "Assignment": None,
    })

    for plan_desc in ["Between 6 and 10 games", "Between 11 and 15 games",
                      "Between 16 and 20 games", "Over 20 games"]:
        count = len(cohort[cohort["ATTEND_NUM_PLAN_DESC"] == plan_desc])
        if count > 0:
            summary_rows.append({
                "": None,
                "Game plan on attending": plan_desc,
                "# of respondants": count,
                "Assignment": assignment_map.get(plan_desc, ""),
            })

    total = len(cohort)
    summary_rows.append({
        "": None,
        "Game plan on attending": "Total",
        "# of respondants": total,
        "Assignment": None,
    })

    return pd.DataFrame(summary_rows)


# ---------- Main ----------

def main() -> None:
    # Step 1: Fetch all data from Snowflake
    df_all = fetch_data()

    # Step 2: Apply cohort filters
    cohort = filter_cohort(df_all.copy()).copy()

    # Step 3: Generate SALES_BRIEFING for each cohort row
    print("\nGenerating SALES_BRIEFING profiles...")
    cohort["SALES_BRIEFING"] = cohort.apply(build_briefing, axis=1)
    print(f"  Generated {len(cohort):,} briefings")

    # Step 4: Build Sheet2 (key columns + briefing)
    sheet2_cols = [
        "FINANCIAL_ID", "ATTENDING_ID", "ATTEND_NUM_PLAN_DESC",
        "EMAIL", "FIRST_NAME", "LAST_NAME",
        "GAMEPK", "GAME_DATE", "GAME_SHORTHAND",
        "TICKET_ID", "SALES_BRIEFING",
    ]
    sheet2_data = cohort[sheet2_cols].copy()

    # Step 5: Strip timezone info from ALL datetime columns (Excel doesn't support tz-aware)
    # Known TZ columns from the Snowflake view schema
    TZ_COLUMNS = ["_FIVETRAN_SYNCED", "SYSTEM_START_DATE", "SYSTEM_END_DATE",
                  "SYSTEM_CREATE_DATE", "SYSTEM_UPDATE_DATE"]
    for col in TZ_COLUMNS:
        if col in df_all.columns:
            df_all[col] = df_all[col].astype(str).replace("NaT", "")
    # Also catch any other tz-aware datetime columns
    for col in df_all.select_dtypes(include=["datetimetz"]).columns:
        df_all[col] = df_all[col].dt.tz_convert(None)
    for col in sheet2_data.select_dtypes(include=["datetimetz"]).columns:
        sheet2_data[col] = sheet2_data[col].dt.tz_convert(None)

    # Step 6: Write Excel with both sheets
    print(f"\nWriting Excel to {OUT}...")
    with pd.ExcelWriter(OUT, engine="openpyxl") as writer:
        # Sheet1: All raw data (full view, all rows for the date range)
        df_all.to_excel(writer, sheet_name="Sheet1", index=False)
        # Sheet2: Key columns with SALES_BRIEFING for cohort
        sheet2_data.to_excel(writer, sheet_name="Sheet2", index=False)

    print(f"\nDone! Wrote {OUT}")
    print(f"  Sheet1: {len(df_all):,} rows x {len(df_all.columns)} columns (all respondents)")
    print(f"  Sheet2: {len(sheet2_data):,} rows x {len(sheet2_cols)} columns (filtered cohort + briefings)")

    # Print a few sample briefings
    for i in range(min(3, len(cohort))):
        r = cohort.iloc[i]
        print("\n" + "=" * 78)
        print(f"Row {i} -- {r.get('FIRST_NAME', '?')} {r.get('LAST_NAME', '?')}  ({r.get('EMAIL', '?')})")
        print("=" * 78)
        print(r["SALES_BRIEFING"])


if __name__ == "__main__":
    main()
