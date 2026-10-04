import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import {
  existsSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  readdirSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { createServer } from "node:http";
import { tmpdir } from "node:os";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";
import type { TaskSnapshot } from "./tasks.ts";

const executable = process.env.PI_SUBAGENT_TEST_PI;
const extensionPath = fileURLToPath(new URL("./index.ts", import.meta.url));

type ScenarioName =
  | "read-only"
  | "skill-allowlist"
  | "no-tools"
  | "parallel"
  | "resume"
  | "trusted-project"
  | "other-project"
  | "foreground"
  | "foreground-cancel"
  | "foreground-length";

interface ScenarioConfig {
  name: ScenarioName;
  capabilities?: {
    tools: string[];
    extensions: false;
    skills: string[];
  };
  expectedChildTools?: string[];
  expectedProjectTrusted?: boolean;
  expectedSkill?: boolean;
  approveProject?: boolean;
  useOtherCwd?: boolean;
}

const scenarios: ScenarioConfig[] = [
  {
    name: "read-only",
    capabilities: {
      tools: ["read", "grep", "find", "ls"],
      extensions: false,
      skills: [],
    },
    expectedChildTools: ["find", "grep", "ls", "read"],
  },
  {
    name: "skill-allowlist",
    capabilities: {
      tools: [],
      extensions: false,
      skills: ["fixture-skill"],
    },
    expectedChildTools: [],
    expectedSkill: true,
  },
  {
    name: "no-tools",
    capabilities: { tools: [], extensions: false, skills: [] },
    expectedChildTools: [],
  },
  {
    name: "parallel",
    capabilities: { tools: [], extensions: false, skills: [] },
    expectedChildTools: [],
  },
  {
    name: "resume",
    capabilities: { tools: [], extensions: false, skills: [] },
    expectedChildTools: [],
  },
  {
    name: "trusted-project",
    approveProject: true,
    expectedProjectTrusted: true,
  },
  { name: "other-project", approveProject: true, useOtherCwd: true },
  { name: "foreground" },
  { name: "foreground-cancel" },
  { name: "foreground-length" },
];

// The Nix check supplies the exact Pi used for types and deployment. No real
// provider credentials or project state are read: every request stays on localhost.
for (const config of scenarios) {
  const scenario = config.name;
  test(
    `installed Pi delegation: ${scenario}`,
    { skip: !executable, timeout: 30000 },
    async () => {
      const fixture = createDisposablePiFixture(scenario);
      const { agentDir, cwd, otherCwd, owned, root, seed, uiChecks, uiProbe } =
        fixture;
      const cancelShell = scenario === "foreground-cancel";

      let parentCalls = 0;
      let childCalls = 0;
      let outcome:
        | {
            tasks: TaskSnapshot[];
            result: string;
            conversation?: {
              conversationId: string;
              resumed: boolean;
              resumable: boolean;
            };
          }
        | undefined;
      let initialConversationId: string | undefined;
      let parallelOutcomes: { tasks: TaskSnapshot[]; result: string }[] = [];
      let cancelledHeartbeat: string | undefined;
      const provider = await startLocalProvider(async (body) => {
        const toolNames = body.tools?.map((tool) => tool.function.name) ?? [];
        const isParent = toolNames.includes("subagent");
        let delta: ChatDelta;
        if (isParent) {
          parentCalls++;
          if (parentCalls === 1) {
            const assignment = {
              label: "integration",
              prompt: `You own ${owned} only. Use the provided tools to implement and verify the disposable change. Do not finalize, publish, or delegate.`,
              ...config.capabilities,
              ...(config.useOtherCwd ? { cwd: otherCwd } : {}),
            };
            delta =
              scenario === "parallel"
                ? toolCalls("subagent", [
                    { ...assignment, label: "parallel-a" },
                    { ...assignment, label: "parallel-b" },
                  ])
                : toolCall("subagent", assignment);
          } else if (scenario === "resume" && parentCalls === 2) {
            const initial = JSON.parse(lastToolContent(body));
            initialConversationId = initial.conversation?.conversationId;
            assert.ok(initialConversationId);
            assert.equal(initial.conversation.resumed, false);
            delta = toolCall("subagent", {
              label: "integration-follow-up",
              prompt: "Continue the same investigation and report the result.",
              conversationId: initialConversationId,
              tools: [],
              extensions: false,
              skills: [],
            });
          } else if (scenario === "resume" && parentCalls === 4) {
            delta = toolCall("subagent_conversations", {});
          } else if (scenario === "resume" && parentCalls === 5) {
            const catalog = JSON.parse(lastToolContent(body));
            assert.equal(catalog.conversations.length, 1);
            assert.equal(
              catalog.conversations[0].conversationId,
              initialConversationId,
            );
            delta = toolCall("subagent", {
              label: "integration-after-restart",
              prompt: "Continue after the coordinator restart.",
              conversationId: initialConversationId,
              tools: [],
              extensions: false,
              skills: [],
            });
          } else {
            parallelOutcomes =
              scenario === "parallel"
                ? lastToolContents(body).map((content) => JSON.parse(content))
                : [];
            outcome = parallelOutcomes[0] ?? JSON.parse(lastToolContent(body));
            assert.equal(
              outcome!.tasks[0]!.status,
              cancelShell
                ? "cancelled"
                : scenario === "foreground-length"
                  ? "failed"
                  : "completed",
              JSON.stringify({ outcome, parallelOutcomes }),
            );
            assert.equal(outcome!.result, cancelShell ? "" : "child verified");
            if (scenario === "resume") {
              assert.equal(
                outcome!.conversation?.conversationId,
                initialConversationId,
              );
              assert.equal(outcome!.conversation?.resumed, true);
              assert.equal(outcome!.conversation?.resumable, true);
            }
            if (scenario === "parallel") {
              assert.equal(parallelOutcomes.length, 2);
              assert.deepEqual(
                parallelOutcomes.map((item) => item.tasks[0]!.label).sort(),
                ["parallel-a", "parallel-b"],
              );
              assert.ok(
                parallelOutcomes.every(
                  (item) =>
                    item.tasks[0]!.status === "completed" &&
                    item.result === "child verified",
                ),
              );
            }
            delta = { content: "integration passed" };
          }
        } else {
          childCalls++;
          assert.equal(toolNames.includes("subagent"), false);
          if (config.expectedChildTools) {
            assert.deepEqual(toolNames.sort(), config.expectedChildTools);
            assert.equal(
              JSON.stringify(body.messages).includes(
                "<name>fixture-skill</name>",
              ),
              config.expectedSkill ?? false,
            );
          } else {
            for (const tool of [
              "read",
              "bash",
              "edit",
              "write",
              "fixture_tool",
            ])
              assert.ok(toolNames.includes(tool), tool);
            assert.ok(
              JSON.stringify(body.messages).includes(
                "Disposable fixture skill sentinel",
              ),
            );
          }
          assert.equal(
            toolNames.includes("fixture_project_tool"),
            config.expectedProjectTrusted ?? false,
          );
          if (scenario === "resume" && childCalls >= 2) {
            const messages = JSON.stringify(body.messages);
            assert.match(messages, /Use the provided tools/u);
            assert.match(messages, /child verified/u);
            assert.match(messages, /Continue the same investigation/u);
            if (childCalls === 3)
              assert.match(messages, /Continue after the coordinator restart/u);
          }

          if (cancelShell) {
            delta = toolCall("bash", {
              command: `tick=0; while :; do tick=$((tick + 1)); printf '%s' "$tick" > '${owned}'; sleep 0.02; done`,
            });
          } else if (scenario === "foreground") {
            const actions: ChatDelta[] = [
              toolCall("write", {
                path: owned,
                content: "first value",
              }),
              toolCall("edit", {
                path: owned,
                edits: [{ oldText: "first value", newText: "verified value" }],
              }),
              toolCall("bash", {
                command: `test -f '${owned}' && printf 'shell verified'`,
              }),
              toolCall("fixture_tool", {}),
            ];
            delta = actions[childCalls - 1] ?? { content: "child verified" };
            if (childCalls === 4)
              assert.ok(lastToolContent(body).includes("shell verified"));
            if (childCalls === 5)
              assert.ok(lastToolContent(body).includes("extension verified"));
          } else if (scenario === "read-only" && childCalls === 1) {
            delta = toolCall("read", { path: seed });
          } else {
            if (scenario === "read-only")
              assert.ok(lastToolContent(body).includes("disposable evidence"));
            delta = { content: "child verified" };
          }
        }
        return {
          delta,
          finishReason:
            scenario === "foreground-length" && !isParent
              ? "length"
              : undefined,
        };
      });
      fixture.configureProvider(provider.port);
      const parentSessionFile = path.join(root, "parent-session.jsonl");
      if (scenario === "resume")
        writeFileSync(parentSessionFile, "", { mode: 0o600 });
      const parentArgs = [
        "--offline",
        "--mode",
        "json",
        "--print",
        ...(scenario === "resume"
          ? ["--session", parentSessionFile]
          : ["--no-session"]),
        "--no-extensions",
        "--extension",
        uiProbe,
        "--no-skills",
        "--no-context-files",
        "--tools",
        scenario === "resume" ? "subagent,subagent_conversations" : "subagent",
        "--model",
        "fixture/fixture",
        "--thinking",
        "off",
        config.approveProject ? "--approve" : "--no-approve",
        "Run the disposable assignment.",
      ];
      const parentEnvironment = {
        ...process.env,
        PI_CODING_AGENT_DIR: agentDir,
        XDG_STATE_HOME: path.join(root, "state"),
        PI_OFFLINE: "1",
        PI_SUBAGENT: "0",
      };
      try {
        const { code, events, stderr, stdout } = await runPiProcess(
          executable!,
          parentArgs,
          cwd,
          parentEnvironment,
        );
        assert.ifError(provider.failure);
        assert.equal(code, 0, `${stderr}\n${stdout}`);
        assert.equal(
          parentCalls,
          scenario === "foreground-cancel" ? 1 : scenario === "resume" ? 3 : 2,
          `${stderr}\n${stdout}`,
        );
        const results = events.filter(
          (event) => event.type === "tool_execution_end",
        );
        assert.equal(
          results.length,
          scenario === "parallel" || scenario === "resume" ? 2 : 1,
        );
        const finalResult = results.at(-1);
        assert.ok(finalResult);
        if (scenario === "foreground-cancel") {
          outcome = JSON.parse(finalResult.result.content[0]!.text);
          assert.equal(outcome!.tasks[0]!.status, "cancelled");
          cancelledHeartbeat = readFileSync(owned, "utf8");
          await new Promise((resolve) => setTimeout(resolve, 150));
          assert.equal(readFileSync(owned, "utf8"), cancelledHeartbeat);
        }
        assert.ok(outcome);
        assert.equal(
          readFileSync(uiChecks, "utf8"),
          "passed",
          `${stderr}\n${stdout}`,
        );
        const reportedOutcomes =
          scenario === "parallel" ? parallelOutcomes : [outcome];
        assert.ok(
          reportedOutcomes.every(
            (item) =>
              item.tasks[0]!.projectTrusted ===
                (config.expectedProjectTrusted ?? false) &&
              !existsSync(item.tasks[0]!.artifactsDir),
          ),
        );
        const updates = events.filter(
          (event) => event.type === "tool_execution_update",
        );
        assert.ok(
          updates.length > 1,
          "one foreground call streams multiple updates",
        );
        assert.ok(
          updates.some(
            (event) => event.partialResult.details.tasks[0].activity.length > 0,
          ),
        );
        assert.ok(
          results.every(
            (result) =>
              result.result.isError ===
              (scenario === "foreground-cancel" ||
                scenario === "foreground-length"),
          ),
        );
        const displayOutcome = finalResult.result.details as {
          tasks: TaskSnapshot[];
        };
        assert.equal(
          outcome.tasks[0]!.transcript,
          undefined,
          "model report omits UI transcript",
        );
        assert.equal(
          outcome.tasks[0]!.usageDiagnostics,
          undefined,
          "model report omits UI usage diagnostics",
        );
        assert.ok(
          displayOutcome.tasks[0]!.transcript,
          "renderer details retain UI transcript",
        );
        if (finalResult.result.usage.input > 0)
          assert.ok(
            displayOutcome.tasks[0]!.usageDiagnostics,
            "renderer details retain UI usage diagnostics",
          );
        assert.equal(
          finalResult.result.structuredContent.tasks[0]!.transcript,
          undefined,
        );
        assert.equal(
          finalResult.result.structuredContent.tasks[0]!.usageDiagnostics,
          undefined,
        );
        if (scenario === "parallel" || scenario === "resume") {
          assert.ok(results.every((result) => result.result.usage.input === 2));
          assert.ok(
            results.every((result) => result.result.usage.output === 3),
          );
        } else {
          const toolUsage =
            scenario === "foreground"
              ? { input: 7, output: 11 }
              : { input: 0, output: 0 };
          assert.equal(
            results[0].result.usage.input,
            childCalls * 2 + toolUsage.input,
          );
          assert.equal(
            results[0].result.usage.output,
            childCalls * 3 + toolUsage.output,
          );
        }
        if (scenario === "resume") {
          assert.match(
            readFileSync(parentSessionFile, "utf8"),
            /dotfiles\.subagent-conversations\.v1/u,
          );
          const storageRoot = path.join(
            root,
            "state",
            "pi",
            "subagent-conversations",
          );
          const scopes = readdirSync(storageRoot);
          assert.equal(scopes.length, 1);
          const conversationDirectories = readdirSync(
            path.join(storageRoot, scopes[0]!),
          );
          assert.equal(conversationDirectories.length, 1);
          assert.equal(conversationDirectories[0], initialConversationId);
          assert.ok(
            existsSync(
              path.join(
                storageRoot,
                scopes[0]!,
                initialConversationId!,
                "child-session.jsonl",
              ),
            ),
          );

          const {
            code: restartedCode,
            events: restartedEvents,
            stderr: restartedStderr,
            stdout: restartedStdout,
          } = await runPiProcess(
            executable!,
            [
              ...parentArgs.slice(0, -1),
              "Continue the persisted subagent conversation.",
            ],
            cwd,
            parentEnvironment,
          );
          assert.ifError(provider.failure);
          assert.equal(
            restartedCode,
            0,
            `${restartedStderr}\n${restartedStdout}`,
          );
          assert.equal(parentCalls, 6);
          assert.equal(childCalls, 3);
          const restartedEvent = restartedEvents
            .filter((event) => event.type === "tool_execution_end")
            .find((event) => event.toolName === "subagent");
          assert.ok(restartedEvent);
          const restartedOutcome = JSON.parse(
            restartedEvent.result.content[0]!.text,
          );
          assert.equal(
            restartedOutcome.conversation.conversationId,
            initialConversationId,
          );
          assert.equal(restartedOutcome.conversation.resumed, true);
          assert.equal(restartedOutcome.tasks[0].status, "completed");
          assert.equal(
            existsSync(restartedOutcome.tasks[0].artifactsDir),
            false,
          );
        }
        if (scenario === "foreground") {
          assert.equal(readFileSync(owned, "utf8"), "verified value");
          const calls = outcome.tasks[0]!.toolCalls!;
          assert.equal(calls.length, 4);
          assert.equal(calls[0]!.preview, "write owned.txt");
          assert.equal(calls[1]!.preview, "edit owned.txt");
          assert.ok(calls.every((call) => call.status === "completed"));
          assert.ok(
            calls.every(
              (call) =>
                !call.preview.includes("first value") &&
                !call.preview.includes("verified value"),
            ),
          );
        } else if (cancelShell)
          assert.equal(readFileSync(owned, "utf8"), cancelledHeartbeat);
        else assert.equal(existsSync(owned), false);
      } finally {
        try {
          await provider.close();
        } finally {
          fixture.cleanup();
        }
      }
    },
  );
}

interface DisposablePiFixture {
  agentDir: string;
  cwd: string;
  otherCwd: string;
  owned: string;
  root: string;
  seed: string;
  uiChecks: string;
  uiProbe: string;
  configureProvider(port: number): void;
  cleanup(): void;
}

function createDisposablePiFixture(
  scenario: ScenarioName,
): DisposablePiFixture {
  const root = mkdtempSync(path.join(tmpdir(), "pi-subagent-integration-"));
  const agentDir = path.join(root, "agent");
  const cwd = path.join(root, "work");
  const otherCwd = path.join(root, "other");
  mkdirSync(agentDir);
  mkdirSync(cwd);
  mkdirSync(otherCwd);

  const uiChecks = path.join(root, "ui-checks.txt");
  const uiProbe = path.join(root, "ui-probe.ts");
  const seed = path.join(cwd, "seed.txt");
  const owned = path.join(cwd, "owned.txt");
  writeFileSync(
    uiProbe,
    uiProbeExtension(
      uiChecks,
      scenario === "foreground-cancel" ? owned : undefined,
    ),
  );
  writeFileSync(seed, "disposable evidence");

  const customExtension = path.join(agentDir, "custom.ts");
  writeFileSync(customExtension, toolExtension("fixture_tool", true));
  for (const project of [cwd, otherCwd]) {
    mkdirSync(path.join(project, ".pi", "extensions"), { recursive: true });
    writeFileSync(
      path.join(project, ".pi", "extensions", "probe.ts"),
      toolExtension("fixture_project_tool"),
    );
  }

  const skillDir = path.join(agentDir, "skills", "fixture-skill");
  mkdirSync(skillDir, { recursive: true });
  writeFileSync(
    path.join(skillDir, "SKILL.md"),
    "---\nname: fixture-skill\ndescription: Disposable fixture skill sentinel\n---\nRead only fixture files.\n",
  );

  return {
    agentDir,
    cwd,
    otherCwd,
    owned,
    root,
    seed,
    uiChecks,
    uiProbe,
    configureProvider(port) {
      writeFileSync(
        path.join(agentDir, "models.json"),
        JSON.stringify({
          providers: {
            fixture: {
              baseUrl: `http://127.0.0.1:${port}/v1`,
              api: "openai-completions",
              apiKey: "dummy",
              models: [
                {
                  id: "fixture",
                  reasoning: false,
                  contextWindow: 128000,
                  maxTokens: 4096,
                },
              ],
            },
          },
        }),
      );
      writeFileSync(
        path.join(agentDir, "settings.json"),
        JSON.stringify({
          extensions: [extensionPath, customExtension],
          retry: { enabled: false },
        }),
      );
    },
    cleanup() {
      rmSync(root, { recursive: true, force: true });
    },
  };
}

interface LocalProviderReply {
  delta: ChatDelta;
  finishReason?: "length";
}

interface LocalProvider {
  port: number;
  readonly failure: unknown;
  close(): Promise<void>;
}

async function startLocalProvider(
  replyTo: (body: ChatRequest) => Promise<LocalProviderReply>,
): Promise<LocalProvider> {
  let failure: unknown;
  const server = createServer(async (request, response) => {
    try {
      let input = "";
      for await (const chunk of request) input += chunk;
      const { delta, finishReason } = await replyTo(
        JSON.parse(input) as ChatRequest,
      );

      response.writeHead(200, { "content-type": "text/event-stream" });
      const emit = (choices: unknown[], usage?: Record<string, number>) =>
        response.write(
          `data: ${JSON.stringify({
            id: "fixture",
            object: "chat.completion.chunk",
            created: 1,
            model: "fixture",
            choices,
            ...(usage ? { usage } : {}),
          })}\n\n`,
        );
      emit([
        {
          index: 0,
          delta: { role: "assistant", ...delta },
          finish_reason: null,
        },
      ]);
      emit([
        {
          index: 0,
          delta: {},
          finish_reason: delta.tool_calls
            ? "tool_calls"
            : (finishReason ?? "stop"),
        },
      ]);
      emit([], {
        prompt_tokens: 2,
        completion_tokens: 3,
        total_tokens: 5,
      });
      response.end("data: [DONE]\n\n");
    } catch (error) {
      failure ??= error;
      response.writeHead(500);
      response.end("fixture assertion failed");
    }
  });
  await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
  const port = (server.address() as { port: number }).port;

  return {
    port,
    get failure() {
      return failure;
    },
    async close() {
      server.closeAllConnections();
      await new Promise<void>((resolve) => server.close(() => resolve()));
    },
  };
}

interface ToolExecutionEndEvent {
  type: "tool_execution_end";
  toolName?: string;
  result: {
    content: { text: string }[];
    details: unknown;
    isError: boolean;
    structuredContent: { tasks: TaskSnapshot[] };
    usage: { input: number; output: number };
  };
}

interface ToolExecutionUpdateEvent {
  type: "tool_execution_update";
  partialResult: { details: { tasks: TaskSnapshot[] } };
}

type PiEvent = ToolExecutionEndEvent | ToolExecutionUpdateEvent;

interface PiProcessResult {
  code: number | null;
  events: PiEvent[];
  stderr: string;
  stdout: string;
}

async function runPiProcess(
  piExecutable: string,
  args: string[],
  cwd: string,
  environment: NodeJS.ProcessEnv,
): Promise<PiProcessResult> {
  const child = spawn(piExecutable, args, {
    cwd,
    env: environment,
    detached: process.platform !== "win32",
    stdio: ["ignore", "pipe", "pipe"],
  });
  let stdout = "";
  let stderr = "";
  child.stdout.setEncoding("utf8");
  child.stdout.on("data", (chunk: string) => {
    stdout += chunk;
  });
  child.stderr.setEncoding("utf8");
  child.stderr.on("data", (chunk: string) => {
    stderr += chunk;
  });

  const terminate = () => {
    try {
      if (child.pid && process.platform !== "win32")
        process.kill(-child.pid, "SIGKILL");
      else child.kill("SIGKILL");
    } catch (error) {
      if ((error as NodeJS.ErrnoException).code !== "ESRCH") throw error;
    }
  };
  const timer = setTimeout(terminate, 20000);
  try {
    const code = await new Promise<number | null>((resolve, reject) => {
      child.on("close", resolve);
      child.on("error", reject);
    });
    const events = stdout
      .trim()
      .split("\n")
      .map((line) => JSON.parse(line) as PiEvent);

    return { code, events, stderr, stdout };
  } finally {
    clearTimeout(timer);
    // A successful close is the ownership boundary; do not signal an old
    // process group after it has been reaped and could be reused.
    if (child.exitCode === null && child.signalCode === null) terminate();
  }
}

interface ChatRequest {
  tools?: { function: { name: string } }[];
  messages: { role: string; content: string }[];
}

interface ChatDelta {
  content?: string;
  tool_calls?: {
    index: number;
    id: string;
    type: string;
    function: {
      name: string;
      arguments: string;
    };
  }[];
}

function toolCall(name: string, args: object): ChatDelta {
  return toolCalls(name, [args]);
}

function toolCalls(name: string, argumentsList: object[]): ChatDelta {
  return {
    tool_calls: argumentsList.map((args, index) => ({
      index,
      id: `call-${name}-${index}`,
      type: "function",
      function: {
        name,
        arguments: JSON.stringify(args),
      },
    })),
  };
}

function lastToolContents(body: ChatRequest): string[] {
  const trailingTools = [...body.messages].reverse();
  const contents: string[] = [];
  for (const message of trailingTools) {
    if (message.role !== "tool") break;
    contents.push(message.content);
  }
  return contents.reverse();
}

function lastToolContent(body: ChatRequest): string {
  return lastToolContents(body).at(-1)!;
}

function toolExtension(name: string, includeUsage = false): string {
  const usage = includeUsage
    ? `, usage: { input: 7, output: 11, cacheRead: 13, cacheWrite: 17,
        reasoning: 5, cacheWrite1h: 3, totalTokens: 48,
        cost: { input: 0.007, output: 0.011, cacheRead: 0.013,
          cacheWrite: 0.017, total: 0.048 } }`
    : "";
  return `import { Type } from "@earendil-works/pi-ai";
export default function(pi) {
  pi.registerTool({ name: ${JSON.stringify(name)}, label: "Fixture", description: "Disposable extension probe",
    parameters: Type.Object({}), execute: async () => ({ content: [{type: "text", text: "extension verified"}], details: undefined${usage} }) });
}`;
}

/** Exercise the real host components and TUI lifecycle without a terminal or credentials. */
function uiProbeExtension(checksPath: string, abortPath?: string): string {
  return `import assert from "node:assert/strict";
import { existsSync, writeFileSync } from "node:fs";
import { visibleWidth } from "@earendil-works/pi-tui";
import registerSubagent from ${JSON.stringify(extensionPath)};
export default function(pi) {
  let tool, theme, failure;
  function check(component) {
    for (const width of [80, 20, 1, 0]) {
      const lines = component.render(width);
      for (const line of lines) {
        assert.ok(visibleWidth(line) <= width, "line exceeds width " + width);
        assert.equal(line.includes("\\x1b[0m…") || line.includes("\\x1b[39m…"), false, "ellipsis loses active styling");
      }
      if (!width) assert.deepEqual(lines, []);
      component.invalidate();
    }
  }
  registerSubagent(new Proxy(pi, {
    get(target, key) {
      if (key !== "registerTool") return Reflect.get(target, key);
      return (definition) => {
        if (definition.name !== "subagent") {
          pi.registerTool(definition);
          return;
        }
        tool = definition;
        pi.registerTool({ ...definition, execute: async (...args) => {
          const ctx = args[4];
          const originalUpdate = args[3];
          args[3] = (partial) => {
            try { check(tool.renderResult(partial, { expanded: false, isPartial: true }, theme, { args: args[1] })); }
            catch (error) { failure = error; }
            originalUpdate?.(partial);
          };
          const abortPath = ${JSON.stringify(abortPath)};
          const abortTimer = abortPath ? setInterval(() => { if (existsSync(abortPath)) ctx.abort(); }, 10) : undefined;
          try { return await definition.execute(...args); }
          finally { if (abortTimer) clearInterval(abortTimer); }
        }});
      };
    }
  }));
  pi.on("session_start", (_event, ctx) => {
    theme = ctx.ui.theme;
    try {
      assert.equal("action" in tool.parameters.properties, false);
      assert.equal("taskId" in tool.parameters.properties, false);
      assert.equal("waitSeconds" in tool.parameters.properties, false);
      assert.ok("conversationId" in tool.parameters.properties);
      assert.equal(tool.parameters.additionalProperties, false);
      assert.ok(tool.parameters.required.includes("label"));
      assert.ok(tool.parameters.required.includes("prompt"));
      const task = { taskId: "task-123", label: "find-auth 中文", status: "running", cwd: "/project", model: "fixture/model", elapsedSeconds: 12,
        activity: ["tool: read finished"], artifactsDir: "/private/artifacts", tools: [], extensions: false, skills: [], projectTrusted: false };
      const call = { label: task.label, prompt: "Find 中文 authentication entry points." };
      const renderedCall = tool.renderCall(call, theme, { args: call });
      assert.doesNotMatch(renderedCall.render(80).join("\\n"), /authentication entry points/u);
      check(renderedCall);
      const receipt = tool.renderResult({ content: [], details: { tasks: [task] } }, { expanded: false, isPartial: false }, theme, { args: call });
      assert.match(receipt.render(20).join("\\n"), /Running/u);
      check(receipt);
      for (const status of ["running", "completed", "failed", "cancelled"]) {
        const report = { tasks: [{ ...task, status, transcript: [
          { kind: "assistant", text: "I’ll inspect it." },
          { kind: "tool", id: "x", preview: "bash npm test", status: "completed", output: "passed" }
        ] }], result: "# Findings\\n\\nEvidence: **中文 verified**.", resultTruncated: true };
        for (const expanded of [false, true]) {
          const view = tool.renderResult({ content: [], details: report }, { expanded, isPartial: false }, theme, { args: call, isError: status === "failed" });
          const rendered = view.render(80).join("\\n");
          if (expanded) {
            assert.match(rendered, /Assistant.*inspect it/u);
            assert.match(rendered, /Output.*passed/u);
            assert.ok(rendered.indexOf("Outcome") < rendered.indexOf("Evidence"));
            assert.ok(rendered.indexOf("Evidence") < rendered.indexOf("Output truncated"));
            assert.ok(rendered.indexOf("Output truncated") < rendered.indexOf("Details"));
          } else assert.match(rendered, /Findings.*Evidence/u);
          check(view);
        }
      }
      check(tool.renderResult({ content: [{ type: "text", text: "Invalid task ID" }] }, { expanded: false, isPartial: true }, theme, { args: {}, isError: true }));
      check(tool.renderResult({ content: [], details: { tasks: [] } }, { expanded: true, isPartial: false }, theme, { args: {} }));
    } catch (error) { failure = error; }
  });
  pi.on("session_shutdown", () => {
    try {
      assert.ifError(failure);
      writeFileSync(${JSON.stringify(checksPath)}, "passed");
    } catch (error) { writeFileSync(${JSON.stringify(checksPath)}, String(error)); }
  });
}`;
}
