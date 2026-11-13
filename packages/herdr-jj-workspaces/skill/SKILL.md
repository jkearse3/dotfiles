---
name: herdr-jj-workspace
description: >-
  Creates or removes a jj workspace shown as its own Herdr workspace, or as its
  own space in the Herdr desktop app, with the `herdr-jj-workspace` command. Use
  when the user, inside Herdr or the Herdr app, asks for a new jj workspace (or
  a Herdr jj workspace, or a workspace to work on something in parallel) or asks
  to remove one. Not for Git worktrees, which Herdr's own worktree commands
  handle, or for plain panes and tabs.
---

# Herdr jj workspaces

`herdr-jj-workspace` does what the user's Herdr shortcuts for new and removed jj
workspaces do, without moving the user's focus unless `--focus` is given.

It drives one of two Herdrs, chosen with `--host`:

- `tui`, the Herdr terminal UI, where `HERDR_ENV=1` is set, and anywhere outside
  the app.
- `app`, the Herdr desktop app, where `HC_TERMINAL_ID` is set and `HERDR_ENV` is
  not `1`. A workspace is an app space, and its ID is a space ID from
  `herdr-app ls`.

Leave `--host` out: the command picks the Herdr it runs in.

## Create

```bash
herdr-jj-workspace add NAME
```

- NAME is one path component, such as `fix-login`; pick a short, descriptive
  name from the request when the user gave none.
- In the TUI, the repository is the one shown by the calling pane's Herdr
  workspace; in the app, it is the one your working directory is in. Either may
  be the primary checkout or any of its jj workspaces. Pass `--workspace ID` to
  use another workspace's or space's repository. The new workspace is grouped
  under the primary checkout's.
- The workspace starts from `trunk()` in `~/.herdr/worktrees/REPO/NAME`. Pass
  `--revision REV` to start it on top of another revision instead, such as a
  bookmark the user wants to stack work on.
- Progress goes to stderr. Stdout is one JSON object:
  `{"path": ..., "workspace_id": ..., "pane_id": ...}`. In the app,
  `workspace_id` is the new space's ID and `pane_id` its terminal's address.

Your own shell stays in its original checkout. To work in the new workspace, use
`path` as the working directory for later commands, or drive its first pane
`pane_id` with the Herdr skill's pane commands (in the app, the herdr-core
skill's `hc` commands). Report `path` to the user.

## Remove

Removal deletes the workspace's directory, snapshots its working copy into a jj
commit first (ignored files are lost), and closes its Herdr workspace or app
space. Remove only a workspace you created in this session or one the user
named.

```bash
herdr-jj-workspace remove --workspace ID --dry-run
herdr-jj-workspace remove --workspace ID
```

Run the dry run first and show the user what it reports. Without `--workspace`,
the calling pane's Herdr workspace or app space is removed, which closes the
pane running the command. In the app, the checkout removed is where the space's
first terminal is now. Primary checkouts and Git worktrees are refused.
