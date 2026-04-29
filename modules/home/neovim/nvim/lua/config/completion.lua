-- Core completion settings that work with or without a completion plugin.
vim.opt.completeopt = "popup,fuzzy,menu,menuone,noinsert,noselect"
vim.opt.shortmess:append("c") -- Suppress messages in the completion menu.

-- Popup menu navigation keybindings.
local function hijack_pum_key(target_key, input_key)
	return function()
		return vim.fn.pumvisible() == 1 and target_key or input_key
	end
end

vim.keymap.set(
	"i",
	"<C-h>",
	hijack_pum_key("<C-e>", "<C-h>"),
	{ desc = "PUM: Escape", expr = true, noremap = true }
)
vim.keymap.set(
	"i",
	"<C-j>",
	hijack_pum_key("<Down>", "<C-j>"),
	{ desc = "PUM: Down", expr = true, noremap = true }
)
vim.keymap.set(
	"i",
	"<C-k>",
	hijack_pum_key("<Up>", "<C-k>"),
	{ desc = "PUM: Up", expr = true, noremap = true }
)
vim.keymap.set(
	"i",
	"<C-l>",
	hijack_pum_key("<Enter>", "<C-l>"),
	{ desc = "PUM: Select", expr = true, noremap = true }
)

-- Fallback LSP completion when no completion plugin is loaded.
vim.api.nvim_create_autocmd("LspAttach", {
	callback = function(event)
		local function is_completion_plugin_enabled()
			local ok = pcall(require, "blink.cmp")
			return ok
		end

		if not is_completion_plugin_enabled() then
			local client = vim.lsp.get_client_by_id(event.data.client_id)
			if client and client:supports_method("textDocument/completion") then
				client.server_capabilities.completionProvider.triggerCharacters =
					vim.split(".abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789", "")

				vim.lsp.completion.enable(true, client.id, event.buf, { autotrigger = true })
			end
		end
	end,
})

-- Blink.cmp completion plugin.
require("lib.config").run({
	plugins = {
		{ src = "https://github.com/saghen/blink.cmp", version = vim.version.range("1.*") },
	},
	setup = function()
		require("blink.cmp").setup({
			keymap = {
				preset = "none",
				["<c-h>"] = {
					"hide",
					"fallback",
				},
				["<c-j>"] = {
					"select_next",
					"fallback",
				},
				["<c-k>"] = {
					"select_prev",
					"fallback",
				},
				["<c-l>"] = {
					"accept",
					"fallback",
				},
				["<tab>"] = {
					"snippet_forward",
					"fallback",
				},
				["<s-tab>"] = {
					"snippet_backward",
					"fallback",
				},
			},
			completion = {
				menu = {
					border = "rounded",
					draw = {
						components = {
							label = {
								width = {
									max = 120,
								},
							},
						},
					},
				},
				documentation = {
					auto_show = true,
					auto_show_delay_ms = 0,
					window = {
						border = "rounded",
					},
				},
				list = {
					selection = {
						auto_insert = false,
					},
				},
				accept = {
					auto_brackets = {
						enabled = false,
					},
				},
			},
			signature = {
				enabled = true,
				window = {
					border = "rounded",
					show_documentation = true,
				},
			},
			cmdline = {
				enabled = true,
				keymap = {
					preset = "inherit",
				},
				completion = {
					menu = {
						auto_show = true,
					},
					list = {
						selection = {
							auto_insert = false,
						},
					},
				},
			},
			sources = {
				default = {
					"lsp",
					"path",
					"snippets",
					"buffer",
				},
			},
		})
	end,
})
