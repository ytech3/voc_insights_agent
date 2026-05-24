// Smoke test for the markdown parser used by app.js.
// Extracts the helpers and runs them against the actual agent output from
// yesterday's AC question. Run with: node smoke_md2html.js

const fs = require("fs");
const path = require("path");

const APP_JS = path.join(__dirname, "..", "azure_deploy", "webapp", "app.js");
const src = fs.readFileSync(APP_JS, "utf-8");

// Evaluate just the helpers we want — they're standalone, no DOM deps.
// Match each function block by name.
function extractFn(name) {
  // greedy match to next top-level function or `// ─` block divider
  const re = new RegExp(`function\\s+${name}\\s*\\([^)]*\\)\\s*\\{[\\s\\S]*?\\n\\}`, "m");
  const m = src.match(re);
  if (!m) throw new Error(`could not extract function ${name}`);
  return m[0];
}

// Load helpers into this module's scope
eval(extractFn("escapeHtml"));
eval(extractFn("md2html"));
eval(extractFn("_renderBlock"));
eval(extractFn("_renderInline"));
eval(extractFn("_renderTable"));

const sample = `On **May 17, 2026**, air conditioning was a significant pain point for fans. Here's the breakdown:

## Air Conditioning Complaints Summary

**Supporting Metrics:**
- **30 unique fans** complained about AC/heat (out of 312 total feedback responses = **9.62%**)
- **50 negative sentences** specifically about air conditioning
- **8 neutral mentions** (acknowledging heat but balanced with positive experiences)

## Key Themes from Fan Complaints:

**1. AC Perceived as Not Working:**
- *"Was the AC even on?"*
- *"It felt like the air conditioning was not on"*

| Date | Avg Satisfaction | Responses |
|------|------------------|-----------|
| May 15 | 9.34 | 310 |
| May 16 | 8.85 | 494 |

Use \`COUNT(*)\` for the total.`;

console.log("=== Input markdown ===");
console.log(sample.slice(0, 200) + "...\n");

console.log("=== Output HTML ===");
const html = md2html(sample);
console.log(html);

// Quick assertions
const checks = [
  { match: /<strong>May 17, 2026<\/strong>/, name: "bold dates" },
  { match: /<h4>Air Conditioning Complaints Summary<\/h4>/, name: "h4 from ##" },
  { match: /<ul><li><strong>30 unique fans/, name: "bullet with nested bold" },
  { match: /<em>"Was the AC even on\?"<\/em>/, name: "italic quote" },
  { match: /<table class="md-table">/, name: "table opens" },
  { match: /<th>Date<\/th>/, name: "table header" },
  { match: /<td>May 15<\/td><td>9.34<\/td><td>310<\/td>/, name: "table row" },
  { match: /<code>COUNT\(\*\)<\/code>/, name: "inline code" },
];

let passed = 0;
let failed = 0;
console.log("\n=== Assertions ===");
for (const c of checks) {
  if (c.match.test(html)) {
    console.log(`  [PASS] ${c.name}`);
    passed++;
  } else {
    console.log(`  [FAIL] ${c.name}`);
    failed++;
  }
}

console.log(`\n${passed} passed, ${failed} failed`);
process.exit(failed === 0 ? 0 : 1);
