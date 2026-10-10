import assert from "node:assert/strict";
import test from "node:test";

import {
  createTranscriptStamp,
  findLatestVisibleTranscriptStampTime,
  findLatestUnstampedTranscriptMessage,
  formatTranscriptStamp,
  isTranscriptStampData,
  TRANSCRIPT_STAMP_DEFAULTS,
  TRANSCRIPT_STAMP_ENTRY_TYPE,
} from "./stamp.ts";

function localTime(
  day: number,
  hour: number,
  minute: number,
  second: number,
): number {
  return new Date(2026, 0, day, hour, minute, second).getTime();
}

function localUtcOffset(timestamp: number): string {
  const offsetMinutes = -new Date(timestamp).getTimezoneOffset();
  const sign = offsetMinutes < 0 ? "-" : "+";
  const absoluteOffsetMinutes = Math.abs(offsetMinutes);
  const hours = Math.floor(absoluteOffsetMinutes / 60);
  const minutes = absoluteOffsetMinutes % 60;

  return `UTC${sign}${String(hours).padStart(2, "0")}:${String(minutes).padStart(2, "0")}`;
}

test("defaults are explicit and require no runtime configuration", () => {
  assert.deepEqual(TRANSCRIPT_STAMP_DEFAULTS, {
    timeZone: "local",
    hourCycle: "24h",
    showSeconds: true,
    showTimeZone: true,
    dateContext: "first-and-day-change",
    showAssistantDuration: true,
    showTurnDuration: true,
    showFirstContentLatency: true,
    showToolPerformance: true,
    showTokenRate: true,
  });
});

test("first stamp includes local date and subsequent same-day stamp stays compact", () => {
  const first = localTime(2, 14, 3, 4);
  const second = localTime(2, 14, 4, 5);

  assert.equal(
    formatTranscriptStamp(createTranscriptStamp("user", first)),
    `2026-01-02 · 14:03:04 ${localUtcOffset(first)}`,
  );
  assert.equal(
    formatTranscriptStamp(createTranscriptStamp("user", second, first)),
    `14:04:05`,
  );
});

test("local day changes restore date context", () => {
  const previous = localTime(2, 23, 59, 59);
  const current = localTime(3, 0, 0, 1);

  assert.equal(
    formatTranscriptStamp(createTranscriptStamp("user", current, previous)),
    `2026-01-03 · 00:00:01 ${localUtcOffset(current)}`,
  );
});

test("assistant duration favors compact human-scale precision", () => {
  const createdAt = localTime(2, 14, 3, 4);

  assert.equal(
    formatTranscriptStamp(
      createTranscriptStamp(
        "assistant",
        createdAt,
        createdAt - 1,
        createdAt + 325,
      ),
    ),
    `14:03:04 · response 325ms`,
  );
  assert.equal(
    formatTranscriptStamp(
      createTranscriptStamp(
        "assistant",
        createdAt,
        createdAt - 1,
        createdAt + 3_200,
      ),
    ),
    `14:03:04 · response 3.2s`,
  );
  assert.equal(
    formatTranscriptStamp(
      createTranscriptStamp(
        "assistant",
        createdAt,
        createdAt - 1,
        createdAt + 63_400,
      ),
    ),
    `14:03:04 · response 1m 03s`,
  );
});

test("assistant stamp distinguishes response and complete turn duration", () => {
  const turnStartedAt = localTime(2, 14, 3, 3);
  const createdAt = turnStartedAt + 1_000;
  const responseCompletedAt = createdAt + 3_200;
  const turnCompletedAt = turnStartedAt + 8_400;

  const stamp = createTranscriptStamp(
    "assistant",
    createdAt,
    createdAt - 1,
    responseCompletedAt,
    {
      startedAt: turnStartedAt,
      completedAt: turnCompletedAt,
    },
  );

  assert.equal(stamp.version, 3);
  assert.equal(
    formatTranscriptStamp(stamp),
    `14:03:04 · response 3.2s · turn 8.4s`,
  );
});

test("assistant stamp summarizes latency, tools, and token throughput", () => {
  const turnStartedAt = localTime(2, 14, 3, 3);
  const createdAt = turnStartedAt + 1_000;
  const firstContentAt = turnStartedAt + 1_500;
  const responseCompletedAt = createdAt + 3_500;
  const turnCompletedAt = turnStartedAt + 9_000;

  const stamp = createTranscriptStamp(
    "assistant",
    createdAt,
    createdAt - 1,
    responseCompletedAt,
    {
      startedAt: turnStartedAt,
      completedAt: turnCompletedAt,
      firstContentAt,
      outputTokens: 150,
      tools: {
        startedAt: turnStartedAt + 4_000,
        completedAt: turnStartedAt + 8_000,
        count: 3,
        errorCount: 1,
      },
    },
  );

  assert.equal(
    formatTranscriptStamp(stamp),
    `14:03:04 · first 1.5s · response 3.5s · turn 9.0s · tools 4.0s×3/1err · 50 tok/s`,
  );
});

