# Herdr Core Terminals

When `HC_TERMINAL_ID` is set, you run inside herdr-core and the user can watch
each terminal you start in the Herdr sidebar. A terminal runs with the login
session's environment, not yours, so expand any value your job takes from your
environment, such as your `$TMPDIR`, in your own shell or write it out as an
absolute path. For each background job:

- Start it with
  `hc run --bg --no-notify --name <name> --cwd <dir> -- <command>`, and when
  `<dir>` has an `.envrc`, run the command through `direnv exec .` so it gets
  the project's tools rather than `/nix/store` paths copied into `PATH`. If
  direnv reports the `.envrc` is blocked, ask the user to allow it; do not run
  `direnv allow` yourself.
- Let the job write to its terminal. A terminal keeps about 1,100 lines, so when
  you need more, run `bash -c 'set -o pipefail; <command> 2>&1 | tee <log>'`
  with `<log>` an absolute path in your scratchpad or `$TMPDIR`. Never redirect
  output away from the terminal, and never append commands after the job, such
  as `; echo EXIT=$?`, because they replace its exit code.
- Wait with `hc wait <name> --timeout <seconds>`, choosing a timeout shorter
  than your shell tool's own limit, and read its JSON: while `ended` is false,
  wait again; once true, `exit_code` is the job's result. `hc wait` itself exits
  0 whatever the job returned. A server never ends, so wait until it is ready
  with `hc wait <name> --output <text> --timeout <seconds>`: `ended` turns true
  with `reason` `output` while the server keeps running. It matches only output
  printed after the wait starts, so on a timeout check `hc read <name>` for the
  text. Once you are done with the server, `hc kill <name>`. For a short job you
  would block on anyway, run it in the foreground by leaving out `--bg` and
  passing the same `--timeout <seconds>`: `hc run` then exits with the job's
  code, or exits 124 and prints `[hc] still running as <t>` when that timeout
  passes, in which case wait on `<name>` as above.
- Do not use `--rm`: a job that exits before you wait on it is removed with its
  exit code. Once it has ended, `hc read <name> --lines <n>` if you need output,
  then `hc rm <name>`. Removing a terminal does not remove its children, so
  remove each one you started.
