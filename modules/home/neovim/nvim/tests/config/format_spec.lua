describe("formatter configuration", function()
	local options, conform, commands, mappings, root_patterns, search, found, format_request

	before_each(function()
		commands, mappings, found = {}, {}, {}
		format_request = nil
		conform = {
			setup = function(value)
				options = value
			end,
			formatters = {},
			format = function(value)
				format_request = value
			end,
		}
		local modules = {
			["lib.config"] = {
				run = function(spec)
					spec.setup()
				end,
			},
			conform = conform,
			["conform.util"] = {
				root_file = function(patterns)
					root_patterns = patterns
					return function()
						return "/project"
					end
				end,
			},
		}
		local environment = setmetatable({
			vim = setmetatable({
				bo = {
					[1] = { filetype = "lua" },
					[2] = { filetype = "html" },
					[3] = { filetype = "markdown" },
					[4] = { filetype = "sh" },
					[5] = { filetype = "unknown" },
				},
				fs = {
					find = function(name, opts)
						search = {
							name = name,
							opts = opts,
						}
						return found
					end,
				},
				loop = {
					os_homedir = function()
						return "/home/user"
					end,
				},
				api = {
					nvim_create_user_command = function(name, callback)
						commands[name] = callback
					end,
				},
				keymap = {
					set = function(_, key, action)
						mappings[key] = action
					end,
				},
			}, { __index = vim }),
			require = function(name)
				return assert(modules[name])
			end,
		}, { __index = _G })
		setfenv(assert(loadfile("lua/config/format.lua")), environment)()
	end)

	it("prefers treefmt with independent fallback lists", function()
		assert.are.same({ "flake.nix", "treefmt.toml", ".treefmt.toml" }, root_patterns)
		assert.are.same(
			{ "treefmt", "stylua", stop_after_first = true },
			options.formatters_by_ft.lua
		)
		assert.are.same(
			{ "treefmt", "kdlfmt", stop_after_first = true },
			options.formatters_by_ft.kdl
		)
		assert.are.same({ "treefmt" }, options.formatters_by_ft._)
		assert.is_not.equal(options.formatters_by_ft.html, options.formatters_by_ft.markdown)
	end)

	it("skips automatic formatting only for the excluded filetypes", function()
		for _, bufnr in ipairs({ 2, 3, 4 }) do
			assert.is_nil(options.format_on_save(bufnr))
		end
		for _, bufnr in ipairs({ 1, 5 }) do
			assert.are.same({
				timeout_ms = 5000,
				lsp_format = "fallback",
			}, options.format_on_save(bufnr))
		end
	end)

	it("passes the nearest KDL config when found and no arguments otherwise", function()
		local append_args = conform.formatters.kdlfmt.append_args
		assert.are.same({}, append_args({}, { filename = "/project/file.kdl" }))
		assert.are.same({
			name = "kdlfmt.kdl",
			opts = {
				path = "/project/file.kdl",
				upward = true,
				stop = "/home/user",
			},
		}, search)
		found = { "/project/kdlfmt.kdl", "/kdlfmt.kdl" }
		assert.are.same(
			{ "--config", found[1] },
			append_args({}, { filename = "/project/file.kdl" })
		)
	end)

	it("keeps explicit formatting asynchronous", function()
		assert.are.equal("<cmd>Format<cr>", mappings["<leader>cf"])
		commands.Format()
		assert.are.same({ async = true }, format_request)
	end)
end)
