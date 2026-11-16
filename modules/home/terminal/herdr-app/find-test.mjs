// Tests the find mod's own pure files: `findRows`, the selectable and
// filterable rows from `rows.ts` against the terminals(), agents(), panes()
// and spaces() entry shapes the Herdr app hands mods, the query matching, list
// planning and stale-result guard in `match.ts`, with a fake `exec` and with
// the real fzf named by `FZF`, the cursor, row height and preview arithmetic
// (preview headers included) and agent preview bookkeeping in `view.ts`, and
// the `ctrl-x` prompts and `ctrl-i` notices in `actions.ts`. The shared
// `mod-lib` files the mod links in are tested by mod-lib-test.mjs. It
// imports the built, type-stripped `find/*.js` from the herdr-app-mods output
// named by `HERDR_APP_MODS`, where the mod's links to `mod-lib` have been
// copied in. Run with
// `HERDR_APP_MODS=$(nix build --no-link --print-out-paths .#herdr-app-mods) FZF=$(command -v fzf) node --test`;
// without `FZF` the real-fzf test is skipped. flake/checks.nix registers it as
// the `herdr-app-find` check through find-check.nix, which sets both.
import assert from "node:assert/strict";
import { execFile } from "node:child_process";
import { test } from "node:test";

const mods = process.env.HERDR_APP_MODS;
if (!mods) {
  throw new Error(
    "HERDR_APP_MODS is unset: set it to the herdr-app-mods build output",
  );
}
const { filterableRows, findRows, isSelectable, needsYouRows, unfoldedRows } =
  await import(`${mods}/find/rows.js`);
const {
  FZF_SCRIPT,
  LatestRequest,
  match,
  matchArgs,
  matchOrAll,
  parseMatch,
  planShownList,
  sameMatchInput,
  sanitize,
} = await import(`${mods}/find/match.js`);
const {
  agentPreviewKey,
  cursorIndex,
  finishedPreviewHeader,
  followAgentPreview,
  footerHints,
  HEADING_ROW_H,
  isWantedAgentRead,
  previewWindow,
  promptHints,
  ROW_H,
  rowHeight,
  rowOffsets,
  screenLines,
  selectableIndex,
  spaceTreePreview,
  TAB_DIVIDER_ROW_H,
  terminalPreviewHeader,
  THREE_LINE_ROW_H,
  TWO_LINE_ROW_H,
  wheelSelectionIndex,
} = await import(`${mods}/find/view.js`);
const { closePrompt, descendantCount, interruptNotice } = await import(
  `${mods}/find/actions.js`
);

// A terminals() entry: a live terminal at `address` reporting `status`, with
// `fields` overriding the defaults.
function terminal(address, status, fields = {}) {
  return {
    address,
    status,
    state: "live",
    parent: null,
    name: null,
    ...fields,
  };
}

// An agents() entry for the agent at `address` with a pane, reporting
// `status`, with `fields` overriding the defaults.
function agent(address, status, fields = {}) {
  return {
    address,
    pane: `p-${address}`,
    space: "s1",
    space_name: "one",
    tab: "t1",
    tab_index: 1,
    tab_name: "1",
    status,
    app: "claude-code",
    program: {
      name: "Claude Code",
      key: "claude",
    },
    title: "",
    seq: 0,
    pinned: false,
    focused: false,
    ...fields,
  };
}

// A panes() entry showing terminal `address` in tab `tab`; a null `address`
// gives a pane without a terminal, as a mod pane has.
function pane(address, tab) {
  return {
    pane: `p-${address}`,
    terminal: address,
    tab,
    title: "",
    cwd: null,
    branch: null,
    status: null,
    app: null,
    focused: false,
    zoomed: false,
    movable: false,
  };
}

// A spaces() entry `id` named `name` holding tabs with ids `tabIds`.
function space(id, name, tabIds, machine = null) {
  return {
    id,
    index: 1,
    name,
    named: true,
    folder: "",
    machine,
    branch: null,
    active: false,
    status: null,
    tabs: tabIds.map((tabId, i) => ({
      id: tabId,
      index: i + 1,
      name: `tab ${tabId}`,
      named: true,
      active: i === 0,
      status: null,
      panes: 1,
      zoomed: false,
      settled: false,
      settled_at: null,
      changed_at: null,
      working_since: null,
    })),
  };
}

// A FindWorld with `fields` overriding the empty defaults.
function world(fields) {
  return {
    terminals: [],
    agents: [],
    panes: [],
    spaces: [],
    machines: [],
    finished: [],
    checkouts: null,
    home: "/home/me",
    ...fields,
  };
}

// Whether `r` is an agent's terminal row.
const isAgentRow = (r) => r.kind === "terminal" && r.model.status !== null;

// `rows`' agent rows as [address, depth] pairs, in order.
const agentTree = (rows) =>
  rows.filter(isAgentRow).map((r) => [r.address, r.depth]);

// `rows`' agent addresses, in order.
const agentOrder = (rows) => rows.filter(isAgentRow).map((r) => r.address);

// The agent row for `address` in `rows`.
const agentRow = (rows, address) =>
  rows.find((r) => isAgentRow(r) && r.address === address);

// The plain terminal row for `address` in `rows`.
const plainRow = (rows, address) =>
  rows.find(
    (r) =>
      r.kind === "terminal" && r.model.status === null && r.address === address,
  );

// `rows`' space headers' keys, in order.
const spaceRowKeys = (rows) =>
  rows.filter((r) => r.kind === "space").map((r) => r.key);

// `rows`' machine header, space header and elsewhere label keys, in order.
const headerKeys = (rows) =>
  rows
    .filter((r) => ["machine", "space", "elsewhere"].includes(r.kind))
    .map((r) => r.key);

test("a tab's terminals list in panes() order, whatever their status", () => {
  const rows = findRows(
    world({
      terminals: [
        terminal("1", "idle"),
        terminal("2", "working"),
        terminal("3", "blocked"),
        terminal("4", "starting"),
        terminal("5", "done"),
      ],
      agents: [
        agent("1", "idle"),
        agent("2", "working"),
        agent("3", "blocked"),
        agent("5", "done"),
      ],
      panes: [
        pane("2", "t1"),
        pane("5", "t1"),
        pane("1", "t1"),
        pane("4", "t1"),
        pane("3", "t1"),
      ],
      spaces: [space("s1", "one", ["t1"])],
    }),
  );
  assert.deepEqual(agentOrder(rows), ["2", "5", "1", "4", "3"]);
});

test("a blocked paneless sub-agent nests under its working parent", () => {
  const rows = findRows(
    world({
      terminals: [
        terminal("p", "working"),
        terminal("k", "blocked", { parent: "p" }),
        terminal("q", "done"),
      ],
      agents: [agent("p", "working"), agent("q", "done")],
    }),
  );
  assert.deepEqual(agentTree(rows), [
    ["p", 0],
    ["k", 1],
    ["q", 0],
  ]);
});

test("a paneless error shows as blocked and a paneless done as idle", () => {
  const rows = findRows(
    world({
      terminals: [terminal("e", "error"), terminal("d", "done")],
    }),
  );
  assert.equal(agentRow(rows, "e").model.status, "blocked");
  assert.equal(agentRow(rows, "d").model.status, "idle");
  assert.deepEqual(agentOrder(rows), ["e", "d"]);
});

test("a done agent nested under an agent shows idle, its parent's done being the news", () => {
  const rows = findRows(
    world({
      terminals: [
        terminal("p", "idle"),
        terminal("k", "done", { parent: "p" }),
        terminal("q", "done"),
      ],
      agents: [agent("p", "idle"), agent("k", "done"), agent("q", "done")],
    }),
  );
  assert.deepEqual(agentTree(rows), [
    ["p", 0],
    ["k", 1],
    ["q", 0],
  ]);
  assert.equal(agentRow(rows, "k").model.status, "idle");
  assert.equal(agentRow(rows, "q").model.status, "done");
});

test("a terminal nests under its live parent, plain or agent; with an ended or missing parent it is top-level", () => {
  const rows = findRows(
    world({
      terminals: [
        terminal("shell", null),
        terminal("ended", "idle", { state: "exited" }),
        terminal("a", "idle", { parent: "shell" }),
        terminal("b", "idle", { parent: "missing" }),
        terminal("c", "idle", { parent: "ended" }),
      ],
    }),
  );
  assert.deepEqual(
    rows.filter((r) => r.kind === "terminal").map((r) => [r.address, r.depth]),
    [
      ["shell", 0],
      ["a", 1],
      ["b", 0],
      ["c", 0],
    ],
  );
  assert.equal(agentRow(rows, "a").parentLabel, "shell");
  assert.equal(agentRow(rows, "b").parentLabel, null);
  // An ended parent agent has no row, so its label names it.
  assert.equal(agentRow(rows, "c").parentLabel, "ended");
});

test("agents whose parents form a cycle still show, under the first", () => {
  const rows = findRows(
    world({
      terminals: [
        terminal("a", "idle", { parent: "b" }),
        terminal("b", "idle", { parent: "a" }),
      ],
    }),
  );
  assert.deepEqual(agentTree(rows), [
    ["a", 0],
    ["b", 1],
  ]);
});

test("elsewhere lists its terminals in terminals() order, whatever their status_ms", () => {
  const rows = findRows(
    world({
      terminals: [
        terminal("a", "idle", { status_ms: 300 }),
        terminal("b", "blocked"),
        terminal("c", "idle", { status_ms: 100 }),
      ],
    }),
  );
  assert.deepEqual(agentOrder(rows), ["a", "b", "c"]);
});

test("sub-terminals follow their parent in terminals() order, whatever their status", () => {
  const rows = findRows(
    world({
      terminals: [
        terminal("p", "idle", { status_ms: 900 }),
        terminal("k", "idle", {
          parent: "p",
          status_ms: 100,
        }),
        terminal("j", "blocked", {
          parent: "p",
          status_ms: 500,
        }),
        terminal("q", "blocked", { status_ms: 50 }),
      ],
    }),
  );
  assert.deepEqual(agentTree(rows), [
    ["p", 0],
    ["k", 1],
    ["j", 1],
    ["q", 0],
  ]);
});

test("nested terminals list depth-first, each under its parent", () => {
  const rows = findRows(
    world({
      terminals: [
        terminal("r", "idle", { name: "root" }),
        terminal("s1", "idle", {
          parent: "r",
          name: "one",
        }),
        terminal("s2", "working", { parent: "r" }),
        terminal("s3", "idle", { parent: "r" }),
        terminal("s11", "idle", { parent: "s1" }),
      ],
    }),
  );
  assert.deepEqual(agentTree(rows), [
    ["r", 0],
    ["s1", 1],
    ["s11", 2],
    ["s2", 1],
    ["s3", 1],
  ]);
  assert.deepEqual(
    rows.filter(isAgentRow).map((r) => r.parentLabel),
    [null, "root", "one", "root", "root"],
  );
});

test("ended and statusless terminals are no agent rows", () => {
  const rows = findRows(
    world({
      terminals: [
        terminal("ended", "working", { state: "exited" }),
        terminal("empty", ""),
        terminal("none", null),
        terminal("missing", undefined),
        terminal("live", "idle"),
      ],
    }),
  );
  assert.deepEqual(agentOrder(rows), ["live"]);
});

test("agent labels: the program's short name, then the terminal's name, agentName, the program, the address", () => {
  const rows = findRows(
    world({
      terminals: [
        terminal("named", "idle", { name: "  reviewer  " }),
        terminal("titled", "idle"),
        terminal("renamed", "idle", { name: "lead" }),
        terminal("program", "idle", {
          program: {
            name: "pi",
            key: "pi",
          },
        }),
        terminal("bare", "idle"),
      ],
      agents: [
        agent("titled", "idle", { title: "✳ Fix the sidebar" }),
        agent("renamed", "idle", { title: "✳ Fix the sidebar" }),
      ],
    }),
  );
  assert.equal(agentRow(rows, "named").model.label, "reviewer");
  assert.equal(agentRow(rows, "titled").model.label, "claude  Fix the sidebar");
  assert.equal(agentRow(rows, "renamed").model.label, "claude  lead");
  assert.equal(agentRow(rows, "program").model.label, "pi");
  assert.equal(agentRow(rows, "bare").model.label, "bare");
});

