// The checkouts the desk-spaces sidebar shows: which Git or jj checkout each
// space's own folder is in, and each live terminal's current folder, with
// branch or bookmark, ahead/behind and its repo, looked up again only when
// the answer could have changed.
//
// A look at a folder first finds the root of the innermost checkout holding
// it with the cheap root queries (`locate`: `jj root` and `git rev-parse
// --show-toplevel`, `innermostRoot` picking between them), then runs the
// full lookup (`check`: several jj or git processes) once for that root,
// which every folder in that checkout shares. A folder is looked at when a
// space or live terminal is first in it, when a command or agent turn ends
// in a pane of a space's tab (that space's folder and the pane's terminal's),
// when its machine is back, and every minute while the window is in front,
// except on a machine the sidebar folds or leaves out (`due`); a jj
// operation or a commit in a local repo looks its roots up again (`watch`).
// The minute's look comes due for a checkout's folders together, spaces' and
// terminals' alike, so it too runs the full lookup once. Folders no space
// and no live terminal is in any more, and roots no such folder is in, are
// dropped, so later looks skip them.

import type { AsyncContext } from "gpui-kit";
import { exec, home, machines, watchFolder, window } from "herdr";
import type { ExecResult, PaneInfo, SpaceInfo } from "herdr";
import { innermostRoot } from "./checkout-root.js";
import { cliPath } from "./paths.js";
import { base } from "./space-order.js";
import type { SpaceCheckout } from "./space-order.js";
import { machineOf } from "./terminals.js";
import type { TerminalEntry } from "./terminals.js";

/**
 * A space's or repo's location: its machine (null for this computer) and a
 * folder there. `where()` keys and checkouts' `repo` are these as JSON.
 */
export type MachinePath = [machine: string | null, path: string];

/**
 * A checkout's root as `locate` finds it: its machine (null for this
 * computer), its root folder, and which tool's checkout it is, which picks
 * the full lookup `check` runs. Root keys (`Checkouts.git`'s) are these as
 * JSON, so a root that turns from Git to jj gets a new key.
 */
type CheckoutRoot = [machine: string | null, top: string, kind: "jj" | "git"];

/**
 * A Git checkout as `Checkouts.check` reads it: the repo's name, the
 * checkout's root folder (`top`), its branch (null when detached), how far it
 * is ahead of and behind its upstream, its repo (`MachinePath` JSON of the
 * repo's git folder), and whether it is a linked worktree.
 */
export interface GitCheckout {
  /**
   * Never set: only a jj checkout has `jj`, so a falsy `jj` narrows
   * `Checkout` to this type.
   */
  jj?: false;
  name: string;
  top: string;
  branch: string | null;
  ahead: number;
  behind: number;
  repo: string;
  linked: boolean;
}

/**
 * A jj checkout as the terminal prompt shows it (`checkJj`): the repo's name,
 * the workspace root (`top`), the nearest bookmark ("(+1b)" when more share
 * it, null without one), which way and how far `@` is from it, `@`'s change ID,
 * whether `@` has a conflict or edits, its repo (`MachinePath` JSON of the
 * shared repo folder), and whether it is a secondary workspace.
 */
export interface JjCheckout {
  jj: true;
  name: string;
  top: string;
  bookmark: string | null;
  direction: "↓" | "↑";
  distance: number;
  change: string;
  conflict: boolean;
  modified: boolean;
  repo: string;
  linked: boolean;
}

/** A place's checkout, Git or jj (`jj` tells them apart). */
export type Checkout = GitCheckout | JjCheckout;

/**
 * A space's place: its machine and the space's own folder (where its new
 * terminals start, not where its terminals have since moved), as one string
 * key (JSON) for `Checkouts`' maps. An empty folder is that machine's home:
 * this computer's is filled in; another machine's stays empty, a place
 * `Checkouts.due` never looks at.
 */
export const where = (s: SpaceInfo): string =>
  JSON.stringify([s.machine ?? null, s.folder || (s.machine ? "" : home())]);
