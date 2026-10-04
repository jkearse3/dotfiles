import assert from "node:assert/strict";
import test from "node:test";
import {
  cleanSubagentText,
  formatSubagentElapsed,
  readSubagentReport,
  subagentCallLines,
  subagentResultLines,
} from "./presentation.ts";
import type { TaskSnapshot } from "./tasks.ts";

const task: TaskSnapshot = {
  taskId: "task-123456789",
  label: "find-auth",
  status: "running",
  cwd: "/project",
  model: "provider/model",
  elapsedSeconds: 12,
  activity: ["tool: read", "tool: read finished"],
  artifactsDir: "/private/artifacts",
  tools: ["read"],
  extensions: false,
  skills: [],
  projectTrusted: true,
};

function text(lines: { text: string }[]): string {
  return lines.map((line) => line.text).join("\n");
}

const usageDiagnostics = {
  totals: {
    input: 42_100,
    output: 3_200,
    cacheRead: 88_400,
    cacheWrite: 5_100,
    cacheWrite1h: 2_000,
    reasoning: 1_500,
    totalTokens: 138_800,
    cost: {
      input: 0.0421,
      output: 0.096,
      cacheRead: 0.00884,
      cacheWrite: 0.0255,
      total: 0.17244,
    },
  },
  overallCacheHitRate: 65.18819188191882,
  latestCacheHitRate: 72.25,
  compactionCount: 1,
};

test("elapsed task time stays compact at human-scale boundaries", () => {
  assert.equal(formatSubagentElapsed(0), "0s");
  assert.equal(formatSubagentElapsed(59), "59s");
  assert.equal(formatSubagentElapsed(60), "1m");
  assert.equal(formatSubagentElapsed(119), "1m 59s");
  assert.equal(formatSubagentElapsed(3665), "1h 1m");
});

test("call preview uses the task label instead of a lossy prompt prefix", () => {
  const lines = subagentCallLines({
    action: "start",
    label: task.label,
    prompt: "Find\nauthentication entry points.",
  });
  assert.equal(lines.length, 1);
  assert.equal(text(lines), "subagent · start · find-auth");
  assert.equal(
    text(subagentCallLines({ action: "result", taskId: task.taskId })),
    "subagent · result · task-123",
  );
  assert.equal(text(subagentCallLines({})), "subagent · …");
});

test("incomplete and schema-invalid streamed arguments cannot crash rendering", () => {
  for (const value of [
    undefined,
    null,
    42,
    { action: 1, label: {}, taskId: false, prompt: [] },
  ]) {
    assert.equal(text(subagentCallLines(value)), "subagent · …");
    assert.match(
      text(subagentResultLines({ tasks: [task] }, value, true)),
      /find-auth/u,
    );
  }
});

test("foreground calls have one label and a live bounded activity trail", () => {
  const call = { label: task.label, prompt: "Find authentication." };
  assert.equal(text(subagentCallLines(call)), "subagent · find-auth");
  assert.equal(
    text(subagentCallLines({ ...call, action: "run" })),
    text(subagentCallLines(call)),
  );
  const running = subagentResultLines(
    {
      tasks: [
        {
          ...task,
          activity: Array.from(
            { length: 8 },
            (_, index) => `tool: step-${index}`,
          ),
        },
      ],
    },
    call,
    false,
  );
  assert.equal(running.length, 5);
  assert.match(text(running), /◌ Running · 12s/u);
  assert.match(text(running), /step-4/u);
  assert.doesNotMatch(text(running), /find-auth|step-3|Ctrl\+O/u);
  const complete = subagentResultLines(
    {
      tasks: [{ ...task, status: "completed" }],
      result: "# Findings\nEvidence.",
    },
    call,
    false,
  );
  assert.match(text(complete), /✓ Completed · 12s/u);
  assert.match(text(complete), /Findings/u);
  assert.doesNotMatch(text(complete), /find-auth|Running/u);
});

