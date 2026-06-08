"""
Build SALES_BRIEFING for VOC_HS1_PREMIUM.xlsx (Qualtrics raw export).

Follows the same template as SALES_BRIEFING_INSTRUCTIONS.md but adapts
to Qualtrics column naming and value formats:
  - gender_id "Female"/"Male" -> "Woman"/"Man"
  - birth_year -> calculated age
  - attend_with_category: comma-separated text -> labels
  - concess_type: comma-separated _suffix list -> food items
  - favorite_team_clean instead of team_favorite
  - merch_no_7_TEXT instead of MERCH_NO_OTHERSPECIFY
  - merch_numrat may include "(best rating)" suffix
"""

import csv
from datetime import date
from pathlib import Path

import pandas as pd

SRC = Path(r"C:\Users\ytaketani\voc_insights_agent\sales_marketing_opp\VOC_HS1_PREMIUM.xlsx")

MISSING = {"", "nan", "NaN", "N/A", "None", "I prefer not to say"}


def is_missing(v) -> bool:
    if v is None:
        return True
    s = str(v).strip()
    return s in MISSING or s.lower() == "nan"


def clean(v):
    if is_missing(v):
        return None
    return str(v).strip()


# ── Attend-with mapping (Qualtrics full text -> short labels) ──
ATTEND_WITH_MAP = {
    "spouse or significant other": "Spouse",
    "adult children (18 and older)": "Adult + Kids",
    "high school aged children (14-17 years old)": "Adult + Kids",
    "younger children (under 14 years old)": "Young Kids",
    "other family members": "Other Family",
    "friends": "Friends",
    "business associates/clients": "Business",
    "i attended by myself": "Alone",
    "other (please specify below)": "Other",
}

# ── Food type mapping (Qualtrics _suffix -> label) ──
FOOD_MAP = {
    "_alcohol": "Alcoholic beverage",
    "_nonalcohol": "Non-alcoholic beverage",
    "_burgers": "Burgers",
    "_chicken": "Chicken",
    "_fries": "Fries",
    "_hotdog": "Hot dogs",
    "_icecream": "Ice cream",
    "_nachos": "Nachos",
    "_nuts": "Nuts",
    "_pizza": "Pizza",
    "_popcorn": "Popcorn",
    "_pretzels": "Pretzels",
    "_salad": "Salad",
    "_sandwich": "Sandwich",
    "_sausage": "Sausage",
}

# Map Qualtrics _suffix to quality column name
FOOD_QUALITY_COL = {
    "_alcohol": "concess_quality_alcohol",
    "_nonalcohol": "concess_quality_nonalcohol",
    "_burgers": "concess_quality_burgers",
    "_chicken": "concess_quality_chicken",
    "_fries": "concess_quality_fries",
    "_hotdog": "concess_quality_hotdog",
    "_icecream": "concess_quality_icecream",
    "_nachos": "concess_quality_nachos",
    "_nuts": "concess_quality_nuts",
    "_pizza": "concess_quality_pizza",
    "_popcorn": "concess_quality_popcorn",
    "_pretzels": "concess_quality_pretzels",
    "_salad": "concess_quality_salad",
    "_sandwich": "concess_quality_sandwich",
    "_sausage": "concess_quality_sausage",
}

NUMERIC_CODES = {"81", "82", "83", "84", "85", "86", "87", "88", "89"}


def clean_numeric(v):
    """Return None if value is a known numeric survey code."""
    c = clean(v)
    if c and c in NUMERIC_CODES:
        return None
    return c


def parse_age(birth_year_str):
    """Calculate age from birth year."""
    v = clean(birth_year_str)
    if not v:
        return None
    try:
        by = int(float(v))
        age = date.today().year - by
        if 1 < age < 120:
            return str(age)
    except (ValueError, TypeError):
        pass
    return None


def parse_gender(gender_id):
    """Map Qualtrics gender_id to the CRM-style labels."""
    g = (clean(gender_id) or "").lower()
    if g in ("female", "woman"):
        return "Woman"
    if g in ("male", "man"):
        return "Man"
    return None


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


