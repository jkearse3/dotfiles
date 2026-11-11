// Tests `agentName` and `agentActivity` from mod-lib/names.ts against the
// agents() and terminals() entry shapes the Herdr app hands mods. Run with
// `node --test`; flake/checks.nix registers it as the `herdr-app-names` check
// through names-check.nix.
import assert from "node:assert/strict";
import { test } from "node:test";

import { agentActivity, agentName } from "./mod-lib/names.ts";

// An agents() entry running `app`, with `fields` overriding the defaults.
function agent(app, fields = {}) {
  return {
    app,
    title: "",
    tab_name: "",
    program: {
      name: app,
      key: app,
    },
    address: "w1:t1:p1",
    ...fields,
  };
}

// A terminals() entry whose agent reports `state` with message `msg`.
function reporting(state, msg) {
  return {
    report: {
      app: "x",
      state,
      msg,
    },
  };
}

test("Claude Code: its topic title without leading decoration", () => {
  const a = agent("claude-code", { title: "✳ Fix the sidebar" });
  assert.equal(agentName(a, undefined), "Fix the sidebar");
});

test("Claude Code: a title equal to its program falls back to the program", () => {
  const a = agent("claude-code", { title: "claude-code" });
  assert.equal(agentName(a, undefined), "claude-code");
});

test("a user-set terminal name wins over topic and title", () => {
  const a = agent("claude-code", { title: "✳ Fix the sidebar" });
  const k = {
    name: "reviewer",
    ...reporting("working", "Reading files"),
  };
  assert.equal(agentName(a, k), "reviewer");
});

test("opencode: the OC prefix is stripped from its title", () => {
  const a = agent("opencode", { title: "OC | Fix sidebar" });
  assert.equal(agentName(a, undefined), "Fix sidebar");
});

test("opencode: a bare OpenCode title falls back to the program", () => {
  const a = agent("opencode", { title: "OpenCode" });
  assert.equal(agentName(a, undefined), "opencode");
});

test("pi: its session name from the report while working or done", () => {
  const a = agent("pi", { title: "π - dotfiles" });
  assert.equal(
    agentName(a, reporting("working", "desk cleanup")),
    "desk cleanup",
  );
  assert.equal(agentName(a, reporting("done", "desk cleanup")), "desk cleanup");
});

test("pi: an idle report and a program-and-folder title fall back to the program", () => {
  const a = agent("pi", { title: "π - dotfiles" });
  assert.equal(agentName(a, reporting("idle", "desk cleanup")), "pi");
});

test("an unknown agent with a path title falls back to the program", () => {
  const a = agent("codex", { title: "~/dotfiles" });
  assert.equal(agentName(a, undefined), "codex");
});

test("a named tab never becomes the agent's name", () => {
  const a = agent("claude-code", { tab_name: "auth" });
  assert.equal(agentName(a, undefined), "claude-code");
});

test("the report is also read from `status`, as `hc get` prints it", () => {
  const a = agent("pi", { title: "π - dotfiles" });
  const k = {
    status: {
      app: "pi",
      state: "working",
      msg: "desk cleanup",
    },
  };
  assert.equal(agentName(a, k), "desk cleanup");
});

test("agentActivity: Claude Code's report message while working", () => {
  const a = agent("claude-code");
  assert.equal(
    agentActivity(a, reporting("working", "Reading files")),
    "Reading files",
  );
});

test("agentActivity: none for Claude Code when done", () => {
  const a = agent("claude-code");
  assert.equal(agentActivity(a, reporting("done", "Reading files")), null);
});

test("agentActivity: none for pi, whose message is its session name", () => {
  const a = agent("pi");
  assert.equal(agentActivity(a, reporting("working", "desk cleanup")), null);
});

test("agentActivity: none without a terminals() entry", () => {
  const a = agent("claude-code");
  assert.equal(agentActivity(a, undefined), null);
});
