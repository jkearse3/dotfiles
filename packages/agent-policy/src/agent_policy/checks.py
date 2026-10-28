"""Named checks: policy analysis that needs code rather than declarations.

An allowlist rule lists check names in its ``checks`` key. A check runs only
when its rule's declarations raise no objection, the rule is not approved, and
the invocation uses no informational option. It may inspect the repository or
run the real tool (for example a dry run), but must not change anything.
Validation rejects a policy that names a check missing from
``NAMED_CHECKS``.
"""

from __future__ import annotations

from collections.abc import Callable, Mapping
from dataclasses import dataclass
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from .invocation import ParsedInvocation
    from .policy import AllowlistRule


@dataclass(frozen=True)
class CheckRequest:
    """Everything a named check may use to judge one invocation."""

    rule: AllowlistRule
    """The owning rule; its ``target_options`` bound how many things the
    invocation may act on."""
    invocation: ParsedInvocation
    """The agent's argv, read against the rule's allowed options."""
    real_command: tuple[str, ...]
    """The real executable followed by the tool's forced prefix arguments."""
    environment: Mapping[str, str]
    """The process environment without ``AGENT_POLICY_APPROVE``."""


@dataclass(frozen=True)
class CheckRefusal:
    """A named check's objection, reported under the owning rule's ID."""

    reason: str
    """Why the invocation is refused, as a clause without a final period."""


NamedCheck = Callable[[CheckRequest], CheckRefusal | None]
"""A check returns ``None`` to pass or a ``CheckRefusal``. An exception it
raises refuses the invocation under the owning rule."""

NAMED_CHECKS: dict[str, NamedCheck] = {}
"""Every check a policy may name, keyed by the name used in policy files."""
