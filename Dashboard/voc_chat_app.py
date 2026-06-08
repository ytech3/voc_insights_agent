# ┌─────────────────────────────────────────────────────────────────┐
# │  VOC Insights Agent — Tampa Bay Rays                            │
# │  Streamlit in Snowflake (SiS) · Tableau Cloud Embedded Chat    │
# │  v2.0 · 2026-05-18                                             │
# └─────────────────────────────────────────────────────────────────┘
#
# PASTE THIS ENTIRE FILE into the Snowsight Streamlit editor.
# Do NOT click Run until all content is pasted.
#
# NOTE: If Cortex Search returns no results, open the Packages tab
# in the Snowsight editor and confirm "snowflake-core" is listed.
# If missing, search for it and click Add.

from __future__ import annotations  # REQUIRED — keeps Python 3.8 compatible with type hints

import json
import pandas as pd
import streamlit as st
import _snowflake
from snowflake.snowpark.context import get_active_session

# ── CONSTANTS ─────────────────────────────────────────────────────────────────

SEMANTIC_MODEL  = "@TBRDP_DW_PROD.LOAD.CORTEX_SEMANTIC_MODELS/voc_semantic_model.yaml"
DB              = "TBRDP_DW_DEV"
SCHEMA          = "IM_RPT"
SEARCH_SERVICE  = "VOC_FEEDBACK_SEARCH"
ANALYST_API     = "/api/v2/cortex/analyst/message"

MAX_HISTORY     = 10   # messages sent to Cortex Analyst per call (cost guardrail)
SQL_ROW_LIMIT   = 200  # row cap injected into generated SQL
SEARCH_LIMIT    = 8    # feedback excerpts per search query

NAVY  = "#092C5C"
BLUE  = "#8FBCE6"
WHITE = "#FFFFFF"

# Words that route to Cortex Search (qualitative) instead of Cortex Analyst (metrics)
SEARCH_TRIGGERS = {
    "feedback", "comment", "comments", "said", "saying", "think", "thought",
    "mentioned", "mention", "complain", "complaint", "praise", "quote", "wrote",
    "response", "responses", "show me", "examples", "verbatim", "what do fans",
    "fan said", "what fans", "telling us", "what are fans", "opinions", "feelings",
    "hear", "heard", "tell me", "reviews"
}

STARTER_QUESTIONS = [
    "What was average overall satisfaction last homestand?",
    "Which feedback topic had the most negative sentiment?",
    "What are fans saying about concessions?",
    "Show me our NPS trend this season.",
    "What percentage of fans are promoters vs detractors?",
]

# ── PAGE CONFIG  (must be first Streamlit call) ───────────────────────────────

st.set_page_config(
    page_title="VOC Insights Agent",
    page_icon="⚾",
    layout="wide",
    initial_sidebar_state="collapsed",
)

# ── CSS ───────────────────────────────────────────────────────────────────────

st.markdown(
    f"""
    <style>
      .block-container {{
        padding: 0.4rem 0.8rem !important;
        max-width: 100% !important;
      }}
      .voc-header {{
        background: {NAVY};
        color: {WHITE};
        padding: 10px 14px;
        border-radius: 8px 8px 0 0;
        display: flex;
        align-items: center;
        gap: 10px;
        margin-bottom: 6px;
      }}
      .voc-title {{ margin: 0; font-size: 14px; font-weight: 700; color: {WHITE}; }}
      .voc-sub   {{ font-size: 10px; color: {BLUE}; margin: 0; }}
      .msg-wrap  {{ margin: 3px 0; }}
      .msg-lbl   {{ font-size: 10px; color: #999; margin-bottom: 1px; }}
      .msg-user  {{
        background: {NAVY}; color: {WHITE};
        padding: 7px 11px; border-radius: 12px 12px 2px 12px;
        margin-left: 20%; font-size: 13px; line-height: 1.4;
      }}
      .msg-agent {{
        background: {WHITE}; color: #1A1A2E;
        border: 1px solid #DDE4F0;
        padding: 7px 11px; border-radius: 12px 12px 12px 2px;
        margin-right: 20%; font-size: 13px; line-height: 1.4;
      }}
      .fb-card {{
        background: {WHITE};
        border-left: 3px solid {BLUE};
        padding: 6px 10px; margin: 4px 0;
        border-radius: 0 6px 6px 0; font-size: 12px;
      }}
      .fb-meta  {{ font-size: 10px; color: #888; margin-bottom: 3px; }}
      .pos {{ border-left-color: #27AE60; }}
      .neg {{ border-left-color: #E74C3C; }}
      .neu {{ border-left-color: #95A5A6; }}
      .status-bar {{
        font-size: 10px; color: #aaa; text-align: center;
        margin-top: 6px; border-top: 1px solid #eee; padding-top: 4px;
      }}
      #MainMenu {{ visibility: hidden; }}
      footer    {{ visibility: hidden; height: 0; }}
      header    {{ visibility: hidden; height: 0; }}
    </style>
    """,
    unsafe_allow_html=True,
)

