# Herdr Core Terminals

When `HC_TERMINAL_ID` is set, you run inside herdr-core. Run background jobs and
servers as `hc` terminals, which the user can watch in the Herdr sidebar. A
terminal gets the login session's environment, not yours, so expand any value
your job takes from your environment, such as your `$TMPDIR`, in your own shell
or write it out as an absolute path.

- Start a job with
  `hc run --bg --no-notify --name <name> --cwd <dir> -- <command>`; without
  `--no-notify`, hc types a note into your input when the job ends. When `<dir>`
  has an `.envrc`, run the command through `direnv exec .` so it gets the
  project's tools rather than `/nix/store` paths copied into `PATH`. If direnv
  reports the `.envrc` is blocked, ask the user to allow it; do not run
  `direnv allow` yourself.
- Let the job write to its terminal. A terminal keeps about 1,100 lines, so when
  you need more, run `bash -c 'set -o pipefail; <command> 2>&1 | tee <log>'`
  with `<log>` an absolute path in your scratchpad or `$TMPDIR`. Never redirect
  output away from the terminal, and never append commands after the job, such
  as `; echo EXIT=$?`, because they replace its exit code.
- Wait with `hc wait <name> --timeout <seconds>`, choosing a timeout shorter
  than your shell tool's own limit. `hc wait` exits 0 whatever the job returned,
  so read its JSON: while `ended` is false, wait again; once true, `exit_code`
  is the job's result.
- A server never ends, so wait until it is ready with
  `hc wait <name> --output <text> --timeout <seconds>`: `ended` turns true with
  `reason` `output` while the server keeps running. The wait matches only output
  printed after it starts, so on a timeout check `hc read <name>` for the text.
  Run `hc kill <name>` once you are done with the server.
- A job you would block on anyway, such as a build or test run, can run in the
  foreground: leave out `--bg` and pass `--timeout <seconds>`. `hc run` then
  exits with the job's code, or, when the timeout passes, prints
  `[hc] still running as <terminal>` and exits 124; then wait on `<name>` as
  above.
- Do not use `--rm`: it removes a job that ends before you wait on it, along
  with its exit code. Once a job has ended, run `hc read <name> --lines <n>` if
  you need its output, then `hc rm <name>`. Removing a terminal does not remove
  the terminals it started, so remove each one you started.
