local DEFAULT_COLUMNS = { "icon" }
local DETAIL_COLUMNS = { "icon", "permissions", "size", "mtime" }

local show_details = false

local function toggle_file_detail_view()
	show_details = not show_details
	local columns = show_details and DETAIL_COLUMNS or DEFAULT_COLUMNS
	require("oil").set_columns(columns)
end

---@param name string
---@param command string
local function create_explore_command(name, command)
	vim.api.nvim_create_user_command(name, command, {
		nargs = "?",
		complete = "dir",
	})
end

local function create_explore_commands()
	-- Override the default `netrw` behavior.
	create_explore_command("Explore", "Oil <args>")
	create_explore_command("E", "Explore <args>")
	create_explore_command("Sexplore", "belowright split | Oil <args>")
	create_explore_command("Vexplore", "rightbelow vsplit | Oil <args>")
	create_explore_command("Texplore", "tabedit % | Oil <args>")
end

local function create_explore_keymaps()
	vim.keymap.set("n", "<leader>e", "<cmd>Explore<cr>", { desc = "Explore" })
	vim.keymap.set(
		"n",
		"<leader>E",
		"<cmd>Explore `=getcwd(-1, 1)`<cr>",
		{ desc = "Explore from workspace dir" }
	)
end

local function setup_oil()
	require("oil").setup({
		columns = DEFAULT_COLUMNS,
		delete_to_trash = true,
		watch_for_changes = false,
		view_options = {
			show_hidden = true,
			natural_order = true,
		},
		keymaps = {
			["gd"] = {
				desc = "Toggle file detail view",
				callback = toggle_file_detail_view,
			},
		},
	})

	create_explore_commands()
	create_explore_keymaps()
end

require("lib.config").run({
	plugins = { "https://github.com/stevearc/oil.nvim" },
	setup = setup_oil,
})
