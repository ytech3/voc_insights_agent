"""Build SALES_BRIEFING for VOC HS2 sales-opportunity cohort.

Cohort filters:
  - PURCHASE_INTENT_DESC == "Yes, I do"
  - ATTEND_NUM_PLAN_DESC in the four clean 5+ game buckets
  - TB_ADDON_6 != "1"  (no problem needing staff follow-up)
  - BUYER_TYPE not in {Full Season Ticket, Full Season Plan, Weekday Plan,
    Weekend Plan, Sunday Plan, Flexible Season Member Ticket, Premium Ticket,
    Sponsor, Employee Ticket}
  - EMAIL domain is a personal-email domain (drop corporate domains)

Differences vs HS1 (build_premium_briefing.py):
  - Snowflake _DESC schema: values already decoded ("Highly satisfied" not 85)
  - AGE column directly (no birth-year math)
  - GENDER_ID_DESC directly
  - attend_with / concess_type are boolean flag columns, not comma strings
"""

from pathlib import Path
import pandas as pd

SRC = Path(r"C:\Users\ytaketani\voc_insights_agent\sales_marketing_opp\HS2.csv")
OUT = Path(r"C:\Users\ytaketani\voc_insights_agent\sales_marketing_opp\VOC_HS2_SALES_OPPORTUNITY.xlsx")

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

# Per codebook_sheets/survey_codes.csv these are sentinel "no answer" codes
# (skipped, abandoned, branching, etc.) — never real ratings.
SENTINEL_CODES = {"81", "82", "83", "84", "85", "86", "87", "88", "89", "90"}

# Decode for raw 1-5 satisfaction columns that ship without a _DESC sibling
# (e.g., CONCESS_GRID_SPEED). Per codebook_sheets/concess_grid.csv.
SAT_1_5 = {
    "1": "Highly satisfied",
    "2": "Somewhat satisfied",
    "3": "Somewhat dissatisfied",
    "4": "Highly dissatisfied",
    "5": "N/A",
}


def is_missing(v) -> bool:
    if v is None:
        return True
    s = str(v).strip()
    return s in MISSING or s.lower() == "nan"


def clean(v):
    if is_missing(v):
        return None
    return str(v).strip()


def clean_rating(v):
    """Like clean(), but also drops sentinel survey codes (81-90).
    Use this for satisfaction/grid columns where 81-90 are never real ratings.
    Don't use it for AGE / OVERALL_NUMRAT / counts where 81-89 are valid."""
    c = clean(v)
    if c is None or c in SENTINEL_CODES:
        return None
    return c


def clean_freetext(v):
    """For free-text fields like _OTHERSPECIFY where Snowflake leaks sentinel codes."""
    return clean_rating(v)


def decode_sat_1_5(v):
    c = clean_rating(v)
    return SAT_1_5.get(c, c)


def is_truthy_flag(v) -> bool:
    c = clean(v)
    return c is not None and c not in {"0", "0.0", "False", "false"}


def email_domain(e: str | None) -> str:
    if not e or "@" not in e:
        return ""
    return e.split("@", 1)[1].strip().lower()


def pronouns(gender: str | None) -> dict:
    g = (gender or "").strip().lower()
    if g == "woman":
        return {"subj": "She", "poss": "her"}
    if g == "man":
        return {"subj": "He", "poss": "his"}
    return {"subj": "They", "poss": "their"}


def gender_noun(gender: str | None) -> str | None:
    g = (gender or "").strip().lower()
    if g == "woman":
        return "woman"
    if g == "man":
        return "man"
    if gender:
        return "fan"
    return None


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


def attended_with(row) -> list[str]:
    labels: list[str] = []
    seen: set[str] = set()
    for col, label in ATTEND_WITH_FLAGS:
        if is_truthy_flag(row.get(col)) and label not in seen:
            seen.add(label)
            labels.append(label)
    return labels


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


def food_items(row) -> list[str]:
    items: list[str] = []
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


NUMRAT_LABELS = [
    ("CONCESS_NUMRAT", "Concessions"),
    ("ENTERTAIN_NUMRAT", "Entertainment"),
    ("MERCH_NUMRAT", "Merch"),
    ("PARKING_NUMRAT", "Parking"),
    ("SEATVIEW_NUMRAT", "Seat view"),
    ("STAFF_NUMRAT", "Staff"),
    ("GE_NUMRAT", "Gameday entry"),
]


def ten_out_of_ten_areas(row) -> list[str]:
    out = []
    for col, label in NUMRAT_LABELS:
        v = clean_rating(row.get(col))
        if v and v.split(" ")[0] == "10":
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


def highly_satisfied_areas(row) -> list[str]:
    out = []
    for col, label in HS_LABELS:
        v = clean_rating(row.get(col))
        if v and v.lower() == "highly satisfied":
            out.append(label)
    if clean_rating(row.get("PREPARED_SAT")) == "1":
        out.append("Pre-game info from team")
    return out


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


def build_bullets(row) -> list[str]:
    bullets: list[str] = []

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
    purchased = bool(merch_screen and merch_screen.lower().startswith("yes"))
    if purchased:
        parts = []
        if merch_num:
            parts.append(f"rated {merch_num.split(' ')[0]}/10")
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
    if inc_ot and not inc_ot.strip().isdigit():
        bullets.append(f'- Incentives feedback: "{inc_ot}"')

    return bullets


def build_briefing(row) -> str:
    return build_paragraph(row) + "\n" + "\n".join(build_bullets(row))


def filter_cohort(df: pd.DataFrame) -> pd.DataFrame:
    n0 = len(df)
    df = df[df["PURCHASE_INTENT_DESC"] == "Yes, I do"]
    n1 = len(df)
    df = df[df["ATTEND_NUM_PLAN_DESC"].isin(PLAN_5PLUS)]
    n2 = len(df)
    df = df[df["TB_ADDON_6"] != "1"]
    n3 = len(df)
    df = df[~df["BUYER_TYPE"].isin(EXCLUDED_BUYER_TYPES)]
    n4 = len(df)
    df = df[df["EMAIL"].fillna("").map(email_domain).isin(PERSONAL_DOMAINS)]
    n5 = len(df)

    print("Cohort funnel:")
    print(f"  Total rows                                : {n0:,}")
    print(f"  + PURCHASE_INTENT_DESC == 'Yes, I do'      : {n1:,}")
    print(f"  + ATTEND_NUM_PLAN_DESC in 5+ buckets       : {n2:,}")
    print(f"  + TB_ADDON_6 != 1 (no staff problem)       : {n3:,}")
    print(f"  + BUYER_TYPE excludes STH/Flex/Corp/Emp    : {n4:,}")
    print(f"  + EMAIL domain is personal                 : {n5:,}")
    return df


def main() -> None:
    df = pd.read_csv(SRC, dtype=str, low_memory=False)
    cohort = filter_cohort(df).copy()
    cohort["SALES_BRIEFING"] = cohort.apply(build_briefing, axis=1)
    cohort.to_excel(OUT, index=False)
    print(f"\nWrote {len(cohort):,} rows to {OUT}")
    print(f"Columns: {len(cohort.columns)} ({len(cohort.columns) - 1} original + SALES_BRIEFING)")
    for i in range(min(4, len(cohort))):
        r = cohort.iloc[i]
        print("\n" + "=" * 78)
        print(f"Row {i} -- {r.get('FIRST_NAME', '?')} {r.get('LAST_NAME', '?')}  ({r.get('EMAIL', '?')})")
        print("=" * 78)
        print(r["SALES_BRIEFING"])


if __name__ == "__main__":
    main()
