/* ───────────────────────────────────────────────────────────────────────
   VOC Insights Agent — embedded chat widget
   Talks to the Azure Function proxy, which fronts Snowflake Cortex AI.
   ─────────────────────────────────────────────────────────────────────── */

// IT-provided Function App URL (no trailing slash):
const FUNCTION_URL = "https://rays-voc-proxy-dxf8bahjhhbnh4bx.eastus2-01.azurewebsites.net";

const CHAT_ENDPOINT   = FUNCTION_URL + "/api/chat";
const HEALTH_ENDPOINT = FUNCTION_URL + "/api/health";

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

// ─── Markdown → HTML (small, covers what the agent actually emits) ─────
// Handles: ## headings, **bold**, *italic*, `code`, - / * lists, 1. ordered
// lists, | tables |, paragraphs separated by blank lines. HTML is escaped
// first so any literal < > in agent output is safe.
function md2html(text) {
  if (!text) return "";
  const safe = escapeHtml(text);
  return safe.split(/\n\s*\n/).map(_renderBlock).filter(Boolean).join("\n");
}

function _renderBlock(block) {
  block = block.trim();
  if (!block) return "";
  const lines = block.split("\n");

  // ## Heading on first line — render heading, then recurse on the rest
  const headMatch = lines[0].match(/^(#{1,4})\s+(.+)$/);
  if (headMatch) {
    const level = Math.min(headMatch[1].length + 2, 6);
    const head  = `<h${level}>${_renderInline(headMatch[2])}</h${level}>`;
    const rest  = lines.slice(1).join("\n").trim();
    return rest ? head + _renderBlock(rest) : head;
  }

  // Markdown table: row 0 starts with |, row 1 is the |---| separator
  if (lines.length >= 2 && lines[0].trim().startsWith("|") && /^\s*\|[\s\-:|]+\|\s*$/.test(lines[1])) {
    return _renderTable(lines);
  }

  // Pure unordered list
  if (lines.every(l => /^\s*[-*]\s+/.test(l))) {
    return "<ul>" + lines.map(l =>
      `<li>${_renderInline(l.replace(/^\s*[-*]\s+/, ""))}</li>`
    ).join("") + "</ul>";
  }

  // Pure ordered list
  if (lines.every(l => /^\s*\d+\.\s+/.test(l))) {
    return "<ol>" + lines.map(l =>
      `<li>${_renderInline(l.replace(/^\s*\d+\.\s+/, ""))}</li>`
    ).join("") + "</ol>";
  }

  // Label-then-list ("**Foo:**\n- a\n- b") — common in the agent's output
  const firstListIdx = lines.findIndex(l => /^\s*[-*]\s+/.test(l));
  if (firstListIdx > 0 && lines.slice(firstListIdx).every(l => /^\s*[-*]\s+/.test(l))) {
    const label = `<p>${_renderInline(lines.slice(0, firstListIdx).join(" "))}</p>`;
    const list  = "<ul>" + lines.slice(firstListIdx).map(l =>
      `<li>${_renderInline(l.replace(/^\s*[-*]\s+/, ""))}</li>`
    ).join("") + "</ul>";
    return label + list;
  }

  // Default: paragraph, collapsing single newlines to spaces
  return `<p>${_renderInline(lines.join(" "))}</p>`;
}

function _renderInline(text) {
  // Order matters: ** before * (otherwise **foo** misreads as *<em>foo*</em>)
  return text
    .replace(/\*\*([^*\n]+?)\*\*/g, "<strong>$1</strong>")
    .replace(/(^|[^*])\*([^*\s][^*]*?)\*(?!\*)/g, "$1<em>$2</em>")
    .replace(/`([^`]+?)`/g, "<code>$1</code>");
}

function _renderTable(lines) {
  const cells = (line) => line.split("|").slice(1, -1).map(c => c.trim());
  const head  = cells(lines[0]);
  const rows  = lines.slice(2).map(cells);
  let html = '<table class="md-table"><thead><tr>';
  head.forEach(h => html += `<th>${_renderInline(h)}</th>`);
  html += "</tr></thead><tbody>";
  rows.forEach(r => {
    html += "<tr>";
    r.forEach(c => html += `<td>${_renderInline(c)}</td>`);
    html += "</tr>";
  });
  html += "</tbody></table>";
  return html;
}

// ─── SSE parsing ────────────────────────────────────────────────────────
// One block = an `event:` line + a `data:` line, separated by blank lines.
function parseSSEBlock(block) {
  let event = null, data = "";
  for (const line of block.split("\n")) {
    if (line.startsWith("event: ")) event = line.slice(7).trim();
    else if (line.startsWith("data: ")) data = line.slice(6);
  }
  if (!event || data === "") return null;
  if (data.trim() === "[DONE]") return { event: "_done" };
  try {
    return { event, data: JSON.parse(data) };
  } catch (e) {
    return null;  // malformed, skip
  }
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
    // Agent bubble starts empty for streaming msgs; askQuestion() fills it via
    // _refreshStreamingBubble() during the stream and _applyFinalEvent() at
    // the end. For non-streaming msgs (error fallbacks etc.) just render content.
    bubble.innerHTML = msg.content || "";
  }
  if (msg.id) bubble.dataset.bubbleId = msg.id;
  wrap.appendChild(bubble);
  $messages.appendChild(wrap);

  // Note: data table, suggestions, sqlFailed note, and tech-details are NOT
  // rendered here anymore — they're rendered by _renderFinalArtifacts() once
  // the `final` SSE event arrives. This avoids double-rendering during streaming.
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

  // 1) Render the user's question bubble
  state.messages.push({ role: "user", content: question });
  renderMessage(state.messages[state.messages.length - 1]);
  updateStatus();
  scrollToBottom();

  // 2) Pre-render the agent bubble as a placeholder we'll fill via streaming
  const msg = {
    id:          "m_" + Date.now() + "_" + Math.random().toString(36).slice(2, 7),
    role:        "agent",
    content:     "",               // becomes the final markdown HTML
    rawText:     "",               // accumulates text deltas during streaming
    statusLine:  "Planning…",      // shown in the bubble before first text delta
    df:          null,
    dataKind:    "metric",
    suggestions: [],
    details:     "",
    sqlFailed:   false,
    streaming:   true,
  };
  state.messages.push(msg);
  renderMessage(msg);
  const bubble = document.querySelector(`[data-bubble-id="${msg.id}"]`);
  _refreshStreamingBubble(msg, bubble);
  setBusy(true);
  scrollToBottom();

  // 3) Open the SSE stream
  let resp;
  try {
    resp = await fetch(CHAT_ENDPOINT, {
      method: "POST",
      mode:   "cors",
      headers: {
        "Content-Type": "application/json",
        "Accept":       "text/event-stream",
      },
      body: JSON.stringify({ question, history: state.apiHistory }),
    });
  } catch (err) {
    _failBubble(bubble, `⚠️ Network error: ${escapeHtml(err.message)}`);
    setBusy(false);
    return;
  }

  if (!resp.ok) {
    const errText = await resp.text().catch(() => "");
    _failBubble(bubble, `⚠️ HTTP ${resp.status}: ${escapeHtml(errText.slice(0, 200))}`);
    setBusy(false);
    return;
  }

  // 4a) Backwards-compat: if the server returned JSON (e.g., older backend
  // that doesn't honor Accept: text/event-stream), treat it as one synthetic
  // `final` event and skip streaming.
  const contentType = (resp.headers.get("Content-Type") || "").toLowerCase();
  if (!contentType.includes("text/event-stream")) {
    try {
      const data = await resp.json();
      _applyFinalEvent(msg, data, bubble);
    } catch (err) {
      _failBubble(bubble, `⚠️ Bad response: ${escapeHtml(err.message)}`);
    }
    msg.streaming = false;
    setBusy(false);
    updateStatus();
    scrollToBottom();
    return;
  }

  // 4b) Read the stream — parse SSE blocks separated by blank lines
  const reader  = resp.body.getReader();
  const decoder = new TextDecoder("utf-8");
  let buffer = "";

  try {
    while (true) {
      const { value, done } = await reader.read();
      if (done) break;
      buffer += decoder.decode(value, { stream: true });
      let blockEnd;
      while ((blockEnd = buffer.indexOf("\n\n")) !== -1) {
        const block = buffer.slice(0, blockEnd);
        buffer = buffer.slice(blockEnd + 2);
        const evt = parseSSEBlock(block);
        if (evt) _handleStreamEvent(msg, bubble, evt);
      }
    }
  } catch (err) {
    console.warn("stream read error:", err);
  }

  // 5) Finalize — if no `final` event arrived, render whatever raw text we have
  msg.streaming = false;
  if (!msg.content && msg.rawText) {
    msg.content = md2html(msg.rawText);
    if (bubble) bubble.innerHTML = msg.content;
  }
  setBusy(false);
  updateStatus();
  scrollToBottom();
}

function _handleStreamEvent(msg, bubble, evt) {
  const { event, data } = evt;

  if (event === "response.status") {
    msg.statusLine = data.message || msg.statusLine;
    _refreshStreamingBubble(msg, bubble);
  } else if (event === "response.text.delta") {
    msg.rawText += data.text || "";
    _refreshStreamingBubble(msg, bubble);
  } else if (event === "response.thinking.delta") {
    msg.details = (msg.details || "") + (data.text || "");
  } else if (event === "response.suggested_queries") {
    msg.suggestions = (data.suggested_queries || []).map(q => q.query).filter(Boolean);
  } else if (event === "final") {
    _applyFinalEvent(msg, data, bubble);
  } else if (event === "error") {
    msg.streaming = false;
    if (bubble) bubble.innerHTML = `⚠️ ${escapeHtml(data.message || "error")}`;
  }
  // response.tool_use, response.tool_result, response.tool_result.status,
  // response.thinking, response.text, response, _done — intentionally ignored
  // (final event carries everything we need for the post-stream render).
}

function _refreshStreamingBubble(msg, bubble) {
  if (!bubble) return;
  bubble.innerHTML = "";
  if (msg.rawText) {
    // Show streaming raw text so the user sees words arriving live.
    // Markdown formatting is applied at the end (final event) to avoid flicker
    // on partial syntax like '**bo'.
    const span = document.createElement("span");
    span.className = "stream-text";
    span.textContent = msg.rawText;
    bubble.appendChild(span);
  } else {
    // Pre-text phase: show the agent's current status as italic text
    const status = document.createElement("em");
    status.className = "status-line";
    status.textContent = msg.statusLine || "Planning…";
    bubble.appendChild(status);
    bubble.appendChild(document.createTextNode(" "));
  }
  bubble.appendChild(_streamDots());
  // Also update the static loading line at the bottom of the chat
  _updateLoadingText(msg.statusLine);
  scrollToBottom();
}

function _streamDots() {
  const dots = document.createElement("span");
  dots.className = "summary-pending";
  dots.innerHTML = '<span class="dot"></span><span class="dot"></span><span class="dot"></span>';
  return dots;
}

function _applyFinalEvent(msg, data, bubble) {
  msg.rawText     = data.summary || msg.rawText;
  msg.content     = md2html(msg.rawText) || "Here are your results.";
  msg.df          = data.data || null;
  msg.dataKind    = data.data_kind || "metric";
  msg.suggestions = data.suggestions || msg.suggestions;
  // Replace details with the server-side aggregated thinking (more complete than
  // our streamed accumulation if the stream got interrupted)
  if (data.details) msg.details = data.details;
  msg.sqlFailed = !!data.sql_failed;
  msg.streaming = false;

  // History — server sends user + assistant pair we should append for follow-ups
  if (data.history_update && data.history_update.length) {
    state.apiHistory.push(...data.history_update);
    const cap = MAX_HISTORY * 2;
    if (state.apiHistory.length > cap) state.apiHistory = state.apiHistory.slice(-cap);
  }

  // Final bubble render — full markdown
  if (bubble) bubble.innerHTML = msg.content;

  // Render data, suggestions, tech details below the bubble
  _renderFinalArtifacts(msg);
}

function _renderFinalArtifacts(msg) {
  const dataTarget = isLandscape() ? $dataPanel : $messages;
  if (msg.df && isLandscape()) {
    $dataPanel.innerHTML = "";  // latest-answer-wins
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

  if (msg.sqlFailed) {
    const note = document.createElement("div");
    note.className = "sql-failed-note";
    note.textContent = "⚠️ I understood your question but couldn't retrieve data. " +
                       "Try rephrasing, or the field may not be available for this date range.";
    $messages.appendChild(note);
  }

  if (msg.details) {
    const det = document.createElement("details");
    det.className = "tech";
    det.dataset.forMsg = msg.id;
    const sum = document.createElement("summary");
    sum.textContent = "ℹ️ Technical details";
    det.appendChild(sum);
    const pre = document.createElement("pre");
    pre.textContent = msg.details.slice(0, 3000);
    det.appendChild(pre);
    $messages.appendChild(det);
  }

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

function _failBubble(bubble, html) {
  if (bubble) bubble.innerHTML = html;
}

function _updateLoadingText(text) {
  const el = document.querySelector("#loading .loading-text");
  if (el) el.textContent = text || "Analyzing…";
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
