// Each space's checkout as the desk-spaces sidebar shows it: which Git or jj
// checkout its first terminal is in, with branch or bookmark, ahead/behind and
// its repo, looked up again only when the answer could have changed.

import type { AsyncContext } from "gpui-kit";
import { exec, machines, watchFolder, window } from "herdr";
import type { ExecResult, PaneInfo, SpaceInfo } from "herdr";
import { cliPath, place } from "./paths.js";

// A space's or repo's location: its machine (null for this computer) and a
// folder there. `where()` keys and checkouts' `repo` are these as JSON.
type MachinePath = [machine: string | null, path: string];

// A Git checkout as `Checkouts.check` reads it: the repo's name, the
// checkout's root folder (`top`), its branch (null when detached), how far it
// is ahead of and behind its upstream, its repo (`MachinePath` JSON of the
// repo's git folder), and whether it is a linked worktree.
export interface GitCheckout {
  // Never set: only a jj checkout has `jj`, so a falsy `jj` narrows
  // `Checkout` to this type.
  jj?: false;
  name: string;
  top: string;
  branch: string | null;
  ahead: number;
  behind: number;
  repo: string;
  linked: boolean;
}

// A jj checkout as the terminal prompt shows it (`checkJj`): the repo's name,
// the workspace root (`top`), the nearest bookmark ("(+1b)" when more share
// it, null without one), which way and how far @ is from it, @'s change ID,
// whether @ has a conflict or edits, its repo (`MachinePath` JSON of the
// shared repo folder), and whether it is a secondary workspace.
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

// A place's checkout, Git or jj (`jj` tells them apart).
export type Checkout = GitCheckout | JjCheckout;

// A space's place: its machine and its first terminal's folder, as one string
// key (JSON) for `Checkouts`' maps.
export const where = (s: SpaceInfo, ps: PaneInfo[]): string =>
  JSON.stringify([s.machine ?? null, place(s, ps)]);
// `split` always returns at least one element, so `pop` finds one.
export const base = (path: string): string =>
  path.replace(/\/+$/, "").split("/").pop()!;
// `path` made absolute against `from`, without "." or ".." segments.
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
// Changes made outside Herdr (an editor's save, a commit in another app):
// looked for this often, in repos the list shows, while the window is in front.
const FALLBACK = 60000;

// The checkouts of the places spaces are in, and the looks that keep them
// current. `folded` is the view's set of folded machines (shared, never
// replaced): a folded machine's repos skip the fallback look.
export class Checkouts {
  declare git: Record<string, Checkout | null>;
  declare checked: Record<string, number>;
  declare unsure: Set<string>;
  declare pending: Set<string>;
  declare busy: Record<string, boolean>;
  declare ready: Record<string, boolean>;
  declare at: Record<string, string>;
  declare watching: Set<string>;
  declare refreshing: boolean;
  declare folded: Set<string | null>;

  constructor(folded: Set<string | null>) {
    this.git = {}; // where() -> { name, top, branch, ahead, behind, repo, linked }, null: not a repo
    this.checked = {}; // where() -> when it was last looked at
    this.unsure = new Set(); // where()s git couldn't answer for (a machine away)
    this.pending = new Set(); // where()s to look at next
    this.busy = {}; // pane -> an agent working or a program in front of its shell
    this.ready = {}; // machine -> its layout was readable at the last look
    this.at = {}; // space -> its where() at the last look
    this.watching = new Set(); // local repos' git folders
    this.refreshing = false; // a look is running
    this.folded = folded;
  }

