-- ui.lua: shared UI primitives for dadbod-grip.
-- Kept small: only patterns that are reused across modules.

local M = {}

--- Show a notification immediately, then run fn.
--- Without the explicit redraw, vim.notify() is invisible until after fn() returns,
--- because Neovim only repaints between event-loop ticks, not during a Lua callback.
--- Use this for any operation that blocks the event loop (db queries, schema builds, etc.).
--- Multiple return values from fn() are forwarded naturally.
--- @param msg string
--- @param fn  function
--- @return    any
function M.blocking(msg, fn)
  vim.notify(msg, vim.log.levels.INFO)
  vim.cmd("redraw")
  return fn()
end

return M
