"""Real SQLite connections and advisory locks in disposable subprocesses."""

import concurrent.futures
import multiprocessing
import unittest
from pathlib import Path
from typing import Literal

from pi_shepherd.errors import TeamError
from pi_shepherd.locks import Locks
from pi_shepherd.registry import Registry
from support import TeamCase


def reserve_slot(path: str, teammate_id: str) -> str:
    registry = Registry(Path(path))
    try:
        request = registry.prepare(registry.get(teammate_id))
        return request.request_id
    except TeamError as error:
        return error.code
    finally:
        registry.close()


def race_reply_cancel(
    path: str, request_id: str, teammate_id: str, action: Literal["reply", "cancel"]
) -> Literal["won", "lost"]:
    registry = Registry(Path(path))
    try:
        if action == "reply":
            registry.reply(request_id, teammate_id, "body")
        else:
            registry.cancel(request_id)
        return "won"
    except TeamError as error:
        if error.code != "conflict":
            raise
        return "lost"
    finally:
        registry.close()


def try_lock(root: str) -> str:
    try:
        with Locks(Path(root), 0.05).hold("held"):
            return "acquired"
    except TeamError as error:
        return error.code


class ConcurrencyTests(TeamCase):
    def test_two_requests_one_slot(self) -> None:
        record = self.create()
        with concurrent.futures.ProcessPoolExecutor(
            2, mp_context=multiprocessing.get_context("spawn")
        ) as pool:
            results = list(
                pool.map(
                    reserve_slot,
                    [str(self.registry.path)] * 2,
                    [record.teammate_id] * 2,
                )
            )
        self.assertEqual(sum(value.startswith("rq_") for value in results), 1)
        self.assertEqual(results.count("inbox_full"), 1)

    def test_reply_cancel_has_one_winner(self) -> None:
        record = self.create()
        request = self.registry.prepare(record)
        with concurrent.futures.ProcessPoolExecutor(
            2, mp_context=multiprocessing.get_context("spawn")
        ) as pool:
            results = list(
                pool.map(
                    race_reply_cancel,
                    [str(self.registry.path)] * 2,
                    [request.request_id] * 2,
                    [record.teammate_id] * 2,
                    ["reply", "cancel"],
                )
            )
        self.assertEqual(sorted(results), ["lost", "won"])

    def test_lock_timeout_is_bounded(self) -> None:
        with (
            self.locks.hold("held"),
            concurrent.futures.ProcessPoolExecutor(
                1, mp_context=multiprocessing.get_context("spawn")
            ) as pool,
        ):
            self.assertEqual(
                pool.submit(try_lock, str(self.locks.root)).result(10), "busy"
            )


if __name__ == "__main__":
    _ = unittest.main()
