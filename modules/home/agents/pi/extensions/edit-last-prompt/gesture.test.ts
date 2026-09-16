import assert from "node:assert/strict";
import test from "node:test";

import { EditLastPromptGesture, findLatestUserMessageId } from "./gesture.ts";

test("double Escape edits the last prompt when the first press interrupts a run", () => {
  const gesture = new EditLastPromptGesture();

  assert.equal(gesture.handleEscape(1_000, false, true), "pass-through");
  assert.equal(gesture.handleEscape(1_300, true, true), "edit-last-prompt");
});

test("double Escape while idle remains available to Pi's built-in action", () => {
  const gesture = new EditLastPromptGesture();

  assert.equal(gesture.handleEscape(1_000, true, true), "pass-through");
  assert.equal(gesture.handleEscape(1_300, true, true), "pass-through");
});

test("draft input and expired sequences do not edit the last prompt", () => {
  const gesture = new EditLastPromptGesture();

  assert.equal(gesture.handleEscape(1_000, false, false), "pass-through");
  assert.equal(gesture.handleEscape(1_100, true, true), "pass-through");
  assert.equal(gesture.handleEscape(1_600, true, true), "pass-through");

  gesture.handleEscape(2_000, false, true);
  gesture.reset();
  assert.equal(gesture.handleEscape(2_100, true, true), "pass-through");
});

test("latest user message lookup ignores assistant and metadata entries", () => {
  const entries = [
    { id: "user-1", type: "message", message: { role: "user" } },
    { id: "assistant-1", type: "message", message: { role: "assistant" } },
    { id: "model-1", type: "model_change" },
    { id: "user-2", type: "message", message: { role: "user" } },
    { id: "assistant-2", type: "message", message: { role: "assistant" } },
  ];

  assert.equal(findLatestUserMessageId(entries), "user-2");
  assert.equal(findLatestUserMessageId(entries.slice(1, 3)), undefined);
});
