import assert from "node:assert/strict";
import test from "node:test";

import {
  createLeftAlignedTranscriptStamp,
  createToggleableTranscriptStamp,
} from "./renderer.ts";

test("renderer reserves the final column for the scrollbar", () => {
  const component = createLeftAlignedTranscriptStamp("stamp", (text) => text, {
    truncate: (text, width) => text.slice(0, width),
    measure: (text) => text.length,
  });

  assert.deepEqual(component.render(9), ["stamp    "]);
  assert.deepEqual(component.render(4), ["sta "]);
  assert.deepEqual(component.render(1), [" "]);
});

test("assistant timing row appears in place only when toggled on", () => {
  const stamp = createLeftAlignedTranscriptStamp("stamp", (text) => text, {
    truncate: (text, width) => text.slice(0, width),
    measure: (text) => text.length,
  });
  let visible = false;
  const component = createToggleableTranscriptStamp(stamp, () => visible);

  assert.deepEqual(component.render(9), []);
  visible = true;
  assert.deepEqual(component.render(9), ["stamp    "]);
  visible = false;
  assert.deepEqual(component.render(9), []);
  visible = true;
  component.invalidate();
  assert.deepEqual(component.render(4), ["sta "]);
});
