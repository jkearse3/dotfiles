local jj_diff = require("lib.jj_diff")

describe("jj diff patches", function()
	it("parses files, hunks, quoted paths, and navigable rows", function()
		local patch = table.concat({
			"diff --git a/plain.txt b/plain.txt",
			"index 1111111..2222222 100644",
			"--- a/plain.txt",
			"+++ b/plain.txt",
			"@@ -1,2 +1,3 @@",
			" same",
			"+added",
			" old",
			'diff --git "a/path with\\tTab.txt" "b/path with\\tTab.txt"',
			"index 1111111..2222222 100644",
			'--- "a/path with\\tTab.txt"',
			'+++ "b/path with\\tTab.txt"',
			"@@ -1 +1 @@",
			"-before",
			"+after",
		}, "\n")

		local parsed = jj_diff.parse_patch(patch)
		assert.are.equal(2, #parsed.files)
		assert.are.equal("path with\tTab.txt", parsed.files[2].new_path)
		assert.are.same({ path = "plain.txt", line = 1 }, parsed.rows[6])
		assert.are.same({ path = "plain.txt", line = 2 }, parsed.rows[7])
		assert.are.same({ path = "plain.txt", line = 3 }, parsed.rows[8])
		assert.are.equal(4, #parsed.quickfix)
	end)

	it("excludes deleted files and deleted rows from navigation", function()
		local patch = table.concat({
			"diff --git a/gone.txt b/gone.txt",
			"deleted file mode 100644",
			"--- a/gone.txt",
			"+++ /dev/null",
			"@@ -1 +0,0 @@",
			"-gone",
		}, "\n")

		local parsed = jj_diff.parse_patch(patch)
		assert.is_nil(parsed.rows[6])
		assert.are.equal(0, #parsed.quickfix)
	end)

	it("maps surviving lines through shifts, changes, renames, and deletion", function()
		local shifted = table.concat({
			"diff --git a/file.txt b/moved.txt",
			"similarity index 80%",
			"rename from file.txt",
			"rename to moved.txt",
			"--- a/file.txt",
			"+++ b/moved.txt",
			"@@ -1,3 +1,4 @@",
			" first",
			"+inserted",
			" second",
			"-third",
			"+changed",
		}, "\n")

		assert.are.same({ "moved.txt", 1 }, { jj_diff.map_line(shifted, "file.txt", 1) })
		assert.are.same({ "moved.txt", 3 }, { jj_diff.map_line(shifted, "file.txt", 2) })
		assert.is_nil(jj_diff.map_line(shifted, "file.txt", 3))
		assert.are.same({ "other.txt", 4 }, { jj_diff.map_line(shifted, "other.txt", 4) })

		local deleted = table.concat({
			"diff --git a/file.txt b/file.txt",
			"deleted file mode 100644",
			"--- a/file.txt",
			"+++ /dev/null",
		}, "\n")
		assert.is_nil(jj_diff.map_line(deleted, "file.txt", 1))
	end)

	it("indexes and maps pure renames", function()
		local patch = table.concat({
			'diff --git "a/old\\tname.txt" "b/new\\tname.txt"',
			"similarity index 100%",
			"rename from old\tname.txt",
			"rename to new\tname.txt",
		}, "\n")

		local parsed = jj_diff.parse_patch(patch)
		assert.are.equal("old\tname.txt", parsed.files[1].old_path)
		assert.are.equal("new\tname.txt", parsed.files[1].new_path)
		assert.are.same({ lnum = 1, text = "new\tname.txt" }, parsed.quickfix[1])
		assert.are.same({ "new\tname.txt", 7 }, { jj_diff.map_line(patch, "old\tname.txt", 7) })
	end)

	it("preserves literal quotes in raw rename metadata", function()
		local patch = table.concat({
			'diff --git "a/\\"old\\"" "b/\\"new\\""',
			"similarity index 100%",
			'rename from "old"',
			'rename to "new"',
		}, "\n")

		assert.are.same({ '"new"', 1 }, { jj_diff.map_line(patch, '"old"', 1) })
	end)

	it("uses copy metadata when header paths contain separators", function()
		local patch = table.concat({
			"diff --git a/source b/target b/file",
			"similarity index 100%",
			"copy from source",
			"copy to target b/file",
		}, "\n")

		local parsed = jj_diff.parse_patch(patch)
		assert.are.equal("source", parsed.files[1].old_path)
		assert.are.equal("target b/file", parsed.files[1].new_path)
		assert.are.same({ lnum = 1, text = "target b/file" }, parsed.quickfix[1])
		assert.are.same({ "source", 7 }, { jj_diff.map_line(patch, "source", 7) })
	end)

	it("does not parse hunk content as file markers", function()
		local patch = table.concat({
			"diff --git a/file.txt b/file.txt",
			"--- a/file.txt",
			"+++ b/file.txt",
			"@@ -1 +1,2 @@",
			" line",
			"+++ content that resembles a marker",
		}, "\n")

		local parsed = jj_diff.parse_patch(patch)
		assert.are.equal("file.txt", parsed.files[1].new_path)
		assert.are.same({ path = "file.txt", line = 2 }, parsed.rows[6])
		assert.are.same({ lnum = 1, text = "file.txt" }, parsed.quickfix[1])
	end)

	it("indexes binary and mode-only files from diff headers", function()
		local patch = table.concat({
			"diff --git a/binary file.bin b/binary file.bin",
			"index 1111111..2222222 100644",
			"Binary files a/binary file.bin and b/binary file.bin differ",
			'diff --git "a/mode\\tfile" "b/mode\\tfile"',
			"old mode 100644",
			"new mode 100755",
		}, "\n")

		local parsed = jj_diff.parse_patch(patch)
		assert.are.equal("binary file.bin", parsed.files[1].new_path)
		assert.are.equal("mode\tfile", parsed.files[2].new_path)
		assert.are.same({ lnum = 1, text = "binary file.bin" }, parsed.quickfix[1])
		assert.are.same({ lnum = 4, text = "mode\tfile" }, parsed.quickfix[2])
	end)
end)

describe("jj diff comparisons", function()
	it("lists current local bookmarks between revision IDs and descriptions", function()
		local calls = {}
		local revisions = assert(jj_diff.list_revisions("/repo", function(args, cwd)
			table.insert(calls, { args = args, cwd = cwd })
			return table.concat({
				'{"commit_id":"aaaaaaaaaaaaaaaa","change_id":"changeonechangeone",'
					.. '"description":"First revision","bookmarks":["zeta","alpha"]}',
				'{"commit_id":"bbbbbbbbbbbbbbbb","change_id":"changetwochangetwo",'
					.. '"description":"Second revision","bookmarks":[]}',
			}, "\n")
		end))

		assert.are.equal("/repo", calls[1].cwd)
		assert.truthy(calls[1].args[6]:find("local_bookmarks.map", 1, true))
		assert.are.same({ "alpha", "zeta" }, revisions[1].bookmarks)
		assert.are.equal(
			"changeonecha  aaaaaaaaaaaa  [alpha, zeta]  First revision",
			revisions[1].display
		)
		assert.are.equal(
			"changetwocha  bbbbbbbbbbbb  [-]            Second revision",
			revisions[2].display
		)
	end)

	it("uses a selected revision commit without shell interpolation", function()
		local calls = {}
		local comparison = jj_diff.revision_comparison("/repo", {
			commit_id = "0123456789abcdef",
			change_id = "abcdefghijklmnop",
			description = "Add the revision preview",
		})
		local patch = assert(jj_diff.patch(comparison, nil, function(args, cwd)
			table.insert(calls, { args = args, cwd = cwd })
			return "patch"
		end))

		assert.are.equal("patch", patch)
		assert.are.equal("Add the revision preview", comparison.description)
		assert.are.same({
			args = {
				"--config",
				"diff.git.show-path-prefix=true",
				"diff",
				"-r",
				"0123456789abcdef",
				"--git",
				"--color",
				"never",
			},
			cwd = "/repo",
		}, calls[1])
	end)

	it("previews revision descriptions above changed files", function()
		local comparison = {
			repo = "/repo",
			target = "0123456789abcdef",
			title = "jj revision abcdefghijkl",
			description = "feat: summarize revisions\n\nExplain why.\n",
		}
		local summary = assert(jj_diff.preview_summary(comparison, function()
			return "file.txt | 2 +-\n1 file changed, 1 insertion(+), 1 deletion(-)\n"
		end))

		assert.are.equal(
			"feat: summarize revisions\n\nExplain why.\n\n"
				.. "file.txt | 2 +-\n1 file changed, 1 insertion(+), 1 deletion(-)\n",
			summary
		)
		assert.are.equal(
			"unchanged stat\n",
			jj_diff.preview_summary({
				repo = "/repo",
				target = "0123456789abcdef",
				title = "jj bookmark main..feature",
			}, function()
				return "unchanged stat\n"
			end)
		)
	end)

	it("uses stats and structured changed-file commands for a revision", function()
		local comparison = {
			repo = "/repo",
			target = "0123456789abcdef",
		}
		local stat_calls = {}
		assert(jj_diff.stat(comparison, function(args, cwd)
			table.insert(stat_calls, { args = args, cwd = cwd })
			return "1 file changed"
		end))
		assert.are.same({
			args = {
				"diff",
				"-r",
				"0123456789abcdef",
				"--stat",
				"--color",
				"never",
			},
			cwd = "/repo",
		}, stat_calls[1])

		local files_calls = {}
		local files = assert(jj_diff.changed_files(comparison, function(args, cwd)
			table.insert(files_calls, { args = args, cwd = cwd })
			return table.concat({
				'{"path":"plain.txt","display":"plain.txt","status":"M"}',
				'{"path":"new name.txt","display":"old.txt => new name.txt","status":"R"}',
			}, "\n")
		end))
		assert.are.same({
			{ path = "plain.txt", display = "plain.txt", status = "M", label = "M  plain.txt" },
			{
				path = "new name.txt",
				display = "old.txt => new name.txt",
				status = "R",
				label = "R  old.txt => new name.txt",
			},
		}, files)
		assert.are.equal("diff", files_calls[1].args[1])
		assert.are.equal("-T", files_calls[1].args[4])
		assert.are.equal("/repo", files_calls[1].cwd)
	end)

	it("passes path scopes as exact root-relative filesets", function()
		local calls = {}
		local comparison = {
			repo = "/repo",
			from = "aaaaaaaa",
			target = "bbbbbbbb",
		}
		assert(jj_diff.patch(comparison, 'odd | ~ (name)\t"\\.txt', function(args, cwd)
			table.insert(calls, { args = args, cwd = cwd })
			return "patch"
		end))

		assert.are.same({
			args = {
				"--config",
				"diff.git.show-path-prefix=true",
				"diff",
				"--from",
				"aaaaaaaa",
				"--to",
				"bbbbbbbb",
				"--git",
				"--color",
				"never",
				"--",
				'root-file:"odd | ~ (name)\\x09\\"\\\\.txt"',
			},
			cwd = "/repo",
		}, calls[1])
	end)

	it("rejects malformed changed-file output", function()
		local files, err = jj_diff.changed_files({ repo = "/repo", target = "aaaaaaaa" }, function()
			return '{"path":"file.txt","status":"M"}\n'
		end)
		assert.is_nil(files)
		assert.are.equal("jj returned invalid changed-file data", err)

		files, err = jj_diff.changed_files({ repo = "/repo", target = "aaaaaaaa" }, function()
			return "not json\n"
		end)
		assert.is_nil(files)
		assert.truthy(err:find("jj returned invalid JSON"))
	end)

	it("attributes one line with structured argv-safe output", function()
		local calls = {}
		local attribution =
			assert(jj_diff.annotate_line("/repo", "odd name.txt", 7, function(args, cwd)
				table.insert(calls, { args = args, cwd = cwd })
				return table.concat({
					'{"commit_id":"0123456789abcdef","change_id":"abcdefghijklmnop",',
					'"line_number":7,"original_line_number":3}\n',
				})
			end))

		assert.are.same({
			commit_id = "0123456789abcdef",
			change_id = "abcdefghijklmnop",
			line_number = 7,
			original_line_number = 3,
		}, attribution)
		assert.are.equal("/repo", calls[1].cwd)
		assert.are.same(
			{ "file", "annotate", "-r", "@", "-T" },
			vim.list_slice(calls[1].args, 1, 5)
		)
		assert.truthy(calls[1].args[6]:find("line_number == 7", 1, true))
		assert.truthy(calls[1].args[6]:find("json(commit.commit_id())", 1, true))
		assert.are.same(
			{ "--color", "never", "--", "odd name.txt" },
			vim.list_slice(calls[1].args, 7)
		)
	end)

	it("rejects missing and malformed line attribution", function()
		local attribution, err = jj_diff.annotate_line("/repo", "file.txt", 1, function()
			return ""
		end)
		assert.is_nil(attribution)
		assert.truthy(err:find("no attribution"))

		attribution, err = jj_diff.annotate_line("/repo", "file.txt", 1, function()
			return '{"commit_id":"not-hex","change_id":"change","line_number":1,'
				.. '"original_line_number":1}\n'
		end)
		assert.is_nil(attribution)
		assert.are.equal("JJ returned invalid line-attribution data", err)

		attribution, err = jj_diff.annotate_line("/repo", "file.txt", 1, function()
			return "not json\n"
		end)
		assert.is_nil(attribution)
		assert.truthy(err:find("jj returned invalid JSON"))
	end)

	it("opens a renamed and shifted attributed line with complete retained scope", function()
		local directory = vim.fn.tempname()
		vim.fn.mkdir(directory, "p")
		local absolute = vim.fs.joinpath(directory, "moved.txt")
		vim.fn.writefile({ "inserted", "line" }, absolute)
		local revision_patch = table.concat({
			"diff --git a/old.txt b/old.txt",
			"--- a/old.txt",
			"+++ b/old.txt",
			"@@ -1 +1 @@",
			"-before",
			"+line",
		}, "\n")
		local forward_patch = table.concat({
			"diff --git a/old.txt b/moved.txt",
			"similarity index 80%",
			"rename from old.txt",
			"rename to moved.txt",
			"--- a/old.txt",
			"+++ b/moved.txt",
			"@@ -1 +1,2 @@",
			"+inserted",
			" line",
		}, "\n")
		local calls = {}
		local commit_id = "0123456789abcdef"
		local function runner(args, cwd)
			table.insert(calls, { args = vim.deepcopy(args), cwd = cwd })
			if args[1] == "root" then
				return directory .. "\n"
			end
			if args[1] == "file" then
				return string.format(
					'{"commit_id":"%s","change_id":"abcdefghijklmnop",'
						.. '"line_number":2,"original_line_number":1}\n',
					commit_id
				)
			end
			if args[4] == "--from" then
				return forward_patch
			end
			return revision_patch
		end

		local opened, err = jj_diff.open_line_revision(absolute, 2, runner)
		assert.is_true(opened, err)
		local buffer = vim.api.nvim_get_current_buf()
		assert.are.equal("jj-diff://review", vim.api.nvim_buf_get_name(buffer))
		assert.are.same({ 6, 0 }, vim.api.nvim_win_get_cursor(0))
		assert.are.same({
			repo = vim.uv.fs_realpath(directory),
			target = commit_id,
			title = "jj revision abcdefghijkl",
		}, vim.b[buffer].jj_diff_comparison)
		local scoped_call
		for _, call in ipairs(calls) do
			if call.args[#call.args] == 'root-file:"old.txt"' then
				scoped_call = call
			end
		end
		assert.is_not_nil(scoped_call)

		local picked
		local pick_scope = jj_diff.pick_scope
		jj_diff.pick_scope = function(comparison)
			picked = comparison
		end
		jj_diff.pick_retained_scope()
		jj_diff.pick_scope = pick_scope
		assert.are.same(vim.b[buffer].jj_diff_comparison, picked)

		vim.api.nvim_buf_delete(buffer, {})
		vim.fn.delete(directory, "rf")
	end)

	it("supports lines attributed to the working-copy commit", function()
		local revision_patch = table.concat({
			"diff --git a/file.txt b/file.txt",
			"--- a/file.txt",
			"+++ b/file.txt",
			"@@ -0,0 +1 @@",
			"+working line",
		}, "\n")
		local calls = 0
		local comparison, location = jj_diff.resolve_line_revision(
			"/repo",
			"file.txt",
			1,
			function(args)
				calls = calls + 1
				if args[1] == "file" then
					return '{"commit_id":"aaaaaaaa","change_id":"workingcopyid",'
						.. '"line_number":1,"original_line_number":1}\n'
				end
				if args[4] == "--from" then
					return ""
				end
				return revision_patch
			end
		)

		assert.are.equal(3, calls)
		assert.are.equal("aaaaaaaa", comparison.target)
		assert.are.same({ path = "file.txt", line = 1 }, location)
	end)

	it("opens a line attributed to a pure rename at the file header", function()
		local directory = vim.fn.tempname()
		vim.fn.mkdir(directory, "p")
		local absolute = vim.fs.joinpath(directory, "new.txt")
		vim.fn.writefile({ "unchanged" }, absolute)
		local rename_patch = table.concat({
			"diff --git a/old.txt b/new.txt",
			"similarity index 100%",
			"rename from old.txt",
			"rename to new.txt",
		}, "\n")
		local function runner(args)
			if args[1] == "root" then
				return directory .. "\n"
			end
			if args[1] == "file" then
				return '{"commit_id":"aaaaaaaa","change_id":"renamechange",'
					.. '"line_number":1,"original_line_number":1}\n'
			end
			if args[4] == "--from" then
				return ""
			end
			return rename_patch
		end

		local opened, err = jj_diff.open_line_revision(absolute, 1, runner)
		assert.is_true(opened, err)
		local buffer = vim.api.nvim_get_current_buf()
		assert.are.same({ 1, 0 }, vim.api.nvim_win_get_cursor(0))
		assert.are.same({
			repo = vim.uv.fs_realpath(directory),
			target = "aaaaaaaa",
			title = "jj revision renamechange",
		}, vim.b[buffer].jj_diff_comparison)

		vim.api.nvim_buf_delete(buffer, {})
		vim.fn.delete(directory, "rf")
	end)

	it("opens a renamed line outside the revision's edit hunks", function()
		local directory = vim.fn.tempname()
		vim.fn.mkdir(directory, "p")
		local absolute = vim.fs.joinpath(directory, "new.txt")
		vim.fn.writefile({ "one", "two", "three", "four", "five" }, absolute)
		local rename_patch = table.concat({
			"diff --git a/old.txt b/new.txt",
			"similarity index 80%",
			"rename from old.txt",
			"rename to new.txt",
			"--- a/old.txt",
			"+++ b/new.txt",
			"@@ -3,3 +3,3 @@",
			" three",
			"-before",
			"+four",
			" five",
		}, "\n")
		local function runner(args)
			if args[1] == "root" then
				return directory .. "\n"
			end
			if args[1] == "file" then
				return '{"commit_id":"aaaaaaaa","change_id":"renamechange",'
					.. '"line_number":1,"original_line_number":1}\n'
			end
			if args[4] == "--from" then
				return ""
			end
			return rename_patch
		end

		local opened, err = jj_diff.open_line_revision(absolute, 1, runner)
		assert.is_true(opened, err)
		local buffer = vim.api.nvim_get_current_buf()
		assert.are.same({ 1, 0 }, vim.api.nvim_win_get_cursor(0))
		assert.are.same("aaaaaaaa", vim.b[buffer].jj_diff_comparison.target)

		vim.api.nvim_buf_delete(buffer, {})
		vim.fn.delete(directory, "rf")
	end)

	it("preserves retained review state when the line workflow fails", function()
		local existing_comparison = {
			repo = "/repo",
			target = "aaaaaaaa",
			title = "existing comparison",
		}
		local buffer = assert(jj_diff.open_patch(existing_comparison, nil, function()
			return "existing patch"
		end))
		local quickfix = vim.fn.getqflist({ id = 0, title = 0 })
		local directory = vim.fn.tempname()
		vim.fn.mkdir(directory, "p")
		local absolute = vim.fs.joinpath(directory, "file.txt")
		vim.fn.writefile({ "line" }, absolute)
		local function assert_preserved()
			assert.are.same({ "existing patch" }, vim.api.nvim_buf_get_lines(buffer, 0, -1, false))
			assert.are.same(existing_comparison, vim.b[buffer].jj_diff_comparison)
			assert.are.same(quickfix, vim.fn.getqflist({ id = 0, title = 0 }))
		end

		local opened, err = jj_diff.open_line_revision(absolute, 1, function(args)
			if args[1] == "root" then
				return directory .. "\n"
			end
			return "not json\n"
		end)
		assert.is_false(opened)
		assert.truthy(err:find("invalid JSON"))
		assert_preserved()

		local revision_patch = table.concat({
			"diff --git a/old.txt b/old.txt",
			"--- a/old.txt",
			"+++ b/old.txt",
			"@@ -0,0 +1 @@",
			"+line",
		}, "\n")
		local copy_patch = table.concat({
			"diff --git a/old.txt b/file.txt",
			"similarity index 100%",
			"copy from old.txt",
			"copy to file.txt",
		}, "\n")
		opened, err = jj_diff.open_line_revision(absolute, 1, function(args)
			if args[1] == "root" then
				return directory .. "\n"
			end
			if args[1] == "file" then
				return '{"commit_id":"aaaaaaaa","change_id":"changeid",'
					.. '"line_number":1,"original_line_number":1}\n'
			end
			if args[4] == "--from" then
				return copy_patch
			end
			return revision_patch
		end)
		assert.is_false(opened)
		assert.truthy(err:find("copied"))
		assert_preserved()

		local patch_calls = 0
		opened, err = jj_diff.open_line_revision(absolute, 1, function(args)
			if args[1] == "root" then
				return directory .. "\n"
			end
			if args[1] == "file" then
				return '{"commit_id":"aaaaaaaa","change_id":"changeid",'
					.. '"line_number":1,"original_line_number":1}\n'
			end
			patch_calls = patch_calls + 1
			if patch_calls == 1 then
				return revision_patch:gsub("old%.txt", "file.txt")
			end
			if patch_calls == 2 then
				return ""
			end
			return nil, "scoped patch failed"
		end)
		assert.is_false(opened)
		assert.are.equal("scoped patch failed", err)
		assert_preserved()

		vim.api.nvim_buf_delete(buffer, {})
		vim.fn.delete(directory, "rf")
	end)

	it("rejects modified, unnamed, non-file, and out-of-repository buffers", function()
		local directory = vim.fn.tempname()
		vim.fn.mkdir(directory, "p")
		local absolute = vim.fs.joinpath(directory, "file.txt")
		vim.fn.writefile({ "saved" }, absolute)
		local buffer = vim.fn.bufadd(absolute)
		vim.fn.bufload(buffer)
		vim.api.nvim_buf_set_lines(buffer, 0, -1, false, { "unsaved" })
		local called = false
		local opened, err = jj_diff.open_line_revision(absolute, 1, function()
			called = true
			return nil, "runner should not be called"
		end)
		assert.is_false(opened)
		assert.are.equal("Save the buffer before opening its JJ line revision", err)
		assert.is_false(called)
		vim.api.nvim_buf_delete(buffer, { force = true })

		opened, err = jj_diff.open_line_revision(absolute, 1, function(args)
			if args[1] == "root" then
				return "/other/repo\n"
			end
			error("runner should not continue")
		end)
		assert.is_false(opened)
		assert.are.equal("File is outside the JJ repository", err)

		vim.cmd("enew")
		local messages = {}
		local notify = vim.notify
		vim.notify = function(message)
			table.insert(messages, message)
		end
		assert.is_false(jj_diff.open_cursor_revision())
		assert.truthy(messages[#messages]:find("named file buffer"))
		vim.bo.buftype = "nofile"
		assert.is_false(jj_diff.open_cursor_revision())
		assert.truthy(messages[#messages]:find("file buffer"))
		vim.notify = notify
		vim.cmd("bdelete!")
		vim.fn.delete(directory, "rf")
	end)

	it("constructs revision and bookmark previewers after fzf-lua normalization", function()
		local fzf = require("fzf-lua")
		local config = require("fzf-lua.config")
		local fzf_exec = fzf.fzf_exec
		local repo_root = jj_diff.repo_root
		local list_revisions = jj_diff.list_revisions
		local list_bookmarks = jj_diff.list_bookmarks
		local captured = {}
		local ok, err = pcall(function()
			jj_diff.repo_root = function()
				return "/repo"
			end
			jj_diff.list_revisions = function()
				return {
					{
						commit_id = "aaaaaaaa",
						change_id = "revisionchange",
						display = "revision",
					},
				}
			end
			jj_diff.list_bookmarks = function()
				return {
					{ name = "feature", target = { "aaaaaaaa" }, display = "feature" },
				}
			end
			fzf.fzf_exec = function(_, picker_options)
				table.insert(captured, picker_options)
			end
			jj_diff.pick_revision()
			jj_diff.pick_bookmark()
		end)
		fzf.fzf_exec = fzf_exec
		jj_diff.repo_root = repo_root
		jj_diff.list_revisions = list_revisions
		jj_diff.list_bookmarks = list_bookmarks
		assert(ok, err)

		assert.are.equal(2, #captured)
		for _, options in ipairs(captured) do
			local normalized = config.normalize_opts(options, {})
			local instance = require("fzf-lua.previewer").new(normalized.previewer, normalized)
			assert.are.equal("function", type(instance.get_tmp_buffer))
			local buffer = instance:get_tmp_buffer()
			assert.is_true(vim.api.nvim_buf_is_valid(buffer))
			vim.api.nvim_buf_delete(buffer, { force = true })
		end
	end)

	it("retains and reuses one listed patch buffer", function()
		local original = vim.api.nvim_get_current_buf()
		local comparison = {
			repo = "/repo",
			target = "0123456789abcdef",
			title = "jj revision test",
		}
		local first = assert(jj_diff.open_patch(comparison, nil, function()
			return "first patch"
		end))
		assert.are.equal("jj-diff://review", vim.api.nvim_buf_get_name(first))
		assert.are.equal(1, vim.fn.buflisted(first))
		assert.are.equal("hide", vim.bo[first].bufhidden)
		assert.is_false(vim.bo[first].swapfile)
		assert.is_false(vim.bo[first].modifiable)
		assert.is_true(vim.bo[first].readonly)
		assert.are.equal("diff", vim.bo[first].filetype)
		assert.are.same(comparison, vim.b[first].jj_diff_comparison)

		local second = assert(jj_diff.open_patch(comparison, "file.txt", function()
			return "second patch"
		end))
		assert.are.equal(first, second)
		assert.are.same({ "second patch" }, vim.api.nvim_buf_get_lines(second, 0, -1, false))
		local retained = 0
		for _, buffer in ipairs(vim.api.nvim_list_bufs()) do
			if
				vim.api.nvim_buf_is_valid(buffer)
				and vim.api.nvim_buf_get_name(buffer) == "jj-diff://review"
			then
				retained = retained + 1
			end
		end
		assert.are.equal(1, retained)

		vim.api.nvim_set_current_buf(original)
		local picked
		local pick_scope = jj_diff.pick_scope
		jj_diff.pick_scope = function(context)
			picked = context
		end
		jj_diff.pick_retained_scope()
		jj_diff.pick_scope = pick_scope
		assert.are.same(comparison, picked)

		vim.api.nvim_buf_delete(second, {})
		assert.is_false(vim.api.nvim_buf_is_valid(second))
	end)

	it("replaces the retained patch quickfix list in place", function()
		local comparison = {
			repo = "/repo",
			target = "0123456789abcdef",
			title = "jj revision test",
		}
		local first_patch = table.concat({
			"diff --git a/first.txt b/first.txt",
			"--- a/first.txt",
			"+++ b/first.txt",
			"@@ -1 +1 @@",
			"-old",
			"+new",
		}, "\n")
		local buffer = assert(jj_diff.open_patch(comparison, nil, function()
			return first_patch
		end))
		local first_list = vim.fn.getqflist({ id = 0, items = 0, nr = 0 })
		assert.are.equal("first.txt", first_list.items[1].text)

		local second_patch = first_patch:gsub("first%.txt", "second.txt")
		assert.are.equal(
			buffer,
			jj_diff.open_patch(comparison, "second.txt", function()
				return second_patch
			end)
		)
		local second_list = vim.fn.getqflist({ id = 0, items = 0, nr = 0 })
		assert.are.equal(first_list.id, second_list.id)
		assert.are.equal(first_list.nr, second_list.nr)
		assert.are.equal("second.txt", second_list.items[1].text)

		vim.api.nvim_buf_delete(buffer, {})
		assert.are.equal(0, vim.fn.getqflist({ id = second_list.id, size = 0 }).size)

		local reopened = assert(jj_diff.open_patch(comparison, nil, function()
			return first_patch
		end))
		local reopened_list = vim.fn.getqflist({ id = 0, nr = 0 })
		assert.are_not.equal(second_list.id, reopened_list.id)
		vim.cmd("silent colder")
		local closed_list = vim.fn.getqflist({ id = 0, size = 0 })
		assert.are.equal(second_list.id, closed_list.id)
		assert.are.equal(0, closed_list.size)

		vim.api.nvim_buf_delete(reopened, {})
	end)

	it("keeps the patch as the alternate buffer after working-file navigation", function()
		local directory = vim.fn.tempname()
		vim.fn.mkdir(directory, "p")
		local path = vim.fs.joinpath(directory, "file.txt")
		vim.fn.writefile({ "line" }, path)
		local patch = table.concat({
			"diff --git a/file.txt b/file.txt",
			"--- a/file.txt",
			"+++ b/file.txt",
			"@@ -1 +1 @@",
			" line",
		}, "\n")
		local comparison = {
			repo = directory,
			target = "0123456789abcdef",
			title = "jj revision test",
		}
		local buffer = assert(jj_diff.open_patch(comparison, nil, function()
			return patch
		end))
		local ok = jj_diff.open_working_line(comparison, { path = "file.txt", line = 1 }, function()
			return ""
		end)

		assert.is_true(ok)
		assert.are.equal(vim.uv.fs_realpath(path), vim.api.nvim_buf_get_name(0))
		assert.are.equal(buffer, vim.fn.bufnr("#"))
		assert.is_true(vim.api.nvim_buf_is_valid(buffer))
		assert.are.equal(1, vim.fn.buflisted(buffer))
		local file_buffer = vim.api.nvim_get_current_buf()
		vim.api.nvim_feedkeys(vim.keycode("<C-^>"), "nx", false)
		assert.are.equal(buffer, vim.api.nvim_get_current_buf())
		vim.api.nvim_feedkeys(vim.keycode("<C-^>"), "nx", false)
		assert.are.equal(file_buffer, vim.api.nvim_get_current_buf())

		vim.api.nvim_buf_delete(buffer, {})
		vim.cmd("bdelete! " .. vim.api.nvim_get_current_buf())
		vim.fn.delete(directory, "rf")
	end)

	it("preserves a retained patch and quickfix list when patch generation fails", function()
		local comparison = {
			repo = "/repo",
			target = "0123456789abcdef",
			title = "jj revision test",
		}
		local buffer = assert(jj_diff.open_patch(comparison, nil, function()
			return "existing patch"
		end))
		vim.fn.setqflist({}, " ", { title = "existing quickfix", items = {} })

		local opened, err = jj_diff.open_patch(comparison, "missing.txt", function()
			return nil, "jj failed"
		end)
		assert.is_nil(opened)
		assert.are.equal("jj failed", err)
		assert.are.same({ "existing patch" }, vim.api.nvim_buf_get_lines(buffer, 0, -1, false))
		assert.are.equal("existing quickfix", vim.fn.getqflist({ title = 0 }).title)

		vim.api.nvim_buf_delete(buffer, {})
	end)

	it("maps against the complete working-copy diff so renames remain visible", function()
		local calls = {}
		local old_notify = vim.notify
		vim.notify = function() end
		local ok = jj_diff.open_working_line(
			{ repo = "/missing", target = "0123456789abcdef" },
			{ path = "old name.txt", line = 1 },
			function(args, cwd)
				table.insert(calls, { args = args, cwd = cwd })
				return ""
			end
		)
		vim.notify = old_notify

		assert.is_false(ok)
		assert.are.same({
			args = {
				"--config",
				"diff.git.show-path-prefix=true",
				"diff",
				"--from",
				"0123456789abcdef",
				"--to",
				"@",
				"--git",
				"--color",
				"never",
			},
			cwd = "/missing",
		}, calls[1])
	end)

	it("refuses to navigate into a modified working-copy buffer", function()
		local directory = vim.fn.tempname()
		vim.fn.mkdir(directory, "p")
		local path = vim.fs.joinpath(directory, "file.txt")
		vim.fn.writefile({ "saved" }, path)
		local buffer = vim.fn.bufadd(path)
		vim.fn.bufload(buffer)
		vim.api.nvim_buf_set_lines(buffer, 0, -1, false, { "unsaved" })
		assert.is_true(vim.bo[buffer].modified)

		local old_notify = vim.notify
		vim.notify = function() end
		local current = vim.api.nvim_get_current_buf()
		local ok = jj_diff.open_working_line(
			{ repo = directory, target = "0123456789abcdef" },
			{ path = "file.txt", line = 1 },
			function()
				return ""
			end
		)
		vim.notify = old_notify

		assert.is_false(ok)
		assert.are.equal(current, vim.api.nvim_get_current_buf())
		assert.is_true(vim.bo[buffer].modified)
		vim.api.nvim_buf_delete(buffer, { force = true })
		vim.fn.delete(directory, "rf")
	end)

	it("resolves a bookmark base from the selected target's first-parent ancestry", function()
		local bookmarks = {
			{ name = "feature-a", target = { "aaaaaaaa" } },
			{ name = "feature-b", target = { "bbbbbbbb" } },
		}
		local comparison =
			assert(jj_diff.bookmark_comparison("/repo", bookmarks[2], bookmarks, function(args, cwd)
				assert.are.equal("/repo", cwd)
				assert.are.equal("log", args[1])
				assert.truthy(args[4]:find("first_ancestors%(commit_id%(bbbbbbbb%)%)"))
				return '{"commit_id":"aaaaaaaa"}\n'
			end))

		assert.are.equal("aaaaaaaa", comparison.from)
		assert.are.equal("bbbbbbbb", comparison.target)
	end)

	it("refuses missing and conflicted bookmark ancestry", function()
		local bookmark = { name = "feature", target = { "bbbbbbbb" } }
		local comparison, err = jj_diff.bookmark_comparison(
			"/repo",
			bookmark,
			{ bookmark },
			function()
				return ""
			end
		)
		assert.is_nil(comparison)
		assert.truthy(err:find("no first%-parent ancestor bookmark"))

		comparison, err = jj_diff.bookmark_comparison(
			"/repo",
			{ name = "conflict", target = { "aaaaaaaa", "bbbbbbbb" } },
			{},
			function()
				error("runner should not be called")
			end
		)
		assert.is_nil(comparison)
		assert.truthy(err:find("ambiguous target"))
	end)
end)
