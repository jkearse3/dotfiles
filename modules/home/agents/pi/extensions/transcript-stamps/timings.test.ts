import assert from "node:assert/strict";
import test from "node:test";

import type {
  ExtensionAPI,
  ExtensionCommandContext,
} from "@earendil-works/pi-coding-agent";

import { createInlineTimingsState, registerTimingsCommand } from "./timings.ts";

test("inline turn timings default to hidden and toggle in both directions", () => {
  const state = createInlineTimingsState();
  assert.equal(state.isVisible(), false);
  assert.equal(state.toggle(), true);
  assert.equal(state.isVisible(), true);
  assert.equal(state.toggle(), false);
  assert.equal(state.isVisible(), false);
});

test("/timings toggles assistant rows without reading or mutating session entries", async () => {
  const state = createInlineTimingsState();
  let handler:
    | ((args: string, context: ExtensionCommandContext) => Promise<void>)
    | undefined;
  const api = {
    registerCommand(name: string, options: { handler: typeof handler }) {
      assert.equal(name, "timings");
      handler = options.handler;
    },
  } as unknown as ExtensionAPI;
  registerTimingsCommand(api, state);
  assert.ok(handler);

  const notices: string[] = [];
  const context = {
    mode: "tui",
    ui: {
      notify: (text: string) => notices.push(text),
    },
  } as unknown as ExtensionCommandContext;
  await handler("", context);
  await handler("", context);
  assert.deepEqual(notices, ["Turn timings shown", "Turn timings hidden"]);
  assert.equal(state.isVisible(), false);
});

test("/timings does not change presentation outside interactive mode", async () => {
  const state = createInlineTimingsState();
  let handler:
    | ((args: string, context: ExtensionCommandContext) => Promise<void>)
    | undefined;
  const api = {
    registerCommand(_name: string, options: { handler: typeof handler }) {
      handler = options.handler;
    },
  } as unknown as ExtensionAPI;
  registerTimingsCommand(api, state);
  assert.ok(handler);

  await handler("", { mode: "print" } as ExtensionCommandContext);
  assert.equal(state.isVisible(), false);
});
