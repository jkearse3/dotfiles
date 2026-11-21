// Tests the mod-lib pure files the desk-spaces sidebar draws its tree with:
// `buildTree`, `spaceTerminals`, `tabFolded`, `rowStatus` and `walkTree` from
// `tree.ts`, `agentDoing`, `folderOf` and `terminalRowModel` from `labels.ts`,
// `machineOf` from `terminals.ts`, `spaceOrder`, `checkoutText` and
// `readSpaceCheckouts` from `space-order.ts`, the finished-terminal readers,
// outcome and label from `finished.ts`, `quietFor` from `quiet.ts`,
// `runningCommand`, `shellCommandText`, `commandText` and `CommandStarts`
// from `foreground.ts`, `hoverFill` and `stripeColor` from `row-colors.ts`,
// `innermostRoot` from `checkout-root.ts`, `spaceCheckoutBadgeKind` and
// `terminalCheckoutBadgeKind` from `checkout-badge.ts`, and the desk-spaces sidebar's status and activity tracking (`AgentHistory`
// from its own `agents.ts`), the trackers over an in-memory `localStorage`,
// against the terminals(), agents(), panes() and spaces() entry shapes the
// Herdr app hands mods. It imports the built, type-stripped
// `desk-spaces/*.js` from the herdr-app-mods output named by
// `HERDR_APP_MODS`, where the mod's links to `mod-lib` have been copied in.
// Run with
// `HERDR_APP_MODS=$(nix build --no-link --print-out-paths .#herdr-app-mods) node --test`;
// flake/checks.nix registers it as the `herdr-app-mod-lib` check through
// mod-lib-check.nix, which sets it.
import assert from "node:assert/strict";
import { test } from "node:test";

const mods = process.env.HERDR_APP_MODS;
if (!mods) {
  throw new Error(
    "HERDR_APP_MODS is unset: set it to the herdr-app-mods build output",
  );
}
const { agentDoing, folderOf, terminalRowModel } = await import(
  `${mods}/desk-spaces/labels.js`
);
const { machineOf } = await import(`${mods}/desk-spaces/terminals.js`);
const { checkoutText, readSpaceCheckouts, spaceOrder } = await import(
  `${mods}/desk-spaces/space-order.js`
);
const { buildTree, rowStatus, spaceTerminals, tabFolded, walkTree } =
  await import(`${mods}/desk-spaces/tree.js`);
const {
  finishedAddresses,
  finishedLabel,
  finishedOutcome,
  finishedTerminalOf,
  readFinishedTerminals,
} = await import(`${mods}/desk-spaces/finished.js`);
const { QUIET_MS, quietFor } = await import(`${mods}/desk-spaces/quiet.js`);
const { hoverFill, stripeColor } = await import(
  `${mods}/desk-spaces/row-colors.js`
);
const { AgentHistory } = await import(`${mods}/desk-spaces/agents.js`);
const { innermostRoot } = await import(`${mods}/desk-spaces/checkout-root.js`);
const { spaceCheckoutBadgeKind, terminalCheckoutBadgeKind } = await import(
  `${mods}/desk-spaces/checkout-badge.js`
);
const {
  COMMAND_SETTLE_MS,
  CommandStarts,
  commandText,
  runningCommand,
  shellCommandText,
} = await import(`${mods}/desk-spaces/foreground.js`);

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

test("machineOf: the part before the first slash, else null", () => {
  assert.equal(machineOf("box/w1:t1"), "box");
  assert.equal(machineOf("w1:t1"), null);
});

// A plain fish shell's terminals() entry at `address` in folder `cwd`.
const fish = (address, cwd, fields = {}) =>
  terminal(address, null, {
    program: {
      name: "fish",
      key: "shell",
    },
    cwd,
    ...fields,
  });

test("agentDoing says a blocked agent's kind, else the activity, else the status word", () => {
  const doing = (fields) =>
    agentDoing({
      status: "working",
      reportKind: null,
      activity: null,
      ...fields,
    });

  assert.deepEqual(
    doing({
      status: "blocked",
      reportKind: "permission",
      activity: "Reading the docs",
    }),
    {
      kind: "blocked",
      text: "permission",
    },
  );
  assert.deepEqual(
    doing({
      status: "blocked",
      activity: "Reading the docs",
    }),
    {
      kind: "activity",
      text: "Reading the docs",
    },
  );
  for (const status of ["working", "idle", "done"])
    assert.deepEqual(
      doing({
        status,
        reportKind: "question",
        activity: "Reading the docs",
      }),
      {
        kind: "activity",
        text: "Reading the docs",
      },
      status,
    );
  for (const status of ["working", "blocked", "idle", "done"])
    assert.deepEqual(
      doing({ status }),
      {
        kind: "status",
        text: status,
      },
      status,
    );
});

// The row model of the live terminal at `address` in `w`'s tree, with
// /home/me as this computer's home and `command` as the command it runs.
const rowModelOf = (w, address, command) => {
  const tree = buildTree(w);
  const nodes = [
    ...tree.machines
      .flatMap((m) => m.spaces)
      .flatMap((s) => [...walkTree(spaceTerminals(s))]),
    ...tree.machines.flatMap((m) => [...walkTree(m.elsewhere)]),
  ].map((step) => step.node);
  return terminalRowModel(
    nodes.find((n) => n.terminal.address === address),
    "/home/me",
    command,
  );
};

test("terminalRowModel: an agent's label, program name, title, status, folder and detail; a plain terminal's label, title and folder", () => {
  const w = treeInput({
    terminals: [
      terminal("asking", "blocked", {
        name: "fixer",
        cwd: "/home/me/dots",
        report: {
          state: "blocked",
          msg: "Reading the docs",
          kind: "permission",
        },
        turn: 2,
      }),
      terminal("reading", "working", {
        cwd: "/home/me/dots",
        foreground: {
          pid: 12,
          name: "claude",
          argv: ["claude"],
          cwd: "/home/me/dots/src",
        },
        report: {
          state: "working",
          msg: "✳ Reading the docs",
          kind: "question",
        },
        turn: 3,
      }),
      // Paneless, so no agents() entry: no activity, though it has turns.
      terminal("kid", "working", {
        parent: "reading",
        report: {
          state: "working",
          msg: "Reading",
        },
        turn: 1,
      }),
      terminal("resting", "idle", {
        cwd: "/home/me/r",
        turn: 4,
      }),
      terminal("finished", "done", {
        cwd: "/home/me/f",
        turn: 5,
      }),
      fish("named", "/home/me/x", { name: "server" }),
      fish("unnamed", "/home/me/y"),
      fish("self-named", "/home/me/z", { name: " Fish " }),
      terminal("nameless", null, { cwd: "/home/me/w" }),
    ],
    agents: [
      agent("asking", "blocked"),
      agent("reading", "working"),
      agent("resting", "idle"),
      agent("finished", "done"),
    ],
    panes: [
      pane("asking", "t1"),
      pane("reading", "t1"),
      pane("resting", "t1"),
      pane("finished", "t1"),
      pane("named", "t1"),
      pane("unnamed", "t1"),
      pane("self-named", "t1"),
      pane("nameless", "t1"),
    ],
    spaces: [space("s1", "dots", ["t1"])],
  });

  assert.deepEqual(rowModelOf(w, "asking"), {
    address: "asking",
    label: "claude  fixer",
    program: {
      name: "Claude Code",
      key: "claude",
    },
    programName: "claude",
    title: "fixer",
    status: "blocked",
    folder: "~/dots",
    detail: {
      kind: "blocked",
      text: "permission",
    },
  });

  // The folder is the terminal's current one, its foreground's, not the
  // one it started in.
  const reading = rowModelOf(w, "reading");
  assert.equal(reading.status, "working");
  assert.equal(reading.folder, "~/dots/src");
  assert.deepEqual(reading.detail, {
    kind: "activity",
    text: "Reading the docs",
  });

  // A turn count never fills in for what an agent is doing.
  const kid = rowModelOf(w, "kid");
  assert.deepEqual(kid.detail, {
    kind: "status",
    text: "working",
  });
  assert.equal(kid.folder, null);
  assert.deepEqual(rowModelOf(w, "resting").detail, {
    kind: "status",
    text: "idle",
  });
  assert.deepEqual(rowModelOf(w, "finished").detail, {
    kind: "status",
    text: "done",
  });

  assert.deepEqual(rowModelOf(w, "named"), {
    address: "named",
    label: "fish  server",
    program: {
      name: "fish",
      key: "shell",
    },
    programName: "fish",
    title: "server",
    status: null,
    folder: "~/x",
    detail: null,
  });
  const unnamed = rowModelOf(w, "unnamed");
  assert.equal(unnamed.label, "fish  ~/y");
  assert.equal(unnamed.programName, "fish");
  assert.equal(unnamed.title, null);
  assert.equal(unnamed.folder, "~/y");
  assert.equal(unnamed.detail, null);

  // A name that only names the program leaves no title.
  const selfNamed = rowModelOf(w, "self-named");
  assert.equal(selfNamed.label, "fish");
  assert.equal(selfNamed.title, null);
  assert.equal(selfNamed.folder, "~/z");

  // Without a program, the address titles an unnamed terminal.
  const nameless = rowModelOf(w, "nameless");
  assert.equal(nameless.label, "nameless  ~/w");
  assert.equal(nameless.programName, null);
  assert.equal(nameless.title, "nameless");
});

