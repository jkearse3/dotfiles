-- Helper to encode a string for use in a URI (for session file naming).
local function uri_encode(str)
	local substituted, _ = str:gsub("([^%w%-%.%_%~])", function(char)
		return string.format("%%%02X", char:byte())
	end)
	return substituted
end

-- Helper to escape % for vim.cmd.
local function escape_string_for_vim_cmd(str)
	local substituted, _ = str:gsub("%%", "\\%%")
	return substituted
end

-- Use current working directory for session file naming.
local cwd = vim.fn.getcwd()
local workspaces_dir = vim.fn.stdpath("state") .. "/internal/workspaces/"
local dir_uri_encoded = uri_encode(cwd)
vim.opt.shadafile = workspaces_dir .. dir_uri_encoded .. ".shada"
local session_path = workspaces_dir .. dir_uri_encoded .. ".session.vim"

-- Save session (including DAP breakpoints).
local function save_session()
	local success, result = pcall(function()
		local dap_breakpoints = require("dap.breakpoints")
		local saved_breakpoints = {}
		local breakpoints_by_buf = dap_breakpoints.get()
		for buf, breakpoints in pairs(breakpoints_by_buf) do
			saved_breakpoints[tostring(buf)] = breakpoints
		end
		local saved_breakpoints_json = vim.fn.json_encode(saved_breakpoints)
		vim.g.DAP_BREAKPOINTS_JSON = saved_breakpoints_json
	end)
	if not success then
		vim.notify("Failed to save dap breakpoints: " .. result, vim.log.levels.ERROR)
	end

	local escaped_session_path = escape_string_for_vim_cmd(session_path)
	local ok, err = pcall(function()
		vim.cmd("mksession! " .. escaped_session_path)
	end)
	if not ok then
		vim.notify("Failed to save session: " .. err, vim.log.levels.ERROR)
		return
	end
	vim.notify("Session saved: " .. session_path, vim.log.levels.INFO)
end

-- Load session (including DAP breakpoints).
local function load_session()
	if vim.fn.filereadable(session_path) == 0 then
		vim.notify("Session file not found: " .. session_path, vim.log.levels.ERROR)
		return
	end
	local escaped_session_path = escape_string_for_vim_cmd(session_path)
	local ok, err = pcall(function()
		vim.cmd("source " .. escaped_session_path)
	end)
	if not ok then
		vim.notify("Failed to load session: " .. err, vim.log.levels.ERROR)
		return
	end
	local success, result = pcall(function()
		local dap_breakpoints = require("dap.breakpoints")
		local breakpoints_json = vim.g.DAP_BREAKPOINTS_JSON or ""
		if breakpoints_json ~= "" then
			local breakpoints_by_buf = vim.fn.json_decode(breakpoints_json)
			for buf, breakpoints in pairs(breakpoints_by_buf) do
				for _, breakpoint in pairs(breakpoints) do
					local line = breakpoint.line
					local opts = {
						condition = breakpoint.condition,
						log_message = breakpoint.logMessage,
						hit_condition = breakpoint.hitCondition,
					}
					dap_breakpoints.set(opts, tonumber(buf), line)
				end
			end
		end
	end)
	if not success then
		vim.notify("Failed to load dap breakpoints: " .. result, vim.log.levels.ERROR)
	end
	vim.notify("Session loaded: " .. session_path, vim.log.levels.INFO)
end

-- User commands for explicit session management.
vim.api.nvim_create_user_command(
	"WorkspaceSaveSession",
	save_session,
	{ desc = "Save workspace session" }
)
vim.api.nvim_create_user_command(
	"WorkspaceLoadSession",
	load_session,
	{ desc = "Load workspace session" }
)

-- Keymaps for explicit session management.
vim.keymap.set("n", "<leader>ws", save_session, { desc = "Save workspace session" })
vim.keymap.set("n", "<leader>wl", load_session, { desc = "Load workspace session" })
