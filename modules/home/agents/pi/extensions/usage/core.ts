import { createHmac, randomBytes } from "node:crypto";
import type { ExtensionContext } from "@earendil-works/pi-coding-agent";

type ResolvedRequestAuth = Awaited<
  ReturnType<ExtensionContext["modelRegistry"]["getApiKeyAndHeaders"]>
>;

const MAX_SUCCESS_BYTES = 64 * 1024;
const MAX_ERROR_BYTES = 4 * 1024;
const DEFAULT_TIMEOUT_MS = 15_000;
const AUTH_FINGERPRINT_SALT = randomBytes(32);

/** Authentication narrowed to headers safe for one validated official origin. */
export interface UsageRequestAuth {
  origin: string;
  headers: Readonly<Record<string, string>>;
  fingerprint: string;
  secrets: readonly string[];
}

/** Injectable fetch signature used by deterministic transport checks. */
export type UsageFetch = (
  input: string | URL | Request,
  init?: RequestInit,
) => Promise<Response>;

/** Returns whether Pi currently has authentication configured for a provider. */
export function providerIsConfigured(
  context: ExtensionContext,
  providerId: string,
): boolean {
  try {
    return context.modelRegistry.getProviderAuthStatus(providerId).configured;
  } catch {
    return false;
  }
}

/**
 * Resolves request authentication only after every current, provider, and
 * resolved-auth base URL has been proven to use the expected HTTPS origin.
 */
export async function resolveOfficialProviderAuth(
  context: ExtensionContext,
  providerId: string,
  officialOrigin: string,
): Promise<UsageRequestAuth> {
  const currentModel =
    context.model?.provider === providerId ? context.model : undefined;
  if (currentModel)
    assertOfficialOrigin(currentModel.baseUrl, officialOrigin, "current model");

  const provider = context.modelRegistry.getProvider(providerId);
  if (!provider) throw new Error(`Provider ${providerId} is unavailable.`);
  assertOfficialOrigin(provider.baseUrl, officialOrigin, "provider");

  let resolved: Extract<ResolvedRequestAuth, { ok: true }> | undefined;
  if (currentModel) {
    const currentAuth =
      await context.modelRegistry.getApiKeyAndHeaders(currentModel);
    if (!currentAuth.ok)
      throw new Error(sanitizeDisplayText(currentAuth.error));
    resolved = currentAuth;
  } else {
    const providerAuth =
      await context.modelRegistry.getProviderAuth(providerId);
    if (providerAuth) {
      resolved = {
        ok: true,
        apiKey: providerAuth.auth.apiKey,
        headers: providerAuth.auth.headers,
        baseUrl: providerAuth.auth.baseUrl,
        env: providerAuth.env,
      };
    }
  }

  if (!resolved)
    throw new Error(`No runtime credential is configured for ${providerId}.`);
  if (resolved.baseUrl)
    assertOfficialOrigin(
      resolved.baseUrl,
      officialOrigin,
      "resolved authentication",
    );

  const authorization =
    headerValue(resolved.headers, "Authorization") ??
    (resolved.apiKey ? `Bearer ${resolved.apiKey}` : undefined);
  if (!authorization)
    throw new Error(
      `Provider ${providerId} did not resolve Bearer authentication.`,
    );

  const secrets = [
    resolved.apiKey,
    headerValue(resolved.headers, "Authorization"),
    authorization,
    ...Object.values(resolved.env ?? {}),
  ].filter((value): value is string => Boolean(value));
  const headers = { Authorization: authorization };

  return {
    origin: officialOrigin,
    headers,
    fingerprint: fingerprintAuth(providerId, officialOrigin, headers),
    secrets: [...new Set(secrets)],
  };
}

/** Fetches one bounded JSON object without following redirects. */
export async function fetchUsageJson(
  url: string,
  auth: UsageRequestAuth,
  signal: AbortSignal,
  fetchImplementation: UsageFetch = fetch,
  timeoutMs = DEFAULT_TIMEOUT_MS,
): Promise<Record<string, unknown>> {
  assertPositiveTimeout(timeoutMs);
  assertOfficialOrigin(url, auth.origin, "usage endpoint");
  if (signal.aborted) throw abortError();

  const controller = new AbortController();
  let timedOut = false;
  const relayAbort = () => controller.abort(signal.reason);
  if (signal.aborted) relayAbort();
  else signal.addEventListener("abort", relayAbort, { once: true });
  const timeout = setTimeout(() => {
    timedOut = true;
    controller.abort(
      new DOMException("Usage request timed out", "TimeoutError"),
    );
  }, timeoutMs);
  timeout.unref?.();

  try {
    const response = await fetchImplementation(url, {
      headers: { ...auth.headers, "User-Agent": "pi-local-usage" },
      redirect: "error",
      signal: controller.signal,
    });
    if (response.redirected)
      throw new Error("Usage endpoint returned a redirect.");

    const body = await readBoundedBody(
      response,
      response.ok ? MAX_SUCCESS_BYTES : MAX_ERROR_BYTES,
      controller.signal,
    );
    if (!response.ok) {
      throw new Error(
        `Usage endpoint returned ${response.status} ${response.statusText}: ${body}`,
      );
    }

    let payload: unknown;
    try {
      payload = JSON.parse(body) as unknown;
    } catch {
      throw new Error("Usage endpoint returned invalid JSON.");
    }
    if (!isRecord(payload))
      throw new Error("Usage endpoint response was not an object.");

    return payload;
  } catch (error) {
    if (timedOut)
      throw new Error(`Usage request timed out after ${timeoutMs}ms.`);
    if (signal.aborted) throw abortError();
    throw new Error(redactUsageError(errorMessage(error), auth.secrets));
  } finally {
    clearTimeout(timeout);
    signal.removeEventListener("abort", relayAbort);
  }
}

