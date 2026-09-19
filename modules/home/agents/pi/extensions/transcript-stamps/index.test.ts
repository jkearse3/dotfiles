import assert from "node:assert/strict";
import test from "node:test";

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

import { registerTranscriptStampLifecycle } from "./lifecycle.ts";
import {
  formatTranscriptStamp,
  TRANSCRIPT_STAMP_ENTRY_TYPE,
  type TranscriptStampData,
} from "./stamp.ts";

type EventHandler = (event: any, context: any) => unknown;

interface ExtensionHarness {
  appended: TranscriptStampData[];
  branch: unknown[];
  emit: (event: string, value?: unknown) => void;
  startSession: (mode?: string) => void;
}

function createExtensionHarness(): ExtensionHarness {
  const handlers = new Map<string, EventHandler>();
  const appended: TranscriptStampData[] = [];
  const harness: ExtensionHarness = {
    appended,
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
    appendEntry(customType: string, data: TranscriptStampData) {
      assert.equal(customType, TRANSCRIPT_STAMP_ENTRY_TYPE);
      appended.push(data);
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
});
