// What the find hub's row actions do, kept pure so `find-test.mjs` can test
// it under Node: the `y/n` prompt `ctrl-x` shows for a row and the command it
// runs on `y` (`closePrompt`), which terminals ending a terminal also ends
// (`killSet`, `descendantCount`), and what `ctrl-i` tells the person after
// interrupting a terminal (`interruptNotice`). A terminal's prompt names the
// tabs and spaces its kill closes, since a tab closes once its last pane's
// terminal ends. This file imports only types from `herdr`.

import type { ExecResult } from "herdr";
import { finishedLabel, finishedOutcome } from "./finished.js";
import type { FindRow, FindWorld } from "./rows.js";
import { parentAddress } from "./terminals.js";
import type { TerminalEntry } from "./terminals.js";

// The command that closes a row's target, with its arguments: an app
// command the hub runs with `run()`, or `hc rm`, which the hub runs as the
// CLI. `terminal.kill` ends the terminal and every terminal it started, at
// all levels. `confirmed: true` skips the app's own confirmation, since the
// hub has already asked. `hc rm` removes a finished terminal's record, so it
// no longer lists anywhere.
export type CloseAction =
  | {
      command: "terminal.kill";
      args: { terminal: string };
    }
  | {
      command: "space.close";
      args: { id: string; confirmed: true };
    }
  | {
      command: "hc rm";
      args: { terminal: string };
    };

// The question `ctrl-x` asks before closing `row`'s target, and the action
// `y` runs. A terminal row's prompt, agent or plain, counts the live
// terminals that end with it (`killSet` over `world.terminals`) and names
// every tab and space the kill closes, wherever they are (`closedPlaces`), as
// `End <label> (+N more)? — closes tab <tab> in <space>, space <space> — y/n`;
// with nothing closing it stays `End <label>? y/n`. A space row closes its
// space. A finished row's prompt removes its finished terminal with `hc rm`,
// as `Remove <label> (<how it ended>)? y/n` ("Remove make (exit 1)? y/n").
// Machine headers, tab dividers, elsewhere labels, and the new-terminal and
// new-space rows close nothing: null.
export function closePrompt(
  row: FindRow,
  world: Pick<FindWorld, "terminals" | "panes" | "spaces">,
): { text: string; action: CloseAction } | null {
  switch (row.kind) {
    case "terminal": {
      const kill = killSet(row.address, world.terminals);
      const more = kill.size - 1;
      const places = closedPlaces(kill, world);
      const closes =
        places.length > 0 ? ` — closes ${places.join(", ")} —` : "";
      return {
        text: `End ${row.model.label}${more > 0 ? ` (+${more} more)` : ""}?${closes} y/n`,
        action: {
          command: "terminal.kill",
          args: { terminal: row.address },
        },
      };
    }
    case "space": {
      const n = row.space.tabs.length;
      return {
        text: `Close space ${row.space.name} (${n} ${n === 1 ? "tab" : "tabs"})? y/n`,
        action: {
          command: "space.close",
          args: {
            id: row.space.id,
            confirmed: true,
          },
        },
      };
    }
    case "finished":
      return {
        text: `Remove ${finishedLabel(row.finished)} (${finishedOutcome(row.finished).text})? y/n`,
        action: {
          command: "hc rm",
          args: { terminal: row.finished.address },
        },
      };
    case "machine":
    case "tab":
    case "elsewhere":
    case "new-terminal":
    case "new-space":
      return null;
  }
}

// The tabs and spaces that close when every terminal in `kill` ends, in
// `world.spaces` order, as prompt parts: `space <name>` for a space whose
// tabs all close (its tabs are not listed), else `tab <name> in <space>` per
// closing tab in tab order. A tab closes when it has panes and every one
// shows a terminal in `kill`; a mod pane, which shows no terminal, keeps its
// tab open, and a tab with no panes in `world.panes` never closes. A space
// closes when it has a tab and all of them close.
function closedPlaces(
  kill: ReadonlySet<string>,
  world: Pick<FindWorld, "panes" | "spaces">,
): string[] {
  const tabCloses = (tabId: string): boolean => {
    const panes = world.panes.filter((p) => p.tab === tabId);
    return (
      panes.length > 0 &&
      panes.every((p) => p.terminal !== null && kill.has(p.terminal))
    );
  };

  const places: string[] = [];
  for (const space of world.spaces) {
    const closing = space.tabs.filter((tab) => tabCloses(tab.id));
    if (closing.length > 0 && closing.length === space.tabs.length)
      places.push(`space ${space.name}`);
    else
      for (const tab of closing)
        places.push(`tab ${tab.name} in ${space.name}`);
  }
  return places;
}

// The addresses `terminal.kill` on `address` ends: `address` itself and every
// live terminal descending from it through `parent` links, at all levels,
// agents and plain programs alike. The walk passes only through live
// terminals, so an ended terminal's children are not included, and it visits
// each terminal once, so a parent cycle ends.
export function killSet(
  address: string,
  terminals: readonly TerminalEntry[],
): Set<string> {
  const childrenByParent = new Map<string, string[]>();
  for (const t of terminals) {
    const parent = t.state === "live" ? parentAddress(t) : null;
    if (!parent) continue;
    const children = childrenByParent.get(parent) ?? [];
    children.push(t.address);
    childrenByParent.set(parent, children);
  }

  const visited = new Set([address]);
  const queue = [address];
  for (let i = 0; i < queue.length; i++) {
    for (const child of childrenByParent.get(queue[i]) ?? []) {
      if (visited.has(child)) continue;
      visited.add(child);
      queue.push(child);
    }
  }
  return visited;
}

// How many live terminals end along with the terminal at `address`: its
// `killSet` without itself.
export function descendantCount(
  address: string,
  terminals: readonly TerminalEntry[],
): number {
  return killSet(address, terminals).size - 1;
}

// The notification `ctrl-i` shows after `hc interrupt --json` ran on the
// terminal labelled `label` and returned `r`, or null to show nothing. A
// non-zero exit is an error, worded by stderr's first line or else the exit
// code. On exit 0, `"outcome":"unknown"` (no sign the terminal stopped) is
// worth telling; `exited` or any other outcome is the interrupt working, and
// output that is not JSON says nothing either way, so both show nothing.
export function interruptNotice(
  label: string,
  r: ExecResult,
): { level: "info" | "error"; body: string } | null {
  if (r.code !== 0)
    return {
      level: "error",
      body:
        r.stderr.trim().split("\n", 1)[0] ||
        `hc interrupt exited with ${r.code}`,
    };

  let outcome: unknown;
  try {
    outcome = (JSON.parse(r.stdout) as { outcome?: unknown } | null)?.outcome;
  } catch {
    return null;
  }
  return outcome === "unknown"
    ? {
        level: "info",
        body: `${label}: no sign it stopped`,
      }
    : null;
}
