import { formatTranscriptTime } from "./stamp.ts";

/** Session sidecar for one idle-to-settled agent busy period. */
export const AGENT_ELAPSED_ENTRY_TYPE = "transcript-agent-elapsed";

/** Local wall-clock observations; a busy period can include steers and queued follow-ups. */
export interface AgentElapsedData {
  version: 1 | 2;
  startedAt: number;
  settledAt: number;
  turnCount: number;
  interrupted: boolean;
  /** Last visible user stamp, available on version 2 for date context. */
  previousVisibleAt?: number;
}

/** Rejects malformed persisted observations before rendering or appending them. */
export function isAgentElapsedData(value: unknown): value is AgentElapsedData {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    return false;
  }
  const data = value as Record<string, unknown>;
  const allowedKeys = [
    "version",
    "startedAt",
    "settledAt",
    "turnCount",
    "interrupted",
    ...(data.version === 2 ? ["previousVisibleAt"] : []),
  ];
  return (
    Object.keys(data).every((key) => allowedKeys.includes(key)) &&
    (data.version === 1 || data.version === 2) &&
    isTimestamp(data.startedAt) &&
    isTimestamp(data.settledAt) &&
    data.settledAt >= data.startedAt &&
    (data.previousVisibleAt === undefined ||
      (data.version === 2 &&
        isTimestamp(data.previousVisibleAt) &&
        data.previousVisibleAt <= data.settledAt)) &&
    typeof data.turnCount === "number" &&
    Number.isSafeInteger(data.turnCount) &&
    data.turnCount >= 0 &&
    typeof data.interrupted === "boolean"
  );
}

/** Formats the elapsed busy period without implying attribution to one prompt. */
export function formatAgentElapsed(data: AgentElapsedData): string | undefined {
  if (!isAgentElapsedData(data)) return undefined;
  const duration = data.settledAt - data.startedAt;
  const elapsed =
    duration < 1_000
      ? `${duration}ms`
      : duration < 60_000
        ? `${(Math.round(duration / 100) / 10).toFixed(1)}s`
        : `${Math.floor(Math.round(duration / 1_000) / 60)}m ${String(Math.round(duration / 1_000) % 60).padStart(2, "0")}s`;
  const turns = `${data.turnCount} ${data.turnCount === 1 ? "turn" : "turns"}`;
  const previousAt =
    data.version === 2 ? data.previousVisibleAt : data.startedAt;
  const clock = formatTranscriptTime(data.settledAt, previousAt);
  return `${clock} · agent ${elapsed} · ${turns}${data.interrupted ? " · interrupted" : ""}`;
}

function isTimestamp(value: unknown): value is number {
  return (
    typeof value === "number" &&
    Number.isFinite(value) &&
    !Number.isNaN(new Date(value).getTime())
  );
}