/**
 * A terminal's place: its machine and the folder it is in now
 * (`foreground.cwd`, else the `cwd` it started in, as `folderOf` reads it).
 * Null without either folder.
 */
export const terminalPlace = (t: TerminalEntry): MachinePath | null => {
  const cwd = t.foreground?.cwd || t.cwd;
  return cwd ? [machineOf(t.address), cwd] : null;
};
/** `terminalPlace` as a key, as `where` keys a space's place. */
export const terminalWhere = (t: TerminalEntry): string | null => {
  const place = terminalPlace(t);
  return place && JSON.stringify(place);
};
/** `path` made absolute against `from`, without "." or ".." segments. */
const resolve = (from: string, path: string): string => {
  const out: string[] = [];
  for (const part of (path.startsWith("/") ? path : `${from}/${path}`).split(
    "/",
  )) {
    if (part === "..") out.pop();
    else if (part && part !== ".") out.push(part);
  }
  return `/${out.join("/")}`;
};
/**
 * Changes made outside Herdr (an editor's save, a commit in another app):
 * looked for this often, in repos the list shows, while the window is in front.
 */
const FALLBACK = 60000;

/**
 * The checkouts of the places spaces and live terminals are in, and the
 * looks that keep them current. `skipsFallback` says which machines' repos
 * skip the fallback look: the view's folded machines and those it leaves out.
 */
export class Checkouts {
  declare roots: Record<string, string | null>;
  declare git: Record<string, Checkout | null>;
  declare checked: Record<string, number>;
  declare unsure: Set<string>;
  declare pending: Set<string>;
  declare pendingRoots: Set<string>;
  declare busy: Record<string, boolean>;
  declare ready: Record<string, boolean>;
  declare at: Record<string, string>;
  declare watching: Set<string>;
  declare refreshing: boolean;
  declare skipsFallback: (machine: string | null) => boolean;

  constructor(skipsFallback: (machine: string | null) => boolean) {
    this.roots = {}; // where() -> its innermost checkout's root key, null: in no checkout
    this.git = {}; // root key -> its checkout, null: a lookup that could not answer
    this.checked = {}; // where() -> when a pass last took it up (before `locate` sets `roots`)
    this.unsure = new Set(); // where()s and root keys that could not be answered for (a machine away)
    this.pending = new Set(); // where()s to look at next
    this.pendingRoots = new Set(); // root keys to look up next
    this.busy = {}; // pane -> an agent working or a program in front of its shell
    this.ready = {}; // machine -> its layout was readable at the last look
    this.at = {}; // space -> its where() at the last look
    this.watching = new Set(); // local repos' git folders
    this.refreshing = false; // a look is running
    this.skipsFallback = skipsFallback;
  }

  /**
   * The checkout the place `key` (a `where()`) is in: null when it is in
   * none or its lookup could not answer yet (`unsureOf`), undefined when it
   * has not been looked at, or its root not looked up, yet.
   */
  checkoutOf(key: string): Checkout | null | undefined {
    const root = this.roots[key];
    return root == null ? root : this.git[root];
  }

  /**
   * Whether the last look at the place `key`, or at its checkout's root,
   * could not answer (its machine away), so what `checkoutOf` gives may be
   * old.
   */
  unsureOf(key: string): boolean {
    const root = this.roots[key];
    return this.unsure.has(key) || (root != null && this.unsure.has(root));
  }

