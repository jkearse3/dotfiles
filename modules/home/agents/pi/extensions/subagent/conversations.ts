import { createHash, randomUUID } from "node:crypto";
import {
  chmodSync,
  closeSync,
  lstatSync,
  mkdirSync,
  openSync,
  readFileSync,
  readdirSync,
  realpathSync,
  renameSync,
  rmSync,
  statSync,
  writeFileSync,
} from "node:fs";
import os from "node:os";
import path from "node:path";

/** Pi custom-entry type containing the active branch's conversation catalog snapshot. */
export const SUBAGENT_CONVERSATION_CATALOG_ENTRY_TYPE =
  "dotfiles.subagent-conversations.v1";

/** Maximum number of durable conversations advertised by one active branch. */
export const MAX_CONVERSATION_CATALOG_RECORDS = 32;

/** Maximum accepted child session size in bytes. */
export const MAX_CONVERSATION_SESSION_BYTES = 64 * 1024 * 1024;

/** Conversation storage expires after this much inactivity. */
export const MAX_CONVERSATION_AGE_MS = 30 * 24 * 60 * 60 * 1000;

const METADATA_VERSION = 2;
const CATALOG_VERSION = 1;
const CLEANUP_MAX_ENTRIES = 128;
const CONVERSATION_ID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/u;
const MAX_CATALOG_CWD_CHARACTERS = 4096;
const MAX_DATE_TIMESTAMP = 8_640_000_000_000_000;

/** Opaque UUID identifying a durable child conversation. */
export type ConversationId = string & {
  readonly __conversationId: unique symbol;
};

/** Catalog record persisted in the parent Pi session; it contains no storage paths. */
export interface ConversationCatalogRecord {
  conversationId: ConversationId;
  label: string;
  cwd: string;
  createdAt: number;
  lastUsedAt: number;
}

/** Versioned active-branch snapshot stored as Pi custom-entry data. */
export interface ConversationCatalogSnapshot {
  version: 1;
  records: ConversationCatalogRecord[];
}

/** Parses strict catalog snapshot data; malformed or unknown versions return undefined. */
export function parseConversationCatalogSnapshot(
  value: unknown,
): ConversationCatalogSnapshot | undefined {
  if (!isRecord(value) || !hasExactKeys(value, ["version", "records"]))
    return undefined;
  if (value.version !== CATALOG_VERSION || !Array.isArray(value.records))
    return undefined;
  if (value.records.length > MAX_CONVERSATION_CATALOG_RECORDS) return undefined;

  const records: ConversationCatalogRecord[] = [];
  const seen = new Set<string>();
  for (const valueRecord of value.records) {
    const record = parseCatalogRecord(valueRecord);
    if (!record || seen.has(record.conversationId)) return undefined;
    seen.add(record.conversationId);
    records.push(record);
  }
  return { version: CATALOG_VERSION, records };
}

/** Reconstructs the latest strict catalog snapshot from active-branch custom entries. */
export function reduceConversationCatalogEntries(
  entries: readonly unknown[],
): ConversationCatalogRecord[] {
  let records: ConversationCatalogRecord[] = [];
  for (const entry of entries) {
    if (!isRecord(entry) || entry.type !== "custom") continue;
    if (entry.customType !== SUBAGENT_CONVERSATION_CATALOG_ENTRY_TYPE) continue;

    const snapshot = parseConversationCatalogSnapshot(entry.data);
    if (!snapshot) return [];
    records = snapshot.records;
  }
  return records;
}

/** Validates and clones at most 32 records as versioned Pi custom-entry data. */
export function serializeConversationCatalogSnapshot(
  records: readonly ConversationCatalogRecord[],
): ConversationCatalogSnapshot {
  const snapshot = parseConversationCatalogSnapshot({
    version: CATALOG_VERSION,
    records,
  });
  if (!snapshot) throw new Error("Conversation catalog snapshot is invalid");
  return snapshot;
}

