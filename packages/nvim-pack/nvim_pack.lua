local request_path = assert(vim.env.NVIM_PACK_REQUEST, "NVIM_PACK_REQUEST is not set")
local response_path = assert(vim.env.NVIM_PACK_RESPONSE, "NVIM_PACK_RESPONSE is not set")

---@param path string
---@return any
local function read_json(path)
	local lines = vim.fn.readfile(path, "b")
	return vim.json.decode(table.concat(lines, "\n"))
end

---@param path string
---@param value any
local function write_json(path, value)
	local status = vim.fn.writefile({ vim.json.encode(value) }, path, "b")
	if status ~= 0 then
		error("could not write nvim-pack response")
	end
end

---@param values string[]
---@return string[]
local function sorted(values)
	table.sort(values)
	return values
end

---@return string[]
local function active_plugin_names()
	local names = {}
	for _, plugin in ipairs(vim.pack.get(nil, { info = false })) do
		if plugin.active then
			names[#names + 1] = plugin.spec.name
		end
	end
	return sorted(names)
end

---@param requested string[]
---@return string[] selected
---@return string[] selection_errors
local function select_active_plugins(requested)
	local active = active_plugin_names()
	if #requested == 0 then
		return active, {}
	end

	local active_set = {}
	for _, name in ipairs(active) do
		active_set[name] = true
	end

	local selected, selection_errors = {}, {}
	for _, name in ipairs(requested) do
		if active_set[name] then
			selected[#selected + 1] = name
		else
			selection_errors[#selection_errors + 1] = name
		end
	end
	return selected, selection_errors
end

---@param lines string[]
---@return string[] details
---@return string[] updates
---@return string[] errors
---@return table<string, string> targets
local function parse_confirmation(lines)
	local details, updates, errors, targets = {}, {}, {}, {}
	local group, current_update = nil, nil
	local in_updates = false

	for _, line in ipairs(lines) do
		local next_group = line:match("^# (%S+)")
		if next_group then
			if in_updates and next_group ~= "Update" then
				in_updates = false
			end
			group = next_group
			in_updates = group == "Update"
		else
			if in_updates then
				details[#details + 1] = line
			end
		end

		local name = line:match("^## (.+)$")
		if name then
			name = name:gsub(" %(not active%)$", "")
			current_update = group == "Update" and name or nil
			if group == "Update" then
				updates[#updates + 1] = name
			elseif group == "Error" then
				errors[#errors + 1] = name
			end
		end

		local target = line:match("^Revision after:%s+(%x+)")
		if target and current_update then
			targets[current_update] = target
		end
	end

	while details[1] == "" do
		table.remove(details, 1)
	end
	while details[#details] == "" do
		table.remove(details)
	end
	return details, updates, errors, targets
end

---@param selected string[]
---@param offline boolean
---@return table
local function inspect_updates(selected, offline)
	if offline then
		vim.pack.update(selected, { offline = true })
	else
		vim.pack.update(selected)
	end

	local bufnr = vim.api.nvim_get_current_buf()
	if vim.bo[bufnr].filetype ~= "nvim-pack" then
		error("vim.pack.update did not create its confirmation buffer")
	end
	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	local details, updates, errors, targets = parse_confirmation(lines)
	return {
		bufnr = bufnr,
		details = details,
		errors = errors,
		targets = targets,
		updates = updates,
	}
end

---@param selected string[]
---@param lock_path string
---@return table
local function snapshot_check_state(selected, lock_path)
	local lock_existed = vim.fn.filereadable(lock_path) == 1
	local lock_before = lock_existed and vim.fn.readfile(lock_path, "b") or {}
	local origins, errors = {}, {}

	for _, plugin in ipairs(vim.pack.get(selected, { info = false })) do
		local result = vim.system({ "git", "remote", "get-url", "origin" }, {
			cwd = plugin.path,
			text = true,
		}):wait()
		if result.code == 0 then
			origins[plugin.spec.name] = {
				path = plugin.path,
				url = vim.trim(result.stdout),
			}
		else
			errors[#errors + 1] = plugin.spec.name
		end
	end

	return {
		errors = errors,
		lock_before = lock_before,
		lock_existed = lock_existed,
		origins = origins,
	}
end

---@param snapshot table
---@param lock_path string
local function restore_check_state(snapshot, lock_path)
	for name, origin in pairs(snapshot.origins) do
		local result = vim.system({ "git", "remote", "set-url", "origin", origin.url }, {
			cwd = origin.path,
			text = true,
		}):wait()
		if result.code ~= 0 then
			error("could not restore origin for " .. name .. ": " .. vim.trim(result.stderr))
		end
	end

	local lock_exists_after = vim.fn.filereadable(lock_path) == 1
	local lock_after = lock_exists_after and vim.fn.readfile(lock_path, "b") or {}
	if snapshot.lock_existed == lock_exists_after and vim.deep_equal(snapshot.lock_before, lock_after) then
		return
	end

	local status
	if snapshot.lock_existed then
		status = vim.fn.writefile(snapshot.lock_before, lock_path, "b")
	else
		status = vim.fn.delete(lock_path)
	end
	if status ~= 0 then
		error("could not restore nvim-pack-lock.json after check")
	end
end

---@param selected string[]
---@param report table
---@param lock_path string
---@return string[]
local function verify_applied_updates(selected, report, lock_path)
	local installed = {}
	for _, plugin in ipairs(vim.pack.get(selected, { info = false })) do
		installed[plugin.spec.name] = plugin.rev
	end

	local lock_ok, lock_lines = pcall(vim.fn.readfile, lock_path)
	local json_ok, lock = pcall(vim.json.decode, lock_ok and table.concat(lock_lines, "\n") or "")
	local apply_errors = {}
	for _, name in ipairs(report.updates) do
		local entry = json_ok and lock.plugins and lock.plugins[name] or nil
		local target = report.targets[name]
		if not target or installed[name] ~= target or not entry or entry.rev ~= target then
			apply_errors[#apply_errors + 1] = name
		end
	end
	return apply_errors
end

---@param selected string[]
---@param lock_path string
---@return table
local function check_updates(selected, lock_path)
	local snapshot = snapshot_check_state(selected, lock_path)
	if #snapshot.errors > 0 then
		return { errors = snapshot.errors }
	end

	local check_ok, report = xpcall(function()
		return inspect_updates(selected, false)
	end, debug.traceback)
	local restore_ok, restore_error = xpcall(function()
		restore_check_state(snapshot, lock_path)
	end, debug.traceback)

	if not check_ok then
		local suffix = restore_ok and "" or ("\nCleanup also failed: " .. restore_error)
		error(report .. suffix)
	end
	if not restore_ok then
		error(restore_error)
	end
	return report
end

---@param selected string[]
---@param lock_path string
---@param offline boolean
---@return table
local function apply_updates(selected, lock_path, offline)
	local report = inspect_updates(selected, offline)
	if #report.errors == 0 and #report.updates > 0 then
		vim.api.nvim_buf_call(report.bufnr, function()
			vim.cmd.write()
		end)
		report.apply_errors = verify_applied_updates(selected, report, lock_path)
	end
	return report
end

---@param request table
---@return table
local function update(request)
	local selected, selection_errors = select_active_plugins(request.plugins or {})
	local empty_report = {
		apply_errors = {},
		details = {},
		errors = {},
		selection_errors = selection_errors,
		updates = {},
	}
	if #selection_errors > 0 or #selected == 0 then
		return empty_report
	end

	local lock_path = vim.fs.joinpath(vim.fn.stdpath("config"), "nvim-pack-lock.json")
	local report
	if request.apply then
		report = apply_updates(selected, lock_path, request.offline == true)
	else
		report = check_updates(selected, lock_path)
	end
	return {
		apply_errors = report.apply_errors or {},
		details = report.details or {},
		errors = report.errors or {},
		selection_errors = selection_errors,
		updates = report.updates or {},
	}
end

---@param dry_run boolean
---@return table
local function prune(dry_run)
	local orphans = {}
	for _, plugin in ipairs(vim.pack.get(nil, { info = false })) do
		if plugin.active == false then
			orphans[#orphans + 1] = plugin.spec.name
		end
	end
	sorted(orphans)
	if not dry_run and #orphans > 0 then
		vim.pack.del(orphans)
	end
	return { names = orphans }
end

---@param request table
---@return table
local function dispatch(request)
	if request.command == "list" then
		return { names = active_plugin_names() }
	end
	if request.command == "prune" then
		return prune(request.dry_run == true)
	end
	if request.command == "update" then
		return update(request)
	end
	error("unknown nvim-pack command: " .. tostring(request.command))
end

local request = read_json(request_path)
local ok, response = xpcall(dispatch, debug.traceback, request)
if not ok then
	response = { fatal_error = response }
end
write_json(response_path, response)
