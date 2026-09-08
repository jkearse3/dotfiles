import os
import sqlite3
import unittest

from pi_shepherd.errors import TeamError
from pi_shepherd.registry import Registry
from support import TeamCase


class RegistryTests(TeamCase):
    def test_fresh_schema_has_two_tables_and_nullable_twin_profile(self) -> None:
        second = Registry(self.registry.path)
        second.close()
        self.assertEqual(
            {
                r[0]
                for r in self.registry.connection.execute(  # pyright: ignore[reportAny]
                    "SELECT name FROM sqlite_master WHERE type='table'"
                )
            },
            {"teammates", "requests"},
        )
        self.assertEqual(
            self.registry.connection.execute("PRAGMA user_version").fetchone()[0], 1
        )
        twin = self.create()
        self.assertIsNone(twin.profile)

    def test_workspace_names_full_ids_and_closed_ambiguity(self) -> None:
        first = self.create()
        second = self.registry.reserve(
            first.endpoint, "w2", "worker", "pi", "pi", str(self.root)
        )
        self.assertEqual(
            self.registry.resolve("worker", first.endpoint, "w1").teammate_id,
            first.teammate_id,
        )
        self.assertEqual(
            self.registry.resolve("worker", first.endpoint, "w2").teammate_id,
            second.teammate_id,
        )
        self.assertEqual(
            self.registry.resolve(first.teammate_id, first.endpoint, "w2"), first
        )
        with self.assertRaises(TeamError):
            _ = self.registry.resolve("worker", first.endpoint, "w3")
        with self.assertRaises(TeamError):
            _ = self.registry.reserve(
                first.endpoint, "w1", "worker", "pi", "pi", str(self.root)
            )
        _ = self.registry.transition(first, phase="closed")
        replacement = self.registry.reserve(
            first.endpoint, "w1", "worker", "pi", "pi", str(self.root)
        )
        self.assertEqual(
            self.registry.resolve("worker", first.endpoint, "w1"), replacement
        )
        _ = self.registry.transition(replacement, phase="closed")
        with self.assertRaises(TeamError):
            _ = self.registry.resolve("worker", first.endpoint, "w1")

    def test_compare_and_swap_and_relocation_name_conflict(self) -> None:
        record = self.create()
        newer = self.registry.transition(record, phase="managed")
        with self.assertRaises(TeamError):
            _ = self.registry.transition(record, phase="closing")
        _ = self.registry.reserve(
            record.endpoint, "w2", "worker", "pi", "pi", str(self.root)
        )
        with self.assertRaises(TeamError):
            _ = self.registry.transition(newer, phase="managed", workspace="w2")
        self.assertEqual(self.registry.get(record.teammate_id).workspace_id, "w1")

    def test_result_survives_restart_and_slot_blocks(self) -> None:
        record = self.create()
        request = self.registry.prepare(record)
        self.registry.reply(request.request_id, record.teammate_id, "result")
        self.registry.delivered(request.request_id, True)
        second = Registry(self.registry.path)
        try:
            completed = second.request(request.request_id)
            self.assertEqual(completed.reply, "result")
            with self.assertRaises(TeamError) as full:
                _ = second.prepare(record)
            self.assertEqual(full.exception.code, "inbox_full")
            with self.assertRaises(TeamError):
                second.cancel(request.request_id)
            self.assertTrue(second.acknowledge(completed))
            self.assertFalse(second.acknowledge(completed))
        finally:
            second.close()
        later = self.registry.prepare(record)
        self.assertFalse(self.registry.acknowledge(completed))
        with self.assertRaises(TeamError):
            self.registry.reply(request.request_id, record.teammate_id, "stale")
        self.assertIsNone(self.registry.request(later.request_id).reply)

    def test_unsafe_files_and_sidecars(self) -> None:
        for kind in ("symlink", "hardlink", "mode", "directory"):
            path = self.root / "state" / (kind + ".sqlite3")
            if kind == "symlink":
                path.symlink_to(self.registry.path)
            elif kind == "hardlink":
                os.link(self.registry.path, path)
            elif kind == "mode":
                _ = path.write_bytes(b"")
                path.chmod(0o644)
            else:
                path.mkdir(mode=0o700)
            with self.subTest(kind=kind), self.assertRaises((TeamError, OSError)):
                _ = Registry(path)
            if kind == "hardlink":
                path.unlink()
        sidecar = self.root / "state/unused.sqlite3-wal"
        sidecar.symlink_to(self.registry.path)
        with self.assertRaises(TeamError):
            _ = Registry(self.root / "state/unused.sqlite3")

    def test_unsafe_parent_and_unsupported_schema(self) -> None:
        directory = self.root / "linked"
        directory.symlink_to(self.root / "state")
        with self.assertRaises(TeamError):
            _ = Registry(directory / "bad.sqlite3")
        path = self.root / "state/old.sqlite3"
        connection = sqlite3.connect(path)
        _ = connection.execute("CREATE TABLE unrelated (id INTEGER)")
        connection.close()
        path.chmod(0o600)
        rejected = Registry.__new__(Registry)
        with self.assertRaises(TeamError):
            rejected.__init__(path)
        with self.assertRaises(sqlite3.ProgrammingError):
            _ = rejected.connection.execute("SELECT 1")

    def test_reply_size_and_forget_conditions(self) -> None:
        record = self.create()
        request = self.registry.prepare(record)
        with self.assertRaises(TeamError):
            self.registry.reply(request.request_id, record.teammate_id, "é" * 131073)
        self.registry.reply(request.request_id, record.teammate_id, "é" * 131072)
        closed = self.registry.transition(record, phase="closed")
        with self.assertRaises(TeamError):
            self.registry.forget(closed)
        self.assertTrue(
            self.registry.acknowledge(self.registry.request(request.request_id))
        )
        self.registry.forget(closed)
        with self.assertRaises(TeamError):
            _ = self.registry.get(record.teammate_id)


if __name__ == "__main__":
    _ = unittest.main()
