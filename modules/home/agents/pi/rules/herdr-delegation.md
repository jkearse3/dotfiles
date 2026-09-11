# Herdr Delegation

For a Pi session not itself delegated by another Pi session, standing delegation
authorization includes managed Herdr teammates.

For Pi delegation, load and follow the installed `pi-shepherd` skill. Use
`pi-shepherd`, not an `Agent` tool, in-process subagent, or raw Herdr; if the
skill or managed path is unavailable or fails, stop.

Keep source writes in the initiating session by default; delegate writes only
through an explicit, nonoverlapping assignment.
