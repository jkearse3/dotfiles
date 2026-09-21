/** The result-screen actions understood by the usage command loop. */
export type UsageResultsAction = "close" | "refresh";

/**
 * Loads and displays usage until the user closes or cancels, forcing every load
 * after the first refresh action to bypass fresh cache entries.
 */
export async function runUsageCommand<Result>(
  load: (forceRefresh: boolean) => Promise<Result | undefined>,
  show: (result: Result) => Promise<UsageResultsAction>,
): Promise<void> {
  let forceRefresh = false;
  while (true) {
    const result = await load(forceRefresh);
    if (result === undefined) return;

    const action = await show(result);
    if (action !== "refresh") return;
    forceRefresh = true;
  }
}

/**
 * Completes a results view for refresh or close input and reports whether the
 * input was consumed. Scrolling remains owned by the view component.
 */
export function handleUsageResultsAction(
  data: string,
  close: boolean,
  done: (action: UsageResultsAction) => void,
): boolean {
  const action = data === "r" ? "refresh" : close ? "close" : undefined;
  if (!action) return false;

  done(action);
  return true;
}
