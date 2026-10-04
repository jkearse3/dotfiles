import type { TaskSnapshot, TaskUsageDiagnostics } from "./tasks.ts";

export type SubagentConversationReport = {
  conversationId: string;
  resumed: boolean;
  resumable: boolean;
  createdAt: string;
  lastUsedAt: string;
  sessionBytes: number;
};

export type SubagentReport = {
  tasks: TaskSnapshot[];
  result?: string;
  resultTruncated?: boolean;
  conversation?: SubagentConversationReport;
};

export interface SubagentCall {
  action?: string;
  label?: string;
  taskId?: string;
  prompt?: string;
  conversationId?: string;
}

export interface SubagentLine {
  text: string;
  tone: "accent" | "muted" | "text" | "success" | "warning" | "error";
  indentColumns?: number;
}

/** Separates primary result lines from diagnostics shown after the outcome. */
export interface SubagentResultPresentation {
  primary: SubagentLine[];
  details: SubagentLine[];
}

/** Terminal-safe text; Markdown output keeps newlines but never terminal controls. */
export function cleanSubagentText(value: string): string {
  return value
    .replace(/\r\n?/gu, "\n")
    .replace(/\u001b\][^\u0007]*?(?:\u0007|\u001b\\)/gu, "")
    .replace(/\u001b\[[0-?]*[ -/]*[@-~]/gu, "")
    .replace(/[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f-\u009f]/gu, "");
}

function inline(value: string): string {
  return cleanSubagentText(value).replace(/\s+/gu, " ").trim();
}

/** Older session entries without recognizable details use a plain-text fallback. */
export function readSubagentReport(value: unknown): SubagentReport | undefined {
  if (!value || typeof value !== "object") return;
  const report = value as Partial<SubagentReport>;
  if (
    !Array.isArray(report.tasks) ||
    !report.tasks.every(
      (task) =>
        task &&
        typeof task === "object" &&
        typeof task.taskId === "string" &&
        typeof task.label === "string" &&
        ["running", "completed", "failed", "cancelled"].includes(task.status) &&
        typeof task.elapsedSeconds === "number" &&
        Number.isFinite(task.elapsedSeconds) &&
        typeof task.cwd === "string" &&
        typeof task.model === "string" &&
        typeof task.artifactsDir === "string" &&
        Array.isArray(task.activity) &&
        task.activity.every((item) => typeof item === "string") &&
        (task.toolCalls === undefined ||
          (Array.isArray(task.toolCalls) &&
            task.toolCalls.every(
              (call) =>
                call &&
                typeof call.id === "string" &&
                typeof call.preview === "string" &&
                ["running", "completed", "failed", "cancelled"].includes(
                  call.status,
                ),
            ))) &&
        (task.transcript === undefined ||
          (Array.isArray(task.transcript) &&
            task.transcript.length <= 64 &&
            task.transcript.every(
              (entry) =>
                entry &&
                (entry.kind === "assistant"
                  ? safeTranscriptText(entry.text, 4000)
                  : entry.kind === "tool" &&
                    typeof entry.id === "string" &&
                    entry.id.length <= 1024 &&
                    safeTranscriptText(entry.preview, 600) &&
                    ["running", "completed", "failed", "cancelled"].includes(
                      entry.status,
                    ) &&
                    (entry.output === undefined ||
                      (safeTranscriptText(entry.output, 1200) &&
                        entry.output.split("\n").length <= 6))),
            ))) &&
        (task.transcriptOmitted === undefined ||
          (Number.isSafeInteger(task.transcriptOmitted) &&
            task.transcriptOmitted >= 0)) &&
        (task.usageDiagnostics === undefined ||
          isTaskUsageDiagnostics(task.usageDiagnostics)) &&
        (task.error === undefined || typeof task.error === "string") &&
        (task.tools === undefined ||
          (Array.isArray(task.tools) &&
            task.tools.every((tool) => typeof tool === "string"))) &&
        (task.skills === undefined ||
          (Array.isArray(task.skills) &&
            task.skills.every((skill) => typeof skill === "string"))) &&
        [task.extensions, task.projectTrusted].every(
          (setting) => setting === undefined || typeof setting === "boolean",
        ),
    ) ||
    (report.result !== undefined && typeof report.result !== "string") ||
    (report.resultTruncated !== undefined &&
      typeof report.resultTruncated !== "boolean") ||
    (report.conversation !== undefined &&
      !isConversationReport(report.conversation))
  )
    return;
  return report as SubagentReport;
}

