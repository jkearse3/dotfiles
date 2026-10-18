# Build Copies

Put materialized revision copies and their build output only under `$TMPDIR` or
the agent's scratchpad, never in the home directory, a repository, or elsewhere.
Keep build output inside each copy; do not redirect `CARGO_TARGET_DIR` or
`build.build-dir` outside it. Build output is removed automatically when the
agent exits, so do not sweep it.
