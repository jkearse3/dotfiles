import type {
  EntryRenderer,
  ExtensionAPI,
} from "@earendil-works/pi-coding-agent";
import {
  truncateToWidth,
  visibleWidth,
  type Component,
} from "@earendil-works/pi-tui";

import { registerTranscriptStampLifecycle } from "./lifecycle.ts";
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

    return createRightAlignedStamp(label, (text) => theme.fg("dim", text));
  };
}

function createRightAlignedStamp(
  label: string,
  style: (text: string) => string,
): Component {
  let cachedWidth: number | undefined;
  let cachedOutput: string[] | undefined;

  return {
    render(width) {
      if (width < 1) return [];
      if (cachedWidth === width && cachedOutput) return cachedOutput;

      const styledLabel = truncateToWidth(style(label), width, "");
      const padding = " ".repeat(
        Math.max(0, width - visibleWidth(styledLabel)),
      );
      cachedWidth = width;
      cachedOutput = [`${padding}${styledLabel}`];
      return cachedOutput;
    },
    invalidate() {
      cachedWidth = undefined;
      cachedOutput = undefined;
    },
  };
}
