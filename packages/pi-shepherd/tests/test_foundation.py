"""Public grammar and Pi launch contracts, without contacting Herdr."""

import contextlib
import io
import unittest
from dataclasses import fields

from pi_shepherd.cli import parse_args
from pi_shepherd.config import Config, parse_config, select_launch
from pi_shepherd.errors import TeamError
from pi_shepherd.ids import alias, is_id, logical_name, marker, new_id
from pi_shepherd.models import Request, Teammate


class FoundationTests(unittest.TestCase):
    def config(self, **changes: object) -> Config:
        return parse_config(
            {
                "profiles": {
                    "readonly": {
                        "args": ["--tools", "read,grep,find,ls"],
                        "env": {"MODE": "readonly"},
                    }
                },
                **changes,
            }
        )

    def test_removed_surface_and_reply_argv_rejected(self) -> None:
        invalid = [
            [name]
            for name in ("capabilities", "rename", "reconcile", "release", "adopt")
        ]
        invalid += [
            ["prompt", "worker", "--prompt", "text"],
            ["request", "worker", "--prompt", "text", "--wait", "--result"],
            ["request", "worker", "--stdin", "--prompt", "text"],
            ["request", "worker", "--stdin", "--prompt-file", "task.txt"],
            ["reply", "rq_test", "body"],
            ["reply", "rq_test"],
            ["create", "worker", "--twin"],
            ["--json", "attach", "worker"],
            ["--json", "--skill"],
        ]
        for argv in invalid:
            with (
                self.subTest(argv=argv),
                contextlib.redirect_stderr(io.StringIO()),
                self.assertRaises(SystemExit),
            ):
                _ = parse_args(argv)

    def test_valid_surface(self) -> None:
        for argv in (
            ["--skill"],
            ["profiles"],
            ["create", "worker"],
            ["create", "worker", "--profile", "readonly"],
            ["list", "--all", "--include-closed"],
            ["show", "worker"],
            ["request", "worker", "--stdin", "--wait"],
            ["request", "worker", "--prompt-file", "-", "--wait"],
            ["reply", "rq_id", "--stdin"],
            ["result", "rq_id", "--ack"],
            ["cancel", "rq_id"],
            ["wait", "worker", "--until", "blocked"],
            ["read", "worker"],
            ["focus", "worker"],
            ["attach", "worker"],
            ["repair", "worker", "--apply"],
            ["close", "worker", "--force"],
            ["forget", "worker"],
        ):
            with self.subTest(argv=argv):
                _ = parse_args(argv)

    def test_numeric_bounds(self) -> None:
        for argv in (
            ["create", "w", "--startup-timeout", "3"],
            ["wait", "w", "--timeout", "-1"],
            ["read", "w", "--lines", "10001"],
        ):
            with (
                contextlib.redirect_stderr(io.StringIO()),
                self.assertRaises(SystemExit),
            ):
                _ = parse_args(argv)

    def test_default_launch_twins_calling_pi(self) -> None:
        config = self.config()
        environment = {
            "PI_PROVIDER": "provider",
            "PI_MODEL": "model",
            "PI_REASONING_LEVEL": "high",
        }
        launch = select_launch(config, None, "pi", environment)
        self.assertIsNone(launch.profile)
        self.assertEqual(launch.env, ())
        self.assertEqual(
            launch.args,
            ("--provider", "provider", "--model", "model", "--thinking", "high"),
        )

        for kind in (None, "other"):
            with self.subTest(kind=kind), self.assertRaises(TeamError) as caught:
                _ = select_launch(config, None, kind, environment)
            self.assertEqual(caught.exception.code, "caller_context")
            self.assertEqual(
                caught.exception.message,
                "Default creation requires a calling Pi agent",
            )

    def test_invalid_pi_twin_values_identify_the_caller_context(self) -> None:
        config = self.config()
        environment = {
            "PI_PROVIDER": "provider",
            "PI_MODEL": "model",
            "PI_REASONING_LEVEL": "high",
        }
        invalid_cases = (
            (
                {key: value for key, value in environment.items() if key != missing},
                f"Calling Pi configuration is missing {missing}",
            )
            for missing in environment
        )
        for caller_environment, message in (
            *invalid_cases,
            (
                {**environment, "PI_MODEL": ""},
                "Calling Pi configuration is missing PI_MODEL",
            ),
            (
                {**environment, "PI_MODEL": "-bad"},
                "Calling Pi configuration has invalid PI_MODEL",
            ),
            (
                {**environment, "PI_PROVIDER": " bad"},
                "Calling Pi configuration has invalid PI_PROVIDER",
            ),
            (
                {**environment, "PI_REASONING_LEVEL": "invalid"},
                "Invalid Pi reasoning level",
            ),
        ):
            with self.subTest(message=message), self.assertRaises(TeamError) as caught:
                _ = select_launch(config, None, "pi", caller_environment)
            self.assertEqual(caught.exception.code, "caller_context")
            self.assertEqual(caught.exception.message, message)

    def test_explicit_profile_is_exact_and_ignores_caller(self) -> None:
        config = self.config()
        launch = select_launch(
            config,
            "readonly",
            "other",
            {
                "PI_PROVIDER": "ignored",
                "PI_MODEL": "ignored",
                "PI_REASONING_LEVEL": "invalid",
            },
        )
        assert launch.profile is not None
        self.assertEqual(launch.profile.name, "readonly")
        self.assertEqual(launch.args, ("--tools", "read,grep,find,ls"))
        self.assertEqual(launch.env, (("MODE", "readonly"),))

        with self.assertRaises(TeamError):
            _ = select_launch(config, "missing", "pi", {})

    def test_closed_pi_profile_config_and_reserved_keys(self) -> None:
        invalid_configs: tuple[dict[str, object], ...] = (
            {"unknown": True},
            {"read_lines": True},
            {"wait_timeout_seconds": 86401},
            {"default_profile": "pi"},
            {"coordinator_profiles": {"pi": "pi"}},
            {"read_source": []},
        )
        for raw in invalid_configs:
            with self.subTest(raw=raw), self.assertRaises(TeamError):
                _ = parse_config(raw)

        for patch in (
            {"backend": "herdr-interactive/v1"},
            {"kind": "pi"},
            {"args": [None]},
            {"env": {"PI_SHEPHERD_TEAMMATE_ID": "spoof"}},
            {"env": {"HERDR_SOCKET_PATH": "/other"}},
            {"selection_hint": " bad"},
            {"extra": True},
        ):
            with self.subTest(patch=patch), self.assertRaises(TeamError):
                _ = parse_config({"profiles": {"pi": {"args": [], **patch}}})

    def test_static_profile_may_set_any_pi_arguments(self) -> None:
        for argument in ("--", "--model", "--provider=x", "--thinking=high"):
            config = parse_config({"profiles": {"pi": {"args": [argument]}}})
            self.assertEqual(select_launch(config, "pi", None, {}).args, (argument,))

    def test_identifiers_and_minimal_records(self) -> None:
        first, second = new_id("tm_"), new_id("tm_")
        self.assertTrue(is_id(first))
        self.assertNotEqual(alias(first), alias(second))
        self.assertTrue(alias(first).startswith("ps_"))
        self.assertNotEqual(marker(first), marker(second))
        self.assertTrue(marker(first).startswith("pi-shepherd:"))
        self.assertLessEqual(len(alias(first)), 32)
        for name in ("tm_name", "Upper", "a b", "a" * 65):
            with self.assertRaises(TeamError):
                _ = logical_name(name)
        self.assertEqual(
            {field.name for field in fields(Request)},
            {
                "request_id",
                "teammate_id",
                "delivery",
                "reply",
                "created_at",
                "replied_at",
            },
        )
        self.assertFalse(
            {field.name for field in fields(Teammate)}
            & {"owner", "runtime_status", "native_session"}
        )


if __name__ == "__main__":
    _ = unittest.main()
