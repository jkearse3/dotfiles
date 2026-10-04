import { Type } from "@earendil-works/pi-ai";
import {
  defineTool,
  getMarkdownTheme,
  type ExtensionAPI,
  type ExtensionToolContext,
} from "@earendil-works/pi-coding-agent";
import {
  Markdown,
  sliceByColumn,
  visibleWidth,
  wrapTextWithAnsi,
} from "@earendil-works/pi-tui";
import { lstatSync, realpathSync } from "node:fs";
import path from "node:path";
import {
  ConversationStorage,
  MAX_CONVERSATION_AGE_MS,
  MAX_CONVERSATION_SESSION_BYTES,
  SUBAGENT_CONVERSATION_CATALOG_ENTRY_TYPE,
  publicConversationError,
  reduceConversationCatalogEntries,
  serializeConversationCatalogSnapshot,
  updateConversationCatalog,
  type ConversationCatalogRecord,
  type ConversationLease,
  type ParentConversationSession,
} from "./conversations.ts";
import {
  cleanSubagentText,
  readSubagentReport,
  subagentCallLines,
  subagentResultPresentation,
  type SubagentReport,
} from "./presentation.ts";
import {
  createSubagentComponent,
  createSubagentTruncator,
} from "./renderer.ts";
import { SubagentTasks, type TaskSnapshot } from "./tasks.ts";

const truncateSubagentLine = createSubagentTruncator({
  slice: (text, startColumn, length) =>
    sliceByColumn(text, startColumn, length, true),
  measure: visibleWidth,
});

const ConversationSchema = Type.Object({
  conversationId: Type.String(),
  resumed: Type.Boolean(),
  resumable: Type.Boolean(),
  createdAt: Type.String(),
  lastUsedAt: Type.String(),
  sessionBytes: Type.Number(),
});

const ConversationCatalogSchema = Type.Object({
  conversationId: Type.String(),
  label: Type.String(),
  cwd: Type.String(),
  createdAt: Type.String(),
  lastUsedAt: Type.String(),
});

const TaskSchema = Type.Object({
  taskId: Type.String(),
  label: Type.String(),
  status: Type.Union([
    Type.Literal("running"),
    Type.Literal("completed"),
    Type.Literal("failed"),
    Type.Literal("cancelled"),
  ]),
  cwd: Type.String(),
  model: Type.String(),
  elapsedSeconds: Type.Number(),
  activity: Type.Array(Type.String()),
  toolCalls: Type.Optional(
    Type.Array(
      Type.Object({
        id: Type.String(),
        preview: Type.String(),
        status: Type.Union([
          Type.Literal("running"),
          Type.Literal("completed"),
          Type.Literal("failed"),
          Type.Literal("cancelled"),
        ]),
      }),
    ),
  ),
  artifactsDir: Type.String(),
  error: Type.Optional(Type.String()),
  tools: Type.Optional(Type.Array(Type.String())),
  extensions: Type.Boolean(),
  skills: Type.Optional(Type.Array(Type.String())),
  projectTrusted: Type.Boolean(),
});

type SubagentModelTask = Omit<
  TaskSnapshot,
  "transcript" | "transcriptOmitted" | "usageDiagnostics"
>;
type SubagentModelReport = Omit<SubagentReport, "tasks"> & {
  tasks: SubagentModelTask[];
};

/** Removes UI-only transcript and usage data from coordinator-visible reports. */
function modelReport(report: SubagentReport): SubagentModelReport {
  return {
    ...report,
    tasks: report.tasks.map((task) => {
      const {
        transcript: _transcript,
        transcriptOmitted: _omitted,
        usageDiagnostics: _usageDiagnostics,
        ...modelTask
      } = task;
      return modelTask;
    }),
  };
}

function conversationReport(lease: ConversationLease, resumed: boolean) {
  let sessionBytes = 0;
  let resumable = false;
  try {
    const session = lstatSync(lease.sessionFilePath);
    sessionBytes = session.size;
    resumable =
      session.isFile() &&
      !session.isSymbolicLink() &&
      sessionBytes <= MAX_CONVERSATION_SESSION_BYTES;
  } catch {
    // The completed task result remains useful even if its checkpoint is lost.
  }
  return {
    conversationId: lease.metadata.conversationId,
    resumed,
    resumable,
    createdAt: new Date(lease.metadata.createdAt).toISOString(),
    lastUsedAt: new Date(lease.metadata.lastUsedAt).toISOString(),
    sessionBytes,
  };
}

