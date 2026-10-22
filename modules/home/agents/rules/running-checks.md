# Running Checks

Run every check that can change a conclusion about whether a change is safe,
including full test suites and builds when the risk calls for them. Run them so
the machine stays usable:

- Run at most one heavy check at a time: a build, a test suite, or anything that
  materializes a revision copy. Walk a stack one revision at a time.
- When dispatching concurrent delegates, assign heavy checks to at most one of
  them at a time; run the rest sequentially afterward, yourself or through later
  delegates.
- Start with the narrowest check that can settle the question, such as one test,
  file, or package, and widen only when its result leaves the question open.
- Record each check's command, revision, and result, and hand them to whoever
  needs them. Do not rerun a check on an unchanged tree when you have its
  recorded result, unless the result decides your next step and you did not
  observe it yourself.
- Check revisions in one materialized copy moved between them, so builds stay
  incremental, rather than in a fresh copy per revision.
- Leave a tool's own parallelism, such as test runner workers or build jobs, at
  its default; never raise it.
