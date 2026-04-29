require("lib.config").run({
	plugins = { "https://github.com/stevearc/conform.nvim" },
	setup = function()
		local conform = require("conform")

		--- Prepends treefmt to a list of fallback formatters with stop_after_first.
		--- @param ... string Fallback formatter names, tried in order if treefmt is unavailable.
		--- @return table conform.FormatterUnit[]
		local function with_treefmt(...)
			local t = { "treefmt", ... }
			t.stop_after_first = true
			return t
		end

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
			format_on_save = function(bufnr)
				local format_deny_list = {
					"html",
					"markdown",
					"sh",
				}
				local filetype = vim.bo[bufnr].filetype
				if vim.tbl_contains(format_deny_list, filetype) then
					return
				end

				return {
					timeout_ms = 5000,
					lsp_format = "fallback",
				}
			end,
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
			append_args = function(_, ctx)
				local cfg = vim.fs.find("kdlfmt.kdl", {
					path = ctx.filename,
					upward = true,
					stop = vim.loop.os_homedir(),
				})[1]
				if cfg then
					return { "--config", cfg }
				end

				return {}
			end,
		}

		vim.api.nvim_create_user_command("Format", function()
			conform.format({ async = true })
		end, { desc = "Format file asynchronously" })

		vim.keymap.set({ "n", "v" }, "<leader>cf", "<cmd>Format<cr>", { desc = "Format file" })
	end,
})
