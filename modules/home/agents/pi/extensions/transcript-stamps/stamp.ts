/** Stable session-entry identifier for transcript stamp data. */
export const TRANSCRIPT_STAMP_ENTRY_TYPE = "transcript-stamp";

/** Fixed presentation policy with no settings-file or environment overrides. */
export interface TranscriptStampDefaults {
  timeZone: "local";
  hourCycle: "24h" | "12h";
  showSeconds: boolean;
  showTimeZone: boolean;
  dateContext: "first-and-day-change" | "day-change" | "never";
  showAssistantDuration: boolean;
  showTurnDuration: boolean;
  showFirstContentLatency: boolean;
  showToolPerformance: boolean;
  showTokenRate: boolean;
}

/** Opinionated defaults applied to every transcript stamp. */
export const TRANSCRIPT_STAMP_DEFAULTS: Readonly<TranscriptStampDefaults> =
  Object.freeze({
    timeZone: "local",
    hourCycle: "24h",
    showSeconds: true,
    showTimeZone: true,
    dateContext: "first-and-day-change",
    showAssistantDuration: true,
    showTurnDuration: true,
    showFirstContentLatency: true,
    showToolPerformance: true,
    showTokenRate: true,
  });

/** Legacy persisted timestamp data retained for existing sessions. */
export interface TranscriptStampDataV1 {
  version: 1;
  role: "user" | "assistant";
  createdAt: number;
  previousCreatedAt?: number;
  completedAt?: number;
}

/** Persisted timestamp data with complete turn timing. */
export interface TranscriptStampDataV2 {
  version: 2;
  role: "assistant";
  createdAt: number;
  previousCreatedAt?: number;
  completedAt?: number;
  turnStartedAt: number;
  turnCompletedAt: number;
}

/** Persisted timing and throughput observations for one assistant turn. */
export interface TranscriptStampDataV3 {
  version: 3;
  role: "assistant";
  createdAt: number;
  previousCreatedAt?: number;
  completedAt?: number;
  turnStartedAt: number;
  turnCompletedAt: number;
  firstContentAt?: number;
  outputTokens?: number;
  toolStartedAt?: number;
  toolCompletedAt?: number;
  toolCount?: number;
  toolErrorCount?: number;
}

/** Supported transcript stamp session-entry data. */
export type TranscriptStampData =
  | TranscriptStampDataV1
  | TranscriptStampDataV2
  | TranscriptStampDataV3;

const TRANSCRIPT_STAMP_V1_KEYS: ReadonlySet<string> = new Set([
  "version",
  "role",
  "createdAt",
  "previousCreatedAt",
  "completedAt",
]);
const TRANSCRIPT_STAMP_V2_KEYS: ReadonlySet<string> = new Set([
  ...TRANSCRIPT_STAMP_V1_KEYS,
  "turnStartedAt",
  "turnCompletedAt",
]);
const TRANSCRIPT_STAMP_V3_KEYS: ReadonlySet<string> = new Set([
  ...TRANSCRIPT_STAMP_V2_KEYS,
  "firstContentAt",
  "outputTokens",
  "toolStartedAt",
  "toolCompletedAt",
  "toolCount",
  "toolErrorCount",
]);

/** Aggregate wall-clock tool observations for one Pi turn. */
export interface TranscriptToolPerformance {
  startedAt: number;
  completedAt: number;
  count: number;
  errorCount: number;
}

/** Complete local performance observations for one Pi turn. */
export interface TranscriptTurnPerformance {
  startedAt: number;
  completedAt: number;
  firstContentAt?: number;
  outputTokens?: number;
  tools?: Readonly<TranscriptToolPerformance>;
}

