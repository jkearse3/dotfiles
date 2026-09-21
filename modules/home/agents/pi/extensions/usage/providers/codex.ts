import {
  abortError,
  fetchUsageJson,
  providerIsConfigured,
  resolveOfficialProviderAuth,
  sanitizeDisplayText,
  type UsageFetch,
} from "../core.ts";
import type {
  UsageProviderAdapter,
  UsageReport,
  UsageRow,
  UsageSection,
} from "../types.ts";

const CODEX_PROVIDER_ID = "openai-codex";
const CODEX_ORIGIN = "https://chatgpt.com";
const CODEX_USAGE_URL = `${CODEX_ORIGIN}/backend-api/wham/usage`;

/** Creates the Codex adapter, optionally with an injected fetch for safe tests. */
export function createCodexUsageAdapter(
  fetchImplementation: UsageFetch = fetch,
): UsageProviderAdapter {
  return {
    id: CODEX_PROVIDER_ID,
    displayName: "OpenAI Codex",
    isConfigured: (context) => providerIsConfigured(context, CODEX_PROVIDER_ID),
    async prepare({ context, signal }) {
      const auth = await resolveOfficialProviderAuth(
        context,
        CODEX_PROVIDER_ID,
        CODEX_ORIGIN,
      );
      if (signal.aborted) throw abortError();

      return {
        cacheKey: auth.fingerprint,
        async execute(executionSignal) {
          const payload = await fetchUsageJson(
            CODEX_USAGE_URL,
            auth,
            executionSignal,
            fetchImplementation,
          );
          return normalizeCodexUsage(payload, Date.now());
        },
      };
    },
  };
}

/** Converts the Codex backend response into provider-neutral dashboard sections. */
export function normalizeCodexUsage(
  payload: Record<string, unknown>,
  capturedAt: number,
): UsageReport {
  const sections: UsageSection[] = [];
  const primaryRows = normalizeRateLimitRows(payload.rate_limit);
  if (primaryRows.length > 0)
    sections.push({ title: "Codex limits", rows: primaryRows });

  const additionalLimits = Array.isArray(payload.additional_rate_limits)
    ? payload.additional_rate_limits
    : [];
  for (const rawLimit of additionalLimits) {
    const limit = asRecord(rawLimit);
    if (!limit) continue;

    const id =
      asDisplayString(limit.metered_feature) ??
      asDisplayString(limit.limit_name);
    if (!id) continue;
    const rows = normalizeRateLimitRows(limit.rate_limit);
    if (rows.length === 0) continue;

    sections.push({
      title: asDisplayString(limit.limit_name) ?? id,
      rows,
    });
  }

  const accountRows = normalizeAccountRows(payload);
  if (accountRows.length > 0)
    sections.unshift({ title: "Subscription", rows: accountRows });
  if (sections.length === 0) {
    throw new Error("Codex usage endpoint returned no displayable usage data.");
  }

  return {
    providerId: CODEX_PROVIDER_ID,
    providerName: "OpenAI Codex",
    semantics: "ChatGPT subscription limits",
    capturedAt,
    sections,
  };
}

function normalizeRateLimitRows(rawRateLimit: unknown): UsageRow[] {
  const rateLimit = asRecord(rawRateLimit);
  if (!rateLimit) return [];

  const rows: UsageRow[] = [];
  const primary = normalizeWindow(
    "Primary limit",
    rateLimit.primary_window,
    "5h",
  );
  const secondary = normalizeWindow(
    "Secondary limit",
    rateLimit.secondary_window,
    "Weekly",
  );
  if (primary) rows.push(primary);
  if (secondary) rows.push(secondary);
  return rows;
}

function normalizeWindow(
  fallbackLabel: string,
  rawWindow: unknown,
  fallbackPeriod: string,
): UsageRow | undefined {
  const window = asRecord(rawWindow);
  if (!window) return undefined;

  const used = asNumber(window.used_percent);
  if (used === undefined) return undefined;
  const remaining = 100 - clampPercent(used);
  const windowSeconds = asNumber(window.limit_window_seconds);
  const resetsAt = asNumber(window.reset_at);

  return {
    label:
      windowSeconds && windowSeconds > 0
        ? `${formatWindowDuration(windowSeconds)} limit`
        : fallbackLabel
            .replace("Primary", fallbackPeriod)
            .replace("Secondary", fallbackPeriod),
    value: `${remaining.toFixed(0)}% left`,
    detail: `${clampPercent(used).toFixed(0)}% used`,
    ...(resetsAt !== undefined ? { resetsAt } : {}),
  };
}

function normalizeAccountRows(payload: Record<string, unknown>): UsageRow[] {
  const rows: UsageRow[] = [];
  const plan = asDisplayString(payload.plan_type);
  if (plan) rows.push({ label: "Plan", value: plan });

  const credits = asRecord(payload.credits);
  if (credits?.has_credits === true) {
    const balance = asNumber(credits.balance);
    rows.push({
      label: "Credits",
      value:
        credits.unlimited === true
          ? "Unlimited"
          : balance === undefined
            ? "Available"
            : String(balance),
    });
  } else if (credits?.has_credits === false) {
    rows.push({ label: "Credits", value: "None" });
  }

  const resetCredits = asRecord(payload.rate_limit_reset_credits);
  const resetCount = asNonnegativeInteger(resetCredits?.available_count);
  if (resetCount !== undefined) {
    rows.push({
      label: "Usage limit resets",
      value: `${resetCount} available`,
    });
  }

  return rows;
}

function formatWindowDuration(seconds: number): string {
  const minutes = Math.ceil(seconds / 60);
  if (minutes === 10_080) return "Weekly";
  if (minutes % 10_080 === 0) return `${minutes / 10_080}w`;
  if (minutes % 1_440 === 0) return `${minutes / 1_440}d`;
  if (minutes % 60 === 0) return `${minutes / 60}h`;
  return `${minutes}m`;
}

function asRecord(value: unknown): Record<string, unknown> | undefined {
  return typeof value === "object" && value !== null && !Array.isArray(value)
    ? (value as Record<string, unknown>)
    : undefined;
}

function asDisplayString(value: unknown): string | undefined {
  if (typeof value !== "string") return undefined;
  return sanitizeDisplayText(value, 160) || undefined;
}

function asNumber(value: unknown): number | undefined {
  if (typeof value === "number" && Number.isFinite(value)) return value;
  if (typeof value === "string" && value.trim()) {
    const parsed = Number(value);
    return Number.isFinite(parsed) ? parsed : undefined;
  }
  return undefined;
}

function asNonnegativeInteger(value: unknown): number | undefined {
  const number = asNumber(value);
  return number !== undefined && Number.isSafeInteger(number) && number >= 0
    ? number
    : undefined;
}

function clampPercent(value: number): number {
  return Math.min(100, Math.max(0, value));
}
