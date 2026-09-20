# Neovim regression tests

From `modules/home/neovim/nvim`, with Plenary and fzf-lua already installed and
`git`, `jj`, and `jj-ensure` on PATH:

```sh
nvim --headless -u tests/minimal_init.lua -i NONE \
  -c "lua require('plenary.test_harness').test_directory('tests', { sequential = true, minimal_init = 'tests/minimal_init.lua' })"
```

The minimal init applies to both the harness and its child processes. It avoids
loading personal configuration, installing/updating plugins, or loading
workspace state. Missing test dependencies fail rather than being installed
automatically.

To run a focused check, replace `'tests'` with a spec path such as
`'tests/lib/lazygit_spec.lua'`. LazyGit tests use mocked jobs and a disposable
Neovim terminal subprocess, not the real LazyGit application or repository
mutations.