  /**
   * Places whose git could have changed: new ones (a new space, a space whose
   * folder changed, a folder a live terminal in `live` is in for the first
   * time; a shell that cds elsewhere does not move its space) no pass has
   * taken up yet, where a command or an agent's turn just ended in a pane of
   * a space's tab (that space's place and the terminal's own, a checkout, a
   * commit, edits), those on a machine that is back, and repos in view whose
   * fallback is due. A new place counts as taken up once a pass stamps it in
   * `checked`, before `locate` records its root, so its first look is not
   * asked for again while it runs.
   * Drops what it knew of places no space and no terminal in `live` is in
   * any more (`prune`).
   */
  due(
    now: number,
    sp: SpaceInfo[],
    ps: PaneInfo[],
    live: TerminalEntry[],
  ): Set<string> {
    // Moved there: what it knew of that place may be old.
    const at: Record<string, string> = {};
    for (const s of sp) at[s.id] = where(s);
    const terminalAt: Record<string, string> = {};
    for (const t of live) {
      const key = terminalWhere(t);
      if (key) terminalAt[t.address] = key;
    }
    const keys = new Set(
      [...Object.values(at), ...Object.values(terminalAt)].filter(
        (k) => (JSON.parse(k) as MachinePath)[1],
      ),
    );
    this.prune(keys);
    const due = new Set(
      [...keys].filter((k) => !(k in this.roots) && !(k in this.checked)),
    );
    for (const [id, k] of Object.entries(at))
      if (this.at[id] && this.at[id] !== k && keys.has(k)) due.add(k);
    this.at = at;
    const spaceOf: Record<string, SpaceInfo> = {};
    for (const s of sp) for (const t of s.tabs ?? []) spaceOf[t.id] = s;
    const busy: Record<string, boolean> = {};
    for (const p of ps) {
      if (!p.terminal || !spaceOf[p.tab]) continue;
      busy[p.pane] =
        p.status === "working" || !(p.program?.shell || p.program?.agent);
      if (this.busy[p.pane] && !busy[p.pane]) {
        this.sameRepo(at[spaceOf[p.tab].id], keys).forEach((k) => due.add(k));
        const own = terminalAt[p.terminal];
        if (own) this.sameRepo(own, keys).forEach((k) => due.add(k));
      }
    }
    this.busy = busy;
    for (const m of machines()) {
      const ready = m.layout === "ready";
      // This computer (null) keys as "null", a name no other machine has.
      if (ready && this.ready[m.name as string] === false)
        for (const k of keys)
          if ((JSON.parse(k) as MachinePath)[0] === m.name) due.add(k);
      this.ready[m.name as string] = ready;
    }
    if (window().active) {
      // A place whose fallback is due brings every place in its checkout
      // along, so they share one pass and one full lookup of their root, and
      // their clocks line up again.
      const dueRoots = new Set<string>();
      for (const k of keys) {
        const asks = this.checkoutOf(k) || this.unsureOf(k);
        if (
          asks &&
          !this.skipsFallback((JSON.parse(k) as MachinePath)[0]) &&
          now - (this.checked[k] ?? 0) > FALLBACK
        ) {
          due.add(k);
          const root = this.roots[k];
          if (root != null) dueRoots.add(root);
        }
      }
      for (const k of keys) {
        const root = this.roots[k];
        if (root != null && dueRoots.has(root)) due.add(k);
      }
    }
    return due;
  }

  /**
   * Forgets the places not in `used` and the roots no remaining place is in,
   * so no later look, fallback or repo watch asks for them again. A look
   * still running may add one back; the next call drops it again.
   */
  prune(used: Set<string>): void {
    for (const key of new Set([
      ...Object.keys(this.roots),
      ...Object.keys(this.checked),
    ])) {
      if (used.has(key)) continue;
      delete this.roots[key];
      delete this.checked[key];
      this.unsure.delete(key);
    }
    const roots = new Set(Object.values(this.roots));
    for (const root of Object.keys(this.git)) {
      if (roots.has(root)) continue;
      delete this.git[root];
      this.unsure.delete(root);
    }
  }

