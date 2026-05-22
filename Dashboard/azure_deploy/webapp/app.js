/* ───────────────────────────────────────────────────────────────────────
   VOC Insights Agent — embedded chat widget
   Talks to the Azure Function proxy, which fronts Snowflake Cortex AI.
   ─────────────────────────────────────────────────────────────────────── */

// IT-provided Function App URL (no trailing slash):
const FUNCTION_URL = "https://rays-voc-proxy-dxf8bahjhhbnh4bx.eastus2-01.azurewebsites.net";

const CHAT_ENDPOINT    = FUNCTION_URL + "/api/chat";
const SUMMARY_ENDPOINT = FUNCTION_URL + "/api/summary";
const HEALTH_ENDPOINT  = FUNCTION_URL + "/api/health";

const MAX_HISTORY = 10;

const STARTER_QUESTIONS = [
  "What was Concessions Rating on 5/20/2026?",
  "Show me our NPS trend this season.",
  "What percentage of fans are promoters vs detractors?",
];

// ─── State ─────────────────────────────────────────────────────────────
const state = {
  messages:   [],   // for rendering: [{ role, html, df?, results?, suggestions?, details?, sqlFailed? }]
  apiHistory: [],   // Cortex Analyst conversation context (pairs)
  busy:       false,
  turns:      0,
};

// ─── DOM ───────────────────────────────────────────────────────────────
const $chat       = document.getElementById("chat");
const $messages   = document.getElementById("messages");
const $messagesCol= document.getElementById("messages-col");
const $dataPanel  = document.getElementById("data-panel");
const $starters   = document.getElementById("starters");
const $startBtns  = document.getElementById("starter-buttons");
const $loading    = document.getElementById("loading");
const $input      = document.getElementById("question");
const $send       = document.getElementById("send-btn");
const $clear      = document.getElementById("clear-btn");
const $status     = document.getElementById("status-bar");

const DATA_PANEL_EMPTY_HTML =
  '<div class="data-panel-empty">Results, charts, and feedback will appear here.</div>';

// True when the iframe is landscape-shaped (wider than ~5:4). Used to route
// data renderings into the right-hand pane instead of inline in the chat.
const isLandscape = () => window.matchMedia("(min-aspect-ratio: 5/4)").matches;

// ─── Init ──────────────────────────────────────────────────────────────
function init() {
  renderStarters();
  $send.addEventListener("click", onSendClick);
  $input.addEventListener("keydown", e => {
    if (e.key === "Enter" && !e.shiftKey) {
      e.preventDefault();
      onSendClick();
    }
  });
  $clear.addEventListener("click", clearChat);
  warmFunction();
}

function warmFunction() {
  // Fire-and-forget ping so the first real question doesn't pay the
  // cold-start tax on the Function App.
  fetch(HEALTH_ENDPOINT, { method: "GET", mode: "cors" }).catch(() => {});
}

// ─── Rendering ─────────────────────────────────────────────────────────
function renderStarters() {
  $startBtns.innerHTML = "";
  STARTER_QUESTIONS.forEach(q => {
    const btn = document.createElement("button");
    btn.textContent = q;
    btn.addEventListener("click", () => askQuestion(q));
    $startBtns.appendChild(btn);
  });
}

function hideStarters() {
  $starters.classList.add("hidden");
}

function escapeHtml(s) {
  return String(s ?? "")
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#39;");
}