/** Adds or touches one record and evicts only least-recently-used catalog records. */
export function updateConversationCatalog(
  records: readonly ConversationCatalogRecord[],
  update: ConversationCatalogRecord,
): ConversationCatalogRecord[] {
  const current = serializeConversationCatalogSnapshot(records).records;
  const parsedUpdate = parseCatalogRecord(update);
  if (!parsedUpdate) throw new Error("Conversation catalog record is invalid");

  const previous = current.find(
    (record) => record.conversationId === parsedUpdate.conversationId,
  );
  const touched: ConversationCatalogRecord = previous
    ? {
        ...parsedUpdate,
        createdAt: previous.createdAt,
      }
    : parsedUpdate;
  return [
    ...current.filter(
      (record) => record.conversationId !== touched.conversationId,
    ),
    touched,
  ]
    .sort(
      (left, right) =>
        right.lastUsedAt - left.lastUsedAt ||
        left.conversationId.localeCompare(right.conversationId),
    )
    .slice(0, MAX_CONVERSATION_CATALOG_RECORDS);
}

function parseCatalogRecord(
  value: unknown,
): ConversationCatalogRecord | undefined {
  if (
    !isRecord(value) ||
    !hasExactKeys(value, [
      "conversationId",
      "label",
      "cwd",
      "createdAt",
      "lastUsedAt",
    ])
  ) {
    return undefined;
  }
  if (
    typeof value.conversationId !== "string" ||
    !CONVERSATION_ID_PATTERN.test(value.conversationId)
  )
    return undefined;
  if (
    typeof value.label !== "string" ||
    value.label.length === 0 ||
    value.label.length > 80 ||
    value.label.trim() !== value.label ||
    /[\u0000-\u001f\u007f]/u.test(value.label)
  )
    return undefined;
  if (
    typeof value.cwd !== "string" ||
    value.cwd.length > MAX_CATALOG_CWD_CHARACTERS ||
    !isCanonicalAbsolutePath(value.cwd)
  )
    return undefined;
  if (
    !isTimestamp(value.createdAt) ||
    !isTimestamp(value.lastUsedAt) ||
    value.lastUsedAt < value.createdAt
  )
    return undefined;
  return {
    conversationId: value.conversationId as ConversationId,
    label: value.label,
    cwd: value.cwd,
    createdAt: value.createdAt,
    lastUsedAt: value.lastUsedAt,
  };
}

/** Persisted, caller-safe attributes for one durable child conversation. */
export interface ConversationMetadata {
  version: 2;
  parentScope: string;
  conversationId: ConversationId;
  cwd: string;
  createdAt: number;
  lastUsedAt: number;
  /** Immutable normalized skill policy; null means configured discovery. */
  skills: string[] | null;
}

/** Dependencies controlling the durable namespace, clock, and process probes. */
export interface ConversationStorageOptions {
  root?: string;
  now?: () => number;
  isProcessAlive?: (pid: number) => boolean | undefined;
}

/** Identifies the persisted parent session that owns a storage namespace. */
export interface ParentConversationSession {
  sessionFilePath: string;
  sessionId: string;
}

/** Inputs for creating a fresh durable conversation. */
export interface CreateConversationInput {
  parent: ParentConversationSession;
  cwd: string;
  /** Omitted means configured discovery; an empty array means no skills. */
  skills?: readonly string[];
}

/** Inputs for resuming a catalog-authorized durable conversation. */
export interface ResumeConversationInput extends CreateConversationInput {
  conversationId: string;
  activeConversationIds: ReadonlySet<string>;
}

/** Exclusive execution lease over one durable child conversation. */
export interface ConversationLease {
  readonly metadata: Readonly<ConversationMetadata>;
  readonly sessionFilePath: string;
  /** Records the successfully spawned child PID while retaining the lease nonce. */
  recordChildPid(pid: number): void;
  /** Releases only the lock still owned by this lease; repeated calls are harmless. */
  release(): void;
}

/** Returns the default private durable root without creating it. */
export function defaultConversationStorageRoot(): string {
  const stateHome = process.env.XDG_STATE_HOME?.trim();
  return path.join(
    stateHome || path.join(os.homedir(), ".local", "state"),
    "pi",
    "subagent-conversations",
  );
}

/** Generates a canonical lowercase UUIDv4 conversation identifier. */
export function createConversationId(): ConversationId {
  return randomUUID() as ConversationId;
}

/** Validates and brands only canonical lowercase UUIDv4 conversation identifiers. */
export function parseConversationId(value: string): ConversationId {
  if (!CONVERSATION_ID_PATTERN.test(value)) {
    throw new Error("Invalid conversationId: expected canonical UUIDv4");
  }
  return value as ConversationId;
}

