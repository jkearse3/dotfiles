import assert from "node:assert/strict";
import test from "node:test";

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import {
  AGENT_ELAPSED_ENTRY_TYPE,
  type AgentElapsedData,
} from "./agent-elapsed.ts";
import { registerTranscriptStampLifecycle } from "./lifecycle.ts";

test("working label updates through continuations, resets on settlement, and restarts", (t) => {
  const harness = createHarness();
  t.mock.timers.enable({ apis: ["setInterval"] });
  let now = 0;
  t.mock.method(performance, "now", () => now);
  t.mock.method(Date, "now", () => 1_000 + now);

  harness.emit("agent_start");
  assert.equal(harness.workingMessage, "Working… (0.0s)");
  now = 199;
  t.mock.timers.tick(100);
  assert.equal(harness.workingMessage, "Working… (0.1s)");
  now = 59_999;
  t.mock.timers.tick(100);
  assert.equal(harness.workingMessage, "Working… (59.9s)");
  now = 60_000;
  t.mock.timers.tick(100);
  assert.equal(harness.workingMessage, "Working… (1m 00.0s)");
  now = 61_250;
  t.mock.timers.tick(100);
  assert.equal(harness.workingMessage, "Working… (1m 01.2s)");

  harness.emit("agent_end");
  harness.emit("agent_start");
  now = 62_300;
  t.mock.timers.tick(100);
  assert.equal(harness.workingMessage, "Working… (1m 02.3s)");
  harness.emit("agent_settled");
  assert.equal(harness.workingMessage, undefined);
  assert.deepEqual(harness.elapsed, [
    {
      version: 2,
      startedAt: 1_000,
      settledAt: 63_300,
      turnCount: 0,
      interrupted: false,
    },
  ]);
  const updates = harness.updates;
  t.mock.timers.tick(5_000);
  assert.equal(harness.updates, updates);

  harness.emit("agent_start");
  assert.equal(harness.workingMessage, "Working… (0.0s)");
  harness.emit("session_shutdown");
});

for (const event of ["session_start", "session_tree", "session_shutdown"]) {
  test(`${event} disposes the timer idempotently`, (t) => {
    const harness = createHarness();
    t.mock.timers.enable({ apis: ["setInterval"] });
    harness.emit("agent_start");
    harness.emit(event);
    harness.emit(event);
    assert.equal(harness.workingMessage, undefined);
    const updates = harness.updates;
    t.mock.timers.tick(5_000);
    assert.equal(harness.updates, updates);
  });
}

for (const mode of ["rpc", "json", "print"]) {
  test(`${mode} starts no timer or UI updates`, (t) => {
    const harness = createHarness(mode);
    t.mock.timers.enable({ apis: ["setInterval"] });
    harness.emit("agent_start", mode);
    t.mock.timers.tick(5_000);
    harness.emit("agent_settled", mode);
    assert.equal(harness.updates, 0);
  });
}

function createHarness(mode = "tui") {
  const handlers = new Map<string, (event: unknown, ctx: unknown) => unknown>();
  const harness = {
    elapsed: [] as AgentElapsedData[],
    workingMessage: undefined as string | undefined,
    updates: 0,
    emit(event: string, mode = "tui") {
      handlers.get(event)?.(
        {},
        {
          mode,
          sessionManager: { getBranch: () => [] },
          ui: {
            setWorkingMessage(text?: string) {
              harness.workingMessage = text;
              harness.updates++;
            },
          },
        },
      );
    },
  };
  registerTranscriptStampLifecycle({
    appendEntry(customType: string, data: AgentElapsedData) {
      assert.equal(customType, AGENT_ELAPSED_ENTRY_TYPE);
      harness.elapsed.push(data);
    },
    on(event: string, handler: (event: unknown, ctx: unknown) => unknown) {
      handlers.set(event, handler);
    },
  } as unknown as ExtensionAPI);
  harness.emit("session_start", mode);
  return harness;
}
