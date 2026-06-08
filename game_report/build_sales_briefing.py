"""
Build a sales-ready CSV from Homestand_1_CRM.csv per the instructions in
SALES_BRIEFING_INSTRUCTIONS.md.

- Preserves every original column + original row order
- Appends a single SALES_BRIEFING column (paragraph + bullets, newline-separated)
- Skips bullets whose underlying fields are all missing
- Renders 4 designated fields verbatim in quotes:
    OVERALL_NUMRAT_OT, INCENTIVES_OT, INCENTIVES_RANK_1_DESC, MERCH_NO_DESC
"""

import csv
from pathlib import Path

import pandas as pd

SRC = Path(r"C:\Users\ytaketani\voc_insights_agent\game_report\Homestand_1_CRM.csv")
OUT = Path(
    r"C:\Users\ytaketani\voc_insights_agent\game_report\Homestand_1_CRM_SalesBriefing.csv"
)

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


ATTEND_MAP = {
    "ATTEND_WITH_CATEGORY_SPOUSE": "Spouse",
    "ATTEND_WITH_CATEGORY_ADULT_KIDS": "Adult + Kids",
    "ATTEND_WITH_CATEGORY_OTHERFAM": "Other Family",
    "ATTEND_WITH_CATEGORY_FRIENDS": "Friends",
    "ATTEND_WITH_CATEGORY_BUSINESS": "Business",
    "ATTEND_WITH_CATEGORY_ALONE": "Alone",
    "ATTEND_WITH_CATEGORY_OTHER": "Other",
}

FOOD_MAP = {
    "ALCOHOL": "Alcoholic beverage",
    "BURGERS": "Burgers",
    "CHICKEN": "Chicken",
    "FRIES": "Fries",
    "HOTDOG": "Hot dogs",
    "ICECREAM": "Ice cream",
    "NACHOS": "Nachos",
    "NONALCOHOL": "Non-alcoholic beverage",
    "NUTS": "Nuts",
    "PIZZA": "Pizza",
    "POPCORN": "Popcorn",
    "PRETZELS": "Pretzels",
    "SALAD": "Salad",
    "SANDWICH": "Sandwich",
    "SAUSAGE": "Sausage",
}


def attended_with(row) -> list[str]:
    out = []
    for col, label in ATTEND_MAP.items():
        if str(row.get(col, "")).strip() == "1":
            out.append(label)
    return out


def food_items(row) -> list[str]:
    items = []
    for key, label in FOOD_MAP.items():
        if str(row.get(f"CONCESS_TYPE_{key}", "")).strip() == "1":
            q = clean(row.get(f"CONCESS_QUALITY_{key}_DESC"))
            items.append(f"{label} ({q})" if q else label)
    for special in ("OTHER_DESSERT_SPECIFY", "OTHER_ENTREE_SPECIFY"):
        v = clean(row.get(f"CONCESS_TYPE_{special}"))
        if v:
            items.append(v)
    return items


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


