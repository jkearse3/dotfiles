---
name: herdr-jj-workspace
description: >-
  Creates or removes a jj workspace shown as its own space in the Herdr desktop
  app, with the `herdr-jj-workspace` command. Use when the user, in the Herdr
  app, asks for a new jj workspace (or a Herdr jj workspace, or a workspace to
  work on something in parallel) or asks to remove one. Not for Git worktrees,
  which the app's own worktree commands handle, or for plain panes and tabs (use
  herdr-app).
---

# Herdr jj workspaces

`herdr-jj-workspace` does what the user's Herdr app shortcuts for new and
removed jj workspaces do, without moving the user's focus unless `--focus` is
given. It drives the Herdr desktop app: each jj workspace is shown as an app
space, and a space's ID comes from `herdr-app ls`.

## Create

```bash
herdr-jj-workspace add NAME
```

- NAME is one path component, such as `fix-login`; pick a short, descriptive
  name from the request when the user gave none.
- The repository is the one your working directory is in, which may be the
  primary checkout or any of its jj workspaces. Pass `--workspace ID` to use
  another space's repository. The new workspace opens as a new space: the find
  hub nests it under its repository's space, and the desk sidebar lists it
  beside the other spaces.
- The workspace starts from `trunk()` in `~/.worktrees/REPO/NAME`, where REPO is
  the primary checkout's path from the home directory. Pass `--revision REV` to
  start it on top of another revision instead, such as a bookmark the user wants
  to stack work on.
- Progress goes to stderr. Stdout is one JSON object:
  `{"path": ..., "workspace_id": ..., "pane_id": ...}`, where `workspace_id` is
  the new space's ID and `pane_id` its terminal's address.

Your own shell stays in its original checkout. To work in the new workspace, use
`path` as the working directory for later commands, or drive its terminal
`pane_id` with the herdr-core skill's `hc` commands. Report `path` to the user.

## Remove

Removal deletes the workspace's directory, snapshots its working copy into a jj
commit first (ignored files are lost), and closes its space. Remove only a
workspace you created in this session or one the user named.

```bash
herdr-jj-workspace remove --workspace ID --dry-run
herdr-jj-workspace remove --workspace ID
```

Run the dry run first and show the user what it reports. Without `--workspace`,
the space of the calling app terminal is removed, which closes the terminal
running the command; outside an app terminal, `--workspace` is required. The
checkout removed is where the space's first terminal is now. Primary checkouts
and Git worktrees are refused.
