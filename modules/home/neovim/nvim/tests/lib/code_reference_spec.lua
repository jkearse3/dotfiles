local code_reference = require("lib.code_reference")

describe("code references", function()
	it("uses a workspace-relative path for one line", function()
		local reference =
			assert(code_reference.build("/workspace/src/main.lua", "/workspace", 12, 12))

		assert.are.equal("src/main.lua:12", reference)
	end)

	it("formats a selected line range in document order", function()
		local reference =
			assert(code_reference.build("/workspace/src/main.lua", "/workspace", 18, 7))

		assert.are.equal("src/main.lua:7-18", reference)
	end)

	it("keeps an absolute path for a file outside the workspace", function()
		local reference = assert(code_reference.build("/other/main.lua", "/workspace", 4, 4))

		assert.are.equal("/other/main.lua:4", reference)
	end)

	it("refuses a buffer without a file path", function()
		local reference, err = code_reference.build("", "/workspace", 1, 1)

		assert.is_nil(reference)
		assert.are.equal("Current buffer does not have a file path", err)
	end)
end)
