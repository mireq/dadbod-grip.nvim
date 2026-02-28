-- Minimal init for VHS/testing: loads plugin from repo root
vim.opt.rtp:prepend(".")
local lazy_path = vim.fn.stdpath("data") .. "/lazy"
vim.opt.rtp:prepend(lazy_path .. "/vim-dadbod")
require("dadbod-grip").setup()
vim.g.db = "postgresql://localhost/grip_test"
