-- ui.lua: shared UI primitives for dadbod-grip.
-- Kept small: only patterns that are reused across modules.

local M = {}

--- Show a spinner + message immediately, run fn(), then clear the float.
--- Uses nvim__redraw({flush=true}) to write to the terminal synchronously,
--- bypassing Neovim's Lua-call batching. eventignore="all" suppresses plugin
--- autocmds (WinNew, BufNew) that add 200-400ms overhead on each call.
--- pcall wraps fn() so the float always closes even if fn() raises an error.
--- All return values from fn() are forwarded naturally.
--- @param msg string
--- @param fn  function
--- @return    any
function M.blocking(msg, fn)
  local display = "⠋ " .. msg
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "", "  " .. display, "" })
  local w   = math.min(vim.fn.strdisplaywidth(display) + 6, vim.o.columns - 4)

  -- Suppress plugin autocmds during float create to avoid 200-400ms overhead
  -- from noice/treesitter/nvim-cmp WinNew and BufNew handlers.
  local ei = vim.o.eventignore
  vim.o.eventignore = "all"
  local win = vim.api.nvim_open_win(buf, false, {
    relative = "editor", style = "minimal", border = "rounded",
    width    = w, height = 3,
    row      = math.floor((vim.o.lines   - 3) / 2),
    col      = math.floor((vim.o.columns - w) / 2),
  })
  vim.o.eventignore = ei

  -- Flush to terminal NOW, before fn() runs. nvim__redraw({flush=true})
  -- bypasses Lua-call batching; vim.cmd("redraw") defers until call returns.
  vim.api.nvim__redraw({ flush = true })

  -- table.pack/table.unpack are Lua 5.2+; LuaJIT is 5.1.
  -- { pcall(fn) } => { ok, r1, r2, ... } or { false, errmsg }
  local rets = { pcall(fn) }
  local ok   = table.remove(rets, 1)

  -- Close float, suppressing autocmds again.
  ei = vim.o.eventignore
  vim.o.eventignore = "all"
  pcall(vim.api.nvim_win_close, win, true)
  pcall(vim.api.nvim_buf_delete, buf, { force = true })
  vim.o.eventignore = ei

  -- Flush the close to terminal so the float disappears before the next render.
  vim.api.nvim__redraw({ flush = true })

  if not ok then error(rets[1], 2) end
  return (table.unpack or unpack)(rets)
end

return M