# ── HELPERS ───────────────────────────────────────────────────────────────────

def rerun():
    """Rerun the app — handles both current and legacy Streamlit API."""
    try:
        st.rerun()
    except AttributeError:
        st.experimental_rerun()


def route(text: str) -> str:
    """Return 'search' for qualitative questions, 'analyst' for metrics."""
    words = set(text.lower().split())
    return "search" if words & SEARCH_TRIGGERS else "analyst"


def clean_analyst_text(raw: str) -> tuple:
    """Split Cortex Analyst text into user-facing interpretation and
    verbose technical details (duplicate synonym warnings, SQL debug info).
    Returns (display_text, technical_details).
    """
    # These markers signal the start of verbose Cortex Analyst debug output
    verbose_markers = [
        "ℹ️ The following SQL expressions",   # ℹ️ unquoted column warning
        "The SQL generated initially",                   # SQL self-correction debug
        "Your semantic model is larger",                 # model size warning
        "The following synonyms are duplicated",         # synonym duplicate warning
    ]
    cut = len(raw)
    for marker in verbose_markers:
        idx = raw.find(marker)
        if 0 < idx < cut:
            cut = idx

    display = raw[:cut].strip()
    details = raw[cut:].strip()
    return display, details


# ── SNOWFLAKE SESSION ─────────────────────────────────────────────────────────

@st.cache_resource
def get_session():
    s = get_active_session()
    try:
        s.sql("ALTER SESSION SET QUERY_TAG = 'VOC_STREAMLIT_TABLEAU'").collect()
    except Exception:
        pass
    return s


session = get_session()

# ── SESSION STATE ─────────────────────────────────────────────────────────────

if "messages"    not in st.session_state:
    st.session_state.messages    = []
if "api_history" not in st.session_state:
    st.session_state.api_history = []
if "started"     not in st.session_state:
    st.session_state.started     = False

# ── CORTEX ANALYST ────────────────────────────────────────────────────────────

def call_analyst(question: str) -> dict:
    """Call Cortex Analyst REST API via SiS internal request method."""
    history = list(st.session_state.api_history[-MAX_HISTORY:])
    history.append({
        "role": "user",
        "content": [{"type": "text", "text": question}],
    })
    resp = _snowflake.send_snow_api_request(
        "POST",
        ANALYST_API,
        {},
        {},
        {"messages": history, "semantic_model_file": SEMANTIC_MODEL},
        None,
        45000,
    )
    status = resp.get("status")
    if status != 200:
        raise RuntimeError(
            f"Cortex Analyst HTTP {status}: {resp.get('content', 'no detail')}"
        )
    return json.loads(resp["content"])


def parse_analyst(data: dict) -> tuple:
    """Return (answer_text, sql_str, suggestions_list, warnings_list)."""
    text, sql, suggestions = "", None, []
    for block in data.get("message", {}).get("content", []):
        t = block.get("type", "")
        if t == "text":
            text = block.get("text", "")
        elif t == "sql":
            sql = block.get("statement", "")
        elif t == "suggestions":
            suggestions = block.get("suggestions", [])
    warnings = [w.get("message", "") for w in data.get("warnings", [])]
    return text, sql, suggestions, warnings


def run_sql(sql: str) -> pd.DataFrame:
    """Execute SQL from Cortex Analyst; injects row limit if absent."""
    clean = sql.strip().rstrip(";")
    if "limit" not in clean.lower():
        clean = f"SELECT * FROM ({clean}) _r LIMIT {SQL_ROW_LIMIT}"
    return session.sql(clean).to_pandas()


# ── CORTEX SEARCH ─────────────────────────────────────────────────────────────

