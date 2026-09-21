import type {
  ExtensionCommandContext,
  ExtensionContext,
} from "@earendil-works/pi-coding-agent";

/** A provider-owned display row whose value retains that provider's semantics. */
export interface UsageRow {
  label: string;
  value: string;
  detail?: string;
  resetsAt?: number;
}

/** A related group of provider usage rows. */
export interface UsageSection {
  title?: string;
  rows: readonly UsageRow[];
}

/** A point-in-time provider report rendered by the central usage dashboard. */
export interface UsageReport {
  providerId: string;
  providerName: string;
  semantics: string;
  capturedAt: number;
  sections: readonly UsageSection[];
  notes?: readonly string[];
}

/** Dependencies supplied while preparing one cancellable provider query. */
export interface UsageProviderQueryContext {
  context: ExtensionCommandContext;
  signal: AbortSignal;
}

/**
 * A credential-bound provider query that can be cached without retaining its
 * authentication material in the shared coordinator.
 */
export interface PreparedUsageQuery {
  cacheKey: string;
  execute(signal: AbortSignal): Promise<UsageReport>;
}

/**
 * Owns configuration detection, authentication preparation, transport, and
 * normalization for one subscription provider. Provider-specific features stay
 * beside their adapter instead of adding provider branches to the dashboard.
 */
export interface UsageProviderAdapter {
  id: string;
  displayName: string;
  isConfigured(context: ExtensionContext): boolean;
  prepare(context: UsageProviderQueryContext): Promise<PreparedUsageQuery>;
}

/** Identifies whether a report came from the provider or a fresh local cache. */
export interface UsageDataProvenance {
  source: "provider" | "cache";
  ageMs: number;
}

/** The result of querying one configured provider without hiding partial failure. */
export type UsageProviderResult =
  | {
      status: "ready";
      report: UsageReport;
      provenance: UsageDataProvenance;
    }
  | {
      status: "error";
      providerId: string;
      providerName: string;
      message: string;
    };
