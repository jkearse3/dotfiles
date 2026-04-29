local orig = vim.lsp.util.open_floating_preview
function vim.lsp.util.open_floating_preview(contents, syntax, opts, ...)
	opts = opts or {}
	opts.border = opts.border or "rounded"
	return orig(contents, syntax, opts, ...)
end

vim.lsp.enable({
	"basedpyright",
	"bashls",
	"buf_ls",
	"gopls",
	"jsonnet_ls",
	"lua_ls",
	"markdown_oxide",
	"nixd",
	"rust_analyzer",
	"ts_ls",
	"yamlls",
})

vim.api.nvim_create_autocmd("LspAttach", {
	callback = function(event)
		vim.keymap.set(
			"n",
			"gd",
			vim.lsp.buf.definition,
			{ buffer = event.buf, desc = "Go to definition" }
		) -- Use lsp instead of tag stack.
	end,
})

---@param ev vim.api.keyset.create_autocmd.callback_args
local function notify_lsp_progress(ev)
	local id = ev.data.client_id
	local key = "lsp:" .. id
	local kind = ev.data.params.value.kind

	if kind == "end" then
		vim.notify("", nil, { key = key })
		return
	end

	local val = ev.data.params.value
	local client = vim.lsp.get_client_by_id(id)
	local parts = {}
	if client then
		table.insert(parts, "[" .. client.name .. "]")
	end
	if val.title then
		table.insert(parts, val.title)
	end
	if val.message then
		table.insert(parts, val.message)
	end
	if val.percentage then
		table.insert(parts, val.percentage .. "%")
	end

	vim.notify(table.concat(parts, " "), vim.log.levels.INFO, { key = key })
end

vim.api.nvim_create_autocmd("LspProgress", {
	callback = notify_lsp_progress,
})
