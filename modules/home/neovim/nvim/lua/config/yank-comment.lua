-- Duplicate line and comment source duplication.
-- `yy` - yank line,
-- `gcc` - comment line,
-- `p` - paste.
vim.keymap.set("n", "ycc", "yygccp", { remap = true })

-- Duplicate block of text and comment source duplication.
-- `y` - yank visual selection,
-- `gv` - reselect last visual selection,
-- `gc` - comment selection,
-- `'>` - go to the end of the selection,
-- `p` - paste.
vim.keymap.set("v", "yc", "ygvgc'>p", { remap = true })
