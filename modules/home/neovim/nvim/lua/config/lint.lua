require("lib.config").run({
	plugins = { "https://github.com/mfussenegger/nvim-lint" },
	setup = function()
		local lint = require("lint")

		-- golangci-lint: Pass directory instead of file as the lint target.
		-- Linting a single file fails when it references symbols from other
		-- files in the same Go package.
		local golangcilint_args = lint.linters.golangcilint.args
		local golangcilint_args_len = #golangcilint_args
		golangcilint_args[golangcilint_args_len] = function()
			return vim.fn.fnamemodify(vim.api.nvim_buf_get_name(0), ":h")
		end

		lint.linters_by_ft = {
			json = { "jq" },
			go = { "golangcilint" },
			sh = { "shellcheck" },
			bash = { "shellcheck" },
			zsh = { "shellcheck" },
			fish = { "fish" },
			proto = { "buf_lint" },
			javascript = { "eslint" },
			javascriptreact = { "eslint" },
			typescript = { "eslint" },
			typescriptreact = { "eslint" },
			python = { "ruff" },
		}

		vim.api.nvim_create_autocmd({ "BufEnter", "BufWritePost", "InsertLeave" }, {
			callback = function()
				local ft = vim.bo.filetype
				if
					ft == "javascript"
					or ft == "javascriptreact"
					or ft == "typescript"
					or ft == "typescriptreact"
				then
					-- Set ESLint's cwd to the project root so relative tsconfig
					-- paths resolve when Neovim's cwd is a parent repo root.
					lint.linters.eslint.cwd = vim.fs.root(0, {
						"eslint.config.mjs",
						"eslint.config.js",
						"eslint.config.cjs",
						".eslintrc.js",
						".eslintrc.json",
					})
				end
				lint.try_lint()
			end,
		})
	end,
})
