-- ui.lua: shared UI primitives for dadbod-grip.
-- Kept small: only patterns that are reused across modules.

local M = {}

--- Show a progress message immediately, run fn(), then close the message.
--- vim.notify() is intercepted async by noice/fidget and never appears before
--- fn() returns. A non-focused float is synchronous: it is in the render buffer
--- at redraw time and appears before any blocking work starts.
--- pcall wraps fn() so the float always closes even if fn() raises an error.
--- All return values from fn() are forwarded naturally.
--- @param msg string
--- @param fn  function
--- @return    any
function M.blocking(msg, fn)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "", "  " .. msg, "" })
  local w   = math.min(#msg + 6, vim.o.columns - 4)
  local win = vim.api.nvim_open_win(buf, false, {
    relative = "editor", style = "minimal", border = "rounded",
    width    = w, height = 3,
    row      = math.floor((vim.o.lines   - 3) / 2),
    col      = math.floor((vim.o.columns - w) / 2),
  })
  -- nvim__redraw({ flush=true }) writes to the terminal immediately, bypassing
  -- Neovim's Lua-call batching. vim.cmd("redraw") defers the flush until the
  -- current Lua call returns, so the float would appear AFTER fn() completes.
  vim.api.nvim__redraw({ flush = true })
  -- table.pack/table.unpack are Lua 5.2+; LuaJIT is 5.1.
  -- { pcall(fn) } => { ok, r1, r2, ... } or { false, errmsg }
  local rets = { pcall(fn) }
  local ok   = table.remove(rets, 1)
  pcall(vim.api.nvim_win_close, win, true)
  pcall(vim.api.nvim_buf_delete, buf, { force = true })
  if not ok then error(rets[1], 2) end
  return (table.unpack or unpack)(rets)
end

return M
