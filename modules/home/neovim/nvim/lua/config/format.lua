--- Uses only the first available formatter, preferring treefmt over fallbacks.
---@param ... string Fallback formatter names in priority order.
---@return conform.FiletypeFormatter
local function with_treefmt(...)
	local formatters = { "treefmt", ... }
	formatters.stop_after_first = true
	return formatters
end

local FORMAT_ON_SAVE_DENY_LIST = { "html", "markdown", "sh" }

--- Leaves excluded filetypes to explicit formatting commands.
---@param bufnr integer
---@return conform.FormatOpts|nil
local function format_on_save(bufnr)
	if vim.tbl_contains(FORMAT_ON_SAVE_DENY_LIST, vim.bo[bufnr].filetype) then
		return
	end

	return {
		timeout_ms = 5000,
		lsp_format = "fallback",
	}
end

--- Looks upward from the formatted file, stopping at the home directory.
---@param _ conform.FormatterConfig
---@param ctx conform.Context
---@return string[]
local function kdlfmt_config_args(_, ctx)
	local config_path = vim.fs.find("kdlfmt.kdl", {
		path = ctx.filename,
		upward = true,
		stop = vim.loop.os_homedir(),
	})[1]
	if config_path then
		return { "--config", config_path }
	end

	return {}
end

local function setup_conform()
	local conform = require("conform")
	conform.setup({
		formatters = {
			treefmt = {
				inherit = true,
				cwd = require("conform.util").root_file({
					"flake.nix",
					"treefmt.toml",
					".treefmt.toml",
				}),
			},
		},
		format_on_save = format_on_save,
		formatters_by_ft = {
			lua = with_treefmt("stylua"),
			nix = with_treefmt("nixfmt"),
			go = with_treefmt("golangci-lint"),
			json = with_treefmt("prettier"),
			javascript = with_treefmt("prettier"),
			javascriptreact = with_treefmt("prettier"),
			typescript = with_treefmt("prettier"),
			typescriptreact = with_treefmt("prettier"),
			html = with_treefmt("prettier"),
			markdown = with_treefmt("prettier"),
			yaml = with_treefmt("prettier"),
			css = with_treefmt("prettier"),
			scss = with_treefmt("prettier"),
			sh = with_treefmt("shfmt"),
			zsh = with_treefmt("shfmt"),
			fish = with_treefmt("fish_indent"),
			rust = with_treefmt("rustfmt"),
			proto = with_treefmt("buf"),
			jsonnet = with_treefmt("jsonnetfmt"),
			kdl = with_treefmt("kdlfmt"),
			toml = with_treefmt("taplo"),
			["_"] = { "treefmt" },
		},
	})

	conform.formatters.kdlfmt = {
		inherit = true,
		append_args = kdlfmt_config_args,
	}

	vim.api.nvim_create_user_command("Format", function()
		conform.format({ async = true })
	end, { desc = "Format file asynchronously" })
	vim.keymap.set({ "n", "v" }, "<leader>cf", "<cmd>Format<cr>", { desc = "Format file" })
end

require("lib.config").run({
	plugins = { "https://github.com/stevearc/conform.nvim" },
	setup = setup_conform,
})