function isTaskUsageDiagnostics(value: unknown): value is TaskUsageDiagnostics {
  if (!value || typeof value !== "object") return false;
  const diagnostics = value as Partial<TaskUsageDiagnostics>;
  const totals = diagnostics.totals;
  if (!totals || typeof totals !== "object") return false;

  const cost = totals.cost;
  return (
    [
      totals.input,
      totals.output,
      totals.cacheRead,
      totals.cacheWrite,
      totals.totalTokens,
    ].every(nonnegativeNumber) &&
    [totals.reasoning, totals.cacheWrite1h].every(optionalNonnegativeNumber) &&
    cost !== undefined &&
    typeof cost === "object" &&
    [
      cost.input,
      cost.output,
      cost.cacheRead,
      cost.cacheWrite,
      cost.total,
    ].every(nonnegativeNumber) &&
    (diagnostics.overallCacheHitRate === undefined ||
      percentage(diagnostics.overallCacheHitRate)) &&
    (diagnostics.latestCacheHitRate === undefined ||
      percentage(diagnostics.latestCacheHitRate)) &&
    Number.isSafeInteger(diagnostics.compactionCount) &&
    diagnostics.compactionCount! >= 0
  );
}

function nonnegativeNumber(value: unknown): value is number {
  return typeof value === "number" && Number.isFinite(value) && value >= 0;
}

function optionalNonnegativeNumber(value: unknown): boolean {
  return value === undefined || nonnegativeNumber(value);
}

function percentage(value: unknown): value is number {
  return nonnegativeNumber(value) && value <= 100;
}

function isConversationReport(
  value: unknown,
): value is SubagentConversationReport {
  if (!value || typeof value !== "object") return false;
  const conversation = value as Partial<SubagentConversationReport>;
  if (
    Object.keys(conversation).sort().join(",") !==
    "conversationId,createdAt,lastUsedAt,resumable,resumed,sessionBytes"
  )
    return false;
  return (
    typeof conversation.conversationId === "string" &&
    /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/u.test(
      conversation.conversationId,
    ) &&
    typeof conversation.resumed === "boolean" &&
    typeof conversation.resumable === "boolean" &&
    typeof conversation.createdAt === "string" &&
    !Number.isNaN(Date.parse(conversation.createdAt)) &&
    typeof conversation.lastUsedAt === "string" &&
    !Number.isNaN(Date.parse(conversation.lastUsedAt)) &&
    Number.isSafeInteger(conversation.sessionBytes) &&
    conversation.sessionBytes! >= 0
  );
}

function safeTranscriptText(
  value: unknown,
  maxCharacters: number,
): value is string {
  return (
    typeof value === "string" &&
    value.length <= maxCharacters &&
    cleanSubagentText(value) === value
  );
}

function activityLabel(value?: string): string {
  if (!value) return "Starting…";
  switch (value) {
    case "assistant: toolUse":
      return "Preparing tools";
    case "assistant: stop":
      return "Finishing";
    case "assistant: error":
      return "Model error";
    case "assistant: aborted":
      return "Model interrupted";
    case "agent settled; awaiting process exit":
      return "Waiting for process exit";
    default:
      return inline(value).replace(/^tool:\s*/u, "");
  }
}

/** Tool renderers also see incomplete or schema-invalid streamed arguments. */
function readSubagentCall(value: unknown): SubagentCall {
  if (!value || typeof value !== "object") return {};
  const call = value as Partial<Record<keyof SubagentCall, unknown>>;
  return {
    action: typeof call.action === "string" ? call.action : undefined,
    label: typeof call.label === "string" ? call.label : undefined,
    taskId: typeof call.taskId === "string" ? call.taskId : undefined,
    prompt: typeof call.prompt === "string" ? call.prompt : undefined,
    conversationId:
      typeof call.conversationId === "string" ? call.conversationId : undefined,
  };
}

export function subagentCallLines(value: unknown): SubagentLine[] {
  const call = readSubagentCall(value);
  const foreground = call.action === undefined || call.action === "run";
  const target = call.label ?? call.taskId?.slice(0, 8);
  return [
    {
      text: foreground
        ? `subagent · ${target ? inline(target) : "…"}`
        : `subagent · ${inline(call.action ?? "…")}${target ? ` · ${inline(target)}` : ""}`,
      tone: "accent",
    },
  ];
}

/** Formats elapsed task time for compact terminal presentation. */
export function formatSubagentElapsed(elapsedSeconds: number): string {
  const totalSeconds = Math.max(0, Math.floor(elapsedSeconds));
  if (totalSeconds < 60) return `${totalSeconds}s`;

  const totalMinutes = Math.floor(totalSeconds / 60);
  const seconds = totalSeconds % 60;
  if (totalMinutes < 60)
    return `${totalMinutes}m${seconds ? ` ${seconds}s` : ""}`;

  const hours = Math.floor(totalMinutes / 60);
  const minutes = totalMinutes % 60;
  return `${hours}h${minutes ? ` ${minutes}m` : ""}`;
}

