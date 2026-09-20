describe("workspace sessions", function()
	local commands, mappings, executed, notifications, globals, restored, options
	local readable, command_error, breakpoint_error
	local session_path = "/state/internal/workspaces/%2Fworkspace%20name.session.vim"

	before_each(function()
		commands, mappings, executed, notifications, globals, restored, options =
			{}, {}, {}, {}, {}, {}, {}
		readable, command_error, breakpoint_error = 1, nil, nil
		local dap_breakpoints = {
			get = function()
				if breakpoint_error then
					error(breakpoint_error)
				end
				return {
					[7] = {
						{
							line = 12,
							condition = "ready",
							logMessage = "hit",
							hitCondition = "3",
						},
					},
				}
			end,
			set = function(opts, buf, line)
				if breakpoint_error then
					error(breakpoint_error)
				end
				table.insert(restored, {
					opts = opts,
					buf = buf,
					line = line,
				})
			end,
		}
		local environment = setmetatable({
			vim = setmetatable({
				g = globals,
				opt = options,
				fn = setmetatable({
					getcwd = function()
						return "/workspace name"
					end,
					stdpath = function()
						return "/state"
					end,
					filereadable = function(path)
						assert.are.equal(session_path, path)
						return readable
					end,
				}, { __index = vim.fn }),
				api = {
					nvim_create_user_command = function(name, callback)
						commands[name] = callback
					end,
				},
				keymap = {
					set = function(_, key, callback)
						mappings[key] = callback
					end,
				},
				cmd = function(command)
					table.insert(executed, command)
					if command_error then
						error(command_error)
					end
				end,
				notify = function(message)
					table.insert(notifications, message)
				end,
			}, { __index = vim }),
			require = function(name)
				assert.are.equal("dap.breakpoints", name)
				return dap_breakpoints
			end,
		}, { __index = _G })
		setfenv(assert(loadfile("lua/config/workspace.lua")), environment)()
	end)

	it("encodes workspace filenames and round-trips breakpoint options", function()
		assert.are.equal("/state/internal/workspaces/%2Fworkspace%20name.shada", options.shadafile)
		assert.are.equal(commands.WorkspaceSaveSession, mappings["<leader>ws"])
		assert.are.equal(commands.WorkspaceLoadSession, mappings["<leader>wl"])
		commands.WorkspaceSaveSession()
		assert.are.equal(
			"mksession! /state/internal/workspaces/\\%2Fworkspace\\%20name.session.vim",
			executed[1]
		)
		assert.are.equal(12, vim.fn.json_decode(globals.DAP_BREAKPOINTS_JSON)["7"][1].line)
		commands.WorkspaceLoadSession()
		assert.are.equal(
			"source /state/internal/workspaces/\\%2Fworkspace\\%20name.session.vim",
			executed[2]
		)
		assert.are.same({
			{
				opts = {
					condition = "ready",
					log_message = "hit",
					hit_condition = "3",
				},
				buf = 7,
				line = 12,
			},
		}, restored)
	end)

	it("still saves the session when breakpoint serialization fails", function()
		breakpoint_error = "breakpoints unavailable"
		commands.WorkspaceSaveSession()
		assert.are.equal(1, #executed)
		assert.matches("Failed to save dap breakpoints:", notifications[1], 1, true)
		assert.are.equal("Session saved: " .. session_path, notifications[2])
	end)

	it("does not source a missing session", function()
		readable = 0
		commands.WorkspaceLoadSession()
		assert.are.same({}, executed)
		assert.are.equal("Session file not found: " .. session_path, notifications[1])
	end)

	it("stops before restoring breakpoints if sourcing fails", function()
		command_error = "source failed"
		globals.DAP_BREAKPOINTS_JSON = '{"7":[{"line":12}]}'
		commands.WorkspaceLoadSession()
		assert.are.same({}, restored)
		assert.are.equal(1, #notifications)
		assert.matches("Failed to load session:", notifications[1], 1, true)
	end)

	it("accepts absent breakpoint state after loading", function()
		commands.WorkspaceLoadSession()
		assert.are.same({}, restored)
		assert.are.same({ "Session loaded: " .. session_path }, notifications)
	end)

	it("reports invalid breakpoint state without failing the loaded session", function()
		globals.DAP_BREAKPOINTS_JSON = "invalid json"
		commands.WorkspaceLoadSession()
		assert.matches("Failed to load dap breakpoints:", notifications[1], 1, true)
		assert.are.equal("Session loaded: " .. session_path, notifications[2])
	end)
end)