test("a terminal row's label starts with its program's short name, and its text ends with its space", () => {
  const rows = findRows(
    world({
      terminals: [
        terminal("a1", "working"),
        terminal("box/2", "idle", {
          name: "helper",
          program: {
            name: "Pi",
            key: "pi",
          },
        }),
        fish("t1", "/home/me/x"),
        fish("t2", "/home/me/y", { name: "server" }),
        terminal("t3", null, {
          name: "build",
          program: {
            name: "make",
            key: "program",
          },
        }),
      ],
      agents: [agent("a1", "working", { title: "✳ Fix the sidebar" })],
      panes: [
        pane("a1", "t1"),
        pane("t1", "t1"),
        pane("t2", "t1"),
        pane("t3", "t1"),
      ],
      spaces: [space("s1", "dots", ["t1"])],
    }),
  );

  // A listed program goes by its table key, not its display name.
  const claude = agentRow(rows, "a1");
  assert.equal(claude.model.program.name, "Claude Code");
  assert.equal(claude.model.label, "claude  Fix the sidebar");
  assert.equal(claude.text, "claude  Fix the sidebar  working  dots");

  const pi = agentRow(rows, "box/2");
  assert.equal(pi.model.label, "pi  helper");
  assert.equal(pi.text, "pi  helper  idle  elsewhere  box");

  // A shell or an unlisted program goes by its process name.
  const shell = plainRow(rows, "t1");
  assert.equal(shell.model.program.name, "fish");
  assert.equal(shell.model.label, "fish  ~/x");
  assert.equal(shell.text, "fish  ~/x  dots");

  // A named one's text holds the folder its row shows after the label.
  const server = plainRow(rows, "t2");
  assert.equal(server.model.label, "fish  server");
  assert.equal(server.text, "fish  server  ~/y  dots");

  assert.equal(plainRow(rows, "t3").model.label, "make  build");
});

test("a terminal row's folder is its cwd, home-relative on this computer, and its text holds it before the space", () => {
  const rows = findRows(
    world({
      terminals: [
        terminal("a1", "working", {
          name: "lead",
          cwd: "/home/me/worktrees/neom8/neom8-jjws-1",
        }),
        terminal("home", "idle", {
          name: "at home",
          cwd: "/home/me",
        }),
        terminal("box/2", "idle", {
          name: "helper",
          cwd: "/home/me/herdr-app",
        }),
        terminal("bare", "idle", { name: "bare" }),
        fish("sh", "/home/me/x"),
      ],
      panes: [pane("a1", "t1"), pane("sh", "t1")],
      spaces: [space("s1", "dots", ["t1"])],
    }),
  );

  const lead = agentRow(rows, "a1");
  assert.equal(lead.model.folder, "~/worktrees/neom8/neom8-jjws-1");
  assert.equal(
    lead.text,
    "lead  working  ~/worktrees/neom8/neom8-jjws-1  dots",
  );
  assert.equal(agentRow(rows, "home").model.folder, "~");

  // Another machine's home folder is unknown, so its path stays whole.
  const helper = agentRow(rows, "box/2");
  assert.equal(helper.model.folder, "/home/me/herdr-app");
  assert.equal(helper.text, "helper  idle  /home/me/herdr-app  elsewhere  box");

  const bare = agentRow(rows, "bare");
  assert.equal(bare.model.folder, null);
  assert.equal(bare.text, "bare  idle  elsewhere");

  // An unnamed plain terminal's text holds its folder once, as its row's
  // second line, though its label shows the folder too.
  const shell = plainRow(rows, "sh");
  assert.equal(shell.model.folder, "~/x");
  assert.equal(shell.text, "fish  ~/x  dots");
});

test("a terminal row's since is an agent's status_ms, except while it works; a plain terminal none", () => {
  const rows = findRows(
    world({
      terminals: [
        terminal("lead", "idle", { status_ms: 1000 }),
        terminal("busy", "working", { status_ms: 1500 }),
        terminal("kid", "idle"),
        fish("sh", "/home/me/x", {
          turn: 4,
          status_ms: 2000,
        }),
      ],
      agents: [agent("lead", "idle")],
      panes: [pane("lead", "t1"), pane("sh", "t1")],
      spaces: [space("s1", "dots", ["t1"])],
    }),
  );

  assert.equal(agentRow(rows, "lead").since, 1000);
  assert.equal(agentRow(rows, "busy").since, null);
  assert.equal(agentRow(rows, "kid").since, null);
  assert.equal(plainRow(rows, "sh").since, null);
});

test("a name that only names the program, ignoring case, is not repeated", () => {
  const rows = findRows(
    world({
      terminals: [
        terminal("pi", "idle", {
          program: {
            name: "pi",
            key: "pi",
          },
        }),
        terminal("claude", "idle", { name: "claude code" }),
        fish("sh", "/x", { name: "Fish" }),
      ],
      agents: [agent("claude", "idle")],
      panes: [pane("sh", "t1")],
    }),
  );
  assert.equal(agentRow(rows, "pi").model.label, "pi");
  assert.equal(agentRow(rows, "pi").text, "pi  idle  elsewhere");
  assert.equal(agentRow(rows, "claude").model.label, "claude");
  assert.equal(agentRow(rows, "claude").text, "claude  idle  elsewhere");
  assert.equal(plainRow(rows, "sh").model.label, "fish");
});

test("an agent's space is its own pane's, else its nearest ancestor's with a pane", () => {
  const rows = findRows(
    world({
      terminals: [
        terminal("shell", null),
        terminal("own", "idle", { name: "own" }),
        terminal("kid", "idle", {
          parent: "shell",
          name: "kid",
        }),
        terminal("lost", "idle", { name: "lost" }),
      ],
      agents: [agent("own", "idle", { tab: "t1" })],
      panes: [pane("own", "t1"), pane("shell", "t2")],
      spaces: [space("s1", "one", ["t1"]), space("s2", "two", ["t2"])],
    }),
  );
  assert.equal(agentRow(rows, "own").space.id, "s1");
  assert.equal(agentRow(rows, "own").text, "claude  own  idle  one");
  assert.equal(agentRow(rows, "kid").space.id, "s2");
  assert.equal(agentRow(rows, "kid").text, "kid  idle  two");
  assert.equal(agentRow(rows, "lost").space, null);
  assert.equal(agentRow(rows, "lost").text, "lost  idle  elsewhere");
});

test("a remote sub-agent's bare parent names a terminal on its machine", () => {
  const rows = findRows(
    world({
      terminals: [
        terminal("3", "idle", { name: "local three" }),
        terminal("box/3", "idle", { name: "remote three" }),
        terminal("box/7", "idle", {
          parent: "3",
          name: "seven",
        }),
      ],
    }),
  );
  // Elsewhere lists this computer's terminals before another machine's.
  assert.deepEqual(agentTree(rows), [
    ["3", 0],
    ["box/3", 0],
    ["box/7", 1],
  ]);
  const seven = agentRow(rows, "box/7");
  assert.equal(seven.machine, "box");
  assert.equal(seven.parentLabel, "remote three");
  assert.equal(seven.text, "seven  idle  elsewhere  box");
  assert.equal(agentRow(rows, "3").machine, null);
});

// A plain fish shell's terminals() entry at `address` in folder `cwd`.
const fish = (address, cwd, fields = {}) =>
  terminal(address, null, {
    program: {
      name: "fish",
      key: "shell",
      shell: true,
    },
    cwd,
    ...fields,
  });

// A world with three spaces: neom8 (active) holds agent A, with a paneless
// sub-agent k and a paneless plain `sleep` nested under it, and two fish
// shells in the same folder; scratch holds agent B and A's paneless
// sub-agent m, labelled into it; quiet holds no terminals. A paneless
// unlabelled parentless worker is elsewhere.
function treeWorld(fields = {}) {
  return world({
    terminals: [
      terminal("A", "working", {
        name: "lead",
        labels: {
          "herdr.space": "s1",
          "herdr.tab": "t1",
        },
      }),
      fish("t22", "/home/me/projects/neom8"),
      fish("t26", "/home/me/projects/neom8"),
      terminal("B", "idle", { name: "bee" }),
      terminal("k", "idle", {
        parent: "A",
        name: "kid",
      }),
      terminal("m", "idle", {
        parent: "A",
        name: "mover",
        labels: { "herdr.space": "s2" },
      }),
      terminal("sleep", null, {
        parent: "A",
        program: { name: "sleep" },
      }),
      terminal("worker", null),
    ],
    agents: [
      agent("A", "working", { tab: "t1" }),
      agent("B", "idle", { tab: "t3" }),
    ],
    panes: [
      pane("A", "t1"),
      pane("t22", "t1"),
      pane("t26", "t1"),
      pane("B", "t3"),
    ],
    spaces: [
      {
        ...space("s1", "neom8", ["t1", "t2"]),
        active: true,
      },
      space("s2", "scratch", ["t3"]),
      space("s3", "quiet", ["t4"]),
    ],
    ...fields,
  });
}

test("findRows lists this computer's header, each space's tabs as a divider and its terminals in pane order with their sub-terminals, then its paneless ones, then its elsewhere and the new rows", () => {
  const rows = findRows(treeWorld());
  assert.deepEqual(
    rows.map((r) => [r.kind, r.key, r.depth ?? null]),
    [
      ["machine", "m:", null],
      ["space", "s:s1", null],
      ["tab", "t:t1", null],
      ["terminal", "a:A", 0],
      ["terminal", "a:k", 1],
      ["terminal", "a:sleep", 1],
      ["terminal", "a:t22", 0],
      ["terminal", "a:t26", 0],
      ["tab", "t:t2", null],
      ["space", "s:s2", null],
      ["tab", "t:t3", null],
      ["terminal", "a:B", 0],
      ["terminal", "a:m", 0],
      ["space", "s:s3", null],
      ["tab", "t:t4", null],
      ["elsewhere", "elsewhere:", null],
      ["terminal", "a:worker", 0],
      ["new-terminal", "new:terminal", null],
      ["new-space", "new:space:", null],
    ],
  );
  assert.equal(new Set(rows.map((r) => r.key)).size, rows.length);

  assert.equal(agentRow(rows, "k").parentLabel, "claude  lead");
  assert.equal(agentRow(rows, "m").space.id, "s2");
  assert.equal(agentRow(rows, "m").parentLabel, "claude  lead");
  assert.equal(agentRow(rows, "A").tab, "t1");
  assert.equal(agentRow(rows, "k").tab, null);

  // Only a paneless terminal listed after its space's tabs, or elsewhere,
  // says so.
  assert.equal(agentRow(rows, "m").note, "no pane");
  assert.equal(plainRow(rows, "worker").note, "no pane");
  assert.equal(agentRow(rows, "k").note, null);
  assert.equal(plainRow(rows, "sleep").note, null);
  assert.equal(agentRow(rows, "A").note, null);

  const t22 = plainRow(rows, "t22");
  assert.equal(t22.model.label, "fish  ~/projects/neom8  #1");
  assert.equal(t22.text, "fish  #1  ~/projects/neom8  neom8");
  assert.equal(t22.tab, "t1");
  assert.equal(t22.parentLabel, null);
  assert.equal(plainRow(rows, "t26").model.label, "fish  ~/projects/neom8  #2");
  assert.equal(rows.at(-2).text, "new terminal in neom8");
});

