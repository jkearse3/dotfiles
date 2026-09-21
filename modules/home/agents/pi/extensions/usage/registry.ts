import { UsageQueryCoordinator, type UsageQueryOutcome } from "./cache.ts";
import { abortError, errorMessage } from "./core.ts";
import type {
  UsageProviderAdapter,
  UsageProviderQueryContext,
  UsageProviderResult,
} from "./types.ts";

const DEFAULT_QUERY_CONCURRENCY = 3;
const DEFAULT_PROVIDER_TIMEOUT_MS = 15_000;

type QueryEntry =
  | { adapter: UsageProviderAdapter }
  | { result: UsageProviderResult };

/** Controls one configured-provider query without changing adapter semantics. */
export interface QueryConfiguredUsageOptions {
  concurrency?: number;
  providerTimeoutMs?: number;
  forceRefresh?: boolean;
  coordinator?: UsageQueryCoordinator;
}

/** Rejects duplicate or malformed adapter identities before command registration. */
export function validateUsageAdapters(
  adapters: readonly UsageProviderAdapter[],
): void {
  const ids = new Set<string>();
  for (const adapter of adapters) {
    if (!/^[a-z0-9]+(?:-[a-z0-9]+)*$/u.test(adapter.id)) {
      throw new Error(`Invalid usage provider ID: ${adapter.id}`);
    }
    if (ids.has(adapter.id)) {
      throw new Error(`Duplicate usage provider ID: ${adapter.id}`);
    }
    ids.add(adapter.id);
  }
}

/**
 * Queries every configured adapter with bounded concurrency and preserves
 * provider order plus partial failures for the central dashboard.
 */
export async function queryConfiguredUsage(
  adapters: readonly UsageProviderAdapter[],
  queryContext: UsageProviderQueryContext,
  options: QueryConfiguredUsageOptions = {},
): Promise<UsageProviderResult[]> {
  const concurrency = options.concurrency ?? DEFAULT_QUERY_CONCURRENCY;
  const providerTimeoutMs =
    options.providerTimeoutMs ?? DEFAULT_PROVIDER_TIMEOUT_MS;
  const coordinator = options.coordinator ?? new UsageQueryCoordinator();
  if (!Number.isSafeInteger(concurrency) || concurrency < 1) {
    throw new Error("Usage query concurrency must be a positive integer.");
  }
  if (!Number.isFinite(providerTimeoutMs) || providerTimeoutMs <= 0) {
    throw new Error("Usage provider timeout must be positive.");
  }
  if (queryContext.signal.aborted) throw abortError();

  const entries = configuredEntries(adapters, queryContext);
  const results = new Array<UsageProviderResult>(entries.length);
  let nextIndex = 0;

  const workers = Array.from(
    { length: Math.min(concurrency, entries.length) },
    async () => {
      while (nextIndex < entries.length) {
        if (queryContext.signal.aborted) throw abortError();
        const index = nextIndex;
        nextIndex += 1;
        const entry = entries[index];
        if (!entry) continue;
        if ("result" in entry) {
          results[index] = entry.result;
          continue;
        }

        const adapter = entry.adapter;
        try {
          const outcome = await queryAdapterWithDeadline(
            adapter,
            queryContext,
            coordinator,
            options.forceRefresh ?? false,
            providerTimeoutMs,
          );
          results[index] = { status: "ready", ...outcome };
        } catch (error) {
          if (queryContext.signal.aborted) throw abortError();
          results[index] = providerError(adapter, error);
        }
      }
    },
  );

  await Promise.all(workers);
  if (queryContext.signal.aborted) throw abortError();
  return results;
}

function configuredEntries(
  adapters: readonly UsageProviderAdapter[],
  queryContext: UsageProviderQueryContext,
): QueryEntry[] {
  const entries: QueryEntry[] = [];
  for (const adapter of adapters) {
    try {
      if (adapter.isConfigured(queryContext.context)) {
        entries.push({ adapter });
      }
    } catch (error) {
      entries.push({ result: providerError(adapter, error) });
    }
  }
  return entries;
}

async function queryAdapterWithDeadline(
  adapter: UsageProviderAdapter,
  queryContext: UsageProviderQueryContext,
  coordinator: UsageQueryCoordinator,
  forceRefresh: boolean,
  timeoutMs: number,
): Promise<UsageQueryOutcome> {
  const controller = new AbortController();
  let timedOut = false;
  const relayAbort = () => controller.abort(queryContext.signal.reason);
  if (queryContext.signal.aborted) relayAbort();
  else
    queryContext.signal.addEventListener("abort", relayAbort, { once: true });

  const timeout = setTimeout(() => {
    timedOut = true;
    controller.abort(
      new DOMException("Usage provider query timed out", "TimeoutError"),
    );
  }, timeoutMs);
  timeout.unref?.();

  const aborted = new Promise<never>((_resolve, reject) => {
    const rejectAbort = () => {
      reject(
        timedOut
          ? new Error(`Usage provider query timed out after ${timeoutMs}ms.`)
          : abortError(),
      );
    };
    if (controller.signal.aborted) rejectAbort();
    else
      controller.signal.addEventListener("abort", rejectAbort, { once: true });
  });

  const query = adapter
    .prepare({
      context: queryContext.context,
      signal: controller.signal,
    })
    .then((prepared) => {
      if (controller.signal.aborted) throw abortError();
      return coordinator.query(
        adapter.id,
        prepared,
        controller.signal,
        forceRefresh,
      );
    });

  try {
    return await Promise.race([query, aborted]);
  } finally {
    clearTimeout(timeout);
    queryContext.signal.removeEventListener("abort", relayAbort);
  }
}

function providerError(
  adapter: UsageProviderAdapter,
  error: unknown,
): UsageProviderResult {
  return {
    status: "error",
    providerId: adapter.id,
    providerName: adapter.displayName,
    message: errorMessage(error),
  };
}
