import type { Theme } from "@earendil-works/pi-coding-agent";
import type { Component } from "@earendil-works/pi-tui";
import type { SubagentField, SubagentLine } from "./presentation.ts";

export interface SubagentTextColumns {
  slice(text: string, startColumn: number, length: number): string;
  measure(text: string): number;
}

/** Builds panel-safe truncation without an ANSI reset before the ellipsis. */
export function createSubagentTruncator(
  columns: SubagentTextColumns,
): (text: string, maxWidth: number) => string {
  return (text, maxWidth) => {
    if (maxWidth <= 0) return "";
    if (columns.measure(text) <= maxWidth) return text;
    if (maxWidth === 1) return "…";
    return `${columns.slice(text, 0, maxWidth - 1)}…`;
  };
}

/** Terminal-column operations; wrapping, when enabled, applies to plain-text lines. */
export interface SubagentTextLayout {
  measure(text: string): number;
  truncate(text: string, width: number): string;
  wrap?(text: string, width: number): string[];
}

/** Renders field continuations and text rows, then optional Markdown output and details. */
export function createSubagentComponent(
  lines: () => SubagentLine[],
  theme: Pick<Theme, "fg">,
  layout: SubagentTextLayout,
  output?: Component,
  details?: Component,
): Component {
  return {
    render(width) {
      if (width < 1) return [];
      const rendered = lines().flatMap((line) => {
        const indent = Math.min(
          line.indentColumns ?? 0,
          Math.max(0, width - 1),
        );
        const contentWidth = width - indent;
        const prefix = " ".repeat(indent);
        return styledRows(line, contentWidth).map(
          (part) => `${prefix}${layout.truncate(part, contentWidth)}`,
        );
      });
      if (output)
        rendered.push(
          "",
          ...output.render(width).map((line) => layout.truncate(line, width)),
        );
      if (details) rendered.push("", ...details.render(width));
      return rendered;
    },
    invalidate() {
      output?.invalidate();
      details?.invalidate();
    },
  };

  function styledRows(line: SubagentLine, width: number): string[] {
    if ("fields" in line)
      return fitFields(line.fields, width, layout.measure).map((row) =>
        theme.fg(line.tone, row),
      );

    const styled = theme.fg(line.tone, line.text);
    return layout.wrap ? layout.wrap(styled, width) : [styled];
  }
}

function fitFields(
  [first, ...rest]: readonly [SubagentField, ...SubagentField[]],
  width: number,
  measure: SubagentTextLayout["measure"],
): string[] {
  const rows: string[] = [];
  let row = fitField(first);
  for (const field of rest) {
    const text = fitField(field);
    const joined = `${row} · ${text}`;
    if (measure(joined) <= width) row = joined;
    else {
      rows.push(row);
      row = text;
    }
  }
  rows.push(row);
  return rows;

  function fitField(field: SubagentField): string {
    if (typeof field === "string") return field;
    return field.find((text) => measure(text) <= width) ?? field.at(-1)!;
  }
}