  /**
   * The checkout of each of `sp` by space id, with only
   * `SpaceCheckout`'s fields: null for a space whose folder git said is in
   * no repo. A space whose last look could not answer (its machine away)
   * keeps the checkout an earlier look found, as the sidebar does; one not
   * looked up yet, or never answered, is left out.
   */
  spaceCheckouts(sp: SpaceInfo[]): Record<string, SpaceCheckout | null> {
    const out: Record<string, SpaceCheckout | null> = {};
    for (const s of sp) {
      const key = where(s);
      const g = this.checkoutOf(key);
      if (g === undefined || (g === null && this.unsureOf(key))) continue;

      out[s.id] = g && {
        name: g.name,
        top: g.top,
        repo: g.repo,
        linked: g.linked,
      };
    }
    return out;
  }

  /**
   * `key` and the other places in its repo (a commit there moves their
   * ahead/behind).
   */
  sameRepo(key: string, keys: Set<string>): string[] {
    const repo = this.checkoutOf(key)?.repo;
    return [
      key,
      ...(repo
        ? [...keys].filter((k) => this.checkoutOf(k)?.repo === repo)
        : []),
    ];
  }

  /**
   * Looks at the places `keys` (`where()`s): finds each one's root, then
   * looks up each root found once.
   */
  refreshGit(keys: Iterable<string>, cx: AsyncContext): void {
    for (const k of keys) this.pending.add(k);
    this.refresh(cx);
  }

  /**
   * Looks up the roots `roots` (root keys) again without looking at the
   * places in them, as after a jj operation or a commit in their repo.
   */
  refreshRoots(roots: Iterable<string>, cx: AsyncContext): void {
    for (const root of roots) this.pendingRoots.add(root);
    this.refresh(cx);
  }

  /**
   * One look at a time, each place and each root once however often it was
   * asked for meanwhile; places first, so the roots they find join the same
   * pass.
   */
  refresh(cx: AsyncContext): void {
    if (this.refreshing) return;
    this.refreshing = true;
    cx.spawn(async (cx) => {
      while (this.pending.size || this.pendingRoots.size) {
        // The whole batch counts as looked at when the pass takes it, so a
        // new place still waiting for its root (`locate`, its own or behind
        // another's) is not due again meanwhile (`due`), and a checkout's
        // places keep one fallback clock.
        const keys = [...this.pending];
        this.pending.clear();
        const now = Date.now();
        for (const key of keys) this.checked[key] = now;
        for (const key of keys) {
          const root = await this.locate(key);
          if (root) this.pendingRoots.add(root);
        }

        const roots = [...this.pendingRoots];
        this.pendingRoots.clear();
        for (const root of roots) await this.check(root, cx);
      }

      const used = new Set(
        (
          Object.values(this.git)
            // `filter(Boolean)` dropped the roots whose lookup failed.
            .filter(Boolean) as Checkout[]
        )
          .map((g) => JSON.parse(g.repo) as MachinePath)
          .filter(([on]) => !on)
          .map(([, repo]) => repo),
      );
      for (const repo of this.watching)
        if (!used.has(repo)) this.watching.delete(repo);
      this.refreshing = false;
      cx.notify();
    });
  }

  /**
   * Finds the root of the innermost checkout the place `key` is in, records
   * it in `roots` and returns its root key; null when the place is in no
   * checkout. When it cannot tell (the machine away, git failing for another
   * reason), keeps the root an earlier look found, marks the place unsure and
   * returns null, so nothing is looked up for it.
   */
  async locate(key: string): Promise<string | null> {
    const [on, cwd] = JSON.parse(key) as MachinePath;
    this.unsure.delete(key);
    try {
      // A failing jj (not installed, not a jj checkout) leaves it to git.
      const jj = await jjCommand(["root"], cwd, on).catch(() => null);
      const jjTop = jj?.code === 0 ? jj.stdout.trim() : null;
      const git = await exec("git", ["rev-parse", "--show-toplevel"], {
        cwd,
        on,
      });
      const gitTop = git.code === 0 ? git.stdout.trim() : null;
      if (!jjTop && !gitTop && !/not a git repository/i.test(git.stderr)) {
        // Only git's own "no" is remembered as no checkout; anything else is
        // asked again.
        this.roots[key] ??= null;
        this.unsure.add(key);
        return null;
      }

      const inner = innermostRoot(jjTop, gitTop);
      const root: CheckoutRoot | null = inner && [on, inner.top, inner.kind];
      const rootKey = root && JSON.stringify(root);
      this.roots[key] = rootKey;
      return rootKey;
    } catch {
      // Couldn't ask (the machine is away): keep what it showed, look again
      // later.
      this.roots[key] ??= null;
      this.unsure.add(key);
      return null;
    }
  }