test("plain labels: the program's short name, then the name, else the home-relative folder; ordinals only on repeats", () => {
  const rows = findRows(
    world({
      terminals: [
        fish("a", "/home/me/x", { name: "  server  " }),
        fish("b", "/home/me"),
        fish("c", "/srv/y"),
        terminal("d", null),
        fish("box/e", "/home/me/z"),
      ],
      panes: [
        pane("a", "t1"),
        pane("b", "t1"),
        pane("c", "t1"),
        {
          ...pane("d", "t1"),
          program: {
            name: "zsh",
            key: "shell",
          },
        },
        pane("box/e", "t1"),
      ],
      spaces: [space("s1", "one", ["t1"])],
    }),
  );
  assert.equal(plainRow(rows, "a").model.label, "fish  server");
  assert.equal(plainRow(rows, "b").model.label, "fish  ~");
  assert.equal(plainRow(rows, "c").model.label, "fish  /srv/y");
  assert.equal(plainRow(rows, "d").model.label, "zsh");
  assert.equal(plainRow(rows, "box/e").model.label, "fish  /home/me/z");
  assert.equal(plainRow(rows, "box/e").text, "fish  /home/me/z  one  box");
  assert.equal(rows.at(-2).text, "new terminal");
});

test("a repeated plain label's ordinal ends the title the row draws, or is the title without one", () => {
  const rows = findRows(
    world({
      terminals: [
        fish("a", "/home/me/x"),
        fish("b", "/home/me/x"),
        fish("c", "/home/me/y", { name: "server" }),
        fish("d", "/home/me/z", { name: "server" }),
        fish("e", "/home/me/w"),
      ],
      panes: ["a", "b", "c", "d", "e"].map((address) => pane(address, "t1")),
      spaces: [space("s1", "one", ["t1"])],
    }),
  );
  const titleOf = (address) => plainRow(rows, address).model.title;
  assert.equal(titleOf("a"), "#1");
  assert.equal(titleOf("b"), "#2");
  assert.equal(titleOf("c"), "server  #1");
  assert.equal(titleOf("d"), "server  #2");
  assert.equal(titleOf("e"), null);
  assert.equal(plainRow(rows, "d").model.label, "fish  server  #2");
});

// A plain terminal at `address` whose foreground runs `make dev`, apart
// from its shell (root pid 100), with `fields` overriding the defaults.
const making = (address, fields = {}) =>
  terminal(address, null, {
    program: {
      name: "make",
      key: "make",
      shell: false,
    },
    cwd: "/home/me/x",
    pid: 100,
    foreground: {
      pid: 200,
      name: "make",
      argv: ["make", "dev"],
      cwd: "/home/me/x",
    },
    ...fields,
  });

test("a plain terminal running a command shows it as its row's detail, without a start time; at its shell, no detail", () => {
  const rows = findRows(
    world({
      terminals: [
        making("run"),
        fish("sh", "/home/me/x", {
          pid: 100,
          foreground: {
            pid: 100,
            name: "fish",
            argv: ["fish"],
            cwd: "/home/me/x",
          },
        }),
      ],
      panes: [pane("run", "t1"), pane("sh", "t1")],
      spaces: [space("s1", "one", ["t1"])],
    }),
  );

  assert.deepEqual(plainRow(rows, "run").model.detail, {
    kind: "command",
    text: "make dev",
    since: null,
  });
  assert.equal(plainRow(rows, "sh").model.detail, null);
  assert.ok(!plainRow(rows, "run").text.includes("dev"));
  assert.equal(rowHeight(plainRow(rows, "run")), THREE_LINE_ROW_H);
  assert.equal(rowHeight(plainRow(rows, "sh")), TWO_LINE_ROW_H);
});

test("a running command leaves a repeated plain label's ordinal and title as they are", () => {
  const rows = findRows(
    world({
      terminals: [making("a"), making("b", { name: "server" }), making("c")],
      panes: ["a", "b", "c"].map((address) => pane(address, "t1")),
      spaces: [space("s1", "one", ["t1"])],
    }),
  );

  const titleOf = (address) => plainRow(rows, address).model.title;
  assert.equal(titleOf("a"), "#1");
  assert.equal(titleOf("b"), "server");
  assert.equal(titleOf("c"), "#2");
  for (const address of ["a", "b", "c"])
    assert.equal(plainRow(rows, address).model.detail.text, "make dev");
});

test("plain terminals follow their space's tab order, then panes() order", () => {
  const rows = findRows(
    world({
      terminals: [fish("a", "/a"), fish("b", "/b"), fish("c", "/c")],
      panes: [pane("a", "t2"), pane("b", "t1"), pane("c", "t2")],
      spaces: [space("s1", "one", ["t1", "t2"])],
    }),
  );
  assert.deepEqual(
    rows.filter((r) => r.kind === "terminal").map((r) => r.address),
    ["b", "a", "c"],
  );
});

// A world of one agent per space, `status` in tab `t<n>` of space `s<n>`
// for each entry of `statuses` (null: a space without agents), with
// `spaces()` in that order.
function spacesWorld(statuses, fields = {}) {
  const entries = statuses.map((status, i) => ({
    n: i + 1,
    status,
  }));
  const agents = entries.filter((e) => e.status !== null);
  return world({
    terminals: agents.map((e) => terminal(`a${e.n}`, e.status)),
    agents: agents.map((e) => agent(`a${e.n}`, e.status, { tab: `t${e.n}` })),
    panes: agents.map((e) => pane(`a${e.n}`, `t${e.n}`)),
    spaces: entries.map((e) => space(`s${e.n}`, `space ${e.n}`, [`t${e.n}`])),
    ...fields,
  });
}

test("spaces list in spaces() order, whatever their agents' statuses", () => {
  const rows = findRows(
    spacesWorld([null, "idle", "blocked", "working", "done", null]),
  );
  assert.deepEqual(spaceRowKeys(rows), [
    "s:s1",
    "s:s2",
    "s:s3",
    "s:s4",
    "s:s5",
    "s:s6",
  ]);
});

// A world whose spaces, in spaces() order, are the worktree ws1, the plain
// notes, the unknown new, the main checkout dots and the worktree ws2, with
// the checkouts the sidebar shares for all but new; each space holds one
// empty tab named after its id.
function checkoutsWorld() {
  const at = (id, name, folder) => ({
    ...space(id, name, [`t-${id}`]),
    folder,
  });
  const checkout = (top, linked) => ({
    name: "dotfiles",
    top,
    repo: "/src/dotfiles/.git",
    linked,
  });
  return world({
    spaces: [
      at("ws1", "one", "/w/ws1"),
      at("notes", "notes", "/home/me/notes"),
      at("new", "new", "/home/me/new"),
      at("dots", "dots", "/src/dotfiles"),
      at("ws2", "two", "/w/ws2/sub"),
    ],
    checkouts: {
      ws1: checkout("/w/ws1", true),
      notes: null,
      dots: checkout("/src/dotfiles", false),
      ws2: checkout("/w/ws2", true),
    },
  });
}

// `rows`' space headers as [key, branch mark, checkout line], each followed
// by its tab dividers' keys.
const spaceListing = (rows) =>
  rows.flatMap((r) =>
    r.kind === "space"
      ? [[r.key, r.tree, r.checkoutLine]]
      : r.kind === "tab"
        ? [r.key]
        : [],
  );

test("findRows lists each worktree's space under its repo's main checkout, marked, each space with its shared checkout line", () => {
  assert.deepEqual(spaceListing(findRows(checkoutsWorld())), [
    ["s:notes", null, "notes"],
    "t:t-notes",
    ["s:new", null, null],
    "t:t-new",
    ["s:dots", null, "dotfiles"],
    "t:t-dots",
    ["s:ws1", "├─", "dotfiles / ws1"],
    "t:t-ws1",
    ["s:ws2", "└─", "dotfiles / ws2"],
    "t:t-ws2",
  ]);
});

test("findRows without shared checkouts lists spaces in spaces() order, unmarked, without checkout lines", () => {
  const rows = findRows({
    ...checkoutsWorld(),
    checkouts: null,
  });
  assert.deepEqual(spaceListing(rows), [
    ["s:ws1", null, null],
    "t:t-ws1",
    ["s:notes", null, null],
    "t:t-notes",
    ["s:new", null, null],
    "t:t-new",
    ["s:dots", null, null],
    "t:t-dots",
    ["s:ws2", null, null],
    "t:t-ws2",
  ]);
});

test("findRows lets a query match a space by its checkout line", () => {
  const rows = findRows(checkoutsWorld());
  const text = (key) => rows.find((r) => r.key === key).text;
  assert.equal(text("s:ws1"), "one  dotfiles / ws1");
  assert.equal(text("s:new"), "new");
});

test("findRows gives each terminal row its tab's index and its pane's place in the tab, mod panes counted", () => {
  const rows = findRows(
    world({
      terminals: [
        terminal("a", "idle", { name: "a" }),
        terminal("b", "idle", { name: "b" }),
        terminal("c", "idle", { name: "c" }),
        terminal("loose", "idle", {
          name: "loose",
          parent: "a",
        }),
      ],
      panes: [
        pane("a", "t2"),
        pane(null, "t2"),
        pane("c", "t1"),
        pane("b", "t2"),
      ],
      spaces: [space("s1", "one", ["t1", "t2"])],
    }),
  );
  const place = (address) => {
    const r = agentRow(rows, address);
    return [r.tabIndex, r.paneIndex];
  };
  assert.deepEqual(place("a"), [2, 1]);
  // The mod pane before it in its tab takes place 2.
  assert.deepEqual(place("b"), [2, 3]);
  assert.deepEqual(place("c"), [1, 1]);
  assert.deepEqual(place("loose"), [null, null]);
});

test("terminalPreviewHeader says where a terminal is: tab, pane and folder, or no pane", () => {
  assert.equal(
    terminalPreviewHeader({
      tab: "t2",
      tabIndex: 2,
      paneIndex: 1,
      folder: "~/src/app",
    }),
    "tab 2 · pane 1 · ~/src/app",
  );
  assert.equal(
    terminalPreviewHeader({
      tab: "t9",
      tabIndex: null,
      paneIndex: 3,
      folder: null,
    }),
    "pane 3",
  );
  assert.equal(
    terminalPreviewHeader({
      tab: null,
      tabIndex: null,
      paneIndex: null,
      folder: "~/src/app",
    }),
    "no pane · ~/src/app",
  );
});

test("findRows gives a plain terminal its folder for the preview header", () => {
  const rows = findRows(
    world({
      terminals: [fish("sh", "/home/me/src")],
      panes: [pane("sh", "t1")],
      spaces: [space("s1", "one", ["t1"])],
    }),
  );
  const sh = rows.find((r) => r.key === "a:sh");
  assert.equal(terminalPreviewHeader(sh), "tab 1 · pane 1 · ~/src");
});

test("rowHeight gives a space row with a checkout line two lines, one without it one", () => {
  const rows = findRows(checkoutsWorld());
  const height = (key) => rowHeight(rows.find((r) => r.key === key));
  assert.equal(height("s:dots"), TWO_LINE_ROW_H);
  assert.equal(height("s:notes"), TWO_LINE_ROW_H);
  assert.equal(height("s:new"), ROW_H);
});

test("elsewhere comes after every space, even holding a blocked agent", () => {
  const base = spacesWorld(["working", null]);
  const rows = findRows({
    ...base,
    terminals: [...base.terminals, terminal("orphan", "blocked")],
  });
  assert.deepEqual(headerKeys(rows), ["m:", "s:s1", "s:s2", "elsewhere:"]);
  const label = rows.find((r) => r.key === "elsewhere:");
  assert.equal(label.kind, "elsewhere");
  assert.equal(label.text, "elsewhere");
  assert.equal(label.machine, null);
  assert.equal(agentRow(rows, "orphan").space, null);
});

