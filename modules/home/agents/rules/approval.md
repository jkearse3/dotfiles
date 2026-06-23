# Approval

Do not perform any mutating action without explicit user approval ("yes", "go ahead", "proceed",
"lgtm").

A mutating action is anything that changes local files, repository state, external services, system
state, or user-visible configuration.

- User requests are not approval by themselves — user may still be exploring.
- Before approval, state the intended mutation clearly enough for the user to know what will change.
- Once approved, follow the plan; stop and ask again if deviating or if the plan fails.