/** Converts storage failures to bounded path-free errors safe for tool results. */
export function publicConversationError(error: unknown): Error {
  const message = error instanceof Error ? error.message : String(error);
  const safeMessages = [
    /^Invalid conversationId:/u,
    /^Conversation is not authorized by the active catalog$/u,
    /^Conversation cwd does not match metadata$/u,
    /^Conversation expired after 30 days without use$/u,
    /^Conversation is already running or its lock cannot be verified$/u,
    /^Child session file exceeds 64 MiB$/u,
    /^Conversation skills do not match original selection$/u,
    /^Conversation predates skill policies; start fresh$/u,
  ];
  if (safeMessages.some((pattern) => pattern.test(message)))
    return new Error(message);
  const code = errorCode(error);
  return new Error(
    `Conversation storage is unavailable${code ? ` (${code})` : ""}`,
  );
}

/** Derives a path-hiding parent namespace from a canonical persisted session file and ID. */
export function deriveParentConversationScope(
  parent: ParentConversationSession,
): string {
  if (!parent.sessionId || parent.sessionId.length > 1024) {
    throw new Error("Parent session ID is invalid");
  }

  const sessionFilePath = canonicalRegularFile(
    parent.sessionFilePath,
    "Parent session file",
  );
  return createHash("sha256")
    .update("pi-subagent-conversations\0")
    .update(sessionFilePath)
    .update("\0")
    .update(parent.sessionId)
    .digest("hex");
}

/** Creates, resumes, locks, and expires conversations beneath one private root. */
export class ConversationStorage {
  private readonly root: string;
  private readonly now: () => number;
  private readonly isProcessAlive: (pid: number) => boolean | undefined;
  private readonly cleanupOffsets = new Map<string, number>();

  constructor(options: ConversationStorageOptions = {}) {
    this.root = path.resolve(options.root ?? defaultConversationStorageRoot());
    this.now = options.now ?? Date.now;
    this.isProcessAlive = options.isProcessAlive ?? probeProcessAlive;
  }

  /** Creates an empty exact child session and returns its exclusive execution lease. */
  create(input: CreateConversationInput): ConversationLease {
    const parentScope = deriveParentConversationScope(input.parent);
    const cwd = canonicalDirectory(input.cwd, "Conversation cwd");
    const skills = normalizeSkillPolicy(input.skills) ?? null;
    const namespace = this.ensureNamespace(parentScope);
    const createdAt = validNow(this.now());

    for (let attempt = 0; attempt < 8; attempt += 1) {
      const conversationId = createConversationId();
      const conversationDirectory = containedPath(namespace, conversationId);
      try {
        mkdirSync(conversationDirectory, { mode: 0o700 });
      } catch (error) {
        if (errorCode(error) === "EEXIST") continue;
        throw error;
      }

      const metadata: ConversationMetadata = {
        version: METADATA_VERSION,
        parentScope,
        conversationId,
        cwd,
        createdAt,
        lastUsedAt: createdAt,
        skills,
      };
      try {
        writeNewPrivateFile(
          path.join(conversationDirectory, "metadata.json"),
          JSON.stringify(metadata),
        );
        writeNewPrivateFile(
          path.join(conversationDirectory, "child-session.jsonl"),
          "",
        );
        return this.acquireLease(conversationDirectory, metadata);
      } catch (error) {
        rmSync(conversationDirectory, { recursive: true, force: true });
        throw error;
      }
    }

    throw new Error("Unable to allocate a unique conversationId");
  }

  /** Resumes only an active-catalog conversation in the exact canonical cwd. */
  resume(input: ResumeConversationInput): ConversationLease {
    const conversationId = parseConversationId(input.conversationId);
    if (!input.activeConversationIds.has(conversationId)) {
      throw new Error("Conversation is not authorized by the active catalog");
    }

    const parentScope = deriveParentConversationScope(input.parent);
    const cwd = canonicalDirectory(input.cwd, "Conversation cwd");
    const namespace = this.ensureNamespace(parentScope);
    const conversationDirectory = containedPath(namespace, conversationId);
    requirePrivateDirectory(conversationDirectory, "Conversation directory");

    const metadataPath = path.join(conversationDirectory, "metadata.json");
    const metadata = readMetadata(metadataPath, parentScope, conversationId);
    if (metadata.cwd !== cwd)
      throw new Error("Conversation cwd does not match metadata");
    if (
      !sameSkillPolicy(
        metadata.skills,
        normalizeSkillPolicy(input.skills) ?? null,
      )
    )
      throw new Error("Conversation skills do not match original selection");
    validateSessionFile(
      path.join(conversationDirectory, "child-session.jsonl"),
    );

    const lease = this.acquireLease(conversationDirectory, metadata);
    const now = validNow(this.now());
    try {
      if (now - metadata.lastUsedAt > MAX_CONVERSATION_AGE_MS)
        throw new Error("Conversation expired after 30 days without use");
      const updatedMetadata: ConversationMetadata = {
        ...metadata,
        lastUsedAt: Math.max(metadata.lastUsedAt, now),
      };
      writePrivateFileAtomically(metadataPath, updatedMetadata);
      return createLeaseView(lease, updatedMetadata);
    } catch (error) {
      lease.release();
      throw error;
    }
  }

