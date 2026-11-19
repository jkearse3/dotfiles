---
name: rex
description:
  Use the rex CLI to manage Rex sessions, open tabs, arrange panes, run
  commands, inspect terminal output, and control connected Rex apps.
metadata:
  rex-stub: "2"
---

<!-- The stub "rex skill setup" installs, kept in the dotfiles repo
(modules/home/terminal/rex/skill) so Home Manager installs it instead. -->

Run `rex __internal skill --feature-session-naming=false` and follow the guide
it prints. The guide comes from the installed Rex CLI, so it describes the
commands available in that version.

If the command fails, the installed Rex version predates the guide. Start with
`rex whoami --json`, then use `rex --help` and `rex COMMAND --help`.
