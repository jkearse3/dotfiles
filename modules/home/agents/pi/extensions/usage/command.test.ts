import assert from "node:assert/strict";
import test from "node:test";

import { handleUsageResultsAction, runUsageCommand } from "./command.ts";

test("usage command refresh forces subsequent loads and close stops", async () => {
  const forceRefreshes: boolean[] = [];
  const actions = ["refresh", "close"] as const;
  let displays = 0;

  await runUsageCommand(
    async (forceRefresh) => {
      forceRefreshes.push(forceRefresh);
      return forceRefreshes.length;
    },
    async () => actions[displays++] ?? "close",
  );

  assert.deepEqual(forceRefreshes, [false, true]);
  assert.equal(displays, 2);
});

test("usage results input completes refresh and close actions", () => {
  const actions: string[] = [];
  const done = (action: "close" | "refresh") => actions.push(action);

  assert.equal(handleUsageResultsAction("r", false, done), true);
  assert.equal(handleUsageResultsAction("q", true, done), true);
  assert.equal(handleUsageResultsAction("x", false, done), false);
  assert.deepEqual(actions, ["refresh", "close"]);
});

test("usage command cancellation does not open the results view", async () => {
  let displays = 0;
  await runUsageCommand(
    async () => undefined,
    async () => {
      displays += 1;
      return "close";
    },
  );

  assert.equal(displays, 0);
});