test("terminalRowModel: a plain terminal's command is its detail; an agent ignores it", () => {
  const w = treeInput({
    terminals: [
      fish("plain", "/home/me/x"),
      terminal("agent", "working", { cwd: "/home/me/a" }),
    ],
    agents: [agent("agent", "working")],
    panes: [pane("plain", "t1"), pane("agent", "t1")],
    spaces: [space("s1", "dots", ["t1"])],
  });
  const command = {
    text: "make dev",
    since: 1000,
  };

  assert.deepEqual(rowModelOf(w, "plain", command).detail, {
    kind: "command",
    text: "make dev",
    since: 1000,
  });
  assert.deepEqual(
    rowModelOf(w, "plain", {
      text: "make dev",
      since: null,
    }).detail,
    {
      kind: "command",
      text: "make dev",
      since: null,
    },
  );
  assert.equal(rowModelOf(w, "plain", null).detail, null);
  assert.equal(rowModelOf(w, "plain").detail, null);
  assert.deepEqual(rowModelOf(w, "agent", command).detail, {
    kind: "status",
    text: "working",
  });
});

test("folderOf: the foreground's folder, else the one it started in, ~ at home on this computer only", () => {
  const foreground = (cwd) => ({
    pid: 7,
    name: "make",
    argv: ["make", "dev"],
    cwd,
  });

  assert.equal(
    folderOf(
      fish("t1", "/home/me/a", { foreground: foreground("/home/me/b") }),
      "/home/me",
    ),
    "~/b",
  );
  // A foreground without a folder falls back to the start folder.
  assert.equal(
    folderOf(
      fish("t1", "/home/me/a", { foreground: foreground(null) }),
      "/home/me",
    ),
    "~/a",
  );
  assert.equal(
    folderOf(
      fish("t1", "/home/me/a", { foreground: foreground("") }),
      "/home/me",
    ),
    "~/a",
  );
  assert.equal(
    folderOf(fish("t1", "/home/me/a", { foreground: null }), "/home/me"),
    "~/a",
  );
  assert.equal(
    folderOf(fish("t1", null, { foreground: foreground(null) }), "/home/me"),
    null,
  );
  // Another machine's folder keeps its home unabbreviated.
  assert.equal(
    folderOf(
      fish("box/t1", "/home/me/a", { foreground: foreground("/home/me/b") }),
      "/home/me",
    ),
    "/home/me/b",
  );
});

// A TreeWorld with `fields` overriding the empty defaults.
function treeInput(fields) {
  return {
    terminals: [],
    agents: [],
    panes: [],
    spaces: [],
    machines: [],
    finished: [],
    ...fields,
  };
}

// A FinishedTerminal at `address` started by `parent`, having exited 0 at
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

// `nodes` and their children, depth first, as addresses indented two spaces
// per level.
const outline = (nodes, depth = 0) =>
  nodes.flatMap((n) => [
    `${"  ".repeat(depth)}${n.terminal.address}`,
    ...outline(n.children, depth + 1),
  ]);

// The space `id` in `tree`.
const treeSpace = (tree, id) =>
  tree.machines.flatMap((m) => m.spaces).find((s) => s.space.id === id);

// The elsewhere terminals of machine `name` (null for this computer) in
// `tree`.
const elsewhereOf = (tree, name) =>
  tree.machines.find((m) => m.name === name).elsewhere;

// The outline of each tab of space `id` in `tree`, by tab id.
const tabOutlines = (tree, id) =>
  Object.fromEntries(
    treeSpace(tree, id).tabs.map((t) => [t.tab.id, outline(t.terminals)]),
  );

test("buildTree lists this computer first, then machines by name, skipping temporary ones", () => {
  const tree = buildTree(
    treeInput({
      spaces: [
        space("lab/s2", "lab two", ["lt1"], "lab"),
        space("s1", "one", ["t1"]),
        space("zed/s3", "zed three", ["zt1"], "zed"),
        space("lab/s4", "lab four", ["lt2"], "lab"),
      ],
      machines: [
        {
          name: "zed",
          state: "connected",
          since_ms: null,
        },
        {
          name: "box",
          state: "unreachable",
          since_ms: 5000,
        },
        {
          name: "tmp",
          state: "connected",
          temporary: true,
        },
      ],
    }),
  );
  assert.deepEqual(
    tree.machines.map((m) => [
      m.name,
      m.state,
      m.sinceMs,
      m.spaces.map((s) => s.space.id),
    ]),
    [
      [null, null, null, ["s1"]],
      ["box", "unreachable", 5000, []],
      // A machine only a space names has no state.
      ["lab", null, null, ["lab/s2", "lab/s4"]],
      ["zed", "connected", null, ["zed/s3"]],
    ],
  );
});

test("buildTree lists every tab in order and each terminal once, by its first pane", () => {
  const s1 = space("s1", "one", ["t1", "t2", "t3"]);
  s1.tabs[1].settled = true;
  const tree = buildTree(
    treeInput({
      terminals: [terminal("b", null), terminal("c", "idle")],
      agents: [agent("c", "idle")],
      panes: [
        pane("c", "t1"),
        pane(null, "t1"),
        pane("b", "t1"),
        pane("b", "t3"),
      ],
      spaces: [s1],
    }),
  );
  assert.deepEqual(tabOutlines(tree, "s1"), {
    t1: ["c", "b"],
    t2: [],
    t3: [],
  });
  assert.deepEqual(treeSpace(tree, "s1").loose, []);
  assert.deepEqual(
    tree.machines.map((m) => m.elsewhere),
    [[]],
  );
});

