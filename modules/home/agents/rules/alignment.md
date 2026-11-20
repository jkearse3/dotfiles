# Alignment

What a change makes visible is the user's decision: anything a user, an API
client, an operator, or the author of another module could notice without
reading the change's code. That includes data and schemas with what happens to
existing rows, API endpoints and their requests, responses, errors, and callers,
UI screens and their states, configuration keys and flags, side effects such as
emails, webhooks, and jobs, the module structure and which module may depend on
which, invariants, and dependencies.

Before writing code that adds, changes, or removes any of these, agree the
change with the user as the acceptance criteria of a spec that `spec` defines,
scaled to the change: renaming one key takes one criterion, a new subsystem a
full spec. Changes the user already specified count as agreed. Within the
criteria the user agrees, a choice the evidence clearly settles may be made
without asking, as the reasoning rules allow, and listed with the spec as `spec`
presents it; the user still sees and agrees the whole spec. Everything else,
such as function bodies, private helpers, internal error handling, and names
that never leave one module, decide with sensible defaults.

An agreed spec binds the work. When building it needs a visible change no
criterion requires, would break one of its Boundaries, or shows that a criterion
cannot hold, stop and present the deviation with its evidence instead of working
around it.