def call_search(query: str) -> list:
    """
    Search VOC_FEEDBACK_SEARCH for qualitative feedback.
    Primary:  snowflake.core Python SDK (sentence-level columns)
    Fallback: SQL !SEARCH syntax (if SDK package unavailable)
    """
    # ── Primary: Python SDK ───────────────────────────────────────────────────
    try:
        from snowflake.core import Root  # requires snowflake-core package in SiS
        root = Root(session)
        svc  = root.databases[DB].schemas[SCHEMA].cortex_search_services[SEARCH_SERVICE]

        # Try sentence-level view columns first
        try:
            res = svc.search(
                query=query,
                columns=["sentence_text", "sentiment_category", "game_date", "season"],
                limit=SEARCH_LIMIT,
            )
            return res.results
        except Exception:
            pass

        # Fallback to response-level view columns
        res = svc.search(
            query=query,
            columns=["OVERALL_NUMRAT_OT", "GAME_DATE", "SEASON"],
            limit=SEARCH_LIMIT,
        )
        return res.results

    except ImportError:
        pass  # snowflake-core not installed — use SQL approach below

    # ── Fallback: SQL !SEARCH syntax ──────────────────────────────────────────
    try:
        safe = query.replace("'", "''")[:400]
        df = session.sql(
            f"SELECT * FROM TABLE("
            f"{DB}.{SCHEMA}.{SEARCH_SERVICE}!SEARCH('{safe}', LIMIT => {SEARCH_LIMIT})"
            f")"
        ).to_pandas()
        return df.to_dict("records")
    except Exception as e:
        return [{"_error": str(e)}]


def render_search(results: list) -> str:
    """Format Cortex Search results as HTML feedback cards."""
    if not results:
        return "No matching feedback found. Try broader search terms."
    if results and "_error" in results[0]:
        return (
            f"Search encountered an issue: {results[0]['_error']}<br/>"
            f"<small>Tip: Open the Packages tab in the Snowsight editor "
            f"and confirm <b>snowflake-core</b> is installed.</small>"
        )

    cards = []
    for r in results:
        text      = r.get("sentence_text") or r.get("OVERALL_NUMRAT_OT") or "—"
        sentiment = r.get("sentiment_category", "")
        date      = r.get("game_date") or r.get("GAME_DATE", "")
        season    = r.get("season") or r.get("SEASON", "")
        badge     = {"Positive": "✅", "Negative": "❌", "Neutral": "➖"}.get(sentiment, "💬")
        css       = {"Positive": "pos", "Negative": "neg", "Neutral": "neu"}.get(sentiment, "")
        meta      = f"{badge} {sentiment or 'Feedback'} · {date} · Season {season}"
        cards.append(
            f'<div class="fb-card {css}">'
            f'<div class="fb-meta">{meta}</div>'
            f'{text}'
            f'</div>'
        )

    return f"<b>Found {len(results)} excerpt(s):</b><br/>" + "".join(cards)


# ── MESSAGE RENDERER ──────────────────────────────────────────────────────────

def render_message(msg: dict):
    role  = msg.get("role", "agent")
    label = "You" if role == "user" else "VOC Agent"
    cls   = "msg-user" if role == "user" else "msg-agent"
    body  = msg.get("content", "")

    # For agent messages, separate clean interpretation from verbose debug output
    technical_details = ""
    if role == "agent":
        body, technical_details = clean_analyst_text(body)

    st.markdown(
        f'<div class="msg-wrap">'
        f'<div class="msg-lbl">{label}</div>'
        f'<div class="{cls}">{body}</div>'
        f'</div>',
        unsafe_allow_html=True,
    )

    df = msg.get("dataframe")
    if df is not None and not df.empty:
        st.dataframe(df, use_container_width=True, height=min(200, 45 + len(df) * 35))
    elif role == "agent" and msg.get("sql_failed"):
        st.caption(
            "⚠️ I understood your question but couldn't retrieve data. "
            "Try rephrasing, or the field may not be available for this date range."
        )

    # Show verbose technical details in a collapsed expander (not shown by default)
    if technical_details:
        with st.expander("ℹ️ Technical details", expanded=False):
            st.text(technical_details[:3000])

    suggestions = msg.get("suggestions", [])
    if suggestions:
        cols = st.columns(min(len(suggestions), 3))
        for i, sug in enumerate(suggestions[:3]):
            with cols[i]:
                if st.button(sug, key=f"sug_{hash(sug)}_{i}", use_container_width=True):
                    st.session_state.pending_question = sug
                    rerun()


