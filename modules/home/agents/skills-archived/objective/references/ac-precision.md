# AC Precision

Precision rules for phrasing objective acceptance criteria.

## AC Precision

An AC is a desired end state or behavior of the finished system — what is true
once the work is done. It is never an implementation detail, a task, or a step
toward that state.

Each AC should be independently verifiable. Split ACs that describe multiple
distinct outcomes. Merge ACs that can't be verified independently of each other.

Precision rules — each AC must:

- **Declare a state or behavior, not a step** — "Export endpoint rejects
  unauthenticated requests with 401" not "Add an auth check to the export
  endpoint".
- **State what happens, not what doesn't** — "Names exceeding max truncate with
  ellipsis" not "doesn't break layout".
- **Include concrete values** — thresholds, formats, specific outputs. "Wraps at
  80 chars" not "handles long text".
- **Describe observable outcomes, not qualities** — "Streams via cursor
  pagination" not "handles gracefully".
