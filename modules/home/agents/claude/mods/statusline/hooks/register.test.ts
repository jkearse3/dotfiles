import type { Engine } from "claude-code/testing";
import type { On, RenderNode, SessionContextUsage } from "claude-code";
import { expect, test } from "claude-code/testing";

const FILLED: SessionContextUsage = {
  tokens: 84000,
  window: 200000,
  percent: 42,
};
const FRESH: SessionContextUsage = { window: 200000 };

const ENGINE_HINT = "? for shortcuts";

// The text of a drawn tree, one entry per string node in drawing order.
function drawnText(node: RenderNode): string[] {
  if (typeof node === "string") return [node];
  const children: readonly RenderNode[] =
    "children" in node && Array.isArray(node.children) ? node.children : [];
  return children.flatMap(drawnText);
}

// Answers the engine calls the mod makes and returns the text of the hint
// row as the mod draws it, the engine's own hint drawn as one Text.
function answerEngine(
  on: On,
  answers: { model: () => string; context: SessionContextUsage },
): ($: Engine) => Promise<string[]> {
  on("session.model", () => ({ value: answers.model() }));
  on("session.usage", () => ({
    value: { startedAt: 0, context: answers.context, rateLimits: [] },
  }));
  on("session.start", (_, e) => ({ cwd: e.cwd }));
  on("session.measure", (_, e) => ({ changed: e.changed }));
  on("turn.start", (_, e) => ({ turnId: e.turnId }));
  on("ui.render", () => ({
    type: "Text",
    props: {},
    children: [ENGINE_HINT],
  }));

  return async ($) => {
    const drawn = await $.ui.render({
      surface: "terminal",
      component: "PromptHint",
      requestId: "hint",
      props: { isDraft: false, isWorking: false, hint: ENGINE_HINT },
    });
    return drawnText(drawn);
  };
}

test("leaves the hint row alone before the session starts", async ($, on) => {
  const drawnRow = answerEngine(on, { model: () => "m", context: FILLED });

  expect(await drawnRow($)).toEqual([ENGINE_HINT]);
});

test("shows 0% before the live window has a response", async ($, on) => {
  const drawnRow = answerEngine(on, {
    model: () => "claude-opus-5-5",
    context: FRESH,
  });

  await $.session.start({
    cwd: "/tmp",
    surface: "terminal",
    isInteractive: true,
  });

  expect(await drawnRow($)).toEqual([ENGINE_HINT, "claude-opus-5-5 │ 0%"]);
});

test("shows the context fill once the session is measured", async ($, on) => {
  const drawnRow = answerEngine(on, {
    model: () => "claude-opus-5-5",
    context: FRESH,
  });

  await $.session.measure({
    context: FILLED,
    rateLimits: [],
    changed: ["context"],
  });

  expect(await drawnRow($)).toEqual([
    ENGINE_HINT,
    "claude-opus-5-5 │ 42% 84000/200000",
  ]);
});

test("picks up a model switch at the next turn", async ($, on) => {
  let model = "claude-opus-5-5";
  const drawnRow = answerEngine(on, { model: () => model, context: FILLED });

  await $.session.start({
    cwd: "/tmp",
    surface: "terminal",
    isInteractive: true,
  });
  model = "claude-sonnet-5-5";
  await $.turn.start({ text: "hi", turnId: "t1" });

  expect(await drawnRow($)).toEqual([
    ENGINE_HINT,
    "claude-sonnet-5-5 │ 42% 84000/200000",
  ]);
});