/** Creates transcript stamp data from observed message and turn times. */
export function createTranscriptStamp(
  role: TranscriptStampData["role"],
  createdAt: number,
  previousCreatedAt?: number,
  completedAt?: number,
  turnPerformance?: Readonly<TranscriptTurnPerformance>,
): TranscriptStampData {
  if (role === "assistant" && turnPerformance) {
    return {
      version: 3,
      role,
      createdAt,
      ...(previousCreatedAt === undefined ? {} : { previousCreatedAt }),
      ...(completedAt === undefined ? {} : { completedAt }),
      turnStartedAt: turnPerformance.startedAt,
      turnCompletedAt: turnPerformance.completedAt,
      ...(turnPerformance.firstContentAt === undefined
        ? {}
        : { firstContentAt: turnPerformance.firstContentAt }),
      ...(turnPerformance.outputTokens === undefined
        ? {}
        : { outputTokens: turnPerformance.outputTokens }),
      ...(turnPerformance.tools === undefined
        ? {}
        : {
            toolStartedAt: turnPerformance.tools.startedAt,
            toolCompletedAt: turnPerformance.tools.completedAt,
            toolCount: turnPerformance.tools.count,
            toolErrorCount: turnPerformance.tools.errorCount,
          }),
    };
  }

  return {
    version: 1,
    role,
    createdAt,
    ...(previousCreatedAt === undefined ? {} : { previousCreatedAt }),
    ...(completedAt === undefined ? {} : { completedAt }),
  };
}

/** Returns whether unknown persisted data is a supported transcript stamp. */
export function isTranscriptStampData(
  value: unknown,
): value is TranscriptStampData {
  if (!isRecord(value)) return false;
  if (value.version !== 1 && value.version !== 2 && value.version !== 3) {
    return false;
  }
  if (value.role !== "user" && value.role !== "assistant") return false;
  if (!isValidTimestamp(value.createdAt)) return false;

  if (
    value.previousCreatedAt !== undefined &&
    !isValidTimestamp(value.previousCreatedAt)
  ) {
    return false;
  }

  if (value.completedAt !== undefined) {
    if (value.role !== "assistant") return false;
    if (!isValidTimestamp(value.completedAt)) return false;
    if (value.completedAt < value.createdAt) return false;
  }

  if (value.version === 1) {
    return hasOnlyKeys(value, TRANSCRIPT_STAMP_V1_KEYS);
  }

  if (value.role !== "assistant") return false;
  if (!isValidTimestamp(value.turnStartedAt)) return false;
  if (!isValidTimestamp(value.turnCompletedAt)) return false;
  if (value.turnStartedAt > value.createdAt) return false;
  if (value.turnCompletedAt < value.createdAt) return false;
  if (
    value.completedAt !== undefined &&
    value.completedAt > value.turnCompletedAt
  ) {
    return false;
  }

  if (value.version === 2) {
    return hasOnlyKeys(value, TRANSCRIPT_STAMP_V2_KEYS);
  }

  if (
    value.firstContentAt !== undefined &&
    (!isValidTimestamp(value.firstContentAt) ||
      value.firstContentAt < value.turnStartedAt ||
      value.firstContentAt > (value.completedAt ?? value.turnCompletedAt))
  ) {
    return false;
  }
  if (
    value.outputTokens !== undefined &&
    !isSafeCount(value.outputTokens, true)
  ) {
    return false;
  }
  if (!hasValidToolPerformance(value)) return false;

  return hasOnlyKeys(value, TRANSCRIPT_STAMP_V3_KEYS);
}