// A world on three machines as `hc machine ls` lists them: zed connected,
// box needing a login since 5, and a temporary tmp. This computer holds
// space s1 with A in its pane and the paneless orphan o1 elsewhere; box
// holds space box/s2 with box/1 in its pane and the paneless box/7
// elsewhere; zed holds nothing.
function machinesWorld() {
  return world({
    terminals: [
      terminal("A", "idle"),
      terminal("o1", "idle"),
      terminal("box/1", "idle"),
      terminal("box/7", "idle"),
    ],
    panes: [pane("A", "t1"), pane("box/1", "bt")],
    spaces: [space("s1", "one", ["t1"]), space("box/s2", "two", ["bt"], "box")],
    machines: [
      {
        name: "zed",
        state: "connected",
      },
      {
        name: "box",
        state: "needs_login",
        since_ms: 5,
      },
      {
        name: "tmp",
        state: "connected",
        temporary: true,
      },
    ],
  });
}

test("findRows heads every machine, this computer first and the others by name, each with its spaces and then its elsewhere", () => {
  const rows = findRows(machinesWorld());
  assert.deepEqual(
    rows.map((r) => r.key),
    [
      "m:",
      "s:s1",
      "t:t1",
      "a:A",
      "elsewhere:",
      "a:o1",
      "m:box",
      "s:box/s2",
      "t:bt",
      "a:box/1",
      "elsewhere:box",
      "a:box/7",
      "m:zed",
      "new:terminal",
      "new:space:",
      "new:space:zed",
    ],
  );

  const header = (key) => rows.find((r) => r.key === key);
  assert.deepEqual(header("m:"), {
    kind: "machine",
    key: "m:",
    text: "this computer",
    machine: {
      name: null,
      state: null,
      sinceMs: null,
    },
  });
  assert.deepEqual(header("m:box").machine, {
    name: "box",
    state: "needs_login",
    sinceMs: 5,
  });
  assert.equal(header("elsewhere:box").machine, "box");
  assert.equal(agentRow(rows, "box/7").note, "no pane");
});

test("findRows heads this computer even when it is the only machine and holds nothing", () => {
  assert.deepEqual(
    findRows(world({})).map((r) => [r.kind, r.key]),
    [
      ["machine", "m:"],
      ["new-terminal", "new:terminal"],
      ["new-space", "new:space:"],
    ],
  );
});

test("findRows starts every tab of a space with a divider, in tab order, empty ones included, and lists its paneless terminals after them without one", () => {
  const s1 = space("s1", "one", ["t1", "t2", "t3"]);
  const rows = findRows(
    world({
      terminals: [
        terminal("A", "idle"),
        terminal("B", "idle"),
        terminal("m", "idle", { labels: { "herdr.space": "s1" } }),
      ],
      agents: [
        agent("A", "idle", { tab: "t1" }),
        agent("B", "idle", { tab: "t3" }),
      ],
      panes: [pane("A", "t1"), pane("B", "t3")],
      spaces: [s1],
    }),
  );
  assert.deepEqual(
    rows.map((r) => r.key),
    [
      "m:",
      "s:s1",
      "t:t1",
      "a:A",
      "t:t2",
      "t:t3",
      "a:B",
      "a:m",
      "new:terminal",
      "new:space:",
    ],
  );
  assert.deepEqual(
    rows.find((r) => r.key === "t:t1"),
    {
      kind: "tab",
      key: "t:t1",
      text: "tab t1",
      tab: s1.tabs[0],
      space: s1,
    },
  );
  assert.equal(agentRow(rows, "m").note, "no pane");
  assert.deepEqual(
    rows.filter((r) => r.kind === "terminal").map((r) => r.folded),
    [false, false, false],
  );
  assert.deepEqual(unfoldedRows(rows), rows);
});

test("a folded tab keeps its divider but leaves its terminal rows out of the empty query's list, which a query still matches", () => {
  // t1 is settled with every terminal quiet, so it folds; t3 is settled
  // with a blocked agent, so it stays open; t2 is not settled.
  const s1 = space("s1", "one", ["t1", "t2", "t3"]);
  s1.tabs[0].settled = true;
  s1.tabs[2].settled = true;
  const rows = findRows(
    world({
      terminals: [
        terminal("A", "idle"),
        terminal("k", "working", { parent: "A" }),
        terminal("B", "idle"),
        terminal("C", "blocked"),
      ],
      agents: [
        agent("A", "idle", { tab: "t1" }),
        agent("B", "idle", { tab: "t2" }),
        agent("C", "blocked", { tab: "t3" }),
      ],
      panes: [pane("A", "t1"), pane("B", "t2"), pane("C", "t3")],
      spaces: [s1],
    }),
  );

  assert.deepEqual(
    rows.filter((r) => r.kind === "terminal").map((r) => [r.address, r.folded]),
    [
      ["A", true],
      ["k", true],
      ["B", false],
      ["C", false],
    ],
  );
  assert.deepEqual(
    unfoldedRows(rows).map((r) => r.key),
    [
      "m:",
      "s:s1",
      "t:t1",
      "t:t2",
      "a:B",
      "t:t3",
      "a:C",
      "new:terminal",
      "new:space:",
    ],
  );
  assert.deepEqual(
    filterableRows(rows)
      .filter((r) => r.kind === "terminal")
      .map((r) => r.address),
    ["A", "k", "B", "C"],
  );
  // The divider carries the tab, whose `settled` dims it.
  assert.equal(rows.find((r) => r.key === "t:t1").tab.settled, true);
});

test("the cursor skips machine headers, tab dividers and elsewhere labels", () => {
  const rows = findRows(machinesWorld());
  const selectable = rows.map(isSelectable);
  const at = (key) => rows.findIndex((r) => r.key === key);

  // The list opens on the first space, below this computer's header.
  assert.equal(selectableIndex(selectable, 0, 1), at("s:s1"));
  // Down from the first space passes its tab's divider.
  assert.equal(selectableIndex(selectable, at("s:s1") + 1, 1), at("a:A"));
  // Up from the first terminal passes the divider back to its space.
  assert.equal(selectableIndex(selectable, at("a:A") - 1, -1), at("s:s1"));
  // Down from this computer's last terminal passes box's header.
  assert.equal(selectableIndex(selectable, at("a:o1") + 1, 1), at("s:box/s2"));
  // Up from box's elsewhere terminal passes its elsewhere label.
  assert.equal(
    selectableIndex(selectable, at("a:box/7") - 1, -1),
    at("a:box/1"),
  );
  // Down from box's last terminal passes zed's empty header.
  assert.equal(
    selectableIndex(selectable, at("a:box/7") + 1, 1),
    at("new:terminal"),
  );
});

test("membership: a terminal's own pane beats its label", () => {
  const rows = findRows(
    world({
      terminals: [terminal("x", "idle", { labels: { "herdr.space": "s2" } })],
      panes: [pane("x", "t1")],
      spaces: [space("s1", "one", ["t1"]), space("s2", "two", ["t2"])],
    }),
  );
  assert.equal(agentRow(rows, "x").space.id, "s1");
});

test("membership: a paneless sub-agent of a plain shell is under the shell's space", () => {
  const rows = findRows(
    world({
      terminals: [fish("sh", "/x"), terminal("kid", "idle", { parent: "sh" })],
      panes: [pane("sh", "t2")],
      spaces: [space("s1", "one", ["t1"]), space("s2", "two", ["t2"])],
    }),
  );
  assert.equal(agentRow(rows, "kid").space.id, "s2");
  assert.equal(agentRow(rows, "kid").depth, 1);
  assert.equal(agentRow(rows, "kid").parentLabel, "fish  /x");
});

test("membership: a labelled paneless agent is under its label's space, else elsewhere", () => {
  const rows = findRows(
    world({
      terminals: [
        terminal("lost", "idle"),
        terminal("labelled", "idle", { labels: { "herdr.space": "s2" } }),
      ],
      spaces: [space("s1", "one", ["t1"]), space("s2", "two", ["t2"])],
    }),
  );
  assert.equal(agentRow(rows, "labelled").space.id, "s2");
  assert.equal(agentRow(rows, "lost").space, null);
  assert.deepEqual(headerKeys(rows), ["m:", "s:s1", "s:s2", "elsewhere:"]);
});

test("membership: a label naming no space falls through to the parent", () => {
  const rows = findRows(
    world({
      terminals: [
        terminal("p", "idle"),
        terminal("kid", "idle", {
          parent: "p",
          labels: { "herdr.space": "gone" },
        }),
      ],
      panes: [pane("p", "t1")],
      spaces: [space("s1", "one", ["t1"])],
    }),
  );
  assert.equal(agentRow(rows, "kid").space.id, "s1");
  assert.deepEqual(agentTree(rows), [
    ["p", 0],
    ["kid", 1],
  ]);
});

test("membership: panes place terminals the same with no labels, null labels or labels", () => {
  const variants = [
    {},
    { labels: null },
    { labels: { "herdr.space": "s1" } },
  ].map((labels) =>
    findRows(
      world({
        terminals: [
          terminal("a", "idle", labels),
          terminal("k", "idle", {
            parent: "a",
            ...labels,
          }),
          fish("sh", "/x", labels),
        ],
        panes: [pane("a", "t1"), pane("sh", "t1")],
        spaces: [space("s1", "one", ["t1"])],
      }),
    ),
  );
  assert.deepEqual(variants[1], variants[0]);
  assert.deepEqual(variants[2], variants[0]);
  assert.equal(agentRow(variants[0], "k").space.id, "s1");
});

test("membership: a remote terminal's bare label names a space on its machine", () => {
  const rows = findRows(
    world({
      terminals: [
        terminal("box/7", "idle", {
          name: "seven",
          labels: { "herdr.space": "spc9" },
        }),
      ],
      spaces: [
        space("spc9", "local nine", ["t1"]),
        space("box/spc9", "nine", ["box/t9"], "box"),
      ],
    }),
  );
  const seven = agentRow(rows, "box/7");
  assert.equal(seven.space.id, "box/spc9");
  assert.equal(seven.text, "seven  idle  nine  box");
  assert.equal(rows.find((r) => r.key === "s:box/spc9").text, "nine  box");
});

test("every terminal row's text ends with its space, or elsewhere, and its machine", () => {
  const base = treeWorld();
  const rows = findRows({
    ...base,
    terminals: [
      ...base.terminals,
      terminal("orphan", "idle"),
      terminal("box/3", "idle"),
    ],
  });
  const terminalRows = rows.filter((r) => r.kind === "terminal");
  assert.ok(terminalRows.length > 0);
  for (const r of terminalRows) {
    const place = [r.space?.name ?? "elsewhere", r.machine]
      .filter(Boolean)
      .join("  ");
    assert.ok(r.text.endsWith(`  ${place}`), r.text);
  }
  assert.equal(agentRow(rows, "box/3").text, "box/3  idle  elsewhere  box");
});

test("filterableRows drops only the machine headers, tab dividers and elsewhere labels, the rows isSelectable refuses", () => {
  const rows = findRows(machinesWorld());
  const unselectable = [
    "m:",
    "t:t1",
    "elsewhere:",
    "m:box",
    "t:bt",
    "elsewhere:box",
    "m:zed",
  ];
  assert.deepEqual(
    rows.filter((r) => !isSelectable(r)).map((r) => r.key),
    unselectable,
  );
  assert.deepEqual(
    filterableRows(rows).map((r) => r.key),
    rows.map((r) => r.key).filter((k) => !unselectable.includes(k)),
  );
});

test("selectableIndex skips unselectable rows in its direction, wrapping", () => {
  const selectable = [false, true, true, false];
  assert.equal(selectableIndex(selectable, 0, 1), 1);
  assert.equal(selectableIndex(selectable, 2, 1), 2);
  assert.equal(selectableIndex(selectable, 3, 1), 1);
  assert.equal(selectableIndex(selectable, 0, -1), 2);
  assert.equal(selectableIndex(selectable, 3, -1), 2);
  assert.equal(selectableIndex([false, false], 1, 1), 1);
  assert.equal(selectableIndex([], 3, -1), 0);
});

