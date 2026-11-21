-- Rex keybindings: the ctrl+b prefix keymap shared with tmux
-- (../tmux/tmux.conf and tmux's defaults) and the Herdr app
-- (../herdr-app/keys.nix). Every prefix binding is a ctrl+b sequence.
-- Where tmux and Herdr disagree: shift+h/j/k/l resize as in tmux, x and
-- shift+x close the pane and tab as in Herdr, and s picks a session as in tmux.
-- shift with a thing's letter renames it: shift+s the session, as shift+t the
-- tab, where the Herdr app renames a space with shift+w.

-- Pressing the prefix twice sends ctrl+b to the program in the pane.
rex.bind("ctrl+b>ctrl+b", "pane.send_key", { key = "ctrl+b" })

-- Splits
rex.bind("ctrl+b>shift+\\", "pane.split", { direction = "right" })
rex.bind("ctrl+b>-", "pane.split", { direction = "down" })
rex.bind("ctrl+b>shift+'", "pane.split", { direction = "down" })
rex.bind("ctrl+b>shift+5", "pane.split", { direction = "right" })
rex.bind("ctrl+b>v", "pane.split", { direction = "right" })

-- Vim-style pane focus
rex.bind("ctrl+b>h", "pane.focus", { direction = "left" })
rex.bind("ctrl+b>j", "pane.focus", { direction = "down" })
rex.bind("ctrl+b>k", "pane.focus", { direction = "up" })
rex.bind("ctrl+b>l", "pane.focus", { direction = "right" })
rex.bind("ctrl+b>o", "pane.focus_next")

-- Resize panes
rex.bind("ctrl+b>shift+h", "pane.resize", { amount = 5, direction = "left" })
rex.bind("ctrl+b>shift+j", "pane.resize", { amount = 5, direction = "down" })
rex.bind("ctrl+b>shift+k", "pane.resize", { amount = 5, direction = "up" })
rex.bind("ctrl+b>shift+l", "pane.resize", { amount = 5, direction = "right" })

-- Panes
rex.bind("ctrl+b>x", "pane.close")
rex.bind("ctrl+b>z", "pane.zoom")
rex.bind("ctrl+b>shift+1", "pane.move_to_new_tab")
rex.bind("ctrl+b>[", "pane.copy_mode.enter")

-- Tab navigation
rex.bind("ctrl+b>ctrl+h", "client.tab.previous")
rex.bind("ctrl+b>ctrl+l", "client.tab.next")
rex.bind("ctrl+b>p", "client.tab.previous")
rex.bind("ctrl+b>n", "client.tab.next")
for i = 1, 9 do
	rex.bind("ctrl+b>" .. i, "client.tab.goto", { index = i })
end

-- Tabs
rex.bind("ctrl+b>c", "client.tab.new")
rex.bind("ctrl+b>,", "client.tab.rename")
rex.bind("ctrl+b>shift+t", "client.tab.rename")
rex.bind("ctrl+b>shift+x", "client.tab.close")
rex.bind("ctrl+b>shift+7", "client.tab.close")
rex.bind("ctrl+b>shift+,", "client.tab.move.backward")
rex.bind("ctrl+b>shift+.", "client.tab.move.forward")

-- Sessions (tmux sessions, Herdr spaces)
rex.bind("ctrl+b>s", "session.switch")
rex.bind("ctrl+b>shift+9", "session.previous")
rex.bind("ctrl+b>shift+0", "session.next")
rex.bind("ctrl+b>shift+n", "session.new")
rex.bind("ctrl+b>shift+s", "session.rename")
rex.bind("ctrl+b>shift+4", "session.rename")
rex.bind("ctrl+b>shift+d", "session.close")

-- Window and config
rex.bind("ctrl+b>shift+;", "client.palette.toggle")
rex.bind("ctrl+b>b", "client.sidebar.toggle")
rex.bind("ctrl+b>r", "client.config.reload")

-- Repeat mode: stands in for tmux's `bind -r`. ctrl+b ctrl+r enters it; the
-- resize, tab and tab-move keys then repeat without the prefix until enter or
-- escape.
rex.mode("repeat", { exclusive = true })
rex.bind("ctrl+b>ctrl+r", "client.mode.enter", { name = "repeat" })
rex.bind("repeat/enter", "client.mode.exit")
rex.bind("repeat/escape", "client.mode.exit")
rex.bind("repeat/shift+h", "pane.resize", { amount = 5, direction = "left" })
rex.bind("repeat/shift+j", "pane.resize", { amount = 5, direction = "down" })
rex.bind("repeat/shift+k", "pane.resize", { amount = 5, direction = "up" })
rex.bind("repeat/shift+l", "pane.resize", { amount = 5, direction = "right" })
rex.bind("repeat/ctrl+h", "client.tab.previous")
rex.bind("repeat/ctrl+l", "client.tab.next")
rex.bind("repeat/shift+,", "client.tab.move.backward")
rex.bind("repeat/shift+.", "client.tab.move.forward")
