import assert from "node:assert/strict";
import test from "node:test";
import type { ExtensionCommandContext } from "@earendil-works/pi-coding-agent";

import { UsageQueryCoordinator } from "./cache.ts";
import { queryConfiguredUsage, validateUsageAdapters } from "./registry.ts";
import type {
  PreparedUsageQuery,
  UsageProviderAdapter,
  UsageReport,
} from "./types.ts";

const TEST_CONTEXT = {} as ExtensionCommandContext;

function report(providerId: string): UsageReport {
  return {
    providerId,
    providerName: providerId,
    semantics: "test semantics",
    capturedAt: 1,
    sections: [{ rows: [{ label: "Remaining", value: "50%" }] }],
  };
}

function adapter(
  id: string,
  options: {
    configured?: boolean;
    execute?: PreparedUsageQuery["execute"];
  } = {},
): UsageProviderAdapter {
  return {
    id,
    displayName: id.toUpperCase(),
    isConfigured: () => options.configured ?? true,
    prepare: async () => ({
      cacheKey: id,
      execute: options.execute ?? (async () => report(id)),
    }),
  };
}

test("adapter validation rejects malformed and duplicate provider IDs", () => {
  assert.throws(
    () => validateUsageAdapters([adapter("Bad ID")]),
    /Invalid usage provider ID/u,
  );
  assert.throws(
    () => validateUsageAdapters([adapter("codex"), adapter("codex")]),
    /Duplicate usage provider ID/u,
  );
});

test("configured usage preserves adapter order and partial failures", async () => {
  const adapters = [
    adapter("first", {
      execute: async () => {
        await new Promise((resolve) => setTimeout(resolve, 5));
        return report("first");
      },
    }),
    adapter("disabled", { configured: false }),
    adapter("failed", {
      execute: async () => {
        throw new Error("provider unavailable");
      },
    }),
  ];

  const results = await queryConfiguredUsage(
    adapters,
    {
      context: TEST_CONTEXT,
      signal: new AbortController().signal,
    },
    { concurrency: 2 },
  );

  assert.equal(results.length, 2);
  assert.equal(
    results[0]?.status === "ready" && results[0].report.providerId,
    "first",
  );
  assert.deepEqual(results[1], {
    status: "error",
    providerId: "failed",
    providerName: "FAILED",
    message: "provider unavailable",
  });
});

test("configuration probe failures remain provider-local", async () => {
  const brokenProbe: UsageProviderAdapter = {
    ...adapter("broken-probe"),
    isConfigured: () => {
      throw new Error("probe failed");
    },
  };
  const results = await queryConfiguredUsage(
    [brokenProbe, adapter("healthy")],
    {
      context: TEST_CONTEXT,
      signal: new AbortController().signal,
    },
  );

  assert.deepEqual(results[0], {
    status: "error",
    providerId: "broken-probe",
    providerName: "BROKEN-PROBE",
    message: "probe failed",
  });
  assert.equal(
    results[1]?.status === "ready" && results[1].report.providerId,
    "healthy",
  );
});

test("configured usage reuses credential-bound cache entries unless forced", async () => {
  const coordinator = new UsageQueryCoordinator();
  let preparations = 0;
  let executions = 0;
  const cached: UsageProviderAdapter = {
    ...adapter("cached"),
    prepare: async () => {
      preparations += 1;
      return {
        cacheKey: "account-a",
        execute: async () => {
          executions += 1;
          return report("cached");
        },
      };
    },
  };
  const queryContext = {
    context: TEST_CONTEXT,
    signal: new AbortController().signal,
  };

  await queryConfiguredUsage([cached], queryContext, { coordinator });
  await queryConfiguredUsage([cached], queryContext, { coordinator });
  await queryConfiguredUsage([cached], queryContext, {
    coordinator,
    forceRefresh: true,
  });

  assert.equal(preparations, 3);
  assert.equal(executions, 2);
});

test("configured usage enforces bounded concurrency", async () => {
  let active = 0;
  let maximumActive = 0;
  const adapters = Array.from({ length: 5 }, (_value, index) =>
    adapter(`provider-${index}`, {
      execute: async () => {
        active += 1;
        maximumActive = Math.max(maximumActive, active);
        await new Promise((resolve) => setTimeout(resolve, 5));
        active -= 1;
        return report(`provider-${index}`);
      },
    }),
  );

  await queryConfiguredUsage(
    adapters,
    {
      context: TEST_CONTEXT,
      signal: new AbortController().signal,
    },
    { concurrency: 2 },
  );

  assert.equal(maximumActive, 2);
});

test("provider-local aborts and deadlines remain partial failures", async () => {
  const localAbort = adapter("local-abort", {
    execute: async () => {
      throw Object.assign(new Error("provider stopped"), {
        name: "AbortError",
      });
    },
  });
  const stalled = adapter("stalled", {
    execute: async () => new Promise<UsageReport>(() => undefined),
  });

  const results = await queryConfiguredUsage(
    [localAbort, stalled, adapter("healthy")],
    {
      context: TEST_CONTEXT,
      signal: new AbortController().signal,
    },
    { concurrency: 3, providerTimeoutMs: 5 },
  );

  assert.equal(results[0]?.status, "error");
  assert.equal(
    results[0]?.status === "error" && results[0].message,
    "provider stopped",
  );
  assert.match(
    results[1]?.status === "error" ? results[1].message : "",
    /timed out after 5ms/u,
  );
  assert.equal(results[2]?.status, "ready");
});

test("configured usage propagates cancellation instead of reporting provider failure", async () => {
  const controller = new AbortController();
  controller.abort();

  await assert.rejects(
    queryConfiguredUsage([adapter("codex")], {
      context: TEST_CONTEXT,
      signal: controller.signal,
    }),
    (error: unknown) => error instanceof Error && error.name === "AbortError",
  );
});