function renderMessage(msg) {
  const wrap = document.createElement("div");
  wrap.className = "msg-wrap";
  if (msg.id) wrap.dataset.msgId = msg.id;

  const lbl = document.createElement("div");
  lbl.className = "msg-lbl";
  lbl.textContent = msg.role === "user" ? "You" : "VOC Agent";
  wrap.appendChild(lbl);

  const bubble = document.createElement("div");
  bubble.className = msg.role === "user" ? "msg-user" : "msg-agent";
  if (msg.role === "user") {
    bubble.textContent = msg.content;
  } else {
    bubble.innerHTML = msg.content || "Here are your results.";
    if (msg.summaryPending) {
      const dots = document.createElement("span");
      dots.className = "summary-pending";
      dots.innerHTML = '<span class="dot"></span><span class="dot"></span><span class="dot"></span>';
      bubble.appendChild(document.createTextNode(" "));
      bubble.appendChild(dots);
    }
  }
  if (msg.id) bubble.dataset.bubbleId = msg.id;
  wrap.appendChild(bubble);
  $messages.appendChild(wrap);

  // Route data renderings: inline in the chat (portrait) OR into the right-hand
  // data panel that refreshes each turn (landscape). The chat text bubble stays
  // in the messages column in both modes.
  const dataTarget = isLandscape() ? $dataPanel : $messages;
  if (msg.df && isLandscape()) {
    $dataPanel.innerHTML = "";  // latest-answer-wins: clear previous data
  }
  if (msg.df) {
    if (msg.dataKind === "feedback") {
      dataTarget.appendChild(renderFeedback(msg.df));
    } else if (msg.dataKind === "chart") {
      dataTarget.appendChild(renderBarChart(msg.df));
    } else if (isSingleNumeric(msg.df)) {
      dataTarget.appendChild(renderHero(msg.df));
    } else {
      dataTarget.appendChild(renderDataframe(msg.df));
    }
  }

  // SQL failure note — stays with the bubble in the chat column
  if (msg.sqlFailed) {
    const note = document.createElement("div");
    note.className = "sql-failed-note";
    note.textContent = "⚠️ I understood your question but couldn't retrieve data. " +
                       "Try rephrasing, or the field may not be available for this date range.";
    $messages.appendChild(note);
  }

  // Technical details (collapsed) — tagged with msg.id so we can update it
  // when the async summary swap moves the interpretation back into details.
  if (msg.details || msg.id) {
    const det = document.createElement("details");
    det.className = "tech";
    if (msg.id) det.dataset.forMsg = msg.id;
    const sum = document.createElement("summary");
    sum.textContent = "ℹ️ Technical details";
    det.appendChild(sum);
    const pre = document.createElement("pre");
    pre.textContent = (msg.details || "").slice(0, 3000);
    det.appendChild(pre);
    if (!msg.details) det.style.display = "none";  // hide until populated
    $messages.appendChild(det);
  }

  // Suggestion buttons
  if (msg.suggestions && msg.suggestions.length) {
    const sg = document.createElement("div");
    sg.className = "suggestions";
    msg.suggestions.slice(0, 3).forEach(text => {
      const btn = document.createElement("button");
      btn.textContent = text;
      btn.addEventListener("click", () => askQuestion(text));
      sg.appendChild(btn);
    });
    $messages.appendChild(sg);
  }
}

function renderDataframe(df) {
  const wrap = document.createElement("div");
  wrap.className = "df-wrap";
  const table = document.createElement("table");
  const thead = document.createElement("thead");
  const trh = document.createElement("tr");
  df.columns.forEach(c => {
    const th = document.createElement("th");
    th.textContent = c;
    trh.appendChild(th);
  });
  thead.appendChild(trh);
  table.appendChild(thead);
  const tbody = document.createElement("tbody");
  df.rows.forEach(row => {
    const tr = document.createElement("tr");
    row.forEach(v => {
      const td = document.createElement("td");
      td.textContent = v === null || v === undefined ? "" : String(v);
      tr.appendChild(td);
    });
    tbody.appendChild(tr);
  });
  table.appendChild(tbody);
  wrap.appendChild(table);
  return wrap;
}

function isSingleNumeric(df) {
  if (!df || !df.rows || df.rows.length !== 1) return false;
  if (!df.columns || df.columns.length !== 1) return false;
  const v = df.rows[0][0];
  return typeof v === "number" || (typeof v === "string" && /^-?\d+(\.\d+)?$/.test(v));
}

