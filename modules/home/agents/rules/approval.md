# Approval

Do not perform any mutating action without explicit user approval ("yes", "go ahead", "proceed",
"lgtm").

A mutating action is anything that changes local files, repository state, external services, system
state, or user-visible configuration.

- User requests are not approval by themselves — user may still be exploring.
- Before approval, state the intended mutation clearly enough for the user to know what will change.
- Approval may cover one action or a stated bounded plan. When the user explicitly approves a plan,
  that approval authorizes only the mutations listed in that plan until the plan completes, blocks,
  fails, or changes scope.
- Once approved, follow the plan; stop and ask again if deviating or if the plan fails.

Fresh approval is required before:

- Any mutation outside the approved plan, or any scope or approach change that changes the intended
  mutations.
- Continuing after an approved plan blocks or fails.
- VCS lifecycle actions unless the approved plan specifically includes them, including commit,
  amend, describe, split, squash, branch/bookmark switching, push, or release actions.
- Destructive or hard-to-reverse changes, unless the approved plan specifically includes them.
- Mutating external services.
- Changing user-visible system configuration.
