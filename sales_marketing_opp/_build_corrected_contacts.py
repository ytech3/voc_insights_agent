"""
Build a corrected contact list for the shared-account FINANCIAL_IDs that
were cross-wired in Homestand_1_CRM_SalesBriefing_UPDATED (1).csv.

Approach:
  1. Find every FINANCIAL_ID in the briefing sent to sales that has >1
     distinct attendee (first_name + last_name). These are the shared accounts.
  2. For each shared FID, list every attendee from the Qualtrics SOT that
     appears in the briefing, joining on (FINANCIAL_ID, FIRST_NAME, LAST_NAME)
     because the briefing's name field was NOT corrupted (only email/order/
     ticket were overwritten by the FINANCIAL_ID-only lookup bug).
  3. Output CORRECT email/order_id/ticket_id from the SOT, alongside the
     values that were actually sent to sales, plus a CONTACT_DECISION flag.

CONTACT_DECISION heuristic:
  - DO NOT CONTACT - Suite holder       : buyer_type == 'Suite'
  - DO NOT CONTACT - corporate domain    : email domain not in personal list
  - CONTACT - personal email             : personal email domain
  - REVIEW                               : missing email / ambiguous
"""
from pathlib import Path
import pandas as pd

ROOT = Path(r"C:\Users\ytaketani\voc_insights_agent")
BRIEFING = ROOT / "sales_marketing_opp" / "Homestand_1_CRM_SalesBriefing_UPDATED (1).csv"
SOT = ROOT / "_tmp_sot" / "2026 SGT Post-Attendance Survey (MLB-VOC)_April 13, 2026_16.54.csv"
CRM = ROOT / "game_report" / "Homestand_1_CRM.csv"
OUT = ROOT / "sales_marketing_opp" / "Homestand_1_Corrected_Contacts.csv"

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


def strip_prefix(v):
    if pd.isna(v) or v == "":
        return v
    return str(v).replace("pv_30_", "", 1)


def email_domain(e):
    if not isinstance(e, str) or "@" not in e:
        return ""
    return e.split("@", 1)[1].strip().lower()


def contact_decision(email, buyer_type):
    dom = email_domain(email)
    bt = (buyer_type or "").strip()
    if bt == "Suite":
        return "DO NOT CONTACT - Suite holder"
    if not dom:
        return "REVIEW - missing email"
    if dom in PERSONAL_DOMAINS:
        return "CONTACT - personal email"
    return "DO NOT CONTACT - corporate domain"


def norm_name(s):
    return str(s or "").strip().lower()


# ── Load data ──
brief = pd.read_csv(BRIEFING, dtype=str, encoding="utf-8", encoding_errors="replace").fillna("")
sot = pd.read_csv(SOT, dtype=str, encoding="utf-8", encoding_errors="replace",
                  skiprows=[1, 2]).fillna("")
crm = pd.read_csv(CRM, dtype=str, encoding="utf-8", encoding_errors="replace").fillna("")
print(f"Briefing rows: {len(brief)}  |  SOT rows: {len(sot)}  |  CRM rows: {len(crm)}")

brief["_fid"] = brief["FINANCIAL_ID"].map(strip_prefix)
brief["_first"] = brief["FIRST_NAME"].map(norm_name)
brief["_last"] = brief["LAST_NAME"].map(norm_name)
sot["_fid"] = sot["financial_id"].map(strip_prefix)
sot["_first"] = sot["first_name"].map(norm_name)
sot["_last"] = sot["last_name"].map(norm_name)
crm["_fid"] = crm["FINANCIAL_ID"].map(strip_prefix)
crm["_first"] = crm["FIRST_NAME"].map(norm_name)
crm["_last"] = crm["LAST_NAME"].map(norm_name)

# ── Shared FIDs: FIDs where the briefing has >1 distinct attendee ──
brief["_name"] = brief["_first"] + "|" + brief["_last"]
fid_name_counts = brief.groupby("_fid")["_name"].nunique()
shared_fids = sorted(fid_name_counts[fid_name_counts > 1].index.tolist())
print(f"Shared FINANCIAL_IDs in briefing: {len(shared_fids)}")

# ── Build SOT lookup keyed on (FID, first, last) ──
sot_idx = {}
for _, r in sot.iterrows():
    key = (str(r["_fid"]), r["_first"], r["_last"])
    # If duplicate (same person on multiple games), prefer row with an email
    if key not in sot_idx or (not sot_idx[key]["email"] and r["email"]):
        sot_idx[key] = r.to_dict()