function renderHero(df) {
  const value = df.rows[0][0];
  const label = df.columns[0];
  const wrap = document.createElement("div");
  wrap.className = "hero-wrap";
  const num = document.createElement("div");
  num.className = "hero-num";
  num.textContent = typeof value === "number"
    ? (Number.isInteger(value) ? value.toLocaleString() : value.toFixed(2))
    : value;
  const lbl = document.createElement("div");
  lbl.className = "hero-lbl";
  lbl.textContent = label.replace(/_/g, " ").toLowerCase();
  wrap.appendChild(num);
  wrap.appendChild(lbl);
  return wrap;
}

// ─── SVG bar chart (auto-rendered when backend tags data_kind === 'chart') ──
function formatChartLabel(raw) {
  const s = String(raw ?? "");
  // ISO date / timestamp → YYYY-MM-DD (or YYYY-MM if it's clearly a month aggregate)
  const m = s.match(/^(\d{4})-(\d{2})-(\d{2})/);
  if (m) return m[3] === "01" ? `${m[1]}-${m[2]}` : `${m[1]}-${m[2]}-${m[3]}`;
  return s.length > 16 ? s.slice(0, 15) + "…" : s;
}

function renderBarChart(df) {
  const wrap = document.createElement("div");
  wrap.className = "chart-wrap";

  // Sort descending by numeric value, cap at top 20
  const pairs = df.rows
    .map(r => [String(r[0] ?? ""), Number(r[1])])
    .filter(([, v]) => Number.isFinite(v))
    .sort((a, b) => b[1] - a[1])
    .slice(0, 20);

  if (!pairs.length) {
    wrap.textContent = "Chart data unavailable.";
    return wrap;
  }

  const max  = Math.max(...pairs.map(p => p[1]));
  const min  = Math.min(0, ...pairs.map(p => p[1]));
  const span = max - min || 1;

  const W           = 360;
  const ROW_H       = 22;
  const LABEL_W     = 110;
  const VAL_W       = 50;
  const BAR_AREA_W  = W - LABEL_W - VAL_W - 8;
  const H           = ROW_H * pairs.length + 12;

  const svg = document.createElementNS("http://www.w3.org/2000/svg", "svg");
  svg.setAttribute("width",  "100%");
  svg.setAttribute("viewBox", `0 0 ${W} ${H}`);
  svg.setAttribute("preserveAspectRatio", "xMinYMin meet");
  svg.classList.add("voc-chart");

  pairs.forEach(([label, value], i) => {
    const y      = 8 + i * ROW_H;
    const width  = ((value - min) / span) * BAR_AREA_W;

    // Category label — format ISO dates nicely, truncate long strings
    const formatted = formatChartLabel(label);
    const labelEl = document.createElementNS("http://www.w3.org/2000/svg", "text");
    labelEl.setAttribute("x", 0);
    labelEl.setAttribute("y", y + ROW_H / 2 + 4);
    labelEl.setAttribute("class", "chart-label");
    labelEl.textContent = formatted;
    if (label !== formatted) {
      const title = document.createElementNS("http://www.w3.org/2000/svg", "title");
      title.textContent = label;
      labelEl.appendChild(title);
    }
    svg.appendChild(labelEl);

    // Bar
    const bar = document.createElementNS("http://www.w3.org/2000/svg", "rect");
    bar.setAttribute("x", LABEL_W);
    bar.setAttribute("y", y + 3);
    bar.setAttribute("width",  Math.max(width, 1));
    bar.setAttribute("height", ROW_H - 8);
    bar.setAttribute("rx", 2);
    bar.setAttribute("class", "chart-bar");
    svg.appendChild(bar);

    // Value label
    const valEl = document.createElementNS("http://www.w3.org/2000/svg", "text");
    valEl.setAttribute("x", LABEL_W + width + 4);
    valEl.setAttribute("y", y + ROW_H / 2 + 4);
    valEl.setAttribute("class", "chart-value");
    valEl.textContent = Number.isInteger(value)
      ? value.toLocaleString()
      : value.toFixed(2);
    svg.appendChild(valEl);
  });

  // Axis labels at top
  const xAxis = document.createElementNS("http://www.w3.org/2000/svg", "text");
  xAxis.setAttribute("x", LABEL_W);
  xAxis.setAttribute("y", 4);
  xAxis.setAttribute("class", "chart-axis");
  xAxis.textContent = df.columns[1].replace(/_/g, " ").toLowerCase();
  svg.appendChild(xAxis);

  wrap.appendChild(svg);

  // Total count caption when truncated
  if (df.rows.length > pairs.length) {
    const caption = document.createElement("div");
    caption.className = "chart-caption";
    caption.textContent = `Top ${pairs.length} of ${df.rows.length} ${df.columns[0].replace(/_/g, " ").toLowerCase()} values.`;
    wrap.appendChild(caption);
  }

  return wrap;
}

