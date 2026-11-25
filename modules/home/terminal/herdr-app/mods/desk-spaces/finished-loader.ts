// The finished terminals the desk-spaces sidebar lists under the live
// terminals that started them, read from the CLI off the render path:
// `hc ls --all --json` says which terminals are finished, and
// `hc get <address> --json` reads each one not read before while this runs.

import type { AsyncContext } from "gpui-kit";
import { hc } from "herdr";
import { finishedAddresses, finishedTerminalOf } from "./finished.js";
import type { FinishedTerminal } from "./finished.js";

/**
 * The finished terminals known while the sidebar runs, and the reads that
 * keep them current. Reads run one at a time: a `refresh` asked for while
 * one runs makes it read again once it ends. A failed `hc ls` keeps the last
 * good set; a failed `hc get` leaves that terminal out until a later
 * refresh reads it.
 */
export class FinishedLoader {
  /**
   * Address -> its finished terminal, as `hc get` gave it. A finished
   * terminal's record does not change, so each is read once; one that
   * `hc ls` stops listing (removed) is dropped.
   */
  declare byAddress: Map<string, FinishedTerminal>;
  /**
   * The live terminal addresses `checkLive` last saw, sorted and joined;
   * null before the first look.
   */
  declare liveKey: string | null;
  declare refreshing: boolean;
  declare rerun: boolean;

  constructor() {
    this.byAddress = new Map();
    this.liveKey = null;
    this.refreshing = false;
    this.rerun = false;
  }

  /** The finished terminals known, in `hc ls` order. */
  get finished(): FinishedTerminal[] {
    return [...this.byAddress.values()];
  }

  /**
   * Refreshes when the live terminals (`liveAddresses`, in any order)
   * differ from the last call's, since a terminal that leaves them may have
   * just finished. The first call always refreshes.
   */
  checkLive(liveAddresses: string[], cx: AsyncContext): void {
    const key = [...liveAddresses].sort().join("\n");
    if (key === this.liveKey) return;

    this.liveKey = key;
    this.refresh(cx);
  }

  /**
   * Reads the finished terminals again, then redraws the view when the set
   * changed.
   */
  refresh(cx: AsyncContext): void {
    if (this.refreshing) {
      this.rerun = true;
      return;
    }

    this.refreshing = true;
    cx.spawn(async (cx) => {
      let changed = false;
      try {
        do {
          this.rerun = false;
          changed = (await this.load()) || changed;
        } while (this.rerun);
      } finally {
        this.refreshing = false;
      }
      if (changed) cx.notify();
    });
  }

  /**
   * One read: the finished addresses `hc ls` lists, each looked up in
   * `byAddress` or read with `hc get`. Whether the set of known finished
   * terminals changed; false, keeping the set, when `hc ls` fails.
   */
  async load(): Promise<boolean> {
    const listed = await hcStdout(["ls", "--all", "--json"]);
    const addresses = listed === null ? null : finishedAddresses(listed);
    if (addresses === null) return false;

    const next = new Map<string, FinishedTerminal>();
    for (const address of addresses) {
      const known = this.byAddress.get(address);
      if (known) {
        next.set(address, known);
        continue;
      }
      const read = await hcStdout(["get", address, "--json"]);
      const f = read === null ? null : finishedTerminalOf(address, read);
      if (f) next.set(address, f);
    }

    const changed =
      next.size !== this.byAddress.size ||
      [...next.keys()].some((address) => !this.byAddress.has(address));
    this.byAddress = next;
    return changed;
  }
}

/**
 * The standard output of `hc args`; null when it cannot run or exits
 * non-zero, which callers treat as no answer this time.
 */
async function hcStdout(args: string[]): Promise<string | null> {
  try {
    const r = await hc(args);
    return r.code === 0 ? r.stdout : null;
  } catch {
    return null;
  }
}