/** Removes terminal control sequences and bounds untrusted display text. */
export function sanitizeDisplayText(
  value: string,
  maxCharacters = 600,
): string {
  const plain = value
    .replace(/\u001b\][^\u0007]*(?:\u0007|\u001b\\)/gu, "")
    .replace(/\u001b\[[0-?]*[ -/]*[@-~]/gu, "")
    .replace(/[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f-\u009f]/gu, "")
    .replace(/\s+/gu, " ")
    .trim();
  if (plain.length <= maxCharacters) return plain;
  return `${plain.slice(0, Math.max(0, maxCharacters - 1))}…`;
}

/** Redacts known secrets and common bearer-token shapes from an error. */
export function redactUsageError(
  value: string,
  secrets: readonly string[] = [],
): string {
  let redacted = value;
  for (const secret of [...new Set(secrets)]
    .filter(Boolean)
    .sort((a, b) => b.length - a.length)) {
    redacted = redacted.replaceAll(secret, "<redacted>");
  }
  redacted = redacted.replace(
    /Bearer\s+[A-Za-z0-9._~+/=-]+/giu,
    "Bearer <redacted>",
  );
  return sanitizeDisplayText(redacted);
}

/** Returns a stable, terminal-safe message for an unknown thrown value. */
export function errorMessage(error: unknown): string {
  return sanitizeDisplayText(
    error instanceof Error ? error.message : String(error),
  );
}

/** Creates the standard cancellation error used by the usage orchestrator. */
export function abortError(): Error {
  return Object.assign(new Error("Usage query cancelled."), {
    name: "AbortError",
  });
}

async function readBoundedBody(
  response: Response,
  maximumBytes: number,
  signal: AbortSignal,
): Promise<string> {
  if (!response.body) return "";

  const reader = response.body.getReader();
  const chunks: Uint8Array[] = [];
  let totalBytes = 0;
  const cancelReader = () => void reader.cancel().catch(() => undefined);
  if (signal.aborted) cancelReader();
  else signal.addEventListener("abort", cancelReader, { once: true });

  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      if (totalBytes + value.byteLength > maximumBytes) {
        await reader.cancel();
        throw new Error(
          `Usage endpoint response exceeded ${maximumBytes} bytes.`,
        );
      }
      chunks.push(value);
      totalBytes += value.byteLength;
    }
  } finally {
    signal.removeEventListener("abort", cancelReader);
    reader.releaseLock();
  }

  const body = new Uint8Array(totalBytes);
  let offset = 0;
  for (const chunk of chunks) {
    body.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return new TextDecoder().decode(body);
}

function assertOfficialOrigin(
  value: string | undefined,
  expectedOrigin: string,
  source: string,
): void {
  try {
    if (value && new URL(value).origin === expectedOrigin) return;
  } catch {
    // The stable error below intentionally excludes the untrusted URL.
  }
  throw new Error(
    `Refusing to send credentials because the ${source} does not use ${expectedOrigin}.`,
  );
}

function headerValue(
  headers: Readonly<Record<string, string | null>> | undefined,
  name: string,
): string | undefined {
  return (
    Object.entries(headers ?? {}).find(
      ([candidate]) => candidate.toLowerCase() === name.toLowerCase(),
    )?.[1] ?? undefined
  );
}

function fingerprintAuth(
  providerId: string,
  officialOrigin: string,
  headers: Readonly<Record<string, string>>,
): string {
  const canonicalHeaders = Object.entries(headers)
    .map(([name, value]) => [name.toLowerCase(), value] as const)
    .sort(([left], [right]) => left.localeCompare(right));
  return createHmac("sha256", AUTH_FINGERPRINT_SALT)
    .update(
      JSON.stringify({ providerId, officialOrigin, headers: canonicalHeaders }),
    )
    .digest("hex");
}

function assertPositiveTimeout(timeoutMs: number): void {
  if (!Number.isFinite(timeoutMs) || timeoutMs <= 0) {
    throw new Error("Usage request timeout must be positive.");
  }
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