// ─── Feedback cards (auto-rendered when backend tags data_kind === 'feedback') ──
const TEXT_HINTS      = ["SENTENCE_TEXT", "FEEDBACK_TEXT", "COMMENT", "COMMENTS",
                         "FREE_TEXT", "VERBATIM", "OVERALL_NUMRAT_OT", "OVERALL_FEEDBACK"];
const TEXT_SUFFIXES   = ["_FEEDBACK", "_COMMENT", "_COMMENTS", "_TEXT", "_DESC",
                         "_SPECIFY", "_VERBATIM", "_NUMRAT_OT"];
const SENTIMENT_HINTS = ["SENTIMENT_CATEGORY", "SENTIMENT"];
const DATE_HINTS      = ["GAME_DATE", "DATE", "RESPONSE_DATE"];
const CATEGORY_HINTS  = ["AI_CATEGORY", "CATEGORY", "TOPIC", "AI_PARENT_TOPIC"];

function findColumn(df, hints) {
  const upper = df.columns.map(c => c.toUpperCase());
  for (const h of hints) {
    const idx = upper.indexOf(h);
    if (idx !== -1) return idx;
  }
  return -1;
}

function findTextColumn(df) {
  const upper = df.columns.map(c => c.toUpperCase());
  const candidates = [];
  for (let i = 0; i < upper.length; i++) {
    if (TEXT_HINTS.includes(upper[i]) || TEXT_SUFFIXES.some(s => upper[i].endsWith(s))) {
      candidates.push(i);
    }
  }
  if (candidates.length === 0) return -1;
  if (candidates.length === 1) return candidates[0];
  // Multiple candidates → pick the one with the longest average string length
  // (so we pick "OVERALL_FEEDBACK" over "CONCESSIONS_SPECIFIC_FEEDBACK" when
  // the latter holds short IDs).
  const sample = df.rows.slice(0, 30);
  let best = candidates[0], bestAvg = -1;
  for (const i of candidates) {
    const lens = sample.map(r => (r[i] == null ? 0 : String(r[i]).length));
    const avg  = lens.reduce((a, b) => a + b, 0) / Math.max(lens.length, 1);
    if (avg > bestAvg) { bestAvg = avg; best = i; }
  }
  return best;
}