test("buildTree fills each terminal's agent entry, first pane, status and machine", () => {
  const p1 = pane("a", "t1");
  const tree = buildTree(
    treeInput({
      terminals: [
        terminal("a", "working"),
        terminal("k", "error", { parent: "a" }),
        terminal("d", "done", { parent: "a" }),
        terminal("sh", null, { parent: "a" }),
        terminal("box/r", "idle"),
      ],
      agents: [agent("a", "blocked")],
      panes: [p1, pane("sh", "t1")],
      spaces: [space("s1", "one", ["t1"])],
    }),
  );
  const [a] = treeSpace(tree, "s1").tabs[0].terminals;
  assert.equal(a.info.address, "a");
  assert.equal(a.pane, p1);
  // The agents() status wins over the terminals() word.
  assert.equal(a.status, "blocked");
  assert.equal(a.machine, null);
  assert.deepEqual(a.finished, []);
  assert.deepEqual(
    a.children.map((c) => [c.terminal.address, c.status, c.info, c.finished]),
    [
      // A paneless sub-agent's error counts as blocked, its done as idle.
      ["k", "blocked", null, []],
      ["d", "idle", null, []],
      // A terminal reporting no status has none.
      ["sh", null, null, []],
    ],
  );
  const [r] = elsewhereOf(tree, "box");
  assert.equal(r.machine, "box");
  assert.equal(r.pane, null);
});

test("buildTree nests a terminal under its parent in the same space, even in another tab", () => {
  const tree = buildTree(
    treeInput({
      terminals: [
        terminal("a", "idle"),
        terminal("k2", "working", { parent: "a" }),
        terminal("k1", "idle", { parent: "a" }),
        terminal("g", "idle", { parent: "k1" }),
      ],
      panes: [
        pane("a", "t1"),
        pane("k1", "t2"),
        pane("k2", "t2"),
        pane("g", "t2"),
      ],
      spaces: [space("s1", "one", ["t1", "t2"])],
    }),
  );
  assert.deepEqual(tabOutlines(tree, "s1"), {
    // Children keep terminals() order, not panes() order.
    t1: ["a", "  k2", "  k1", "    g"],
    t2: [],
  });
});

test("buildTree leaves a terminal whose parent is in another space at the top of its own", () => {
  const tree = buildTree(
    treeInput({
      terminals: [
        terminal("a", "idle"),
        terminal("k", "idle", { parent: "a" }),
      ],
      panes: [pane("a", "t1"), pane("k", "t2")],
      spaces: [space("s1", "one", ["t1"]), space("s2", "two", ["t2"])],
    }),
  );
  assert.deepEqual(tabOutlines(tree, "s1"), { t1: ["a"] });
  assert.deepEqual(tabOutlines(tree, "s2"), { t2: ["k"] });
});

test("buildTree qualifies a remote child's bare parent with the child's machine", () => {
  const tree = buildTree(
    treeInput({
      terminals: [
        terminal("a1", "idle"),
        terminal("box/a1", "idle"),
        terminal("box/k1", "idle", { parent: "a1" }),
      ],
      panes: [pane("a1", "t1"), pane("box/a1", "bt1")],
      spaces: [
        space("s1", "one", ["t1"]),
        space("box/s1", "box one", ["bt1"], "box"),
      ],
    }),
  );
  assert.deepEqual(tabOutlines(tree, "s1"), { t1: ["a1"] });
  assert.deepEqual(tabOutlines(tree, "box/s1"), {
    bt1: ["box/a1", "  box/k1"],
  });
});

test("buildTree puts the first terminal of a parent cycle at the top level", () => {
  const tree = buildTree(
    treeInput({
      terminals: [
        terminal("x", "idle", { parent: "y" }),
        terminal("y", "idle", { parent: "x" }),
        terminal("z", "idle", { parent: "z" }),
      ],
      panes: [pane("y", "t1"), pane("z", "t1"), pane("x", "t1")],
      spaces: [space("s1", "one", ["t1"])],
    }),
  );
  assert.deepEqual(tabOutlines(tree, "s1"), { t1: ["z", "x", "  y"] });
});

test("buildTree finishes a parent chain longer than the ancestor walk", () => {
  const chain = Array.from({ length: 40 }, (_, i) =>
    terminal(`c${i}`, "idle", { parent: i === 0 ? null : `c${i - 1}` }),
  );
  const tree = buildTree(
    treeInput({
      terminals: chain,
      panes: [pane("c0", "t1")],
      spaces: [space("s1", "one", ["t1"])],
    }),
  );
  // The walk up from c33 and below stops 32 steps short of c0's pane, so
  // they belong to no space and start their own chain under elsewhere.
  const inSpace = outline(treeSpace(tree, "s1").tabs[0].terminals);
  assert.equal(inSpace.length, 33);
  assert.equal(inSpace[32], `${"  ".repeat(32)}c32`);
  const elsewhere = outline(elsewhereOf(tree, null));
  assert.deepEqual(elsewhere[0], "c33");
  assert.equal(elsewhere.at(-1), `${"  ".repeat(6)}c39`);
});

test("buildTree puts a paneless terminal its label or an ancestor's places in loose", () => {
  const tree = buildTree(
    treeInput({
      terminals: [
        terminal("bg", null, { labels: { "herdr.space": "s1" } }),
        terminal("box/bg", null, { labels: { "herdr.space": "s2" } }),
        terminal("p", "done", {
          state: "exited",
          labels: { "herdr.space": "s1" },
        }),
        terminal("k", "idle", { parent: "p" }),
        terminal("a", "idle", { labels: { "herdr.space": "s1" } }),
        terminal("ka", "idle", { parent: "a" }),
      ],
      spaces: [
        space("s1", "one", ["t1"]),
        space("box/s2", "box two", ["bt1"], "box"),
      ],
    }),
  );
  assert.deepEqual(outline(treeSpace(tree, "s1").loose), [
    "bg",
    // An ended parent's label places k, but k cannot nest under it.
    "k",
    "a",
    "  ka",
  ]);
  assert.deepEqual(outline(treeSpace(tree, "box/s2").loose), ["box/bg"]);
  assert.deepEqual(tabOutlines(tree, "s1"), { t1: [] });
});

test("buildTree lists live terminals no space holds under their machine's elsewhere and drops ended ones", () => {
  const tree = buildTree(
    treeInput({
      terminals: [
        terminal("e", "idle"),
        terminal("box/e", "idle"),
        terminal("gone", "idle", { state: "exited" }),
        terminal("ek", "idle", { parent: "e" }),
        terminal("box/ek", "idle", { parent: "e" }),
        terminal("orphan", null, { labels: { "herdr.space": "nope" } }),
        terminal("zed/e", "idle"),
        terminal("shown-gone", null, { state: "exited" }),
      ],
      panes: [pane("shown-gone", "t1")],
      spaces: [space("s1", "one", ["t1"])],
      machines: [
        {
          name: "zed",
          state: "connected",
        },
      ],
    }),
  );
  assert.deepEqual(
    tree.machines.map((m) => [m.name, m.state, outline(m.elsewhere)]),
    [
      [null, null, ["e", "  ek", "orphan"]],
      // A machine only an elsewhere terminal names gets an entry with no
      // state, in name order.
      ["box", null, ["box/e", "  box/ek"]],
      ["zed", "connected", ["zed/e"]],
    ],
  );
  assert.deepEqual(tabOutlines(tree, "s1"), { t1: [] });
});

