---
name: herdr-jj-workspace
description: >-
  Creates or removes a jj workspace shown as its own Herdr workspace with the
  `herdr-jj-workspace` command. Use when the user, inside Herdr, asks for a new
  jj workspace (or a Herdr jj workspace, or a workspace to work on something in
  parallel) or asks to remove one. Not for Git worktrees, which Herdr's own
  worktree commands handle, or for plain panes and tabs. Requires HERDR_ENV=1.
---

# Herdr jj workspaces

`herdr-jj-workspace` does what the user's Herdr shortcuts for new and removed jj
workspaces do, without moving the user's focus unless `--focus` is given.

## Create

```bash
herdr-jj-workspace add NAME
```

- NAME is one path component, such as `fix-login`; pick a short, descriptive
  name from the request when the user gave none.
- The repository is the one shown by the calling pane's Herdr workspace, which
  may be the primary checkout or any of its jj workspaces; pass `--workspace ID`
  to use another Herdr workspace's repository. The new Herdr workspace is
  grouped under the primary checkout's.
- The workspace starts from `trunk()` in `~/.herdr/worktrees/REPO/NAME`.
- Progress goes to stderr. Stdout is one JSON object:
  `{"path": ..., "workspace_id": ..., "pane_id": ...}`.

Your own shell stays in its original checkout. To work in the new workspace, use
`path` as the working directory for later commands, or drive its root pane
`pane_id` with the Herdr skill's pane commands. Report `path` to the user.

## Remove

Removal deletes the workspace's directory, snapshots its working copy into a jj
commit first (ignored files are lost), and closes its Herdr workspace. Remove
only a workspace you created in this session or one the user named.

```bash
herdr-jj-workspace remove --workspace ID --dry-run
herdr-jj-workspace remove --workspace ID
```

Run the dry run first and show the user what it reports. Without `--workspace`,
the calling pane's Herdr workspace is removed, which closes the pane running the
command. Primary checkouts and Git worktrees are refused.
