-- Chooses the TypeScript/JavaScript language server for a project, so each
-- project gets exactly one: TypeScript 7's native server (`tsgo`) or
-- `typescript-language-server` (`ts_ls`), which loads a TypeScript < 7
-- workspace's own `tsserver` and its plugins.
local M = {}

local project_root_markers = { "tsconfig.json", "jsconfig.json", "package.json", ".git" }

--- Iterates `root` and then each of its ancestors.
---@param root string
---@return fun(): string?
local function directories_upward(root)
	local next_dir = vim.fs.normalize(root)
	return function()
		local dir = next_dir
		if dir ~= nil then
			local parent = vim.fs.dirname(dir)
			next_dir = parent ~= dir and parent or nil
		end
		return dir
	end
end

--- Reads the major version of `<node_modules>/<package_name>`.
--- Returns nil when its `package.json` is missing or not valid JSON, and 0 when
--- the JSON has no readable `version`, which callers treat as below 7.
---@param node_modules string
---@param package_name string
---@return integer?
local function read_package_major(node_modules, package_name)
	local package_json = vim.fs.joinpath(node_modules, package_name, "package.json")

	local read_ok, lines = pcall(vim.fn.readfile, package_json)
	if not read_ok or vim.tbl_isempty(lines) then
		return nil
	end

	local decode_ok, manifest = pcall(vim.json.decode, table.concat(lines, "\n"))
	if not decode_ok or type(manifest) ~= "table" then
		return nil
	end

	local major = type(manifest.version) == "string" and manifest.version:match("^(%d+)%.")
	return tonumber(major) or 0
end

---@param bufnr integer
---@return string
local function buffer_directory(bufnr)
	local path = vim.api.nvim_buf_get_name(bufnr)
	if path == "" then
		return assert(vim.uv.cwd())
	end
	return vim.fs.dirname(vim.fs.abspath(path))
end

--- The server for a project root.
--- `tsgo` carries the command that starts TypeScript 7's language server over stdio.
---@alias lib.typescript_server.Selection
---| { server: "tsgo", cmd: string[] }
---| { server: "ts_ls" }

--- Returns the server for a project root.
---
--- The project's TypeScript is the nearest `node_modules` holding
--- `@typescript/native-preview`, `@typescript/native`, or `typescript`,
--- searching from `root` upward as Node resolves packages:
--- - `@typescript/native-preview`, or `@typescript/native` or `typescript` at
---   major version 7 or later: `tsgo` running that `node_modules/.bin` binary.
---   A project can install TypeScript 7 as `@typescript/native` while aliasing
---   `typescript` to the TypeScript 6 API package, which has no `tsserver` for
---   `ts_ls` to load, so `@typescript/native` takes precedence.
--- - `typescript` below 7, or with an unreadable `version`: `ts_ls`.
--- - No TypeScript (including a `node_modules` not installed yet): `tsgo`
---   running the global `tsc` on PATH, which must be TypeScript 7.
---
--- A `typescript/package.json` that is missing or not valid JSON does not count,
--- and the search continues upward.
---@param root string Absolute project root directory.
---@return lib.typescript_server.Selection
function M.select(root)
	for dir in directories_upward(root) do
		local node_modules = vim.fs.joinpath(dir, "node_modules")
		local native_preview_manifest =
			vim.fs.joinpath(node_modules, "@typescript", "native-preview", "package.json")

		if vim.uv.fs_stat(native_preview_manifest) then
			return {
				server = "tsgo",
				cmd = { vim.fs.joinpath(node_modules, ".bin", "tsgo"), "--lsp", "--stdio" },
			}
		end

		local tsc_selection = {
			server = "tsgo",
			cmd = { vim.fs.joinpath(node_modules, ".bin", "tsc"), "--lsp", "--stdio" },
		}

		local native_major = read_package_major(node_modules, "@typescript/native")
		if native_major ~= nil and native_major >= 7 then
			return tsc_selection
		end

		local typescript_major = read_package_major(node_modules, "typescript")
		if typescript_major ~= nil then
			if typescript_major >= 7 then
				return tsc_selection
			end
			return { server = "ts_ls" }
		end
	end

	return {
		server = "tsgo",
		cmd = { "tsc", "--lsp", "--stdio" },
	}
end

--- Returns a `vim.lsp.Config.root_dir` function that activates `server` only
--- for projects whose `select` result names it, so `tsgo` and `ts_ls` never
--- both attach to a root.
---
--- The root is the nearest directory containing any of `tsconfig.json`,
--- `jsconfig.json`, `package.json`, or `.git`, falling back to the buffer's
--- directory.
---@param server "tsgo"|"ts_ls"
---@return fun(bufnr: integer, on_dir: fun(root_dir?: string))
function M.root_dir(server)
	return function(bufnr, on_dir)
		-- Nested, the markers share one priority, so the nearest directory with
		-- any of them wins; a flat list would let a `tsconfig.json` higher up beat
		-- a nearer package's `package.json`.
		local root = vim.fs.root(bufnr, { project_root_markers }) or buffer_directory(bufnr)
		if M.select(root).server == server then
			on_dir(root)
		end
	end
end

return M