// Whether row `i` of rows with `heights` shows whole in a `viewHeight` px
// view scrolled to `scroll`: where the render keeps the selection without
// scrolling.
const isRowInView = (i, heights, scroll, viewHeight) => {
  const offsets = rowOffsets(heights);
  return offsets[i] >= scroll && offsets[i + 1] <= scroll + viewHeight;
};

// `n` rows, each 10 px tall.
const tenPx = (n) => Array.from({ length: n }, () => 10);

test("wheelSelectionIndex keeps the cursor inside the view past a header at the bottom edge", () => {
  // Rows 3-5 showed at scroll 30 with the cursor on 5; a 2 px wheel up
  // shows 3 and the header at 4 whole, and cuts off 5.
  const selectable = [true, true, true, true, false, true, true, true];
  const heights = tenPx(selectable.length);
  const at = wheelSelectionIndex(selectable, heights, 28, 30, 5);
  assert.equal(at, 3);
  assert.ok(isRowInView(at, heights, 28, 30));
});

test("wheelSelectionIndex steps inward past a header at the top edge", () => {
  // Rows 0-2 showed at scroll 0 with the cursor on 1; a 12 px wheel down
  // shows the header at 2 and row 3 whole.
  const selectable = [true, true, false, true, true, true];
  const heights = tenPx(selectable.length);
  const at = wheelSelectionIndex(selectable, heights, 12, 30, 1);
  assert.equal(at, 3);
  assert.ok(isRowInView(at, heights, 12, 30));
  assert.equal(wheelSelectionIndex(selectable, heights, 12, 30, 3), 3);
});

test("wheelSelectionIndex with no selectable row in view takes the nearest inward", () => {
  const selectable = [true, false, true];
  assert.equal(wheelSelectionIndex(selectable, tenPx(3), 10, 10, 2), 0);
  assert.equal(wheelSelectionIndex(selectable, tenPx(3), 10, 10, 0), 2);
  assert.equal(wheelSelectionIndex([], [], 0, 30, 4), 0);
});

test("wheelSelectionIndex measures rows of mixed heights", () => {
  // Tops 0, 32, 78, 124, 156; the strip is 202 px tall.
  const heights = [32, 46, 46, 32, 46];

  // At scroll 40 a 100 px view shows only row 2 whole (78-124): row 3 ends
  // at 156, past 140. A uniform 32 px row would put row 3 in view.
  const allSelectable = heights.map(() => true);
  const at = wheelSelectionIndex(allSelectable, heights, 40, 100, 4);
  assert.equal(at, 2);
  assert.ok(isRowInView(at, heights, 40, 100));

  // At scroll 78 an 80 px view shows rows 2 and 3 whole; from below, the
  // cursor steps inward past the header at 3 to row 2.
  const headerAt3 = [true, true, true, false, true];
  const fromBelow = wheelSelectionIndex(headerAt3, heights, 78, 80, 4);
  assert.equal(fromBelow, 2);
  assert.ok(isRowInView(fromBelow, heights, 78, 80));
});

test("rowOffsets gives each row's top and then the strip's height", () => {
  assert.deepEqual(rowOffsets([]), [0]);
  assert.deepEqual(rowOffsets([32, 46, 32]), [0, 32, 78, 110]);
});

test("rowHeight gives agent rows three lines, plain terminal rows two, machine headers and elsewhere labels the heading height, tab dividers the sidebar's divider height, every other row one line", () => {
  const rows = findRows(
    world({
      terminals: [
        terminal("doing", "working", {
          report: {
            state: "working",
            msg: "Reading the docs",
          },
        }),
        terminal("turned", "idle", { turn: 3 }),
        terminal("rooted", "idle", { cwd: "/home/me/x" }),
        terminal("silent", "idle"),
        fish("sh", "/home/me/x"),
        fish("named", "/home/me/x", { name: "server" }),
      ],
      agents: [agent("doing", "working")],
      panes: [pane("doing", "t1"), pane("sh", "t1"), pane("named", "t1")],
      spaces: [space("s1", "dots", ["t1"])],
    }),
  );

  for (const address of ["doing", "turned", "rooted", "silent"])
    assert.equal(rowHeight(agentRow(rows, address)), THREE_LINE_ROW_H, address);
  assert.equal(rowHeight(plainRow(rows, "sh")), TWO_LINE_ROW_H);
  assert.equal(rowHeight(plainRow(rows, "named")), TWO_LINE_ROW_H);
  const kinds = new Set(rows.map((r) => r.kind));
  for (const kind of ["machine", "elsewhere", "space", "tab", "new-space"])
    assert.ok(kinds.has(kind), `fixture has a ${kind} row`);
  for (const r of rows.filter((r) => r.kind !== "terminal"))
    assert.equal(
      rowHeight(r),
      r.kind === "machine" || r.kind === "elsewhere"
        ? HEADING_ROW_H
        : r.kind === "tab"
          ? TAB_DIVIDER_ROW_H
          : ROW_H,
      r.key,
    );
  // The sidebar's divider: `tabDivider`'s height, no padding around it.
  assert.equal(TAB_DIVIDER_ROW_H, 18);
});

test("findRows shows and matches a blocked agent's report kind only while blocked", () => {
  const rows = findRows(
    world({
      terminals: [
        terminal("asking", "blocked", {
          report: {
            state: "blocked",
            kind: "permission",
          },
        }),
        terminal("stale", "working", {
          report: {
            state: "working",
            kind: "question",
          },
        }),
        fish("sh", "/home/me/x"),
      ],
      agents: [agent("asking", "blocked"), agent("stale", "working")],
      panes: [pane("asking", "t1"), pane("stale", "t1"), pane("sh", "t1")],
      spaces: [space("s1", "dots", ["t1"])],
    }),
  );

  const asking = agentRow(rows, "asking");
  assert.deepEqual(asking.model.detail, {
    kind: "blocked",
    text: "permission",
  });
  assert.match(asking.text, /\bpermission\b/);

  const stale = agentRow(rows, "stale");
  assert.deepEqual(stale.model.detail, {
    kind: "status",
    text: "working",
  });
  assert.doesNotMatch(stale.text, /question/);

  assert.equal(plainRow(rows, "sh").model.detail, null);
});

// Rows for `match`, keyed "a:<n>" by position from 1.
const matchRows = (...texts) =>
  texts.map((text, i) => ({
    key: `a:${i + 1}`,
    text,
  }));

// A fake `exec` that records each call and answers with `result`.
function fakeExec(result) {
  const calls = [];
  const exec = async (command, args) => {
    calls.push([command, args]);
    return {
      code: 0,
      stdout: "",
      stderr: "",
      ...result,
    };
  };
  return { exec, calls };
}

// A promise with its resolve and reject functions, settled by the test.
function deferred() {
  let resolve;
  let reject;
  const promise = new Promise((res, rej) => {
    resolve = res;
    reject = rej;
  });
  return { promise, resolve, reject };
}

test("FZF_SCRIPT hands sh a literal \\n and \\t", () => {
  assert.equal(
    FZF_SCRIPT,
    'f=$1 q=$2; shift 2; printf "%s\\n" "$@" | "$f" --filter="$q" --delimiter="\\t" --nth=2.. --tiebreak=index',
  );
});

test("matchArgs passes fzf, the query and one key-tab-text line per row", () => {
  const rows = matchRows("dot\tfiles\n", "web");
  assert.deepEqual(matchArgs("/bin/fzf", "do", rows), [
    "-c",
    FZF_SCRIPT,
    "sh",
    "/bin/fzf",
    "do",
    "a:1\tdot files",
    "a:2\tweb",
  ]);
});

test("sanitize turns tabs, newlines and C1 characters into single spaces", () => {
  assert.equal(sanitize(" a\tb\n\nc\u0085d\u007fe\u0000 "), "a b c d e");
  assert.equal(sanitize("plain  text"), "plain text");
});

test("a blank query or no rows returns the rows without running fzf", async () => {
  const { exec, calls } = fakeExec({ code: 2 });
  const rows = matchRows("dot", "web");
  assert.deepEqual(await match(exec, "fzf", "  ", rows), rows);
  assert.deepEqual(await match(exec, "fzf", "dot", []), []);
  assert.equal(calls.length, 0);
});

test("exit 0 maps fzf's lines to rows in fzf's order, skipping unknown keys", async () => {
  const rows = matchRows("dot", "web", "neo");
  const { exec, calls } = fakeExec({
    stdout: "a:3\tneo\nzz\tgone\na:1\tdot\n",
  });
  assert.deepEqual(await match(exec, "fzf", "o", rows), [rows[2], rows[0]]);
  assert.deepEqual(calls, [["sh", matchArgs("fzf", "o", rows)]]);
  assert.deepEqual(parseMatch("a:2\tweb", rows), [rows[1]]);
});

test("exit 1 is no match and exit 2 is an error", async () => {
  const rows = matchRows("dot");
  assert.deepEqual(
    await match(fakeExec({ code: 1 }).exec, "fzf", "x", rows),
    [],
  );
  await assert.rejects(
    match(fakeExec({ code: 2, stderr: "bad query\n" }).exec, "fzf", "x", rows),
    { message: "bad query" },
  );
  await assert.rejects(match(fakeExec({ code: 2 }).exec, "fzf", "x", rows), {
    message: "fzf exited with 2",
  });
});

test("matchOrAll returns every row and the first error line when matching fails", async () => {
  const rows = matchRows("dot", "web");
  assert.deepEqual(
    await matchOrAll(
      fakeExec({ code: 2, stderr: "bad query\nmore\n" }).exec,
      "fzf",
      "x",
      rows,
    ),
    {
      rows,
      error: "bad query",
    },
  );
  const unstartable = async () => {
    throw new Error("no such program: sh\ndetail");
  };
  assert.deepEqual(await matchOrAll(unstartable, "fzf", "x", rows), {
    rows,
    error: "no such program: sh",
  });
  assert.deepEqual(
    await matchOrAll(fakeExec({ stdout: "a:2\tweb\n" }).exec, "fzf", "w", rows),
    {
      rows: [rows[1]],
      error: null,
    },
  );
});

test("sameMatchInput compares keys and texts in order", () => {
  const rows = matchRows("dot", "web");
  assert.equal(sameMatchInput(rows, matchRows("dot", "web")), true);
  assert.equal(sameMatchInput(rows, matchRows("dot", "wob")), false);
  assert.equal(sameMatchInput(rows, [rows[1], rows[0]]), false);
  assert.equal(sameMatchInput(rows, matchRows("dot")), false);
});

test("LatestRequest discards an older request that settles after a newer one", async () => {
  const latest = new LatestRequest();
  const older = deferred();
  const newer = deferred();
  const olderRun = latest.run(() => older.promise);
  const newerRun = latest.run(() => newer.promise);
  newer.resolve("new");
  older.resolve("old");
  assert.deepEqual(await newerRun, {
    stale: false,
    value: "new",
  });
  assert.deepEqual(await olderRun, { stale: true });
});

test("LatestRequest turns an older rejection stale and rethrows the latest", async () => {
  const latest = new LatestRequest();
  const older = deferred();
  const olderRun = latest.run(() => older.promise);
  const newerRun = latest.run(async () => {
    throw new Error("latest failed");
  });
  older.reject(new Error("older failed"));
  assert.deepEqual(await olderRun, { stale: true });
  await assert.rejects(newerRun, { message: "latest failed" });
});

test("LatestRequest turns a request running at invalidate stale", async () => {
  const latest = new LatestRequest();
  const pending = deferred();
  const run = latest.run(() => pending.promise);
  latest.invalidate();
  pending.resolve("answer");
  assert.deepEqual(await run, { stale: true });
  assert.deepEqual(await latest.run(async () => "next"), {
    stale: false,
    value: "next",
  });
});