function renderFeedback(df) {
  const textIdx      = findTextColumn(df);
  const sentimentIdx = findColumn(df, SENTIMENT_HINTS);
  const dateIdx      = findColumn(df, DATE_HINTS);
  const categoryIdx  = findColumn(df, CATEGORY_HINTS);

  // Fallback to table if we can't identify a text column
  if (textIdx === -1) return renderDataframe(df);

  const sentimentClass = { Positive: "pos", Negative: "neg", Neutral: "neu" };
  const sentimentBadge = { Positive: "✅", Negative: "❌", Neutral: "➖" };

  const wrap = document.createElement("div");
  const hdr = document.createElement("div");
  hdr.className = "fb-header";
  hdr.innerHTML = `<b>${df.rows.length} excerpt${df.rows.length === 1 ? "" : "s"}:</b>`;
  wrap.appendChild(hdr);

  df.rows.slice(0, 25).forEach(row => {
    const text      = row[textIdx];
    const sentiment = sentimentIdx >= 0 ? row[sentimentIdx] : "";
    const date      = dateIdx      >= 0 ? row[dateIdx]      : "";
    const category  = categoryIdx  >= 0 ? row[categoryIdx]  : "";

    const card = document.createElement("div");
    card.className = "fb-card " + (sentimentClass[sentiment] || "");

    const meta = document.createElement("div");
    meta.className = "fb-meta";
    const badge = sentimentBadge[sentiment] || "💬";
    const parts = [badge + " " + (sentiment || "Feedback")];
    if (date)     parts.push(String(date).slice(0, 10));
    if (category) parts.push(category);
    meta.textContent = parts.join(" · ");
    card.appendChild(meta);

    const body = document.createElement("div");
    body.textContent = text || "—";
    card.appendChild(body);

    wrap.appendChild(card);
  });

  if (df.rows.length > 25) {
    const more = document.createElement("div");
    more.className = "fb-header";
    more.textContent = `Showing first 25 of ${df.rows.length} excerpts.`;
    wrap.appendChild(more);
  }

  return wrap;
}

function updateStatus() {
  $status.textContent =
    `Session: ${state.turns} question(s) · ` +
    `History: ${Math.min(state.turns, MAX_HISTORY)} / ${MAX_HISTORY} · ` +
    `SQL rows capped at 200 · Snowflake Cortex`;
}

function scrollToBottom() {
  // In landscape the messages column scrolls independently; in portrait the
  // whole chat area scrolls. Cover both.
  if ($messagesCol) $messagesCol.scrollTop = $messagesCol.scrollHeight;
  $chat.scrollTop = $chat.scrollHeight;
  if ($dataPanel) $dataPanel.scrollTop = 0;  // show new data from top
}

function setBusy(b) {
  state.busy = b;
  $send.disabled = b;
  $input.disabled = b;
  $loading.classList.toggle("hidden", !b);
  if (b) scrollToBottom();
}

// ─── Send flow ─────────────────────────────────────────────────────────
function onSendClick() {
  const q = $input.value.trim();
  if (!q || state.busy) return;
  $input.value = "";
  askQuestion(q);
}

async function askQuestion(question) {
  hideStarters();
  state.turns += 1;

  // Drop any prior suggestion buttons (only the latest answer keeps them).
  document.querySelectorAll(".suggestions").forEach(el => el.remove());

  state.messages.push({ role: "user", content: question });
  renderMessage(state.messages[state.messages.length - 1]);
  updateStatus();
  scrollToBottom();

  setBusy(true);

  try {
    const resp = await fetch(CHAT_ENDPOINT, {
      method: "POST",
      mode: "cors",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        question,
        history: state.apiHistory,
      }),
    });

    if (!resp.ok) {
      const errText = await resp.text();
      throw new Error(`HTTP ${resp.status}: ${errText.slice(0, 300)}`);
    }

    const data = await resp.json();
    const msg  = handleAgentResponse(data, question);

    // Streaming summary: kick off Cortex Complete fetch *after* data renders.
    // Skip when there's nothing to summarize (no data, single-value hero, or
    // SQL failed). Result lands in msg.content when ready.
    if (
      msg && data.type === "analyst" && data.data
      && data.data.rows && data.data.rows.length
      && !isSingleNumeric(data.data)
      && !data.sql_failed
    ) {
      fetchSummaryAsync(msg, question, data);
    }
  } catch (err) {
    state.messages.push({
      role: "agent",
      content: `⚠️ Something went wrong: ${escapeHtml(err.message)}`,
    });
    renderMessage(state.messages[state.messages.length - 1]);
  } finally {
    setBusy(false);
    updateStatus();
    scrollToBottom();
  }
}

