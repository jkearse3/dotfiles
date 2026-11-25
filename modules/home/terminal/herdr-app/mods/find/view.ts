// The find hub's display arithmetic, kept pure so `find-test.mjs` can test it
// under Node: where the cursor lands when the list changes (`cursorIndex`)
// and which row it can rest on (`selectableIndex`, and `wheelSelectionIndex`
// under the mouse wheel), how tall each row is and where it sits
// (`rowHeight`, `rowOffsets`), the lines of a terminal's screen
// (`screenLines`), the slice of a preview that fits (`previewWindow`), the
// tree preview of a space (`spaceTreePreview`), the line heading a
// terminal's screen (`terminalPreviewHeader`) or a finished terminal's
// (`finishedPreviewHeader`), and which terminal screen the
// preview keeps and reads as the selection moves (`followAgentPreview`,
// `isWantedAgentRead`), and the keys the footer offers for the selected row
// (`footerHints`) or while a `y/n` prompt shows (`promptHints`). This file
// imports only types from `herdr`, `rows.ts` and `actions.ts`, and pure
// helpers from `finished.ts`, `labels.ts` and `terminals.ts`.

import type { SpaceInfo } from "herdr";
import type { CloseAction } from "./actions.js";
import { finishedOutcome } from "./finished.js";
import type { FinishedTerminal } from "./finished.js";
import { homeRelative } from "./labels.js";
import type { FindRow } from "./rows.js";
import { machineOf } from "./terminals.js";

/**
 * The cursor's index in a list of row `keys` after a render. When the query
 * or needs-you filter behind the list changed (`sameFilter` false), the
 * cursor goes to the top; otherwise it stays on the row it was on
 * (`prevKey`), and when that row is gone it stays at the same position
 * (`prevIndex`), clamped to the list. An empty list puts it at 0.
 */
export function cursorIndex(
  keys: readonly string[],
  prevKey: string | null,
  prevIndex: number,
  sameFilter: boolean,
): number {
  if (keys.length === 0 || !sameFilter) return 0;

  const kept = prevKey === null ? -1 : keys.indexOf(prevKey);
  if (kept >= 0) return kept;
  return Math.max(0, Math.min(prevIndex, keys.length - 1));
}

/**
 * The lines of `hc read` output: carriage returns dropped, each line's
 * trailing whitespace trimmed, and the blank lines after the last text
 * dropped. Blank lines between text lines stay.
 */
export function screenLines(stdout: string): string[] {
  const lines = stdout
    .split("\n")
    .map((line) => line.replace(/\r/g, "").trimEnd());

  while (lines.length > 0 && lines[lines.length - 1] === "") lines.pop();
  return lines;
}

/**
 * The slice `[start, end)` of a `total`-line preview that shows in `visible`
 * lines, scrolled `offset` lines away from its `anchor` end: "bottom" shows
 * the last lines at offset 0, as a terminal does, and "top" the first.
 * `offset` comes back clamped to what the preview can scroll, so a caller can
 * store it.
 */
export function previewWindow(
  total: number,
  visible: number,
  offset: number,
  anchor: "bottom" | "top",
): { start: number; end: number; offset: number } {
  const shown = Math.max(0, Math.min(visible, total));
  const clamped = Math.max(0, Math.min(offset, total - shown));

  if (anchor === "bottom") {
    const end = total - clamped;
    return {
      start: end - shown,
      end,
      offset: clamped,
    };
  }
  return {
    start: clamped,
    end: clamped + shown,
    offset: clamped,
  };
}

/**
 * The first index from `from` on, moving by `step` and wrapping at the
 * ends, whose row the cursor can rest on (`selectable[i]`): `from` itself
 * when it can. `from` when no row can, and 0 for an empty list.
 */
export function selectableIndex(
  selectable: readonly boolean[],
  from: number,
  step: 1 | -1,
): number {
  const n = selectable.length;
  if (n === 0) return 0;

  for (let i = 0; i < n; i++) {
    const at = (((from + i * step) % n) + n) % n;
    if (selectable[at]) return at;
  }
  return from;
}

/**
 * The height of a one-line row, in logical px, fitting `terminalRow` from
 * `tree-rows.ts`: 4 px padding above and below, lines at 1.3 line height 2 px
 * apart, a 12.5 px first line (16.25 px), an 11 px folder line (14.3 px) and
 * an 11.5 px third line (14.95 px). One line takes 24.25 px, two 40.55 px and
 * three 57.5 px; this height, `TWO_LINE_ROW_H` and `THREE_LINE_ROW_H` each
 * leave a few px to spare around that, centered.
 */
