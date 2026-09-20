local M = {}

--- Resolves standard GitHub HTTPS/SSH remotes without contacting the server.
--- Other hosts must be explicitly listed as HTTPS roots in github_enterprise_urls.
---@param remote_url string
---@param enterprise_urls? string[]
---@return string|nil base
---@return string|nil error
function M.remote_base(remote_url, enterprise_urls)
	local authority, project = remote_url:match("^https?://([^/]+)/(.+)$")
	if not authority then
		authority, project = remote_url:match("^ssh://([^/]+)/(.+)$")
	end
	if not authority then
		authority, project = remote_url:match("^[^@/]+@([^:]+):(.+)$")
	end
	if not authority then
		return nil, "Unsupported remote URL; expected a GitHub HTTPS or SSH remote"
	end
	local host = authority:gsub("^.*@", ""):gsub(":%d+$", ""):lower()
	if host == "ssh.github.com" then
		host = "github.com"
	end
	local base = host == "github.com" and "https://github.com" or nil
	for _, url in ipairs(enterprise_urls or {}) do
		local enterprise_authority = url:match("^https://([^/@]+)/?$")
		local enterprise_host = enterprise_authority
			and enterprise_authority:gsub(":%d+$", ""):lower()
		if enterprise_host == host then
			base = url:gsub("/$", "")
		end
	end
	if not base then
		return nil, "Remote is not GitHub; configure github_enterprise_urls for an Enterprise host"
	end

	project = project:gsub("/$", ""):gsub("%.git$", "")
	local owner, name = project:match("^([%w_.%-]+)/([%w_.%-]+)$")
	if not owner or owner == "." or owner == ".." or name == "." or name == ".." then
		return nil, "Remote does not identify an owner/repository"
	end
	return base .. "/" .. project
end

---@param cwd string
---@param ... string
---@return vim.SystemCompleted
local function git(cwd, ...)
	return vim.system({ "git", "--literal-pathspecs", ... }, {
		cwd = cwd,
		env = { GIT_OPTIONAL_LOCKS = "0" },
	}):wait(5000)
end

---@param cwd string
---@param ... string
---@return string
local function output(cwd, ...)
	local result = git(cwd, ...)
	if result.code ~= 0 then
		error("Git " .. select(1, ...) .. " failed: " .. vim.trim(result.stderr or ""), 0)
	end
	return result.stdout
end

--- Prefer the upstream remote; otherwise origin, then a sole remote. Never guess among forks.
---@param repo string
---@return string
local function select_remote(repo)
	local branch = git(repo, "symbolic-ref", "--quiet", "--short", "HEAD")
	if branch.code == 0 then
		local remote =
			git(repo, "config", "--get", "branch." .. vim.trim(branch.stdout) .. ".remote")
		if remote.code == 0 and vim.trim(remote.stdout) ~= "." then
			return vim.trim(remote.stdout)
		end
	end
	local remotes = vim.split(vim.trim(output(repo, "remote")), "\n", { trimempty = true })
	if vim.tbl_contains(remotes, "origin") then
		return "origin"
	end
	if #remotes == 1 then
		return remotes[1]
	end
	error("No unambiguous remote: configure a branch upstream or an origin remote", 0)
end

---@param path string
---@return string
local function encode_path(path)
	return (
		path:gsub("([^%w%-%._~/])", function(char)
			return string.format("%%%02X", char:byte())
		end)
	)
end

---@param bufnr integer
---@param first_line integer
---@param last_line integer
---@return string
local function build_permalink(bufnr, first_line, last_line)
	local file = vim.api.nvim_buf_get_name(bufnr)
	if file == "" or vim.bo[bufnr].buftype ~= "" then
		error("Permalinks require a named file buffer", 0)
	end
	if vim.bo[bufnr].modified then
		error("Save or discard buffer changes before copying a permalink", 0)
	end
	local first, last = math.min(first_line, last_line), math.max(first_line, last_line)
	if first < 1 or last > vim.api.nvim_buf_line_count(bufnr) then
		error("Permalink line range is outside the buffer", 0)
	end

	local repo = output(vim.fs.dirname(file), "rev-parse", "--show-toplevel"):gsub("\n$", "")
	local path = vim.fs.relpath(repo, file)
	if not path then
		error("File is outside its Git worktree", 0)
	end
	local commit = vim.trim(output(repo, "rev-parse", "--verify", "HEAD^{commit}"))
	local blob = output(repo, "show", commit .. ":" .. path)
	local diff = git(repo, "diff", "--no-ext-diff", "--no-textconv", "--quiet", commit, "--", path)
	local staged = git(
		repo,
		"diff",
		"--cached",
		"--no-ext-diff",
		"--no-textconv",
		"--quiet",
		commit,
		"--",
		path
	)
	if diff.code ~= 0 or staged.code ~= 0 then
		error("File differs from HEAD; commit and publish the changes before sharing its lines", 0)
	end

	-- Buffer contents can be stale even when 'modified' is false. Compare with the exact blob.
	local contents = table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n")
	if vim.bo[bufnr].endofline then
		contents = contents .. "\n"
	end
	if vim.bo[bufnr].bomb and blob:sub(1, 3) == "\239\187\191" then
		blob = blob:sub(4)
	end
	if vim.bo[bufnr].fileformat == "dos" then
		blob = blob:gsub("\r\n", "\n")
	end
	if contents ~= blob then
		error("Buffer contents do not match HEAD; reload the file before copying a permalink", 0)
	end

	local remote = select_remote(repo)
	local remote_url = output(repo, "remote", "get-url", remote):gsub("\n$", "")
	local base, err = M.remote_base(remote_url, vim.g.github_enterprise_urls)
	if not base then
		error(err, 0)
	end
	local published = output(
		repo,
		"for-each-ref",
		"--contains=" .. commit,
		"--format=%(refname)",
		"refs/remotes/" .. remote .. "/"
	)
	if published == "" then
		error(
			"HEAD is not present in local tracking refs for "
				.. remote
				.. "; publish or fetch before sharing",
			0
		)
	end

	-- GitHub's plain view supports line anchors even for rendered Markdown and other markup.
	local anchor = first == last and ("#L" .. first) or string.format("#L%d-L%d", first, last)
	return string.format("%s/blob/%s/%s?plain=1%s", base, commit, encode_path(path), anchor)
end

--- Builds a commit-pinned GitHub URL only for unchanged, tracked file contents.
--- Publication is inferred from local remote-tracking refs, not checked over the network.
---@param bufnr integer
---@param first_line integer
---@param last_line integer
---@return string|nil url
---@return string|nil error
function M.build(bufnr, first_line, last_line)
	local ok, result = pcall(build_permalink, bufnr, first_line, last_line)
	if not ok then
		return nil, tostring(result)
	end
	return result
end

--- Copies a verified local file/line reference as a GitHub permalink; failures leave the clipboard alone.
---@param first_line integer
---@param last_line integer
function M.copy(first_line, last_line)
	local url, err = M.build(vim.api.nvim_get_current_buf(), first_line, last_line)
	if not url then
		vim.notify(err, vim.log.levels.WARN)
		return
	end
	vim.fn.setreg("+", url)
	vim.notify("Copied permalink: " .. url, vim.log.levels.INFO)
end

return M
