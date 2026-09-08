"""Pi-only static profiles and bounded caller twinning."""

import os
import re
from collections.abc import Mapping
from dataclasses import dataclass, field
from pathlib import Path
from typing import cast

import tomllib

from .errors import TeamError, require
from .ids import NAME
from .models import READ_SOURCES

PI_KIND = "pi"
PI_TWIN_ENVIRONMENT = ("PI_PROVIDER", "PI_MODEL", "PI_REASONING_LEVEL")
PI_TWIN_OPTIONS = ("--provider", "--model", "--thinking")
PI_THINKING_LEVELS = {"off", "minimal", "low", "medium", "high", "xhigh", "max"}


@dataclass(frozen=True)
class Profile:
    name: str
    args: tuple[str, ...] = field(repr=False)
    env: tuple[tuple[str, str], ...] = field(repr=False)
    selection_hint: str | None = None


@dataclass(frozen=True)
class Launch:
    profile: Profile | None
    args: tuple[str, ...] = field(repr=False)
    env: tuple[tuple[str, str], ...] = field(repr=False)


@dataclass(frozen=True)
class Config:
    profiles: Mapping[str, Profile]
    startup_timeout_seconds: int = 30
    wait_timeout_seconds: int = 600
    read_source: str = "recent-unwrapped"
    read_lines: int = 120


def xdg_root(key: str, fallback: Path) -> Path:
    value = os.environ.get(key, "")
    return Path(value) if os.path.isabs(value) else fallback


def table(value: object) -> dict[str, object]:
    require(
        isinstance(value, dict)
        and all(isinstance(k, str) for k in cast(dict[object, object], value)),
        "configuration",
        "Expected a configuration table",
    )
    return cast(dict[str, object], value)


def closed_keys(raw: Mapping[str, object], allowed: set[str]) -> None:
    require(not (set(raw) - allowed), "configuration", "Unknown configuration key")


def text(value: object, *, bounded: bool = False) -> str:
    require(isinstance(value, str), "configuration", "Expected text")
    value = cast(str, value)
    require(
        bool(value) and "\0" not in value, "configuration", "Invalid configuration text"
    )
    if bounded:
        require(
            len(value) <= 500
            and value == value.strip()
            and not re.search(r"[\x00-\x1f\x7f]", value),
            "configuration",
            "Expected trimmed single-line text up to 500 characters",
        )
    return value


def pi_caller_value(environment: Mapping[str, str], key: str) -> str:
    value = environment.get(key)
    require(
        isinstance(value, str) and bool(value),
        "caller_context",
        f"Calling Pi configuration is missing {key}",
    )
    value = cast(str, value)
    require(
        len(value) <= 500
        and value == value.strip()
        and not re.search(r"[\x00-\x1f\x7f]", value)
        and not value.startswith("-"),
        "caller_context",
        f"Calling Pi configuration has invalid {key}",
    )
    return value


def bounded_integer(value: object, minimum: int, maximum: int) -> int:
    require(
        type(value) is int and minimum <= value <= maximum,
        "configuration",
        f"Expected integer in {minimum}..{maximum}",
    )
    return cast(int, value)


def parse_config(raw: Mapping[str, object]) -> Config:
    closed_keys(
        raw,
        {
            "profiles",
            "startup_timeout_seconds",
            "wait_timeout_seconds",
            "read_source",
            "read_lines",
        },
    )
    profiles: dict[str, Profile] = {}
    for name, value in table(raw.get("profiles", {})).items():
        require(bool(NAME.fullmatch(name)), "configuration", "Invalid profile name")
        profile = table(value)
        closed_keys(profile, {"args", "env", "selection_hint"})
        args = profile.get("args", [])
        require(
            isinstance(args, list)
            and all(
                isinstance(argument, str) and "\0" not in argument
                for argument in cast(list[object], args)
            ),
            "configuration",
            "args must be an exact string array without NUL",
        )
        environment: list[tuple[str, str]] = []
        for key, item in table(profile.get("env", {})).items():
            require(
                bool(re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", key))
                and not key.startswith("HERDR_")
                and not key.startswith("PI_SHEPHERD_")
                and key not in {"XDG_STATE_HOME", "XDG_RUNTIME_DIR"},
                "configuration",
                "Invalid or reserved environment key",
            )
            require(
                isinstance(item, str) and "\0" not in item,
                "configuration",
                "Invalid environment value",
            )
            environment.append((key, cast(str, item)))
        hint = profile.get("selection_hint")
        profiles[name] = Profile(
            name=name,
            args=tuple(cast(list[str], args)),
            env=tuple(sorted(environment)),
            selection_hint=text(hint, bounded=True) if hint is not None else None,
        )

    source = raw.get("read_source", "recent-unwrapped")
    require(source in READ_SOURCES, "configuration", "Unknown read source")
    return Config(
        profiles=profiles,
        startup_timeout_seconds=bounded_integer(
            raw.get("startup_timeout_seconds", 30), 4, 300
        ),
        wait_timeout_seconds=bounded_integer(
            raw.get("wait_timeout_seconds", 600), 0, 86400
        ),
        read_source=cast(str, source),
        read_lines=bounded_integer(raw.get("read_lines", 120), 1, 10000),
    )


def load_config(path: Path | None = None) -> Config:
    path = (
        path
        or xdg_root("XDG_CONFIG_HOME", Path.home() / ".config")
        / "pi-shepherd/config.toml"
    )
    try:
        with path.open("rb") as stream:
            return parse_config(tomllib.load(stream))
    except FileNotFoundError:
        return parse_config({})
    except (OSError, ValueError) as error:
        raise TeamError("configuration", "Could not read configuration") from error


def select_launch(
    config: Config,
    requested_profile: str | None,
    caller_kind: str | None,
    environment: Mapping[str, str],
) -> Launch:
    if requested_profile is not None:
        require(
            requested_profile in config.profiles,
            "configuration",
            "Unknown Pi profile",
        )
        profile = config.profiles[requested_profile]
        return Launch(profile=profile, args=profile.args, env=profile.env)

    require(
        caller_kind == PI_KIND,
        "caller_context",
        "Default creation requires a calling Pi agent",
    )
    values = tuple(
        pi_caller_value(environment, key) for key in PI_TWIN_ENVIRONMENT
    )
    require(
        values[2] in PI_THINKING_LEVELS,
        "caller_context",
        "Invalid Pi reasoning level",
    )
    arguments = tuple(
        item for pair in zip(PI_TWIN_OPTIONS, values, strict=True) for item in pair
    )
    return Launch(profile=None, args=arguments, env=())