test("spaceTerminals lists each tab's terminals in tab order, then the loose ones", () => {
  const tree = buildTree(
    treeInput({
      terminals: [
        terminal("bg", null, { labels: { "herdr.space": "s1" } }),
        terminal("b", "idle"),
        terminal("a", "idle"),
        terminal("k", "idle", { parent: "a" }),
      ],
      panes: [pane("b", "t2"), pane("a", "t1")],
      spaces: [space("s1", "one", ["t1", "t2"])],
    }),
  );
  assert.deepEqual(
    spaceTerminals(treeSpace(tree, "s1")).map((n) => n.terminal.address),
    ["a", "b", "bg"],
  );
});

// The one tab of space s1, settled when `settled`, in a tree where it holds
// idle agent "a" with agent "k", reporting `kidStatus`, nested under it.
function settledTab(settled, kidStatus) {
  const s1 = space("s1", "one", ["t1"]);
  s1.tabs[0].settled = settled;
  const tree = buildTree(
    treeInput({
      terminals: [
        terminal("a", "idle"),
        terminal("k", kidStatus, { parent: "a" }),
      ],
      agents: [agent("a", "idle"), agent("k", kidStatus)],
      panes: [pane("a", "t1"), pane("k", "t1")],
      spaces: [s1],
    }),
  );
  return treeSpace(tree, "s1").tabs[0];
}

test("tabFolded folds a settled tab whose terminals are all quiet", () => {
  assert.equal(tabFolded(settledTab(true, "idle")), true);
  assert.equal(tabFolded(settledTab(true, "working")), true);
});

test("tabFolded unfolds a settled tab with a blocked or done terminal at any depth", () => {
  assert.equal(tabFolded(settledTab(true, "blocked")), false);
  assert.equal(tabFolded(settledTab(true, "done")), false);
});

test("tabFolded never folds a tab that is not settled", () => {
  assert.equal(tabFolded(settledTab(false, "idle")), false);
});

test("rowStatus shows a done agent nested under an agent as idle, else its own status", () => {
  const tree = buildTree(
    treeInput({
      terminals: [
        terminal("a", "idle"),
        terminal("k", "done", { parent: "a" }),
        terminal("kw", "working", { parent: "a" }),
        terminal("sh", null),
        terminal("d", "done", { parent: "sh" }),
      ],
      agents: [
        agent("a", "idle"),
        agent("k", "done"),
        agent("kw", "working"),
        agent("d", "done"),
      ],
      panes: [
        pane("a", "t1"),
        pane("k", "t1"),
        pane("kw", "t1"),
        pane("sh", "t1"),
        pane("d", "t1"),
      ],
      spaces: [space("s1", "one", ["t1"])],
    }),
  );
  const [a, sh] = treeSpace(tree, "s1").tabs[0].terminals;
  const [k, kw] = a.children;
  const [d] = sh.children;
  assert.equal(rowStatus(a, null), "idle");
  assert.equal(rowStatus(k, a), "idle");
  assert.equal(rowStatus(kw, a), "working");
  // A plain shell reports no status, so its done sub-agent stays done.
  assert.equal(rowStatus(sh, null), null);
  assert.equal(rowStatus(d, sh), "done");
  // At the top level a done agent stays done.
  assert.equal(rowStatus(k, null), "done");
});

test("walkTree walks depth first with each row's depth", () => {
  const tree = buildTree(
    treeInput({
      terminals: [
        terminal("a", "idle"),
        terminal("k1", "idle", { parent: "a" }),
        terminal("g1", "idle", { parent: "k1" }),
        terminal("g2", "idle", { parent: "k1" }),
        terminal("k2", "idle", { parent: "a" }),
        terminal("g3", "idle", { parent: "k2" }),
        terminal("b", "idle"),
      ],
      panes: [pane("a", "t1"), pane("b", "t1")],
      spaces: [space("s1", "one", ["t1"])],
    }),
  );
  assert.deepEqual(
    [...walkTree(spaceTerminals(treeSpace(tree, "s1")))].map(
      ({ node, depth }) => [node.terminal.address, depth],
    ),
    [
      ["a", 0],
      ["k1", 1],
      ["g1", 2],
      ["g2", 2],
      ["k2", 1],
      ["g3", 2],
      ["b", 0],
    ],
  );
  assert.deepEqual([...walkTree([])], []);
});

// A checkout of repo `repo` named "dotfiles", linked unless `main`, with
// root folder `top`.
function spaceCheckout(repo, top, main = false) {
  return {
    name: "dotfiles",
    top,
    repo,
    linked: !main,
  };
}

// The space names of `spaceOrder(spaces, checkouts[name])`, each after its
// branch mark when it has one.
function orderedNames(names, checkouts) {
  return spaceOrder(names, (n) => checkouts[n] ?? null).map(
    ({ space, tree }) => (tree ? `${tree} ${space}` : space),
  );
}

test("spaceOrder moves linked spaces under their repo's first main space, the last marked └─", () => {
  assert.deepEqual(
    orderedNames(["ws1", "plain", "main", "ws2", "main2"], {
      ws1: spaceCheckout("r", "/d/ws1"),
      main: spaceCheckout("r", "/d", true),
      ws2: spaceCheckout("r", "/d/ws2"),
      main2: spaceCheckout("r", "/d", true),
    }),
    ["plain", "main", "├─ ws1", "└─ ws2", "main2"],
  );
});

test("spaceOrder keeps a linked space whose main checkout has no space in place", () => {
  assert.deepEqual(
    orderedNames(["a", "ws", "b"], {
      ws: spaceCheckout("r", "/d/ws"),
      b: spaceCheckout("other", "/o", true),
    }),
    ["a", "ws", "b"],
  );
  assert.deepEqual(orderedNames([], {}), []);
});

test("spaceOrder hands back each space's checkout", () => {
  const ws = spaceCheckout("r", "/d/ws");
  const main = spaceCheckout("r", "/d", true);
  assert.deepEqual(
    spaceOrder(["ws", "main"], (n) => ({ ws, main })[n]),
    [
      { space: "main", checkout: main, tree: null },
      { space: "ws", checkout: ws, tree: "└─" },
    ],
  );
});

test("checkoutText: repo / checkout folder, the repo alone when they match, ~ at home", () => {
  const here = { folder: "/h/x", machine: null };
  assert.equal(
    checkoutText(here, spaceCheckout("r", "/d/ws3"), "/h"),
    "dotfiles / ws3",
  );
  assert.equal(
    checkoutText(here, spaceCheckout("r", "/src/DotFiles/", true), "/h"),
    "dotfiles",
  );
  assert.equal(checkoutText(here, null, "/h"), "x");
  assert.equal(checkoutText({ folder: "/h", machine: null }, null, "/h"), "~");
  assert.equal(checkoutText({ folder: "", machine: "box" }, null, "/h"), "~");
  // Another machine's folder that equals this computer's home is named.
  assert.equal(checkoutText({ folder: "/h", machine: "box" }, null, "/h"), "h");
  assert.equal(checkoutText({ folder: "/", machine: null }, null, "/h"), null);
});

test("readSpaceCheckouts keeps checkouts and nulls, drops junk entries, rejects non-objects", () => {
  const c = spaceCheckout("r", "/d/ws");
  assert.deepEqual(
    readSpaceCheckouts({
      s1: { ...c, extra: 1 },
      s2: null,
      s3: { ...c, linked: "yes" },
      s4: "dotfiles",
      s5: { name: "x" },
    }),
    { s1: c, s2: null },
  );
  for (const junk of [undefined, null, "x", 3, [c]])
    assert.equal(readSpaceCheckouts(junk), null);
});

