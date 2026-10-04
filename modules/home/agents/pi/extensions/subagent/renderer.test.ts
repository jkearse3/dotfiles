import assert from "node:assert/strict";
import test from "node:test";
import {
  createSubagentComponent,
  createSubagentTruncator,
} from "./renderer.ts";
import type { SubagentLine } from "./presentation.ts";

const plainTheme = { fg: (_tone: string, text: string) => text };
const layout = {
  truncate: (text: string, width: number) => text.slice(0, width),
};

test("panel truncation keeps the ellipsis inside active ANSI styling", () => {
  const ansi = /\x1b\[[0-?]*[ -/]*[@-~]/gu;
  const truncate = createSubagentTruncator({
    measure: (text) => text.replace(ansi, "").length,
    slice: (text, start, length) => {
      const activeStyle = text.match(/^\x1b\[[0-?]*[ -/]*[@-~]/u)?.[0] ?? "";
      return `${activeStyle}${text.replace(ansi, "").slice(start, start + length)}`;
    },
  });
  const styled = "\x1b[38;5;75mabcdefgh\x1b[39m";
  const truncated = truncate(styled, 5);
  assert.equal(truncated.replace(ansi, ""), "abcd…");
  assert.equal(truncate("abc", 3), "abc");
  assert.equal(truncate("abc", 1), "…");
  assert.equal(truncate("abc", 0), "");
});

test("compact components clip instead of wrapping and tolerate zero width", () => {
  const component = createSubagentComponent(
    () => [{ text: "long task label", tone: "accent" }],
    plainTheme,
    layout,
  );
  assert.deepEqual(component.render(9), ["long task"]);
  assert.deepEqual(component.render(1), ["l"]);
  assert.deepEqual(component.render(0), []);
});

test("live lines and theme styles are reevaluated after updates and invalidation", () => {
  let label = "Running";
  let style = "first";
  const component = createSubagentComponent(
    () => [{ text: label, tone: "accent" }],
    { fg: (_tone, text) => `${style}:${text}` },
    layout,
  );
  assert.deepEqual(component.render(80), ["first:Running"]);
  label = "Completed";
  style = "second";
  component.invalidate();
  assert.deepEqual(component.render(80), ["second:Completed"]);
});

test("expanded hierarchy keeps hanging indents around Markdown and details", () => {
  let outputInvalidated = false;
  let detailsInvalidated = false;
  const lines: SubagentLine[] = [
    { text: "abcdef", tone: "muted", indentColumns: 2 },
  ];
  const component = createSubagentComponent(
    () => lines,
    plainTheme,
    {
      ...layout,
      wrap: (text, width) =>
        text.match(new RegExp(`.{1,${width}}`, "gu")) ?? [],
    },
    {
      render: (width) => ["Markdown".slice(0, width)],
      invalidate: () => {
        outputInvalidated = true;
      },
    },
    {
      render: (width) => ["Details".slice(0, width)],
      invalidate: () => {
        detailsInvalidated = true;
      },
    },
  );
  assert.deepEqual(component.render(5), [
    "  abc",
    "  def",
    "",
    "Markd",
    "",
    "Detai",
  ]);
  assert.deepEqual(component.render(0), []);
  component.invalidate();
  assert.equal(outputInvalidated, true);
  assert.equal(detailsInvalidated, true);
});
