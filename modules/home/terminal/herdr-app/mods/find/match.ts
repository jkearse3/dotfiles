// Filters the find hub's rows by the query typed into it (`match`), with
// fzf's own matcher and query syntax, so the hub matches the way an fzf
// picker does. fzf runs once per query in `--filter` mode, through `sh`
// and the app's `exec`, over each row's key and sanitized text; only the
// text is matched, and fzf's output lines map back to rows by key.
//
// `planShownList` decides which match the hub's list shows and when to
// start or discard one, and `LatestRequest` keeps a slow answer to an
// older query (or an older preview) from replacing a newer one.
//
// This file imports only types from `herdr`, and `exec` is passed in, so
// `find-test.mjs` can test it under Node, against the real fzf too.

import type { ExecResult } from "herdr";

/**
 * A row `match` can filter: `key` identifies it and is never matched,
 * `text` is what the query matches.
 */
export interface Matchable {
  key: string;
  text: string;
}

/**
 * Runs `command` with `args` and resolves with its exit code and output,
 * as the app's `exec` does; rejects when the command cannot start.
 */
export type Exec = (command: string, args: string[]) => Promise<ExecResult>;

/**
 * The `sh -c` script `matchArgs` runs: `$1` is fzf's path, `$2` the query,
 * and every further argument one "<key>\t<text>" line. fzf keeps the lines
 * whose second field onwards (the text) match, best first, input order
 * among ties. `String.raw` keeps `\n` and `\t` for `printf` and fzf to read.
 */
export const FZF_SCRIPT = String.raw`f=$1 q=$2; shift 2; printf "%s\n" "$@" | "$f" --filter="$q" --delimiter="\t" --nth=2.. --tiebreak=index`;

/**
 * `text` on one line fit for an fzf input line: control characters (C0,
 * DEL and C1, including tabs and newlines) become spaces, runs of
 * whitespace collapse to one space, and the ends are trimmed.
 */
