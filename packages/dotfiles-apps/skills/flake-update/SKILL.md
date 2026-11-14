---
name: flake-update
description:
  Updates this dotfiles repository's flake inputs and package pins with `nix run
  .#flake-update`, fixes what the update breaks inside the same jj change, and
  explains each fix in its description. Use when the user asks to update
  dependencies, flake inputs, flake.lock, nixpkgs, or package pins in this
  repository, or to finish a dependency update a failed run left in `@`. Not for
  activating the result (`switch-home`, `switch-system`) or for publishing.
---

# Flake Update

`nix run .#flake-update` owns the whole update: it updates the inputs and pins
in a jj change, checks it, generates the description's lists of what moved, and
commits. Your part is to fix what its checks reject and to explain each fix.
Never commit, squash, split, or redescribe the update outside this procedure;
doing so skips the checks or drops the generated lists.

`docs/architecture.md` (Blueprint Outputs) describes the command's behavior.

## Prepare

1. Work from the repository root. Choose the base: `trunk()` unless the user
   names another. `nix run .#flake-update` runs the checkout's own copy of the
   command, so while a stack that changes flake-update is unlanded, update on
   top of that stack to use it.
2. Look for an unlanded dependency update:

   ```bash
   jj log -r 'subject(exact:"build(nix): update dependencies") ~ ::trunk()'
   ```

   If one exists, ask the user whether to stack the new update on it, discard
   it, or land it first; updating beside it redoes its work and its fixes.

3. Put an empty, undescribed `@` on the base. The command updates in that `@`;
   any other `@` gets a new child, stacking the update on what `@` holds.
4. Run `jj status`. If it fails because 1Password is locked, ask the user to
   unlock it: the `nix` wrapper snapshots through jj, and jj signs the commit.

## Run

1. Run the command so its progress reaches you as it happens, with the full log
   kept in a file for reading errors:

   ```bash
   log="$(mktemp -t flake-update.XXXXXX)"
   nix run .#flake-update 2>&1 | tee "$log" |
     grep --line-buffered -E '^(==>|error:|warning: could|Resuming|Dependencies unchanged)'
   echo "flake-update exited ${PIPESTATUS[0]}; full log: $log"
   ```

   A run takes several minutes, longer when it builds packages. When the harness
   can stream a background command's output lines as events, such as Claude
   Code's Monitor tool with its longest timeout, run it that way. Otherwise run
   it in the foreground with the longest timeout available. Never start it
   detached and guess when it finishes; the exit line is the only sign it ended.
   Pass no `--blueprint`, and no `DOTFILES_PRIVATE_LOCAL` unless the user asks.

2. Relay each phase to the user as one short line as it starts:
   - `==> Updating flake inputs and package pins`: fetching the new lock and
     running the package updaters.
   - `Resuming the dependency update in @`: a previous run left the update; this
     run skips updating.
   - `==> Checking: <check>`: evaluating every blueprint, `nix flake check`,
     then building the home and system configurations.
   - `==> Building the configurations of @- to compare package versions`: slow
     when the parent was never built.
   - `==> Committing the dependency update`: signing and committing.
   - `==> Committed the dependency update as <change-id>`: done; the description
     is printed just before it.
3. Act on the outcome:
   - `Dependencies unchanged; nothing to commit`: report it and stop.
   - `error: <check> failed.`: read the lines before it in the log; see Fix.
   - `also changes files beyond the dependency pins`: write the explanation; see
     Explain.
   - `updating dependencies failed`: `@` is restored and no update remains.
     Report the cause from the log, such as a network or updater failure, and
     stop.
   - `files in @ changed while the checks ran`: rerun once nothing else is
     editing the checkout.
   - `committing the update failed` with a signing error: ask the user to unlock
     1Password, then rerun.
   - `warning: could not build the configurations of @-`: the commit lacks the
     package-version list; mention it in the report.
   - Anything else that looks wrong, in the output or the description it
     generates: see Improve the Command.

