import type {
  EntryRenderer,
  ExtensionAPI,
} from "@earendil-works/pi-coding-agent";
import { truncateToWidth, visibleWidth } from "@earendil-works/pi-tui";

import { registerTranscriptStampLifecycle } from "./lifecycle.ts";
import { createRightAlignedTranscriptStamp } from "./renderer.ts";
import {
  formatTranscriptStamp,
  isTranscriptStampData,
  TRANSCRIPT_STAMP_ENTRY_TYPE,
  type TranscriptStampData,
} from "./stamp.ts";

/**
 * Adds quiet, right-aligned timestamps and local turn-performance observations
 * to the interactive transcript without timers, I/O, or model-context content.
 */
export default function transcriptStampsExtension(pi: ExtensionAPI): void {
  pi.registerEntryRenderer(
    TRANSCRIPT_STAMP_ENTRY_TYPE,
    createTranscriptStampRenderer(),
  );
  registerTranscriptStampLifecycle(pi);
}

function createTranscriptStampRenderer(): EntryRenderer<TranscriptStampData> {
  return (entry, _options, theme) => {
    if (!isTranscriptStampData(entry.data)) return undefined;

    const label = formatTranscriptStamp(entry.data);
    if (!label) return undefined;

    return createRightAlignedTranscriptStamp(
      label,
      (text) => theme.fg("dim", text),
      {
        truncate: (text, width) => truncateToWidth(text, width, ""),
        measure: visibleWidth,
      },
    );
  };
}