/** Formats a stamp using the extension's fixed local-time presentation. */
export function formatTranscriptStamp(
  stamp: Readonly<TranscriptStampData>,
): string | undefined {
  if (!isTranscriptStampData(stamp)) return undefined;

  const created = new Date(stamp.createdAt);
  const hour =
    TRANSCRIPT_STAMP_DEFAULTS.hourCycle === "24h"
      ? created.getHours()
      : created.getHours() % 12 || 12;
  const timeParts = [
    String(hour).padStart(2, "0"),
    String(created.getMinutes()).padStart(2, "0"),
    ...(TRANSCRIPT_STAMP_DEFAULTS.showSeconds
      ? [String(created.getSeconds()).padStart(2, "0")]
      : []),
  ];
  const period =
    TRANSCRIPT_STAMP_DEFAULTS.hourCycle === "12h"
      ? created.getHours() < 12
        ? " AM"
        : " PM"
      : "";
  const timeZone = TRANSCRIPT_STAMP_DEFAULTS.showTimeZone
    ? ` ${formatLocalUtcOffset(created)}`
    : "";
  const time = `${timeParts.join(":")}${period}${timeZone}`;
  const date = [
    created.getFullYear(),
    String(created.getMonth() + 1).padStart(2, "0"),
    String(created.getDate()).padStart(2, "0"),
  ].join("-");
  const label = shouldShowStampDate(stamp) ? `${date} · ${time}` : time;

  if (stamp.role !== "assistant") return label;

  const metrics: string[] = [];
  if (
    stamp.version === 3 &&
    stamp.firstContentAt !== undefined &&
    TRANSCRIPT_STAMP_DEFAULTS.showFirstContentLatency
  ) {
    metrics.push(
      `first ${formatElapsedTime(stamp.firstContentAt - stamp.turnStartedAt)}`,
    );
  }
  if (
    stamp.completedAt !== undefined &&
    TRANSCRIPT_STAMP_DEFAULTS.showAssistantDuration
  ) {
    metrics.push(
      `response ${formatElapsedTime(stamp.completedAt - stamp.createdAt)}`,
    );
  }
  if (
    (stamp.version === 2 || stamp.version === 3) &&
    TRANSCRIPT_STAMP_DEFAULTS.showTurnDuration
  ) {
    metrics.push(
      `turn ${formatElapsedTime(stamp.turnCompletedAt - stamp.turnStartedAt)}`,
    );
  }
  if (
    stamp.version === 3 &&
    stamp.toolStartedAt !== undefined &&
    stamp.toolCompletedAt !== undefined &&
    stamp.toolCount !== undefined &&
    TRANSCRIPT_STAMP_DEFAULTS.showToolPerformance
  ) {
    const errors =
      stamp.toolErrorCount === undefined || stamp.toolErrorCount === 0
        ? ""
        : `/${stamp.toolErrorCount}err`;
    metrics.push(
      `tools ${formatElapsedTime(stamp.toolCompletedAt - stamp.toolStartedAt)}×${stamp.toolCount}${errors}`,
    );
  }
  if (stamp.version === 3 && TRANSCRIPT_STAMP_DEFAULTS.showTokenRate) {
    const tokenRate = formatTokenRate(stamp);
    if (tokenRate) metrics.push(tokenRate);
  }

  return metrics.length > 0 ? `${label} · ${metrics.join(" · ")}` : label;
}

/** Message sidecar missing from the active branch after clone or tree navigation. */
export interface UnstampedTranscriptMessage {
  role: TranscriptStampData["role"];
  createdAt: number;
}

/** Finds the latest user or assistant message without a following stamp entry. */
export function findLatestUnstampedTranscriptMessage(
  entries: readonly unknown[],
): UnstampedTranscriptMessage | undefined {
  for (
    let messageIndex = entries.length - 1;
    messageIndex >= 0;
    messageIndex -= 1
  ) {
    const entry = entries[messageIndex];
    if (!isRecord(entry) || entry.type !== "message") continue;
    if (!isRecord(entry.message)) continue;
    if (entry.message.role !== "user" && entry.message.role !== "assistant") {
      continue;
    }
    if (!isValidTimestamp(entry.message.timestamp)) continue;

    for (let index = messageIndex + 1; index < entries.length; index += 1) {
      const candidate = entries[index];
      if (!isRecord(candidate)) continue;
      if (candidate.type !== "custom") continue;
      if (candidate.customType !== TRANSCRIPT_STAMP_ENTRY_TYPE) continue;
      if (!isTranscriptStampData(candidate.data)) continue;
      if (candidate.data.role !== entry.message.role) continue;
      if (candidate.data.createdAt !== entry.message.timestamp) continue;

      return undefined;
    }

    return {
      role: entry.message.role,
      createdAt: entry.message.timestamp,
    };
  }

  return undefined;
}

/** Finds the latest compatible stamp time on the active session branch. */
export function findLatestTranscriptStampTime(
  entries: readonly unknown[],
): number | undefined {
  for (let index = entries.length - 1; index >= 0; index -= 1) {
    const entry = entries[index];
    if (!isRecord(entry)) continue;
    if (entry.type !== "custom") continue;
    if (entry.customType !== TRANSCRIPT_STAMP_ENTRY_TYPE) continue;
    if (!isTranscriptStampData(entry.data)) continue;

    return entry.data.createdAt;
  }

  return undefined;
}

