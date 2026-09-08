"""Two-table intent/inbox registry; SQLite constraints are the final race fence."""

# sqlite3.Row is dynamic; constraints own its shape. Unused SQL cursors and
# adjacent SQL literals are intentional at this concrete storage boundary.
# pyright: reportAny=false, reportUnusedCallResult=false, reportImplicitStringConcatenation=false

import os
import sqlite3
from dataclasses import asdict
from datetime import datetime, timezone
from pathlib import Path

from .errors import TeamError, require
from .ids import is_id, logical_name, new_id
from .locks import Locks
from .models import MAX_REPLY_BYTES, Phase, Request, Teammate
from .private_fs import check_path, private_directory, private_file

SCHEMA = """
CREATE TABLE teammates (
 teammate_id TEXT PRIMARY KEY,
 endpoint TEXT NOT NULL,
 workspace_id TEXT NOT NULL,
 logical_name TEXT NOT NULL,
 profile TEXT,
 kind TEXT NOT NULL CHECK (kind = 'pi'),
 cwd TEXT NOT NULL,
 phase TEXT NOT NULL CHECK (phase IN ('provisioning','managed','closing','closed')),
 tab_id TEXT,
 pane_id TEXT,
 revision INTEGER NOT NULL CHECK (revision >= 0),
 created_at TEXT NOT NULL,
 updated_at TEXT NOT NULL,
 closed_at TEXT,
 CHECK ((tab_id IS NULL) = (pane_id IS NULL)),
 CHECK (phase != 'managed' OR tab_id IS NOT NULL),
 CHECK ((phase = 'closed') = (closed_at IS NOT NULL))
);
CREATE UNIQUE INDEX active_names ON teammates(endpoint,workspace_id,logical_name) WHERE phase != 'closed';
CREATE TABLE requests (
 request_id TEXT PRIMARY KEY,
 teammate_id TEXT NOT NULL UNIQUE REFERENCES teammates(teammate_id) ON DELETE CASCADE,
 delivery TEXT NOT NULL CHECK (delivery IN ('prepared','submitted','uncertain')),
 reply TEXT CHECK (reply IS NULL OR length(CAST(reply AS BLOB)) <= 262144),
 created_at TEXT NOT NULL,
 replied_at TEXT,
 CHECK ((reply IS NULL) = (replied_at IS NULL))
);
PRAGMA user_version = 1;
"""


def now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="milliseconds")