test("task usage stays compact when collapsed and complete when expanded", () => {
  const report = {
    tasks: [
      {
        ...task,
        status: "completed" as const,
        usageDiagnostics,
      },
    ],
  };
  assert.equal(readSubagentReport(report), report);

  const collapsed = text(subagentResultLines(report, {}, false));
  assert.match(
    collapsed,
    /↑42\.1k · ↓3\.2k · R88\.4k · W5\.1k · CH72\.3% · \$0\.172/u,
  );

  const expanded = text(subagentResultLines(report, {}, true));
  assert.match(expanded, /Usage:/u);
  assert.match(
    expanded,
    /Tokens: 42,100 input · 3,200 output · 88,400 cache read · 5,100 cache write · 138,800 total/u,
  );
  assert.match(expanded, /Cache hit: 65\.2% overall · 72\.3% latest response/u);
  assert.match(
    expanded,
    /Cost: \$0\.172 total · \$0\.042 input · \$0\.096 output · \$0\.009 cache read · \$0\.025 cache write/u,
  );
  assert.match(
    expanded,
    /Reported subsets: 1,500 reasoning · 2,000 one-hour cache write/u,
  );
  assert.match(expanded, /Compactions: 1 usage record included in totals/u);

  assert.equal(
    readSubagentReport({
      tasks: [
        {
          ...task,
          usageDiagnostics: {
            ...usageDiagnostics,
            latestCacheHitRate: 101,
          },
        },
      ],
    }),
    undefined,
  );
});

test("expanded results identify durable conversations without exposing storage paths", () => {
  const conversation = {
    conversationId: "00000000-0000-4000-8000-000000000001",
    resumed: true,
    resumable: true,
    createdAt: "2026-01-01T00:00:00.000Z",
    lastUsedAt: "2026-01-02T00:00:00.000Z",
    sessionBytes: 2048,
  };
  const report = {
    tasks: [{ ...task, status: "completed" as const }],
    conversation,
  };
  assert.equal(readSubagentReport(report), report);
  const expanded = text(
    subagentResultLines(
      report,
      {
        label: task.label,
        prompt: "Continue.",
        conversationId: conversation.conversationId,
      },
      true,
    ),
  );
  assert.match(expanded, /Conversation: .* · resumed · resumable/u);
  assert.match(expanded, /Stored context: 2 KiB/u);
  assert.doesNotMatch(expanded, /session\.jsonl|storage path/u);
  assert.equal(
    readSubagentReport({
      ...report,
      conversation: { ...conversation, storagePath: "/secret" },
    }),
    undefined,
  );
});

test("foreground previews show targets and per-call completion without duplicate rows", () => {
  const report = {
    tasks: [
      {
        ...task,
        toolCalls: [
          {
            id: "a",
            preview: "read src/main.ts:10–14",
            status: "completed" as const,
          },
          { id: "b", preview: "bash npm test", status: "running" as const },
        ],
      },
    ],
  };
  const lines = text(subagentResultLines(report, { label: task.label }, false));
  assert.match(lines, /✓ read src\/main.ts:10–14/);
  assert.match(lines, /→ bash npm test/);
  assert.doesNotMatch(lines, /read finished/);
  assert.ok(readSubagentReport(report));
  assert.equal(
    readSubagentReport({ tasks: [{ ...task, toolCalls: [null] }] }),
    undefined,
  );
});

