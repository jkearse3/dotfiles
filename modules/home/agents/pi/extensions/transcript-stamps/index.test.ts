import assert from "node:assert/strict";
import test from "node:test";

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

import {
  AGENT_ELAPSED_ENTRY_TYPE,
  formatAgentElapsed,
  isAgentElapsedData,
  type AgentElapsedData,
} from "./agent-elapsed.ts";
import { registerTranscriptStampLifecycle } from "./lifecycle.ts";
import {
  formatTranscriptStamp,
  TRANSCRIPT_STAMP_ENTRY_TYPE,
  type TranscriptStampData,
} from "./stamp.ts";

type EventHandler = (event: any, context: any) => unknown;

interface ExtensionHarness {
  appended: TranscriptStampData[];
  elapsed: AgentElapsedData[];
  branch: unknown[];
  emit: (event: string, value?: unknown) => void;
  startSession: (mode?: string) => void;
}

function createExtensionHarness(): ExtensionHarness {
  const handlers = new Map<string, EventHandler>();
  const appended: TranscriptStampData[] = [];
  const elapsed: AgentElapsedData[] = [];
  const harness: ExtensionHarness = {
    appended,
    elapsed,
    branch: [],
    emit(event, value = {}) {
      const handler = handlers.get(event);
      assert.ok(handler, `missing ${event} handler`);
      handler(value, {
        mode: "tui",
        sessionManager: { getBranch: () => harness.branch },
      });
    },
    startSession(mode = "tui") {
      const handler = handlers.get("session_start");
      assert.ok(handler);
      handler(
        {},
        {
          mode,
          sessionManager: { getBranch: () => harness.branch },
        },
      );
    },
  };
  const api = {
    appendEntry(
      customType: string,
      data: TranscriptStampData | AgentElapsedData,
    ) {
      if (customType === TRANSCRIPT_STAMP_ENTRY_TYPE) {
        appended.push(data as TranscriptStampData);
      } else {
        assert.equal(customType, AGENT_ELAPSED_ENTRY_TYPE);
        elapsed.push(data as AgentElapsedData);
      }
    },
    on(event: string, handler: EventHandler) {
      handlers.set(event, handler);
    },
    registerEntryRenderer() {},
  };

  registerTranscriptStampLifecycle(api as unknown as ExtensionAPI);
  return harness;
}

function withClock(observations: number[], run: () => void): void {
  const originalNow = Date.now;
  Date.now = () => {
    const observation = observations.shift();
    if (observation === undefined) {
      throw new Error("unexpected Date.now observation");
    }
    return observation;
  };
  try {
    run();
    assert.deepEqual(observations, []);
  } finally {
    Date.now = originalNow;
  }
}

function localUtcOffset(timestamp: number): string {
  const offsetMinutes = -new Date(timestamp).getTimezoneOffset();
  const sign = offsetMinutes < 0 ? "-" : "+";
  const absoluteOffsetMinutes = Math.abs(offsetMinutes);
  const hours = Math.floor(absoluteOffsetMinutes / 60);
  const minutes = absoluteOffsetMinutes % 60;

  return `UTC${sign}${String(hours).padStart(2, "0")}:${String(minutes).padStart(2, "0")}`;
}

test("lifecycle stamps finalized queued messages and parallel tools", () => {
  const harness = createExtensionHarness();
  const base = new Date(2026, 0, 2, 14, 0, 0).getTime();
  harness.startSession();

  harness.emit("message_end", {
    message: { role: "user", timestamp: base + 1_000 },
  });
  harness.emit("message_end", {
    message: { role: "user", timestamp: base + 1_200 },
  });
  harness.branch = [
    {
      type: "message",
      message: { role: "user", timestamp: base + 1_100 },
    },
    {
      type: "message",
      message: { role: "user", timestamp: base + 1_300 },
    },
  ];

  withClock(
    [2_000, 2_500, 2_600, 2_700, 3_300, 3_500, 4_000, 5_000].map(
      (offset) => base + offset,
    ),
    () => {
      harness.emit("turn_start");
      harness.emit("message_start", {
        message: { role: "assistant", timestamp: base + 2_100 },
      });
      harness.emit("message_update", {
        message: { role: "assistant", timestamp: base + 2_100 },
        assistantMessageEvent: { type: "text_delta", delta: "first" },
      });
      harness.emit("tool_execution_start", { toolCallId: "a" });
      harness.emit("tool_execution_start", { toolCallId: "b" });
      harness.emit("tool_execution_end", { toolCallId: "b", isError: true });
      harness.emit("tool_execution_end", { toolCallId: "a", isError: false });
      harness.emit("message_end", {
        message: {
          role: "assistant",
          timestamp: base + 2_100,
          usage: { output: 10 },
        },
      });
      harness.emit("turn_end", {
        message: {
          role: "assistant",
          timestamp: base + 2_200,
          usage: { output: 20 },
        },
      });
    },
  );

  assert.equal(harness.appended.length, 3);
  assert.deepEqual(harness.appended[0], {
    version: 1,
    role: "user",
    createdAt: base + 1_100,
  });
  assert.deepEqual(harness.appended[1], {
    version: 1,
    role: "user",
    createdAt: base + 1_300,
    previousCreatedAt: base + 1_100,
  });
  assert.equal(harness.appended[2]?.createdAt, base + 2_200);
  assert.equal(
    formatTranscriptStamp(harness.appended[2]!),
    `14:00:02 ${localUtcOffset(base + 2_200)} · first 500ms · response 1.8s · turn 3.0s · tools 900ms×2/1err · 13 tok/s`,
  );
});

