import {
  assistantTextPreview,
  toolOutputPreview,
  toolPreview,
} from "./tool-preview.ts";
import { spawn, type ChildProcess } from "node:child_process";
import { randomUUID } from "node:crypto";
import {
  closeSync,
  existsSync,
  mkdtempSync,
  openSync,
  rmSync,
  statSync,
  writeFileSync,
  writeSync,
} from "node:fs";
import { homedir, tmpdir } from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import type { Usage } from "@earendil-works/pi-ai";
import type { JsonAgentSessionEvent } from "@earendil-works/pi-coding-agent";

/** A task is complete only after its process closes and its final message succeeds. */
export type TaskStatus = "running" | "completed" | "failed" | "cancelled";

export type TranscriptEntry =
  | { kind: "assistant"; text: string }
  | {
      kind: "tool";
      id: string;
      preview: string;
      status: "running" | "completed" | "failed" | "cancelled";
      output?: string;
    };

/** Provider usage attributable to one task; retained only for UI diagnostics. */
export type TaskUsageDiagnostics = {
  totals: Usage;
  /** Cache-read share across every usage-bearing call, including compactions. */
  overallCacheHitRate?: number;
  /** Cache-read share of the latest assistant response, matching Pi's footer. */
  latestCacheHitRate?: number;
  /** Usage-bearing compactions included in totals. */
  compactionCount: number;
};

/** Compact task metadata plus bounded UI-only transcript and usage diagnostics. */
export type TaskSnapshot = {
  taskId: string;
  label: string;
  status: TaskStatus;
  cwd: string;
  model: string;
  elapsedSeconds: number;
  activity: string[];
  /** Recent tool calls, updated in place by call ID; display-safe argument previews only. */
  toolCalls?: {
    id: string;
    preview: string;
    status: "running" | "completed" | "failed" | "cancelled";
  }[];
  /** Chronological assistant commentary and tool activity; excluded from model reports. */
  transcript?: TranscriptEntry[];
  transcriptOmitted?: number;
  usageDiagnostics?: TaskUsageDiagnostics;
  artifactsDir: string;
  error?: string;
  tools?: string[];
  extensions: boolean;
  skills?: string[];
  projectTrusted: boolean;
};

/** A polled or final task report; model usage is claimed only once per task. */
export type TaskResult = {
  tasks: TaskSnapshot[];
  result?: string;
  resultTruncated?: boolean;
  usage?: Usage;
};

/** Explicit child configuration; only a named durable child conversation may be inherited. */
export interface TaskAssignment {
  label: string;
  prompt: string;
  cwd: string;
  model: string;
  thinking: string;
  /** Omit for configured defaults; an empty array disables all tools. */
  tools?: string[];
  /** Enable configured extensions, including MCP. Defaults to true. */
  extensions?: boolean;
  /** Omit for discovered defaults; an empty array disables all skills. */
  skills?: string[];
  /** Only the initiating context may authorize project resources. Defaults to false. */
  projectTrusted?: boolean;
  /** Exact private Pi session file for a durable conversation. Omit for an ephemeral child. */
  conversationSessionFile?: string;
}

/** Process entry point, injectable for disposable subprocess fixtures. */
export interface PiInvocation {
  command: string;
  args: string[];
}

/** Owns bounded, session-local child processes and private artifacts. No automatic retries. */
export class SubagentTasks {
  private readonly tasks = new Map<string, RunningTask>();
  private closed = false;

  private readonly invocation: PiInvocation;
  private readonly managedSkillsDir: string;

  constructor(
    invocation: PiInvocation = currentPiInvocation(),
    managedSkillsDir: string = defaultManagedSkillsDir(),
  ) {
    this.invocation = invocation;
    this.managedSkillsDir = managedSkillsDir;
  }

  /** Validates a requested managed skill policy without spawning a child. */
  validateSkills(skills: string[] | undefined): void {
    resolveManagedSkills(skills, this.managedSkillsDir);
  }

