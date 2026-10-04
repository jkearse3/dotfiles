import assert from "node:assert/strict";
import {
  lstatSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  readdirSync,
  renameSync,
  rmSync,
  symlinkSync,
  truncateSync,
  utimesSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import test from "node:test";
import {
  ConversationStorage,
  MAX_CONVERSATION_CATALOG_RECORDS,
  MAX_CONVERSATION_SESSION_BYTES,
  SUBAGENT_CONVERSATION_CATALOG_ENTRY_TYPE,
  deriveParentConversationScope,
  parseConversationCatalogSnapshot,
  parseConversationId,
  publicConversationError,
  reduceConversationCatalogEntries,
  serializeConversationCatalogSnapshot,
  updateConversationCatalog,
  type ConversationCatalogRecord,
  type ConversationId,
  type ParentConversationSession,
} from "./conversations.ts";

interface Fixture {
  disposableRoot: string;
  storageRoot: string;
  cwd: string;
  parent: ParentConversationSession;
  storage: ConversationStorage;
  cleanup(): void;
}

function fixture(
  options: {
    now?: () => number;
    isProcessAlive?: (pid: number) => boolean | undefined;
  } = {},
): Fixture {
  const disposableRoot = mkdtempSync(
    path.join(tmpdir(), "pi-conversations-test-"),
  );
  const storageRoot = path.join(disposableRoot, "state");
  const cwd = path.join(disposableRoot, "work");
  const sessionFilePath = path.join(disposableRoot, "parent-session.jsonl");
  mkdirSync(cwd);
  writeFileSync(sessionFilePath, "");
  const parent = { sessionFilePath, sessionId: "parent-session-id" };
  return {
    disposableRoot,
    storageRoot,
    cwd,
    parent,
    storage: new ConversationStorage({ root: storageRoot, ...options }),
    cleanup: () => rmSync(disposableRoot, { recursive: true, force: true }),
  };
}

function conversationDirectory(f: Fixture, conversationId: string): string {
  return path.join(
    f.storageRoot,
    deriveParentConversationScope(f.parent),
    conversationId,
  );
}

function active(conversationId: string): ReadonlySet<string> {
  return new Set([conversationId]);
}

function catalogRecord(
  index: number,
  lastUsedAt = index + 1,
): ConversationCatalogRecord {
  const suffix = index.toString(16).padStart(12, "0");
  return {
    conversationId: `00000000-0000-4000-8000-${suffix}` as ConversationId,
    label: `conversation ${index}`,
    cwd: "/canonical/work",
    createdAt: 0,
    lastUsedAt,
  };
}

test("creates private metadata, an exact empty session, and an opaque namespace", () => {
  const f = fixture({ now: () => 1_000 });
  try {
    const lease = f.storage.create({ parent: f.parent, cwd: f.cwd });
    const directory = conversationDirectory(f, lease.metadata.conversationId);
    assert.equal(
      parseConversationId(lease.metadata.conversationId),
      lease.metadata.conversationId,
    );
    assert.equal(readFileSync(lease.sessionFilePath, "utf8"), "");
    assert.equal(
      lease.sessionFilePath,
      path.join(directory, "child-session.jsonl"),
    );
    assert.deepEqual(
      JSON.parse(readFileSync(path.join(directory, "metadata.json"), "utf8")),
      lease.metadata,
    );
    assert.equal(
      path.basename(path.dirname(directory)),
      deriveParentConversationScope(f.parent),
    );
    assert.equal(
      path.dirname(directory).includes(path.basename(f.parent.sessionFilePath)),
      false,
    );

    if (process.platform !== "win32") {
      assert.equal(lstatSync(directory).mode & 0o777, 0o700);
      assert.equal(
        lstatSync(path.join(directory, "metadata.json")).mode & 0o777,
        0o600,
      );
      assert.equal(lstatSync(lease.sessionFilePath).mode & 0o777, 0o600);
      assert.equal(
        lstatSync(path.join(directory, "run.lock")).mode & 0o777,
        0o700,
      );
    }
    lease.release();
  } finally {
    f.cleanup();
  }
});

test("public storage errors retain useful domains without exposing private paths", () => {
  const privatePath = "/private/state/pi/subagent-conversations/secret";
  const filesystemError = Object.assign(
    new Error(`ENOENT: no such file or directory, lstat '${privatePath}'`),
    { code: "ENOENT" },
  );
  const sanitized = publicConversationError(filesystemError);
  assert.match(sanitized.message, /unavailable \(ENOENT\)/u);
  assert.doesNotMatch(sanitized.message, /private|secret/u);
  assert.equal(
    publicConversationError(
      new Error("Conversation cwd does not match metadata"),
    ).message,
    "Conversation cwd does not match metadata",
  );
  assert.equal(
    publicConversationError(
      new Error("Conversation skills do not match original selection"),
    ).message,
    "Conversation skills do not match original selection",
  );
  assert.equal(
    publicConversationError(
      new Error("Conversation predates skill policies; start fresh"),
    ).message,
    "Conversation predates skill policies; start fresh",
  );
});

test("strict IDs reject traversal and parent session identity separates namespaces", () => {
  const f = fixture();
  try {
    for (const invalid of [
      "../escape",
      "00000000-0000-0000-0000-000000000000",
      "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA",
    ]) {
      assert.throws(() => parseConversationId(invalid), /conversationId/u);
      assert.throws(
        () =>
          f.storage.resume({
            parent: f.parent,
            cwd: f.cwd,
            conversationId: invalid,
            activeConversationIds: active(invalid),
          }),
        /conversationId/u,
      );
    }

    const sameFileOtherId = { ...f.parent, sessionId: "another-session" };
    const otherFilePath = path.join(f.disposableRoot, "other-session.jsonl");
    writeFileSync(otherFilePath, "");
    const otherFile = {
      sessionFilePath: otherFilePath,
      sessionId: f.parent.sessionId,
    };
    assert.notEqual(
      deriveParentConversationScope(f.parent),
      deriveParentConversationScope(sameFileOtherId),
    );
    assert.notEqual(
      deriveParentConversationScope(f.parent),
      deriveParentConversationScope(otherFile),
    );
  } finally {
    f.cleanup();
  }
});

test("resume requires catalog authorization and exact canonical cwd, then atomically touches metadata", () => {
  let now = 10;
  const f = fixture({ now: () => now });
  try {
    const created = f.storage.create({ parent: f.parent, cwd: f.cwd });
    const conversationId = created.metadata.conversationId;
    created.release();
    assert.throws(
      () =>
        f.storage.resume({
          parent: f.parent,
          cwd: f.cwd,
          conversationId,
          activeConversationIds: new Set(),
        }),
      /active catalog/u,
    );

    const otherCwd = path.join(f.disposableRoot, "other-work");
    mkdirSync(otherCwd);
    assert.throws(
      () =>
        f.storage.resume({
          parent: f.parent,
          cwd: otherCwd,
          conversationId,
          activeConversationIds: active(conversationId),
        }),
      /cwd/u,
    );

    now = 20;
    const resumed = f.storage.resume({
      parent: f.parent,
      cwd: f.cwd,
      conversationId,
      activeConversationIds: active(conversationId),
    });
    assert.equal(resumed.metadata.createdAt, 10);
    assert.equal(resumed.metadata.lastUsedAt, 20);
    assert.equal(
      JSON.parse(
        readFileSync(
          path.join(conversationDirectory(f, conversationId), "metadata.json"),
          "utf8",
        ),
      ).lastUsedAt,
      20,
    );
    resumed.release();
  } finally {
    f.cleanup();
  }
});

test("resume preserves the original normalized skill policy", () => {
  const f = fixture();
  try {
    const created = f.storage.create({
      parent: f.parent,
      cwd: f.cwd,
      skills: ["plan-work", "diff-review"],
    });
    const conversationId = created.metadata.conversationId;
    assert.deepEqual(created.metadata.skills, ["diff-review", "plan-work"]);
    created.release();

    for (const skills of [undefined, [], ["diff-review"]] as const) {
      assert.throws(
        () =>
          f.storage.resume({
            parent: f.parent,
            cwd: f.cwd,
            conversationId,
            activeConversationIds: active(conversationId),
            skills,
          }),
        /skills do not match/u,
      );
    }

    const resumed = f.storage.resume({
      parent: f.parent,
      cwd: f.cwd,
      conversationId,
      activeConversationIds: active(conversationId),
      skills: ["diff-review", "plan-work"],
    });
    resumed.release();
  } finally {
    f.cleanup();
  }
});

test("legacy conversations without a skill policy must start fresh", () => {
  const f = fixture();
  try {
    const created = f.storage.create({ parent: f.parent, cwd: f.cwd });
    const conversationId = created.metadata.conversationId;
    const metadataPath = path.join(
      conversationDirectory(f, conversationId),
      "metadata.json",
    );
    created.release();

    const legacy = JSON.parse(readFileSync(metadataPath, "utf8"));
    legacy.version = 1;
    delete legacy.skills;
    writeFileSync(metadataPath, JSON.stringify(legacy));

    assert.throws(
      () =>
        f.storage.resume({
          parent: f.parent,
          cwd: f.cwd,
          conversationId,
          activeConversationIds: active(conversationId),
        }),
      /predates skill policies/u,
    );
  } finally {
    f.cleanup();
  }
});

test("resume fails closed for missing, corrupt, oversized, and symlink session files", () => {
  const scenarios: Array<{
    name: string;
    mutate(sessionPath: string): void;
    message: RegExp;
  }> = [
    {
      name: "missing",
      mutate: (sessionPath) => rmSync(sessionPath),
      message: /ENOENT/u,
    },
    {
      name: "directory",
      mutate: (sessionPath) => {
        rmSync(sessionPath);
        mkdirSync(sessionPath);
      },
      message: /regular file/u,
    },
    {
      name: "oversized",
      mutate: (sessionPath) =>
        truncateSync(sessionPath, MAX_CONVERSATION_SESSION_BYTES + 1),
      message: /64 MiB/u,
    },
    {
      name: "symlink",
      mutate: (sessionPath) => {
        const target = `${sessionPath}.target`;
        writeFileSync(target, "");
        rmSync(sessionPath);
        symlinkSync(target, sessionPath);
      },
      message: /non-symlink regular file/u,
    },
  ];
  for (const scenario of scenarios) {
    const f = fixture();
    try {
      const created = f.storage.create({ parent: f.parent, cwd: f.cwd });
      const conversationId = created.metadata.conversationId;
      created.release();
      scenario.mutate(created.sessionFilePath);
      assert.throws(
        () =>
          f.storage.resume({
            parent: f.parent,
            cwd: f.cwd,
            conversationId,
            activeConversationIds: active(conversationId),
          }),
        scenario.message,
        scenario.name,
      );
    } finally {
      f.cleanup();
    }
  }
});

test("resume rejects malformed metadata and never recreates missing durable state", () => {
  const f = fixture();
  try {
    const created = f.storage.create({ parent: f.parent, cwd: f.cwd });
    const conversationId = created.metadata.conversationId;
    const directory = conversationDirectory(f, conversationId);
    created.release();
    const metadataPath = path.join(directory, "metadata.json");
    const metadataTarget = `${metadataPath}.target`;
    renameSync(metadataPath, metadataTarget);
    symlinkSync(metadataTarget, metadataPath);
    assert.throws(
      () =>
        f.storage.resume({
          parent: f.parent,
          cwd: f.cwd,
          conversationId,
          activeConversationIds: active(conversationId),
        }),
      /non-symlink regular file/u,
    );
    rmSync(metadataPath);
    renameSync(metadataTarget, metadataPath);

    writeFileSync(metadataPath, "{broken", { mode: 0o600 });
    assert.throws(
      () =>
        f.storage.resume({
          parent: f.parent,
          cwd: f.cwd,
          conversationId,
          activeConversationIds: active(conversationId),
        }),
      /metadata is malformed/u,
    );

    rmSync(directory, { recursive: true });
    assert.throws(
      () =>
        f.storage.resume({
          parent: f.parent,
          cwd: f.cwd,
          conversationId,
          activeConversationIds: active(conversationId),
        }),
      /ENOENT/u,
    );
    assert.equal(lstatExists(directory), false);
  } finally {
    f.cleanup();
  }
});

test("lock excludes live owners, records children, releases once, and recovers only definitely dead locks", () => {
  const f = fixture({ isProcessAlive: () => true });
  try {
    const first = f.storage.create({ parent: f.parent, cwd: f.cwd });
    const conversationId = first.metadata.conversationId;
    first.recordChildPid(4242);
    assert.throws(
      () =>
        f.storage.resume({
          parent: f.parent,
          cwd: f.cwd,
          conversationId,
          activeConversationIds: active(conversationId),
        }),
      /already running/u,
    );
    first.release();
    first.release();

    const second = f.storage.resume({
      parent: f.parent,
      cwd: f.cwd,
      conversationId,
      activeConversationIds: active(conversationId),
    });
    const lockPath = path.join(
      conversationDirectory(f, conversationId),
      "run.lock",
    );
    assert.equal(
      JSON.parse(readFileSync(path.join(lockPath, "owner.json"), "utf8"))
        .ownerPid,
      process.pid,
    );

    second.recordChildPid(4243);
    const deadStorage = new ConversationStorage({
      root: f.storageRoot,
      isProcessAlive: () => false,
    });
    assert.throws(
      () =>
        new ConversationStorage({
          root: f.storageRoot,
          isProcessAlive: () => undefined,
        }).resume({
          parent: f.parent,
          cwd: f.cwd,
          conversationId,
          activeConversationIds: active(conversationId),
        }),
      /cannot be verified/u,
    );
    const recovered = deadStorage.resume({
      parent: f.parent,
      cwd: f.cwd,
      conversationId,
      activeConversationIds: active(conversationId),
    });
    second.release();
    assert.equal(
      lstatExists(lockPath),
      true,
      "stale lease cannot release the replacement lock",
    );
    recovered.release();
    assert.equal(lstatExists(lockPath), false);

    const unconfirmed = f.storage.resume({
      parent: f.parent,
      cwd: f.cwd,
      conversationId,
      activeConversationIds: active(conversationId),
    });
    assert.throws(
      () =>
        deadStorage.resume({
          parent: f.parent,
          cwd: f.cwd,
          conversationId,
          activeConversationIds: active(conversationId),
        }),
      /cannot be verified/u,
      "a dead owner without a confirmed child PID stays fail-closed",
    );
    unconfirmed.release();
  } finally {
    f.cleanup();
  }
});

test("resume enforces inactivity expiry even before a cleanup pass", () => {
  let now = 0;
  const f = fixture({ now: () => now });
  try {
    const created = f.storage.create({ parent: f.parent, cwd: f.cwd });
    const conversationId = created.metadata.conversationId;
    created.release();
    now = 31 * 24 * 60 * 60 * 1000;
    assert.throws(
      () =>
        f.storage.resume({
          parent: f.parent,
          cwd: f.cwd,
          conversationId,
          activeConversationIds: active(conversationId),
        }),
      /expired after 30 days/u,
    );
    assert.equal(
      lstatExists(
        path.join(conversationDirectory(f, conversationId), "run.lock"),
      ),
      false,
    );
  } finally {
    f.cleanup();
  }
});

test("catalog parsing and branch reduction fail closed on malformed or unknown snapshots", () => {
  const record = catalogRecord(1);
  const snapshot = serializeConversationCatalogSnapshot([record]);
  assert.equal(
    parseConversationCatalogSnapshot({ version: 2, records: [] }),
    undefined,
  );
  assert.equal(
    parseConversationCatalogSnapshot({
      version: 1,
      records: [{ ...record, storagePath: "/secret" }],
    }),
    undefined,
  );
  assert.equal(
    parseConversationCatalogSnapshot({
      version: 1,
      records: [{ ...record, cwd: `/${"x".repeat(4096)}` }],
    }),
    undefined,
  );
  assert.equal(
    parseConversationCatalogSnapshot({
      version: 1,
      records: [{ ...record, lastUsedAt: Number.MAX_SAFE_INTEGER }],
    }),
    undefined,
  );

  const validEntry = {
    type: "custom",
    customType: SUBAGENT_CONVERSATION_CATALOG_ENTRY_TYPE,
    data: snapshot,
  };
  assert.deepEqual(
    reduceConversationCatalogEntries([{ type: "message" }, validEntry]),
    [record],
  );
  assert.deepEqual(
    reduceConversationCatalogEntries([
      validEntry,
      {
        type: "custom",
        customType: SUBAGENT_CONVERSATION_CATALOG_ENTRY_TYPE,
        data: { version: 99, records: [] },
      },
    ]),
    [],
  );
  assert.deepEqual(
    reduceConversationCatalogEntries([
      validEntry,
      { type: "custom", customType: "other", data: {} },
    ]),
    [record],
  );
});

test("catalog touches by ID and evicts least-recently-used records without storage paths", () => {
  let records: ConversationCatalogRecord[] = [];
  for (
    let index = 0;
    index < MAX_CONVERSATION_CATALOG_RECORDS + 3;
    index += 1
  ) {
    records = updateConversationCatalog(records, catalogRecord(index));
  }
  assert.equal(records.length, MAX_CONVERSATION_CATALOG_RECORDS);
  assert.equal(
    records.some(
      (record) => record.conversationId === catalogRecord(0).conversationId,
    ),
    false,
  );
  assert.equal(records[0]!.lastUsedAt, MAX_CONVERSATION_CATALOG_RECORDS + 3);

  const existing = records.at(-1)!;
  records = updateConversationCatalog(records, {
    ...existing,
    label: "touched",
    createdAt: 999,
    lastUsedAt: 10_000,
  });
  assert.equal(records[0]!.label, "touched");
  assert.equal(records[0]!.createdAt, existing.createdAt);
  assert.equal("storagePath" in records[0]!, false);
});

test("storage rejects symlink roots and conversation-directory substitutions", () => {
  const f = fixture();
  try {
    const actualRoot = path.join(f.disposableRoot, "actual-state");
    mkdirSync(actualRoot);
    const linkedRoot = path.join(f.disposableRoot, "linked-state");
    symlinkSync(actualRoot, linkedRoot);
    assert.throws(
      () =>
        new ConversationStorage({ root: linkedRoot }).create({
          parent: f.parent,
          cwd: f.cwd,
        }),
      /symlink/u,
    );

    const created = f.storage.create({ parent: f.parent, cwd: f.cwd });
    const conversationId = created.metadata.conversationId;
    const directory = conversationDirectory(f, conversationId);
    created.release();
    const moved = `${directory}.moved`;
    renameForTest(directory, moved);
    symlinkSync(moved, directory);
    assert.throws(
      () =>
        f.storage.resume({
          parent: f.parent,
          cwd: f.cwd,
          conversationId,
          activeConversationIds: active(conversationId),
        }),
      /non-symlink directory/u,
    );
  } finally {
    f.cleanup();
  }
});

test("cleanup and execution use the same exclusive conversation lock", () => {
  const now = 40 * 24 * 60 * 60 * 1000;
  const f = fixture({ now: () => now });
  try {
    const oldStorage = new ConversationStorage({
      root: f.storageRoot,
      now: () => 0,
    });
    const activeLease = oldStorage.create({ parent: f.parent, cwd: f.cwd });
    const directory = conversationDirectory(
      f,
      activeLease.metadata.conversationId,
    );
    assert.equal(f.storage.cleanup(f.parent), 0);
    assert.equal(lstatExists(directory), true);
    activeLease.release();
    assert.equal(f.storage.cleanup(f.parent), 1);
    assert.equal(lstatExists(directory), false);
  } finally {
    f.cleanup();
  }
});

test("cleanup recovers confirmed dead locks but retains spawn-pending locks", () => {
  const now = 40 * 24 * 60 * 60 * 1000;
  const f = fixture({ now: () => now, isProcessAlive: () => false });
  try {
    const oldStorage = new ConversationStorage({
      root: f.storageRoot,
      now: () => 0,
      isProcessAlive: () => false,
    });
    const confirmed = oldStorage.create({ parent: f.parent, cwd: f.cwd });
    confirmed.recordChildPid(4242);
    const confirmedDirectory = conversationDirectory(
      f,
      confirmed.metadata.conversationId,
    );
    const pending = oldStorage.create({ parent: f.parent, cwd: f.cwd });
    const pendingDirectory = conversationDirectory(
      f,
      pending.metadata.conversationId,
    );

    assert.equal(f.storage.cleanup(f.parent), 1);
    assert.equal(lstatExists(confirmedDirectory), false);
    assert.equal(lstatExists(pendingDirectory), true);
    pending.release();
  } finally {
    f.cleanup();
  }
});

test("cleanup is parent-scoped, skips locks and symlinks, expires orphans, and examines at most 128 entries", () => {
  const now = 40 * 24 * 60 * 60 * 1000;
  const f = fixture({ now: () => now });
  try {
    const oldStorage = new ConversationStorage({
      root: f.storageRoot,
      now: () => 0,
    });
    const expired = oldStorage.create({ parent: f.parent, cwd: f.cwd });
    const expiredDirectory = conversationDirectory(
      f,
      expired.metadata.conversationId,
    );
    expired.release();

    const scope = deriveParentConversationScope(f.parent);
    const namespace = path.join(f.storageRoot, scope);
    mkdirSync(namespace, { recursive: true });
    const old = new Date(0);
    for (let index = 0; index < 130; index += 1) {
      const orphan = path.join(
        namespace,
        `orphan-${index.toString().padStart(3, "0")}`,
      );
      mkdirSync(orphan);
      utimesSync(orphan, old, old);
    }
    const locked = path.join(namespace, "00000000-0000-4000-8000-ffffffffffff");
    mkdirSync(path.join(locked, "run.lock"), { recursive: true });
    utimesSync(locked, old, old);
    const freshOrphan = path.join(namespace, "fresh-orphan");
    mkdirSync(freshOrphan);
    const fresh = new Date(now);
    utimesSync(freshOrphan, fresh, fresh);
    const outside = path.join(f.disposableRoot, "outside");
    mkdirSync(outside);
    const linked = path.join(namespace, "linked-orphan");
    symlinkSync(outside, linked);

    const removed = f.storage.cleanup(f.parent);
    assert.ok(removed <= 128);
    assert.equal(lstatExists(path.join(namespace, "orphan-000")), false);
    assert.ok(
      remainingDirectories(namespace) >= 2,
      "bounded pass leaves entries for later cleanup",
    );
    assert.equal(lstatExists(expiredDirectory), false);
    assert.equal(lstatExists(locked), true);
    assert.equal(lstatExists(freshOrphan), true);
    assert.equal(lstatExists(linked), true);
    assert.equal(lstatExists(outside), true);
    f.storage.cleanup(f.parent);
    assert.equal(lstatExists(path.join(namespace, "orphan-129")), false);

    const otherParent = { ...f.parent, sessionId: "other-parent" };
    assert.equal(f.storage.cleanup(otherParent), 0);
    assert.equal(lstatExists(namespace), true);
  } finally {
    f.cleanup();
  }
});

function lstatExists(candidate: string): boolean {
  try {
    lstatSync(candidate);
    return true;
  } catch {
    return false;
  }
}

function remainingDirectories(candidate: string): number {
  return readdirSync(candidate).length;
}

function renameForTest(source: string, destination: string): void {
  renameSync(source, destination);
}