class Registry:
    def __init__(self, path: Path) -> None:
        self.path: Path = path
        private_directory(path.parent)
        with Locks(path.parent).hold("schema"):
            descriptor = private_file(path)
            os.close(descriptor)
            for suffix in ("-wal", "-shm", "-journal"):
                sibling = Path(str(path) + suffix)
                if sibling.exists() or sibling.is_symlink():
                    check_path(sibling)
            self.connection: sqlite3.Connection = sqlite3.connect(
                path, timeout=5, isolation_level=None
            )
            try:
                self.initialize_schema()
            except BaseException:
                self.connection.close()
                raise

    def initialize_schema(self) -> None:
        self.connection.row_factory = sqlite3.Row
        self.connection.execute("PRAGMA foreign_keys = ON")
        version = self.connection.execute("PRAGMA user_version").fetchone()[0]
        tables = self.connection.execute(
            "SELECT name FROM sqlite_master WHERE type='table'"
        ).fetchall()
        require(
            version == 1 or version == 0 and not tables,
            "registry_schema",
            "Unsupported registry; no migration is performed",
        )
        if version == 0:
            self.connection.executescript("BEGIN IMMEDIATE;" + SCHEMA + "COMMIT;")
        self.connection.execute("PRAGMA journal_mode = WAL")
        self.connection.execute("PRAGMA synchronous = FULL")
        require(
            {
                row[0]
                for row in self.connection.execute(
                    "SELECT name FROM sqlite_master WHERE type='table'"
                )
            }
            == {"teammates", "requests"},
            "registry_schema",
            "Unexpected registry tables",
        )

    def close(self) -> None:
        self.connection.close()

    def get(self, teammate_id: str) -> Teammate:
        row = self.connection.execute(
            "SELECT * FROM teammates WHERE teammate_id=?", (teammate_id,)
        ).fetchone()
        require(row is not None, "not_found", "Teammate not found")
        return Teammate(**dict(row))

    def list(
        self, endpoint: str, workspace: str | None, include_closed: bool
    ) -> list[Teammate]:
        rows = self.connection.execute(
            "SELECT * FROM teammates WHERE endpoint=? AND (? IS NULL OR workspace_id=?) "
            "AND (? OR phase!='closed') ORDER BY workspace_id,logical_name,teammate_id",
            (endpoint, workspace, workspace, include_closed),
        )
        return [Teammate(**dict(row)) for row in rows]

    def resolve(self, reference: str, endpoint: str, workspace: str) -> Teammate:
        if is_id(reference):
            record = self.get(reference)
            require(
                record.endpoint == endpoint,
                "not_found",
                "Teammate belongs to another endpoint",
            )
            return record
        logical_name(reference)
        records = [
            r
            for r in self.list(endpoint, workspace, True)
            if r.logical_name == reference
        ]
        active = [r for r in records if r.phase != "closed"]
        choices = active or records
        require(
            bool(choices),
            "not_found",
            "No teammate with that name in the current workspace",
        )
        require(
            len(choices) == 1,
            "ambiguous",
            "Closed name is ambiguous; use a full teammate ID",
        )
        return choices[0]

    def reserve(
        self,
        endpoint: str,
        workspace: str,
        name: str,
        profile: str | None,
        kind: str,
        cwd: str,
    ) -> Teammate:
        timestamp = now()
        record = Teammate(
            teammate_id=new_id("tm_"),
            endpoint=endpoint,
            workspace_id=workspace,
            logical_name=logical_name(name),
            profile=profile,
            kind=kind,
            cwd=cwd,
            created_at=timestamp,
            updated_at=timestamp,
        )
        values = asdict(record)
        try:
            self.connection.execute(
                f"INSERT INTO teammates ({','.join(values)}) VALUES ({','.join('?' for _ in values)})",
                tuple(values.values()),
            )
        except sqlite3.IntegrityError as error:
            raise TeamError(
                "name_taken", "An active teammate already has that workspace name"
            ) from error
        return record

    def transition(
        self,
        record: Teammate,
        *,
        phase: Phase,
        workspace: str | None = None,
        tab: str | None = None,
        pane: str | None = None,
    ) -> Teammate:
        require(
            record.phase != "closed", "closed", "Closed teammate intent cannot change"
        )
        require(
            (record.phase, phase)
            in {
                ("provisioning", "provisioning"),
                ("provisioning", "managed"),
                ("provisioning", "closing"),
                ("provisioning", "closed"),
                ("managed", "managed"),
                ("managed", "closing"),
                ("managed", "closed"),
                ("closing", "closing"),
                ("closing", "closed"),
            },
            "registry_state",
            "Invalid lifecycle transition",
        )
        timestamp = now()
        try:
            cursor = self.connection.execute(
                "UPDATE teammates SET phase=?,workspace_id=?,tab_id=?,pane_id=?,revision=revision+1,"
                "updated_at=?,closed_at=? WHERE teammate_id=? AND revision=?",
                (
                    phase,
                    workspace or record.workspace_id,
                    tab or record.tab_id,
                    pane or record.pane_id,
                    timestamp,
                    timestamp if phase == "closed" else None,
                    record.teammate_id,
                    record.revision,
                ),
            )
        except sqlite3.IntegrityError as error:
            raise TeamError(
                "conflict", "Lifecycle transition conflicts with existing intent"
            ) from error
        require(
            cursor.rowcount == 1,
            "conflict",
            "Teammate changed; refresh before proceeding",
        )
        return self.get(record.teammate_id)

    def forget(self, record: Teammate, force: bool = False) -> None:
        cursor = self.connection.execute(
            "DELETE FROM teammates WHERE teammate_id=? AND revision=? AND "
            "(? OR (phase='closed' AND NOT EXISTS (SELECT 1 FROM requests WHERE teammate_id=?)))",
            (record.teammate_id, record.revision, force, record.teammate_id),
        )
        require(
            cursor.rowcount == 1,
            "conflict",
            "Forget requires unchanged closed intent and an empty inbox",
        )

    def slot(self, teammate_id: str) -> Request | None:
        row = self.connection.execute(
            "SELECT * FROM requests WHERE teammate_id=?", (teammate_id,)
        ).fetchone()
        return Request(**dict(row)) if row is not None else None

    def request(self, request_id: str) -> Request:
        require(is_id(request_id, "rq_"), "invalid_id", "Invalid request ID")
        row = self.connection.execute(
            "SELECT * FROM requests WHERE request_id=?", (request_id,)
        ).fetchone()
        require(
            row is not None,
            "not_found",
            "Request is absent, cancelled, or acknowledged",
        )
        return Request(**dict(row))

    def prepare(self, record: Teammate) -> Request:
        request_id = new_id("rq_")
        try:
            cursor = self.connection.execute(
                "INSERT INTO requests SELECT ?,teammate_id,'prepared',NULL,?,NULL FROM teammates "
                "WHERE teammate_id=? AND revision=? AND phase='managed'",
                (request_id, now(), record.teammate_id, record.revision),
            )
        except sqlite3.IntegrityError as error:
            raise TeamError(
                "inbox_full",
                "A pending or unacknowledged request already occupies this teammate's slot",
            ) from error
        require(
            cursor.rowcount == 1,
            "conflict",
            "Teammate changed before request reservation",
        )
        return self.request(request_id)

    def delivered(self, request_id: str, uncertain: bool) -> None:
        self.connection.execute(
            "UPDATE requests SET delivery=? WHERE request_id=? AND delivery='prepared'",
            ("uncertain" if uncertain else "submitted", request_id),
        )

    def reply(self, request_id: str, teammate_id: str, body: str) -> None:
        require(
            len(body.encode("utf-8")) <= MAX_REPLY_BYTES,
            "reply_size",
            "Reply exceeds 256 KiB",
        )
        cursor = self.connection.execute(
            "UPDATE requests SET reply=?,replied_at=? WHERE request_id=? AND teammate_id=? AND reply IS NULL",
            (body, now(), request_id, teammate_id),
        )
        require(
            cursor.rowcount == 1,
            "conflict",
            "Request is no longer pending; reply was not stored",
        )

    def cancel(self, request_id: str) -> None:
        cursor = self.connection.execute(
            "DELETE FROM requests WHERE request_id=? AND reply IS NULL", (request_id,)
        )
        require(
            cursor.rowcount == 1,
            "conflict",
            "Only a matching pending request can be cancelled",
        )

    def acknowledge(self, request: Request) -> bool:
        require(
            request.reply is not None, "pending", "Cannot acknowledge a pending request"
        )
        cursor = self.connection.execute(
            "DELETE FROM requests WHERE request_id=? AND replied_at=? AND reply IS NOT NULL",
            (request.request_id, request.replied_at),
        )
        return cursor.rowcount == 1