  /**
   * Run to completion, publishing snapshots on activity and every second.
   * Aborting stops the owned process group; returns its final report and usage.
   * Observer errors disable progress, not execution; updates are best-effort.
   */
  async run(
    assignment: TaskAssignment,
    signal?: AbortSignal,
    onUpdate?: (task: TaskSnapshot) => void,
    onSpawn?: (pid: number) => void,
  ): Promise<TaskResult> {
    if (signal?.aborted) throw new Error("Subagent run aborted before start");
    let publishing = true;
    let observer = onUpdate;
    const publish = (snapshot: TaskSnapshot) => {
      if (!publishing) return;
      try {
        observer?.(snapshot);
      } catch {
        // Progress is best-effort; a broken view must not strand the child.
        observer = undefined;
      }
    };
    const snapshot = this.launch(assignment, publish, onSpawn);
    const task = this.get(snapshot.taskId);
    const abort = () => task.stop();
    signal?.addEventListener("abort", abort, { once: true });
    if (signal?.aborted) abort();
    const timer = onUpdate
      ? setInterval(() => publish(task.snapshot()), 1000)
      : undefined;
    try {
      await task.finished;
      return await this.result(task.taskId);
    } finally {
      publishing = false;
      if (timer) clearInterval(timer);
      signal?.removeEventListener("abort", abort);
    }
  }

  /** Launch a fresh configurable Pi process; returns immediately after spawn. */
  start(assignment: TaskAssignment): TaskSnapshot {
    return this.launch(assignment);
  }

  /** Foreground ownership is registered before notifying shared activity views. */
  private launch(
    assignment: TaskAssignment,
    onUpdate?: (task: TaskSnapshot) => void,
    onSpawn?: (pid: number) => void,
  ): TaskSnapshot {
    if (this.closed) throw new Error("Subagent session is closed");
    if (this.tasks.size >= 32)
      throw new Error("Session task limit reached (32)");
    if (
      [...this.tasks.values()].filter((task) => task.status === "running")
        .length >= 4
    ) {
      throw new Error("Concurrent subagent limit reached (4)");
    }
    if (!assignment.prompt.trim())
      throw new Error("Subagent prompt must not be empty");
    if (Buffer.byteLength(assignment.prompt) > 256 * 1024)
      throw new Error("Subagent prompt exceeds 256 KiB");
    if (!statSync(assignment.cwd).isDirectory())
      throw new Error("Subagent cwd must be a directory");

    if (
      assignment.tools?.some(
        (tool) =>
          !/^[A-Za-z0-9_][A-Za-z0-9_.:-]*$/.test(tool) || tool === "subagent",
      )
    ) {
      throw new Error("tools must contain valid non-delegating tool names");
    }
    const managedSkills = resolveManagedSkills(
      assignment.skills,
      this.managedSkillsDir,
    );

    const artifactsDir = mkdtempSync(path.join(tmpdir(), "pi-subagent-"));
    let eventsFd: number | undefined;
    let stderrFd: number | undefined;
    try {
      writeFileSync(path.join(artifactsDir, "task.txt"), assignment.prompt, {
        mode: 0o600,
      });
      const instructionsPath = path.join(artifactsDir, "instructions.txt");
      const skillPrompt = formatManagedSkillsPrompt(managedSkills);
      writeFileSync(
        instructionsPath,
        [CHILD_INSTRUCTIONS.trimEnd(), skillPrompt]
          .filter(Boolean)
          .join("\n\n") + "\n",
        { mode: 0o600 },
      );
      eventsFd = openSync(path.join(artifactsDir, "events.jsonl"), "wx", 0o600);
      stderrFd = openSync(path.join(artifactsDir, "stderr.log"), "wx", 0o600);
      const child = spawn(
        this.invocation.command,
        [
          ...this.invocation.args,
          "--mode",
          "json",
          "--print",
          ...(assignment.conversationSessionFile
            ? ["--session", assignment.conversationSessionFile]
            : ["--no-session"]),
          ...(assignment.extensions === false ? ["--no-extensions"] : []),
          ...(assignment.skills === undefined ? [] : ["--no-skills"]),
          "--no-prompt-templates",
          "--no-themes",
          assignment.projectTrusted ? "--approve" : "--no-approve",
          ...(assignment.tools === undefined
            ? []
            : assignment.tools.length
              ? ["--tools", assignment.tools.join(",")]
              : ["--no-tools"]),
          "--exclude-tools",
          "subagent",
          "--extension",
          fileURLToPath(new URL("./index.ts", import.meta.url)),
          "--model",
          assignment.model,
          "--thinking",
          assignment.thinking,
          "--append-system-prompt",
          instructionsPath,
        ],
        {
          cwd: assignment.cwd,
          env: childEnvironment(),
          detached: process.platform !== "win32",
          stdio: ["pipe", "pipe", "pipe"],
        },
      );
      const task = new RunningTask(
        assignment,
        artifactsDir,
        child,
        eventsFd,
        stderrFd,
        () => {
          onUpdate?.(task.snapshot());
        },
      );
      this.tasks.set(task.taskId, task);
      let prompt = assignment.prompt;
      if (child.pid !== undefined && onSpawn) {
        try {
          onSpawn(child.pid);
        } catch (error) {
          prompt = "";
          task.fail(`Could not record child ownership: ${String(error)}`);
        }
      }
      child.stdin!.on("error", (error: Error) =>
        task.fail(`Prompt delivery failed: ${error.message}`),
      );
      child.stdin!.end(prompt);
      onUpdate?.(task.snapshot());
      return task.snapshot();
    } catch (error) {
      if (eventsFd !== undefined) closeSync(eventsFd);
      if (stderrFd !== undefined) closeSync(stderrFd);
      rmSync(artifactsDir, { recursive: true, force: true });
      throw error;
    }
  }

