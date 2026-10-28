import type {
  ExtensionAPI,
  ExtensionContext,
  ToolCallEvent,
  ToolCallEventResult,
} from "@earendil-works/pi-coding-agent";

/**
 * The override `agent-policy` refusals tell an agent to prefix a command with.
 * Its presence anywhere in a shell command is a request for the user's
 * approval, whatever rule IDs it names.
 */
export const APPROVAL_REQUEST_MARKER = "AGENT_POLICY_APPROVE=";

export const NO_UI_REASON =
  "This command sets AGENT_POLICY_APPROVE, which needs the user's approval, but this Pi session has no UI to ask in, so the command was not run. Do not retry it; report that it needs the user's approval.";
export const DECLINED_REASON =
  "The user declined to approve this AGENT_POLICY_APPROVE command, so it was not run. Do not retry it with AGENT_POLICY_APPROVE unless the user asks you to.";

/** The command of a bash tool call that requests a policy approval. */
export function policyApprovalCommand(
  event: ToolCallEvent,
): string | undefined {
  if (event.toolName !== "bash") return undefined;
  const command: unknown = event.input.command;
  return typeof command === "string" &&
    command.includes(APPROVAL_REQUEST_MARKER)
    ? command
    : undefined;
}

/** Asks the user before an approval-requesting command runs; blocks without a UI. */
export async function gatePolicyApproval(
  event: ToolCallEvent,
  ctx: Pick<ExtensionContext, "hasUI" | "ui">,
): Promise<ToolCallEventResult | undefined> {
  const command = policyApprovalCommand(event);
  if (command === undefined) return undefined;
  if (!ctx.hasUI) return { block: true, reason: NO_UI_REASON };

  const approved = await ctx.ui.confirm(
    "Approve agent policy override?",
    command,
  );
  return approved ? undefined : { block: true, reason: DECLINED_REASON };
}

/**
 * Turns a command carrying `AGENT_POLICY_APPROVE=` into a user prompt, so
 * `agent-policy` honors the override only after the user agreed. Subagent
 * children load this explicitly even with extensions disabled; they have no
 * UI, so it always blocks there.
 */
export default function agentPolicyApprovalExtension(pi: ExtensionAPI): void {
  pi.on("tool_call", gatePolicyApproval);
}
