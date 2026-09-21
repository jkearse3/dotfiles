import assert from "node:assert/strict";
import test from "node:test";
import type { ExtensionContext } from "@earendil-works/pi-coding-agent";

import {
  fetchUsageJson,
  redactUsageError,
  resolveOfficialProviderAuth,
  sanitizeDisplayText,
  type UsageRequestAuth,
} from "./core.ts";

const TEST_AUTH: UsageRequestAuth = {
  origin: "https://chatgpt.com",
  headers: { Authorization: "Bearer secret-token" },
  fingerprint: "test-fingerprint",
  secrets: ["secret-token", "Bearer secret-token"],
};

test("official auth resolution rejects a custom model origin before reading credentials", async () => {
  let authReads = 0;
  const context = {
    model: {
      provider: "openai-codex",
      baseUrl: "https://proxy.example.test/backend-api",
    },
    modelRegistry: {
      getProvider: () => ({ baseUrl: "https://chatgpt.com/backend-api" }),
      getApiKeyAndHeaders: async () => {
        authReads += 1;
        return { ok: true as const, apiKey: "must-not-be-read" };
      },
    },
  } as unknown as ExtensionContext;

  await assert.rejects(
    resolveOfficialProviderAuth(context, "openai-codex", "https://chatgpt.com"),
    /current model does not use https:\/\/chatgpt\.com/u,
  );
  assert.equal(authReads, 0);
});

test("official auth resolution narrows current model auth to Authorization", async () => {
  const context = {
    model: {
      provider: "openai-codex",
      baseUrl: "https://chatgpt.com/backend-api",
    },
    modelRegistry: {
      getProvider: () => ({ baseUrl: "https://chatgpt.com/backend-api" }),
      getApiKeyAndHeaders: async () => ({
        ok: true as const,
        apiKey: "secret-token",
        headers: { "X-Unrelated": "must-not-be-forwarded" },
        baseUrl: "https://chatgpt.com/backend-api",
      }),
    },
  } as unknown as ExtensionContext;

  const auth = await resolveOfficialProviderAuth(
    context,
    "openai-codex",
    "https://chatgpt.com",
  );

  assert.deepEqual(auth.headers, { Authorization: "Bearer secret-token" });
  assert.equal(auth.fingerprint.length, 64);
  assert.ok(auth.secrets.includes("secret-token"));
});

test("bounded usage fetch refuses redirects and sends only narrowed headers", async () => {
  let request: RequestInit | undefined;
  const payload = await fetchUsageJson(
    "https://chatgpt.com/backend-api/wham/usage",
    TEST_AUTH,
    new AbortController().signal,
    async (_input, init) => {
      request = init;
      return new Response(JSON.stringify({ plan_type: "pro" }), {
        status: 200,
      });
    },
  );

  assert.deepEqual(payload, { plan_type: "pro" });
  assert.equal(request?.redirect, "error");
  assert.deepEqual(request?.headers, {
    Authorization: "Bearer secret-token",
    "User-Agent": "pi-local-usage",
  });
});

test("bounded usage fetch rejects an origin mismatch before sending credentials", async () => {
  let fetchCalls = 0;
  await assert.rejects(
    fetchUsageJson(
      "https://proxy.example.test/usage",
      TEST_AUTH,
      new AbortController().signal,
      async () => {
        fetchCalls += 1;
        return new Response("{}");
      },
    ),
    /usage endpoint does not use https:\/\/chatgpt\.com/u,
  );
  assert.equal(fetchCalls, 0);
});

test("usage fetch bounds response bodies and redacts provider errors", async () => {
  await assert.rejects(
    fetchUsageJson(
      "https://chatgpt.com/backend-api/wham/usage",
      TEST_AUTH,
      new AbortController().signal,
      async () => new Response("x".repeat(64 * 1024 + 1)),
    ),
    /exceeded 65536 bytes/u,
  );

  await assert.rejects(
    fetchUsageJson(
      "https://chatgpt.com/backend-api/wham/usage",
      TEST_AUTH,
      new AbortController().signal,
      async () => new Response("Bearer secret-token failed", { status: 401 }),
    ),
    (error: unknown) => {
      assert.ok(error instanceof Error);
      assert.doesNotMatch(error.message, /secret-token/u);
      assert.match(error.message, /<redacted> failed/u);
      return true;
    },
  );
});

test("display sanitization and explicit redaction remove terminal controls", () => {
  assert.equal(sanitizeDisplayText("main\u001b[31m\naccount"), "main account");
  assert.equal(
    redactUsageError("token=abc123 Bearer other-token", ["abc123"]),
    "token=<redacted> Bearer <redacted>",
  );
});