  /** Returns a bounded summary, never assistant thinking or tool arguments. */
  status(taskId?: string): TaskSnapshot[] {
    return taskId
      ? [this.get(taskId).snapshot()]
      : [...this.tasks.values()].map((task) => task.snapshot());
  }

  /** Wait at most the requested seconds. Aborting the wait does not cancel the task. */
  async result(
    taskId: string,
    waitSeconds = 0,
    signal?: AbortSignal,
  ): Promise<TaskResult> {
    const task = this.get(taskId);
    await waitForTask(task.finished, waitSeconds, signal);
    const tasks = [task.snapshot()];
    if (task.status === "running") return { tasks };

    const usage = task.usageReported ? undefined : task.usage;
    task.usageReported = true;
    return {
      tasks,
      result: task.reply.slice(0, 16000),
      resultTruncated: task.reply.length > 16000,
      usage,
    };
  }

  /** Stops only the owned child process group, escalating after one second. */
  async cancel(taskId: string): Promise<TaskSnapshot> {
    const task = this.get(taskId);
    task.stop();
    await task.finished;
    return task.snapshot();
  }

  /** Idempotently stops all children, then deletes exactly their artifact directories. */
  async shutdown(): Promise<void> {
    this.closed = true;
    await Promise.all(
      [...this.tasks.values()].map(async (task) => {
        task.stop();
        await task.finished;
        rmSync(task.artifactsDir, { recursive: true, force: true });
      }),
    );
    this.tasks.clear();
  }

  private get(taskId: string): RunningTask {
    const task = this.tasks.get(taskId);
    if (!task) throw new Error(`Unknown subagent task: ${taskId}`);
    return task;
  }
}

