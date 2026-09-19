import assert from "node:assert/strict";
import test from "node:test";

import { createRightAlignedTranscriptStamp } from "./renderer.ts";

test("renderer reserves the final column for the scrollbar", () => {
  const component = createRightAlignedTranscriptStamp("stamp", (text) => text, {
    truncate: (text, width) => text.slice(0, width),
    measure: (text) => text.length,
  });

  assert.deepEqual(component.render(9), ["   stamp "]);
  assert.deepEqual(component.render(4), ["sta "]);
  assert.deepEqual(component.render(1), [" "]);
});
