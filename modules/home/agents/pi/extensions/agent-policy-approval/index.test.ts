import assert from "node:assert/strict";
import test from "node:test";

import type {
  ExtensionAPI,
  ToolCallEvent,
} from "@earendil-works/pi-coding-agent";

import agentPolicyApprovalExtension, {
  DECLINED_REASON,
  NO_UI_REASON,
} from "./index.ts";

type ToolCallHandler = (event: ToolCallEvent, context: unknown) => unknown;

interface GateHarness {
  confirmations: { title: string; message: string }[];
  call(
    event: ToolCallEvent,
    ui: { hasUI: boolean; approve?: boolean },
  ): Promise<unknown>;
}

function createGateHarness(): GateHarness {
  const handlers: ToolCallHandler[] = [];
  const api = {
    on(event: string, handler: ToolCallHandler) {
      assert.equal(event, "tool_call");
      handlers.push(handler);
    },
  };
  agentPolicyApprovalExtension(api as unknown as ExtensionAPI);
  assert.equal(handlers.length, 1);

  const confirmations: GateHarness["confirmations"] = [];
  return {
    confirmations,
    call(event, { hasUI, approve = false }) {
      return Promise.resolve(
        handlers[0]!(event, {
          hasUI,
          ui: {
            async confirm(title: string, message: string) {
              confirmations.push({ title, message });
              return approve;
            },
          },
        }),
      );
    },
  };
}

function bashCall(command: string): ToolCallEvent {
  return {
    type: "tool_call",
    toolCallId: "call-1",
    toolName: "bash",
    input: { command },
  };
}

const approvalCommand =
  "AGENT_POLICY_APPROVE=jj.git-push jj git push -b feature";

test("an approval request without a UI is blocked unasked", async () => {
  const gate = createGateHarness();
  assert.deepEqual(
    await gate.call(bashCall(approvalCommand), { hasUI: false }),
    { block: true, reason: NO_UI_REASON },
  );
  assert.deepEqual(gate.confirmations, []);
});

test("a declined approval request is blocked", async () => {
  const gate = createGateHarness();
  assert.deepEqual(
    await gate.call(bashCall(approvalCommand), { hasUI: true }),
    { block: true, reason: DECLINED_REASON },
  );
  assert.equal(gate.confirmations.length, 1);
  assert.equal(gate.confirmations[0]!.message, approvalCommand);
});

test("an approved request runs", async () => {
  const gate = createGateHarness();
  assert.equal(
    await gate.call(bashCall(approvalCommand), { hasUI: true, approve: true }),
    undefined,
  );
  assert.equal(gate.confirmations.length, 1);
});

test("the marker anywhere in a bash command asks", async () => {
  const gate = createGateHarness();
  for (const command of [
    "cd repo && AGENT_POLICY_APPROVE=git.push git push",
    "export AGENT_POLICY_APPROVE=jj.git-push",
    "env AGENT_POLICY_APPROVE= jj git push",
  ]) {
    assert.deepEqual(await gate.call(bashCall(command), { hasUI: false }), {
      block: true,
      reason: NO_UI_REASON,
    });
  }
});

test("other bash commands and other tools pass unasked", async () => {
  const gate = createGateHarness();
  for (const event of [
    bashCall("jj git push -b feature"),
    bashCall("echo AGENT_POLICY_APPROVE"),
    {
      type: "tool_call",
      toolCallId: "call-2",
      toolName: "write",
      input: { path: "notes.txt", content: approvalCommand },
    } satisfies ToolCallEvent,
  ]) {
    assert.equal(await gate.call(event, { hasUI: false }), undefined);
    assert.equal(await gate.call(event, { hasUI: true }), undefined);
  }
  assert.deepEqual(gate.confirmations, []);
});