const CHILD_INSTRUCTIONS = `You are a delegated subagent, not the coordinator.
The assignment defines your authority. Enabled tools are capabilities, not permission.
Follow local repository instructions and any narrower assignment boundaries.
Do not delegate further, publish, or mutate external/shared systems without explicit
human authorization. Do not request interactive approval; report blockers instead.
Only edit files explicitly assigned to you. Preserve unrelated work and do not
finalize repository changes; the coordinator owns review and finalization.
Report findings or changes with file paths, verification performed, and limitations.
Your final assistant response is the result delivered to the coordinator.
Cancellation does not roll back changes you have already made.
`;
const MAX_LOG_BYTES = 32 * 1024 * 1024;
const MAX_EVENT_BYTES = 8 * 1024 * 1024;

class RunningTask {
  readonly taskId = randomUUID();
  status: TaskStatus = "running";
  readonly activity: string[] = [];
  readonly toolCalls: NonNullable<TaskSnapshot["toolCalls"]> = [];
  readonly transcript: TranscriptEntry[] = [];
  private transcriptOmitted = 0;
  reply = "";
  usageReported = false;
  readonly usage: Usage = {
    input: 0,
    output: 0,
    cacheRead: 0,
    cacheWrite: 0,
    totalTokens: 0,
    cost: {
      input: 0,
      output: 0,
      cacheRead: 0,
      cacheWrite: 0,
      total: 0,
    },
  };
  readonly finished: Promise<void>;
  private usageEventCount = 0;
  private latestCacheHitRate?: number;
  private compactionCount = 0;
  private finish!: () => void;
  private readonly startedAt = Date.now();
  private endedAt?: number;
  private buffer = "";
  private logBytes = 0;
  private settled = false;
  private stopReason?: string;
  private assistantError?: string;
  private failure?: string;
  private stopping = false;
  private cleanupFinished: Promise<void> = Promise.resolve();

  private readonly assignment: TaskAssignment;
  readonly artifactsDir: string;
  private readonly child: ChildProcess;
  private readonly eventsFd: number;
  private readonly stderrFd: number;
  private readonly publishSnapshot: () => void;

  constructor(
    assignment: TaskAssignment,
    artifactsDir: string,
    child: ChildProcess,
    eventsFd: number,
    stderrFd: number,
    publishSnapshot: () => void,
  ) {
    this.assignment = assignment;
    this.artifactsDir = artifactsDir;
    this.child = child;
    this.eventsFd = eventsFd;
    this.stderrFd = stderrFd;
    this.publishSnapshot = publishSnapshot;
    this.finished = new Promise((resolve) => {
      this.finish = resolve;
    });
    child.stdout!.setEncoding("utf8");
    child.stdout!.on("data", (chunk: string) => {
      if (!this.log(this.eventsFd, chunk)) return;
      this.buffer += chunk;
      let newline: number;
      while ((newline = this.buffer.indexOf("\n")) !== -1) {
        const line = this.buffer.slice(0, newline);
        this.buffer = this.buffer.slice(newline + 1);
        this.consume(line);
      }
      if (Buffer.byteLength(this.buffer) > MAX_EVENT_BYTES)
        this.fail("JSON event exceeds 8 MiB");
    });
    child.stderr!.setEncoding("utf8");
    child.stderr!.on("data", (chunk: string) => {
      this.log(this.stderrFd, chunk);
    });
    child.on("error", (error) =>
      this.fail(`Could not run Pi: ${error.message}`),
    );
    child.on("close", async (code, signal) => {
      if (this.buffer.trim()) this.consume(this.buffer);
      // Group escalation must outlive the leader: descendants may close their pipes.
      await this.cleanupFinished;
      this.endedAt = Date.now();
      if (this.failure) this.status = "failed";
      else if (this.stopping) this.status = "cancelled";
      else if (
        code !== 0 ||
        !this.settled ||
        this.stopReason !== "stop" ||
        !this.reply.trim()
      ) {
        this.status = "failed";
        this.failure =
          this.assistantError ??
          `Pi did not complete successfully (exit=${code}, signal=${signal}, settled=${this.settled}, stopReason=${this.stopReason ?? "missing"}). See stderr.log.`;
      } else this.status = "completed";

      const unfinishedStatus =
        this.status === "cancelled" ? "cancelled" : "failed";
      for (const call of this.toolCalls) {
        if (call.status === "running") call.status = unfinishedStatus;
      }
      for (const entry of this.transcript) {
        if (entry.kind === "tool" && entry.status === "running")
          entry.status = unfinishedStatus;
      }
      try {
        writeFileSync(path.join(this.artifactsDir, "reply.txt"), this.reply, {
          mode: 0o600,
        });
      } catch (error) {
        this.status = "failed";
        this.failure = `Could not save reply: ${String(error)}`;
      } finally {
        closeSync(this.eventsFd);
        closeSync(this.stderrFd);
        this.finish();
        this.publishSnapshot();
      }
    });
  }