def attended_with(row) -> list[str]:
    """Parse comma-separated attend_with_category into short labels."""
    raw = clean(row.get("attend_with_category"))
    if not raw:
        return []
    parts = [p.strip().lower() for p in raw.split(",")]
    seen = set()
    labels = []
    for p in parts:
        label = ATTEND_WITH_MAP.get(p, p.title())
        if label not in seen:
            seen.add(label)
            labels.append(label)
    return labels


def food_items(row) -> list[str]:
    """Parse comma-separated concess_type into food items with quality ratings."""
    raw = clean(row.get("concess_type"))
    if not raw:
        return []
    items = []
    for suffix in raw.split(","):
        suffix = suffix.strip().lower()
        label = FOOD_MAP.get(suffix)
        if not label:
            # Handle free-text specials
            if suffix and suffix not in ("_none", ""):
                items.append(suffix.strip("_").title())
            continue
        q_col = FOOD_QUALITY_COL.get(suffix)
        q = clean(row.get(q_col)) if q_col else None
        items.append(f"{label} ({q})" if q else label)
    # Also check free-text food fields
    for col in ("concess_type_14_TEXT", "concess_type_12_TEXT"):
        v = clean(row.get(col))
        if v:
            items.append(v)
    return items


def clean_rating(v):
    """Strip '(best rating)' suffix from ratings like '10 (best rating)'."""
    c = clean_numeric(v)
    if not c:
        return None
    return c.split(" ")[0] if " " in c else c


