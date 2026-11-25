# Alignment

What a change makes visible is the user's decision: anything a user, an API
client, an operator, or the author of another module could notice without
reading the change's code. That includes:

- data and schemas, and what happens to existing rows
- API endpoints and their requests, responses, errors, and callers
- UI screens and their states
- configuration keys and flags
- side effects such as emails, webhooks, and jobs
- the module structure and which module may depend on which
- invariants and dependencies

Before writing code that adds, changes, or removes any of these, agree the
change with the user as the acceptance criteria of a spec as the `spec` skill
defines it, scaled to the change: renaming one key takes one criterion, a new
subsystem a full spec. Changes the user already specified count as agreed. While
drafting the spec, settle yourself any choice the evidence clearly decides, as
the reasoning rules allow, and record it as the `spec` skill directs; the user
still agrees the whole spec, unless they handed you their decisions under the
reasoning rules, which agrees it once it leaves no question open. Decide
everything else, such as function bodies, private helpers, internal error
handling, and names that never leave one module, with sensible defaults.

An agreed spec binds the work. When building it needs a visible change no
criterion requires, would break its Boundaries section, or shows that a
criterion cannot hold, stop and present the deviation with its evidence instead
of working around it. Under a handover, decide a deviation the reasoning rules
let you decide, amend the spec, and list the amendment.