  /** Removes at most 128 unlocked entries older than 30 days from one parent namespace. */
  cleanup(parent: ParentConversationSession): number {
    const parentScope = deriveParentConversationScope(parent);
    const root = this.ensureRoot();
    const namespace = containedPath(root, parentScope);
    if (!pathExistsWithoutFollowing(namespace)) return 0;
    requirePrivateDirectory(namespace, "Parent conversation namespace");

    const cutoff = validNow(this.now()) - MAX_CONVERSATION_AGE_MS;
    let removed = 0;
    const allEntries = readdirSync(namespace, { withFileTypes: true }).sort(
      (left, right) => left.name.localeCompare(right.name),
    );
    const start =
      (this.cleanupOffsets.get(parentScope) ?? 0) %
      Math.max(1, allEntries.length);
    const examined = Math.min(CLEANUP_MAX_ENTRIES, allEntries.length);
    const entries = Array.from(
      { length: examined },
      (_, index) => allEntries[(start + index) % allEntries.length]!,
    );
    this.cleanupOffsets.set(
      parentScope,
      allEntries.length ? (start + examined) % allEntries.length : 0,
    );
    for (const entry of entries) {
      const candidate = containedPath(namespace, entry.name);
      if (!entry.isDirectory() || entry.isSymbolicLink()) continue;
      const fallbackAgeTimestamp = lstatSync(candidate).mtimeMs;
      const lockPath = path.join(candidate, "run.lock");
      let cleanupLock = tryAcquireCleanupLock(lockPath);
      if (!cleanupLock && this.recoverDeadLock(lockPath))
        cleanupLock = tryAcquireCleanupLock(lockPath);
      if (!cleanupLock) continue;

      let deleted = false;
      try {
        const metadata = tryReadCleanupMetadata(
          path.join(candidate, "metadata.json"),
          parentScope,
          entry.name,
        );
        const ageTimestamp = metadata?.lastUsedAt ?? fallbackAgeTimestamp;
        if (ageTimestamp <= cutoff) {
          rmSync(candidate, { recursive: true, force: true });
          deleted = true;
          removed += 1;
        }
      } finally {
        if (!deleted) releaseOwnedLock(cleanupLock.path, cleanupLock.owner);
      }
    }
    return removed;
  }

  private ensureRoot(): string {
    mkdirSync(this.root, { recursive: true, mode: 0o700 });
    requirePrivateDirectory(this.root, "Conversation storage root");
    chmodSync(this.root, 0o700);
    return this.root;
  }

  private ensureNamespace(parentScope: string): string {
    const root = this.ensureRoot();
    const namespace = containedPath(root, parentScope);
    try {
      mkdirSync(namespace, { mode: 0o700 });
    } catch (error) {
      if (errorCode(error) !== "EEXIST") throw error;
    }
    requirePrivateDirectory(namespace, "Parent conversation namespace");
    chmodSync(namespace, 0o700);
    return namespace;
  }

  private acquireLease(
    conversationDirectory: string,
    metadata: ConversationMetadata,
  ): ConversationLease {
    const lockPath = path.join(conversationDirectory, "run.lock");
    for (let attempt = 0; attempt < 2; attempt += 1) {
      const nonce = randomUUID();
      try {
        mkdirSync(lockPath, { mode: 0o700 });
        const owner: LockOwner = {
          version: 1,
          nonce,
          ownerPid: process.pid,
          spawnPending: true,
        };
        writeNewPrivateFile(
          path.join(lockPath, "owner.json"),
          JSON.stringify(owner),
        );
        return new FileConversationLease(
          metadata,
          path.join(conversationDirectory, "child-session.jsonl"),
          lockPath,
          owner,
        );
      } catch (error) {
        if (errorCode(error) !== "EEXIST") {
          if (pathExistsWithoutFollowing(lockPath))
            rmSync(lockPath, { recursive: true, force: true });
          throw error;
        }
        if (attempt === 1 || !this.recoverDeadLock(lockPath)) {
          throw new Error(
            "Conversation is already running or its lock cannot be verified",
          );
        }
      }
    }
    throw new Error("Conversation lock acquisition failed");
  }

