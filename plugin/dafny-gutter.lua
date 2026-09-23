if vim.g.loaded_dafny_gutter then
  return
end
vim.g.loaded_dafny_gutter = true

local gutter = require("dafny-gutter")
gutter.setup()

vim.api.nvim_create_user_command("DafnyGutterEnable", function()
  gutter.enable()
end, { desc = "Enable Dafny verification gutter" })

vim.api.nvim_create_user_command("DafnyGutterDisable", function()
  gutter.disable()
end, { desc = "Disable Dafny verification gutter" })