  snapshot(): TaskSnapshot {
    const overallCacheHitRate = promptCacheHitRate(this.usage);

    return {
      taskId: this.taskId,
      label: this.assignment.label,
      status: this.status,
      cwd: this.assignment.cwd,
      model: this.assignment.model,
      elapsedSeconds: Math.floor(
        ((this.endedAt ?? Date.now()) - this.startedAt) / 1000,
      ),
      activity: [...this.activity],
      toolCalls: this.toolCalls.map((call) => ({ ...call })),
      transcript: this.transcript.map((entry) => ({ ...entry })),
      ...(this.transcriptOmitted
        ? { transcriptOmitted: this.transcriptOmitted }
        : {}),
      ...(this.usageEventCount
        ? {
            usageDiagnostics: {
              totals: cloneUsage(this.usage),
              ...(overallCacheHitRate === undefined
                ? {}
                : { overallCacheHitRate }),
              ...(this.latestCacheHitRate === undefined
                ? {}
                : { latestCacheHitRate: this.latestCacheHitRate }),
              compactionCount: this.compactionCount,
            },
          }
        : {}),
      artifactsDir: this.artifactsDir,
      ...(this.failure ? { error: this.failure } : {}),
      ...(this.assignment.tools === undefined
        ? {}
        : { tools: [...this.assignment.tools] }),
      extensions: this.assignment.extensions !== false,
      ...(this.assignment.skills === undefined
        ? {}
        : { skills: [...this.assignment.skills] }),
      projectTrusted: this.assignment.projectTrusted === true,
    };
  }

  fail(message: string): void {
    this.failure ??= message;
    this.stop();
  }

  stop(): void {
    if (this.status !== "running" || this.stopping) return;
    this.stopping = true;
    this.signal("SIGTERM");
    this.cleanupFinished = new Promise((resolve) => {
      setTimeout(() => {
        this.signal("SIGKILL");
        resolve();
      }, 1000);
    });
  }

  private signal(signal: NodeJS.Signals): void {
    try {
      if (process.platform !== "win32" && this.child.pid)
        process.kill(-this.child.pid, signal);
      else this.child.kill(signal);
    } catch (error) {
      if ((error as NodeJS.ErrnoException).code !== "ESRCH")
        this.failure ??= `Could not stop child: ${String(error)}`;
    }
  }

  private log(fd: number, chunk: string): boolean {
    this.logBytes += Buffer.byteLength(chunk);
    if (this.logBytes > MAX_LOG_BYTES) {
      this.fail("Subagent logs exceed 32 MiB");
      return false;
    }
    try {
      writeSync(fd, chunk);
      return true;
    } catch (error) {
      this.fail(`Could not write task log: ${String(error)}`);
      return false;
    }
  }