test("buildTree hangs finished terminals under their live parent, oldest first", () => {
  const tree = buildTree(
    treeInput({
      terminals: [
        terminal("a", "idle"),
        terminal("k", "idle", { parent: "a" }),
        terminal("gone", null, { state: "finished" }),
      ],
      panes: [pane("a", "t1")],
      spaces: [space("s1", "one", ["t1"])],
      finished: [
        finishedTerminal("f2", "a", 20),
        finishedTerminal("f1", "a", 10),
        finishedTerminal("fk", "k", 5),
        // Its parent has finished too, so it hangs nowhere.
        finishedTerminal("orphan", "gone", 1),
        finishedTerminal("unknown", "nobody", 2),
        finishedTerminal("top", null, 3),
      ],
    }),
  );
  const [a] = treeSpace(tree, "s1").tabs[0].terminals;
  assert.deepEqual(
    a.finished.map((f) => f.address),
    ["f1", "f2"],
  );
  assert.deepEqual(
    a.children[0].finished.map((f) => f.address),
    ["fk"],
  );
  assert.deepEqual(
    [...walkTree(spaceTerminals(treeSpace(tree, "s1")))].map((step) =>
      step.kind === "finished"
        ? step.finished.address
        : step.node.terminal.address,
    ),
    ["a", "k", "fk", "f1", "f2"],
  );
});

test("buildTree hangs a remote finished terminal under its remote parent", () => {
  const tree = buildTree(
    treeInput({
      terminals: [terminal("box/t1", "idle"), terminal("t1", "idle")],
      finished: [finishedTerminal("box/t9", "box/t1", 1)],
    }),
  );
  assert.deepEqual(
    elsewhereOf(tree, "box")[0].finished.map((f) => f.address),
    ["box/t9"],
  );
  assert.deepEqual(elsewhereOf(tree, null)[0].finished, []);
});

test("walkTree puts finished terminals after their parent's children", () => {
  const tree = buildTree(
    treeInput({
      terminals: [
        terminal("a", "idle"),
        terminal("k", "idle", { parent: "a" }),
        terminal("b", "idle"),
      ],
      panes: [pane("a", "t1"), pane("b", "t1")],
      spaces: [space("s1", "one", ["t1"])],
      finished: [
        finishedTerminal("g", "k", 1),
        finishedTerminal("f1", "a", 2),
        finishedTerminal("f2", "a", 3),
      ],
    }),
  );
  const steps = [...walkTree(spaceTerminals(treeSpace(tree, "s1")))];
  assert.deepEqual(
    steps.map((step) =>
      step.kind === "finished"
        ? [
            "finished",
            step.finished.address,
            step.parent.terminal.address,
            step.depth,
          ]
        : ["terminal", step.node.terminal.address, step.depth],
    ),
    [
      ["terminal", "a", 0],
      ["terminal", "k", 1],
      ["finished", "g", "k", 2],
      ["finished", "f1", "a", 1],
      ["finished", "f2", "a", 1],
      ["terminal", "b", 0],
    ],
  );
});

test("tabFolded unfolds a settled tab with a failed finished terminal at any depth", () => {
  // A settled tab whose idle agent "a" holds idle agent "k", which started
  // finished terminal "f" with `fields`.
  const tabWith = (fields) => {
    const s1 = space("s1", "one", ["t1"]);
    s1.tabs[0].settled = true;
    const tree = buildTree(
      treeInput({
        terminals: [
          terminal("a", "idle"),
          terminal("k", "idle", { parent: "a" }),
        ],
        agents: [agent("a", "idle"), agent("k", "idle")],
        panes: [pane("a", "t1")],
        spaces: [s1],
        finished: [finishedTerminal("f", "k", 1, fields)],
      }),
    );
    return treeSpace(tree, "s1").tabs[0];
  };
  assert.equal(tabFolded(tabWith({ exitCode: 0 })), true);
  assert.equal(tabFolded(tabWith({ exitCode: 2 })), false);
  assert.equal(
    tabFolded(tabWith({ exitCode: null, reason: "killed", signal: 9 })),
    false,
  );
});

test("finishedOutcome says how a finished terminal ended and whether it failed", () => {
  const outcome = (fields) =>
    finishedOutcome(finishedTerminal("f", null, 1, fields));
  assert.deepEqual(outcome({}), { failed: false, text: "exit 0" });
  assert.deepEqual(outcome({ exitCode: 2 }), { failed: true, text: "exit 2" });
  assert.deepEqual(
    outcome({ exitCode: null, signal: 15, reason: "signaled" }),
    { failed: true, text: "signal 15" },
  );
  // A kill says so rather than naming its signal.
  assert.deepEqual(outcome({ exitCode: null, signal: 9, reason: "killed" }), {
    failed: true,
    text: "killed",
  });
  for (const reason of [
    "holder_lost",
    "stopped_by_restart",
    "server_stop",
    "host_shutdown",
  ])
    assert.deepEqual(
      outcome({ exitCode: null, reason }),
      { failed: true, text: "lost" },
      reason,
    );
  assert.deepEqual(outcome({ exitCode: null, reason: null }), {
    failed: true,
    text: "ended",
  });
});

test("finishedLabel is the name, else the command, else the address", () => {
  assert.equal(
    finishedLabel(finishedTerminal("t9", null, 1, { name: "build" })),
    "build",
  );
  assert.equal(finishedLabel(finishedTerminal("t9", null, 1)), "make");
  assert.equal(
    finishedLabel(finishedTerminal("t9", null, 1, { command: null })),
    "t9",
  );
});

test("finishedAddresses lists the finished terminals of hc ls --all --json", () => {
  const stdout = JSON.stringify({
    hidden_finished: 0,
    terminals: [
      {
        address: "t1k",
        agent: "fish",
        cwd: "/home/me",
        state: "live",
        turn: 0,
        where: "dotfiles / 1",
      },
      {
        address: "t3a",
        agent: "make",
        cwd: "/home/me/src",
        name: "build",
        state: "finished",
        turn: 0,
      },
      {
        address: "t3b",
        agent: "sleep",
        cwd: "/home/me",
        state: "finished",
        turn: 0,
      },
    ],
  });
  assert.deepEqual(finishedAddresses(stdout), ["t3a", "t3b"]);
  assert.deepEqual(
    finishedAddresses(JSON.stringify({ hidden_finished: 0, terminals: [] })),
    [],
  );
  for (const junk of ["", "not json", "[]", "null", '{"terminals":3}'])
    assert.equal(finishedAddresses(junk), null, junk);
});

// The `hc get <address> --json` output of a finished `make` that exited
// with `fields` overriding the defaults.
function getOutput(fields = {}) {
  return JSON.stringify({
    address: "t3a",
    argv: ["/usr/bin/make", "-j4"],
    cols: 80,
    created_ms: 1794195337640,
    cwd: "/home/me/src",
    die_with_parent: false,
    exit_code: 2,
    finished_ms: 1794195399000,
    foreground: null,
    identity: "ghostty",
    keep: false,
    labels: {},
    name: null,
    notify: true,
    parent: "t29",
    pid: null,
    reason: "exited",
    reported: false,
    rm: false,
    rows: 24,
    screen: "exact",
    signal: null,
    state: "finished",
    status: null,
    status_ms: null,
    template: null,
    title: "",
    turn: 0,
    ...fields,
  });
}

