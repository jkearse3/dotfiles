-- Core search keymaps that work without any plugin.
vim.keymap.set("n", "<leader>/", "<cmd>nohlsearch<cr>", { desc = "Clear search highlights" })

-- Fzf-lua fuzzy finder.
---@alias config.search.FzfPicker fun(opts?: table): thread?, string?, table?

---@param entry string
---@return string
local function git_status_path(entry)
	return entry:match("%s%-%>%s(.+)$") or entry
end

---@param fzf fzf-lua
local function configure_fzf(fzf)
	local git_options = require("lib.git_history").options(fzf)
	git_options.status = { _fmt = { from = git_status_path } }

	---@type fzf-lua.Config
	local options = {
		grep = { hidden = true },
		git = git_options,
		winopts = {
			fullscreen = true,
			preview = {
				layout = "vertical",
				vertical = "down:80%",
			},
		},
		keymap = {
			fzf = {
				true,
				["ctrl-q"] = "select-all+accept",
				["ctrl-l"] = "accept",
			},
		},
		actions = {
			files = {
				true,
				["ctrl-i"] = fzf.actions.toggle_ignore,
				["ctrl-h"] = fzf.actions.toggle_hidden,
			},
		},
	}

	fzf.setup(options)

	fzf.register_ui_select()
end

---@param fzf fzf-lua
local function explore_directory(fzf)
	fzf.fzf_exec("fd --type d --hidden --exclude .git", {
		prompt = vim.fn.fnamemodify(vim.fn.getcwd(), ":~") .. "/",
		actions = {
			---@param selected string[]
			["default"] = function(selected)
				vim.cmd.Explore(selected[1])
			end,
		},
	})
end

---@param key string
---@param picker config.search.FzfPicker
---@param description string
local function map_fzf_picker(key, picker, description)
	vim.keymap.set("n", key, picker, { desc = description })
end

---@param fzf fzf-lua
---@param key string
---@param picker config.search.FzfPicker
---@param description string
local function map_visual_fzf_picker(fzf, key, picker, description)
	vim.keymap.set("v", key, function()
		picker({ search = fzf.utils.get_visual_selection() })
	end, { desc = description })
end

---@param fzf fzf-lua
local function set_fzf_keymaps(fzf)
	map_fzf_picker("<leader>fe", function()
		explore_directory(fzf)
	end, "FZF: Explore directory")
	map_fzf_picker("<leader>ff", fzf.files, "FZF: Files")
	map_fzf_picker("<leader>fs", fzf.lgrep_curbuf, "FZF: Live grep file")
	map_visual_fzf_picker(
		fzf,
		"<leader>fs",
		fzf.lgrep_curbuf,
		"FZF: Live grep file (visual selection)"
	)
	map_fzf_picker("<leader>fS", fzf.live_grep, "FZF: Live grep workspace")
	map_visual_fzf_picker(
		fzf,
		"<leader>fS",
		fzf.live_grep,
		"FZF: Live grep workspace (visual selection)"
	)
	map_fzf_picker("<leader>fw", fzf.grep_cword, "FZF: Grep word")
	map_fzf_picker("<leader>fW", fzf.grep_cWORD, "FZF: Grep WORD")
	map_fzf_picker("<leader>fm", fzf.marks, "FZF: Marks")
	map_fzf_picker("<leader>fr", fzf.registers, "FZF: Registers")
	map_fzf_picker("<leader>f<leader>", fzf.resume, "FZF: Resume last search")
	map_fzf_picker("<leader>fh", fzf.helptags, "FZF: Help tags")
	map_fzf_picker("<leader>fk", fzf.keymaps, "FZF: Keymaps")
	map_fzf_picker("<leader>fb", fzf.buffers, "FZF: Open buffers")

	map_fzf_picker("<leader>fql", fzf.quickfix, "FZF: Quickfix list")
	map_fzf_picker("<leader>fqs", fzf.quickfix_stack, "FZF: Quickfix stack")

	map_fzf_picker("<leader>fls", fzf.lsp_document_symbols, "FZF: LSP document symbols")
	map_fzf_picker("<leader>flS", fzf.lsp_live_workspace_symbols, "FZF: LSP workspace symbols")
	map_fzf_picker("<leader>flr", fzf.lsp_references, "FZF: LSP references")
	map_fzf_picker("<leader>fld", fzf.lsp_definitions, "FZF: LSP definitions")
	map_fzf_picker("<leader>flD", fzf.lsp_declarations, "FZF: LSP declarations")
	map_fzf_picker("<leader>flt", fzf.lsp_typedefs, "FZF: LSP type definitions")
	map_fzf_picker("<leader>fli", fzf.lsp_implementations, "FZF: LSP type implementations")
	map_fzf_picker("<leader>flp", fzf.lsp_document_diagnostics, "FZF: LSP document diagnostics")
	map_fzf_picker("<leader>flP", fzf.lsp_workspace_diagnostics, "FZF: LSP workspace diagnostics")

	map_fzf_picker("<leader>fgs", fzf.git_status, "FZF: Git status")
	map_fzf_picker("<leader>fgS", fzf.git_stash, "FZF: Git stash")
	map_fzf_picker("<leader>fgf", fzf.git_files, "FZF: Git files")
	map_fzf_picker("<leader>fgb", fzf.git_branches, "FZF: Git branches")
	map_fzf_picker("<leader>fgB", fzf.git_blame, "FZF: Git blame")
	map_fzf_picker("<leader>fgt", fzf.git_tags, "FZF: Git tags")
	map_fzf_picker("<leader>fgh", fzf.git_hunks, "FZF: Git hunks")

	map_fzf_picker("<leader>fdb", fzf.dap_breakpoints, "FZF: DAP breakpoints")
end

require("lib.config").run({
	plugins = { "https://github.com/ibhagwan/fzf-lua" },
	setup = function()
		---@type fzf-lua
		local fzf = require("fzf-lua")
		configure_fzf(fzf)
		set_fzf_keymaps(fzf)
	end,
})
