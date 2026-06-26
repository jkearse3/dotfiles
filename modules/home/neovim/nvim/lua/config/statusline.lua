require("lib.config").run({
	plugins = { "https://github.com/echasnovski/mini.nvim" },
	setup = function()
		local statusline = require("mini.statusline")

		local function section_copilot(args)
			if statusline.is_truncated(args.trunc_width) then
				return ""
			end
			local ok, client = pcall(require, "copilot.client")
			if not ok then
				return ""
			end
			local is_enabled = ok and client.buf_is_attached(0)
			local auto_trigger = vim.b.copilot_suggestion_auto_trigger
			if auto_trigger == nil then
				auto_trigger = true
			end
			local check = is_enabled and "✓" or "✗"
			local mode = auto_trigger and "A" or "M"
			return "GHC" .. check .. mode
		end

		statusline.setup({
			content = {
				active = function()
					local mode, mode_hl = statusline.section_mode({ trunc_width = 120 })
					local filename = vim.bo.buftype == "terminal" and "%t"
						or statusline.section_filename({ trunc_width = 140 })
					local fileinfo = statusline.section_fileinfo({ trunc_width = 120 })
					local copilot = section_copilot({ trunc_width = 75 })
					return statusline.combine_groups({
						{ hl = mode_hl, strings = { string.sub(mode, 1, 1) } },
						{ hl = "MiniStatuslineFilename", strings = { filename } },
						"%<",
						"%=",
						{ hl = "MiniStatuslineFileinfo", strings = { fileinfo, copilot } },
					})
				end,
			},
		})
	end,
})
