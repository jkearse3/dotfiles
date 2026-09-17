# Herdr Delegation

For a Pi session not itself delegated by another Pi session, standing delegation
authorization includes managed Herdr teammates.

For Pi delegation, load and follow the installed `herdr-delegation` skill. Use
Herdr-managed teammates, not an `Agent` tool or in-process subagent. If the
managed path or request-scoped result delivery fails, stop rather than changing
coordination mechanisms implicitly.

Keep source writes in the initiating session by default; delegate writes only
through an explicit, nonoverlapping assignment. Treat request-scoped result
files as temporary message transport, not authority to mutate project files.
