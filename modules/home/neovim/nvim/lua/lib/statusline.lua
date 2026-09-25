--- Renders the global statusline: mode name, file name, and file details.
---@class lib.statusline
local M = {}

--- Global 'statusline' value. `%{%...%}` evaluates in the window being drawn, so
--- window and buffer lookups inside `render()` refer to that window.
M.option = "%{%v:lua.require'lib.statusline'.render()%}"

--- Window widths below which sections switch to their short form.
local filename_full_path_width = 140
local fileinfo_details_width = 120

local CTRL_S = vim.api.nvim_replace_termcodes("<C-S>", true, true, true)
local CTRL_V = vim.api.nvim_replace_termcodes("<C-V>", true, true, true)

---@class lib.statusline.ModeSection
---@field name string
---@field highlight string

--- Mode sections keyed by the single-character `mode()` result.
---@type table<string, lib.statusline.ModeSection>
-- stylua: ignore
local mode_sections = {
	n        = { name = "NORMAL",   highlight = "StatusLineModeNormal" },
	v        = { name = "VISUAL",   highlight = "StatusLineModeVisual" },
	V        = { name = "V-LINE",   highlight = "StatusLineModeVisual" },
	[CTRL_V] = { name = "V-BLOCK",  highlight = "StatusLineModeVisual" },
	s        = { name = "SELECT",   highlight = "StatusLineModeVisual" },
	S        = { name = "S-LINE",   highlight = "StatusLineModeVisual" },
	[CTRL_S] = { name = "S-BLOCK",  highlight = "StatusLineModeVisual" },
	i        = { name = "INSERT",   highlight = "StatusLineModeInsert" },
	R        = { name = "REPLACE",  highlight = "StatusLineModeReplace" },
	c        = { name = "COMMAND",  highlight = "StatusLineModeCommand" },
	r        = { name = "PROMPT",   highlight = "StatusLineModeOther" },
	["!"]    = { name = "SHELL",    highlight = "StatusLineModeOther" },
	t        = { name = "TERMINAL", highlight = "StatusLineModeOther" },
}

---@type lib.statusline.ModeSection
local unknown_mode_section = {
	name = "UNKNOWN",
	highlight = "StatusLineModeOther",
}

--- Width the statusline spans: the editor for a global statusline, otherwise
--- the window being drawn.
---@return integer
local function statusline_width()
	if vim.o.laststatus == 3 then
		return vim.o.columns
	end
	return vim.api.nvim_win_get_width(0)
end

--- Pads `text` with one space on each side under `highlight`; empty text
--- renders nothing.
---@param highlight string
---@param text string
---@return string
local function section(highlight, text)
	if text == "" then
		return ""
	end
	return string.format("%%#%s# %s ", highlight, text)
end

---@return string
local function filename_text()
	if vim.bo.buftype == "terminal" then
		return "%t"
	end
	if statusline_width() < filename_full_path_width then
		return "%f%m%r"
	end
	return "%F%m%r"
end

--- Size of the buffer's current text, not its saved file.
---@return string
local function buffer_size_text()
	local size = math.max(vim.fn.line2byte(vim.fn.line("$") + 1) - 1, 0)
	if size < 1024 then
		return string.format("%dB", size)
	elseif size < 1048576 then
		return string.format("%.2fKiB", size / 1024)
	end
	return string.format("%.2fMiB", size / 1048576)
end

--- Filetype, plus encoding, line format, and size for normal buffers in wide
--- windows.
---@return string
local function fileinfo_text()
	local filetype = vim.bo.filetype
	if statusline_width() < fileinfo_details_width or vim.bo.buftype ~= "" then
		return filetype
	end

	local encoding = vim.bo.fileencoding ~= "" and vim.bo.fileencoding or vim.o.encoding
	local details = string.format("%s[%s] %s", encoding, vim.bo.fileformat, buffer_size_text())
	if filetype == "" then
		return details
	end
	return filetype .. " " .. details
end

--- Installs the statusline globally, turns off 'showmode', and keeps its
--- highlights in sync with the colorscheme. Window-local 'statusline' values
--- still take precedence.
function M.setup()
	vim.go.statusline = M.option
	-- The mode section replaces the command-line "-- INSERT --" indicator.
	vim.o.showmode = false
	-- Keep quickfix windows on this statusline instead of the qf ftplugin's.
	vim.g.qf_disable_statusline = 1

	M.set_highlights()
	vim.api.nvim_create_autocmd("ColorScheme", {
		group = vim.api.nvim_create_augroup("lib.statusline", { clear = true }),
		callback = M.set_highlights,
		desc = "Derive statusline highlights from the colorscheme",
	})
end

--- Returns the statusline for the window being drawn: the full layout for the
--- current window (or every window with a global statusline), and the full file
--- path for inactive windows.
---@return string
function M.render()
	local is_current = vim.api.nvim_get_current_win() == tonumber(vim.g.actual_curwin)
	if not is_current and vim.o.laststatus ~= 3 then
		return "%#StatusLineNC#%F%="
	end

	local mode = mode_sections[vim.fn.mode()] or unknown_mode_section
	return table.concat({
		section(mode.highlight, mode.name),
		section("StatusLineFilename", filename_text()),
		"%<%=",
		section("StatusLineFileinfo", fileinfo_text()),
	})
end

---@param name string
---@param attribute "fg"|"bg"
---@return integer|nil
local function highlight_color(name, attribute)
	return vim.api.nvim_get_hl(0, { name = name, link = false })[attribute]
end

--- Defines the statusline highlight groups from the active colorscheme's
--- syntax, diagnostic, and UI colors so they follow any colorscheme. Missing
--- source colors leave the corresponding attribute unset.
function M.set_highlights()
	local mode_foreground = highlight_color("Normal", "bg")
	local mode_backgrounds = {
		StatusLineModeNormal = highlight_color("Function", "fg"),
		StatusLineModeInsert = highlight_color("String", "fg"),
		StatusLineModeVisual = highlight_color("Statement", "fg"),
		StatusLineModeReplace = highlight_color("DiagnosticError", "fg"),
		StatusLineModeCommand = highlight_color("DiagnosticWarn", "fg"),
		StatusLineModeOther = highlight_color("DiagnosticHint", "fg"),
	}
	for name, background in pairs(mode_backgrounds) do
		vim.api.nvim_set_hl(0, name, {
			fg = mode_foreground,
			bg = background,
			bold = true,
		})
	end

	local file_foreground = highlight_color("StatusLine", "fg")
	vim.api.nvim_set_hl(0, "StatusLineFilename", {
		fg = file_foreground,
		bg = highlight_color("CursorLine", "bg"),
	})
	vim.api.nvim_set_hl(0, "StatusLineFileinfo", {
		fg = file_foreground,
		bg = highlight_color("Visual", "bg"),
	})
end

return M
