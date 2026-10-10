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

/** Reuses the same inline stamp while its visibility changes at render time. */
export function createToggleableTranscriptStamp(
  stamp: TranscriptStampComponent,
  isVisible: () => boolean,
): TranscriptStampComponent {
  return {
    render: (width) => (isVisible() ? stamp.render(width) : []),
    invalidate: () => stamp.invalidate(),
  };
}

const TRANSCRIPT_STAMP_RIGHT_PADDING = 1;

/** Creates a left-aligned stamp that reserves the final terminal column. */
export function createLeftAlignedTranscriptStamp(
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

      const contentWidth = Math.max(0, width - TRANSCRIPT_STAMP_RIGHT_PADDING);
      const styledLabel = textLayout.truncate(style(label), contentWidth);
      const trailingPadding = " ".repeat(
        Math.max(0, width - textLayout.measure(styledLabel)),
      );
      cachedWidth = width;
      cachedOutput = [`${styledLabel}${trailingPadding}`];
      return cachedOutput;
    },
    invalidate() {
      cachedWidth = undefined;
      cachedOutput = undefined;
    },
  };
}
