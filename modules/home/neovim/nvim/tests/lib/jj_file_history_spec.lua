local history = require("lib.jj_file_history")

local function revisions(count)
	local rows = {}
	for index = 1, count do
		rows[index] = vim.json.encode({
			{
				commit_id = string.format("%040x", index),
				change_id = "changeid",
				description = "revision",
				parents = { string.format("%040x", index + 1) },
			},
			{},
		})
	end
	return table.concat(rows, "\n")
end

local modified = vim.json.encode({ status = "modified", source = "file.txt", target = "file.txt" })

describe("bounded rename-aware file history", function()
	it("bounds traversal independently from the number of matching entries", function()
		local calls = 0
		local result = assert(history.trace("file.txt", function(args)
			if args[1] == "file" then
				return "present\n"
			end
			if args[1] == "log" then
				return revisions(501)
			end
			calls = calls + 1
			return ""
		end))
		assert.are.equal(500, calls)
		assert.are.equal(0, #result.revisions)
		assert.matches("Partial history", result.boundary, 1, true)
	end)

	it("caps matching entries and explains the truncated history", function()
		local calls = 0
		local result = assert(history.trace("file.txt", function(args)
			if args[1] == "file" then
				return "present\n"
			end
			if args[1] == "log" then
				return revisions(501)
			end
			calls = calls + 1
			return modified
		end))
		assert.are.equal(200, calls)
		assert.are.equal(200, #result.revisions)
		assert.matches("Partial history", result.boundary, 1, true)
	end)

	it("checks the elapsed lookup budget between revisions", function()
		local clock, elapsed = vim.uv.hrtime, 0
		vim.uv.hrtime = function()
			return elapsed
		end
		local ok, result = pcall(history.trace, "file.txt", function(args)
			if args[1] == "file" then
				return "present\n"
			end
			if args[1] == "log" then
				return revisions(3)
			end
			elapsed = 31e9
			return modified
		end)
		vim.uv.hrtime = clock
		assert.is_true(ok, result)
		assert.are.equal(1, #result.revisions)
		assert.matches("30-second", result.boundary, 1, true)
	end)

	it("rejects absent recorded paths without scanning earlier lifetimes", function()
		local calls = 0
		local result, err = history.trace("file.txt", function()
			calls = calls + 1
			return ""
		end)
		assert.is_nil(result)
		assert.are.equal(1, calls)
		assert.matches("absent from recorded", err, 1, true)
	end)

	it("rejects malformed history and transition metadata", function()
		for _, output in ipairs({ "bad json", "true", "null", "[]", "[{}]" }) do
			local result, err = history.trace("file.txt", function(args)
				return args[1] == "file" and "present\n" or output
			end)
			assert.is_nil(result)
			assert.is_not_nil(err)
		end
		for _, output in ipairs({ "bad json", "true", "{}", modified .. "\n" .. modified }) do
			local result, err = history.trace("file.txt", function(args)
				if args[1] == "file" then
					return "present\n"
				end
				return args[1] == "log" and revisions(2) or output
			end)
			assert.is_nil(result)
			assert.is_not_nil(err)
		end
	end)

	it("does not publish partial history when a later query fails", function()
		local calls = 0
		local result, err = history.trace("file.txt", function(args)
			if args[1] == "file" then
				return "present\n"
			end
			if args[1] == "log" then
				return revisions(3)
			end
			calls = calls + 1
			if calls == 2 then
				return nil, "query failed"
			end
			return modified
		end)
		assert.is_nil(result)
		assert.are.equal("query failed", err)
	end)
end)