test("persisted stamp validation rejects ambiguous or unsafe shapes", () => {
  const createdAt = localTime(2, 14, 3, 4);

  assert.equal(
    isTranscriptStampData(
      createTranscriptStamp("assistant", createdAt, undefined, createdAt + 1),
    ),
    true,
  );
  assert.equal(
    isTranscriptStampData(
      createTranscriptStamp("user", createdAt, undefined, createdAt + 1),
    ),
    false,
  );
  assert.equal(
    isTranscriptStampData(
      createTranscriptStamp("assistant", createdAt, undefined, createdAt - 1),
    ),
    false,
  );
  assert.equal(
    isTranscriptStampData({
      ...createTranscriptStamp("user", createdAt),
      unexpected: true,
    }),
    false,
  );
  const legacyTurnStamp = {
    version: 2,
    role: "assistant",
    createdAt,
    turnStartedAt: createdAt - 1_000,
    turnCompletedAt: createdAt + 3_000,
  };
  assert.equal(isTranscriptStampData(legacyTurnStamp), true);
  const turnStamp = createTranscriptStamp(
    "assistant",
    createdAt,
    undefined,
    createdAt + 2_000,
    {
      startedAt: createdAt - 1_000,
      completedAt: createdAt + 3_000,
    },
  );
  assert.equal(isTranscriptStampData(turnStamp), true);
  assert.equal(
    isTranscriptStampData({
      ...turnStamp,
      toolCount: 1,
    }),
    false,
  );
  assert.equal(
    isTranscriptStampData({
      ...turnStamp,
      turnCompletedAt: createdAt + 1_000,
    }),
    false,
  );
});

test("latest stamp lookup ignores unrelated and malformed session entries", () => {
  const older = localTime(2, 14, 3, 4);
  const newer = localTime(2, 14, 4, 5);
  const entries = [
    { type: "message", message: { role: "user", timestamp: older } },
    {
      type: "custom",
      customType: TRANSCRIPT_STAMP_ENTRY_TYPE,
      data: createTranscriptStamp("user", older),
    },
    {
      type: "custom",
      customType: TRANSCRIPT_STAMP_ENTRY_TYPE,
      data: { version: 99, role: "user", createdAt: newer },
    },
    {
      type: "custom",
      customType: TRANSCRIPT_STAMP_ENTRY_TYPE,
      data: createTranscriptStamp("assistant", newer, older, newer + 1),
    },
  ];

  assert.equal(findLatestVisibleTranscriptStampTime(entries), older);
  assert.equal(
    findLatestVisibleTranscriptStampTime(entries.slice(0, 1)),
    undefined,
  );
});

test("hidden assistant stamps do not consume visible day-change context", () => {
  const previousUser = localTime(2, 23, 59, 0);
  const nextDayAssistant = localTime(3, 0, 0, 5);
  const nextUser = localTime(3, 1, 0, 0);
  const entries = [
    {
      type: "custom",
      customType: TRANSCRIPT_STAMP_ENTRY_TYPE,
      data: createTranscriptStamp("user", previousUser),
    },
    {
      type: "custom",
      customType: TRANSCRIPT_STAMP_ENTRY_TYPE,
      data: createTranscriptStamp("assistant", nextDayAssistant, previousUser),
    },
  ];
  const previousVisibleAt = findLatestVisibleTranscriptStampTime(entries);
  assert.equal(previousVisibleAt, previousUser);
  assert.equal(
    formatTranscriptStamp(
      createTranscriptStamp("user", nextUser, previousVisibleAt),
    ),
    `2026-01-03 · 01:00:00 ${localUtcOffset(nextUser)}`,
  );
});

test("unstamped terminal message is detected for clone reconciliation", () => {
  const createdAt = localTime(2, 14, 3, 4);
  const message = {
    type: "message",
    message: {
      role: "user",
      timestamp: createdAt,
    },
  };

  assert.deepEqual(findLatestUnstampedTranscriptMessage([message]), {
    role: "user",
    createdAt,
  });
  assert.equal(
    findLatestUnstampedTranscriptMessage([
      message,
      {
        type: "custom",
        customType: TRANSCRIPT_STAMP_ENTRY_TYPE,
        data: createTranscriptStamp("user", createdAt),
      },
    ]),
    undefined,
  );
});