  private recoverDeadLock(lockPath: string): boolean {
    const owner = tryReadLockOwner(lockPath);
    if (!owner) return false;
    if (this.isProcessAlive(owner.ownerPid) !== false) return false;
    if (owner.spawnPending) return false;
    if (
      owner.childPid !== undefined &&
      this.isProcessAlive(owner.childPid) !== false
    )
      return false;

    const recoveryPath = `${lockPath}.recovery-${randomUUID()}`;
    try {
      renameSync(lockPath, recoveryPath);
    } catch {
      return false;
    }

    const movedOwner = tryReadLockOwner(recoveryPath);
    if (!movedOwner || movedOwner.nonce !== owner.nonce) {
      restoreQuarantinedLock(recoveryPath, lockPath);
      return false;
    }
    rmSync(recoveryPath, { recursive: true, force: true });
    return true;
  }
}

interface LockOwner {
  version: 1;
  nonce: string;
  ownerPid: number;
  childPid?: number;
  spawnPending?: true;
}

class FileConversationLease implements ConversationLease {
  readonly metadata: Readonly<ConversationMetadata>;
  readonly sessionFilePath: string;
  private readonly lockPath: string;
  private owner: LockOwner;
  private released = false;

  constructor(
    metadata: Readonly<ConversationMetadata>,
    sessionFilePath: string,
    lockPath: string,
    owner: LockOwner,
  ) {
    this.metadata = metadata;
    this.sessionFilePath = sessionFilePath;
    this.lockPath = lockPath;
    this.owner = owner;
  }

  recordChildPid(pid: number): void {
    if (this.released)
      throw new Error("Conversation lease is already released");
    if (!Number.isSafeInteger(pid) || pid <= 0)
      throw new Error("Child PID is invalid");

    const current = readLockOwner(this.lockPath);
    if (current.nonce !== this.owner.nonce)
      throw new Error("Conversation lease ownership was lost");
    const { spawnPending: _pending, ...confirmedOwner } = current;
    this.owner = { ...confirmedOwner, childPid: pid };
    writePrivateFileAtomically(
      path.join(this.lockPath, "owner.json"),
      this.owner,
    );
  }

  release(): void {
    if (this.released) return;
    this.released = true;

    releaseOwnedLock(this.lockPath, this.owner);
  }
}

function tryAcquireCleanupLock(
  lockPath: string,
): { path: string; owner: LockOwner } | undefined {
  const owner: LockOwner = {
    version: 1,
    nonce: randomUUID(),
    ownerPid: process.pid,
  };
  try {
    mkdirSync(lockPath, { mode: 0o700 });
  } catch (error) {
    if (errorCode(error) === "EEXIST") return undefined;
    throw error;
  }
  try {
    writeNewPrivateFile(
      path.join(lockPath, "owner.json"),
      JSON.stringify(owner),
    );
    return { path: lockPath, owner };
  } catch (error) {
    rmSync(lockPath, { recursive: true, force: true });
    throw error;
  }
}

function releaseOwnedLock(lockPath: string, owner: LockOwner): void {
  const current = tryReadLockOwner(lockPath);
  if (!current || current.nonce !== owner.nonce) return;
  const releasePath = `${lockPath}.release-${owner.nonce}`;
  try {
    renameSync(lockPath, releasePath);
  } catch {
    return;
  }

  const movedOwner = tryReadLockOwner(releasePath);
  if (movedOwner?.nonce === owner.nonce) {
    rmSync(releasePath, { recursive: true, force: true });
  } else {
    restoreQuarantinedLock(releasePath, lockPath);
  }
}

function restoreQuarantinedLock(
  quarantinedPath: string,
  lockPath: string,
): void {
  if (pathExistsWithoutFollowing(lockPath)) return;
  try {
    renameSync(quarantinedPath, lockPath);
  } catch {
    // An unverifiable lock remains quarantined rather than being deleted.
  }
}