test("non-TUI sessions do not persist transcript stamps", () => {
  const harness = createExtensionHarness();
  harness.startSession("rpc");
  harness.emit("message_end", {
    message: { role: "user", timestamp: 1_000 },
  });
  harness.emit("agent_end");

  assert.deepEqual(harness.appended, []);
  assert.deepEqual(harness.elapsed, []);
});

test("agent elapsed covers multiple turns and steering until settled, once", () => {
  const harness = createExtensionHarness();
  harness.startSession();
  withClock([1_000, 2_000, 3_000, 5_000], () => {
    harness.emit("agent_start");
    harness.emit("agent_end");
    harness.emit("agent_start"); // queued continuation does not restart the clock
    harness.emit("turn_end", {
      message: { role: "assistant", timestamp: 1_200, usage: { output: 0 } },
    });
    harness.emit("agent_end");
    harness.emit("agent_start"); // steer or queued follow-up in the same busy period
    harness.emit("turn_end", {
      message: { role: "assistant", timestamp: 2_200, usage: { output: 0 } },
    });
    harness.emit("agent_settled");
    harness.emit("agent_settled");
  });
  assert.deepEqual(harness.elapsed, [
    {
      version: 1,
      startedAt: 1_000,
      settledAt: 5_000,
      turnCount: 2,
      interrupted: false,
    },
  ]);
  assert.equal(formatAgentElapsed(harness.elapsed[0]!), "agent 4.0s · 2 turns");
});

test("agent elapsed marks aborted work and handles a run without assistant turns", () => {
  const harness = createExtensionHarness();
  harness.startSession();
  withClock([1_000, 1_100, 1_300, 2_000, 2_500], () => {
    harness.emit("agent_start");
    harness.emit("message_end", {
      message: { role: "assistant", timestamp: 1_010, stopReason: "aborted" },
    });
    harness.emit("agent_settled");
    harness.emit("agent_start");
    harness.emit("agent_settled");
  });
  assert.equal(
    formatAgentElapsed(harness.elapsed[0]!),
    "agent 300ms · 0 turns · interrupted",
  );
  assert.equal(
    formatAgentElapsed(harness.elapsed[1]!),
    "agent 500ms · 0 turns",
  );
});

test("a successful continuation clears the interrupted label", () => {
  const harness = createExtensionHarness();
  harness.startSession();
  withClock([1_000, 1_100, 1_500, 2_000], () => {
    harness.emit("agent_start");
    harness.emit("message_end", {
      message: { role: "assistant", timestamp: 1_010, stopReason: "aborted" },
    });
    harness.emit("agent_end");
    harness.emit("agent_start");
    harness.emit("message_end", {
      message: { role: "assistant", timestamp: 1_200, stopReason: "stop" },
    });
    harness.emit("agent_settled");
  });
  assert.equal(formatAgentElapsed(harness.elapsed[0]!), "agent 1.0s · 0 turns");
});

test("tree navigation discards an active busy period", () => {
  const harness = createExtensionHarness();
  harness.startSession();
  withClock([1_000], () => harness.emit("agent_start"));
  harness.emit("session_tree");
  harness.emit("agent_settled");
  assert.deepEqual(harness.elapsed, []);
});

test("agent elapsed rejects malformed persisted sidecars", () => {
  const valid = {
    version: 1,
    startedAt: 1_000,
    settledAt: 2_000,
    turnCount: 1,
    interrupted: false,
  };
  assert.equal(isAgentElapsedData(valid), true);
  assert.equal(isAgentElapsedData({ ...valid, settledAt: 999 }), false);
  assert.equal(isAgentElapsedData({ ...valid, turnCount: -1 }), false);
  assert.equal(isAgentElapsedData({ ...valid, extra: true }), false);
  assert.equal(isAgentElapsedData({ ...valid, interrupted: undefined }), false);
});