test("finishedTerminalOf reads a finished terminal from hc get --json", () => {
  assert.deepEqual(finishedTerminalOf("t3a", getOutput()), {
    address: "t3a",
    parent: "t29",
    name: null,
    command: "make",
    cwd: "/home/me/src",
    exitCode: 2,
    signal: null,
    reason: "exited",
    finishedMs: 1794195399000,
  });
  // A remote terminal's bare parent is on its machine.
  const remote = finishedTerminalOf(
    "box/t3a",
    getOutput({ name: "build", exit_code: null, signal: 9, reason: "killed" }),
  );
  assert.equal(remote.address, "box/t3a");
  assert.equal(remote.parent, "box/t29");
  assert.equal(remote.name, "build");
  assert.equal(remote.signal, 9);
  assert.equal(remote.exitCode, null);
  assert.equal(
    finishedTerminalOf("t3a", getOutput({ parent: null, argv: [] })).parent,
    null,
  );
  assert.equal(
    finishedTerminalOf("t3a", getOutput({ argv: [] })).command,
    null,
  );
  assert.equal(
    finishedTerminalOf("t3a", getOutput({ state: "live", exit_code: null })),
    null,
  );
  for (const junk of ["", "not json", "[]", "null"])
    assert.equal(finishedTerminalOf("t3a", junk), null, junk);
});

test("readFinishedTerminals keeps the finished terminals of a shared value", () => {
  const f = finishedTerminal("t3a", "t29", 5, { extra: true });
  const { extra: _, ...clean } = f;
  assert.deepEqual(readFinishedTerminals([f, { address: "t1" }, null, 3]), [
    clean,
  ]);
  for (const junk of [undefined, null, "x", 3, { t3a: f }])
    assert.deepEqual(readFinishedTerminals(junk), []);
});

// Installs an in-memory `localStorage` holding `items` (key -> stored
// string), as the app gives each mod, and returns the map it writes to.
function useStorage(items = {}) {
  const store = new Map(Object.entries(items));
  Object.defineProperty(globalThis, "localStorage", {
    value: {
      getItem: (k) => store.get(k) ?? null,
      setItem: (k, v) => store.set(k, String(v)),
    },
    configurable: true,
    writable: true,
  });
  return store;
}

const MIN = 60000;

test("trackActivity stamps a new agent now and keeps the stamp while nothing changes", () => {
  useStorage();
  const h = new AgentHistory();
  const k = terminal("t1", "working", {
    turn: 3,
    report: { msg: "Read a.ts" },
  });
  h.trackActivity([k], 1000);
  assert.equal(h.activeAt("t1"), 1000);
  h.trackActivity([{ ...k, report: { msg: "Read a.ts" } }], 5000);
  assert.equal(h.activeAt("t1"), 1000);
  assert.equal(h.activeAt("t2"), null);
});

test("trackActivity restamps on a new report message, turn or state", () => {
  useStorage();
  const h = new AgentHistory();
  const k = terminal("t1", "working", {
    turn: 3,
    report: { msg: "Read a.ts" },
  });
  h.trackActivity([k], 1000);
  h.trackActivity([{ ...k, report: { msg: "Edit a.ts" } }], 2000);
  assert.equal(h.activeAt("t1"), 2000);
  h.trackActivity([{ ...k, report: { msg: "Edit a.ts" }, turn: 4 }], 3000);
  assert.equal(h.activeAt("t1"), 3000);
  const same = { ...k, report: { msg: "Edit a.ts" }, turn: 4 };
  h.trackActivity([{ ...same, status: "blocked" }], 4000);
  h.trackActivity([same], 5000);
  assert.equal(h.activeAt("t1"), 5000);
});

test("trackActivity restamps on a new core status time with the same state, message and turn", () => {
  useStorage();
  const h = new AgentHistory();
  // A working -> blocked -> working round trip the sidebar never sampled
  // leaves only a newer status_ms behind.
  const k = terminal("t1", "working", {
    status_ms: 500,
    turn: 3,
    report: { msg: "Read a.ts" },
  });
  h.trackActivity([k], 1000);
  h.trackActivity([{ ...k }], 2000);
  assert.equal(h.activeAt("t1"), 1000);
  h.trackActivity([{ ...k, status_ms: 1500 }], 3000);
  assert.equal(h.activeAt("t1"), 3000);
});

test("trackActivity restamps a stored record missing a field once", () => {
  useStorage({
    active: JSON.stringify({
      t1: { s: "working", m: null, n: 2, at: 700 },
    }),
  });
  const h = new AgentHistory();
  const k = terminal("t1", "working", { turn: 2 });
  h.trackActivity([k], 1000);
  assert.equal(h.activeAt("t1"), 1000);
  h.trackActivity([k], 2000);
  assert.equal(h.activeAt("t1"), 1000);
});

test("trackActivity counts done and idle as one state and skips terminals without a status", () => {
  useStorage();
  const h = new AgentHistory();
  h.trackActivity([terminal("t1", "done"), terminal("t2", null)], 1000);
  h.trackActivity([terminal("t1", "idle"), terminal("t2", "")], 2000);
  assert.equal(h.activeAt("t1"), 1000);
  assert.equal(h.activeAt("t2"), null);
});

test("AgentHistory keeps activity across restarts and reads storage from before it tracked any", () => {
  const store = useStorage({
    changed: JSON.stringify({ t1: { s: "working", at: 700 } }),
  });
  const before = new AgentHistory();
  assert.equal(before.since({ address: "t1" }), 700);
  assert.equal(before.activeAt("t1"), null);
  before.trackActivity([terminal("t1", "working", { turn: 2 })], 1000);
  assert.ok(store.has("active"));

  const after = new AgentHistory();
  assert.equal(after.activeAt("t1"), 1000);
  after.trackActivity([terminal("t1", "working", { turn: 2 })], 9000);
  assert.equal(after.activeAt("t1"), 1000);
});

test("trackActivity drops agents gone for over 30 days and keeps recently gone ones", () => {
  const day = 86400000;
  useStorage();
  const h = new AgentHistory();
  h.trackActivity([terminal("old", "idle"), terminal("recent", "idle")], 0);
  h.trackActivity([terminal("recent", "working")], 29 * day);
  h.trackActivity([terminal("new", "working")], 31 * day);
  assert.equal(h.activeAt("old"), null);
  assert.equal(h.activeAt("recent"), 29 * day);
  assert.equal(h.activeAt("new"), 31 * day);
});

test("track stamps a status change with the core's status time, not when the sidebar first sees it", () => {
  useStorage();
  const h = new AgentHistory();
  // The agent went idle at 2:00 while the app was closed; it opens at 3:00.
  h.track(
    [agent("t1", "idle")],
    [terminal("t1", "idle", { status_ms: 120 * MIN })],
    180 * MIN,
  );
  assert.equal(h.since({ address: "t1" }), 120 * MIN);
});

test("track stamps a status change now when the core reports no status time", () => {
  useStorage();
  const h = new AgentHistory();
  h.track([agent("t1", "working")], [terminal("t1", "working")], 1000);
  h.track(
    [agent("t2", "working")],
    [terminal("t2", "working", { status_ms: null })],
    2000,
  );
  assert.equal(h.since({ address: "t1" }), 1000);
  assert.equal(h.since({ address: "t2" }), 2000);
});

test("track keeps a finished agent's stamp when looking at it turns done into idle", () => {
  useStorage();
  const h = new AgentHistory();
  h.track(
    [agent("t1", "done")],
    [terminal("t1", "done", { status_ms: 500 })],
    1000,
  );
  h.track(
    [agent("t1", "idle")],
    [terminal("t1", "idle", { status_ms: 4000 })],
    5000,
  );
  assert.equal(h.since({ address: "t1" }), 500);
});

test("track restamps a real status change with the new core status time", () => {
  useStorage();
  const h = new AgentHistory();
  h.track(
    [agent("t1", "idle")],
    [terminal("t1", "idle", { status_ms: 500 })],
    1000,
  );
  h.track(
    [agent("t1", "working")],
    [terminal("t1", "working", { status_ms: 4000 })],
    5000,
  );
  assert.equal(h.since({ address: "t1" }), 4000);
});

