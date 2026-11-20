# Running Checks

Run every check that can change a conclusion about whether a change is safe,
including full test suites and builds when the risk calls for them. Run them so
the machine stays usable:

- Start with the narrowest check that can settle the question, such as one test,
  file, or package, and widen only when its result leaves the question open.
- Run at most one heavy check at a time: a build, a test suite, or anything that
  checks out a revision copy. Walk a stack one revision at a time.
- When dispatching concurrent delegates, assign heavy checks to at most one of
  them at a time; run the rest sequentially afterward, yourself or through later
  delegates.
- Leave a tool's own parallelism, such as test runner workers or build jobs, at
  its default; never raise it.
- Record each check's command, revision, and result, and hand them to whoever
  needs them. Do not rerun a check on an unchanged tree when you have its
  recorded result, unless the result decides your next step and you did not
  observe it yourself.

When you check out a copy of a revision to build or test it, put it under
`$TMPDIR` or your scratchpad, never in the home directory, a repository, or
elsewhere. Use one copy and move it between revisions, so builds stay
incremental. Keep build output inside the copy; do not redirect
`CARGO_TARGET_DIR` or `build.build-dir` outside it. Build output is removed
automatically when the agent exits, so do not sweep it.
