-- editor.lua: float cell editor.
-- Minimal: one purpose, no state leaked to caller.
--
-- Keymap philosophy:
--   INSERT <Esc>  -> normal mode (natural Vim; NOT mapped to cancel)
--   INSERT <C-c>  -> cancel
--   NORMAL <Esc>  -> cancel
--   NORMAL q      -> cancel
--   <CR> / <C-s>  -> save (both modes)
--
-- This means the editor is a real mini-buffer: full Vim motions available.
-- The footer updates live to show INSERT vs NORMAL hints.

local M = {}

local _ag = vim.api.nvim_create_augroup("DadbodGripEditor", { clear = true })

-- Sentinel: caller uses this to distinguish "user set NULL" from "user cancelled".
M.NULL_VALUE = "__GRIP_NULL__"

-- M.open(prompt, initial_value, on_save, opts)
--   prompt:        string shown in border title (e.g. "users.name")
--   initial_value: string | nil (nil = current value is NULL, pre-fill empty)
--   on_save(result):
--     result = nil              -> user cancelled
--     result = M.NULL_VALUE     -> user explicitly wants NULL (saved empty)
--     result = "some string"    -> new value
--   opts (optional table):
--     opts.max_h  number  max float height (default 20)
--     opts.max_w  number  max float width  (default 100)
--     opts.ft     string  filetype for syntax highlighting (e.g. "json")
function M.open(prompt, initial_value, on_save, opts)
  opts = opts or {}
  local caller_win = vim.api.nvim_get_current_win()  -- save for restore on close
  local pre_fill = initial_value or ""
  -- Split on newlines so nvim_buf_set_lines receives clean per-line strings
  local fill_lines = vim.split(pre_fill, "\n", { plain = true })
  local height = math.min(opts.max_h or 20, math.max(3, #fill_lines))
  -- Width from longest line
  local max_line_len = 0
  for _, l in ipairs(fill_lines) do max_line_len = math.max(max_line_len, #l) end
  local width = math.min(opts.max_w or 100, math.max(40, max_line_len + 6))

  -- Create a scratch buffer for the editor
  local edit_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_option_value("buftype", "nofile", { buf = edit_buf })
  vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = edit_buf })
  if opts.ft then
    vim.api.nvim_set_option_value("filetype", opts.ft, { buf = edit_buf })
  end
  vim.api.nvim_buf_set_lines(edit_buf, 0, -1, false, fill_lines)

  -- Position: above cursor row
  local cursor = vim.api.nvim_win_get_cursor(0)
  local win_row = cursor[1]
  local float_row = win_row > 3 and -(height + 1) or 1

  local float_win = vim.api.nvim_open_win(edit_buf, true, {
    relative = "cursor",
    row = float_row,
    col = 0,
    width = width,
    height = height,
    style = "minimal",
    border = "rounded",
    title = " " .. (prompt or "edit") .. " ",
    title_pos = "center",
    footer     = "  INSERT  <CR>=save  <Esc>=normal  ",
    footer_pos = "right",
    zindex = 60,
  })

  -- Word wrap: long values wrap at word boundaries instead of scrolling sideways
  vim.wo[float_win].wrap        = true
  vim.wo[float_win].linebreak   = true
  vim.wo[float_win].breakindent = true

  -- Start in insert mode at end of line
  vim.cmd("startinsert!")

  local closed = false  -- guard against double-fire (save + WinLeave)

  local function restore_caller()
    vim.schedule(function()
      if vim.api.nvim_win_is_valid(caller_win) then
        vim.api.nvim_set_current_win(caller_win)
      end
    end)
  end

  local function do_save()
    if closed then return end
    closed = true
    local lines = vim.api.nvim_buf_get_lines(edit_buf, 0, -1, false)
    -- Join all lines to support multi-line editing (for cells with embedded newlines)
    local val = table.concat(lines, "\n")
    vim.cmd("stopinsert")
    if vim.api.nvim_win_is_valid(float_win) then
      vim.api.nvim_win_close(float_win, true)
    end
    restore_caller()
    -- Empty string -> NULL signal
    local result = val == "" and M.NULL_VALUE or val
    on_save(result)
  end

  local function do_cancel()
    if closed then return end
    closed = true
    vim.cmd("stopinsert")
    if vim.api.nvim_win_is_valid(float_win) then
      vim.api.nvim_win_close(float_win, true)
    end
    restore_caller()
    on_save(nil)
  end

  -- Live footer: updates when mode changes so the user always sees the right hints
  local function _set_footer(mode_char)
    if not vim.api.nvim_win_is_valid(float_win) then return end
    local f = mode_char == "i"
      and "  INSERT  <CR>=save  <Esc>=normal  "
      or  "  NORMAL  <CR>=save  q/<Esc>=cancel  "
    vim.api.nvim_win_set_config(float_win, { footer = f, footer_pos = "right" })
  end
  vim.api.nvim_create_autocmd("InsertEnter", {
    group = _ag, buffer = edit_buf,
    callback = function() _set_footer("i") end,
  })
  vim.api.nvim_create_autocmd("InsertLeave", {
    group = _ag, buffer = edit_buf,
    callback = function() _set_footer("n") end,
  })

  -- Keymaps (buf-local)
  -- NOTE: INSERT <Esc> is intentionally NOT mapped; natural Vim exits to NORMAL mode
  vim.keymap.set({ "i", "n" }, "<CR>",  do_save,   { buffer = edit_buf, noremap = true })
  vim.keymap.set({ "i", "n" }, "<C-s>", do_save,   { buffer = edit_buf, noremap = true })
  vim.keymap.set("n",           "<Esc>", do_cancel, { buffer = edit_buf, noremap = true })
  vim.keymap.set("n",           "q",     do_cancel, { buffer = edit_buf, noremap = true, nowait = true })
  vim.keymap.set("i",           "<C-c>", do_cancel, { buffer = edit_buf, noremap = true })

  -- Also cancel if the float loses focus
  vim.api.nvim_create_autocmd("WinLeave", {
    group  = _ag,
    buffer = edit_buf,
    once = true,
    callback = function()
      if closed then return end  -- already handled by save/cancel
      closed = true
      if vim.api.nvim_win_is_valid(float_win) then
        vim.api.nvim_win_close(float_win, true)
      end
      restore_caller()
      on_save(nil)
    end,
  })
end

-- Show a focused error float. Dismiss with q / <CR> / <Esc>.
function M.show_error(title, lines)
  local caller_win = vim.api.nvim_get_current_win()

  local max_w = 0
  for _, l in ipairs(lines) do max_w = math.max(max_w, #l) end
  local width = math.min(80, math.max(40, max_w + 4))

  local err_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(err_buf, 0, -1, false, lines)
  vim.api.nvim_set_option_value("modifiable", false, { buf = err_buf })

  -- Highlight group for error
  local ns = vim.api.nvim_create_namespace("grip_error")
  for i, line in ipairs(lines) do
    if line:match("^✗") or line:match("violates") or line:match("constraint") then
      vim.api.nvim_buf_set_extmark(err_buf, ns, i - 1, 0, {
        end_col = #line,
        hl_group = "DiagnosticError",
      })
    elseif line:match("preserved") or line:match("Fix") or line:match("press") then
      vim.api.nvim_buf_set_extmark(err_buf, ns, i - 1, 0, {
        end_col = #line,
        hl_group = "DiagnosticHint",
      })
    end
  end

  local float_win = vim.api.nvim_open_win(err_buf, true, {
    relative = "editor",
    row = math.floor((vim.o.lines - #lines - 4) / 2),
    col = math.floor((vim.o.columns - width) / 2),
    width = width,
    height = #lines,
    style = "minimal",
    border = "rounded",
    title = " " .. (title or "Error") .. " ",
    title_pos = "center",
    zindex = 70,
  })

  local function dismiss()
    if vim.api.nvim_win_is_valid(float_win) then
      vim.api.nvim_win_close(float_win, true)
    end
    if vim.api.nvim_win_is_valid(caller_win) then
      vim.api.nvim_set_current_win(caller_win)
    end
  end

  for _, key in ipairs({ "q", "<CR>", "<Esc>" }) do
    vim.keymap.set("n", key, dismiss, { buffer = err_buf, nowait = true })
  end

  -- Safety: dismiss if float loses focus (e.g. user clicks away)
  vim.api.nvim_create_autocmd("WinLeave", {
    group  = _ag,
    buffer = err_buf,
    once = true,
    callback = dismiss,
  })
end

return M