def build_paragraph(row) -> str:
    first_name = clean(row.get("FIRST_NAME")) or "This fan"
    age = clean(row.get("AGE"))
    gender_raw = clean(row.get("GENDER_ID_DESC"))
    overall = clean(row.get("OVERALL_NUMRAT"))
    with_list = attended_with(row)
    fav = clean(row.get("TEAM_FAVORITE"))
    avidity = clean(row.get("TEAM_AVIDITY_DESC"))
    ot = clean(row.get("OVERALL_NUMRAT_OT"))
    pro = pronouns(gender_raw)
    gnoun = gender_noun(gender_raw)

    # -- Sentence 1 --
    # Prefer "{First} is a {age}-year-old {gender} who attended with {X} and rated {poss} overall experience {N}/10."
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
        # If intro includes "is a ...", use "who" linker for attended-with; else " and "
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

    # -- Sentence 2: fandom + verbatim pointer (consolidated) --
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
            f"left a detailed comment — see verbatim below for {pro['poss']} exact words"
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

    age = clean(row.get("AGE"))
    gender = clean(row.get("GENDER_ID_DESC"))
    demo_line = [x for x in (age, gender) if x]
    if demo_line:
        bullets.append(f"- Demographics: {', '.join(demo_line)}")

    with_list = attended_with(row)
    if with_list:
        bullets.append(f"- Attended with: {', '.join(with_list)}")

    fav = clean(row.get("TEAM_FAVORITE"))
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

    overall_rating = clean(row.get("OVERALL_NUMRAT"))
    if overall_rating:
        bullets.append(f"- Overall experience rating: {overall_rating}/10")

    foods = food_items(row)
    if foods:
        bullets.append(f"- Food purchased & satisfaction: {', '.join(foods)}")

    cnum = clean(row.get("CONCESS_NUMRAT"))
    sub_metrics = []
    for name, col in [
        ("clean", "CONCESS_GRID_CLEAN_DESC"),
        ("service", "CONCESS_GRID_CUSTSERV_DESC"),
        ("selection", "CONCESS_GRID_SELECTION_DESC"),
        ("value", "CONCESS_GRID_VALUE_DESC"),
    ]:
        v = clean(row.get(col))
        if v:
            sub_metrics.append(f"{name}: {v}")
    if cnum or sub_metrics:
        if cnum and sub_metrics:
            line = f"- Concessions overall: {cnum}/10 — {', '.join(sub_metrics)}"
        elif cnum:
            line = f"- Concessions overall: {cnum}/10"
        else:
            line = f"- Concessions overall: {', '.join(sub_metrics)}"
        bullets.append(line)

    # Merch branch
    merch_screen = clean(row.get("MERCH_SCREENER_DESC"))
    merch_intent = clean(row.get("MERCH_INTENT_DESC"))
    merch_no = clean(row.get("MERCH_NO_DESC"))
    merch_no_other = clean(row.get("MERCH_NO_OTHERSPECIFY"))
    merch_num = clean(row.get("MERCH_NUMRAT"))
    purchased = bool(merch_screen and merch_screen.lower().startswith("yes"))
    if purchased:
        parts = []
        if merch_num:
            parts.append(f"rated {merch_num}/10")
        for name, col in [
            ("quality", "MERCH_GRID_MERCHQUALITY_DESC"),
            ("price", "MERCH_GRID_PRICE_DESC"),
            ("selection", "MERCH_GRID_SELECTION_DESC"),
            ("service", "MERCH_GRID_CUSTSERV_DESC"),
            ("wait", "MERCH_GRID_WAIT_DESC"),
        ]:
            v = clean(row.get(col))
            if v:
                parts.append(f"{name}: {v}")
        bullets.append(
            f"- Merch: Purchased — {'; '.join(parts)}" if parts else "- Merch: Purchased"
        )
    elif merch_no or merch_no_other:
        reason_parts = []
        if merch_no:
            reason_parts.append(f'"{merch_no}"')
        if merch_no_other:
            reason_parts.append(f'"{merch_no_other}"')
        bullets.append(
            f"- Merch: Did not purchase — reason: {' / '.join(reason_parts)}"
        )
    elif merch_intent:
        bullets.append(f"- Merch: Did not purchase — intent signal: {merch_intent}")

    # Top incentive (rank 1) — always a bullet when present
    rank1 = clean(row.get("INCENTIVES_RANK_1_DESC"))
    if rank1:
        bullets.append(f'- Top Incentive: "{rank1}"')

    # Overall comment (verbatim)
    ot = clean(row.get("OVERALL_NUMRAT_OT"))
    if ot:
        bullets.append(f'- Overall comment: "{ot}"')

    # Incentives feedback (verbatim) — placed AFTER overall comment.
    # INCENTIVES_OT is polluted with short numeric survey codes (e.g. "87", "86").
    # Only include when it's an actual open-ended text response.
    inc_ot = clean(row.get("INCENTIVES_OT"))
    if inc_ot and not inc_ot.strip().isdigit():
        bullets.append(f'- Incentives feedback: "{inc_ot}"')

    return bullets


def build_briefing(row) -> str:
    paragraph = build_paragraph(row)
    bullets = build_bullets(row)
    return paragraph + "\n" + "\n".join(bullets)


def main() -> None:
    df = pd.read_csv(SRC, dtype=str, keep_default_na=False)
    df["SALES_BRIEFING"] = df.apply(build_briefing, axis=1)
    df.to_csv(OUT, index=False, quoting=csv.QUOTE_MINIMAL)

    print(f"Wrote {len(df)} rows to {OUT}")
    print(f"Original columns: {len(df.columns) - 1} + 1 new (SALES_BRIEFING)")
    for i in (0, 1, 2, 3):
        print("\n" + "=" * 70)
        print(
            f"Row {i} — {df.iloc[i].get('FIRST_NAME', '?')} {df.iloc[i].get('LAST_NAME', '?')}"
        )
        print("=" * 70)
        print(df.iloc[i]["SALES_BRIEFING"])


if __name__ == "__main__":
    main()