  private consume(line: string): void {
    if (!line.trim()) return;
    if (Buffer.byteLength(line) > MAX_EVENT_BYTES) {
      this.fail("JSON event exceeds 8 MiB");
      return;
    }
    try {
      const event = JSON.parse(line) as JsonAgentSessionEvent;
      if (event.type === "agent_start") this.settled = false;
      if (event.type === "agent_settled") this.settled = true;
      if (event.type === "message_end" && event.message.role === "assistant") {
        const message = event.message;
        this.reply = message.content
          .filter((block) => block.type === "text")
          .map((block) => block.text)
          .join("\n");
        this.stopReason = message.stopReason;
        this.assistantError = message.errorMessage;
        this.addUsage(message.usage);
        this.latestCacheHitRate = promptCacheHitRate(message.usage);
        if (message.stopReason === "toolUse") {
          const commentary = assistantTextPreview(
            message.content
              .filter((block) => block.type === "text")
              .map((block) => block.text)
              .join("\n"),
          );
          if (commentary)
            this.addTranscript({ kind: "assistant", text: commentary });
        }
        this.note(`assistant: ${message.stopReason}`);
      } else if (event.type === "tool_execution_start") {
        const call = {
          id: event.toolCallId,
          preview: toolPreview(event.toolName, event.args, this.assignment.cwd),
          status: "running" as const,
        };
        this.toolCalls.push(call);
        this.addTranscript({ kind: "tool", ...call });
        if (this.toolCalls.length > 8) this.toolCalls.shift();
        this.note(`tool: ${event.toolName}`);
      } else if (event.type === "tool_execution_end") {
        if (!event.parentToolCallId && event.result?.usage)
          this.addUsage(event.result.usage);
        const call = this.toolCalls.find(
          (call) => call.id === event.toolCallId,
        );
        const status = event.isError ? "failed" : "completed";
        if (call) call.status = status;
        const transcriptCall = this.transcript.find(
          (entry) => entry.kind === "tool" && entry.id === event.toolCallId,
        );
        if (transcriptCall?.kind === "tool") {
          transcriptCall.status = status;
          transcriptCall.output = toolOutputPreview(
            event.toolName,
            event.result,
          );
        }
        this.note(
          `tool: ${event.toolName} ${event.isError ? "failed" : "finished"}`,
        );
      } else if (event.type === "compaction_end" && event.result?.usage) {
        this.addUsage(event.result.usage);
        this.compactionCount++;
        this.note("context compacted");
      } else if (event.type === "auto_retry_start") this.note("provider retry");
      else if (event.type === "compaction_start")
        this.note("compacting context");
      else if (event.type === "agent_settled")
        this.note("agent settled; awaiting process exit");
    } catch (error) {
      this.fail(`Invalid Pi JSON event: ${String(error)}`);
    }
  }

  private addTranscript(entry: TranscriptEntry): void {
    this.transcript.push(entry);
    if (this.transcript.length > 64) {
      this.transcript.shift();
      this.transcriptOmitted++;
    }
  }

  private addUsage(usage: Usage): void {
    this.usageEventCount++;
    for (const key of [
      "input",
      "output",
      "cacheRead",
      "cacheWrite",
      "totalTokens",
    ] as const) {
      this.usage[key] += usage[key];
    }
    for (const key of ["reasoning", "cacheWrite1h"] as const) {
      if (usage[key] !== undefined)
        this.usage[key] = (this.usage[key] ?? 0) + usage[key];
    }
    for (const key of [
      "input",
      "output",
      "cacheRead",
      "cacheWrite",
      "total",
    ] as const) {
      this.usage.cost[key] += usage.cost[key];
    }
  }

  private note(activity: string): void {
    this.activity.push(activity.slice(0, 200));
    if (this.activity.length > 8) this.activity.shift();
    this.publishSnapshot();
  }
}

function cloneUsage(usage: Usage): Usage {
  return {
    input: usage.input,
    output: usage.output,
    cacheRead: usage.cacheRead,
    cacheWrite: usage.cacheWrite,
    ...(usage.cacheWrite1h === undefined
      ? {}
      : { cacheWrite1h: usage.cacheWrite1h }),
    ...(usage.reasoning === undefined ? {} : { reasoning: usage.reasoning }),
    totalTokens: usage.totalTokens,
    cost: { ...usage.cost },
  };
}