async function fetchSummaryAsync(msg, question, chatData) {
  try {
    const resp = await fetch(SUMMARY_ENDPOINT, {
      method: "POST",
      mode: "cors",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        question,
        interpretation: chatData.interpretation || "",
        data:           chatData.data,
        data_kind:      chatData.data_kind || "metric",
        sql:            chatData.sql || "",
      }),
    });
    if (!resp.ok) throw new Error(`HTTP ${resp.status}`);
    const body = await resp.json();
    const summary = (body.summary || "").trim();
    msg.summaryPending = false;
    if (summary) {
      msg.content = summary;
      // Pull the interpretation back into details since the summary is now the bubble
      if (chatData.interpretation && !msg.details.includes("Interpretation:")) {
        msg.details = ("Interpretation: " + chatData.interpretation + "\n\n" + msg.details).trim();
      }
    }
    updateBubble(msg);
  } catch (err) {
    msg.summaryPending = false;
    updateBubble(msg);
    console.warn("Summary fetch failed:", err);
  }
}

function updateBubble(msg) {
  const bubble = document.querySelector(`[data-bubble-id="${msg.id}"]`);
  if (bubble) {
    bubble.innerHTML = msg.content || "Here are your results.";
    if (msg.summaryPending) {
      const dots = document.createElement("span");
      dots.className = "summary-pending";
      dots.innerHTML = '<span class="dot"></span><span class="dot"></span><span class="dot"></span>';
      bubble.appendChild(document.createTextNode(" "));
      bubble.appendChild(dots);
    }
  }
  // Update the Technical details expander tied to this message
  const det = document.querySelector(`details.tech[data-for-msg="${msg.id}"]`);
  if (det) {
    det.querySelector("pre").textContent = (msg.details || "").slice(0, 3000);
    det.style.display = msg.details ? "" : "none";
  }
}

function handleAgentResponse(data, question) {
  // Two-stage rendering for SI-like UX:
  //   1) Initial render: interpretation + data table/chart/cards shown immediately
  //      (~5-7s from question submit). User sees the answer materializing.
  //   2) Async render: when /api/summary returns, the bubble text swaps to the
  //      natural-language summary and the interpretation tucks into Technical Details.
  // Single-value answers (hero number) skip the summary fetch entirely — the number
  // is the answer.
  const willStream =
    data.type === "analyst" && data.data && data.data.rows && data.data.rows.length
    && !isSingleNumeric(data.data) && !data.sql_failed;

  // First-paint bubble text: interpretation if available, fallback to a generic line.
  const initialBody =
    data.interpretation ||
    data.text ||
    (data.sql_failed ? "Here is what I found." : "Here are your results.");

  const warnings = (data.warnings || []).filter(Boolean);
  const detailsParts = [];
  if (data.details) detailsParts.push(data.details);
  if (warnings.length) {
    detailsParts.push("--- Cortex warnings ---\n" + warnings.join("\n"));
  }

  const msg = {
    id:             "m_" + Date.now() + "_" + Math.random().toString(36).slice(2, 7),
    role:           "agent",
    content:        initialBody,
    summaryPending: willStream,
    df:             data.data || null,
    dataKind:       data.data_kind || "metric",
    suggestions:    data.suggestions || [],
    details:        detailsParts.join("\n\n"),
    sqlFailed:      !!data.sql_failed,
  };
  state.messages.push(msg);
  renderMessage(msg);

  // Append history for follow-up context (mirrors voc_chat_app.py)
  if (data.history_update && data.history_update.length) {
    state.apiHistory.push(...data.history_update);
    const cap = MAX_HISTORY * 2;
    if (state.apiHistory.length > cap) {
      state.apiHistory = state.apiHistory.slice(-cap);
    }
  }

  return msg;
}

// ─── Clear chat ────────────────────────────────────────────────────────
function clearChat() {
  state.messages = [];
  state.apiHistory = [];
  state.turns = 0;
  $messages.innerHTML = "";
  if ($dataPanel) $dataPanel.innerHTML = DATA_PANEL_EMPTY_HTML;
  $starters.classList.remove("hidden");
  updateStatus();
}

// ─── Boot ──────────────────────────────────────────────────────────────
init();