  /**
   * One checkout root's lookup (`root`, a root key): branch or bookmark,
   * ahead/behind, its repo. When it cannot answer, keeps what an earlier
   * lookup found and marks the root unsure.
   */
  async check(root: string, cx: AsyncContext): Promise<void> {
    const [on, top, kind] = JSON.parse(root) as CheckoutRoot;
    this.unsure.delete(root);
    try {
      const info =
        kind === "jj" ? await checkJj(top, on) : await checkGit(top, on);
      if (!info) {
        this.git[root] ??= null;
        this.unsure.add(root);
        return;
      }

      this.git[root] = info.checkout;
      if (!on)
        this.watch(
          info.repo,
          cx,
          info.checkout.jj ? `${info.repo}/op_heads` : info.repo,
        );
    } catch {
      // Couldn't ask (the machine is away): keep what it showed, look again
      // later.
      this.git[root] ??= null;
      this.unsure.add(root);
    }
  }

  /**
   * `dir` is what changes when the repo does: the git folder, or a jj repo's
   * op_heads.
   */
  watch(repo: string, cx: AsyncContext, dir: string = repo): void {
    if (this.watching.has(repo)) return;
    this.watching.add(repo);
    cx.spawn(async (cx) => {
      try {
        while (this.watching.has(repo)) {
          await watchFolder(dir);
          const mine = JSON.stringify([null, repo]);
          if (this.watching.has(repo))
            this.refreshRoots(
              Object.keys(this.git).filter((k) => this.git[k]?.repo === mine),
              cx,
            );
        }
      } catch {
        this.watching.delete(repo);
      }
    });
  }
}

/**
 * A checkout as a full lookup found it, with its repo folder: the git
 * folder of a Git checkout, the shared repo folder of a jj one.
 */
interface CheckoutLookup {
  checkout: Checkout;
  repo: string;
}

/**
 * The Git checkout whose root is `top`: its branch, ahead/behind and repo.
 * Null when git cannot answer there.
 */
async function checkGit(
  top: string,
  on: string | null,
): Promise<CheckoutLookup | null> {
  // No optional locks: a status that touched the index would wake the watch
  // again. Writes nothing under .git (index lock, fsmonitor cookie):
  // watch() would wake on it.
  const r = await exec(
    "git",
    [
      "--no-optional-locks",
      "-c",
      "core.fsmonitor=false",
      "status",
      "--porcelain=v2",
      "--branch",
    ],
    { cwd: top, on },
  );
  if (r.code !== 0) return null;

  // The repo's own .git folder names it; a worktree's top differs from it.
  const common = await exec(
    "git",
    ["rev-parse", "--path-format=absolute", "--git-common-dir"],
    { cwd: top, on },
  );
  if (common.code !== 0) return null;
  const repo = common.stdout.trim();
  const name = repo.endsWith("/.git")
    ? base(repo.slice(0, -5))
    : base(repo).replace(/\.git$/, "");
  const info: GitCheckout = {
    name,
    top,
    branch: null,
    ahead: 0,
    behind: 0,
    repo: JSON.stringify([on, repo]),
    linked: repo !== `${top}/.git`,
  };
  for (const line of r.stdout.split("\n")) {
    if (line.startsWith("# branch.head ")) info.branch = line.slice(14);
    else if (line.startsWith("# branch.ab ")) {
      const [a, b] = line.slice(12).split(" ");
      info.ahead = Math.abs(parseInt(a, 10)) || 0;
      info.behind = Math.abs(parseInt(b, 10)) || 0;
    }
  }
  return { checkout: info, repo };
}