## Fix

The failed update stays uncommitted in `@` with the subject
`build(nix): update dependencies`. Work in `@` itself; never `jj new` or
`jj commit` there.

1. Read the error to the failing module or package. The repository guards its
   workarounds with assertions that fail once upstream changes, naming the file
   and the condition, such as an overlay that "may no longer be needed".
2. Confirm the cause against the updated inputs before changing anything, for
   example by evaluating the new package's version or build inputs from the
   locked revision in `flake.lock`.
3. Make the smallest fix: drop a workaround upstream made redundant, restore
   what it replaced, or adapt the configuration to the upstream change. Keep
   unrelated cleanup out of the update.
4. Run the narrowest check that shows the fix works, then go to Explain.

## Explain

Every fix needs an explanation in the description of `@`, between the subject
and the generated lists. The command refuses to check or commit a fix without
one.

1. Read `~/.agents/skills/finalize-changes/references/revision-descriptions.md`
   and follow its body rules: why the update needed the fix and what the fix
   changes, in separate paragraphs, with no workflow narration.
2. Keep the subject exactly `build(nix): update dependencies`; the next run
   finds the update by it. Do not write the input, pin, or package-version
   lists; the command generates them and replaces anything from their headings
   down.
3. Write it with `jj describe -m "<full description>"`, keeping explanations of
   earlier fixes in the same update.
4. Rerun `nix run .#flake-update`. It resumes the update in `@`, reruns the
   checks without updating again, and commits. Repeat Fix and Explain until it
   commits.

## Improve the Command

This skill and the command improve as they are used. When the command
misbehaves, fix the command rather than working around it in the update. Signs:

- A generated list is wrong, noisy, or misses a change the closures or
  `flake.lock` show.
- A message points the wrong way, or a failure matches no outcome under Run.
- The command does something this skill does not describe.

Never hand-edit the generated lists, which the next run replaces, and never put
a change to the command inside the update.

1. Show the user the evidence: the output in question beside what the real data
   says, such as the closures, `flake.lock`, or the log. Propose the fix, and
   make it only once the user agrees; it changes a tool, not just dependencies.
2. The command runs from the checkout, so the fix must sit below the update for
   the update to use it. Insert a revision under the update and work in it:

   ```bash
   jj new --no-edit --insert-before <update>
   jj edit '<update>-'
   ```

   `<update>` is the update's change ID, and `<update>-` is then the new
   revision below it. Record the ID before moving, because `@` moves to the fix:
   while the update is uncommitted in `@`, it is
   `jj log -r @ --no-graph -T 'change_id.short()'`; for a committed update,
   `jj log -r 'subject(exact:"build(nix): update dependencies") ~ ::trunk()'`
   lists it.

3. Fix `packages/dotfiles-apps/flake-update.sh` following the repository's
   coding rules. Add a case to `flake-update-test.sh` that fails without the
   fix, using the real data's shape as the fixture, and confirm it fails when
   the fix is reverted. When the command's output lines change, update the Run
   section here; `flake-update-test.sh` fails when this skill quotes a line the
   command no longer prints. When the problem was in this skill's guidance, fix
   the skill in the same revision.
4. Run `nix flake check`, then describe the fix revision following
   `finalize-changes` and its revision-description rules.
5. Return to the update with `jj edit <update>` and rerun
   `nix run .#flake-update`. It resumes the update with the fixed command,
   reruns the checks, and regenerates the description, keeping the explanation.
   This also works for an update already committed.
6. Report the fix revision separately from the update. It lands before the
   update.

## Discard

`jj abandon @` discards the update. Do it only when the user asks or when the
update must start over, and say so.

## Report

Report the committed change ID and its full description, the notable version
changes in it, each fix and why it was needed, and anything left undone.
Activation is a separate step: run `switch-home` or `switch-system` only when
the user asks.
