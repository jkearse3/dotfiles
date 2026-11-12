local typescript_server = require("lib.typescript_server")

--- Writes `node_modules/<package_name>/package.json` under `dir` with `version`.
---@param dir string
---@param package_name string
---@param version string
local function install_package(dir, package_name, version)
	local package_dir = vim.fs.joinpath(dir, "node_modules", package_name)
	vim.fn.mkdir(package_dir, "p")
	vim.fn.writefile(
		{ vim.json.encode({ name = package_name, version = version }) },
		vim.fs.joinpath(package_dir, "package.json")
	)
end

describe("typescript server selection", function()
	local project

	before_each(function()
		-- Resolve symlinks such as macOS /tmp so roots compare equal to `project`.
		local path = vim.fn.tempname()
		vim.fn.mkdir(path, "p")
		project = assert(vim.uv.fs_realpath(path))
	end)

	after_each(function()
		vim.fn.delete(project, "rf")
	end)

	it("uses the global TypeScript 7 server without node_modules", function()
		assert.are.same({
			server = "tsgo",
			cmd = { "tsc", "--lsp", "--stdio" },
		}, typescript_server.select(project))
	end)

	it("defers to ts_ls for a project on TypeScript 5", function()
		install_package(project, "typescript", "5.9.3")

		assert.are.same({ server = "ts_ls" }, typescript_server.select(project))
	end)

	it("runs the project's tsc for a project on TypeScript 7", function()
		install_package(project, "typescript", "7.0.2")

		assert.are.same({
			server = "tsgo",
			cmd = { vim.fs.joinpath(project, "node_modules", ".bin", "tsc"), "--lsp", "--stdio" },
		}, typescript_server.select(project))
	end)

	it("runs the project's tsgo when @typescript/native-preview is installed", function()
		install_package(project, "typescript", "5.9.3")
		install_package(project, "@typescript/native-preview", "7.0.0-dev.20260101.1")

		assert.are.same({
			server = "tsgo",
			cmd = { vim.fs.joinpath(project, "node_modules", ".bin", "tsgo"), "--lsp", "--stdio" },
		}, typescript_server.select(project))
	end)

	it("runs the project's tsc when @typescript/native is TypeScript 7", function()
		install_package(project, "typescript", "6.0.2")
		install_package(project, "@typescript/native", "7.0.2")

		assert.are.same({
			server = "tsgo",
			cmd = { vim.fs.joinpath(project, "node_modules", ".bin", "tsc"), "--lsp", "--stdio" },
		}, typescript_server.select(project))
	end)

	it("resolves TypeScript hoisted into a parent node_modules", function()
		local package_root = vim.fs.joinpath(project, "packages", "app")
		vim.fn.mkdir(vim.fs.joinpath(package_root, "node_modules"), "p")
		install_package(project, "typescript", "5.9.3")

		assert.are.same({ server = "ts_ls" }, typescript_server.select(package_root))
	end)

	it("skips an unparsable typescript package.json and keeps searching upward", function()
		local package_root = vim.fs.joinpath(project, "packages", "app")
		local broken_dir = vim.fs.joinpath(package_root, "node_modules", "typescript")
		vim.fn.mkdir(broken_dir, "p")
		vim.fn.writefile({ "{" }, vim.fs.joinpath(broken_dir, "package.json"))
		install_package(project, "typescript", "7.0.2")

		assert.are.same({
			server = "tsgo",
			cmd = { vim.fs.joinpath(project, "node_modules", ".bin", "tsc"), "--lsp", "--stdio" },
		}, typescript_server.select(package_root))
	end)

	it("activates exactly one server for a buffer's project root", function()
		install_package(project, "typescript", "5.9.3")
		vim.fn.writefile({ "{}" }, vim.fs.joinpath(project, "tsconfig.json"))
		local source_dir = vim.fs.joinpath(project, "src")
		vim.fn.mkdir(source_dir, "p")
		local bufnr = vim.fn.bufadd(vim.fs.joinpath(source_dir, "main.ts"))

		local activated = {}
		for _, server in ipairs({ "tsgo", "ts_ls" }) do
			typescript_server.root_dir(server)(bufnr, function(root)
				activated[server] = root
			end)
		end
		vim.api.nvim_buf_delete(bufnr, { force = true })

		assert.are.same({ ts_ls = project }, activated)
	end)

	it("roots a nested package at its own package.json under a parent tsconfig", function()
		vim.fn.writefile({ "{}" }, vim.fs.joinpath(project, "tsconfig.json"))
		local package_dir = vim.fs.joinpath(project, "sub")
		vim.fn.mkdir(vim.fs.joinpath(package_dir, "src"), "p")
		vim.fn.writefile({ "{}" }, vim.fs.joinpath(package_dir, "package.json"))
		install_package(package_dir, "typescript", "5.9.3")
		local bufnr = vim.fn.bufadd(vim.fs.joinpath(package_dir, "src", "a.ts"))

		local activated = {}
		for _, server in ipairs({ "tsgo", "ts_ls" }) do
			typescript_server.root_dir(server)(bufnr, function(root)
				activated[server] = root
			end)
		end
		vim.api.nvim_buf_delete(bufnr, { force = true })

		assert.are.same({ ts_ls = package_dir }, activated)
	end)
end)