/**
 * Runs jj with `args` in `cwd` on machine `on`. On this machine, the user's
 * jj by its store path, since the app's PATH depends on how the app was
 * started; another machine resolves its own `jj`. A dotfiles-paths.json
 * without the entry leaves the bare name. Every call passes
 * --ignore-working-copy: a snapshot would write an operation on each look,
 * which the op_heads watch would answer with another look.
 */
async function jjCommand(
  args: string[],
  cwd: string,
  on: string | null,
): Promise<ExecResult> {
  const program = on ? "jj" : await cliPath("jj").catch(() => "jj");
  return exec(
    program,
    ["--ignore-working-copy", "--no-pager", "--color=never", ...args],
    { cwd, on },
  );
}

/**
 * The jj checkout whose workspace root is `top`, as the terminal prompt
 * shows it. modules/home/shell/starship/jj-starship-prompt.sh mirrors this
 * bookmark and distance rule; change both together. Null when jj cannot
 * answer there.
 */
async function checkJj(
  top: string,
  on: string | null,
): Promise<CheckoutLookup | null> {
  const jj = (args: string[]): Promise<ExecResult> => jjCommand(args, top, on);
  // A secondary workspace's .jj/repo is a file naming the shared repo folder.
  const pointer = await exec("cat", [`${top}/.jj/repo`], { cwd: top, on });
  const repo =
    pointer.code === 0
      ? resolve(`${top}/.jj`, pointer.stdout.trim())
      : `${top}/.jj/repo`;
  // The bookmark names on the revisions `revset` selects (jjx bookmark
  // nearest).
  const names = async (revset: string): Promise<string[]> => {
    const r = await jj([
      "log",
      "--no-graph",
      "-r",
      revset,
      "-T",
      'local_bookmarks.map(|b| json(b.name())).join("\\n") ++ if(local_bookmarks, "\\n")',
    ]);
    if (r.code !== 0) throw new Error(r.stderr);
    return r.stdout
      .split("\n")
      .filter(Boolean)
      .map((line) => JSON.parse(line) as string);
  };
  const count = async (revset: string): Promise<number> => {
    const r = await jj(["log", "--no-graph", "-r", revset, "-T", '"x"']);
    if (r.code !== 0) throw new Error(r.stderr);
    return r.stdout.length;
  };
  try {
    // A bookmark at or after @ first (↓, the revisions from @ up to it), else
    // the nearest at or before it (↑, its descendants up to @, an empty @
    // too).
    const after = "roots(@:: & bookmarks())";
    const before = "heads(::@ & bookmarks())";
    let marks = await names(after);
    let direction: JjCheckout["direction"] = "↓";
    let distance = marks.length ? await count(`@..${after}`) : 0;
    if (!marks.length) {
      marks = await names(before);
      direction = "↑";
      distance = marks.length ? await count(`${before}::@ ~ ${before}`) : 0;
    }
    const at = await jj([
      "log",
      "--no-graph",
      "-r",
      "@",
      "-T",
      'change_id.shortest(8) ++ " " ++ if(conflict, "1", "0") ++ " " ++ if(empty, "1", "0")',
    ]);
    if (at.code !== 0) return null;
    const [change, conflict, empty] = at.stdout.trim().split(" ");
    const info: JjCheckout = {
      jj: true,
      name: base(repo.replace(/\/\.jj\/repo$/, "")),
      top,
      bookmark: marks.length
        ? marks[0] + (marks.length > 1 ? `(+${marks.length - 1}b)` : "")
        : null,
      direction,
      distance,
      change,
      conflict: conflict === "1",
      modified: empty === "0",
      repo: JSON.stringify([on, repo]),
      linked: repo !== `${top}/.jj/repo`,
    };
    return { checkout: info, repo };
  } catch {
    return null;
  }
}