/** Registers foreground delegation with parent-scoped durable conversations. */
export default function subagentExtension(pi: ExtensionAPI): void {
  if (process.env.PI_SUBAGENT === "1") {
    pi.on("tool_call", (event) => {
      if (
        event.toolName === "subagent" ||
        event.toolName === "subagent_conversations"
      )
        return {
          block: true,
          reason: "Delegated subagents cannot delegate further",
        };
    });
    return;
  }

  const conversationStorage = new ConversationStorage();
  let conversations: ConversationCatalogRecord[] = [];
  let parentSession: ParentConversationSession | undefined;
  let tasks: SubagentTasks | undefined;

  const refreshConversations = (ctx: ExtensionToolContext) => {
    const sessionFilePath = ctx.sessionManager.getSessionFile();
    parentSession = sessionFilePath
      ? {
          sessionFilePath,
          sessionId: ctx.sessionManager.getSessionId(),
        }
      : undefined;
    conversations = parentSession
      ? reduceConversationCatalogEntries(ctx.sessionManager.getBranch())
      : [];
    if (!parentSession) return;

    conversationStorage.cleanup(parentSession);
    const cutoff = Date.now() - MAX_CONVERSATION_AGE_MS;
    const retained = conversations.filter(
      (record) => record.lastUsedAt >= cutoff,
    );
    if (retained.length === conversations.length) return;
    pi.appendEntry(
      SUBAGENT_CONVERSATION_CATALOG_ENTRY_TYPE,
      serializeConversationCatalogSnapshot(retained),
    );
    conversations = retained;
  };

  pi.on("session_start", (_event, ctx) => {
    const sessionFilePath = ctx.sessionManager.getSessionFile();
    parentSession = sessionFilePath
      ? {
          sessionFilePath,
          sessionId: ctx.sessionManager.getSessionId(),
        }
      : undefined;
    conversations = parentSession
      ? reduceConversationCatalogEntries(ctx.sessionManager.getBranch())
      : [];
  });

  pi.on("session_shutdown", async () => {
    await tasks?.shutdown();
    tasks = undefined;
    conversations = [];
    parentSession = undefined;
  });

  pi.registerTool(
    defineTool({
      name: "subagent",
      label: "Subagent",
      description:
        "Run a Pi subagent in one foreground call. Omit conversationId to start a fresh conversation; pass a returned conversationId to continue the same line of inquiry with its prior message and tool context. Resume for follow-ups on the same investigation or implementation; start fresh for independent, parallel, or unbiased work, materially changed scope, or stale/large context. Requires prompt and label, streams progress, waits for completion, and returns the final response and usage. Interrupting the call stops its child but preserves the durable conversation checkpoint and does not roll back edits. Conversations belong to the active persisted parent-session branch and survive reloads, session switching, and Pi restarts; ephemeral --no-session parents cannot create resumable conversations. Each continuation spawns a new process, and one conversation cannot run concurrently. Give bounded scope, authority, explicit nonoverlapping file ownership for writes, expected evidence, verification, and limitations. Children use normal configured Pi tools and skills by default, including shell, edit, and write. Optional tools replaces the active tool selection; [] disables all tools. Optional skills selects exact managed skill names; [] disables all skills. A resumed conversation must keep its original skill selection. Extensions/MCP default on and can be disabled separately. For read-only work use tools [read,grep,find,ls], extensions false. These controls are not an OS sandbox or grants of authority; extension code and enabled shell commands retain OS permissions. The subagent tools and further delegation are unavailable to children. Project resources inherit trust only for the caller's exact canonical cwd; other directories are not auto-approved. Default model/thinking match the caller; model is an optional override. Private invocation artifacts support diagnostics and are deleted at parent-session shutdown; durable child conversations remain private and bounded. No persistent processes, background jobs, queues, or runner-level retries.",
      parameters: Type.Object(
        {
          label: Type.String({ minLength: 1, maxLength: 80 }),
          prompt: Type.String({ minLength: 1, maxLength: 256 * 1024 }),
          conversationId: Type.Optional(
            Type.String({
              pattern:
                "^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$",
              description:
                "Durable conversation to continue; omit to start fresh.",
            }),
          ),
          cwd: Type.Optional(
            Type.String({
              description:
                "Defaults to the caller's working directory; relative paths resolve there.",
            }),
          ),
          model: Type.Optional(
            Type.String({
              minLength: 1,
              description:
                "Optional Pi model selector; omit to inherit the caller's active provider/model.",
            }),
          ),
          tools: Type.Optional(
            Type.Array(
              Type.String({
                minLength: 1,
                maxLength: 128,
                pattern: "^[A-Za-z0-9_][A-Za-z0-9_.:-]*$",
              }),
              {
                maxItems: 64,
                description:
                  "Active tool allowlist; omitted uses configured defaults, [] disables all tools. Use extensions:false as well for tightly restricted tasks.",
              },
            ),
          ),
          extensions: Type.Optional(
            Type.Boolean({
              description:
                "Load configured extensions and MCP; defaults to true. Extension code itself is not constrained by the tool allowlist.",
            }),
          ),
          skills: Type.Optional(
            Type.Array(
              Type.String({
                minLength: 1,
                maxLength: 64,
                pattern: "^[a-z0-9]+(?:-[a-z0-9]+)*$",
              }),
              {
                maxItems: 32,
                description:
                  "Managed skill-name allowlist; omitted uses discovered defaults, [] disables all skills.",
              },
            ),
          ),
        },
        { additionalProperties: false },
      ),
      outputSchema: Type.Object({
        tasks: Type.Array(TaskSchema),
        result: Type.Optional(Type.String()),
        resultTruncated: Type.Optional(Type.Boolean()),
        conversation: Type.Optional(ConversationSchema),
      }),
      renderCall(args, theme) {
        const lines = subagentCallLines(args);
        return createSubagentComponent(() => lines, theme, {
          truncate: truncateSubagentLine,
        });
      },
      renderResult(result, { expanded }, theme, renderContext) {
        const report = readSubagentReport(result.details);
        const layout = {
          truncate: truncateSubagentLine,
          wrap: expanded ? wrapTextWithAnsi : undefined,
        };
        if (!report) {
          const text = cleanSubagentText(
            result.content
              .filter((part) => part.type === "text")
              .map((part) => part.text)
              .join("\n"),
          );
          const lines = [
            {
              text: text.replace(/\s+/gu, " ").trim() || "No output",
              tone: renderContext.isError
                ? ("error" as const)
                : ("muted" as const),
            },
          ];
          return createSubagentComponent(() => lines, theme, layout);
        }
        const presentation = subagentResultPresentation(
          report,
          renderContext.args,
          expanded,
        );
        const output =
          expanded && report.result?.trim()
            ? new Markdown(
                cleanSubagentText(report.result),
                0,
                0,
                getMarkdownTheme(),
              )
            : undefined;
        const detailsComponent =
          output && presentation.details.length
            ? createSubagentComponent(() => presentation.details, theme, layout)
            : undefined;
        const lines = output
          ? presentation.primary
          : [...presentation.primary, ...presentation.details];
        return createSubagentComponent(
          () => lines,
          theme,
          layout,
          output,
          detailsComponent,
        );
      },
      async execute(_id, params, signal, onUpdate, ctx) {
        if (signal?.aborted) throw new Error("Subagent call aborted");
        if (!ctx.model && !params.model)
          throw new Error("No active model selected");

        try {
          refreshConversations(ctx);
        } catch (error) {
          throw publicConversationError(error);
        }
        tasks ??= new SubagentTasks();
        tasks.validateSkills(params.skills);
        const cwd = realpathSync(path.resolve(ctx.cwd, params.cwd ?? "."));
        const label = params.label.replace(/[\x00-\x1f\x7f]/g, " ").trim();
        if (!label) throw new Error("Subagent label must not be blank");
        const requestedConversationId = params.conversationId;
        if (requestedConversationId && !parentSession) {
          throw new Error(
            "conversationId requires a persisted parent Pi session",
          );
        }

        const resumed = requestedConversationId !== undefined;
        let lease: ConversationLease | undefined;
        try {
          lease = parentSession
            ? resumed
              ? conversationStorage.resume({
                  parent: parentSession,
                  cwd,
                  conversationId: requestedConversationId!,
                  activeConversationIds: new Set(
                    conversations.map((record) => record.conversationId),
                  ),
                  skills: params.skills,
                })
              : conversationStorage.create({
                  parent: parentSession,
                  cwd,
                  skills: params.skills,
                })
            : undefined;
        } catch (error) {
          throw publicConversationError(error);
        }
        try {
          if (lease) {
            const previousCatalog = conversations;
            conversations = updateConversationCatalog(conversations, {
              conversationId: lease.metadata.conversationId,
              label,
              cwd: lease.metadata.cwd,
              createdAt: lease.metadata.createdAt,
              lastUsedAt: lease.metadata.lastUsedAt,
            });
            try {
              pi.appendEntry(
                SUBAGENT_CONVERSATION_CATALOG_ENTRY_TYPE,
                serializeConversationCatalogSnapshot(conversations),
              );
            } catch (error) {
              conversations = previousCatalog;
              throw publicConversationError(error);
            }
          }

          const conversation = lease
            ? conversationReport(lease, resumed)
            : undefined;
          const assignment = {
            label,
            prompt: params.prompt,
            cwd,
            model: params.model ?? `${ctx.model!.provider}/${ctx.model!.id}`,
            thinking: pi.getThinkingLevel(),
            tools: params.tools,
            extensions: params.extensions,
            skills: params.skills,
            projectTrusted:
              ctx.isProjectTrusted() && cwd === realpathSync(ctx.cwd),
            ...(lease
              ? { conversationSessionFile: lease.sessionFilePath }
              : {}),
          };
          const outcome = await tasks.run(
            assignment,
            signal,
            (task) => {
              const progress: SubagentReport = {
                tasks: [task],
                ...(conversation ? { conversation } : {}),
              };
              onUpdate?.({
                content: [
                  { type: "text", text: JSON.stringify(modelReport(progress)) },
                ],
                details: progress,
              });
            },
            (pid) => {
              try {
                lease?.recordChildPid(pid);
              } catch (error) {
                throw publicConversationError(error);
              }
            },
          );
          const { usage, ...taskReport } = outcome;
          const report: SubagentReport = {
            ...taskReport,
            ...(lease
              ? { conversation: conversationReport(lease, resumed) }
              : {}),
          };
          const agentReport = modelReport(report);
          return {
            content: [
              { type: "text", text: JSON.stringify(agentReport, null, 2) },
            ],
            details: report,
            structuredContent: agentReport,
            isError: report.tasks.some(
              (task) => task.status === "failed" || task.status === "cancelled",
            ),
            usage,
          };
        } finally {
          try {
            lease?.release();
          } catch (error) {
            throw publicConversationError(error);
          }
        }
      },
    }),
  );

  pi.registerTool(
    defineTool({
      name: "subagent_conversations",
      label: "Subagent Conversations",
      description:
        "List the bounded durable subagent conversations authorized by the active parent-session branch. Use this only when a relevant conversationId is no longer visible in context. It returns metadata, never child messages, tool output, or storage paths. Resume the same line of inquiry with subagent conversationId; start fresh for independent or unbiased work.",
      parameters: Type.Object({}, { additionalProperties: false }),
      outputSchema: Type.Object({
        conversations: Type.Array(ConversationCatalogSchema),
      }),
      async execute(_id, _params, _signal, _onUpdate, ctx) {
        try {
          refreshConversations(ctx);
        } catch (error) {
          throw publicConversationError(error);
        }
        const report = {
          conversations: conversations.map((record) => ({
            conversationId: record.conversationId,
            label: record.label,
            cwd: record.cwd,
            createdAt: new Date(record.createdAt).toISOString(),
            lastUsedAt: new Date(record.lastUsedAt).toISOString(),
          })),
        };
        return {
          content: [{ type: "text", text: JSON.stringify(report, null, 2) }],
          details: report,
          structuredContent: report,
        };
      },
    }),
  );
}