export const ROW_H = 32;
/**
 * The height of a plain terminal row or a space row with a second line, in
 * logical px: two lines take 40.55 px (see `ROW_H`), and this leaves a few px
 * to spare around them, centered, while also fitting a space row's 11.5 px
 * checkout line.
 */
export const TWO_LINE_ROW_H = 46;
/**
 * The height of an agent row with its third line, in logical px: three lines
 * take 57.5 px (see `ROW_H`), and this leaves a few px to spare around them,
 * centered.
 */
export const THREE_LINE_ROW_H = 62;
/**
 * The height of a machine header or an elsewhere label, in logical px: the
 * desk-spaces sidebar's machine header height.
 */
export const HEADING_ROW_H = 26;
/**
 * The height of a tab divider, in logical px: the desk-spaces sidebar's,
 * which `tabDivider` from `tree-rows.ts` sets.
 */
export const TAB_DIVIDER_ROW_H = 18;

/**
 * `row`'s height in the list: `HEADING_ROW_H` for a machine header or an
 * elsewhere label; `TAB_DIVIDER_ROW_H` for a tab divider; for a terminal
 * row, `THREE_LINE_ROW_H` when it has a third line (its model's `detail`:
 * every agent, and a plain terminal running a command) and `TWO_LINE_ROW_H`
 * otherwise, its second line being its folder; `TWO_LINE_ROW_H` for a space
 * row with a checkout line; `ROW_H` for every other row.
 */
export function rowHeight(row: FindRow): number {
  if (row.kind === "machine" || row.kind === "elsewhere") return HEADING_ROW_H;
  if (row.kind === "tab") return TAB_DIVIDER_ROW_H;
  if (row.kind === "terminal") {
    return row.model.detail !== null ? THREE_LINE_ROW_H : TWO_LINE_ROW_H;
  }

  const hasSecondLine = row.kind === "space" && row.checkoutLine !== null;
  return hasSecondLine ? TWO_LINE_ROW_H : ROW_H;
}

/**
 * Where each of the rows with `heights` sits in the list's strip, in logical
 * px: entry `i` is row `i`'s top, the sum of the heights before it, and the
 * last entry, one past the rows, is the strip's total height.
 */
export function rowOffsets(heights: readonly number[]): number[] {
  const offsets = [0];
  for (const h of heights) offsets.push(offsets[offsets.length - 1] + h);
  return offsets;
}

/**
 * The row the cursor rests on after the list scrolls to `scroll` px under
 * the mouse wheel, so the next render need not scroll back to reach it. The
 * list shows rows with `heights` px, stacked from the strip's top, in a view
 * `viewHeight` px tall; `selectable[i]` says whether the cursor can rest on
 * row `i`, and both arrays list the same rows. A cursor at `from` that has
 * left the fully visible rows moves to the nearest edge of them, then to the
 * nearest row inside them the cursor can rest on, preferring the side further
 * inward; one still inside keeps its place when selectable. When no visible
 * row is selectable, the cursor goes to the first selectable row from that
 * edge on, moving inward and wrapping as `selectableIndex` does. An empty
 * list gives 0.
 */
export function wheelSelectionIndex(
  selectable: readonly boolean[],
  heights: readonly number[],
  scroll: number,
  viewHeight: number,
  from: number,
): number {
  const n = selectable.length;
  if (n === 0) return 0;

  const offsets = rowOffsets(heights);
  const firstStarting = offsets.findIndex((top, i) => i < n && top >= scroll);
  const first = firstStarting === -1 ? n - 1 : firstStarting;
  let lastEnding = -1;
  for (let i = 0; i < n; i++) {
    if (offsets[i + 1] <= scroll + viewHeight) lastEnding = i;
  }
  const last = Math.max(first, lastEnding);
  const at = Math.max(first, Math.min(from, last));
  const inward: 1 | -1 = from > last ? -1 : 1;

  for (let d = 0; d <= last - first; d++) {
    for (const i of [at + d * inward, at - d * inward]) {
      if (i >= first && i <= last && selectable[i]) return i;
    }
  }
  return selectableIndex(selectable, at, inward);
}

