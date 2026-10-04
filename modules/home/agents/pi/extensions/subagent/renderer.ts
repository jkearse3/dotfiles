import type { Theme } from "@earendil-works/pi-coding-agent";
import type { Component } from "@earendil-works/pi-tui";
import type { SubagentLine } from "./presentation.ts";

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

export interface SubagentTextLayout {
  truncate(text: string, width: number): string;
  wrap?(text: string, width: number): string[];
}

/** Renders terminal-column-aware lines, optional Markdown output, then details. */
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
        const text = theme.fg(line.tone, line.text);
        const content = layout.wrap ? layout.wrap(text, contentWidth) : [text];
        return content.map(
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
}
