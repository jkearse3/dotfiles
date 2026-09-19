/** Minimal render lifecycle used by Pi transcript stamp components. */
export interface TranscriptStampComponent {
  render(width: number): string[];
  invalidate(): void;
}

/** Terminal-aware text operations supplied by Pi's TUI runtime. */
export interface TranscriptStampTextLayout {
  truncate(text: string, width: number): string;
  measure(text: string): number;
}

const TRANSCRIPT_STAMP_RIGHT_PADDING = 1;

/** Creates a right-aligned stamp that reserves the final terminal column. */
export function createRightAlignedTranscriptStamp(
  label: string,
  style: (text: string) => string,
  textLayout: Readonly<TranscriptStampTextLayout>,
): TranscriptStampComponent {
  let cachedWidth: number | undefined;
  let cachedOutput: string[] | undefined;

  return {
    render(width) {
      if (width < 1) return [];
      if (cachedWidth === width && cachedOutput) return cachedOutput;

      const rightPadding = " ".repeat(TRANSCRIPT_STAMP_RIGHT_PADDING);
      const contentWidth = Math.max(0, width - TRANSCRIPT_STAMP_RIGHT_PADDING);
      const styledLabel = textLayout.truncate(style(label), contentWidth);
      const leftPadding = " ".repeat(
        Math.max(0, contentWidth - textLayout.measure(styledLabel)),
      );
      cachedWidth = width;
      cachedOutput = [`${leftPadding}${styledLabel}${rightPadding}`];
      return cachedOutput;
    },
    invalidate() {
      cachedWidth = undefined;
      cachedOutput = undefined;
    },
  };
}
