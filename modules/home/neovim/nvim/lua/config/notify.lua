---@class NotifyEntry
---@field key string
---@field msg string
---@field level integer
---@field timer? uv.uv_timer_t
---@field buf? integer
---@field win? integer

---@type NotifyEntry[]
local entries = {}

---@param key string
---@return integer|nil, NotifyEntry|nil
local function find_entry(key)
	for i, e in ipairs(entries) do
		if e.key == key then
			return i, e
		end
	end
end

---@param entry NotifyEntry
local function close_entry_win(entry)
	if entry.win and vim.api.nvim_win_is_valid(entry.win) then
		vim.api.nvim_win_close(entry.win, true)
		entry.win = nil
	end
	entry.buf = nil
end

---@param key string
local function remove_entry(key)
	local i = find_entry(key)
	if i then
		local e = entries[i]
		if e.timer then
			e.timer:stop()
		end
		close_entry_win(e)
		table.remove(entries, i)
	end
end

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

---@param text string
---@param max_w integer
---@return string[]
local function wrap_text(text, max_w)
	local result = {}
	for _, paragraph in ipairs(vim.split(text, "\n", { plain = true })) do
		if vim.fn.strdisplaywidth(paragraph) <= max_w then
			table.insert(result, paragraph)
		else
			local line = ""
			for word in paragraph:gmatch("%S+") do
				local candidate = line == "" and word or (line .. " " .. word)
				if vim.fn.strdisplaywidth(candidate) > max_w then
					if line ~= "" then
						table.insert(result, line)
					end
					-- Break single words that exceed max width.
					while vim.fn.strdisplaywidth(word) > max_w do
						local cut = max_w
						while vim.fn.strdisplaywidth(word:sub(1, cut)) > max_w do
							cut = cut - 1
						end
						table.insert(result, word:sub(1, cut))
						word = word:sub(cut + 1)
					end
					line = word
				else
					line = candidate
				end
			end
			if line ~= "" then
				table.insert(result, line)
			end
		end
	end
	return result
end

---@type table<integer, string>
local level_hl = {
	[vim.log.levels.ERROR] = "DiagnosticError",
	[vim.log.levels.WARN] = "DiagnosticWarn",
}

local MAX_WIDTH = 50

local ns = vim.api.nvim_create_namespace("notify")

local function render()
	if #entries == 0 then
		return
	end

	-- Stack from bottom-right, newest entry at the bottom.
	local row = vim.o.lines - 2
	local col = vim.o.columns

	for i = #entries, 1, -1 do
		local e = entries[i]
		local lines = wrap_text(e.msg, MAX_WIDTH)

		local width = 0
		for _, line in ipairs(lines) do
			width = math.max(width, vim.fn.strdisplaywidth(line))
		end
		width = math.min(math.max(width, 1), MAX_WIDTH)
		local height = #lines

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

		local b = get_entry_buf(e)
		vim.api.nvim_buf_set_lines(b, 0, -1, false, lines)
		vim.api.nvim_buf_clear_namespace(b, ns, 0, -1)

		local hl = level_hl[e.level]
		if hl then
			for j = 1, #lines do
				vim.api.nvim_buf_set_extmark(
					b,
					ns,
					j - 1,
					0,
					{ end_col = #lines[j], hl_group = hl }
				)
			end
		end

		if e.win and vim.api.nvim_win_is_valid(e.win) then
			vim.api.nvim_win_set_config(e.win, win_opts)
			vim.api.nvim_win_set_buf(e.win, b)
		else
			win_opts.noautocmd = true
			e.win = vim.api.nvim_open_win(b, false, win_opts)
		end

		-- Move row up: content height + 2 for top/bottom border.
		row = row - height - 2
	end
end

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
		local _, existing = find_entry(key)
		if existing then
			existing.msg = msg
			existing.level = level
		else
			table.insert(entries, { key = key, msg = msg, level = level })
		end
	else
		-- Transient: generate unique key, auto-dismiss after 4s.
		local tkey = "transient:" .. tostring(vim.uv.hrtime())
		local entry = { key = tkey, msg = msg, level = level }
		entry.timer = vim.defer_fn(function()
			remove_entry(tkey)
			render()
		end, 4000)
		table.insert(entries, entry)
	end

	render()
end

vim.notify = notify