function taskLine(
  task: TaskSnapshot,
  started = false,
  includeLabel = true,
): SubagentLine {
  const states = {
    running: { icon: "◌", label: "Running", tone: "accent" },
    completed: { icon: "✓", label: "Completed", tone: "success" },
    failed: { icon: "✗", label: "Failed", tone: "error" },
    cancelled: { icon: "■", label: "Cancelled", tone: "warning" },
  } as const;
  const state = states[task.status];
  if (started)
    return {
      text: `↗ Started · ${inline(task.taskId).slice(0, 8)}`,
      tone: state.tone,
    };

  const usage = task.usageDiagnostics
    ? ` · ${compactUsage(task.usageDiagnostics)}`
    : "";
  return {
    text: `${state.icon} ${includeLabel ? `${inline(task.label)} · ` : ""}${state.label} · ${formatSubagentElapsed(task.elapsedSeconds)}${usage}`,
    tone: state.tone,
  };
}

/** Builds result sections so expanded Markdown can precede diagnostics. */
export function subagentResultPresentation(
  report: SubagentReport,
  callValue: unknown,
  expanded: boolean,
): SubagentResultPresentation {
  const call = readSubagentCall(callValue);
  const foreground = call.action === undefined || call.action === "run";
  if (!report.tasks.length)
    return {
      primary: [{ text: "No subagent tasks in this session.", tone: "muted" }],
      details: [],
    };

  const visible = expanded ? report.tasks : report.tasks.slice(0, 4);
  const hasExpandedOutcome = expanded && Boolean(report.result?.trim());
  const lines: SubagentLine[] = [];
  const details: SubagentLine[] = [];
  if (expanded && call.prompt)
    lines.push({
      text: `Assignment:\n${cleanSubagentText(call.prompt)}`,
      tone: "muted",
    });

  for (const task of visible) {
    lines.push(
      taskLine(
        task,
        call.action === "start" && task.status === "running",
        !foreground || !call.label || report.tasks.length > 1,
      ),
    );
    if (task.error)
      lines.push({
        text: expanded ? cleanSubagentText(task.error) : inline(task.error),
        tone: "error",
      });
    else if (
      task.status === "running" &&
      !expanded &&
      call.action !== "start"
    ) {
      const activity = foreground
        ? task.activity.slice(-4)
        : task.activity.slice(-1);
      if (foreground && task.toolCalls?.length)
        lines.push(...toolCallLines(task.toolCalls.slice(-4)));
      else
        for (const entry of activity.length ? activity : ["Starting…"])
          lines.push({ text: activityLabel(entry), tone: "muted" });
    }
    if (!expanded) continue;

    if (task.transcript?.length) {
      lines.push({ text: "Transcript:", tone: "muted" });
      if (task.transcriptOmitted)
        lines.push({
          text: `… ${task.transcriptOmitted} earlier entries omitted`,
          tone: "warning",
          indentColumns: 2,
        });
      lines.push(...transcriptLines(task.transcript));
    } else {
      if (task.toolCalls?.length) {
        lines.push({ text: "Tool calls:", tone: "muted" });
        lines.push(...toolCallLines(task.toolCalls, 2));
      }
      if (task.activity.length) {
        lines.push({ text: "Activity:", tone: "muted" });
        for (const activity of task.activity)
          lines.push({
            text: inline(activity),
            tone: "muted",
            indentColumns: 2,
          });
      }
    }

    const taskDetails: SubagentLine[] = [
      ...(task.usageDiagnostics
        ? usageDiagnosticLines(task.usageDiagnostics)
        : []),
      { text: "Details:", tone: "muted" },
      {
        text: `Task: ${inline(task.taskId)}`,
        tone: "muted",
        indentColumns: 2,
      },
      ...(report.conversation
        ? [
            {
              text: `Conversation: ${inline(report.conversation.conversationId)} · ${report.conversation.resumed ? "resumed" : "new"} · ${report.conversation.resumable ? "resumable" : "context limit reached"}`,
              tone: report.conversation.resumable
                ? ("muted" as const)
                : ("warning" as const),
              indentColumns: 2,
            },
            {
              text: `Stored context: ${formatBytes(report.conversation.sessionBytes)} · last used ${inline(report.conversation.lastUsedAt)}`,
              tone: "muted" as const,
              indentColumns: 2,
            },
          ]
        : []),
      {
        text: `Model: ${inline(task.model)}`,
        tone: "muted",
        indentColumns: 2,
      },
      {
        text: `Directory: ${inline(task.cwd)}`,
        tone: "muted",
        indentColumns: 2,
      },
      {
        text: `Tools: ${task.tools === undefined ? "configured defaults" : task.tools.length ? task.tools.map(inline).join(", ") : "none"}`,
        tone: "muted",
        indentColumns: 2,
      },
      {
        text: `Extensions: ${setting(task.extensions)} · Skills: ${task.skills === undefined ? "configured defaults" : task.skills.length ? task.skills.map(inline).join(", ") : "none"} · Inherited project trust: ${setting(task.projectTrusted)}`,
        tone: "muted",
        indentColumns: 2,
      },
      {
        text: `Artifacts: ${inline(task.artifactsDir)}`,
        tone: "muted",
        indentColumns: 2,
      },
    ];
    if (hasExpandedOutcome) details.push(...taskDetails);
    else lines.push(...taskDetails);
  }

  if (visible.length < report.tasks.length)
    lines.push({
      text: `+${report.tasks.length - visible.length} more tasks`,
      tone: "muted",
    });
  if (hasExpandedOutcome) lines.push({ text: "Outcome:", tone: "muted" });
  if (!expanded && report.result?.trim())
    lines.push({ text: resultPreview(report.result), tone: "muted" });
  if (report.resultTruncated) {
    const truncationNotice: SubagentLine = {
      text: "Output truncated · full response in reply.txt",
      tone: "warning",
    };
    if (hasExpandedOutcome) details.unshift(truncationNotice);
    else lines.push(truncationNotice);
  }
  if (
    !expanded &&
    (!foreground || report.tasks.some((task) => task.status !== "running"))
  )
    lines.push({ text: "Ctrl+O to expand", tone: "muted" });

  return { primary: lines, details };
}

