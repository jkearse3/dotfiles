-- Copilot
require("lib.config").run({
	plugins = { "https://github.com/zbirenbaum/copilot.lua" },
	setup = function()
		---@class copilot_config
		require("copilot").setup({
			filetypes = {
				sh = function()
					if string.match(vim.fs.basename(vim.api.nvim_buf_get_name(0)), "^%.env.*") then
						return false
					end
					if string.match(vim.fs.basename(vim.api.nvim_buf_get_name(0)), ".envrc") then
						return false
					end
					return true
				end,
			},
			server = {
				type = "binary",
				custom_server_filepath = "copilot-language-server",
			},
			suggestion = {
				enabled = true,
				auto_trigger = true,
				hide_during_completion = false,
				accept = false,
			},
		})

		local suggestion = require("copilot.suggestion")

		vim.keymap.set("n", "<leader>cst", function()
			suggestion.toggle_auto_trigger()
			vim.schedule(function()
				vim.cmd("redrawstatus")
			end)
		end, { desc = "Copilot: Toggle suggestions" })

		local function handle_when_visible(lhs, action)
			local function pass_through_keymap(mapping)
				vim.api.nvim_feedkeys(
					vim.api.nvim_replace_termcodes(mapping, true, false, true),
					"n",
					false
				)
			end

			return function()
				if not suggestion.is_visible() then
					pass_through_keymap(lhs)
					return
				end
				action()
			end
		end

		vim.keymap.set(
			"i",
			"<c-g><c-l>",
			handle_when_visible("<c-g><c-l>", suggestion.accept_line),
			{ desc = "Copilot: Accept line" }
		)
		vim.keymap.set(
			"i",
			"<c-g><c-h>",
			handle_when_visible("<c-g><c-h>", function()
				suggestion.dismiss()
			end),
			{ desc = "Copilot: Dismiss suggestion" }
		)
		vim.keymap.set(
			"i",
			"<c-g><c-j>",
			handle_when_visible("<c-g><c-j>", function()
				suggestion.next()
			end),
			{ desc = "Copilot: Next suggestion" }
		)
		vim.keymap.set(
			"i",
			"<c-g><c-k>",
			handle_when_visible("<c-g><c-k>", function()
				suggestion.prev()
			end),
			{ desc = "Copilot: Previous suggestion" }
		)
	end,
})

-- Claude Code
require("lib.config").run({
	plugins = { "https://github.com/coder/claudecode.nvim" },
	setup = function()
		require("claudecode").setup({
			terminal = {
				provider = "native",
			},
		})
	end,
})
