import assert from "node:assert/strict";
import test from "node:test";

import { UsageQueryCoordinator } from "./cache.ts";
import type { PreparedUsageQuery, UsageReport } from "./types.ts";

function report(providerId: string, capturedAt: number): UsageReport {
  return {
    providerId,
    providerName: providerId,
    semantics: "test semantics",
    capturedAt,
    sections: [{ rows: [{ label: "Remaining", value: "50%" }] }],
  };
}

function prepared(
  cacheKey: string,
  execute: PreparedUsageQuery["execute"],
): PreparedUsageQuery {
  return { cacheKey, execute };
}

test("usage cache serves fresh reports and refreshes stale or forced entries", async () => {
  let now = 1_000;
  let executions = 0;
  const coordinator = new UsageQueryCoordinator(100, 4, () => now);
  const query = prepared("account-a", async () => {
    executions += 1;
    return report("provider", now);
  });
  const signal = new AbortController().signal;

  const first = await coordinator.query("provider", query, signal);
  now += 50;
  const second = await coordinator.query("provider", query, signal);
  assert.equal(second.report, first.report);
  assert.equal(first.provenance.source, "provider");
  assert.equal(second.provenance.source, "cache");
  assert.equal(second.provenance.ageMs, 50);
  assert.equal(executions, 1);
  assert.equal(coordinator.lookup("provider", "account-a").status, "fresh");

  now += 101;
  assert.equal(coordinator.lookup("provider", "account-a").status, "stale");
  assert.equal(coordinator.lookup("provider", "account-a").status, "missing");
  await coordinator.query("provider", query, signal);
  assert.equal(executions, 2);

  await coordinator.query("provider", query, signal, true);
  assert.equal(executions, 3);
});

test("usage cache expiry timer removes reports without a later cache access", async () => {
  const coordinator = new UsageQueryCoordinator(5);
  const signal = new AbortController().signal;
  await coordinator.query(
    "provider",
    prepared("account-a", async () => report("provider", 1)),
    signal,
  );

  await new Promise((resolve) => setTimeout(resolve, 20));
  assert.equal(coordinator.lookup("provider", "account-a").status, "missing");
});

test("usage cache isolates credential identities and provider invalidation", async () => {
  const coordinator = new UsageQueryCoordinator();
  const signal = new AbortController().signal;
  await coordinator.query(
    "provider",
    prepared("account-a", async () => report("provider", 1)),
    signal,
  );
  await coordinator.query(
    "provider",
    prepared("account-b", async () => report("provider", 2)),
    signal,
  );

  assert.equal(coordinator.lookup("provider", "account-a").status, "fresh");
  assert.equal(coordinator.lookup("provider", "account-b").status, "fresh");
  coordinator.clearProvider("provider");
  assert.equal(coordinator.lookup("provider", "account-a").status, "missing");
  assert.equal(coordinator.lookup("provider", "account-b").status, "missing");
});

test("usage cache expires rolled-back clocks and evicts its oldest identity", async () => {
  let now = 1_000;
  const coordinator = new UsageQueryCoordinator(100, 1, () => now);
  const signal = new AbortController().signal;
  await coordinator.query(
    "provider",
    prepared("account-a", async () => report("provider", 1)),
    signal,
  );

  now = 999;
  assert.equal(coordinator.lookup("provider", "account-a").status, "stale");
  assert.equal(coordinator.lookup("provider", "account-a").status, "missing");

  now = 1_000;
  await coordinator.query(
    "provider",
    prepared("account-a", async () => report("provider", 2)),
    signal,
  );
  await coordinator.query(
    "provider",
    prepared("account-b", async () => report("provider", 3)),
    signal,
  );
  assert.equal(coordinator.lookup("provider", "account-a").status, "missing");
  assert.equal(coordinator.lookup("provider", "account-b").status, "fresh");
});

test("in-flight usage queries are shared without one consumer cancelling another", async () => {
  const coordinator = new UsageQueryCoordinator();
  const firstController = new AbortController();
  const secondController = new AbortController();
  let executions = 0;
  let complete: (() => void) | undefined;
  let executionWasAborted = false;
  const query = prepared(
    "account-a",
    (signal) =>
      new Promise<UsageReport>((resolve, reject) => {
        executions += 1;
        complete = () => resolve(report("provider", 1));
        signal.addEventListener(
          "abort",
          () => {
            executionWasAborted = true;
            reject(Object.assign(new Error("aborted"), { name: "AbortError" }));
          },
          { once: true },
        );
      }),
  );

  const first = coordinator.query("provider", query, firstController.signal);
  const second = coordinator.query("provider", query, secondController.signal);
  await Promise.resolve();
  firstController.abort();

  await assert.rejects(
    first,
    (error: unknown) => error instanceof Error && error.name === "AbortError",
  );
  complete?.();
  assert.equal((await second).report.providerId, "provider");
  assert.equal(executions, 1);
  assert.equal(executionWasAborted, false);
});

test("the final cancelled consumer aborts an uncached provider query", async () => {
  const coordinator = new UsageQueryCoordinator();
  const controller = new AbortController();
  let executionWasAborted = false;
  const query = prepared(
    "account-a",
    (signal) =>
      new Promise<UsageReport>((_resolve, reject) => {
        signal.addEventListener(
          "abort",
          () => {
            executionWasAborted = true;
            reject(Object.assign(new Error("aborted"), { name: "AbortError" }));
          },
          { once: true },
        );
      }),
  );

  const pending = coordinator.query("provider", query, controller.signal);
  await Promise.resolve();
  controller.abort();
  await assert.rejects(pending);
  await Promise.resolve();

  assert.equal(executionWasAborted, true);
  assert.equal(coordinator.lookup("provider", "account-a").status, "missing");
});

test("a cancelled abort-ignoring query detaches so retries can succeed", async () => {
  const coordinator = new UsageQueryCoordinator();
  const firstController = new AbortController();
  const retryController = new AbortController();
  const completions: Array<(value: UsageReport) => void> = [];
  let executions = 0;
  const query = prepared(
    "account-a",
    async () =>
      new Promise<UsageReport>((resolve) => {
        executions += 1;
        completions.push(resolve);
      }),
  );

  const first = coordinator.query("provider", query, firstController.signal);
  await Promise.resolve();
  firstController.abort();
  await assert.rejects(first);

  const retry = coordinator.query("provider", query, retryController.signal);
  await Promise.resolve();
  completions[1]?.(report("provider", 2));
  assert.equal((await retry).report.capturedAt, 2);
  assert.equal(executions, 2);

  completions[0]?.(report("provider", 1));
  await Promise.resolve();
  const cached = coordinator.lookup("provider", "account-a");
  assert.equal(cached.status === "fresh" && cached.report.capturedAt, 2);
});