/** Flattens result sections for non-component consumers and focused tests. */
export function subagentResultLines(
  report: SubagentReport,
  callValue: unknown,
  expanded: boolean,
): SubagentLine[] {
  const presentation = subagentResultPresentation(report, callValue, expanded);
  return [...presentation.primary, ...presentation.details];
}

function resultPreview(result: string): string {
  const contentLines = result
    .split(/\r?\n/u)
    .map((line) => line.trim())
    .filter(Boolean);
  const firstLine = contentLines[0] ?? "";
  const heading = firstLine.match(/^#{1,6}\s+(.+)$/u)?.[1];
  if (!heading) return plainMarkdownLine(firstLine);

  const detail = contentLines.slice(1).find(isSubstantiveMarkdownLine);
  return detail
    ? `${plainMarkdownLine(heading)} — ${plainMarkdownLine(detail)}`
    : plainMarkdownLine(heading);
}

function isSubstantiveMarkdownLine(value: string): boolean {
  return !(
    /^#{1,6}(?:\s+|$)/u.test(value) ||
    /^(?:`{3,}|~{3,})/u.test(value) ||
    /^(?:[-*_]\s*){3,}$/u.test(value)
  );
}

function plainMarkdownLine(value: string): string {
  return inline(value)
    .replace(/^>\s*/u, "")
    .replace(/^\d+[.)]\s+/u, "")
    .replace(/^[-+*]\s+/u, "")
    .replace(/!\[([^\]]*)\]\([^)]+\)/gu, "$1")
    .replace(/\[([^\]]+)\]\([^)]+\)/gu, "$1")
    .replace(/(\*\*|__|~~)(.*?)\1/gu, "$2")
    .replace(/(^|[\s(])([*_])([^*_]+)\2(?=$|[\s).,!?:;])/gu, "$1$3")
    .replace(/`([^`]+)`/gu, "$1");
}

function transcriptLines(
  transcript: NonNullable<TaskSnapshot["transcript"]>,
): SubagentLine[] {
  return transcript.flatMap((entry) => {
    if (entry.kind === "assistant")
      return [
        {
          text: `Assistant · ${cleanSubagentText(entry.text).slice(0, 4000)}`,
          tone: "text" as const,
          indentColumns: 2,
        },
      ];
    const lines = toolCallLines(
      [{ ...entry, preview: inline(entry.preview).slice(0, 600) }],
      2,
    );
    if (entry.output)
      lines.push({
        text: `Output · ${cleanSubagentText(entry.output)
          .slice(0, 1200)
          .split("\n")
          .slice(0, 6)
          .join("\n")}`,
        tone: "muted",
        indentColumns: 4,
      });
    return lines;
  });
}

function toolCallLines(
  calls: NonNullable<TaskSnapshot["toolCalls"]>,
  indent = 0,
): SubagentLine[] {
  return calls.map((call) => ({
    text: `${call.status === "running" ? "→" : call.status === "completed" ? "✓" : call.status === "cancelled" ? "■" : "✗"} ${inline(call.preview)}`,
    tone:
      call.status === "failed"
        ? "error"
        : call.status === "cancelled"
          ? "warning"
          : call.status === "running"
            ? "accent"
            : "muted",
    indentColumns: indent,
  }));
}

function compactUsage(diagnostics: TaskUsageDiagnostics): string {
  const { totals } = diagnostics;
  const fields = [
    `↑${formatCompactCount(totals.input)}`,
    `↓${formatCompactCount(totals.output)}`,
  ];
  if (totals.cacheRead || totals.cacheWrite) {
    fields.push(`R${formatCompactCount(totals.cacheRead)}`);
    fields.push(`W${formatCompactCount(totals.cacheWrite)}`);
  }
  if (diagnostics.latestCacheHitRate !== undefined)
    fields.push(`CH${diagnostics.latestCacheHitRate.toFixed(1)}%`);
  fields.push(formatCost(totals.cost.total));
  return fields.join(" · ");
}

function usageDiagnosticLines(
  diagnostics: TaskUsageDiagnostics,
): SubagentLine[] {
  const { totals } = diagnostics;
  const lines: SubagentLine[] = [
    { text: "Usage:", tone: "muted" },
    {
      text: `Tokens: ${formatExactCount(totals.input)} input · ${formatExactCount(totals.output)} output · ${formatExactCount(totals.cacheRead)} cache read · ${formatExactCount(totals.cacheWrite)} cache write · ${formatExactCount(totals.totalTokens)} total`,
      tone: "muted",
      indentColumns: 2,
    },
  ];
  if (
    diagnostics.overallCacheHitRate !== undefined ||
    diagnostics.latestCacheHitRate !== undefined
  ) {
    const rates = [
      ...(diagnostics.overallCacheHitRate === undefined
        ? []
        : [`${diagnostics.overallCacheHitRate.toFixed(1)}% overall`]),
      ...(diagnostics.latestCacheHitRate === undefined
        ? []
        : [`${diagnostics.latestCacheHitRate.toFixed(1)}% latest response`]),
    ];
    lines.push({
      text: `Cache hit: ${rates.join(" · ")}`,
      tone: "muted",
      indentColumns: 2,
    });
  }
  lines.push({
    text: `Cost: ${formatCost(totals.cost.total)} total · ${formatCost(totals.cost.input)} input · ${formatCost(totals.cost.output)} output · ${formatCost(totals.cost.cacheRead)} cache read · ${formatCost(totals.cost.cacheWrite)} cache write`,
    tone: "muted",
    indentColumns: 2,
  });

  const optionalTokens = [
    ...(totals.reasoning === undefined
      ? []
      : [`${formatExactCount(totals.reasoning)} reasoning`]),
    ...(totals.cacheWrite1h === undefined
      ? []
      : [`${formatExactCount(totals.cacheWrite1h)} one-hour cache write`]),
  ];
  if (optionalTokens.length)
    lines.push({
      text: `Reported subsets: ${optionalTokens.join(" · ")}`,
      tone: "muted",
      indentColumns: 2,
    });
  if (diagnostics.compactionCount)
    lines.push({
      text: `Compactions: ${diagnostics.compactionCount} usage record${diagnostics.compactionCount === 1 ? "" : "s"} included in totals`,
      tone: "muted",
      indentColumns: 2,
    });
  return lines;
}

function formatCompactCount(value: number): string {
  if (value < 1000) return String(value);
  if (value < 1_000_000)
    return `${stripTrailingZero((value / 1000).toFixed(1))}k`;
  return `${stripTrailingZero((value / 1_000_000).toFixed(1))}m`;
}

function stripTrailingZero(value: string): string {
  return value.replace(/\.0$/u, "");
}

function formatExactCount(value: number): string {
  return value.toLocaleString("en-US");
}

function formatCost(value: number): string {
  const precision = value > 0 && value < 0.001 ? 6 : 3;
  return `$${value.toFixed(precision)}`;
}

function formatBytes(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${Math.ceil(bytes / 1024)} KiB`;
  return `${Math.ceil(bytes / (1024 * 1024))} MiB`;
}

function setting(value: boolean | undefined): string {
  return value === undefined ? "not recorded" : value ? "on" : "off";
}
