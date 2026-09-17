--- Provides floating, stacked notifications and installs them as `vim.notify`.
--- Keyed notifications remain active for updates or explicit dismissal;
--- unkeyed notifications disappear automatically after four seconds.

---@class NotifyEntry
---@field key string
---@field msg string
---@field level integer
---@field timer? uv.uv_timer_t
---@field buf? integer
---@field win? integer

---@type NotifyEntry[]
local entries = {}

--- Finds an active notification by its stable key.
---@param key string
---@return integer|nil, NotifyEntry|nil
local function find_entry(key)
	for i, e in ipairs(entries) do
		if e.key == key then
			return i, e
		end
	end
end

--- Closes an entry's window and forgets its disposable buffer.
---@param entry NotifyEntry
local function close_entry_win(entry)
	if entry.win and vim.api.nvim_win_is_valid(entry.win) then
		vim.api.nvim_win_close(entry.win, true)
		entry.win = nil
	end
	entry.buf = nil
end

--- Stops and removes an active notification, if it exists.
---@param key string
local function remove_entry(key)
	local i, entry = find_entry(key)
	if not i or not entry then
		return
	end

	if entry.timer then
		entry.timer:stop()
	end
	close_entry_win(entry)
	table.remove(entries, i)
end

--- Returns the entry's buffer, creating a scratch buffer when needed.
---@param entry NotifyEntry
---@return integer
local function get_entry_buf(entry)
	if entry.buf and vim.api.nvim_buf_is_valid(entry.buf) then
		return entry.buf
	end
	entry.buf = vim.api.nvim_create_buf(false, true)
	vim.bo[entry.buf].bufhidden = "wipe"
	return entry.buf
end

--- Adds a word to the current line, moving overflow into completed lines.
--- Words wider than the limit are split into chunks that fit.
---@param lines string[]
---@param line string
---@param word string
---@param max_w integer
---@return string
local function append_wrapped_word(lines, line, word, max_w)
	local candidate = line == "" and word or (line .. " " .. word)
	if vim.fn.strdisplaywidth(candidate) <= max_w then
		return candidate
	end

	if line ~= "" then
		table.insert(lines, line)
	end

	-- Break single words that exceed max width.
	while vim.fn.strdisplaywidth(word) > max_w do
		local cut = max_w
		while vim.fn.strdisplaywidth(word:sub(1, cut)) > max_w do
			cut = cut - 1
		end
		table.insert(lines, word:sub(1, cut))
		word = word:sub(cut + 1)
	end

	return word
end

--- Wraps each paragraph into display lines no wider than the limit.
---@param text string
---@param max_w integer
---@return string[]
local function wrap_text(text, max_w)
	local lines = {}
	for _, paragraph in ipairs(vim.split(text, "\n", { plain = true })) do
		if vim.fn.strdisplaywidth(paragraph) <= max_w then
			table.insert(lines, paragraph)
		else
			local line = ""
			for word in paragraph:gmatch("%S+") do
				line = append_wrapped_word(lines, line, word, max_w)
			end
			if line ~= "" then
				table.insert(lines, line)
			end
		end
	end

	return lines
end

---@type table<integer, string>
local level_hl = {
	[vim.log.levels.ERROR] = "DiagnosticError",
	[vim.log.levels.WARN] = "DiagnosticWarn",
}

local MAX_WIDTH = 50

local ns = vim.api.nvim_create_namespace("notify")

--- Calculates the floating window dimensions for rendered lines.
---@param lines string[]
---@return integer, integer
local function get_content_size(lines)
	local width = 0
	for _, line in ipairs(lines) do
		width = math.max(width, vim.fn.strdisplaywidth(line))
	end

	return math.min(math.max(width, 1), MAX_WIDTH), #lines
end

--- Replaces a notification buffer's text and applies severity highlighting.
---@param buf integer
---@param lines string[]
---@param level integer
local function set_buffer_content(buf, lines, level)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)

	local hl = level_hl[level]
	if not hl then
		return
	end

	for i, line in ipairs(lines) do
		vim.api.nvim_buf_set_extmark(buf, ns, i - 1, 0, {
			end_col = #line,
			hl_group = hl,
		})
	end
end

--- Draws one notification at the requested position and returns its height.
---@param entry NotifyEntry
---@param row integer
---@param col integer
---@return integer
local function render_entry(entry, row, col)
	local lines = wrap_text(entry.msg, MAX_WIDTH)
	local width, height = get_content_size(lines)
	local win_opts = {
		relative = "editor",
		anchor = "SE",
		row = row,
		col = col,
		width = width,
		height = height,
		focusable = false,
		border = "rounded",
		style = "minimal",
	}

	local buf = get_entry_buf(entry)
	set_buffer_content(buf, lines, entry.level)

	if entry.win and vim.api.nvim_win_is_valid(entry.win) then
		vim.api.nvim_win_set_config(entry.win, win_opts)
		vim.api.nvim_win_set_buf(entry.win, buf)
	else
		win_opts.noautocmd = true
		entry.win = vim.api.nvim_open_win(buf, false, win_opts)
	end

	return height
end

--- Arranges all active notifications in a bottom-right stack.
local function render()
	-- Stack from bottom-right, newest entry at the bottom.
	local row = vim.o.lines - 2
	local col = vim.o.columns

	for i = #entries, 1, -1 do
		local height = render_entry(entries[i], row, col)
		row = row - height - 2
	end
end

--- Updates a keyed notification or adds it when it is not already active.
---@param key string
---@param msg string
---@param level integer
local function upsert_keyed_entry(key, msg, level)
	local _, entry = find_entry(key)
	if entry then
		entry.msg = msg
		entry.level = level
		return
	end

	table.insert(entries, {
		key = key,
		msg = msg,
		level = level,
	})
end

--- Adds an unkeyed notification that removes itself after four seconds.
---@param msg string
---@param level integer
local function add_transient_entry(msg, level)
	local key = "transient:" .. tostring(vim.uv.hrtime())
	local entry = {
		key = key,
		msg = msg,
		level = level,
	}
	entry.timer = vim.defer_fn(function()
		remove_entry(key)
		render()
	end, 4000)

	table.insert(entries, entry)
end

--- Displays, updates, or dismisses a notification.
--- A key keeps a notification active for later updates; an empty keyed
--- message dismisses it.
---@param msg string
---@param level integer|nil
---@param opts table|nil
local function notify(msg, level, opts)
	opts = opts or {}
	level = level or vim.log.levels.INFO
	local key = opts.key

	-- Keyed dismiss: empty msg + key = remove entry.
	if key and (msg == nil or msg == "") then
		remove_entry(key)
		render()
		return
	end

	if key then
		upsert_keyed_entry(key, msg, level)
	else
		add_transient_entry(msg, level)
	end

	render()
end

vim.notify = notify
