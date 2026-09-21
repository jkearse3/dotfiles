import { abortError } from "./core.ts";
import type {
  PreparedUsageQuery,
  UsageDataProvenance,
  UsageReport,
} from "./types.ts";

const DEFAULT_CACHE_TTL_MS = 5 * 60 * 1_000;
const DEFAULT_CACHE_CAPACITY = 32;

/** The freshness of one credential-bound report in the process-local cache. */
export type UsageCacheLookup =
  | { status: "missing" }
  | { status: "fresh"; ageMs: number; report: UsageReport }
  | { status: "stale"; ageMs: number; report: UsageReport };

/** A provider report annotated with its command-visible data provenance. */
export interface UsageQueryOutcome {
  report: UsageReport;
  provenance: UsageDataProvenance;
}

interface UsageCacheEntry {
  createdAt: number;
  expires: ReturnType<typeof setTimeout>;
  report: UsageReport;
}

interface UsageInFlightEntry {
  controller: AbortController;
  consumers: number;
  settled: boolean;
  promise: Promise<UsageReport>;
}

/**
 * Coordinates credential-keyed report caching and in-flight request sharing.
 * It performs no background work; callers decide when provider queries begin.
 */
export class UsageQueryCoordinator {
  private readonly cache = new Map<string, UsageCacheEntry>();
  private readonly inFlight = new Map<string, UsageInFlightEntry>();
  private readonly ttlMs: number;
  private readonly capacity: number;
  private readonly now: () => number;

  constructor(
    ttlMs = DEFAULT_CACHE_TTL_MS,
    capacity = DEFAULT_CACHE_CAPACITY,
    now: () => number = () => performance.now(),
  ) {
    if (!Number.isFinite(ttlMs) || ttlMs <= 0) {
      throw new Error("Usage cache TTL must be positive.");
    }
    if (!Number.isSafeInteger(capacity) || capacity < 1) {
      throw new Error("Usage cache capacity must be a positive integer.");
    }

    this.ttlMs = ttlMs;
    this.capacity = capacity;
    this.now = now;
  }

  /** Returns a cached report without starting provider or network work. */
  lookup(providerId: string, cacheKey: string): UsageCacheLookup {
    const key = usageCacheKey(providerId, cacheKey);
    const entry = this.cache.get(key);
    if (!entry) return { status: "missing" };

    const ageMs = this.now() - entry.createdAt;
    if (ageMs >= 0 && ageMs <= this.ttlMs) {
      return { status: "fresh", ageMs, report: entry.report };
    }

    this.deleteCacheEntry(key, entry);
    return { status: "stale", ageMs: Math.max(0, ageMs), report: entry.report };
  }

  /**
   * Returns a fresh cached report or executes the prepared provider query.
   * Concurrent consumers of the same identity share one request; cancellation
   * aborts that request only after its final consumer leaves.
   */
  async query(
    providerId: string,
    prepared: PreparedUsageQuery,
    signal: AbortSignal,
    forceRefresh = false,
  ): Promise<UsageQueryOutcome> {
    if (signal.aborted) throw abortError();

    const key = usageCacheKey(providerId, prepared.cacheKey);
    const cached = this.lookup(providerId, prepared.cacheKey);
    if (!forceRefresh && cached.status === "fresh") {
      return {
        report: cached.report,
        provenance: { source: "cache", ageMs: cached.ageMs },
      };
    }

    let entry = this.inFlight.get(key);
    if (!entry) {
      entry = this.startQuery(providerId, key, prepared);
      this.inFlight.set(key, entry);
    }

    const report = await this.awaitQuery(key, entry, signal);
    return {
      report,
      provenance: { source: "provider", ageMs: 0 },
    };
  }

  /** Removes cached reports for a provider without disturbing other accounts. */
  clearProvider(providerId: string): void {
    const prefix = `${providerId.length}:${providerId}:`;
    for (const [key, entry] of this.cache) {
      if (key.startsWith(prefix)) this.deleteCacheEntry(key, entry);
    }
  }

  private startQuery(
    providerId: string,
    key: string,
    prepared: PreparedUsageQuery,
  ): UsageInFlightEntry {
    const controller = new AbortController();
    let entry: UsageInFlightEntry;
    const promise = Promise.resolve()
      .then(() => prepared.execute(controller.signal))
      .then((report) => {
        if (controller.signal.aborted || this.inFlight.get(key) !== entry) {
          throw abortError();
        }
        if (report.providerId !== providerId) {
          throw new Error(
            `Prepared usage query ${providerId} returned report ${report.providerId}.`,
          );
        }
        this.store(key, report);
        return report;
      })
      .finally(() => {
        entry.settled = true;
        if (this.inFlight.get(key) === entry) this.inFlight.delete(key);
      });
    entry = {
      controller,
      consumers: 0,
      settled: false,
      promise,
    };
    return entry;
  }

  private async awaitQuery(
    key: string,
    entry: UsageInFlightEntry,
    signal: AbortSignal,
  ): Promise<UsageReport> {
    entry.consumers += 1;
    let rejectAbort: (() => void) | undefined;
    const aborted = new Promise<never>((_resolve, reject) => {
      rejectAbort = () => reject(abortError());
      if (signal.aborted) rejectAbort();
      else signal.addEventListener("abort", rejectAbort, { once: true });
    });

    try {
      return await Promise.race([entry.promise, aborted]);
    } finally {
      if (rejectAbort) signal.removeEventListener("abort", rejectAbort);
      entry.consumers -= 1;
      if (entry.consumers === 0 && !entry.settled) {
        if (this.inFlight.get(key) === entry) this.inFlight.delete(key);
        entry.controller.abort();
      }
    }
  }

  private store(key: string, report: UsageReport): void {
    const existing = this.cache.get(key);
    if (existing) this.deleteCacheEntry(key, existing);
    while (this.cache.size >= this.capacity) {
      const oldestKey = this.cache.keys().next().value;
      if (oldestKey === undefined) break;
      const oldest = this.cache.get(oldestKey);
      if (oldest) this.deleteCacheEntry(oldestKey, oldest);
    }

    let entry: UsageCacheEntry;
    const expires = setTimeout(() => {
      if (this.cache.get(key) === entry) this.cache.delete(key);
    }, this.ttlMs);
    expires.unref?.();
    entry = {
      createdAt: this.now(),
      expires,
      report,
    };
    this.cache.set(key, entry);
  }

  private deleteCacheEntry(key: string, entry: UsageCacheEntry): void {
    if (this.cache.get(key) !== entry) return;
    clearTimeout(entry.expires);
    this.cache.delete(key);
  }
}

function usageCacheKey(providerId: string, cacheKey: string): string {
  return `${providerId.length}:${providerId}:${cacheKey}`;
}
