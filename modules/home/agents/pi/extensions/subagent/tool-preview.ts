import path from "node:path";

/** Bounded tool summaries: file/search targets, commands, or unknown-tool argument names. */
export function toolPreview(name: string, value: unknown, cwd: string): string {
  const args =
    value && typeof value === "object"
      ? (value as Record<string, unknown>)
      : {};
  const text = (key: string) =>
    typeof args[key] === "string" ? (args[key] as string) : "";
  const target = () => {
    const file = text("path") || text("file_path");
    return file && path.isAbsolute(file)
      ? path.relative(cwd, file) || "."
      : file || ".";
  };
  let detail: string;
  switch (name) {
    case "read": {
      const offset =
        typeof args.offset === "number" &&
        Number.isSafeInteger(args.offset) &&
        args.offset > 0
          ? args.offset
          : undefined;
      const limit =
        typeof args.limit === "number" &&
        Number.isSafeInteger(args.limit) &&
        args.limit > 0
          ? args.limit
          : undefined;
      detail = target();
      if (offset || limit)
        detail += `:${offset ?? 1}${limit ? `–${(offset ?? 1) + limit - 1}` : ""}`;
      break;
    }
    case "write":
    case "edit":
    case "ls":
      detail = target();
      break;
    case "grep":
    case "find":
      detail = `${text("pattern")} · ${target()}`;
      break;
    case "bash":
      detail = text("command");
      break;
    default:
      // Unknown tools may carry credentials or complete documents. Show shape only.
      detail = Object.keys(args)
        .slice(0, 6)
        .map((key) => `${key}=…`)
        .join(" ");
  }
  return safeDisplayText(`${name}${detail ? `  ${detail}` : ""}`, 600, false);
}

/** Safe bounded output for commands and discovery tools; file contents stay excluded. */
export function toolOutputPreview(
  name: string,
  value: unknown,
): string | undefined {
  if (!["bash", "grep", "find", "ls"].includes(name)) return;
  if (!value || typeof value !== "object") return;
  const content = (value as { content?: unknown }).content;
  if (!Array.isArray(content)) return;
  const output = content
    .filter((part): part is { type: "text"; text: string } =>
      Boolean(
        part &&
          typeof part === "object" &&
          (part as { type?: unknown }).type === "text" &&
          typeof (part as { text?: unknown }).text === "string",
      ),
    )
    .map((part) => part.text)
    .join("\n");
  if (!output.trim()) return;
  return safeDisplayText(output, 1200, true).split("\n").slice(0, 6).join("\n");
}

/** Bounded visible assistant commentary with hidden reasoning supplied separately. */
export function assistantTextPreview(value: string): string {
  return safeDisplayText(value, 4000, true);
}

/** Best-effort credential redaction, terminal-control removal, and display bound. */
function safeDisplayText(
  value: string,
  maxCharacters: number,
  preserveLines: boolean,
): string {
  const cleaned = value
    .replace(/\r\n?/gu, "\n")
    .replace(/\u001b\][^\u0007]*?(?:\u0007|\u001b\\)/gu, "")
    .replace(/\u001b\[[0-?]*[ -/]*[@-~]/gu, "")
    .replace(/[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f-\u009f]/gu, "")
    .replace(/\b(?:Bearer|Basic)\s+[^\s'";]+/giu, "Bearer <redacted>")
    .replace(
      /(\b[\w-]*(?:token|secret|password|passwd|api[_-]?key|authorization|cookie)[\w-]*["']?[\s=:]+)(?:"(?:\\.|[^"\\])*"|'[^']*'|[^\s;]+)/giu,
      "$1<redacted>",
    )
    .replace(/(https?:\/\/)[^\s/@]+:[^\s/@]+@/giu, "$1<redacted>@")
    .replace(/\b(?:sk-|ghp_|github_pat_)[A-Za-z0-9_-]+/gu, "<redacted>");
  const normalized = preserveLines
    ? cleaned
        .split("\n")
        .map((line) => line.replace(/[ \t]+/gu, " ").trimEnd())
        .join("\n")
        .trim()
    : cleaned.replace(/\s+/gu, " ").trim();
  return normalized.length <= maxCharacters
    ? normalized
    : `${normalized.slice(0, Math.max(0, maxCharacters - 1))}…`;
}
