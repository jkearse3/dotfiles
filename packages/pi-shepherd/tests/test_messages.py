import contextlib
import io
import json
import os
import unittest
from dataclasses import replace
from types import SimpleNamespace
from typing import cast
from unittest.mock import Mock, patch

from pi_shepherd import cli, messages
from pi_shepherd.errors import TeamError
from pi_shepherd.models import MAX_REPLY_BYTES, Teammate
from support import TeamCase


class MessageTests(TeamCase):
    def as_teammate(self, record: Teammate) -> None:
        assert record.pane_id is not None
        self.runtime.caller_id = record.pane_id
        self.runtime.environment["PI_SHEPHERD_TEAMMATE_ID"] = record.teammate_id

    def test_end_to_end_cooperative_exchange_and_ack(self) -> None:
        record = self.create()
        submitted = messages.request(
            self.team, "worker", "Do the task", False, 0, False
        )
        self.assertEqual(submitted["request_status"], "pending")
        self.assertEqual(submitted["delivery"], "submitted")
        self.assertNotIn("wait_outcome", submitted)
        self.assertNotIn("runtime_status", submitted)
        self.assertNotIn("runtime_health", submitted)
        request_id = submitted["request_id"]
        assert isinstance(request_id, str)
        with self.assertRaises(TeamError):
            _ = messages.request(self.team, "worker", "another task", False, 0, True)
        self.as_teammate(record)
        _ = messages.reply(self.team, request_id, "response\n")
        result = messages.result(self.registry, request_id, True, 0)
        view = messages.result_view(result)
        self.assertEqual(view["request_status"], "completed")
        self.assertEqual(view["attribution"], "cooperative_unverified")
        self.assertEqual(result.reply, "response\n")
        self.assertTrue(self.registry.acknowledge(result))
        self.assertFalse(self.registry.acknowledge(result))
        with self.assertRaises(TeamError):
            _ = messages.reply(self.team, request_id, "late")

    def test_reply_during_request_submission_survives_delivery_update(self) -> None:
        record = self.create()

        def reply_early(text: str) -> None:
            request = self.pending_request(record.teammate_id)
            self.assertIn(f"pi-shepherd reply {request.request_id} --stdin", text)
            self.registry.reply(request.request_id, record.teammate_id, "early")

        self.runtime.after_prompt = reply_early
        result = messages.request(self.team, "worker", "text", True, 0, False)
        self.assertEqual(result["content"], "early")
        self.assertEqual(result["request_status"], "completed")
        self.assertEqual(result["wait_outcome"], "completed")
        self.assertEqual(self.pending_request(record.teammate_id).delivery, "submitted")

    def test_uncertain_and_definite_delivery_are_distinct(self) -> None:
        record = self.create()
        self.runtime.failure = "prompt"
        result = messages.request(self.team, "worker", "private prompt", True, 0, False)
        self.assertEqual(result["request_status"], "pending")
        self.assertEqual(result["wait_outcome"], "delivery_uncertain")
        self.assertIsNone(result["runtime_status"])
        self.assertIsNone(result["runtime_health"])
        pending = self.pending_request(record.teammate_id)
        self.assertEqual(pending.delivery, "uncertain")
        self.assertEqual(result["request_id"], pending.request_id)
        with self.assertRaises(TeamError):
            _ = messages.request(self.team, "worker", "retry", False, 0, True)
        self.assertEqual(self.runtime.calls.count("prompt"), 1)
        self.registry.cancel(pending.request_id)
        self.runtime.failure = "prompt_rejected"
        with self.assertRaises(TeamError):
            _ = messages.request(self.team, "worker", "text", False, 0, False)
        self.assertIsNone(self.registry.slot(record.teammate_id))

    def test_crash_after_prepare_preserves_nonreplayable_slot(self) -> None:
        record = self.create()
        with (
            patch.object(self.runtime, "prompt", side_effect=KeyboardInterrupt),
            self.assertRaises(KeyboardInterrupt),
        ):
            _ = messages.request(self.team, "worker", "text", False, 0, False)
        self.assertEqual(self.pending_request(record.teammate_id).delivery, "prepared")
        with self.assertRaises(TeamError):
            _ = messages.request(self.team, "worker", "text", False, 0, False)

    def test_reply_requires_exact_current_identity_and_pending_id(self) -> None:
        record = self.create()
        request = self.registry.prepare(record)
        with self.assertRaises(TeamError):
            _ = messages.reply(self.team, request.request_id, "spoof")
        self.runtime.environment["PI_SHEPHERD_TEAMMATE_ID"] = record.teammate_id
        with self.assertRaises(TeamError):
            _ = messages.reply(self.team, request.request_id, "wrong pane")
        self.as_teammate(record)
        self.registry.cancel(request.request_id)
        later = self.registry.prepare(record)
        with self.assertRaises(TeamError):
            _ = messages.reply(self.team, request.request_id, "stale")
        self.assertIsNone(self.registry.request(later.request_id).reply)

    def test_timeout_blocked_and_missing_reply_preserve_slot(self) -> None:
        record = self.create()
        result = messages.request(self.team, "worker", "text", True, 0, False)
        self.assertEqual(result["request_status"], "pending")
        self.assertEqual(result["wait_outcome"], "timeout")
        self.assertEqual(result["runtime_status"], "idle")
        self.assertEqual(result["runtime_health"], "healthy")
        request_id = result["request_id"]
        assert isinstance(request_id, str)
        self.runtime.set_status("blocked")
        blocked = messages.wait_request(self.team, request_id, 0)
        self.assertEqual(blocked["request_status"], "pending")
        self.assertEqual(blocked["wait_outcome"], "runtime_blocked")
        self.assertEqual(blocked["runtime_status"], "blocked")
        self.assertEqual(blocked["runtime_health"], "healthy")
        self.runtime.set_status("done")
        # Replace only messages' module binding; Locks must keep the real clock.
        monotonic = Mock(side_effect=[0, 6])
        sleep = Mock()
        clock = SimpleNamespace(monotonic=monotonic, sleep=sleep)
        with patch("pi_shepherd.messages.time", new=clock):
            missing = messages.wait_request(self.team, request_id, 100)
            self.assertEqual(missing["request_status"], "pending")
            self.assertEqual(missing["wait_outcome"], "reply_missing")
            self.assertEqual(missing["runtime_status"], "done")
            self.assertEqual(missing["runtime_health"], "healthy")
            self.assertEqual(monotonic.call_count, 2)
            sleep.assert_not_called()
        self.assertIsNotNone(self.registry.slot(record.teammate_id))
        self.assertNotIn("read", self.runtime.calls)

    def test_unhealthy_runtime_is_diagnostic_for_pending_request(self) -> None:
        record = self.create()
        submitted = messages.request(self.team, "worker", "text", False, 0, False)
        request_id = submitted["request_id"]
        assert isinstance(request_id, str)
        self.runtime.missing_agent()

        result = messages.wait_request(self.team, request_id, 0)

        self.assertEqual(result["request_status"], "pending")
        self.assertEqual(result["wait_outcome"], "runtime_unhealthy")
        self.assertEqual(result["runtime_status"], "unknown")
        self.assertEqual(result["runtime_health"], "agent_missing")
        self.assertIsNotNone(self.registry.slot(record.teammate_id))
        self.assertNotIn("read", self.runtime.calls)

    def test_focused_and_unsettled_preflight_has_no_effect(self) -> None:
        record = self.create()
        self.runtime.agents = [replace(p, focused=True) for p in self.runtime.agents]
        with self.assertRaises(TeamError):
            _ = messages.request(self.team, "worker", "text", False, 0, False)
        self.runtime.set_status("working")
        with self.assertRaises(TeamError):
            _ = messages.request(self.team, "worker", "text", False, 0, True)
        self.assertIsNone(self.registry.slot(record.teammate_id))
        self.assertNotIn("prompt", self.runtime.calls)

    def test_bounded_utf8_input(self) -> None:
        self.assertEqual(messages.read_body(io.BytesIO(b"")), "")
        self.assertEqual(
            len(messages.read_body(io.BytesIO(b"x" * MAX_REPLY_BYTES))), MAX_REPLY_BYTES
        )
        for data in (b"x" * (MAX_REPLY_BYTES + 1), b"\xff"):
            with self.assertRaises(TeamError) as caught:
                _ = messages.read_body(io.BytesIO(data))
            self.assertNotIn(repr(data), str(caught.exception))

    def test_result_wait_reports_durable_status_without_runtime_diagnostics(
        self,
    ) -> None:
        record = self.create()
        request = self.registry.prepare(record)
        self.registry.delivered(request.request_id, False)
        environment = {
            "XDG_STATE_HOME": str(self.root),
            "XDG_CONFIG_HOME": str(self.root / "config"),
        }
        output = io.StringIO()
        with (
            patch.dict(os.environ, environment),
            patch("pi_shepherd.cli.registry_path", return_value=self.registry.path),
            contextlib.redirect_stdout(output),
        ):
            self.assertEqual(
                cli.main(
                    [
                        "--json",
                        "result",
                        request.request_id,
                        "--wait",
                        "--timeout",
                        "0",
                    ]
                ),
                0,
            )

        payload = cast(dict[str, object], json.loads(output.getvalue()))
        self.assertEqual(payload["command"], "result")
        result = cast(dict[str, object], payload["result"])
        self.assertEqual(result["request_status"], "pending")
        self.assertEqual(result["delivery"], "submitted")
        self.assertEqual(result["wait_outcome"], "timeout")
        self.assertNotIn("runtime_status", result)
        self.assertNotIn("runtime_health", result)
        self.assertIsNotNone(self.registry.slot(record.teammate_id))

    def test_request_stdin_reaches_message_dispatch(self) -> None:
        request = Mock(return_value={"request_status": "pending"})
        args = cli.parse_args(["request", "worker", "--stdin", "--wait"])
        with (
            patch("pi_shepherd.cli.sys.stdin", io.StringIO("Inspect café\n")),
            patch("pi_shepherd.cli.messages.request", request),
        ):
            result = cli.dispatch(self.team, args)

        self.assertEqual(result, {"request_status": "pending"})
        request.assert_called_once_with(
            self.team,
            "worker",
            "Inspect café\n",
            True,
            self.team.config.wait_timeout_seconds,
            False,
        )

    def test_completed_request_human_output_is_only_the_body(self) -> None:
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            cli.emit("request", {"content": "response\n"}, False)
        self.assertEqual(output.getvalue(), "response\n")

    def test_failed_output_does_not_acknowledge(self) -> None:
        record = self.create()
        request = self.registry.prepare(record)
        self.registry.reply(request.request_id, record.teammate_id, "private-body")
        environment = {
            "XDG_STATE_HOME": str(self.root),
            "XDG_CONFIG_HOME": str(self.root / "config"),
        }
        # Inject the actual temporary registry path without altering normal path discovery.
        with (
            patch.dict(os.environ, environment),
            patch("pi_shepherd.cli.registry_path", return_value=self.registry.path),
            patch("pi_shepherd.cli.emit", side_effect=BrokenPipeError),
            contextlib.redirect_stderr(io.StringIO()),
        ):
            self.assertEqual(cli.main(["result", request.request_id, "--ack"]), 1)
        self.assertEqual(
            self.registry.request(request.request_id).reply, "private-body"
        )
        output = io.StringIO()
        with (
            patch.dict(os.environ, environment),
            patch("pi_shepherd.cli.registry_path", return_value=self.registry.path),
            contextlib.redirect_stdout(output),
        ):
            self.assertEqual(cli.main(["result", request.request_id, "--ack"]), 0)
        self.assertEqual(output.getvalue(), "private-body")
        with self.assertRaises(TeamError):
            _ = self.registry.request(request.request_id)


if __name__ == "__main__":
    _ = unittest.main()
