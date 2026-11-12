# Starts Neovim exactly as Home Manager installs it and fails on startup
# errors, missing or duplicated plugins, or missing tree-sitter grammars.
#
# The check takes Home Manager's own built outputs rather than rebuilding them:
# `neovimPack` is the plugin pack linked to `~/.local/share/nvim/site/pack/hm`,
# `neovimConfig` the read-only store copy linked to `~/.config/nvim`, and
# `neovim` the wrapped `programs.neovim.finalPackage`, whose sideloaded init
# sets providers and `package.path`. A disposable HOME and XDG tree holds the
# config and pack where Neovim looks for them, `git` and `jj` are on PATH, and
# no `tree-sitter` executable is, so every parser must come from the pack.
#
# A probe loaded with `--cmd` before init records every `vim.notify` call at
# ERROR level: the config installs its own `vim.notify` in `config.notify`
# before any plugin block runs, so the probe preloads that module, runs the
# real file, and wraps the result with a recorder that forwards each call.
# After VimEnter the probe asserts that no error was reported, that each
# plugin in `plugins.nix` is on 'runtimepath' exactly once and loads, that
# plugin scripts were sourced once, and that a `.zig` buffer, a language with
# no compiled leftover, gets tree-sitter highlighting from a store parser.
#
# `flake/checks.nix` registers this as the `neovim-startup` check.
{
  git,
  jujutsu,
  lib,
  neovim,
  neovimConfig,
  neovimPack,
  runCommand,
  vimPlugins,
  writeText,
}:
let
  # The `:packadd` names Home Manager installs as optional plugins.
  neovimPluginNames = builtins.attrNames (import ./plugins.nix vimPlugins);

  startupProbe = writeText "neovim-startup-probe.lua" ''
    local reported_errors = {}
    local is_notify_recorded = false

    -- Runs the config's real notify module, then records ERROR calls of the
    -- `vim.notify` it installs while still forwarding every call to it.
    package.preload["config.notify"] = function()
    	local notify_path = vim.api.nvim_get_runtime_file("lua/config/notify.lua", false)[1]
    	assert(notify_path, "lua/config/notify.lua is not on 'runtimepath'")
    	dofile(notify_path)

    	local config_notify = vim.notify
    	vim.notify = function(msg, level, opts)
    		if level == vim.log.levels.ERROR then
    			table.insert(reported_errors, tostring(msg))
    		end
    		return config_notify(msg, level, opts)
    	end
    	is_notify_recorded = true
    end

    local plugin_names = ${lib.generators.toLua { } neovimPluginNames}
    local required_modules = {
    	"blink.cmp",
    	"conform",
    	"fzf-lua",
    	"gitsigns",
    	"dap",
    	"dap-go",
    	"lint",
    	"nvim-treesitter",
    	"oil",
    	"plenary",
    	"tokyonight",
    }

    local failures = {}

    local function fail(message)
    	table.insert(failures, message)
    end

    local function check_startup_errors()
    	if not is_notify_recorded then
    		fail("config.notify was never loaded, so vim.notify errors were not recorded")
    	end
    	for _, msg in ipairs(reported_errors) do
    		fail("vim.notify reported an ERROR: " .. msg)
    	end
    	if vim.v.errmsg ~= "" then
    		fail("v:errmsg is set: " .. vim.v.errmsg)
    	end
    end

    local function check_plugins_load()
    	for _, module in ipairs(required_modules) do
    		local ok, err = pcall(require, module)
    		if not ok then
    			fail("require('" .. module .. "') failed: " .. tostring(err))
    		end
    	end
    	if vim.fn.exists(":TestNearest") ~= 2 then
    		fail("vim-test's :TestNearest command is not defined")
    	end
    end

    local function check_runtimepath()
    	local runtimepath = vim.opt.runtimepath:get()
    	for _, entry in ipairs(runtimepath) do
    		if entry:find("/site/pack/core", 1, true) then
    			fail("'runtimepath' contains a vim.pack clone: " .. entry)
    		end
    	end

    	for _, name in ipairs(plugin_names) do
    		local suffix = "/opt/" .. name
    		local count = 0
    		for _, entry in ipairs(runtimepath) do
    			if entry:sub(-#suffix) == suffix then
    				count = count + 1
    			end
    		end
    		if count ~= 1 then
    			fail(string.format("%d 'runtimepath' entries end in %s, expected 1", count, suffix))
    		end
    	end

    	local conform_modules = #vim.api.nvim_get_runtime_file("lua/conform/init.lua", true)
    	if conform_modules ~= 1 then
    		fail(string.format("found %d copies of lua/conform/init.lua, expected 1", conform_modules))
    	end
    end

    -- conform.nvim's plugin script defines :ConformInfo without a load guard,
    -- so sourcing it twice would go unnoticed except in getscriptinfo().
    -- Script names are resolved store paths, such as
    -- `/nix/store/<hash>-vimplugin-conform.nvim-<version>/plugin/conform.lua`.
    local function check_plugin_scripts_sourced_once()
    	if vim.fn.exists(":ConformInfo") ~= 2 then
    		fail("conform.nvim's :ConformInfo command is not defined")
    	end
    	local conform_scripts = #vim.fn.getscriptinfo({ name = "conform\\.nvim[^/]*/plugin/" })
    	if conform_scripts ~= 1 then
    		fail(string.format("conform.nvim's plugin script was sourced %d times, expected 1", conform_scripts))
    	end
    end

    local function check_zig_highlighting()
    	vim.cmd.edit(vim.fn.fnameescape(vim.env.NEOVIM_STARTUP_ZIG_FILE))
    	local buf = vim.api.nvim_get_current_buf()
    	if vim.treesitter.highlighter.active[buf] == nil then
    		fail("opening a .zig file did not start tree-sitter highlighting")
    	end

    	local parser_path = vim.api.nvim_get_runtime_file("parser/zig.so", true)[1]
    	local parser_realpath = parser_path and vim.uv.fs_realpath(parser_path)
    	if not parser_realpath or not vim.startswith(parser_realpath, "/nix/store/") then
    		fail("parser/zig.so does not resolve into /nix/store: " .. tostring(parser_realpath or parser_path))
    	end
    end

    local function run_checks()
    	check_startup_errors()
    	check_plugins_load()
    	check_runtimepath()
    	check_plugin_scripts_sourced_once()
    	check_zig_highlighting()
    end

    -- Scheduled so every other VimEnter handler has run first.
    vim.api.nvim_create_autocmd("VimEnter", {
    	once = true,
    	callback = function()
    		vim.schedule(function()
    			local ok, err = pcall(run_checks)
    			if not ok then
    				fail("the probe itself failed: " .. tostring(err))
    			end

    			for _, message in ipairs(failures) do
    				io.stderr:write("neovim-startup: FAIL: " .. message .. "\n")
    			end
    			if #failures > 0 then
    				vim.cmd.cquit(1)
    			else
    				io.stdout:write("neovim-startup: ok\n")
    				vim.cmd.qall({ bang = true })
    			end
    		end)
    	end,
    })
  '';
in
runCommand "neovim-startup"
  {
    nativeBuildInputs = [
      git
      jujutsu
    ];
  }
  ''
    export HOME="$TMPDIR/home"
    export XDG_CONFIG_HOME="$TMPDIR/xdg/config"
    export XDG_DATA_HOME="$TMPDIR/xdg/data"
    export XDG_STATE_HOME="$TMPDIR/xdg/state"
    export XDG_CACHE_HOME="$TMPDIR/xdg/cache"
    export XDG_RUNTIME_DIR="$TMPDIR/xdg/run"
    mkdir -p "$HOME" "$XDG_CONFIG_HOME" "$XDG_DATA_HOME/nvim/site/pack" "$XDG_STATE_HOME" "$XDG_CACHE_HOME"
    mkdir -m 700 -p "$XDG_RUNTIME_DIR"

    ln -s ${neovimConfig} "$XDG_CONFIG_HOME/nvim"
    ln -s ${neovimPack} "$XDG_DATA_HOME/nvim/site/pack/hm"

    if command -v tree-sitter >/dev/null; then
      echo "neovim-startup: tree-sitter must not be on PATH" >&2
      exit 1
    fi

    mkdir "$TMPDIR/work"
    cd "$TMPDIR/work"
    export NEOVIM_STARTUP_ZIG_FILE="$TMPDIR/work/main.zig"
    echo 'pub fn main() void {}' > "$NEOVIM_STARTUP_ZIG_FILE"

    # The timeout turns a probe that never quits into a failure, and the
    # required output line catches an exit that skipped the probe.
    set -o pipefail
    timeout 120 ${neovim}/bin/nvim --headless --cmd "luafile ${startupProbe}" \
      | tee "$TMPDIR/nvim-output.log"
    grep -qxF 'neovim-startup: ok' "$TMPDIR/nvim-output.log" \
      || { echo "neovim-startup: Neovim exited without running the probe" >&2; exit 1; }

    touch "$out"
  ''