// Renders the hub's list for `query` over `rows` as `shownList` in
// `main.ts` does: plans it from `hub`'s match state, stores the plan's
// state back in `hub` and invalidates `hub.matcher` when the plan says to.
// Returns the plan.
function renderList(hub, query, rows) {
  const plan = planShownList(query, rows, hub);
  if (plan.invalidate) hub.matcher.invalidate();
  hub.requested = plan.requested;
  hub.shownQuery = plan.shownQuery;
  return plan;
}

// A new hub with no match run yet.
function newHub() {
  return {
    matcher: new LatestRequest(),
    matched: null,
    requested: null,
    shownQuery: "",
  };
}

// Runs the match `start` through `hub.matcher` as `runMatch` does: once
// `answer` resolves with keys, stores them with `start` as `hub.matched`
// unless the run turned stale. Resolves with whether it stored them.
async function runListMatch(hub, start, answer) {
  const r = await hub.matcher.run(() => answer.promise);
  if (r.stale) return false;

  hub.matched = {
    ...start,
    keys: r.value,
    error: null,
  };
  return true;
}

test("planShownList: backspacing past a running match shows the cached one and stales it", async () => {
  const hub = newHub();
  const rows = matchRows("ab", "b");

  const typedA = renderList(hub, "a", rows);
  assert.equal(typedA.shown, null);
  assert.equal(typedA.shownQuery, "");
  assert.deepEqual(typedA.start, {
    query: "a",
    input: rows,
  });
  const answerA = deferred();
  const runA = runListMatch(hub, typedA.start, answerA);
  answerA.resolve(["a:1"]);
  assert.equal(await runA, true);
  const matchedA = hub.matched;
  assert.equal(renderList(hub, "a", rows).shown, matchedA);

  const typedAb = renderList(hub, "ab", rows);
  assert.equal(typedAb.shown, matchedA);
  assert.equal(typedAb.shownQuery, "a");
  assert.equal(typedAb.start.query, "ab");
  assert.equal(typedAb.invalidate, false);
  const answerAb = deferred();
  const runAb = runListMatch(hub, typedAb.start, answerAb);

  const backspaced = renderList(hub, "a", rows);
  assert.equal(backspaced.shown, matchedA);
  assert.equal(backspaced.shownQuery, "a");
  assert.equal(backspaced.start, null);
  assert.equal(backspaced.invalidate, true);
  assert.equal(backspaced.requested, matchedA);
  answerAb.resolve(["a:1"]);
  assert.equal(await runAb, false);
  assert.equal(hub.matched, matchedA);
});

test("planShownList: rows changing back while a match runs reuse the cached match", () => {
  const hub = newHub();
  const rows = matchRows("dot", "web");
  const changed = matchRows("dot", "wob");
  const matchedD = {
    query: "d",
    input: matchRows("dot", "web"),
    keys: ["a:1"],
    error: null,
  };
  hub.matched = matchedD;
  hub.requested = matchedD;
  hub.shownQuery = "d";

  const onChange = renderList(hub, "d", changed);
  assert.equal(onChange.shown, matchedD);
  assert.deepEqual(onChange.start, {
    query: "d",
    input: changed,
  });
  assert.equal(onChange.invalidate, false);

  const onRevert = renderList(hub, "d", rows);
  assert.equal(onRevert.shown, matchedD);
  assert.equal(onRevert.start, null);
  assert.equal(onRevert.invalidate, true);
  assert.equal(onRevert.requested, matchedD);
});

test("planShownList: a blank query shows every row and starts nothing", () => {
  const rows = matchRows("dot", "web");
  const pending = {
    query: "w",
    input: rows,
  };
  const plan = planShownList(" ", rows, {
    matched: {
      query: "d",
      input: rows,
      keys: ["a:1"],
      error: "bad query",
    },
    requested: pending,
    shownQuery: "d",
  });
  assert.deepEqual(plan, {
    shown: null,
    shownQuery: " ",
    requested: pending,
    start: null,
    invalidate: false,
  });
});

test("planShownList: a repeated render does not start the pending match again", () => {
  const rows = matchRows("dot", "web");
  const pending = {
    query: "w",
    input: matchRows("dot", "web"),
  };
  const plan = planShownList("w", rows, {
    matched: null,
    requested: pending,
    shownQuery: "",
  });
  assert.deepEqual(plan, {
    shown: null,
    shownQuery: "",
    requested: pending,
    start: null,
    invalidate: false,
  });
  assert.equal(plan.requested, pending);
});

// `exec` for the real fzf: runs `command` and resolves with its exit code
// and output, rejecting only when it cannot start, as the app's `exec` does.
const realExec = (command, args) =>
  new Promise((resolve, reject) => {
    execFile(command, args, (error, stdout, stderr) => {
      if (error && typeof error.code !== "number") reject(error);
      else
        resolve({
          code: error ? error.code : 0,
          stdout,
          stderr,
        });
    });
  });

test(
  "the real fzf matches texts, never keys, ties in input order",
  { skip: process.env.FZF ? false : "FZF is unset" },
  async () => {
    const fzf = process.env.FZF;
    const rows = matchRows("neo vim", "web app", "dot files");
    assert.deepEqual(await match(realExec, fzf, "'dot | neo", rows), [
      rows[0],
      rows[2],
    ]);
    assert.deepEqual(await match(realExec, fzf, "a:", rows), []);
  },
);

test("cursorIndex: a new query goes to the top, else the cursor keeps its row", () => {
  const keys = ["a", "b", "c"];
  assert.equal(cursorIndex(keys, "c", 2, false), 0);
  assert.equal(cursorIndex(["c", "a", "b"], "b", 0, true), 2);
  assert.equal(cursorIndex(["a", "b"], "c", 2, true), 1);
  assert.equal(cursorIndex(keys, "x", 1, true), 1);
  assert.equal(cursorIndex(keys, null, 0, true), 0);
  assert.equal(cursorIndex([], "a", 3, true), 0);
});

test("screenLines drops carriage returns and trailing blanks, keeps inner blanks", () => {
  assert.deepEqual(screenLines("one  \r\n\r\nthree\t\n  \n\n"), [
    "one",
    "",
    "three",
  ]);
  assert.deepEqual(screenLines(""), []);
});

test("previewWindow anchors at either end and clamps the offset", () => {
  assert.deepEqual(previewWindow(10, 4, 0, "bottom"), {
    start: 6,
    end: 10,
    offset: 0,
  });
  assert.deepEqual(previewWindow(10, 4, 2, "bottom"), {
    start: 4,
    end: 8,
    offset: 2,
  });
  assert.deepEqual(previewWindow(10, 4, 99, "bottom"), {
    start: 0,
    end: 4,
    offset: 6,
  });
  assert.deepEqual(previewWindow(10, 4, -3, "bottom"), {
    start: 6,
    end: 10,
    offset: 0,
  });
  assert.deepEqual(previewWindow(10, 4, 3, "top"), {
    start: 3,
    end: 7,
    offset: 3,
  });
  assert.deepEqual(previewWindow(10, 4, 99, "top"), {
    start: 6,
    end: 10,
    offset: 6,
  });
  assert.deepEqual(previewWindow(3, 4, 2, "bottom"), {
    start: 0,
    end: 3,
    offset: 0,
  });
  assert.deepEqual(previewWindow(3, 4, 2, "top"), {
    start: 0,
    end: 3,
    offset: 0,
  });
});

test("spaceTreePreview lists the space's terminals, sub-agents indented, status words aligned", () => {
  const rows = findRows(
    world({
      terminals: [
        terminal("a", "working", { name: "lead" }),
        terminal("k", "idle", {
          parent: "a",
          name: "kid",
        }),
        fish("sh", "/x", { name: "sh" }),
        terminal("o", "idle", { name: "other" }),
      ],
      agents: [agent("a", "working"), agent("o", "idle")],
      panes: [pane("a", "t1"), pane("sh", "t1"), pane("o", "t2")],
      spaces: [space("s1", "one", ["t1"]), space("s2", "two", ["t2"])],
    }),
  );
  const one = rows.find((r) => r.kind === "space").space;
  assert.deepEqual(spaceTreePreview(one, rows), [
    {
      text: "claude  lead  working",
      status: "working",
    },
    {
      text: "  kid         idle",
      status: "idle",
    },
    {
      text: "fish  sh",
      status: null,
    },
  ]);
  assert.deepEqual(spaceTreePreview(space("s3", "three", []), rows), []);
});

