-- Core completion settings that work with or without a completion plugin.
vim.opt.completeopt = "popup,fuzzy,menu,menuone,noinsert,noselect"
vim.opt.shortmess:append("c") -- Suppress messages in the completion menu.

-- Popup menu navigation keybindings.
---@param input_key string
---@param pum_key string
---@param description string
local function set_pum_keymap(input_key, pum_key, description)
	vim.keymap.set("i", input_key, function()
		return vim.fn.pumvisible() == 1 and pum_key or input_key
	end, { desc = description, expr = true, noremap = true })
end

set_pum_keymap("<C-h>", "<C-e>", "PUM: Escape")
set_pum_keymap("<C-j>", "<Down>", "PUM: Down")
set_pum_keymap("<C-k>", "<Up>", "PUM: Up")
set_pum_keymap("<C-l>", "<Enter>", "PUM: Select")

-- Fallback LSP completion when no completion plugin is loaded.
---@param event vim.api.keyset.create_autocmd.callback_args
local function enable_native_lsp_completion(event)
	local is_blink_cmp_loaded = pcall(require, "blink.cmp")
	if is_blink_cmp_loaded then
		return
	end

	local client = vim.lsp.get_client_by_id(event.data.client_id)
	if not client or not client:supports_method("textDocument/completion") then
		return
	end

	client.server_capabilities.completionProvider.triggerCharacters =
		vim.split(".abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789", "")
	vim.lsp.completion.enable(true, client.id, event.buf, { autotrigger = true })
end

vim.api.nvim_create_autocmd("LspAttach", {
	callback = enable_native_lsp_completion,
})

-- Blink.cmp completion plugin.
---@param action blink.cmp.KeymapCommand
---@return blink.cmp.KeymapCommand[]
local function action_with_fallback(action)
	return { action, "fallback" }
end

---@type blink.cmp.Config
local blink_options = {
	keymap = {
		preset = "none",
		["<c-h>"] = action_with_fallback("hide"),
		["<c-j>"] = action_with_fallback("select_next"),
		["<c-k>"] = action_with_fallback("select_prev"),
		["<c-l>"] = action_with_fallback("accept"),
		["<tab>"] = action_with_fallback("snippet_forward"),
		["<s-tab>"] = action_with_fallback("snippet_backward"),
	},
	completion = {
		menu = {
			border = "rounded",
			draw = { components = { label = { width = { max = 120 } } } },
		},
		documentation = {
			auto_show = true,
			auto_show_delay_ms = 0,
			window = { border = "rounded" },
		},
		list = { selection = { auto_insert = false } },
		accept = { auto_brackets = { enabled = false } },
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
		keymap = { preset = "inherit" },
		completion = {
			menu = { auto_show = true },
			list = { selection = { auto_insert = false } },
		},
	},
	sources = {
		default = { "lsp", "path", "snippets", "buffer" },
	},
}

require("lib.config").run({
	plugins = {
		{
			src = "https://github.com/saghen/blink.cmp",
			version = vim.version.range("1.*"),
		},
	},
	setup = function()
		---@type blink.cmp.API
		local blink = require("blink.cmp")
		blink.setup(blink_options)
	end,
})
