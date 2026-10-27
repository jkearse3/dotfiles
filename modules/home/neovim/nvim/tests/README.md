# Neovim regression tests

The `neovim` flake check runs every spec hermetically against the plenary.nvim
and fzf-lua revisions pinned in `nvim-pack-lock.json`. From the repository root:

```sh
nix build .#checks.aarch64-darwin.neovim --print-build-logs
```

`./x.sh check` runs it together with the repository's other checks.

To run the specs by hand from `modules/home/neovim/nvim`, with Plenary and
fzf-lua already installed and `git`, `jj`, and `jjx` on PATH:

```sh
XDG_CONFIG_HOME="$(mktemp -d)" nvim --headless -u tests/minimal_init.lua -i NONE \
  -c "lua require('plenary.test_harness').test_directory('tests', { sequential = true, minimal_init = 'tests/minimal_init.lua' })"
```

The specs run `jjx ensure` in disposable repositories, which writes
repository-scoped jj config under `$XDG_CONFIG_HOME/jj/repos/`; the fresh
`XDG_CONFIG_HOME` keeps that out of your real config, while the unchanged `HOME`
and `XDG_DATA_HOME` still let Neovim find the installed plugins.

The minimal init applies to both the harness and its child processes. It avoids
loading personal configuration, installing/updating plugins, or loading
workspace state. Missing test dependencies fail rather than being installed
automatically.

To run a focused check, replace `'tests'` with a spec path such as
`'tests/lib/lazygit_spec.lua'`, keeping the fresh `XDG_CONFIG_HOME`:

```sh
XDG_CONFIG_HOME="$(mktemp -d)" nvim --headless -u tests/minimal_init.lua -i NONE \
  -c "lua require('plenary.test_harness').test_directory('tests/lib/lazygit_spec.lua', { sequential = true, minimal_init = 'tests/minimal_init.lua' })"
```

LazyGit tests use mocked jobs and a disposable Neovim terminal subprocess, not
the real LazyGit application or repository mutations.

`tests/lib/jj_review_source_spec.lua` uses disposable JJ repositories for pinned
bookmark ranges, read-only line attribution, concurrent bookmark movement,
divergent operation heads, bounded analysis, and cancellation. These tests
create and rewrite only temporary fixture history; they do not activate the
personal Neovim configuration or mutate this repository's history.