function createLeaseView(
  lease: ConversationLease,
  metadata: ConversationMetadata,
): ConversationLease {
  return {
    metadata,
    sessionFilePath: lease.sessionFilePath,
    recordChildPid: (pid) => lease.recordChildPid(pid),
    release: () => lease.release(),
  };
}

function readMetadata(
  metadataPath: string,
  parentScope: string,
  conversationId: ConversationId,
): ConversationMetadata {
  requireRegularFile(metadataPath, "Conversation metadata");
  let value: unknown;
  try {
    value = JSON.parse(readFileSync(metadataPath, "utf8"));
  } catch {
    throw new Error("Conversation metadata is malformed");
  }
  if (
    isRecord(value) &&
    value.version === 1 &&
    hasExactKeys(value, [
      "version",
      "parentScope",
      "conversationId",
      "cwd",
      "createdAt",
      "lastUsedAt",
    ])
  ) {
    throw new Error("Conversation predates skill policies; start fresh");
  }
  if (
    !isRecord(value) ||
    !hasExactKeys(value, [
      "version",
      "parentScope",
      "conversationId",
      "cwd",
      "createdAt",
      "lastUsedAt",
      "skills",
    ])
  ) {
    throw new Error("Conversation metadata is malformed");
  }
  if (
    value.version !== METADATA_VERSION ||
    value.parentScope !== parentScope ||
    value.conversationId !== conversationId ||
    typeof value.cwd !== "string" ||
    !isCanonicalAbsolutePath(value.cwd) ||
    !isTimestamp(value.createdAt) ||
    !isTimestamp(value.lastUsedAt) ||
    value.lastUsedAt < value.createdAt ||
    (value.skills !== null && !isNormalizedSkillPolicy(value.skills))
  ) {
    throw new Error("Conversation metadata is invalid");
  }
  return value as unknown as ConversationMetadata;
}

function normalizeSkillPolicy(
  skills: readonly string[] | undefined,
): string[] | undefined {
  if (skills === undefined) return undefined;
  const normalized = [...skills].sort();
  if (!isNormalizedSkillPolicy(normalized))
    throw new Error("Conversation skill policy is invalid");
  return normalized;
}

function isNormalizedSkillPolicy(value: unknown): value is string[] {
  return (
    Array.isArray(value) &&
    value.length <= 32 &&
    value.every(
      (skill) =>
        typeof skill === "string" &&
        skill.length <= 64 &&
        /^[a-z0-9]+(?:-[a-z0-9]+)*$/u.test(skill),
    ) &&
    new Set(value).size === value.length &&
    value.every((skill, index) => index === 0 || value[index - 1]! < skill)
  );
}

function sameSkillPolicy(
  left: readonly string[] | null,
  right: readonly string[] | null,
): boolean {
  return (
    left === right ||
    (left !== null &&
      right !== null &&
      left.length === right.length &&
      left.every((skill, index) => skill === right[index]))
  );
}

function tryReadCleanupMetadata(
  metadataPath: string,
  parentScope: string,
  conversationId: string,
): ConversationMetadata | undefined {
  if (!CONVERSATION_ID_PATTERN.test(conversationId)) return undefined;
  try {
    return readMetadata(
      metadataPath,
      parentScope,
      conversationId as ConversationId,
    );
  } catch {
    return undefined;
  }
}

function validateSessionFile(sessionFilePath: string): void {
  requireRegularFile(sessionFilePath, "Child session file");
  if (statSync(sessionFilePath).size > MAX_CONVERSATION_SESSION_BYTES) {
    throw new Error("Child session file exceeds 64 MiB");
  }
}

function canonicalDirectory(candidate: string, description: string): string {
  const canonicalPath = realpathSync(candidate);
  if (!statSync(canonicalPath).isDirectory())
    throw new Error(`${description} must be a directory`);
  if (canonicalPath.length > MAX_CATALOG_CWD_CHARACTERS)
    throw new Error(`${description} exceeds 4096 characters`);
  return canonicalPath;
}

function canonicalRegularFile(candidate: string, description: string): string {
  const canonicalPath = realpathSync(candidate);
  if (!statSync(canonicalPath).isFile())
    throw new Error(`${description} must be a regular file`);
  return canonicalPath;
}

