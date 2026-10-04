import assert from "node:assert/strict";
import test from "node:test";
import {
  assistantTextPreview,
  toolOutputPreview,
  toolPreview,
} from "./tool-preview.ts";

test("file and search previews expose targets but never file payloads", () => {
  assert.equal(
    toolPreview(
      "read",
      { path: "/repo/src/main.ts", offset: 10, limit: 5 },
      "/repo",
    ),
    "read  src/main.ts:10–14".replace(/\s+/g, " "),
  );
  assert.equal(
    toolPreview(
      "write",
      { path: "src/main.ts", content: "secret payload" },
      "/repo",
    ),
    "write src/main.ts",
  );
  assert.equal(
    toolPreview(
      "edit",
      { path: "src/main.ts", edits: [{ newText: "secret payload" }] },
      "/repo",
    ),
    "edit src/main.ts",
  );
  assert.equal(
    toolPreview(
      "grep",
      { pattern: "authenticate", path: "/repo/src" },
      "/repo",
    ),
    "grep authenticate · src",
  );
  assert.equal(
    toolPreview("find", { pattern: "*.ts" }, "/repo"),
    "find *.ts · .",
  );
});

test("command previews sanitize controls and common credential forms before clipping", () => {
  const preview = toolPreview(
    "bash",
    {
      command:
        "TOKEN=abc curl -H 'Authorization: Bearer xyz' https://user:password@example.com --api-key 'private key'\n echo \x1b[31mhello\x1b[0m",
    },
    "/repo",
  );
  assert.doesNotMatch(preview, /abc|xyz|user:password|private key|\x1b|\n/);
  assert.match(preview, /hello/);
  assert.ok(
    toolPreview("bash", { command: "x".repeat(1000) }, "/repo").length <= 600,
  );
});

test("quoted JSON credential keys are redacted from commands", () => {
  const command = `curl -d '{"password":"hunter2","api_key":"private value","secret":"escaped\\\"value"}'`;
  const preview = toolPreview("bash", { command }, "/repo");
  assert.doesNotMatch(preview, /hunter2|private value|escaped|value/);
  assert.match(preview, /<redacted>/);
});

test("safe output summaries are bounded to discovery tools and six lines", () => {
  const result = {
    content: [
      {
        type: "text",
        text: "one\ntwo\nthree\nfour\nfive\nsix\nseven TOKEN=secret",
      },
    ],
  };
  assert.equal(
    toolOutputPreview("bash", result),
    "one\ntwo\nthree\nfour\nfive\nsix",
  );
  assert.equal(toolOutputPreview("read", result), undefined);
  assert.equal(toolOutputPreview("custom", result), undefined);
  assert.equal(
    toolOutputPreview("bash", { content: [{ type: "image", data: "secret" }] }),
    undefined,
  );
  assert.equal(
    assistantTextPreview("Visible\ncommentary\x1b[31m"),
    "Visible\ncommentary",
  );
});

test("unknown tools expose argument names only and tolerate missing arguments", () => {
  assert.equal(
    toolPreview(
      "custom",
      { query: "private data", token: "secret", content: "payload" },
      "/repo",
    ),
    "custom query=… token=<redacted> content=…",
  );
  assert.equal(toolPreview("custom", null, "/repo"), "custom");
});