test("quietFor: a working agent quiet for 10 minutes or more, else null", () => {
  assert.equal(QUIET_MS, 10 * MIN);
  assert.equal(quietFor("working", 0, 10 * MIN), 10 * MIN);
  assert.equal(quietFor("working", 0, 10 * MIN - 1000), null);
  assert.equal(quietFor("working", null, 60 * MIN), null);
  for (const status of ["idle", "blocked", "done", null])
    assert.equal(quietFor(status, 0, 60 * MIN), null, String(status));
});

// A plain terminals() entry at `address` whose root process is 100, running
// `argv` in process `pid` that the app's program marks `shell` or not.
function plainRunning(address, pid, argv, shell = false) {
  return terminal(address, null, {
    pid: 100,
    program: {
      key: shell ? "shell" : "program",
      name: argv[0] ?? "x",
      icon: null,
      tint: false,
      tile: null,
      color: null,
      shell,
      agent: false,
    },
    foreground: {
      pid,
      name: argv[0] ?? "x",
      argv,
      cwd: "/home/u/x",
    },
  });
}

test("runningCommand: null while the shell holds the foreground", () => {
  assert.equal(runningCommand(plainRunning("t1", 100, ["fish"], true)), null);
  // A shell started inside the shell counts as the shell.
  assert.equal(runningCommand(plainRunning("t1", 200, ["bash"], true)), null);
});

test("runningCommand: a command other than the shell, by its file name", () => {
  assert.deepEqual(runningCommand(plainRunning("t1", 200, ["make", "dev"])), {
    pid: 200,
    text: "make dev",
  });
  assert.deepEqual(
    runningCommand(
      plainRunning("t1", 200, [
        "/nix/store/abc-nix/bin/nix",
        "build",
        "--no-link",
        ".#lint",
      ]),
    ),
    {
      pid: 200,
      text: "nix build --no-link .#lint",
    },
  );
});

test("runningCommand: a shell running a script or a -c command is a command", () => {
  assert.deepEqual(
    runningCommand(plainRunning("t1", 200, ["bash", "./deploy.sh"], true)),
    {
      pid: 200,
      text: "deploy.sh",
    },
  );
  // A `#!/usr/bin/env bash` script in the terminal's root process.
  assert.deepEqual(
    runningCommand(
      plainRunning(
        "t1",
        100,
        ["/nix/store/abc-bash/bin/bash", "/Users/x/.nix-profile/bin/claude"],
        true,
      ),
    ),
    {
      pid: 100,
      text: "claude",
    },
  );
  assert.deepEqual(
    runningCommand(plainRunning("t1", 200, ["bash", "-c", "make dev"], true)),
    {
      pid: 200,
      text: "make dev",
    },
  );
});

test("runningCommand: an interactive shell with options is the shell", () => {
  for (const argv of [
    ["bash"],
    ["bash", "--rcfile", "/tmp/x"],
    ["bash", "-l"],
    ["-zsh"],
  ])
    assert.equal(
      runningCommand(plainRunning("t1", 200, argv, true)),
      null,
      argv.join(" "),
    );
});

test("shellCommandText: a script after options and their values, or the -c command", () => {
  assert.equal(
    shellCommandText(["bash", "./deploy.sh", "prod"]),
    "deploy.sh prod",
  );
  assert.equal(
    shellCommandText(["bash", "-e", "-o", "pipefail", "x.sh"]),
    "x.sh",
  );
  assert.equal(
    shellCommandText(["bash", "--rcfile", "/tmp/rc", "x.sh"]),
    "x.sh",
  );
  assert.equal(shellCommandText(["bash", "--", "-odd.sh"]), "-odd.sh");
  assert.equal(
    shellCommandText(["bash", "-lc", "make dev", "arg0"]),
    "make dev",
  );
  assert.equal(shellCommandText(["fish", "--command=make dev"]), "make dev");
  assert.equal(shellCommandText(["fish", "--command", "make dev"]), "make dev");
  assert.equal(shellCommandText(["fish", "-C", "source x"]), null);
  assert.equal(shellCommandText(["bash", "-c"]), null);
  assert.equal(shellCommandText(["bash", "--"]), null);
  assert.equal(shellCommandText([]), null);
});

test("runningCommand: null without a foreground or a numeric foreground pid", () => {
  const t = plainRunning("t1", 200, ["make"]);
  assert.equal(runningCommand({ ...t, foreground: undefined }), null);
  assert.equal(runningCommand({ ...t, foreground: null }), null);
  assert.equal(
    runningCommand({ ...t, foreground: { ...t.foreground, pid: "200" } }),
    null,
  );
});

test("runningCommand: without a program, the root process is the shell", () => {
  const t = plainRunning("t1", 100, ["fish"]);
  assert.equal(runningCommand({ ...t, program: undefined }), null);
  const make = plainRunning("t1", 200, ["make"]);
  assert.deepEqual(runningCommand({ ...make, program: undefined }), {
    pid: 200,
    text: "make",
  });
});

test("commandText: the process name when there are no arguments", () => {
  assert.equal(
    commandText({
      pid: 1,
      name: "htop",
      argv: [],
    }),
    "htop",
  );
});

test("CommandStarts shows a command once it has run COMMAND_SETTLE_MS, since it was first seen", () => {
  useStorage();
  const c = new CommandStarts();
  const make = plainRunning("t1", 200, ["make", "dev"]);
  assert.equal(COMMAND_SETTLE_MS, 2000);
  c.track([make], 1000);
  c.track([make], 2999);
  assert.equal(c.shown(make, 2999), null);
  c.track([make], 3000);
  assert.deepEqual(c.shown(make, 3000), {
    text: "make dev",
    since: 1000,
  });
});

test("CommandStarts keeps the stamp for the same process and restamps a new one", () => {
  useStorage();
  const c = new CommandStarts();
  c.track([plainRunning("t1", 200, ["make"])], 1000);
  c.track([plainRunning("t1", 200, ["make"])], 5000);
  assert.equal(c.shown(plainRunning("t1", 200, ["make"]), 5000).since, 1000);
  const next = plainRunning("t1", 300, ["make"]);
  c.track([next], 6000);
  assert.equal(c.shown(next, 7999), null);
  assert.equal(c.shown(next, 8000).since, 6000);
});

test("CommandStarts drops a command back at the shell and reports the change", () => {
  useStorage();
  const c = new CommandStarts();
  const make = plainRunning("t1", 200, ["make"]);
  c.track([make], 0);
  assert.equal(c.track([make], 3000), true);
  assert.equal(c.track([plainRunning("t1", 100, ["fish"], true)], 4000), true);
  // The same process again counts from when it is seen again.
  c.track([make], 5000);
  assert.equal(c.shown(make, 6000), null);
});

test("CommandStarts track reports crossing the settle time once and nothing on no change", () => {
  useStorage();
  const c = new CommandStarts();
  const make = plainRunning("t1", 200, ["make"]);
  assert.equal(c.track([], 0), false);
  assert.equal(c.track([make], 0), true);
  assert.equal(c.track([make], 1000), false);
  assert.equal(c.track([make], 2000), true);
  assert.equal(c.track([make], 2250), false);
  assert.equal(c.track([make], 9000), false);
});

test("CommandStarts keeps stamps across restarts", () => {
  const store = useStorage();
  const make = plainRunning("t1", 200, ["make"]);
  new CommandStarts().track([make], 1000);
  assert.ok(store.has("commands"));

  const after = new CommandStarts();
  after.track([make], 9000);
  assert.equal(after.shown(make, 9000).since, 1000);
});