# ── HEADER ────────────────────────────────────────────────────────────────────

st.markdown(
    f"""
    <div class="voc-header">
      <div style="font-size:22px">⚾</div>
      <div>
        <p class="voc-title">VOC Insights Agent</p>
        <p class="voc-sub">Tampa Bay Rays · Fan Experience Analytics · Powered by Snowflake Cortex</p>
      </div>
    </div>
    """,
    unsafe_allow_html=True,
)

_, clear_col = st.columns([6, 1])
with clear_col:
    if st.button("Clear ↺", use_container_width=True):
        st.session_state.messages    = []
        st.session_state.api_history = []
        st.session_state.started     = False
        rerun()

# ── STARTER PROMPTS ───────────────────────────────────────────────────────────

if not st.session_state.started and not st.session_state.messages:
    st.markdown(
        "<div style='font-size:12px;color:#555;margin:4px 0;'>"
        "Ask anything about fan satisfaction, NPS, feedback topics, or trends — or pick a starter:</div>",
        unsafe_allow_html=True,
    )
    for i in range(0, len(STARTER_QUESTIONS), 2):
        row  = STARTER_QUESTIONS[i : i + 2]
        cols = st.columns(len(row))
        for j, q in enumerate(row):
            with cols[j]:
                if st.button(q, key=f"start_{i}_{j}", use_container_width=True):
                    st.session_state.pending_question = q
                    st.session_state.started = True
                    rerun()

# ── CHAT HISTORY ──────────────────────────────────────────────────────────────

for msg in st.session_state.messages:
    render_message(msg)

# ── RESOLVE PENDING QUESTION (from buttons) ───────────────────────────────────

question = st.session_state.pop("pending_question", None)

# ── CHAT INPUT ────────────────────────────────────────────────────────────────

typed = st.chat_input("Ask about fan satisfaction, NPS, feedback topics…")
if typed:
    question = typed
    st.session_state.started = True

# ── PROCESS QUESTION ──────────────────────────────────────────────────────────

if question:
    st.session_state.messages.append({"role": "user", "content": question})

    with st.spinner("Analyzing…"):
        try:
            if route(question) == "search":
                # ── Cortex Search path (qualitative) ──────────────────────
                results = call_search(question)
                st.session_state.messages.append({
                    "role":    "agent",
                    "content": render_search(results),
                })

            else:
                # ── Cortex Analyst path (metrics / SQL) ───────────────────
                raw  = call_analyst(question)
                text, sql, suggestions, warnings = parse_analyst(raw)

                df         = None
                sql_failed = False
                if sql:
                    try:
                        df = run_sql(sql)
                    except Exception:
                        sql_failed = True
                        sql        = None

                # Update API history for follow-up context
                st.session_state.api_history.append({
                    "role": "user",
                    "content": [{"type": "text", "text": question}],
                })
                if "message" in raw:
                    st.session_state.api_history.append(raw["message"])

                # Trim to MAX_HISTORY pairs
                cap = MAX_HISTORY * 2
                if len(st.session_state.api_history) > cap:
                    st.session_state.api_history = st.session_state.api_history[-cap:]

                if warnings:
                    text += (
                        "<br/><small style='color:#e67e22'>ℹ️ "
                        + "; ".join(w for w in warnings if w)
                        + "</small>"
                    )

                st.session_state.messages.append({
                    "role":        "agent",
                    "content":     text or "Here are your results.",
                    "dataframe":   df,
                    "suggestions": suggestions,
                    "sql_failed":  sql_failed,
                })

        except Exception as err:
            st.session_state.messages.append({
                "role":    "agent",
                "content": f"⚠️ Something went wrong: {err}",
            })

    rerun()

# ── STATUS BAR ────────────────────────────────────────────────────────────────

turns = len([m for m in st.session_state.messages if m["role"] == "user"])
st.markdown(
    f'<div class="status-bar">'
    f"Session: {turns} question(s) · "
    f"History window: {min(turns, MAX_HISTORY)} / {MAX_HISTORY} · "
    f"SQL rows capped at {SQL_ROW_LIMIT} · "
    f"Snowflake Cortex"
    f"</div>",
    unsafe_allow_html=True,
)
