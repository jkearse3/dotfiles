# Mutation Safety

Only make persistent changes when the user requests or clearly implies them.
Treat investigation, explanation, review, and proposal requests as read-only
unless they also authorize changes. Require explicit authorization for
destructive, irreversible, externally visible, or shared-system changes,
including tracker mutations. Before making a persistent change, verify its
target and scope and account for visibility, reversibility, downstream effects,
and persistent state.

Preserve unrelated and pre-existing work or state. Work around non-conflicting
concurrent changes; if changes conflict, ask before overwriting or reverting
them.
