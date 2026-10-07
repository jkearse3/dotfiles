local review_comments = require("lib.jj_review_comments")

describe("JJ review comments", function()
	local function rows(texts)
		local rendered, numbers = {}, {}
		for index, value in ipairs(texts) do
			rendered[index] = { kind = "add", path = "a.lua", new_line = index, text = value }
			numbers[#numbers + 1] = index
		end
		return { rows = rendered }, numbers
	end
	local function comment(line, texts)
		local lines = {}
		for offset, value in ipairs(texts) do
			lines[#lines + 1] =
				{ side = "new", kind = "add", line = line + offset - 1, text = value }
		end
		return { id = "c", path = "a.lua", commit_id = "old", lines = lines, body = "Body" }
	end

	it("anchors a repeated snippet at the occurrence nearest its original line", function()
		local rendered, numbers = rows({ "x", "y", "pad", "pad", "x", "y" })
		local view = {
			commit_id = "new",
			rendered = rendered,
			files = { ["a.lua"] = { rows = numbers, complete = true } },
		}
		local located = review_comments.locate({ comment(4, { "x", "y" }) }, view)[1]
		assert.are.equal("carried", located.placement)
		assert.are.same({ 5, 6 }, { located.first_row, located.last_row })
	end)

	it("distinguishes stale, unverified, and outside comments", function()
		local rendered, numbers = rows({ "x" })
		local function placement(files)
			local view = {
				commit_id = "old",
				rendered = rendered,
				files = files,
			}
			return review_comments.locate({ comment(1, { "gone" }) }, view)[1].placement
		end
		assert.are.equal("stale", placement({ ["a.lua"] = { rows = numbers, complete = true } }))
		assert.are.equal(
			"unloaded",
			placement({ ["a.lua"] = { rows = numbers, complete = false } })
		)
		assert.are.equal("outside", placement({}))
		assert.are.equal("unloaded", placement(nil))
	end)

	it("refuses selections that span files or contain no source line", function()
		local rendered = {
			{ kind = "file", path = "a.lua", text = "a.lua" },
			{ kind = "add", path = "a.lua", new_line = 1, text = "x" },
			{ kind = "add", path = "b.lua", new_line = 1, text = "y" },
		}
		assert.matches(
			"span files",
			select(3, review_comments.anchor_lines(rendered, { 2, 3 })),
			1,
			true
		)
		assert.matches(
			"source line",
			select(3, review_comments.anchor_lines(rendered, { 1 })),
			1,
			true
		)
	end)

	it("labels deletions by old lines and fences quoted backticks safely", function()
		local item = {
			placement = "current",
			comment = { path = "a.lua", body = "Why?" },
			lines = {
				{ side = "old", kind = "delete", line = 7, text = "s = ```" },
				{ side = "old", kind = "delete", line = 8, text = "end" },
			},
		}
		local prompt = review_comments.compose_prompt(
			{ change_id = "k", commit_id = "a", diff_command = "jj diff -r a" },
			{ item }
		)
		assert.matches(
			"## 1. a.lua:7-8 (removed lines)\n\n````diff\n-s = ```\n-end\n````\n\nWhy?",
			prompt,
			1,
			true
		)
		assert.is_nil(
			review_comments.compose_prompt(
				{ change_id = "k", commit_id = "a", diff_command = "" },
				{}
			)
		)
	end)
end)
