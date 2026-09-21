import assert from "node:assert/strict";
import test from "node:test";

import { formatUsageReport } from "../format.ts";
import { normalizeCodexUsage } from "./codex.ts";

test("Codex adapter preserves plan, windows, credits, resets, and model buckets", () => {
  const report = normalizeCodexUsage(
    {
      plan_type: "pro",
      rate_limit: {
        primary_window: {
          used_percent: 60,
          limit_window_seconds: 18_000,
          reset_at: 10_000,
        },
        secondary_window: {
          used_percent: 80,
          limit_window_seconds: 604_800,
          reset_at: 174_700,
        },
      },
      credits: {
        has_credits: true,
        unlimited: false,
        balance: "12",
      },
      rate_limit_reset_credits: { available_count: 2 },
      additional_rate_limits: [
        {
          limit_name: "GPT-5.3 Codex Spark",
          metered_feature: "gpt-5.3-codex-spark",
          rate_limit: {
            primary_window: {
              used_percent: 10,
              limit_window_seconds: 18_000,
            },
          },
        },
      ],
    },
    3_000,
  );

  assert.equal(report.providerId, "openai-codex");
  assert.equal(report.semantics, "ChatGPT subscription limits");
  assert.deepEqual(report.sections[0], {
    title: "Subscription",
    rows: [
      { label: "Plan", value: "pro" },
      { label: "Credits", value: "12" },
      { label: "Usage limit resets", value: "2 available" },
    ],
  });
  assert.deepEqual(report.sections[1]?.rows, [
    {
      label: "5h limit",
      value: "40% left",
      detail: "60% used",
      resetsAt: 10_000,
    },
    {
      label: "Weekly limit",
      value: "20% left",
      detail: "80% used",
      resetsAt: 174_700,
    },
  ]);
  assert.equal(report.sections[2]?.title, "GPT-5.3 Codex Spark");

  const formatted = formatUsageReport(report);
  assert.match(formatted, /ChatGPT subscription limits/u);
  assert.match(formatted, /5h limit:\s+40% left/u);
  assert.match(formatted, /Weekly limit:\s+20% left/u);
  assert.match(
    formatUsageReport(report, { source: "cache", ageMs: 120_000 }),
    /Data: Cache · 2m old/u,
  );
});

test("Codex adapter sanitizes labels and tolerates malformed optional buckets", () => {
  const report = normalizeCodexUsage(
    {
      credits: { has_credits: true },
      additional_rate_limits: [
        null,
        { limit_name: "bad", rate_limit: "not-an-object" },
        {
          limit_name: "Spark\u001b[31m\nlimit",
          rate_limit: {
            primary_window: { used_percent: "25" },
          },
        },
      ],
    },
    4_000,
  );

  assert.equal(report.sections[0]?.rows[0]?.value, "Available");
  assert.equal(report.sections[1]?.title, "Spark limit");
  assert.equal(report.sections[1]?.rows[0]?.value, "75% left");
});

test("Codex adapter rejects responses with no displayable usage", () => {
  assert.throws(() => normalizeCodexUsage({}, 0), /no displayable usage data/u);
  assert.throws(
    () => normalizeCodexUsage({ rate_limit: { primary_window: {} } }, 0),
    /no displayable usage data/u,
  );
});