export function sanitize(text: string): string {
  return text
    .replace(/[\u0000-\u001f\u007f-\u009f]/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

/**
 * The `sh` arguments that filter `rows` by `query` with the fzf at
 * `fzfPath`. The query and rows travel as arguments, never inside the
 * script, so no shell quoting applies to them.
 */
export function matchArgs(
  fzfPath: string,
  query: string,
  rows: readonly Matchable[],
): string[] {
  return [
    "-c",
    FZF_SCRIPT,
    "sh",
    fzfPath,
    query,
    ...rows.map((r) => `${r.key}\t${sanitize(r.text)}`),
  ];
}

/**
 * The rows fzf's `stdout` names, in fzf's order. Each line's key is its
 * text before the first tab; empty lines and keys not among `rows` are
 * skipped.
 */
export function parseMatch<R extends Matchable>(
  stdout: string,
  rows: readonly R[],
): R[] {
  const byKey = new Map(rows.map((r) => [r.key, r]));

  const matched: R[] = [];
  for (const line of stdout.split("\n")) {
    if (line === "") continue;
    const row = byKey.get(line.split("\t", 1)[0]);
    if (row) matched.push(row);
  }
  return matched;
}

/**
 * The rows matching `query`, best first, as fzf at `fzfPath` ranks them.
 * A blank query matches every row in its given order, and neither it nor
 * an empty `rows` runs fzf. No match resolves to `[]` (fzf's exit 1).
 * Rejects with fzf's stderr (or its exit code) when fzf fails, such as on
 * a malformed query, and with `exec`'s error when `sh` cannot start.
 */
export async function match<R extends Matchable>(
  exec: Exec,
  fzfPath: string,
  query: string,
  rows: readonly R[],
): Promise<R[]> {
  if (query.trim() === "" || rows.length === 0) return [...rows];

  const result = await exec("sh", matchArgs(fzfPath, query, rows));
  if (result.code === 0) return parseMatch(result.stdout, rows);
  if (result.code === 1) return [];
  throw new Error(result.stderr.trim() || `fzf exited with ${result.code}`);
}

/**
 * `match`, but never rejecting: when matching fails, `rows` comes back
 * whole and unfiltered with `error` set to the first line of the failure,
 * so the hub stays usable without fzf and can say why it isn't filtering.
 * `error` is null on success.
 */
export async function matchOrAll<R extends Matchable>(
  exec: Exec,
  fzfPath: string,
  query: string,
  rows: readonly R[],
): Promise<{ rows: R[]; error: string | null }> {
  try {
    return {
      rows: await match(exec, fzfPath, query, rows),
      error: null,
    };
  } catch (e) {
    const message = e instanceof Error ? e.message : String(e);
    return {
      rows: [...rows],
      error: message.split("\n", 1)[0],
    };
  }
}

/**
 * Whether `a` and `b` would give `match` the same input: the same keys
 * with the same texts, in the same order. The hub can then keep a result
 * instead of rerunning fzf.
 */
export function sameMatchInput(
  a: readonly Matchable[],
  b: readonly Matchable[],
): boolean {
  return (
    a.length === b.length &&
    a.every((r, i) => r.key === b[i].key && r.text === b[i].text)
  );
}

/**
 * A match the hub asked for: `query` over `input`, the keys and texts of
 * the rows it filters.
 */
export interface MatchRequest {
  query: string;
  input: Matchable[];
}

/**
 * The hub's match state that `planShownList` reads: `matched` is the
 * latest match that finished, `requested` the match the list on screen
 * answers or awaits, and `shownQuery` the query whose list is on screen.
 */
export interface ShownListState<M extends MatchRequest> {
  matched: M | null;
  requested: MatchRequest | null;
  shownQuery: string;
}

/**
 * What the hub does for one render, from `planShownList`. The hub shows
 * `shown`'s rows in its order, or every row when `shown` is null; stores
 * `requested` and `shownQuery`; makes a match still running stale when
 * `invalidate` is set; and starts `start` when it is not null.
 */
export interface ShownListPlan<M extends MatchRequest> {
  shown: M | null;
  shownQuery: string;
  requested: MatchRequest | null;
  start: MatchRequest | null;
  invalidate: boolean;
}

/**
 * Decides the hub's list for `query` over `rows`, so a match answering an
 * older query or older rows is never drawn over a newer list:
 * - A blank query shows every row and starts nothing.
 * - When `matched` answers `query` over `rows`, the list shows it. A match
 *   still running, such as for a query since backspaced, no longer answers
 *   this list, so unless `matched` is already the request, it is made stale
 *   and `matched` becomes the request.
 * - Otherwise the list on screen stays (`matched` while `shownQuery` is not
 *   blank, else every row) until the match arrives, and the match starts
 *   unless it is already `requested`.
 */
export function planShownList<M extends MatchRequest>(
  query: string,
  rows: readonly Matchable[],
  state: ShownListState<M>,
): ShownListPlan<M> {
  const { matched, requested, shownQuery } = state;
  if (query.trim() === "") {
    return {
      shown: null,
      shownQuery: query,
      requested,
      start: null,
      invalidate: false,
    };
  }

  const input = rows.map(({ key, text }) => ({
    key,
    text,
  }));
  if (matched?.query === query && sameMatchInput(matched.input, input)) {
    return {
      shown: matched,
      shownQuery: query,
      requested: matched,
      start: null,
      invalidate: requested !== matched,
    };
  }

  const isRequested =
    requested?.query === query && sameMatchInput(requested.input, input);
  const start = isRequested
    ? null
    : {
        query,
        input,
      };
  return {
    shown: shownQuery.trim() !== "" ? matched : null,
    shownQuery,
    requested: start ?? requested,
    start,
    invalidate: false,
  };
}

/**
 * Tracks a series of asynchronous requests, such as one match per query,
 * so only the latest one's result is used.
 */
export class LatestRequest {
  /** The number of requests `run` has started, plus one per `invalidate`. */
  declare last: number;

  constructor() {
    this.last = 0;
  }

  /**
   * Runs `work` as the latest request. Resolves `{ stale: true }` when a
   * newer `run` started before `work` settled, whether `work` resolved or
   * rejected; otherwise resolves with its value or rethrows its error.
   */
  async run<T>(
    work: () => Promise<T>,
  ): Promise<{ stale: false; value: T } | { stale: true }> {
    const request = ++this.last;
    try {
      const value = await work();
      return request === this.last ? { stale: false, value } : { stale: true };
    } catch (e) {
      if (request !== this.last) return { stale: true };
      throw e;
    }
  }

  /**
   * Makes every request still running resolve `{ stale: true }`, for when
   * the latest one no longer answers what its result would be used for.
   */
  invalidate(): void {
    this.last++;
  }
}
