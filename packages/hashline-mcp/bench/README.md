# hashline benchmark

Runs the same editing tasks through headless Claude Code with and without the
hashline tools and compares success, tokens, cost, turns, tool errors, and time.

The `hashline` arm launches `claude` as usual. The `stock` arm sets
`CLAUDE_HASHLINE=0`, which the `claude` wrapper reads to leave out the hashline
MCP server; the CLAUDE.md hashline rule applies only when those tools are
present. A run whose session did not load the tools its arm expects is marked
invalid and left out of the report.

Each task seeds a fresh temporary directory, runs one `claude -p` session in
auto permission mode with prompts denied, and passes only when the directory
then matches the expected files byte for byte. The tasks are defined in
`hashline_bench/tasks.py`. List them with:

```sh
PYTHONPATH=packages/hashline-mcp/bench python3 -m hashline_bench tasks
```

## Running

Sessions spend real API usage: each run is one session per task, arm, and
repetition. Start with a small run to check the setup:

```sh
PYTHONPATH=packages/hashline-mcp/bench python3 -m hashline_bench run \
  --runs 2 --min-runs 2 --task read-only-control --task several-edits-in-one-file
```

A fuller comparison of both arms:

```sh
PYTHONPATH=packages/hashline-mcp/bench python3 -m hashline_bench run --jobs 4
```

### Spending less

- **Reuse stock results.** Stock sessions do not change when hashline does, so
  compare a new hashline build against an earlier run's stock results:

  ```sh
  PYTHONPATH=packages/hashline-mcp/bench python3 -m hashline_bench run \
    --baseline <earlier-results-dir> --jobs 4
  ```

  This runs only the hashline arm. It refuses a baseline whose tasks have
  changed since, by the task digests each run records in `config.json`. Run
  stock again after a Claude Code or model update.

- **Stop when the answer is clear.** Each task runs `--min-runs` times per arm
  (default 3), then one more round at a time while its time comparison is
  unsure, up to `--runs` (default 5). A comparison is decided once its 90%
  interval excludes 1 or lies within 10% of it. Against a baseline, more
  hashline runs cannot narrow the stock side of the interval, so a task still
  unsure after about five runs usually stays unsure; treat it as a difference
  too small to measure rather than raising `--runs`.
- **Warm the prompt cache.** Before the first round, each arm runs one short
  unrecorded session, so the first measured sessions after a change to the tool
  definitions do not pay to write the prompt cache. `--no-warmup` skips it.
- **Run the core set.** By default only the core tasks run; tasks that behave
  like another core task are left out. `--all-tasks` includes them, and `--task`
  picks tasks by name, such as only the move tasks after a change to `move`.

Options include `--model`, `--effort`, `--max-budget-usd` (per session, default
2), `--timeout` (seconds per session), and `--seed` (schedule order). Sessions
run in a shuffled order so neither arm consistently goes first.

Results go to `$XDG_STATE_HOME/hashline-bench/<timestamp>/` unless `--out` is
given:

- `runs.jsonl`: one record per session
- `report.md`: the summary printed at the end
- `transcripts/`: each session's stream-json output and stderr
- `failed/`: the working directory of every failed or invalid run

Summarize a finished or interrupted run again with:

```sh
PYTHONPATH=packages/hashline-mcp/bench python3 -m hashline_bench report <results-dir>
```

## Reading the report

The report compares medians per task, because results vary between sessions. A
ratio below 1 means hashline used less. Turns are the steadiest measure of a
change's effect, and each costs a few seconds, so judge a change by turns and
output tokens first. Wall time is the goal but varies most, so its ratio comes
with a 90% interval and a verdict: `lower`, `higher`, `equivalent` (within 10%),
or `unsure`. Totals sum per-task means, since tasks may run different numbers of
times. In the hashline arm, `shell calls` usually counts checks the tools'
results should have made unnecessary. `read-only-control` makes no edits, so its
difference is the cost of carrying the hashline tool schemas.

## Tests

```sh
cd packages/hashline-mcp/bench
python3 -B -m unittest discover -s tests
```

The tests replace `claude` with a fake script, so they make no API calls.