test("footerHints offers each row kind's keys, scrolling only with a scrollable preview", () => {
  const rows = findRows(
    treeWorld({
      terminals: [...treeWorld().terminals, terminal("orphan", "blocked")],
    }),
  );
  const byKind = {
    agent: agentRow(rows, "A"),
    plain: plainRow(rows, "t22"),
    space: rows.find((r) => r.kind === "space" && r.space.id === "s1"),
    machine: rows.find((r) => r.kind === "machine"),
    tab: rows.find((r) => r.kind === "tab"),
    elsewhere: rows.find((r) => r.kind === "elsewhere"),
    newTerminal: rows.find((r) => r.kind === "new-terminal"),
    newSpace: rows.find((r) => r.kind === "new-space"),
    none: undefined,
  };
  for (const [kind, row] of Object.entries(byKind))
    if (kind !== "none") assert.ok(row, `fixture has a ${kind} row`);

  const enter = (label) => ({
    keys: "enter",
    label,
  });
  const terminalKeys = [
    enter("go"),
    {
      keys: "ctrl-x",
      label: "end",
    },
    {
      keys: "ctrl-i",
      label: "interrupt",
    },
  ];
  const rowKeys = {
    agent: terminalKeys,
    plain: terminalKeys,
    space: [
      enter("switch"),
      {
        keys: "ctrl-x",
        label: "close",
      },
    ],
    machine: [],
    tab: [],
    elsewhere: [],
    newTerminal: [enter("create")],
    newSpace: [enter("create")],
    none: [],
  };
  const scroll = {
    keys: "ctrl-u/d",
    label: "scroll",
  };
  const always = (isNeedsYouOn) => [
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
  for (const [kind, row] of Object.entries(byKind)) {
    assert.deepEqual(
      footerHints(row, false, false),
      [...rowKeys[kind], ...always(false)],
      `${kind} without a scrollable preview`,
    );
    assert.deepEqual(
      footerHints(row, true, false),
      [...rowKeys[kind], scroll, ...always(false)],
      `${kind} with a scrollable preview`,
    );
    assert.deepEqual(
      footerHints(row, false, true),
      [...rowKeys[kind], ...always(true)],
      `${kind} with the needs-you filter on`,
    );
  }
});

test("needsYouRows keeps the terminal rows showing blocked or done, in tree order", () => {
  // The done sub-agent of a blocked agent shows idle, and a paneless error
  // under elsewhere shows blocked.
  const s1 = space("s1", "one", ["t1", "t2"]);
  const rows = findRows(
    world({
      terminals: [
        terminal("D", "done"),
        terminal("W", "working"),
        terminal("B", "blocked"),
        terminal("kid", "done", { parent: "B" }),
        terminal("I", "idle"),
        terminal("E", "error"),
        fish("sh", "/home/me/x"),
      ],
      agents: [
        agent("D", "done", { tab: "t2" }),
        agent("W", "working", { tab: "t2" }),
        agent("B", "blocked", { tab: "t2" }),
        agent("I", "idle", { tab: "t1" }),
      ],
      panes: [
        pane("I", "t1"),
        pane("D", "t2"),
        pane("W", "t2"),
        pane("B", "t2"),
        pane("sh", "t2"),
      ],
      spaces: [s1],
    }),
  );

  assert.deepEqual(
    needsYouRows(rows).map((r) => [r.address, r.model.status]),
    [
      ["D", "done"],
      ["B", "blocked"],
      ["E", "blocked"],
    ],
  );
  assert.deepEqual(needsYouRows([]), []);
});

test("a terminal row's text holds its shown status word, so a query for blocked or done finds it", () => {
  const rows = findRows(
    world({
      terminals: [
        terminal("D", "done"),
        terminal("B", "blocked"),
        terminal("kid", "done", { parent: "B" }),
        fish("sh", "/home/me/x"),
      ],
      agents: [agent("D", "done"), agent("B", "blocked")],
      panes: [pane("D", "t1"), pane("B", "t1"), pane("sh", "t1")],
      spaces: [space("s1", "dots", ["t1"])],
    }),
  );

  assert.match(agentRow(rows, "D").text, /\bdone\b/);
  assert.match(agentRow(rows, "B").text, /\bblocked\b/);
  // A done sub-agent shows idle under its parent, and its text says so.
  assert.match(agentRow(rows, "kid").text, /\bidle\b/);
  assert.doesNotMatch(agentRow(rows, "kid").text, /\bdone\b/);
  assert.equal(plainRow(rows, "sh").text, "fish  ~/x  dots");
});

test("promptHints offers only y with the prompt's verb and cancel while a prompt shows", () => {
  const world = treeWorld();
  const rows = findRows(world);
  const terminalPrompt = closePrompt(agentRow(rows, "A"), world);
  const spacePrompt = closePrompt(
    rows.find((r) => r.kind === "space" && r.space?.id === "s1"),
    world,
  );
  assert.ok(terminalPrompt && spacePrompt, "fixture rows have prompts");

  const cancel = {
    keys: "any other key",
    label: "cancel",
  };
  assert.deepEqual(promptHints(terminalPrompt.action), [
    {
      keys: "y",
      label: "end",
    },
    cancel,
  ]);
  assert.deepEqual(promptHints(spacePrompt.action), [
    {
      keys: "y",
      label: "close",
    },
    cancel,
  ]);
});

test("agentPreviewKey writes a plain terminal's null status as empty", () => {
  assert.equal(agentPreviewKey("t1", null), "a:t1|");
  assert.equal(agentPreviewKey("t1", "idle"), "a:t1|idle");
});

test("followAgentPreview reads a plain terminal's screen and keeps it while staying", () => {
  const plain = { address: "t1", status: null };

  const arrived = followAgentPreview(plain, {
    preview: null,
    previewWanted: null,
  });
  assert.deepEqual(arrived, {
    preview: null,
    previewWanted: "a:t1|",
    readKey: "a:t1|",
  });

  const shown = {
    key: "a:t1|",
    address: "t1",
    lines: ["$"],
    error: null,
  };
  assert.deepEqual(
    followAgentPreview(plain, {
      preview: shown,
      previewWanted: "a:t1|",
    }),
    {
      preview: shown,
      previewWanted: null,
      readKey: null,
    },
  );
});

// An agent screen read for the agent at `address` while it had `status`.
function screen(address, status) {
  return {
    key: agentPreviewKey(address, status),
    address,
    lines: [`${address} ${status}`],
    error: null,
  };
}

// The agent preview state after a read for `key` lands with `preview`, kept
// only while it is still wanted, as the hub keeps it.
function land(state, key, preview) {
  return isWantedAgentRead(state.previewWanted, key)
    ? { ...state, preview }
    : state;
}

test("followAgentPreview: leaving an agent for a space and returning reads it afresh", () => {
  const a = { address: "w/1", status: "idle" };
  const onA = {
    preview: screen("w/1", "idle"),
    previewWanted: null,
  };

  const left = followAgentPreview(null, onA);
  assert.deepEqual(left, {
    preview: null,
    previewWanted: null,
    readKey: null,
  });

  const back = followAgentPreview(a, left);
  assert.deepEqual(back, {
    preview: null,
    previewWanted: "a:w/1|idle",
    readKey: "a:w/1|idle",
  });
});

test("followAgentPreview: leaving an agent drops a read still waiting for it", () => {
  const waiting = {
    preview: null,
    previewWanted: agentPreviewKey("w/1", "idle"),
  };

  const left = followAgentPreview(null, waiting);
  assert.equal(left.previewWanted, null);
  assert.equal(isWantedAgentRead(left.previewWanted, "a:w/1|idle"), false);
});

test("followAgentPreview: a status change reads a new key and keeps the old screen meanwhile", () => {
  const old = screen("w/1", "working");

  const next = followAgentPreview(
    { address: "w/1", status: "done" },
    { preview: old, previewWanted: null },
  );
  assert.deepEqual(next, {
    preview: old,
    previewWanted: "a:w/1|done",
    readKey: "a:w/1|done",
  });
});

test("followAgentPreview: the same agent and status with its screen schedules no read", () => {
  const shown = screen("w/1", "idle");

  const next = followAgentPreview(
    { address: "w/1", status: "idle" },
    { preview: shown, previewWanted: "a:w/2|idle" },
  );
  assert.deepEqual(next, {
    preview: shown,
    previewWanted: null,
    readKey: null,
  });
});

test("followAgentPreview: a read already wanted for the key is not scheduled again", () => {
  const next = followAgentPreview(
    { address: "w/1", status: "idle" },
    { preview: null, previewWanted: "a:w/1|idle" },
  );
  assert.deepEqual(next, {
    preview: null,
    previewWanted: "a:w/1|idle",
    readKey: null,
  });
});

test("isWantedAgentRead accepts only the key still wanted", () => {
  assert.equal(isWantedAgentRead("a:w/1|idle", "a:w/1|idle"), true);
  assert.equal(isWantedAgentRead("a:w/1|done", "a:w/1|idle"), false);
  assert.equal(isWantedAgentRead(null, "a:w/1|idle"), false);
});

test("followAgentPreview: moving A to B and back before B's read lands keeps no stale screen", () => {
  const a = { address: "w/1", status: "idle" };
  const b = { address: "w/2", status: "working" };
  const onA = {
    preview: screen("w/1", "idle"),
    previewWanted: null,
  };

  const onB = followAgentPreview(b, onA);
  assert.equal(onB.preview, null);
  assert.equal(onB.readKey, "a:w/2|working");

  const backOnA = followAgentPreview(a, onB);
  assert.equal(backOnA.preview, null);
  assert.equal(backOnA.readKey, "a:w/1|idle");

  const bLanded = land(backOnA, "a:w/2|working", screen("w/2", "working"));
  assert.equal(bLanded.preview, null);

  const aLanded = land(bLanded, "a:w/1|idle", screen("w/1", "idle"));
  assert.deepEqual(aLanded.preview, screen("w/1", "idle"));
  assert.equal(followAgentPreview(a, aLanded).readKey, null);
});

test("descendantCount counts live descendants at every level, agents or not", () => {
  const terminals = [
    terminal("a1", "idle"),
    terminal("k1", "working", { parent: "a1" }),
    terminal("g1", "idle", { parent: "k1" }),
    terminal("sh", null, { parent: "a1", program: { name: "zsh" } }),
    terminal("other", "idle"),
  ];
  assert.equal(descendantCount("a1", terminals), 3);
  assert.equal(descendantCount("other", terminals), 0);
  assert.equal(descendantCount("missing", terminals), 0);
});

test("descendantCount skips ended terminals and their children", () => {
  const terminals = [
    terminal("a1", "idle"),
    terminal("k1", "idle", { parent: "a1", state: "exited" }),
    terminal("g1", "idle", { parent: "k1" }),
    terminal("k2", "idle", { parent: "a1" }),
  ];
  assert.equal(descendantCount("a1", terminals), 1);
});

test("descendantCount qualifies a remote child's bare parent and ends a cycle", () => {
  const remote = [
    terminal("box/a1", "idle"),
    terminal("box/k1", "idle", { parent: "a1" }),
    // A bare "a1" on another machine is not box/a1's child.
    terminal("lab/k2", "idle", { parent: "a1" }),
  ];
  assert.equal(descendantCount("box/a1", remote), 1);

  const cycle = [
    terminal("x", "idle", { parent: "y" }),
    terminal("y", "idle", { parent: "x" }),
  ];
  assert.equal(descendantCount("x", cycle), 1);
});

// An agent row for the agent at `address`, for `closePrompt`.
const agentRowAt = (address) => ({
  kind: "terminal",
  key: `a:${address}`,
  text: address,
  address,
  model: {
    address,
    label: `agent ${address}`,
    program: null,
    programName: null,
    title: `agent ${address}`,
    status: "idle",
    folder: null,
    detail: {
      kind: "status",
      text: "idle",
    },
  },
  since: null,
  depth: 0,
  parentLabel: null,
  space: null,
  machine: null,
  tab: null,
});

test("closePrompt ends an agent with terminal.kill and counts what ends with it", () => {
  const terminals = [
    terminal("a1", "idle"),
    terminal("k1", "idle", { parent: "a1" }),
    terminal("g1", "idle", { parent: "k1" }),
    terminal("sh", null, { parent: "a1" }),
  ];
  assert.deepEqual(closePrompt(agentRowAt("a1"), world({ terminals })), {
    text: "End agent a1 (+3 more)? y/n",
    action: {
      command: "terminal.kill",
      args: { terminal: "a1" },
    },
  });
  assert.equal(
    closePrompt(agentRowAt("g1"), world({ terminals })).text,
    "End agent g1? y/n",
  );
});

test("closePrompt names a tab an agent's kill closes in a space that keeps another tab", () => {
  const terminals = [
    terminal("a1", "idle"),
    terminal("k1", null, { parent: "a1" }),
    terminal("sh", null),
  ];
  const panes = [pane("a1", "t1"), pane("k1", "t1"), pane("sh", "t2")];
  const spaces = [space("s1", "dots", ["t1", "t2"])];
  assert.deepEqual(
    closePrompt(agentRowAt("a1"), world({ terminals, panes, spaces })),
    {
      text: "End agent a1 (+1 more)? — closes tab tab t1 in dots — y/n",
      action: {
        command: "terminal.kill",
        args: { terminal: "a1" },
      },
    },
  );
});

test("closePrompt names a space an agent's kill closes instead of its tabs", () => {
  const terminals = [
    terminal("a1", "idle"),
    terminal("k1", null, { parent: "a1" }),
  ];
  const panes = [pane("a1", "t1"), pane("k1", "t1")];
  const spaces = [space("s1", "solo", ["t1"])];
  assert.equal(
    closePrompt(agentRowAt("a1"), world({ terminals, panes, spaces })).text,
    "End agent a1 (+1 more)? — closes space solo — y/n",
  );
});

test("closePrompt names the tab an agent in its last pane closes", () => {
  const terminals = [terminal("a1", "idle"), terminal("sh", null)];
  const panes = [pane("sh", "t1"), pane("a1", "t2")];
  const spaces = [space("s1", "dots", ["t1", "t2"])];
  assert.equal(
    closePrompt(agentRowAt("a1"), world({ terminals, panes, spaces })).text,
    "End agent a1? — closes tab tab t2 in dots — y/n",
  );
});

test("closePrompt names every place an agent's kill closes, in spaces order", () => {
  const terminals = [
    terminal("a1", "idle"),
    terminal("k1", "idle", { parent: "a1" }),
    terminal("sh", null),
  ];
  const panes = [pane("sh", "t1"), pane("a1", "t2"), pane("k1", "t3")];
  const spaces = [
    space("s1", "dots", ["t1", "t2"]),
    space("s2", "solo", ["t3"]),
  ];
  assert.equal(
    closePrompt(agentRowAt("a1"), world({ terminals, panes, spaces })).text,
    "End agent a1 (+1 more)? — closes tab tab t2 in dots, space solo — y/n",
  );
});

test("closePrompt keeps a tab holding a mod pane open", () => {
  const terminals = [terminal("a1", "idle")];
  const panes = [
    pane("a1", "t1"),
    {
      ...pane(null, "t1"),
      terminal: null,
      mod: "files",
    },
  ];
  const spaces = [space("s1", "solo", ["t1"])];
  assert.equal(
    closePrompt(agentRowAt("a1"), world({ terminals, panes, spaces })).text,
    "End agent a1? y/n",
  );
});

test("closePrompt never closes a tab with no panes", () => {
  const terminals = [terminal("a1", "idle")];
  const spaces = [space("s1", "solo", ["t1"])];
  assert.equal(
    closePrompt(agentRowAt("a1"), world({ terminals, spaces })).text,
    "End agent a1? y/n",
  );
});

test("closePrompt ends a plain terminal with terminal.kill and names the tab it closes", () => {
  const w = world({
    terminals: [fish("sh", "/home/me/x"), fish("other", "/home/me/y")],
    panes: [pane("other", "t1"), pane("sh", "t2")],
    spaces: [space("s1", "dots", ["t1", "t2"])],
  });
  assert.deepEqual(closePrompt(plainRow(findRows(w), "sh"), w), {
    text: "End fish  ~/x? — closes tab tab t2 in dots — y/n",
    action: {
      command: "terminal.kill",
      args: { terminal: "sh" },
    },
  });
});

test("closePrompt closes a space, confirmed, and offers nothing on a machine header, a tab divider or an elsewhere label", () => {
  const two = space("s1", "dots", ["t1", "t2"]);
  const one = space("s2", "solo", ["t3"]);
  const spaceRow = (s) => ({
    kind: "space",
    key: `s:${s.id}`,
    text: s.name,
    space: s,
  });

  assert.deepEqual(closePrompt(spaceRow(two), world({})), {
    text: "Close space dots (2 tabs)? y/n",
    action: {
      command: "space.close",
      args: {
        id: "s1",
        confirmed: true,
      },
    },
  });
  assert.equal(
    closePrompt(spaceRow(one), world({})).text,
    "Close space solo (1 tab)? y/n",
  );

  const rows = findRows(world({ terminals: [terminal("orphan", "idle")] }));
  assert.deepEqual(
    rows.slice(0, 2).map((r) => r.kind),
    ["machine", "elsewhere"],
  );
  assert.equal(closePrompt(rows[0], world({})), null);
  assert.equal(closePrompt(rows[1], world({})), null);

  const divider = findRows(world({ spaces: [one] })).find(
    (r) => r.kind === "tab",
  );
  assert.ok(divider);
  assert.equal(closePrompt(divider, world({})), null);
});

test("closePrompt offers nothing on the new-terminal and new-space rows", () => {
  const machines = [
    {
      name: "box",
      state: "connected",
    },
  ];
  for (const row of findRows(world({ machines }))) {
    assert.equal(closePrompt(row, world({})), null, row.key);
  }
});

test("interruptNotice shows nothing when the agent exited or stopped some other way", () => {
  const ok = (stdout) => ({
    code: 0,
    stdout,
    stderr: "",
  });
  assert.equal(interruptNotice("probe", ok('{"outcome":"exited"}')), null);
  assert.equal(interruptNotice("probe", ok('{"outcome":"idle"}')), null);
  assert.equal(interruptNotice("probe", ok("not json")), null);
  assert.equal(interruptNotice("probe", ok("null")), null);
});

test("interruptNotice tells the person when there is no sign it stopped", () => {
  assert.deepEqual(
    interruptNotice("probe", {
      code: 0,
      stdout: '{"outcome":"unknown"}',
      stderr: "",
    }),
    {
      level: "info",
      body: "probe: no sign it stopped",
    },
  );
});

test("interruptNotice reports a failed hc interrupt by stderr's first line or exit code", () => {
  assert.deepEqual(
    interruptNotice("probe", {
      code: 2,
      stdout: "",
      stderr: "\nno terminal named probe\nmore detail\n",
    }),
    {
      level: "error",
      body: "no terminal named probe",
    },
  );
  assert.deepEqual(
    interruptNotice("probe", {
      code: 2,
      stdout: "",
      stderr: " \n",
    }),
    {
      level: "error",
      body: "hc interrupt exited with 2",
    },
  );
});

// `finishedMs`, with `fields` overriding the defaults.
function finishedTerminal(address, parent, finishedMs, fields = {}) {
  return {
    address,
    parent,
    name: null,
    command: "make",
    cwd: "/home/me/src",
    exitCode: 0,
    signal: null,
    reason: "exited",
    finishedMs,
    ...fields,
  };
}

// `treeWorld` with finished terminals: "fk" (exit 0) under the sub-agent
// "k", and "f1" (exit 2, newer) and "f0" (exit 0) under the lead "A", which
// also started "k" and "sleep"; "fw" under the elsewhere "worker".
function finishedWorld(fields = {}) {
  return treeWorld({
    finished: [
      finishedTerminal("f1", "A", 20, {
        name: "build",
        exitCode: 2,
      }),
      finishedTerminal("fk", "k", 5),
      finishedTerminal("f0", "A", 10),
      finishedTerminal("fw", "worker", 1),
    ],
    ...fields,
  });
}

test("findRows lists a terminal's finished terminals after its nested rows, oldest first, one level deeper", () => {
  const rows = findRows(finishedWorld());
  const s1Rows = rows.slice(
    rows.findIndex((r) => r.key === "a:A"),
    rows.findIndex((r) => r.key === "a:t22"),
  );
  assert.deepEqual(
    s1Rows.map((r) => [r.key, r.depth]),
    [
      ["a:A", 0],
      ["a:k", 1],
      ["f:fk", 2],
      ["a:sleep", 1],
      ["f:f0", 1],
      ["f:f1", 1],
    ],
  );

  const f1 = rows.find((r) => r.key === "f:f1");
  assert.equal(f1.kind, "finished");
  assert.equal(f1.finished.address, "f1");
  assert.equal(f1.parent, "A");
  assert.equal(f1.parentLabel, rows.find((r) => r.key === "a:A").model.label);
  assert.equal(
    rows.find((r) => r.key === "f:fk").parentLabel,
    rows.find((r) => r.key === "a:k").model.label,
  );
  assert.equal(f1.parentTab, "t1");
  assert.equal(f1.space.id, "s1");
  assert.equal(f1.machine, null);
  assert.equal(f1.folded, false);
  // A paneless parent has no tab, so Enter peeks at it.
  assert.equal(rows.find((r) => r.key === "f:fk").parentTab, null);

  const fw = rows.find((r) => r.key === "f:fw");
  assert.equal(fw.space, null);
  assert.equal(fw.depth, 1);
  assert.equal(rows[rows.indexOf(fw) - 1].key, "a:worker");
});

test("a finished row's text holds its label, how it ended, the word finished, its space and its machine", () => {
  const rows = findRows(finishedWorld());
  assert.equal(
    rows.find((r) => r.key === "f:f1").text,
    "build  exit 2  finished  neom8",
  );
  assert.equal(
    rows.find((r) => r.key === "f:fw").text,
    "make  exit 0  finished  elsewhere",
  );

  const remote = findRows(
    world({
      terminals: [terminal("box/t1", null)],
      finished: [finishedTerminal("box/t9", "box/t1", 1, { reason: "killed" })],
    }),
  );
  assert.equal(
    remote.find((r) => r.key === "f:box/t9").text,
    "make  killed  finished  elsewhere  box",
  );
});

test("finished rows are selectable and filterable, one line tall, and offer Enter to their parent and ctrl-x to remove", () => {
  const rows = findRows(finishedWorld());
  const finishedRows = rows.filter((r) => r.kind === "finished");
  assert.equal(finishedRows.length, 4);
  for (const r of finishedRows) {
    assert.ok(isSelectable(r), r.key);
    assert.equal(rowHeight(r), ROW_H, r.key);
  }
  assert.deepEqual(
    filterableRows(rows)
      .filter((r) => r.kind === "finished")
      .map((r) => r.key),
    finishedRows.map((r) => r.key),
  );
  assert.deepEqual(footerHints(finishedRows[0], false, false).slice(0, 3), [
    {
      keys: "enter",
      label: "go to parent",
    },
    {
      keys: "ctrl-x",
      label: "remove",
    },
    {
      keys: "ctrl-n",
      label: "needs you",
      isOn: false,
    },
  ]);
});

test("needsYouRows keeps the finished rows that failed, not the ones that exited 0", () => {
  const rows = findRows(
    finishedWorld({
      finished: [
        finishedTerminal("ok", "A", 1),
        finishedTerminal("bad", "A", 2, { exitCode: 1 }),
        finishedTerminal("gone", "A", 3, {
          exitCode: null,
          reason: "killed",
        }),
      ],
    }),
  );
  assert.deepEqual(
    needsYouRows(rows).map((r) => r.key),
    ["f:bad", "f:gone"],
  );
});

test("a folded tab hides its finished rows with its terminals, and a failed one keeps the tab open", () => {
  // t1 is settled with its agent and finished helper quiet, so it folds;
  // t2 is settled but its helper failed, so it stays open.
  const s1 = space("s1", "one", ["t1", "t2"]);
  s1.tabs[0].settled = true;
  s1.tabs[1].settled = true;
  const rows = findRows(
    world({
      terminals: [terminal("A", "idle"), terminal("B", "idle")],
      agents: [
        agent("A", "idle", { tab: "t1" }),
        agent("B", "idle", { tab: "t2" }),
      ],
      panes: [pane("A", "t1"), pane("B", "t2")],
      spaces: [s1],
      finished: [
        finishedTerminal("fa", "A", 1),
        finishedTerminal("fb", "B", 1, { exitCode: 1 }),
      ],
    }),
  );

  assert.deepEqual(
    rows
      .filter((r) => r.kind === "terminal" || r.kind === "finished")
      .map((r) => [r.key, r.folded]),
    [
      ["a:A", true],
      ["f:fa", true],
      ["a:B", false],
      ["f:fb", false],
    ],
  );
  assert.deepEqual(
    unfoldedRows(rows).map((r) => r.key),
    ["m:", "s:s1", "t:t1", "t:t2", "a:B", "f:fb", "new:terminal", "new:space:"],
  );
  // A query still reaches the folded one.
  assert.ok(filterableRows(rows).some((r) => r.key === "f:fa"));
});

test("finishedPreviewHeader says how and when a finished terminal ended and where it ran", () => {
  assert.equal(
    finishedPreviewHeader(
      finishedTerminal("t9", "A", 1, { exitCode: 1 }),
      "3m",
      "/home/me",
    ),
    "✗ exit 1 · 3m ago · ~/src",
  );
  assert.equal(
    finishedPreviewHeader(finishedTerminal("t9", "A", 1), null, "/home/me"),
    "✓ exit 0 · ~/src",
  );
  // A remote folder keeps its full path, and an empty one is left out.
  assert.equal(
    finishedPreviewHeader(
      finishedTerminal("box/t9", "box/t1", 1, { cwd: "/home/me/x" }),
      "<1m",
      "/home/me",
    ),
    "✓ exit 0 · <1m ago · /home/me/x",
  );
  assert.equal(
    finishedPreviewHeader(
      finishedTerminal("t9", "A", 1, {
        cwd: "",
        exitCode: null,
        reason: "killed",
      }),
      null,
      "/home/me",
    ),
    "✗ killed",
  );
});

test("closePrompt asks to remove a finished row with hc rm, and promptHints names the verb", () => {
  const w = finishedWorld();
  const rows = findRows(w);
  const prompt = closePrompt(
    rows.find((r) => r.key === "f:f1"),
    w,
  );
  assert.deepEqual(prompt, {
    text: "Remove build (exit 2)? y/n",
    action: {
      command: "hc rm",
      args: { terminal: "f1" },
    },
  });
  assert.equal(
    closePrompt(
      rows.find((r) => r.key === "f:fk"),
      w,
    ).text,
    "Remove make (exit 0)? y/n",
  );
  assert.deepEqual(promptHints(prompt.action), [
    {
      keys: "y",
      label: "remove",
    },
    {
      keys: "any other key",
      label: "cancel",
    },
  ]);
});
