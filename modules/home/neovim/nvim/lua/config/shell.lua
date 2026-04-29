require("lib.config").run({
	setup = function()
		vim.opt.shell = os.getenv("HOME") .. "/.nix-profile/bin/fish"
		vim.opt.shellcmdflag = "-c"
	end,
})