test("expanded foreground results render a chronological visible transcript", () => {
  const transcript = [
    { kind: "assistant" as const, text: "I’ll inspect the entry point." },
    {
      kind: "tool" as const,
      id: "a",
      preview: "read src/main.ts:1–20",
      status: "completed" as const,
    },
    {
      kind: "tool" as const,
      id: "b",
      preview: "bash npm test",
      status: "failed" as const,
      output: "1 test failed\nExpected true",
    },
  ];
  const lines = text(
    subagentResultLines(
      {
        tasks: [
          { ...task, status: "failed", transcript, transcriptOmitted: 2 },
        ],
        result: "# Result\nFailed safely.",
      },
      { label: task.label, prompt: "Inspect it." },
      true,
    ),
  );
  assert.match(lines, /^Assignment:\nInspect it\./u);
  assert.match(lines, /Transcript:\n… 2 earlier entries omitted/u);
  assert.match(
    lines,
    /Assistant · I’ll inspect the entry point\.[\s\S]*✓ read src\/main\.ts:1–20[\s\S]*✗ bash npm test[\s\S]*Output · 1 test failed\nExpected true/u,
  );
  assert.match(lines, /Outcome:[\s\S]*Details:/u);
  assert.doesNotMatch(lines, /Recent activity|Recent tool calls/u);
  const unsafeLines = text(
    subagentResultLines(
      {
        tasks: [
          {
            ...task,
            transcript: [
              { kind: "assistant", text: "safe\x1b[31m" },
              {
                kind: "tool",
                id: "x",
                preview: "bash echo\x1b[31m",
                status: "completed",
                output: "line\x1b[31m\n".repeat(10),
              },
            ],
          },
        ],
      },
      {},
      true,
    ),
  );
  assert.doesNotMatch(unsafeLines, /\x1b/u);
  assert.ok(unsafeLines.split("line").length <= 8);
});

test("start receipts do not pretend historical snapshots are live", () => {
  const lines = subagentResultLines(
    { tasks: [task] },
    { action: "start" },
    false,
  );
  assert.match(text(lines), /↗ Started · task-123/u);
  assert.doesNotMatch(text(lines), /Running|read finished|artifacts|provider/u);
});

test("collapsed status reports show activity and limit task rows", () => {
  const tasks = Array.from({ length: 6 }, (_, index) => ({
    ...task,
    label: `task-${index}`,
  }));
  const lines = subagentResultLines({ tasks }, { action: "status" }, false);
  assert.match(text(lines), /Running · 12s/u);
  assert.match(text(lines), /read finished/u);
  assert.match(text(lines), /\+2 more tasks/u);
  assert.doesNotMatch(text(lines), /task-4/u);
});

test("expanded views expose diagnostics and requested capabilities", () => {
  const lines = subagentResultLines(
    { tasks: [task] },
    { action: "start", prompt: "Bounded assignment.\n  Preserve indentation." },
    true,
  );
  assert.match(text(lines), /Task: task-123456789/u);
  assert.match(text(lines), /Directory: \/project/u);
  assert.match(text(lines), /Tools: read/u);
  assert.match(
    text(lines),
    /Extensions: off · Skills: none · Inherited project trust: on/u,
  );
  assert.match(text(lines), /Activity:/u);
  assert.match(text(lines), /Details:/u);
  assert.match(text(lines), /Artifacts: \/private\/artifacts/u);
  assert.match(
    text(lines),
    /Assignment:\nBounded assignment\.\n  Preserve indentation\./u,
  );
  assert.match(
    text(
      subagentResultLines({ tasks: [{ ...task, tools: undefined }] }, {}, true),
    ),
    /Tools: configured defaults/u,
  );
  assert.match(
    text(subagentResultLines({ tasks: [{ ...task, tools: [] }] }, {}, true)),
    /Tools: none/u,
  );
  assert.match(
    text(
      subagentResultLines(
        { tasks: [{ ...task, skills: ["diff-review"] }] },
        {},
        true,
      ),
    ),
    /Skills: diff-review/u,
  );
});

test("collapsed final output pairs a heading with substantive preview text", () => {
  const lines = subagentResultLines(
    {
      tasks: [{ ...task, status: "completed" }],
      result:
        "\n# **Findings**\n\n---\n\n*Evidence* from [tests](https://example.test/report).",
      resultTruncated: true,
    },
    { action: "result" },
    false,
  );
  assert.match(text(lines), /✓ find-auth · Completed/u);
  assert.match(text(lines), /\nFindings — Evidence from tests\.\n/u);
  assert.match(text(lines), /Output truncated · full response in reply\.txt/u);
  assert.doesNotMatch(
    text(
      subagentResultLines({ tasks: [task], result: "Response body" }, {}, true),
    ),
    /Response body/u,
    "the Markdown component owns the expanded response",
  );
});

