import type { ExtensionUIContext } from "@earendil-works/pi-coding-agent";

/**
 * Creates an idle spinner timer; TUI lifecycle callers start it once per busy
 * period and stop it on settlement or disposal. Both operations are idempotent;
 * stopping restores the default working label.
 */
export function createLiveAgentTimer() {
  let interval: ReturnType<typeof setInterval> | undefined;
  let activeUI: ExtensionUIContext | undefined;

  const stop = (): void => {
    if (interval !== undefined) clearInterval(interval);
    interval = undefined;
    activeUI?.setWorkingMessage();
    activeUI = undefined;
  };

  const start = (ui: ExtensionUIContext): void => {
    if (interval !== undefined) return;
    activeUI = ui;
    const startedAt = performance.now();
    const update = (): void => {
      const tenths = Math.floor((performance.now() - startedAt) / 100);
      const seconds = (tenths / 10).toFixed(1);
      const elapsed =
        tenths < 600
          ? `${seconds}s`
          : `${Math.floor(tenths / 600)}m ${((tenths % 600) / 10).toFixed(1).padStart(4, "0")}s`;
      ui.setWorkingMessage(`Working… (${elapsed})`);
    };

    update();
    interval = setInterval(update, 100);
    interval.unref();
  };

  return {
    start,
    stop,
  };
}
