import { atom, read, update } from "claude-code";
import type {
  EngineInterface,
  Register,
  SessionContextUsage,
} from "claude-code";

import type { StatuslineLine } from "../types";

// The session's model and context window fill, for example
// `claude-opus-5-5 │ 42% 84000/200000`, kept for the hint row to draw.
const line = atom(
  { plugin: "statusline", key: "line" } as const,
  null as StatuslineLine,
);

export const register: Register = (on) => {
  on("session.start", async ($, e, next) => {
    const started = await next(e);
    await refreshLine($, (await $.session.usage()).context);
    return started;
  });

  // Refreshes the model after a `/model` switch, which lands between turns.
  on("turn.start", async ($, e, next) => {
    const turn = await next(e);
    await refreshLine($, (await $.session.usage()).context);
    return turn;
  });

  on("session.measure", async ($, e, next) => {
    const measured = await next(e);
    await refreshLine($, e.context);
    return measured;
  });

  // A row of its own under the engine's hint row: a tail on that row is cut at
  // its end, and dropped entirely on a narrow terminal.
  on("ui.render", { component: "PromptHint" }, async ($, e, next) => {
    const hint = await next(e);
    const text = await read($, line);
    if (text === null) return hint;

    const { Box, Text } = $.ui.resolve(e);
    return (
      <Box flexDirection="column">
        {hint}
        <Text dimColor>{text}</Text>
      </Box>
    );
  });
};

async function refreshLine(
  $: EngineInterface,
  context: SessionContextUsage,
): Promise<void> {
  const text = `${await $.session.model()} │ ${contextFill(context)}`;
  await update($, line, () => text);
}

// `tokens` and `percent` stay absent until the live window's first response.
function contextFill(context: SessionContextUsage): string {
  if (context.tokens === undefined || context.percent === undefined)
    return "0%";
  return `${context.percent}% ${context.tokens}/${context.window}`;
}
