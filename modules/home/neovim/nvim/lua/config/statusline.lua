require("lib.config").run({
	plugins = { "https://github.com/echasnovski/mini.nvim" },
	setup = function()
		local statusline = require("mini.statusline")

		statusline.setup({
			content = {
				active = function()
					local mode, mode_hl = statusline.section_mode({ trunc_width = 120 })
					local filename = vim.bo.buftype == "terminal" and "%t"
						or statusline.section_filename({ trunc_width = 140 })
					local fileinfo = statusline.section_fileinfo({ trunc_width = 120 })
					return statusline.combine_groups({
						{ hl = mode_hl, strings = { string.sub(mode, 1, 1) } },
						{ hl = "MiniStatuslineFilename", strings = { filename } },
						"%<",
						"%=",
						{ hl = "MiniStatuslineFileinfo", strings = { fileinfo } },
					})
				end,
			},
		})
	end,
})