function requirePrivateDirectory(candidate: string, description: string): void {
  const details = lstatSync(candidate);
  if (details.isSymbolicLink() || !details.isDirectory()) {
    throw new Error(`${description} must be a non-symlink directory`);
  }
}

function requireRegularFile(candidate: string, description: string): void {
  const details = lstatSync(candidate);
  if (details.isSymbolicLink() || !details.isFile()) {
    throw new Error(`${description} must be a non-symlink regular file`);
  }
}

function containedPath(parent: string, child: string): string {
  const candidate = path.resolve(parent, child);
  const relative = path.relative(parent, candidate);
  if (
    !relative ||
    relative.startsWith(`..${path.sep}`) ||
    relative === ".." ||
    path.isAbsolute(relative)
  ) {
    throw new Error("Conversation storage path escapes its namespace");
  }
  return candidate;
}

function writeNewPrivateFile(filePath: string, contents: string): void {
  const descriptor = openSync(filePath, "wx", 0o600);
  try {
    writeFileSync(descriptor, contents, "utf8");
  } finally {
    closeSync(descriptor);
  }
  chmodSync(filePath, 0o600);
}

function writePrivateFileAtomically(filePath: string, value: unknown): void {
  const temporaryPath = `${filePath}.tmp-${randomUUID()}`;
  try {
    writeNewPrivateFile(temporaryPath, JSON.stringify(value));
    renameSync(temporaryPath, filePath);
  } finally {
    rmSync(temporaryPath, { force: true });
  }
}

function readLockOwner(lockPath: string): LockOwner {
  requirePrivateDirectory(lockPath, "Conversation lock");
  requireRegularFile(
    path.join(lockPath, "owner.json"),
    "Conversation lock owner",
  );
  const value = JSON.parse(
    readFileSync(path.join(lockPath, "owner.json"), "utf8"),
  ) as unknown;
  if (!isLockOwner(value))
    throw new Error("Conversation lock owner is malformed");
  return value;
}

function tryReadLockOwner(lockPath: string): LockOwner | undefined {
  try {
    return readLockOwner(lockPath);
  } catch {
    return undefined;
  }
}

function isLockOwner(value: unknown): value is LockOwner {
  if (!isRecord(value)) return false;
  const keys = ["version", "nonce", "ownerPid"];
  if (value.childPid !== undefined) keys.push("childPid");
  if (value.spawnPending !== undefined) keys.push("spawnPending");
  return (
    hasExactKeys(value, keys) &&
    value.version === 1 &&
    typeof value.nonce === "string" &&
    CONVERSATION_ID_PATTERN.test(value.nonce) &&
    isPid(value.ownerPid) &&
    (value.childPid === undefined || isPid(value.childPid)) &&
    (value.spawnPending === undefined || value.spawnPending === true) &&
    !(value.childPid !== undefined && value.spawnPending === true)
  );
}

function probeProcessAlive(pid: number): boolean | undefined {
  try {
    process.kill(pid, 0);
    return true;
  } catch (error) {
    if (errorCode(error) === "ESRCH") return false;
    if (errorCode(error) === "EPERM") return true;
    return undefined;
  }
}

function validNow(value: number): number {
  if (!isTimestamp(value))
    throw new Error("Conversation clock returned an invalid timestamp");
  return value;
}

function isTimestamp(value: unknown): value is number {
  return (
    typeof value === "number" &&
    Number.isSafeInteger(value) &&
    value >= 0 &&
    value <= MAX_DATE_TIMESTAMP
  );
}

function isPid(value: unknown): value is number {
  return typeof value === "number" && Number.isSafeInteger(value) && value > 0;
}

function isCanonicalAbsolutePath(value: string): boolean {
  return path.isAbsolute(value) && path.resolve(value) === value;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function hasExactKeys(
  value: Record<string, unknown>,
  expected: readonly string[],
): boolean {
  const keys = Object.keys(value);
  return (
    keys.length === expected.length &&
    keys.every((key) => expected.includes(key))
  );
}

function errorCode(error: unknown): string | undefined {
  return isRecord(error) && typeof error.code === "string"
    ? error.code
    : undefined;
}

function pathExistsWithoutFollowing(candidate: string): boolean {
  try {
    lstatSync(candidate);
    return true;
  } catch (error) {
    if (errorCode(error) === "ENOENT") return false;
    throw error;
  }
}