def build_paragraph(row) -> str:
    first_name = clean(row.get("first_name")) or "This fan"
    age = parse_age(row.get("birth_year"))
    gender_raw = parse_gender(row.get("gender_id"))
    overall = clean(row.get("overall_numrat"))
    with_list = attended_with(row)
    fav = clean(row.get("favorite_team_clean")) or clean_numeric(row.get("team_favorite"))
    avidity = clean(row.get("team_avidity"))
    ot = clean(row.get("overall_numrat_ot"))
    pro = pronouns(gender_raw)
    gnoun = gender_noun(gender_raw)

    # -- Sentence 1 --
    if age and gnoun:
        intro = f"{first_name} is a {age}-year-old {gnoun}"
    elif age:
        intro = f"{first_name} is {age} years old"
    elif gnoun:
        intro = f"{first_name} is a {gnoun}"
    else:
        intro = first_name

    tail = []
    if with_list:
        tail.append(f"attended with {', '.join(with_list).lower()}")
    if overall:
        tail.append(f"rated {pro['poss']} overall experience {overall}/10")

    if tail:
        if with_list and (age or gnoun):
            if overall:
                sentence1 = (
                    f"{intro} who attended with {', '.join(with_list).lower()} "
                    f"and rated {pro['poss']} overall experience {overall}/10."
                )
            else:
                sentence1 = f"{intro} who attended with {', '.join(with_list).lower()}."
        else:
            sentence1 = f"{intro} {' and '.join(tail)}."
    else:
        sentence1 = f"{intro} completed the post-game VOC survey."

    # -- Sentence 2: fandom + verbatim --
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

    game = clean(row.get("game_shorthand"))
    if game:
        bullets.append(f"- Game: {game}")

    age = parse_age(row.get("birth_year"))
    gender = parse_gender(row.get("gender_id"))
    demo_line = [x for x in (age, gender) if x]
    if demo_line:
        bullets.append(f"- Demographics: {', '.join(demo_line)}")

    with_list = attended_with(row)
    if with_list:
        bullets.append(f"- Attended with: {', '.join(with_list)}")

    fav = clean(row.get("favorite_team_clean")) or clean_numeric(row.get("team_favorite"))
    if fav:
        bullets.append(f"- Favorite team: {fav}")

    interest = clean(row.get("team_interest"))
    if interest:
        bullets.append(f"- Teams of interest: {interest}")

    avidity = clean(row.get("team_avidity"))
    if avidity:
        bullets.append(f"- Team avidity: {avidity}")

    pkg = clean(row.get("package_size"))
    price_scale = clean(row.get("price_scale"))
    if pkg or price_scale:
        parts = []
        if pkg:
            parts.append(pkg)
        if price_scale:
            parts.append(f"price scale {price_scale}")
        bullets.append(f"- Package size / price scale: {' / '.join(parts)}")

    overall_rating = clean(row.get("overall_numrat"))
    if overall_rating:
        bullets.append(f"- Overall experience rating: {overall_rating}/10")

    foods = food_items(row)
    if foods:
        bullets.append(f"- Food purchased & satisfaction: {', '.join(foods)}")

    cnum = clean(row.get("concess_numrat"))
    sub_metrics = []
    for name, col in [
        ("clean", "concess_grid_clean"),
        ("service", "concess_grid_custserv"),
        ("selection", "concess_grid_selection"),
        ("value", "concess_grid_value"),
    ]:
        v = clean(row.get(col))
        if v:
            sub_metrics.append(f"{name}: {v}")
    if cnum or sub_metrics:
        if cnum and sub_metrics:
            line = f"- Concessions overall: {cnum}/10 -- {', '.join(sub_metrics)}"
        elif cnum:
            line = f"- Concessions overall: {cnum}/10"
        else:
            line = f"- Concessions overall: {', '.join(sub_metrics)}"
        bullets.append(line)

    # Merch branch
    merch_screen = clean(row.get("merch_screener"))
    merch_no = clean(row.get("merch_no"))
    merch_no_other = clean(row.get("merch_no_7_TEXT"))
    merch_num = clean_rating(row.get("merch_numrat"))
    purchased = bool(merch_screen and merch_screen.lower().startswith("yes"))
    if purchased:
        parts = []
        if merch_num:
            parts.append(f"rated {merch_num}/10")
        for name, col in [
            ("quality", "merch_grid_merchquality"),
            ("price", "merch_grid_price"),
            ("selection", "merch_grid_selection"),
            ("service", "merch_grid_custserv" if "merch_grid_custserv" in (row.index if hasattr(row, "index") else row.keys()) else ""),
            ("wait", "merch_grid_wait"),
        ]:
            if col:
                v = clean(row.get(col))
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
        bullets.append(
            f"- Merch: Did not purchase -- reason: {' / '.join(reason_parts)}"
        )

    # Top incentive
    rank1 = clean(row.get("incentives_rank_1"))
    if rank1:
        bullets.append(f'- Top Incentive: "{rank1}"')

    # Overall comment (verbatim)
    ot = clean(row.get("overall_numrat_ot"))
    if ot:
        bullets.append(f'- Overall comment: "{ot}"')

    # Incentives feedback (verbatim) -- skip pure numeric codes
    inc_ot = clean(row.get("incentives_ot"))
    if inc_ot and not inc_ot.strip().isdigit():
        bullets.append(f'- Incentives feedback: "{inc_ot}"')

    return bullets


def build_briefing(row) -> str:
    paragraph = build_paragraph(row)
    bullets = build_bullets(row)
    return paragraph + "\n" + "\n".join(bullets)


def main() -> None:
    df = pd.read_excel(SRC, dtype=str)
    df["SALES_BRIEFING"] = df.apply(build_briefing, axis=1)

    # Write back to Excel
    df.to_excel(SRC, index=False)

    print(f"Wrote {len(df)} rows with SALES_BRIEFING to {SRC}")
    print(f"Columns: {len(df.columns)} ({len(df.columns) - 1} original + 1 new)")
    for i in range(min(4, len(df))):
        print(f"\n{'=' * 70}")
        print(
            f"Row {i} -- {df.iloc[i].get('first_name', '?')} {df.iloc[i].get('last_name', '?')}"
        )
        print("=" * 70)
        print(df.iloc[i]["SALES_BRIEFING"])


if __name__ == "__main__":
    main()