test("failed and cancelled tasks are distinct and cannot look successful", () => {
  const failed = subagentResultLines(
    { tasks: [{ ...task, status: "failed", error: "Provider failed" }] },
    {},
    false,
  );
  assert.equal(failed[0]!.tone, "error");
  assert.match(text(failed), /✗ find-auth · Failed/u);
  assert.match(text(failed), /Provider failed/u);
  const cancelled = subagentResultLines(
    { tasks: [{ ...task, status: "cancelled" }] },
    {},
    false,
  );
  assert.equal(cancelled[0]!.tone, "warning");
  assert.match(text(cancelled), /■ find-auth · Cancelled/u);
});

test("display sanitization removes ANSI, OSC links, and controls without changing model data", () => {
  const unsafe =
    "\x1b[31mred\x1b[0m\n\x1b]8;;https://example.com\x07link\x1b]8;;\x07\x00";
  assert.equal(cleanSubagentText(unsafe), "red\nlink");
  const stHyperlink =
    "before\x1b]8;;https://example.com\x1b\\link\x1b]8;;\x1b\\after";
  assert.equal(cleanSubagentText(stHyperlink), "beforelinkafter");
  const report = { tasks: [{ ...task, label: unsafe }] };
  assert.doesNotMatch(
    text(subagentResultLines(report, {}, false)),
    /\x1b|\x00/u,
  );
  assert.equal(report.tasks[0]!.label, unsafe);
  assert.equal(
    cleanSubagentText("first\r\nsecond\rthird"),
    "first\nsecond\nthird",
  );
});

test("valid historical reports render, while malformed details fall back safely", () => {
  const report = { tasks: [task], result: "final" };
  assert.equal(readSubagentReport(report), report);
  assert.ok(
    readSubagentReport({
      tasks: [
        {
          ...task,
          extensions: undefined,
          skills: undefined,
          projectTrusted: undefined,
        },
      ],
    }),
  );
  assert.deepEqual(readSubagentReport({ tasks: [] }), { tasks: [] });
  for (const invalid of [
    undefined,
    null,
    42,
    {},
    { tasks: [null] },
    { tasks: ["task"] },
    { tasks: [{ ...task, activity: [1] }] },
    { tasks: [{ ...task, status: "unknown" }] },
    { tasks: [{ ...task, elapsedSeconds: NaN }] },
    { tasks: [{ ...task, tools: {} }] },
    { tasks: [{ ...task, extensions: "yes" }] },
    { tasks: [{ ...task, transcript: [null] }] },
    { tasks: [{ ...task, transcript: [{ kind: "assistant", text: 1 }] }] },
    {
      tasks: [
        {
          ...task,
          transcript: [
            { kind: "tool", id: "x", preview: "read file", status: "unknown" },
          ],
        },
      ],
    },
    { tasks: [{ ...task, transcriptOmitted: -1 }] },
    {
      tasks: [
        {
          ...task,
          transcript: Array.from({ length: 65 }, () => ({
            kind: "assistant",
            text: "x",
          })),
        },
      ],
    },
    {
      tasks: [
        {
          ...task,
          transcript: [{ kind: "assistant", text: "x".repeat(4001) }],
        },
      ],
    },
    {
      tasks: [
        { ...task, transcript: [{ kind: "assistant", text: "x\x1b[31m" }] },
      ],
    },
    {
      tasks: [
        {
          ...task,
          transcript: [
            {
              kind: "tool",
              id: "x",
              preview: "read file",
              status: "completed",
              output: "x\n".repeat(7),
            },
          ],
        },
      ],
    },
    { tasks: [task], result: {} },
    { tasks: [task], resultTruncated: "yes" },
  ])
    assert.equal(readSubagentReport(invalid), undefined);
});