  // Places whose git could have changed: new ones (a new space, a cd), where a
  // command or an agent's turn just ended (a checkout, a commit, edits), those
  // on a machine that is back, and repos in view whose fallback is due.
  due(now: number, sp: SpaceInfo[], ps: PaneInfo[]): Set<string> {
    // Moved there: what it knew of that place may be old.
    const at: Record<string, string> = {};
    for (const s of sp) at[s.id] = where(s, ps);
    const keys = new Set(
      Object.values(at).filter((k) => (JSON.parse(k) as MachinePath)[1]),
    );
    const due = new Set([...keys].filter((k) => !(k in this.git)));
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
      if (this.busy[p.pane] && !busy[p.pane])
        this.sameRepo(at[spaceOf[p.tab].id], keys).forEach((k) => due.add(k));
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
      for (const k of keys) {
        const asks = this.git[k] || this.unsure.has(k);
        if (
          asks &&
          !this.folded.has((JSON.parse(k) as MachinePath)[0]) &&
          now - (this.checked[k] ?? 0) > FALLBACK
        )
          due.add(k);
      }
    }
    return due;
  }

  // `key` and the other places in its repo (a commit there moves their
  // ahead/behind).
  sameRepo(key: string, keys: Set<string>): string[] {
    const repo = this.git[key]?.repo;
    return [
      key,
      ...(repo ? [...keys].filter((k) => this.git[k]?.repo === repo) : []),
    ];
  }

  // One look at a time, each place once however often it was asked for
  // meanwhile.
  refreshGit(keys: Iterable<string>, cx: AsyncContext): void {
    for (const k of keys) this.pending.add(k);
    if (this.refreshing) return;
    this.refreshing = true;
    cx.spawn(async (cx) => {
      while (this.pending.size) {
        const keys = [...this.pending];
        this.pending.clear();
        for (const key of keys) await this.check(key, cx);
      }
      const used = new Set(
        (
          Object.values(this.git)
            // `filter(Boolean)` dropped the places that are not repos.
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

  // One place's git: branch, ahead/behind, its repo.
  async check(key: string, cx: AsyncContext): Promise<void> {
    const [on, cwd] = JSON.parse(key) as MachinePath;
    this.checked[key] = Date.now();
    this.unsure.delete(key);
    try {
      // jj keeps Git's HEAD detached, so a jj checkout shows jj's own picture.
      const jj = await checkJj(cwd, on);
      if (jj) {
        this.git[key] = jj.info;
        if (!on) this.watch(jj.repo, cx, `${jj.repo}/op_heads`);
        return;
      }
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
        { cwd, on },
      );
      if (r.code !== 0) {
        // Only git's own "no" is remembered as no repo; anything else is asked
        // again.
        if (!/not a git repository/i.test(r.stderr)) this.unsure.add(key);
        this.git[key] = null;
        return;
      }
      // The repo's own .git folder names it; a worktree's top differs from it.
      const top = await exec("git", ["rev-parse", "--show-toplevel"], {
        cwd,
        on,
      });
      const common = await exec(
        "git",
        ["rev-parse", "--path-format=absolute", "--git-common-dir"],
        { cwd, on },
      );
      const repo = common.stdout.trim();
      const checkoutTop = top.stdout.trim();
      const name = repo.endsWith("/.git")
        ? base(repo.slice(0, -5))
        : base(repo).replace(/\.git$/, "");
      const info: GitCheckout = {
        name,
        top: checkoutTop,
        branch: null,
        ahead: 0,
        behind: 0,
        repo: JSON.stringify([on, repo]),
        linked: repo !== `${checkoutTop}/.git`,
      };
      for (const line of r.stdout.split("\n")) {
        if (line.startsWith("# branch.head ")) info.branch = line.slice(14);
        else if (line.startsWith("# branch.ab ")) {
          const [a, b] = line.slice(12).split(" ");
          info.ahead = Math.abs(parseInt(a, 10)) || 0;
          info.behind = Math.abs(parseInt(b, 10)) || 0;
        }
      }
      this.git[key] = info;
      if (!on) this.watch(repo, cx);
    } catch {
      // Couldn't ask (the machine is away): keep what it showed, look again
      // later.
      this.git[key] ??= null;
      this.unsure.add(key);
    }
  }

  // `dir` is what changes when the repo does: the git folder, or a jj repo's
  // op_heads.
  watch(repo: string, cx: AsyncContext, dir: string = repo): void {
    if (this.watching.has(repo)) return;
    this.watching.add(repo);
    cx.spawn(async (cx) => {
      try {
        while (this.watching.has(repo)) {
          await watchFolder(dir);
          const mine = JSON.stringify([null, repo]);
          if (this.watching.has(repo))
            this.refreshGit(
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

// One jj checkout as the terminal prompt shows it, with its shared repo
// folder. modules/home/shell/starship/jj-starship-prompt.sh mirrors this
// bookmark and distance rule; change both together. Returns null where jj
// isn't installed or the place isn't a jj checkout, which leaves it to git.
// Every jj call passes --ignore-working-copy: a snapshot would write an
// operation on each look, which the op_heads watch would answer with another
// look.
async function checkJj(
  cwd: string,
  on: string | null,
): Promise<{ info: JjCheckout; repo: string } | null> {
  // On this machine, the user's jj by its store path, since the app's PATH
  // depends on how the app was started; another machine resolves its own
  // `jj`. A dotfiles-paths.json without the entry leaves the bare name.
  const program = on ? "jj" : await cliPath("jj").catch(() => "jj");
  const jj = (args: string[]): Promise<ExecResult> =>
    exec(
      program,
      ["--ignore-working-copy", "--no-pager", "--color=never", ...args],
      { cwd, on },
    );
  let root: ExecResult;
  try {
    root = await jj(["root"]);
  } catch {
    return null;
  }
  if (root.code !== 0) return null;
  const top = root.stdout.trim();
  // A secondary workspace's .jj/repo is a file naming the shared repo folder.
  const pointer = await exec("cat", [`${top}/.jj/repo`], { cwd, on });
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
    return { info, repo };
  } catch {
    return null;
  }
}
