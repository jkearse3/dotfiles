import type {
  EntryRenderer,
  ExtensionAPI,
} from "@earendil-works/pi-coding-agent";
import { truncateToWidth, visibleWidth } from "@earendil-works/pi-tui";
import {
  AGENT_ELAPSED_ENTRY_TYPE,
  formatAgentElapsed,
  type AgentElapsedData,
} from "./agent-elapsed.ts";

import { registerTranscriptStampLifecycle } from "./lifecycle.ts";
import {
  createLeftAlignedTranscriptStamp,
  createToggleableTranscriptStamp,
} from "./renderer.ts";
import {
  formatTranscriptStamp,
  formatTranscriptTime,
  isTranscriptStampData,
  TRANSCRIPT_STAMP_ENTRY_TYPE,
  type TranscriptStampData,
} from "./stamp.ts";
import { createInlineTimingsState, registerTimingsCommand } from "./timings.ts";

/**
 * Shows user stamps and agent summaries by default; /timings toggles stored
 * assistant turn timing rows without adding content to model context.
 */
export default function transcriptStampsExtension(pi: ExtensionAPI): void {
  const timings = createInlineTimingsState();
  pi.registerEntryRenderer(
    TRANSCRIPT_STAMP_ENTRY_TYPE,
    createTranscriptStampRenderer(timings.isVisible),
  );
  pi.registerEntryRenderer(
    AGENT_ELAPSED_ENTRY_TYPE,
    createAgentElapsedRenderer(),
  );
  registerTranscriptStampLifecycle(pi);
  registerTimingsCommand(pi, timings);
}

function createTranscriptStampRenderer(
  isTimingsVisible: () => boolean,
): EntryRenderer<TranscriptStampData> {
  return (entry, _options, theme) => {
    if (!isTranscriptStampData(entry.data)) return undefined;
    const assistant = entry.data.role === "assistant";
    const label = assistant
      ? formatTranscriptStamp(entry.data)
      : formatTranscriptTime(
          entry.data.createdAt,
          entry.data.previousCreatedAt,
        );
    if (!label) return undefined;

    const stamp = createLeftAlignedTranscriptStamp(
      label,
      (text) => theme.fg("dim", text),
      {
        truncate: (text, width) => truncateToWidth(text, width, ""),
        measure: visibleWidth,
      },
    );

    return assistant
      ? createToggleableTranscriptStamp(stamp, isTimingsVisible)
      : stamp;
  };
}

function createAgentElapsedRenderer(): EntryRenderer<AgentElapsedData> {
  return (entry, _options, theme) => {
    const label = entry.data && formatAgentElapsed(entry.data);
    if (!label) return undefined;

    return createLeftAlignedTranscriptStamp(
      label,
      (text) => theme.fg("dim", text),
      {
        truncate: (text, width) => truncateToWidth(text, width, ""),
        measure: visibleWidth,
      },
    );
  };
}
