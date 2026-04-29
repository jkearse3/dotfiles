require("lib.config").run({
	plugins = {
		"https://github.com/mfussenegger/nvim-dap",
		"https://github.com/leoluz/nvim-dap-go",
	},
	setup = function()
		require("dap-go").setup()

		local dap = require("dap")
		local widgets = require("dap.ui.widgets")

		vim.keymap.set(
			"n",
			"<leader>db",
			dap.toggle_breakpoint,
			{ desc = "DAP: Toggle breakpoint" }
		)
		vim.keymap.set("n", "<leader>dc", dap.continue, { desc = "DAP: Start/Continue" })
		vim.keymap.set("n", "<leader>dI", dap.step_into, { desc = "DAP: Step into" })
		vim.keymap.set("n", "<leader>dO", dap.step_out, { desc = "DAP: Step out" })
		vim.keymap.set("n", "<leader>do", dap.step_over, { desc = "DAP: Step over" })
		vim.keymap.set("n", "<leader>dd", dap.down, { desc = "DAP: Down" })
		vim.keymap.set("n", "<leader>du", dap.up, { desc = "DAP: Up" })
		vim.keymap.set("n", "<leader>dp", dap.pause, { desc = "DAP: Pause" })
		vim.keymap.set("n", "<leader>dt", dap.terminate, { desc = "DAP: Terminate" })
		vim.keymap.set("n", "<leader>dS", dap.session, { desc = "DAP: Session" })
		vim.keymap.set("n", "<leader>dr", dap.repl.toggle, { desc = "DAP: Toggle repl" })
		vim.keymap.set("n", "<leader>dl", dap.run_last, { desc = "DAP: Run last" })
		vim.keymap.set("n", "<leader>dC", dap.run_to_cursor, { desc = "DAP: Run to cursor" })

		vim.keymap.set("n", "<leader>dp", widgets.preview, { desc = "DAP: Preview" })

		local scopes_sidebar = widgets.sidebar(widgets.scopes, { height = 10 }, "belowright split")
		vim.keymap.set("n", "<leader>ds", scopes_sidebar.toggle, { desc = "DAP: Scopes" })

		local frames_sidebar = widgets.sidebar(widgets.frames, { height = 10 }, "belowright split")
		vim.keymap.set("n", "<leader>df", frames_sidebar.toggle, { desc = "DAP: Frames" })
	end,
})
