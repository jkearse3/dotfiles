const DOUBLE_ESCAPE_WINDOW_MS = 500;

export type DoubleEscapeAction = "pass-through" | "edit-last-prompt";

/**
 * Recognizes two empty-editor Escape presses when the first press interrupted an
 * active agent run. Other input and expired sequences reset the gesture.
 */
export class EditLastPromptGesture {
  private firstEscapeAt: number | undefined;
  private firstEscapeInterruptedRun = false;

  handleEscape(
    now: number,
    agentIdle: boolean,
    editorEmpty: boolean,
  ): DoubleEscapeAction {
    if (!editorEmpty) {
      this.reset();
      return "pass-through";
    }

    const elapsed =
      this.firstEscapeAt === undefined ? undefined : now - this.firstEscapeAt;
    if (
      elapsed !== undefined &&
      elapsed >= 0 &&
      elapsed < DOUBLE_ESCAPE_WINDOW_MS
    ) {
      const action = this.firstEscapeInterruptedRun
        ? "edit-last-prompt"
        : "pass-through";
      this.reset();
      return action;
    }

    this.firstEscapeAt = now;
    this.firstEscapeInterruptedRun = !agentIdle;
    return "pass-through";
  }

  /** Cancel a pending double-Escape gesture after any non-Escape input. */
  reset(): void {
    this.firstEscapeAt = undefined;
    this.firstEscapeInterruptedRun = false;
  }
}

/** Return the newest user-message entry ID on the active session branch. */
export function findLatestUserMessageId(
  entries: readonly {
    id: string;
    type: string;
    message?: { role: string };
  }[],
): string | undefined {
  for (let index = entries.length - 1; index >= 0; index -= 1) {
    const entry = entries[index];
    if (entry?.type === "message" && entry.message?.role === "user") {
      return entry.id;
    }
  }

  return undefined;
}