test("CommandStarts drops terminals gone for over 30 days and keeps recently gone ones", () => {
  const day = 86400000;
  const store = useStorage();
  const c = new CommandStarts();
  c.track(
    [plainRunning("old", 200, ["make"]), plainRunning("recent", 300, ["make"])],
    0,
  );
  c.track([plainRunning("recent", 301, ["make"])], 29 * day);
  assert.ok("old" in JSON.parse(store.get("commands")));
  c.track([plainRunning("new", 400, ["make"])], 31 * day);
  assert.deepEqual(Object.keys(JSON.parse(store.get("commands"))).sort(), [
    "new",
    "recent",
  ]);
});

test("CommandStarts skips agents", () => {
  useStorage();
  const c = new CommandStarts();
  const t = { ...plainRunning("t1", 200, ["claude"]), status: "working" };
  assert.equal(c.track([t], 0), false);
  assert.equal(c.shown(t, 5000), null);
});

test("hoverFill mixes the backdrop halfway toward the theme's hover color", () => {
  assert.equal(hoverFill({ hover: "#ffffff" }, "#000000"), "#808080ff");
  assert.equal(hoverFill({ hover: "#204060" }, "#fff"), "#90a0b0ff");
});

test("hoverFill falls back to the hover color when either color isn't hex", () => {
  assert.equal(hoverFill({ hover: "#ffffff" }, "transparent"), "#ffffff");
  assert.equal(hoverFill({ hover: "rgb(1, 2, 3)" }, "#000000"), "rgb(1, 2, 3)");
});

test("hoverFill mixes a #rrggbbaa color's alpha like its other channels", () => {
  assert.equal(hoverFill({ hover: "#ffffff00" }, "#00000080"), "#80808040");
});

// A theme whose every stripe color is distinct, so each assertion tells
// which color a row got.
const stripeTheme = {
  working: "#000001",
  blocked: "#000002",
  done: "#000003",
  idle: "#000004",
  dim: "#000005",
  ansi6: "#000006",
};

test("stripeColor colors an agent row by its status", () => {
  const agent = (status, detail) =>
    stripeColor(stripeTheme, { status, detail });
  assert.equal(
    agent("working", { kind: "activity", text: "Reading" }),
    "#000001",
  );
  // A quiet working agent is still working.
  assert.equal(
    agent("working", { kind: "status", text: "working" }),
    "#000001",
  );
  assert.equal(
    agent("blocked", { kind: "blocked", text: "permission" }),
    "#000002",
  );
  assert.equal(agent("done", { kind: "status", text: "done" }), "#000003");
  assert.equal(agent("idle", { kind: "status", text: "idle" }), "#000004");
  assert.equal(
    agent("running", { kind: "status", text: "running" }),
    "#000004",
  );
});

test("stripeColor colors a plain row cyan only while it runs a command", () => {
  assert.equal(
    stripeColor(stripeTheme, { status: null, detail: null }),
    "#000004",
  );
  const command = { kind: "command", text: "make dev", since: null };
  assert.equal(
    stripeColor(stripeTheme, { status: null, detail: command }),
    "#000006",
  );
});

test("stripeColor falls back to dim for a theme without idle or done", () => {
  const { idle, done, ...theme } = stripeTheme;
  assert.equal(stripeColor(theme, { status: "idle", detail: null }), "#000005");
  assert.equal(stripeColor(theme, { status: "done", detail: null }), "#000005");
  assert.equal(stripeColor(theme, { status: null, detail: null }), "#000005");
});

test("innermostRoot picks jj for a colocated repo, where both roots match", () => {
  assert.deepEqual(innermostRoot("/r", "/r"), { top: "/r", kind: "jj" });
});

test("innermostRoot picks the longer root, a checkout nested in another", () => {
  assert.deepEqual(innermostRoot("/r", "/r/sub"), {
    top: "/r/sub",
    kind: "git",
  });
  assert.deepEqual(innermostRoot("/r/ws", "/r"), { top: "/r/ws", kind: "jj" });
});

test("innermostRoot takes the one root found, or null for none", () => {
  assert.deepEqual(innermostRoot("/r", null), { top: "/r", kind: "jj" });
  assert.deepEqual(innermostRoot(null, "/r"), { top: "/r", kind: "git" });
  assert.equal(innermostRoot(null, null), null);
  assert.equal(innermostRoot("", ""), null);
});

// A jj checkout's badge fields with @ on its bookmark and nothing in it,
// with `fields` laid over them.
const jjBadge = (fields) => ({
  jj: true,
  conflict: false,
  modified: false,
  direction: "↑",
  distance: 0,
  ...fields,
});

test("terminalCheckoutBadgeKind marks a conflict on every row", () => {
  const g = jjBadge({ conflict: true, modified: true, distance: 3 });
  assert.equal(terminalCheckoutBadgeKind("working", g), "conflict");
  assert.equal(terminalCheckoutBadgeKind("blocked", g), "conflict");
  assert.equal(terminalCheckoutBadgeKind(null, g), "conflict");
});

test("terminalCheckoutBadgeKind leaves review off a working or blocked agent and a plain terminal", () => {
  const g = jjBadge({ modified: true });
  assert.equal(terminalCheckoutBadgeKind("blocked", g), null);
  assert.equal(terminalCheckoutBadgeKind("working", g), null);
  assert.equal(terminalCheckoutBadgeKind(null, g), null);
  assert.equal(terminalCheckoutBadgeKind(null, { ahead: 2 }), null);
});

test("terminalCheckoutBadgeKind marks unshipped jj work on an agent with nothing to do", () => {
  assert.equal(
    terminalCheckoutBadgeKind("idle", jjBadge({ modified: true })),
    "review",
  );
  assert.equal(
    terminalCheckoutBadgeKind("done", jjBadge({ distance: 2 })),
    "review",
  );
  assert.equal(
    terminalCheckoutBadgeKind("idle", jjBadge({ distance: 2 })),
    "review",
  );
});

test("terminalCheckoutBadgeKind counts @ itself in the jj distance, and only after the bookmark", () => {
  assert.equal(
    terminalCheckoutBadgeKind("idle", jjBadge({ distance: 1 })),
    null,
  );
  assert.equal(
    terminalCheckoutBadgeKind("idle", jjBadge({ direction: "↓", distance: 3 })),
    null,
  );
  assert.equal(terminalCheckoutBadgeKind("idle", jjBadge({})), null);
});

test("terminalCheckoutBadgeKind marks Git commits ahead on an agent with nothing to do", () => {
  assert.equal(terminalCheckoutBadgeKind("idle", { ahead: 1 }), "review");
  assert.equal(
    terminalCheckoutBadgeKind("idle", { jj: false, ahead: 0 }),
    null,
  );
});

test("spaceCheckoutBadgeKind badges only a space whose agents are all quiet", () => {
  const conflict = jjBadge({ conflict: true });
  assert.equal(spaceCheckoutBadgeKind(["idle", "done"], conflict), "conflict");
  assert.equal(spaceCheckoutBadgeKind(["idle", "working"], conflict), null);
  assert.equal(spaceCheckoutBadgeKind(["blocked"], conflict), null);
  assert.equal(spaceCheckoutBadgeKind([], conflict), null);
  assert.equal(spaceCheckoutBadgeKind(["idle"], { ahead: 1 }), "review");
  assert.equal(spaceCheckoutBadgeKind(["idle"], { ahead: 0 }), null);
  assert.equal(spaceCheckoutBadgeKind(["idle"], null), null);
});