function shouldShowStampDate(stamp: Readonly<TranscriptStampData>): boolean {
  if (TRANSCRIPT_STAMP_DEFAULTS.dateContext === "never") return false;
  if (stamp.previousCreatedAt === undefined) {
    return TRANSCRIPT_STAMP_DEFAULTS.dateContext === "first-and-day-change";
  }

  const current = new Date(stamp.createdAt);
  const previous = new Date(stamp.previousCreatedAt);
  return (
    current.getFullYear() !== previous.getFullYear() ||
    current.getMonth() !== previous.getMonth() ||
    current.getDate() !== previous.getDate()
  );
}

function formatLocalUtcOffset(date: Date): string {
  const offsetMinutes = -date.getTimezoneOffset();
  const sign = offsetMinutes < 0 ? "-" : "+";
  const absoluteOffsetMinutes = Math.abs(offsetMinutes);
  const hours = Math.floor(absoluteOffsetMinutes / 60);
  const minutes = absoluteOffsetMinutes % 60;

  return `UTC${sign}${String(hours).padStart(2, "0")}:${String(minutes).padStart(2, "0")}`;
}

function formatTokenRate(
  stamp: Readonly<TranscriptStampDataV3>,
): string | undefined {
  if (
    stamp.outputTokens === undefined ||
    stamp.outputTokens === 0 ||
    stamp.firstContentAt === undefined ||
    stamp.completedAt === undefined ||
    stamp.completedAt <= stamp.firstContentAt
  ) {
    return undefined;
  }

  const tokensPerSecond =
    stamp.outputTokens / ((stamp.completedAt - stamp.firstContentAt) / 1_000);
  if (!Number.isFinite(tokensPerSecond)) return undefined;

  const precision = tokensPerSecond < 10 ? 1 : 0;
  return `${tokensPerSecond.toFixed(precision)} tok/s`;
}

function formatElapsedTime(elapsedMilliseconds: number): string {
  if (elapsedMilliseconds < 1_000) return `${elapsedMilliseconds}ms`;
  if (elapsedMilliseconds < 60_000) {
    const seconds = Math.round(elapsedMilliseconds / 100) / 10;
    return `${seconds.toFixed(seconds < 10 ? 1 : 0)}s`;
  }

  const totalSeconds = Math.round(elapsedMilliseconds / 1_000);
  const minutes = Math.floor(totalSeconds / 60);
  const seconds = totalSeconds % 60;
  return `${minutes}m ${String(seconds).padStart(2, "0")}s`;
}

function hasValidToolPerformance(value: Record<string, unknown>): boolean {
  const hasStartedAt = value.toolStartedAt !== undefined;
  const hasCompletedAt = value.toolCompletedAt !== undefined;
  const hasCount = value.toolCount !== undefined;
  const hasErrorCount = value.toolErrorCount !== undefined;
  if (!hasStartedAt && !hasCompletedAt && !hasCount && !hasErrorCount) {
    return true;
  }
  if (!hasStartedAt || !hasCompletedAt || !hasCount || !hasErrorCount) {
    return false;
  }

  if (!isValidTimestamp(value.turnStartedAt)) return false;
  if (!isValidTimestamp(value.turnCompletedAt)) return false;

  return (
    isValidTimestamp(value.toolStartedAt) &&
    isValidTimestamp(value.toolCompletedAt) &&
    value.toolStartedAt >= value.turnStartedAt &&
    value.toolCompletedAt >= value.toolStartedAt &&
    value.toolCompletedAt <= value.turnCompletedAt &&
    isSafeCount(value.toolCount, false) &&
    isSafeCount(value.toolErrorCount, true) &&
    value.toolErrorCount <= value.toolCount
  );
}

function isSafeCount(value: unknown, allowZero: boolean): value is number {
  return (
    typeof value === "number" &&
    Number.isSafeInteger(value) &&
    value >= (allowZero ? 0 : 1)
  );
}

function isValidTimestamp(value: unknown): value is number {
  return (
    typeof value === "number" &&
    Number.isFinite(value) &&
    !Number.isNaN(new Date(value).getTime())
  );
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function hasOnlyKeys(
  value: Record<string, unknown>,
  allowedKeys: ReadonlySet<string>,
): boolean {
  return Object.keys(value).every((key) => allowedKeys.has(key));
}
