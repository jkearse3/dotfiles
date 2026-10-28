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

from .jj_push_dry_run import jj_push_dry_run_refusal

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


def check_jj_push_dry_run(request: CheckRequest) -> CheckRefusal | None:
    """Refuse a `jj git push` unless its dry run only adds or moves forward
    at most as many bookmarks as it names targets (see ``jj_push_dry_run``)."""
    reason = jj_push_dry_run_refusal(request)
    return None if reason is None else CheckRefusal(reason)


NAMED_CHECKS: dict[str, NamedCheck] = {
    "jj-push-dry-run": check_jj_push_dry_run,
}
"""Every check a policy may name, keyed by the name used in policy files."""