/**
 * One line of a space's tree preview, and the status word it shows; null
 * for a plain terminal.
 */
export interface PreviewLine {
  text: string;
  status: string | null;
}

/**
 * The tree preview of `space`: one line per terminal row in `rows` listed
 * under it, in `rows` order. Each line indents two spaces per depth before
 * the row's label, then shows its status word in a column aligned across
 * the lines; a plain terminal's line has no status. Pass the unfiltered
 * `findRows` result, so sub-agents follow their parents.
 */
export function spaceTreePreview(
  space: SpaceInfo,
  rows: readonly FindRow[],
): PreviewLine[] {
  const members = rows.flatMap((r) =>
    r.kind === "terminal" && r.space?.id === space.id
      ? [
          {
            column: "  ".repeat(r.depth) + r.model.label,
            status: r.model.status,
          },
        ]
      : [],
  );
  const width = Math.max(0, ...members.map((m) => m.column.length));

  return members.map((m) => ({
    text: `${m.column.padEnd(width)}  ${m.status ?? ""}`.trimEnd(),
    status: m.status,
  }));
}

/**
 * The line heading terminal `row`'s screen in the preview, saying where the
 * terminal is: "tab 2 · pane 1 · ~/src/app", leaving out a part that is
 * null, and "no pane · ~/src/app" for a terminal without a pane. The folder
 * is the row's `folder`, for agents and plain terminals alike.
 */
export function terminalPreviewHeader(
  row: Pick<
    Extract<FindRow, { kind: "terminal" }>,
    "tab" | "tabIndex" | "paneIndex" | "folder"
  >,
): string {
  const place =
    row.tab === null
      ? ["no pane"]
      : [
          row.tabIndex === null ? null : `tab ${row.tabIndex}`,
          row.paneIndex === null ? null : `pane ${row.paneIndex}`,
        ];
  return [...place, row.folder].filter((part) => part !== null).join(" · ");
}

/**
 * The line heading finished terminal `f`'s screen in the preview, saying
 * how and when it ended and where it ran: "✗ exit 1 · 3m ago · ~/src/app",
 * a "✓" in place of the "✗" when it did not fail (`finishedOutcome`). `ago`
 * is how long ago it finished as the rows write it ("3m"); null leaves that
 * part out, as does an empty `cwd`. A folder on this computer writes `home`
 * as `~`.
 */
export function finishedPreviewHeader(
  f: FinishedTerminal,
  ago: string | null,
  home: string,
): string {
  const outcome = finishedOutcome(f);
  const folder =
    f.cwd === ""
      ? null
      : machineOf(f.address)
        ? f.cwd
        : homeRelative(f.cwd, home);
  return [
    `${outcome.failed ? "✗" : "✓"} ${outcome.text}`,
    ago === null ? null : `${ago} ago`,
    folder,
  ]
    .filter((part) => part !== null)
    .join(" · ");
}

/**
 * The terminal preview bookkeeping as the selection moves: the screen it
 * keeps, the read it waits for, and the read to schedule.
 *
 * `selected` is the selected terminal row's `address` and `status` (null for
 * a plain terminal), or null when the selection is no terminal row.
 * `state.preview` is the terminal screen read last, identified by its `key`
 * (`agentPreviewKey`) and `address`; `state.previewWanted` is the key of the
 * read scheduled last, null when none is wanted. The result is the next
 * `preview` and `previewWanted` and, in `readKey`, the key of a read to
 * schedule now, or null.
 *
 * Leaving a terminal forgets its screen and any wanted read, so returning to
 * it reads the screen afresh. While the same terminal's status changes, its
 * old screen stays shown until the new read lands. A screen already read for the
 * selected key cancels a read still waiting for another key, and a read
 * already wanted for it is not scheduled again.
 */
export function followAgentPreview<P extends AgentPreviewRef>(
  selected: { address: string; status: string | null } | null,
  state: AgentPreviewState<P>,
): AgentPreviewState<P> & { readKey: string | null } {
  const preview =
    state.preview && selected?.address === state.preview.address
      ? state.preview
      : null;
  if (!selected) {
    return {
      preview,
      previewWanted: null,
      readKey: null,
    };
  }

  const key = agentPreviewKey(selected.address, selected.status);
  if (preview?.key === key) {
    return {
      preview,
      previewWanted: null,
      readKey: null,
    };
  }
  return {
    preview,
    previewWanted: key,
    readKey: state.previewWanted === key ? null : key,
  };
}

