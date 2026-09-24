import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

/** Ephemeral presentation choice shared by the command and assistant renderers. */
export interface InlineTimingsState {
  isVisible(): boolean;
  toggle(): boolean;
}

/** Keeps per-turn timing rows hidden until explicitly enabled in this Pi process. */
export function createInlineTimingsState(): InlineTimingsState {
  let visible = false;
  return {
    isVisible: () => visible,
    toggle() {
      visible = !visible;
      return visible;
    },
  };
}

/** Toggles assistant turn timings in place instead of printing a separate report. */
export function registerTimingsCommand(
  pi: ExtensionAPI,
  state: InlineTimingsState,
): void {
  pi.registerCommand("timings", {
    description: "Show or hide per-turn timing rows in the transcript",
    handler: async (_args, ctx) => {
      if (ctx.mode !== "tui") return;
      const visible = state.toggle();
      ctx.ui.notify(`Turn timings ${visible ? "shown" : "hidden"}`, "info");
    },
  });
}