function promptCacheHitRate(usage: Usage): number | undefined {
  const promptTokens = usage.input + usage.cacheRead + usage.cacheWrite;
  return promptTokens > 0 ? (usage.cacheRead / promptTokens) * 100 : undefined;
}

interface ManagedSkill {
  name: string;
  instructionsPath: string;
}

function resolveManagedSkills(
  skills: string[] | undefined,
  managedSkillsDir: string,
): ManagedSkill[] {
  if (skills === undefined) return [];
  if (
    skills.some(
      (skill) =>
        skill.length > 64 || !/^[a-z0-9]+(?:-[a-z0-9]+)*$/u.test(skill),
    )
  ) {
    throw new Error("skills must contain valid managed skill names");
  }
  if (new Set(skills).size !== skills.length)
    throw new Error("skills must not contain duplicate names");

  return skills.map((name) => {
    const instructionsPath = path.join(managedSkillsDir, name, "SKILL.md");
    if (!existsSync(instructionsPath) || !statSync(instructionsPath).isFile())
      throw new Error(`Unknown managed skill: ${name}`);
    return { name, instructionsPath };
  });
}

function formatManagedSkillsPrompt(skills: ManagedSkill[]): string {
  if (skills.length === 0) return "";
  return [
    "The coordinator selected the following workflow skills for this assignment.",
    "Read each listed SKILL.md before working and follow its instructions.",
    "Resolve relative references against the directory containing that SKILL.md.",
    "",
    "<available_skills>",
    ...skills.flatMap((skill) => [
      "  <skill>",
      `    <name>${skill.name}</name>`,
      `    <location>${escapeXml(skill.instructionsPath)}</location>`,
      "  </skill>",
    ]),
    "</available_skills>",
  ].join("\n");
}

function escapeXml(value: string): string {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&apos;");
}

function defaultManagedSkillsDir(): string {
  const agentDir =
    process.env.PI_CODING_AGENT_DIR ?? path.join(homedir(), ".pi", "agent");
  return path.join(agentDir, "skills");
}

function currentPiInvocation(): PiInvocation {
  const script = process.argv[1];
  if (script && /(?:^|\/)cli\.(?:js|ts)$/.test(script) && existsSync(script)) {
    return {
      command: process.execPath,
      args: [script],
    };
  }
  return {
    command: /^(node|bun)(\.exe)?$/i.test(path.basename(process.execPath))
      ? "pi"
      : process.execPath,
    args: [],
  };
}

function childEnvironment(): NodeJS.ProcessEnv {
  const env: NodeJS.ProcessEnv = {
    ...process.env,
    PI_SUBAGENT: "1",
  };
  for (const key of Object.keys(env)) {
    if (
      key.startsWith("HERDR_") ||
      [
        "PI_SESSION_ID",
        "PI_SESSION_FILE",
        "PI_PROVIDER",
        "PI_MODEL",
        "PI_REASONING_LEVEL",
      ].includes(key)
    )
      delete env[key];
  }
  return env;
}

async function waitForTask(
  finished: Promise<void>,
  seconds: number,
  signal?: AbortSignal,
): Promise<void> {
  if (signal?.aborted)
    throw new Error("Subagent result wait aborted; task remains running");
  if (!Number.isFinite(seconds) || seconds < 0 || seconds > 60)
    throw new Error("waitSeconds must be between 0 and 60");
  if (seconds === 0) return;

  await new Promise<void>((resolve, reject) => {
    const abort = () => {
      cleanup();
      reject(new Error("Subagent result wait aborted; task remains running"));
    };
    const cleanup = () => {
      clearTimeout(timer);
      signal?.removeEventListener("abort", abort);
    };
    const timer = setTimeout(() => {
      cleanup();
      resolve();
    }, seconds * 1000);
    signal?.addEventListener("abort", abort, { once: true });
    void finished.then(() => {
      cleanup();
      resolve();
    });
  });
}
