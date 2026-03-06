if vim.fn.has("nvim-0.10") == 0 then
  vim.notify("dadbod-grip.nvim requires Neovim 0.10+", vim.log.levels.ERROR)
  return
end
if vim.g.loaded_dadbod_grip then return end
vim.g.loaded_dadbod_grip = true
require("dadbod-grip").setup()
