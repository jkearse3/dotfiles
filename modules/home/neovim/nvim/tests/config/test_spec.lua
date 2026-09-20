describe("test runner configuration", function()
	local globals, mappings, job, notifications, registers
	local root, filetype, cargo

	before_each(function()
		globals, mappings, notifications, registers = {}, {}, {}, {}
		root, filetype, cargo = "/workspace", "lua", ""
		job = nil

		local environment = setmetatable({
			vim = setmetatable({
				g = globals,
				bo = setmetatable({}, {
					__index = function(_, key)
						if key == "filetype" then
							return filetype
						end
						return vim.bo[key]
					end,
				}),
				fn = setmetatable({
					getcwd = function()
						return root
					end,
					findfile = function()
						return cargo
					end,
					setreg = function(register, value)
						registers[register] = value
					end,
					jobstart = function(command, options)
						job = {
							command = command,
							options = options,
						}
					end,
				}, { __index = vim.fn }),
				keymap = {
					set = function(_, key, action)
						mappings[key] = action
					end,
				},
				notify = function(message)
					table.insert(notifications, message)
				end,
			}, { __index = vim }),
			require = function(name)
				assert.are.equal("lib.config", name)
				return {
					run = function(spec)
						spec.setup()
					end,
				}
			end,
		}, { __index = _G })
		setfenv(assert(loadfile("lua/config/test.lua")), environment)()
	end)

	after_each(function()
		local bufnr = vim.fn.bufnr("[Test Output]")
		if bufnr ~= -1 then
			vim.api.nvim_buf_delete(bufnr, { force = true })
		end
		vim.cmd("only")
	end)

	it("appends both output streams and exit status to a reusable read-only split", function()
		globals["test#custom_strategies"].scratch("test-command")
		local bufnr = vim.fn.bufnr("[Test Output]")
		assert.are.equal("test-command", job.command)
		assert.is_true(job.options.stdout_buffered)
		assert.is_true(job.options.stderr_buffered)
		job.options.on_stdout(1, { "passed" })
		job.options.on_stderr(1, { "warning" })
		job.options.on_stdout(1, nil)
		job.options.on_stderr(1, {})
		job.options.on_exit(1, 2)
		assert.are.same({
			"Running: test-command",
			"---",
			"",
			"passed",
			"warning",
			"",
			"--- Test completed with exit code: 2 ---",
		}, vim.api.nvim_buf_get_lines(bufnr, 0, -1, false))
		assert.is_false(vim.bo[bufnr].modifiable)

		local window_count = #vim.api.nvim_list_wins()
		globals["test#custom_strategies"].scratch("next-command")
		assert.are.equal(bufnr, vim.fn.bufnr("[Test Output]"))
		assert.are.equal(window_count, #vim.api.nvim_list_wins())
		assert.are.same(
			{ "Running: next-command", "---", "" },
			vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
		)
	end)

	it("toggles the first output window without deleting its buffer", function()
		mappings["<leader>tot"]()
		assert.are.equal("No test buffer found. Run a test first.", notifications[1])
		globals["test#custom_strategies"].scratch("test-command")
		local bufnr = vim.fn.bufnr("[Test Output]")
		mappings["<leader>tot"]()
		assert.are.equal(0, #vim.fn.win_findbuf(bufnr))
		mappings["<leader>tot"]()
		assert.are.equal(1, #vim.fn.win_findbuf(bufnr))
	end)

	it("copies commands without starting a job", function()
		globals["test#custom_strategies"].copy("test-command")
		assert.are.equal("test-command", registers["+"])
		assert.is_nil(job)
	end)

	it("uses the working directory except for Rust's manifest lookup", function()
		assert.are.equal(root, globals["test#project_root"]())
		filetype, cargo = "rust", "/workspace/crate/Cargo.toml"
		assert.are.equal("/workspace/crate", globals["test#project_root"]())
		-- An absent manifest is still passed through fnamemodify.
		cargo = ""
		assert.are.equal(vim.fn.fnamemodify("", ":h"), globals["test#project_root"]())
	end)
end)
