import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

import {
  AGENT_ELAPSED_ENTRY_TYPE,
  isAgentElapsedData,
} from "./agent-elapsed.ts";
import {
  createTranscriptStamp,
  findLatestVisibleTranscriptStampTime,
  findLatestUnstampedTranscriptMessage,
  isTranscriptStampData,
  TRANSCRIPT_STAMP_ENTRY_TYPE,
  type TranscriptStampData,
  type TranscriptTurnPerformance,
} from "./stamp.ts";

interface ActiveToolObservation {
  startedAt: number;
}

interface ToolPerformanceObservation {
  startedAt: number;
  completedAt: number;
  count: number;
  errorCount: number;
}

const MAX_TRACKED_TOOLS_PER_TURN = 256;

/** Persists timestamp and performance sidecars for interactive transcript turns. */
export function registerTranscriptStampLifecycle(pi: ExtensionAPI): void {
  let tuiSessionActive = false;
  let previousCreatedAt: number | undefined;
  let pendingUserCreatedAt: number[] = [];
  let pendingAssistantResponseCompletedAt: number | undefined;
  let activeTurnStartedAt: number | undefined;
  let firstContentAt: number | undefined;
  let toolPerformance: ToolPerformanceObservation | undefined;
  const activeTools = new Map<string, ActiveToolObservation>();
  let agentStartedAt: number | undefined;
  let agentTurnCount = 0;
  let agentInterrupted = false;

  const appendStamp = (stamp: TranscriptStampData): void => {
    if (!tuiSessionActive || !isTranscriptStampData(stamp)) return;

    pi.appendEntry<TranscriptStampData>(TRANSCRIPT_STAMP_ENTRY_TYPE, stamp);
    if (stamp.role === "user") previousCreatedAt = stamp.createdAt;
  };

  const flushPendingUserStamps = (): void => {
    for (const createdAt of pendingUserCreatedAt) {
      appendStamp(createTranscriptStamp("user", createdAt, previousCreatedAt));
    }

    pendingUserCreatedAt = [];
  };

  const flushFinalizedUserStamps = (entries: readonly unknown[]): void => {
    const finalizedCreatedAt = findLatestUserMessageTimes(
      entries,
      pendingUserCreatedAt.length,
    );
    if (finalizedCreatedAt.length === pendingUserCreatedAt.length) {
      pendingUserCreatedAt = finalizedCreatedAt;
    }
    flushPendingUserStamps();
  };

  const resetTurnPerformance = (): void => {
    pendingAssistantResponseCompletedAt = undefined;
    activeTurnStartedAt = undefined;
    firstContentAt = undefined;
    toolPerformance = undefined;
    activeTools.clear();
  };
  const resetAgentElapsed = (): void => {
    agentStartedAt = undefined;
    agentTurnCount = 0;
    agentInterrupted = false;
  };

  const synchronizeBranch = (entries: readonly unknown[]): void => {
    pendingUserCreatedAt = [];
    resetAgentElapsed();
    resetTurnPerformance();
    previousCreatedAt = findLatestVisibleTranscriptStampTime(entries);

    const unstampedMessage = findLatestUnstampedTranscriptMessage(entries);
    if (!unstampedMessage) return;

    appendStamp(
      createTranscriptStamp(
        unstampedMessage.role,
        unstampedMessage.createdAt,
        previousCreatedAt,
      ),
    );
  };

  pi.on("session_start", (_event, ctx) => {
    tuiSessionActive = ctx.mode === "tui";
    synchronizeBranch(ctx.sessionManager.getBranch());
  });

  pi.on("session_tree", (_event, ctx) => {
    synchronizeBranch(ctx.sessionManager.getBranch());
  });

  pi.on("agent_start", () => {
    if (tuiSessionActive && agentStartedAt === undefined) {
      agentStartedAt = Date.now();
    }
  });
  pi.on("turn_start", () => {
    resetTurnPerformance();
    activeTurnStartedAt = tuiSessionActive ? Date.now() : undefined;
  });

  pi.on("message_start", (event, ctx) => {
    if (event.message.role === "assistant") {
      flushFinalizedUserStamps(ctx.sessionManager.getBranch());
    }
  });

  pi.on("message_update", (event) => {
    if (!tuiSessionActive || firstContentAt !== undefined) return;
    if (event.message.role !== "assistant") return;
    if (!isMeaningfulAssistantUpdate(event.assistantMessageEvent)) return;

    const observedAt = Date.now();
    if (
      activeTurnStartedAt !== undefined &&
      observedAt >= activeTurnStartedAt
    ) {
      firstContentAt = observedAt;
    }
  });

  pi.on("tool_execution_start", (event) => {
    if (!tuiSessionActive || activeTurnStartedAt === undefined) return;
    if (
      activeTools.size + (toolPerformance?.count ?? 0) >=
      MAX_TRACKED_TOOLS_PER_TURN
    ) {
      return;
    }
    if (activeTools.has(event.toolCallId)) return;

    const startedAt = Date.now();
    if (startedAt < activeTurnStartedAt) return;

    activeTools.set(event.toolCallId, { startedAt });
  });

  pi.on("tool_execution_end", (event) => {
    const tool = activeTools.get(event.toolCallId);
    if (!tool) return;
    activeTools.delete(event.toolCallId);

    const completedAt = Date.now();
    if (completedAt < tool.startedAt) return;

    if (!toolPerformance) {
      toolPerformance = {
        startedAt: tool.startedAt,
        completedAt,
        count: 1,
        errorCount: event.isError ? 1 : 0,
      };
      return;
    }

    toolPerformance.startedAt = Math.min(
      toolPerformance.startedAt,
      tool.startedAt,
    );
    toolPerformance.completedAt = Math.max(
      toolPerformance.completedAt,
      completedAt,
    );
    toolPerformance.count += 1;
    if (event.isError) toolPerformance.errorCount += 1;
  });

  pi.on("message_end", (event) => {
    if (!tuiSessionActive) return;

    if (event.message.role === "user") {
      pendingUserCreatedAt.push(event.message.timestamp);
      return;
    }
    if (event.message.role !== "assistant") return;
    if (agentStartedAt !== undefined) {
      agentInterrupted = event.message.stopReason === "aborted";
    }

    const responseCompletedAt = Date.now();
    pendingAssistantResponseCompletedAt =
      responseCompletedAt >= event.message.timestamp
        ? responseCompletedAt
        : undefined;
  });

  pi.on("turn_end", (event) => {
    const observedResponseCompletedAt = pendingAssistantResponseCompletedAt;
    const turnStartedAt = activeTurnStartedAt;
    const observedFirstContentAt = firstContentAt;
    const observedToolPerformance = toolPerformance;
    resetTurnPerformance();

    if (event.message.role !== "assistant") return;

    if (agentStartedAt !== undefined) {
      agentTurnCount += 1;
      agentInterrupted = event.message.stopReason === "aborted";
    }

    const createdAt = event.message.timestamp;
    const outputTokens = event.message.usage.output;
    const responseCompletedAt =
      observedResponseCompletedAt !== undefined &&
      observedResponseCompletedAt >= createdAt
        ? observedResponseCompletedAt
        : undefined;

    const turnCompletedAt = Date.now();
    let turnPerformance: TranscriptTurnPerformance | undefined;
    if (
      turnStartedAt !== undefined &&
      turnStartedAt <= createdAt &&
      turnCompletedAt >= createdAt &&
      (responseCompletedAt === undefined ||
        turnCompletedAt >= responseCompletedAt)
    ) {
      turnPerformance = {
        startedAt: turnStartedAt,
        completedAt: turnCompletedAt,
      };
      if (
        observedFirstContentAt !== undefined &&
        observedFirstContentAt >= turnStartedAt &&
        observedFirstContentAt <= (responseCompletedAt ?? turnCompletedAt)
      ) {
        turnPerformance.firstContentAt = observedFirstContentAt;
      }
      if (Number.isSafeInteger(outputTokens) && outputTokens >= 0) {
        turnPerformance.outputTokens = outputTokens;
      }
      if (
        observedToolPerformance !== undefined &&
        observedToolPerformance.startedAt >= turnStartedAt &&
        observedToolPerformance.completedAt <= turnCompletedAt
      ) {
        turnPerformance.tools = observedToolPerformance;
      }
    }
    appendStamp(
      createTranscriptStamp(
        "assistant",
        createdAt,
        previousCreatedAt,
        responseCompletedAt,
        turnPerformance,
      ),
    );
  });

  pi.on("agent_end", (_event, ctx) => {
    flushFinalizedUserStamps(ctx.sessionManager.getBranch());
    resetTurnPerformance();
  });

  pi.on("agent_settled", () => {
    const startedAt = agentStartedAt;
    const turnCount = agentTurnCount;
    const interrupted = agentInterrupted;
    resetAgentElapsed();
    if (!tuiSessionActive || startedAt === undefined) return;

    const data = {
      version: 2 as const,
      startedAt,
      settledAt: Date.now(),
      turnCount,
      interrupted,
      ...(previousCreatedAt === undefined
        ? {}
        : { previousVisibleAt: previousCreatedAt }),
    };
    if (isAgentElapsedData(data)) {
      pi.appendEntry(AGENT_ELAPSED_ENTRY_TYPE, data);
    }
  });
  pi.on("session_shutdown", (_event, ctx) => {
    flushFinalizedUserStamps(ctx.sessionManager.getBranch());
    pendingUserCreatedAt = [];
    resetTurnPerformance();
    resetAgentElapsed();
    previousCreatedAt = undefined;
    tuiSessionActive = false;
  });
}

