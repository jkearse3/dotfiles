import assert from "node:assert/strict";
import {
  existsSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  realpathSync,
  rmSync,
  statSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import test from "node:test";
import {
  SubagentTasks,
  type TaskAssignment,
  type TaskSnapshot,
} from "./tasks.ts";

// A real disposable subprocess exercises framing, process lifetime, and stream ownership.
const CHILD_SCRIPT = `
let prompt = '';
process.stdin.setEncoding('utf8');
process.stdin.on('data', chunk => prompt += chunk);
process.stdin.on('end', () => {
  const emit = event => process.stdout.write(JSON.stringify(event) + '\\n');
  const usage = () => ({
    input: 2, output: 3, cacheRead: 4, cacheWrite: 5,
    cacheWrite1h: 2, reasoning: 1, totalTokens: 14,
    cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, total: 0.1 }
  });
  const message = (text, stopReason = 'stop') => emit({
    type: 'message_end',
    message: {
      role: 'assistant', content: [{ type: 'text', text }], stopReason,
      errorMessage: stopReason === 'error' ? 'provider failed' : undefined,
      usage: usage()
    }
  });
  emit({ type: 'session', version: 3 });
  emit({ type: 'agent_start' });
  if (prompt === 'descendant') {
    const { spawn } = require('node:child_process');
    const fs = require('node:fs');
    const grandchild = spawn(process.execPath, ['-e', \`
      const fs = require('node:fs');
      process.on('SIGTERM', () => {});
      fs.writeFileSync('grandchild.pid', String(process.pid));
      let tick = 0;
      setInterval(() => fs.writeFileSync('heartbeat.txt', String(++tick)), 10);
    \`], { stdio: 'ignore' });
    grandchild.unref();
    setInterval(() => {}, 1000);
    return;
  }
  if (prompt === 'hang' || prompt === 'ignore-term') {
    if (prompt === 'ignore-term') process.on('SIGTERM', () => {});
    emit({ type: 'tool_execution_start', toolCallId: 'read-1', toolName: 'read', args: { secret: 'not in summary' } });
    setInterval(() => {}, 1000);
    return;
  }
  if (prompt === 'parallel-tools') {
    for (let i = 0; i < 70; i++) emit({ type: 'tool_execution_start', toolCallId: String(i), toolName: 'read', args: { path: 'file-' + i } });
    for (let i = 69; i >= 0; i--) emit({ type: 'tool_execution_end', toolCallId: String(i), toolName: 'read', isError: i === 65 });
    message('verified'); emit({ type: 'agent_settled' }); return;
  }
  if (prompt === 'bad-json') { process.stdout.write('not JSON\\n'); return; }
  if (prompt === 'oversized') { process.stdout.write('x'.repeat(9 * 1024 * 1024)); return; }
  if (prompt === 'stderr') { process.stderr.write('startup diagnostic'); process.exitCode = 2; return; }
  if (prompt === 'empty') { message(''); emit({ type: 'agent_settled' }); return; }
  if (prompt === 'intermediate') { message('stale reply'); return; }
  if (prompt === 'error') { message('partial reply', 'error'); emit({ type: 'agent_settled' }); return; }
  if (prompt === 'recovery') {
    message('old error', 'error'); emit({ type: 'agent_end' });
    emit({ type: 'auto_retry_start' }); emit({ type: 'agent_start' });
  }
  if (prompt === 'compaction') emit({
    type: 'compaction_end', result: { usage: usage() }
  });
  emit({ type: 'tool_execution_start', toolCallId: 'grep-1', toolName: 'grep', args: { pattern: 'authenticate', path: 'src' } });
  emit({ type: 'tool_execution_end', toolCallId: 'grep-1', toolName: 'grep', result: {
    content: [{ type: 'text', text: 'src/auth.ts:10: authenticate' }],
    ...(prompt === 'tool-usage' ? { usage: usage() } : {})
  }, isError: false });
  if (prompt === 'tool-usage') emit({
    type: 'tool_execution_end', toolCallId: 'nested-1', toolName: 'model-tool',
    parentToolCallId: 'grep-1', result: { content: [], usage: usage() }, isError: false
  });
  message('intermediate commentary', 'toolUse');
  message(prompt === 'long' ? 'x'.repeat(20000) : JSON.stringify({
    prompt: prompt + ' 😀\\u2028\\u2029', args: process.argv.slice(1),
    cwd: process.cwd(), herdr: process.env.HERDR_PANE_ID,
    parentSession: process.env.PI_SESSION_ID, delegated: process.env.PI_SUBAGENT
  }));
  emit({ type: 'agent_end' });
  emit({ type: 'agent_settled' });
});
`;

function fixture() {
  const cwd = mkdtempSync(path.join(tmpdir(), "pi-subagent-test-"));
  const managedSkillsDir = path.join(cwd, "managed-skills");
  const fixtureSkillDir = path.join(managedSkillsDir, "fixture-skill");
  mkdirSync(fixtureSkillDir, { recursive: true });
  writeFileSync(
    path.join(fixtureSkillDir, "SKILL.md"),
    "---\nname: fixture-skill\ndescription: Fixture skill sentinel\n---\nFixture instructions.\n",
  );
  const tasks = new SubagentTasks(
    {
      command: process.execPath,
      args: ["-e", CHILD_SCRIPT, "--"],
    },
    managedSkillsDir,
  );
  const assignment = (prompt: string): TaskAssignment => ({
    label: "test",
    prompt,
    cwd,
    model: "provider/model",
    thinking: "medium",
    tools: ["read", "grep", "find", "ls"],
    extensions: false,
    skills: [],
  });
  return {
    tasks,
    assignment,
    cleanup: async () => {
      await tasks.shutdown();
      rmSync(cwd, { recursive: true, force: true });
    },
  };
}

test("foreground run streams one task and automatically collects its response and usage", async () => {
  const f = fixture();
  const updates: TaskSnapshot[] = [];
  try {
    const result = await f.tasks.run(
      f.assignment("assignment"),
      undefined,
      (task) => updates.push(task),
    );
    assert.equal(updates[0]!.status, "running");
    assert.equal(updates.at(-1)!.status, "completed");
    assert.equal(new Set(updates.map((task) => task.taskId)).size, 1);
    assert.ok(updates.some((task) => task.activity.includes("tool: grep")));
    assert.equal(result.tasks[0]!.status, "completed");
    assert.ok(
      updates.some((task) => task.toolCalls?.[0]?.status === "running"),
    );
    assert.deepEqual(result.tasks[0]!.toolCalls, [
      { id: "grep-1", preview: "grep authenticate · src", status: "completed" },
    ]);
    assert.deepEqual(result.tasks[0]!.transcript, [
      {
        kind: "tool",
        id: "grep-1",
        preview: "grep authenticate · src",
        status: "completed",
        output: "src/auth.ts:10: authenticate",
      },
      { kind: "assistant", text: "intermediate commentary" },
    ]);
    assert.equal(result.usage!.input, 4);
    assert.equal(result.usage!.reasoning, 2);
    assert.equal(result.usage!.cacheWrite1h, 4);
    assert.deepEqual(result.tasks[0]!.usageDiagnostics, {
      totals: result.usage,
      overallCacheHitRate: (8 / 22) * 100,
      latestCacheHitRate: (4 / 11) * 100,
      compactionCount: 0,
    });
    assert.equal(updates[0]!.usageDiagnostics, undefined);
    assert.equal(
      JSON.parse(result.result!).prompt,
      "assignment 😀\u2028\u2029",
    );
    assert.equal(
      (await f.tasks.result(result.tasks[0]!.taskId)).usage,
      undefined,
    );
  } finally {
    await f.cleanup();
  }
});

test("top-level tool usage is counted once while nested usage rolls into its parent", async () => {
  const f = fixture();
  try {
    const result = await f.tasks.run(f.assignment("tool-usage"));
    assert.equal(result.usage!.input, 6);
    assert.equal(result.usage!.output, 9);
    assert.equal(result.usage!.cacheRead, 12);
    assert.equal(result.usage!.reasoning, 3);
    assert.equal(result.tasks[0]!.usageDiagnostics!.totals.input, 6);
  } finally {
    await f.cleanup();
  }
});

test("durable conversations use an exact session file and publish the child PID", async () => {
  const f = fixture();
  const sessionFile = path.join(f.assignment("").cwd, "child-session.jsonl");
  writeFileSync(sessionFile, "", { mode: 0o600 });
  let spawnedPid: number | undefined;
  try {
    const result = await f.tasks.run(
      {
        ...f.assignment("assignment"),
        conversationSessionFile: sessionFile,
      },
      undefined,
      undefined,
      (pid) => {
        spawnedPid = pid;
      },
    );
    const args: string[] = JSON.parse(result.result!).args;
    assert.ok(spawnedPid && spawnedPid > 0);
    assert.equal(args.includes("--no-session"), false);
    assert.equal(args[args.indexOf("--session") + 1], sessionFile);
  } finally {
    await f.cleanup();
  }
});

test("recent call tracking is bounded and resolves concurrent same-tool calls by ID", async () => {
  const f = fixture();
  try {
    const result = await f.tasks.run(f.assignment("parallel-tools"));
    const calls = result.tasks[0]!.toolCalls!;
    assert.deepEqual(
      calls.map((call) => call.id),
      ["62", "63", "64", "65", "66", "67", "68", "69"],
    );
    assert.equal(calls[3]!.status, "failed");
    assert.ok(
      calls
        .filter((call) => call.id !== "65")
        .every((call) => call.status === "completed"),
    );
    assert.equal(result.tasks[0]!.transcript!.length, 64);
    assert.equal(result.tasks[0]!.transcriptOmitted, 6);
  } finally {
    await f.cleanup();
  }
});

test("foreground abort refreshes elapsed time, stops the process group, and returns cancellation usage", async () => {
  const f = fixture();
  const controller = new AbortController();
  const updates: TaskSnapshot[] = [];
  try {
    const run = f.tasks.run(
      f.assignment("ignore-term"),
      controller.signal,
      (task) => updates.push(task),
    );
    await new Promise((resolve) => setTimeout(resolve, 1150));
    assert.ok(updates.some((task) => task.elapsedSeconds >= 1));
    controller.abort();
    const result = await run;
    assert.equal(result.tasks[0]!.status, "cancelled");
    assert.equal(result.tasks[0]!.toolCalls?.[0]?.status, "cancelled");
    assert.ok(result.usage);
    const count = updates.length;
    await new Promise((resolve) => setTimeout(resolve, 1050));
    assert.equal(
      updates.length,
      count,
      "no progress timer survives completion",
    );
  } finally {
    await f.cleanup();
  }
});

test("foreground runs handle pre-abort, startup abort races, failures, and broken observers", async () => {
  const f = fixture();
  try {
    await assert.rejects(
      f.tasks.run(f.assignment("hang"), AbortSignal.abort()),
      /before start/u,
    );
    assert.equal(f.tasks.status().length, 0);
    const controller = new AbortController();
    const cancelled = await f.tasks.run(
      f.assignment("hang"),
      controller.signal,
      () => controller.abort(),
    );
    assert.equal(cancelled.tasks[0]!.status, "cancelled");
    const failed = await f.tasks.run(f.assignment("error"));
    assert.equal(failed.tasks[0]!.status, "failed");
    assert.equal(failed.usage!.input, 2);
    let calls = 0;
    const complete = await f.tasks.run(
      f.assignment("assignment"),
      undefined,
      () => {
        calls++;
        throw new Error("broken progress view");
      },
    );
    assert.equal(complete.tasks[0]!.status, "completed");
    assert.equal(calls, 1);
    const ownershipFailure = await f.tasks.run(
      f.assignment("hang"),
      undefined,
      undefined,
      () => {
        throw new Error("lock write failed");
      },
    );
    assert.equal(ownershipFailure.tasks[0]!.status, "failed");
    assert.match(
      ownershipFailure.tasks[0]!.error ?? "",
      /Could not record child ownership/u,
    );
  } finally {
    await f.cleanup();
  }
});

test("session shutdown settles an in-flight foreground run before removing its registry", async () => {
  const f = fixture();
  try {
    const run = f.tasks.run(f.assignment("hang"));
    await f.tasks.shutdown();
    const result = await run;
    assert.equal(result.tasks[0]!.status, "cancelled");
    assert.equal(existsSync(result.tasks[0]!.artifactsDir), false);
  } finally {
    await f.cleanup();
  }
});

test("launch captures private artifacts, isolates resources, extracts only final text, and bills usage once", async () => {
  const f = fixture();
  const oldHerdr = process.env.HERDR_PANE_ID;
  const oldSession = process.env.PI_SESSION_ID;
  process.env.HERDR_PANE_ID = "parent-pane";
  process.env.PI_SESSION_ID = "parent-session";
  try {
    const started = f.tasks.start(f.assignment("assignment"));
    assert.equal(started.status, "running");
    const reply = await f.tasks.result(started.taskId, 5);
    assert.equal(reply.tasks[0]!.status, "completed");
    const captured = JSON.parse(reply.result!);
    assert.equal(captured.prompt, "assignment 😀\u2028\u2029");
    assert.equal(captured.herdr, undefined);
    assert.equal(captured.parentSession, undefined);
    assert.equal(captured.delegated, "1");
    assert.equal(captured.cwd, realpathSync(f.assignment("").cwd));
    const args: string[] = captured.args;
    for (const flag of [
      "--no-extensions",
      "--no-skills",
      "--no-session",
      "--no-approve",
    ])
      assert.ok(args.includes(flag));
    assert.equal(args[args.indexOf("--tools") + 1], "read,grep,find,ls");
    assert.equal(args[args.indexOf("--model") + 1], "provider/model");
    assert.equal(args[args.indexOf("--exclude-tools") + 1], "subagent");
    assert.ok(args.includes("--extension"));
    assert.equal(reply.tasks[0]!.extensions, false);
    assert.deepEqual(reply.tasks[0]!.skills, []);
    assert.equal(reply.tasks[0]!.projectTrusted, false);
    assert.equal(args.includes("assignment"), false);
    assert.equal(reply.usage!.input, 4);
    assert.equal(reply.usage!.totalTokens, 28);
    assert.equal((await f.tasks.result(started.taskId)).usage, undefined);
    assert.ok(reply.tasks[0]!.activity.includes("tool: grep finished"));
    assert.ok(!JSON.stringify(reply.tasks[0]!.activity).includes("secret"));
    assert.equal(
      readFileSync(path.join(started.artifactsDir, "task.txt"), "utf8"),
      "assignment",
    );
    assert.equal(
      readFileSync(path.join(started.artifactsDir, "reply.txt"), "utf8"),
      reply.result,
    );
    assert.equal(statSync(started.artifactsDir).mode & 0o077, 0);
    assert.equal(
      statSync(path.join(started.artifactsDir, "events.jsonl")).mode & 0o077,
      0,
    );
    await f.tasks.shutdown();
    assert.equal(existsSync(started.artifactsDir), false);
    await f.tasks.shutdown();
    assert.throws(() => f.tasks.start(f.assignment("new")), /closed/);
  } finally {
    if (oldHerdr === undefined) delete process.env.HERDR_PANE_ID;
    else process.env.HERDR_PANE_ID = oldHerdr;
    if (oldSession === undefined) delete process.env.PI_SESSION_ID;
    else process.env.PI_SESSION_ID = oldSession;
    await f.cleanup();
  }
});

test("default capabilities load configured tools, extensions and skills", async () => {
  const f = fixture();
  try {
    const started = f.tasks.start({
      ...f.assignment("default"),
      tools: undefined,
      extensions: undefined,
      skills: undefined,
      projectTrusted: true,
    });
    const reply = await f.tasks.result(started.taskId, 5);
    const args: string[] = JSON.parse(reply.result!).args;
    for (const flag of [
      "--tools",
      "--no-tools",
      "--no-extensions",
      "--no-skills",
      "--no-approve",
    ]) {
      assert.equal(args.includes(flag), false);
    }
    assert.ok(args.includes("--approve"));
    assert.equal(reply.tasks[0]!.extensions, true);
    assert.equal(reply.tasks[0]!.skills, undefined);
    assert.equal(reply.tasks[0]!.tools, undefined);
  } finally {
    await f.cleanup();
  }
});

test("explicit skills load only named managed skills", async () => {
  const f = fixture();
  try {
    const started = f.tasks.start({
      ...f.assignment("configured skill"),
      skills: ["fixture-skill"],
    });
    const reply = await f.tasks.result(started.taskId, 5);
    const args: string[] = JSON.parse(reply.result!).args;
    assert.ok(args.includes("--no-skills"));
    assert.ok(!args.includes("--skill"));
    const instructionsPath = args[args.indexOf("--append-system-prompt") + 1]!;
    const instructions = readFileSync(instructionsPath, "utf8");
    assert.match(instructions, /<name>fixture-skill<\/name>/);
    assert.match(
      instructions,
      /managed-skills\/fixture-skill\/SKILL\.md<\/location>/,
    );
    assert.deepEqual(reply.tasks[0]!.skills, ["fixture-skill"]);
  } finally {
    await f.cleanup();
  }
});

for (const tools of [[], ["custom_tool"]]) {
  test(`explicit capabilities select ${tools.join(",") || "no tools"}`, async () => {
    const f = fixture();
    try {
      const started = f.tasks.start({
        ...f.assignment("configured"),
        tools,
      });
      const reply = await f.tasks.result(started.taskId, 5);
      const args: string[] = JSON.parse(reply.result!).args;
      if (tools.length)
        assert.equal(args[args.indexOf("--tools") + 1], tools.join(","));
      else {
        assert.ok(args.includes("--no-tools"));
        assert.equal(args.includes("--tools"), false);
      }
      assert.deepEqual(reply.tasks[0]!.tools, tools);
    } finally {
      await f.cleanup();
    }
  });
}

for (const prompt of [
  "error",
  "intermediate",
  "empty",
  "bad-json",
  "stderr",
  "oversized",
]) {
  test(`does not accept ${prompt} as a completed result`, async () => {
    const f = fixture();
    try {
      const started = f.tasks.start(f.assignment(prompt));
      const reply = await f.tasks.result(started.taskId, 5);
      assert.equal(reply.tasks[0]!.status, "failed");
      assert.ok(reply.tasks[0]!.error);
      if (prompt === "error")
        assert.match(reply.tasks[0]!.error!, /provider failed/);
      if (prompt === "stderr")
        assert.equal(
          readFileSync(path.join(started.artifactsDir, "stderr.log"), "utf8"),
          "startup diagnostic",
        );
    } finally {
      await f.cleanup();
    }
  });
}

test("automatic provider recovery can supersede an intermediate error", async () => {
  const f = fixture();
  try {
    const started = f.tasks.start(f.assignment("recovery"));
    const result = await f.tasks.result(started.taskId, 5);
    assert.equal(result.tasks[0]!.status, "completed");
    assert.ok(result.tasks[0]!.activity.includes("provider retry"));
    assert.equal(result.usage!.input, 6);
  } finally {
    await f.cleanup();
  }
});

test("compaction usage is included in once-only task accounting", async () => {
  const f = fixture();
  try {
    const started = f.tasks.start(f.assignment("compaction"));
    const result = await f.tasks.result(started.taskId, 5);
    assert.equal(result.tasks[0]!.status, "completed");
    assert.equal(result.usage!.totalTokens, 42);
    assert.equal(result.usage!.input, 6);
    assert.equal(result.tasks[0]!.usageDiagnostics!.compactionCount, 1);
    assert.equal(result.tasks[0]!.usageDiagnostics!.totals.reasoning, 3);
    assert.ok(Math.abs(result.usage!.cost.total - 0.3) < 1e-10);
    assert.equal((await f.tasks.result(started.taskId)).usage, undefined);
  } finally {
    await f.cleanup();
  }
});

test("cancellation kills a pipe-detached descendant after its leader closes", async () => {
  const f = fixture();
  const cwd = f.assignment("").cwd;
  const pidFile = path.join(cwd, "grandchild.pid");
  const heartbeat = path.join(cwd, "heartbeat.txt");
  let pid: number | undefined;
  try {
    const started = f.tasks.start(f.assignment("descendant"));
    for (let i = 0; i < 200 && !existsSync(heartbeat); i++) {
      await new Promise((resolve) => setTimeout(resolve, 10));
    }
    pid = Number(readFileSync(pidFile, "utf8"));
    assert.ok(pid > 0);
    assert.equal((await f.tasks.cancel(started.taskId)).status, "cancelled");
    await new Promise((resolve) => setTimeout(resolve, 100));
    const stoppedHeartbeat = readFileSync(heartbeat, "utf8");
    await new Promise((resolve) => setTimeout(resolve, 100));
    assert.equal(readFileSync(heartbeat, "utf8"), stoppedHeartbeat);
  } finally {
    if (pid !== undefined) {
      try {
        process.kill(pid, "SIGKILL");
      } catch (error) {
        if ((error as NodeJS.ErrnoException).code !== "ESRCH") throw error;
      }
    }
    await f.cleanup();
  }
});

test("large replies are bounded in the result but complete on disk", async () => {
  const f = fixture();
  try {
    const started = f.tasks.start(f.assignment("long"));
    const result = await f.tasks.result(started.taskId, 5);
    assert.equal(result.result!.length, 16000);
    assert.equal(result.resultTruncated, true);
    assert.equal(
      readFileSync(path.join(started.artifactsDir, "reply.txt"), "utf8").length,
      20000,
    );
  } finally {
    await f.cleanup();
  }
});

test("polling and aborted waits preserve background work; cancellation and shutdown stop it", async () => {
  const f = fixture();
  try {
    const started = f.tasks.start(f.assignment("hang"));
    assert.equal((await f.tasks.result(started.taskId)).result, undefined);
    const controller = new AbortController();
    const waiting = f.tasks.result(started.taskId, 5, controller.signal);
    controller.abort();
    await assert.rejects(waiting, /task remains running/);
    assert.equal(f.tasks.status(started.taskId)[0]!.status, "running");
    assert.equal((await f.tasks.cancel(started.taskId)).status, "cancelled");
    assert.equal((await f.tasks.cancel(started.taskId)).status, "cancelled");
    const other = f.tasks.start(f.assignment("hang"));
    await f.tasks.shutdown();
    assert.equal(existsSync(other.artifactsDir), false);
  } finally {
    await f.cleanup();
  }
});

test("rejects unknown tasks, invalid assignments, excessive concurrency and waits", async () => {
  const f = fixture();
  try {
    assert.throws(() => f.tasks.status("foreign"), /Unknown/);
    for (const tools of [["read,write"], ["subagent"], ["--approve"]]) {
      assert.throws(
        () => f.tasks.start({ ...f.assignment("task"), tools }),
        /valid non-delegating/,
      );
    }
    assert.throws(
      () => f.tasks.start({ ...f.assignment("task"), skills: ["../skill"] }),
      /valid managed skill names/,
    );
    assert.throws(
      () =>
        f.tasks.start({
          ...f.assignment("task"),
          skills: ["fixture-skill", "fixture-skill"],
        }),
      /duplicate names/,
    );
    assert.throws(
      () => f.tasks.start({ ...f.assignment("task"), skills: ["unknown"] }),
      /Unknown managed skill: unknown/,
    );
    assert.throws(() => f.tasks.start(f.assignment(" ")), /empty/);
    assert.throws(
      () => f.tasks.start(f.assignment("x".repeat(256 * 1024 + 1))),
      /256 KiB/,
    );
    const started = f.tasks.start(f.assignment("hang"));
    await assert.rejects(
      f.tasks.result(started.taskId, 61),
      /between 0 and 60/,
    );
    for (let i = 0; i < 3; i++) f.tasks.start(f.assignment("hang"));
    assert.throws(() => f.tasks.start(f.assignment("hang")), /Concurrent/);
    assert.equal(f.tasks.status().length, 4);
  } finally {
    await f.cleanup();
  }
});

test("spawn failures become inspectable failed tasks", async () => {
  const cwd = mkdtempSync(path.join(tmpdir(), "pi-subagent-missing-"));
  const tasks = new SubagentTasks({
    command: path.join(cwd, "missing-executable"),
    args: [],
  });
  try {
    const started = tasks.start({
      label: "missing",
      prompt: "task",
      cwd,
      model: "provider/model",
      thinking: "medium",
    });
    const result = await tasks.result(started.taskId, 5);
    assert.equal(result.tasks[0]!.status, "failed");
    assert.match(
      result.tasks[0]!.error!,
      /Could not run Pi|Prompt delivery failed/,
    );
  } finally {
    await tasks.shutdown();
    rmSync(cwd, { recursive: true, force: true });
  }
});
