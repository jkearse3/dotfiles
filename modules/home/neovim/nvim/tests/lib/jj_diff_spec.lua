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

	it("resolves renamed and shifted lines using complete comparison patches", function()
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
		local calls = 0
		local comparison, location = jj_diff.resolve_line_revision(
			"/repo",
			"moved.txt",
			2,
			function(args)
				calls = calls + 1
				if args[1] == "file" then
					return '{"commit_id":"aaaaaaaa","change_id":"changeid","line_number":2,"original_line_number":1}'
				end
				assert.is_false(vim.tbl_contains(args, "--"))
				return args[4] == "--from" and forward_patch or revision_patch
			end
		)
		assert.are.equal(3, calls)
		assert.are.equal("aaaaaaaa", comparison.target)
		assert.are.same({ path = "old.txt", line = 1 }, location)
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

	it("resolves pure renames and renamed lines outside edit hunks", function()
		local rename = table.concat({
			"diff --git a/old.txt b/new.txt",
			"similarity index 100%",
			"rename from old.txt",
			"rename to new.txt",
		}, "\n")
		for _, patch in ipairs({
			rename,
			rename .. "\n--- a/old.txt\n+++ b/new.txt\n@@ -3 +3 @@\n-before\n+after",
		}) do
			local comparison, location = jj_diff.resolve_line_revision(
				"/repo",
				"new.txt",
				1,
				function(args)
					if args[1] == "file" then
						return '{"commit_id":"aaaaaaaa","change_id":"changeid","line_number":1,"original_line_number":1}'
					end
					return args[4] == "--from" and "" or patch
				end
			)
			assert.are.equal("aaaaaaaa", comparison.target)
			assert.are.same({ path = "new.txt", line = 1 }, location)
		end
	end)

	it("refuses copied origins rather than inventing a historical location", function()
		local comparison, err = jj_diff.resolve_line_revision("/repo", "copy.txt", 1, function(args)
			if args[1] == "file" then
				return '{"commit_id":"aaaaaaaa","change_id":"changeid","line_number":1,"original_line_number":1}'
			end
			if args[4] == "--from" then
				return "diff --git a/old.txt b/copy.txt\nsimilarity index 100%\ncopy from old.txt\ncopy to copy.txt"
			end
			return "diff --git a/old.txt b/old.txt\n--- /dev/null\n+++ b/old.txt\n@@ -0,0 +1 @@\n+line"
		end)
		assert.is_nil(comparison)
		assert.matches("copied", err, 1, true)
	end)

	it("propagates attribution and comparison failures without a partial result", function()
		for phase = 1, 3 do
			local calls = 0
			local comparison, err = jj_diff.resolve_line_revision(
				"/repo",
				"file.txt",
				1,
				function(args)
					calls = calls + 1
					if calls == phase then
						return nil, "query failed"
					end
					if args[1] == "file" then
						return '{"commit_id":"aaaaaaaa","change_id":"changeid","line_number":1,"original_line_number":1}'
					end
					return ""
				end
			)
			assert.is_nil(comparison)
			assert.are.equal("query failed", err)
			assert.are.equal(phase, calls)
		end
	end)

	it("rejects scalar and ambiguous annotations", function()
		local row =
			'{"commit_id":"aaaaaaaa","change_id":"changeid","line_number":1,"original_line_number":1}'
		for _, output in ipairs({ "null", "true", "17", '"string"', "[]", row .. "\n" .. row }) do
			local value, err = jj_diff.annotate_line("/repo", "file.txt", 1, function()
				return output
			end)
			assert.is_nil(value)
			assert.is_not_nil(err)
		end
		for _, line in ipairs({ 0, -1, 1.5 }) do
			local value, err = jj_diff.annotate_line("/repo", "file.txt", line, function()
				error("Invalid line must not query JJ")
			end)
			assert.is_nil(value)
			assert.is_not_nil(err)
		end
	end)

	it("lists only live local bookmarks and rejects malformed records", function()
		local bookmarks = assert(jj_diff.list_bookmarks("/repo", function()
			return table.concat({
				'{"name":"local","target":["aaaaaaaa"]}',
				'{"name":"remote","remote":true,"target":["bbbbbbbb"]}',
				'{"name":"deleted","target":null}',
				'{"name":"empty","target":[]}',
			}, "\n")
		end))
		assert.are.equal(1, #bookmarks)
		assert.are.equal("local", bookmarks[1].name)
		for _, output in ipairs({ "null", "true", "{}", '{"name":"bad","target":true}' }) do
			local value, err = jj_diff.list_bookmarks("/repo", function()
				return output
			end)
			assert.is_nil(value)
			assert.is_not_nil(err)
		end
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
		assert.are.same({ kind = "bookmark", name = "feature-b" }, comparison.source)
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