function findLatestUserMessageTimes(
  entries: readonly unknown[],
  limit: number,
): number[] {
  if (limit < 1) return [];
  const createdAt: number[] = [];
  for (let index = entries.length - 1; index >= 0; index -= 1) {
    const entry = entries[index];
    if (!isRecord(entry) || entry.type !== "message") continue;
    if (!isRecord(entry.message) || entry.message.role !== "user") continue;
    if (!isValidTimestamp(entry.message.timestamp)) continue;

    createdAt.push(entry.message.timestamp);
    if (createdAt.length === limit) break;
  }
  return createdAt.reverse();
}

function isValidTimestamp(value: unknown): value is number {
  return (
    typeof value === "number" &&
    Number.isFinite(value) &&
    !Number.isNaN(new Date(value).getTime())
  );
}

function isMeaningfulAssistantUpdate(value: unknown): boolean {
  if (!isRecord(value) || typeof value.type !== "string") return false;
  if (
    value.type === "text_delta" ||
    value.type === "thinking_delta" ||
    value.type === "toolcall_delta"
  ) {
    return typeof value.delta === "string" && value.delta.length > 0;
  }
  if (value.type === "text_end" || value.type === "thinking_end") {
    return typeof value.content === "string" && value.content.length > 0;
  }
  return value.type === "toolcall_end" && isRecord(value.toolCall);
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