/**
 * The agent screen the preview holds and the read it waits for, as
 * `followAgentPreview` reads and returns them.
 */
export interface AgentPreviewState<P extends AgentPreviewRef> {
  preview: P | null;
  previewWanted: string | null;
}

/**
 * What `followAgentPreview` needs of a read agent screen: the key it was read
 * for and the agent's address.
 */
export interface AgentPreviewRef {
  key: string;
  address: string;
}

/**
 * The preview key of the terminal at `address` while it has `status`, null
 * for a plain terminal written as empty: a new status makes a new key, so
 * the screen is read again.
 */
export function agentPreviewKey(
  address: string,
  status: string | null,
): string {
  return `a:${address}|${status ?? ""}`;
}

/**
 * Whether a scheduled agent screen read for `key` should go ahead, or its
 * result be kept: only while it is still the wanted read (`previewWanted`),
 * so a read the selection has since left is dropped.
 */
export function isWantedAgentRead(
  previewWanted: string | null,
  key: string,
): boolean {
  return previewWanted === key;
}

/**
 * One key the hub's footer offers: the `keys` to press and the `label` saying
 * what they do. A key that toggles a filter carries `isOn`, whether the
 * filter is on, which the footer marks; other keys leave it out.
 */
export interface FooterHint {
  keys: string;
  label: string;
  isOn?: boolean;
}

/**
 * The keys the footer offers while `row` is selected, in footer order:
 * `enter`, `ctrl-x` and `ctrl-i` where they act on `row`, labelled for it
 * (a finished row's `enter` goes to the terminal that started it, and its
 * `ctrl-x` removes it);
 * `ctrl-u/d` when the preview can scroll (`hasPreview`); then, always,
 * `ctrl-n` toggling the needs-you filter, marked on while `isNeedsYouOn`,
 * moving and `esc`. A machine header, a tab divider, an elsewhere label and
 * no selection (`undefined`) offer nothing beyond the preview, the filter,
 * moving and `esc`.
 */
export function footerHints(
  row: FindRow | undefined,
  hasPreview: boolean,
  isNeedsYouOn: boolean,
): FooterHint[] {
  const rowHints: FooterHint[] = [];
  switch (row?.kind) {
    case "terminal":
      rowHints.push(
        {
          keys: "enter",
          label: "go",
        },
        {
          keys: "ctrl-x",
          label: "end",
        },
        {
          keys: "ctrl-i",
          label: "interrupt",
        },
      );
      break;
    case "space":
      rowHints.push(
        {
          keys: "enter",
          label: "switch",
        },
        {
          keys: "ctrl-x",
          label: "close",
        },
      );
      break;
    case "finished":
      rowHints.push(
        {
          keys: "enter",
          label: "go to parent",
        },
        {
          keys: "ctrl-x",
          label: "remove",
        },
      );
      break;
    case "new-terminal":
    case "new-space":
      rowHints.push({
        keys: "enter",
        label: "create",
      });
      break;
    case "machine":
    case "tab":
    case "elsewhere":
    case undefined:
      break;
  }

  return [
    ...rowHints,
    ...(hasPreview
      ? [
          {
            keys: "ctrl-u/d",
            label: "scroll",
          },
        ]
      : []),
    {
      keys: "ctrl-n",
      label: "needs you",
      isOn: isNeedsYouOn,
    },
    {
      keys: "↑↓ ctrl-j/k",
      label: "move",
    },
    {
      keys: "esc",
      label: "leave",
    },
  ];
}

/**
 * The keys the footer offers while the `y/n` prompt for `action` shows: `y`
 * runs it, labelled with its verb, and any other key, `esc` included, only
 * dismisses the prompt, so the selected row's keys do not act until it is
 * gone.
 */
export function promptHints(action: CloseAction): FooterHint[] {
  return [
    {
      keys: "y",
      label: PROMPT_VERBS[action.command],
    },
    {
      keys: "any other key",
      label: "cancel",
    },
  ];
}

/** The verb `promptHints` gives `y` for each kind of `CloseAction`. */
const PROMPT_VERBS: Record<CloseAction["command"], string> = {
  "terminal.kill": "end",
  "space.close": "close",
  "hc rm": "remove",
};
