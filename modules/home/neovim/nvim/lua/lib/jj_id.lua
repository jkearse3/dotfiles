--- Formats JJ change and commit IDs for display.
---@class lib.jj_id
local M = {}

--- Display length of JJ's default `format_short_id` alias (`id.shortest(8)`).
M.short_length = 8

--- Returns the display prefix of a full change or commit ID.
--- Display only: unlike JJ's `shortest`, the prefix is not extended when ambiguous, so
--- commands, lookups, and copied IDs must keep using the full ID.
---@param id string
---@return string
function M.short(id)
	return id:sub(1, M.short_length)
end

return M