# CRM secondary lookup (for attendees who are in CRM but not in SOT yet)
crm_idx = {}
for _, r in crm.iterrows():
    key = (str(r["_fid"]), r["_first"], r["_last"])
    if key not in crm_idx or (not crm_idx[key].get("EMAIL") and r["EMAIL"]):
        crm_idx[key] = r.to_dict()

# ── Build one row per (FID, attendee) from the briefing ──
rows = []
affected = brief[brief["_fid"].isin(shared_fids)].copy()
# Dedup: unique (FID, first, last) within the briefing universe
unique_attendees = affected.drop_duplicates(subset=["_fid", "_first", "_last"])
print(f"Unique attendees under shared FIDs (the list you asked for): {len(unique_attendees)}")

for _, b in unique_attendees.iterrows():
    key = (b["_fid"], b["_first"], b["_last"])
    sot_hit = sot_idx.get(key)
    crm_hit = crm_idx.get(key, {})

    if sot_hit:
        correct_email = sot_hit.get("email") or sot_hit.get("RecipientEmail") or ""
        correct_order = sot_hit.get("order_id", "")
        correct_ticket = sot_hit.get("ticket_id", "")
        correct_fid = sot_hit.get("financial_id", "")
        correct_attending = sot_hit.get("attending_id", "")
        buyer_type = sot_hit.get("buyer_type", "") or crm_hit.get("BUYER_TYPE", "")
        source = "SOT"
    else:
        correct_email = crm_hit.get("EMAIL", "")
        correct_order = crm_hit.get("ORDER_ID", "")
        correct_ticket = crm_hit.get("TICKET_ID", "")
        correct_fid = crm_hit.get("FINANCIAL_ID", b["FINANCIAL_ID"])
        correct_attending = ""  # CRM doesn't carry attending_id
        buyer_type = crm_hit.get("BUYER_TYPE", "")
        source = "CRM"

    price_scale = crm_hit.get("PRICE_SCALE", "")
    section = crm_hit.get("SECTION_CODE", "")
    decision = contact_decision(correct_email, buyer_type)

    rows.append({
        "FINANCIAL_ID": correct_fid,
        "ATTENDING_ID": correct_attending,
        "FIRST_NAME": sot_hit["first_name"] if sot_hit else (crm_hit.get("FIRST_NAME") or b["FIRST_NAME"]),
        "LAST_NAME": sot_hit["last_name"] if sot_hit else (crm_hit.get("LAST_NAME") or b["LAST_NAME"]),
        "EMAIL_CORRECT": correct_email,
        "EMAIL_AS_SENT_TO_SALES": b["EMAIL"],
        "ORDER_ID_CORRECT": correct_order,
        "ORDER_ID_AS_SENT_TO_SALES": b["ORDER_ID"],
        "TICKET_ID_CORRECT": correct_ticket,
        "TICKET_ID_AS_SENT_TO_SALES": b["TICKET_ID"],
        "BUYER_TYPE": buyer_type,
        "PRICE_SCALE": price_scale,
        "SECTION_CODE": section,
        "ATTEND_NUM_PLAN_DESC": b.get("ATTEND_NUM_PLAN_DESC", ""),
        "CONTACT_DECISION": decision,
        "LOOKUP_SOURCE": source,
    })

out = pd.DataFrame(rows)
out["_sort_decision"] = out["CONTACT_DECISION"].map(
    lambda s: 0 if s.startswith("DO NOT CONTACT") else (1 if s.startswith("CONTACT") else 2)
)
out = out.sort_values(["FINANCIAL_ID", "_sort_decision", "LAST_NAME"]).drop(columns=["_sort_decision"])

out.to_csv(OUT, index=False, encoding="utf-8")
print(f"\nWrote {OUT}")
print(f"Total rows: {len(out)}")
print(f"Distinct FINANCIAL_IDs: {out['FINANCIAL_ID'].nunique()}")
print("\nCONTACT_DECISION breakdown:")
print(out["CONTACT_DECISION"].value_counts().to_string())
print("\nLOOKUP_SOURCE breakdown:")
print(out["LOOKUP_SOURCE"].value_counts().to_string())

print("\n=== Spot check: pv_30_111634 (Rays Partners — Lindsey's account) ===")
cols = ["FINANCIAL_ID", "FIRST_NAME", "LAST_NAME", "EMAIL_CORRECT",
        "EMAIL_AS_SENT_TO_SALES", "ORDER_ID_CORRECT", "TICKET_ID_CORRECT",
        "BUYER_TYPE", "CONTACT_DECISION"]
print(out[out["FINANCIAL_ID"].str.contains("111634", na=False)][cols].to_string())
