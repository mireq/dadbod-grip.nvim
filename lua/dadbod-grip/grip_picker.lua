-- grip_picker.lua — self-contained floating list picker. Zero external deps.
--
-- M.open(opts):
--   title    : string                       float title
--   items    : table                        list of any type (required)
--   display  : fn(item) -> string           optional; defaults to tostring
--   on_select: fn(item)                     called when Enter pressed
--   on_delete: fn(item, refresh_fn)         optional; enables D key.
--                                           caller deletes, then calls
--                                           refresh_fn(new_items) to re-render.
--
-- Keymaps (buffer-local, normal mode):
--   j / <Down>   Move down (wraps)
--   k / <Up>     Move up (wraps)
--   Enter        Select hovered item, close picker
--   D            Delete hovered item (only when on_delete is provided)
--   / or gp      Open filter input (vim.ui.input); empty = clear filter
--   q / <Esc>    Close without selection
--
-- Visual:
--   ╭─── Saved Queries (5) ─────────────────╮
--   │  ▶ employees-by-dept                   │
--   │    revenue-monthly                     │
--   │    users-inactive                      │
--   │  ────────────────────────────────────  │
--   │  Enter:load  D:delete  /:filter  q     │
--   ╰────────────────────────────────────────╯

local M = {}

-- ── helpers ──────────────────────────────────────────────────────────────────

local function clamp(n, lo, hi)
  if hi < lo then return lo end
  return math.max(lo, math.min(hi, n))
end

-- ── open ─────────────────────────────────────────────────────────────────────

function M.open(opts)
  assert(opts, "grip_picker.open: opts required")
  local display = opts.display or tostring
  local on_select = opts.on_select
  local on_delete = opts.on_delete
  local title = opts.title or "Grip Picker"

  -- Mutable state
  local items = opts.items or {}
  local filter = ""
  local cursor = 1

  -- ── filter ──

  local function filtered_items()
    if filter == "" then return items end
    local out = {}
    for _, item in ipairs(items) do
      if tostring(display(item)):lower():find(filter:lower(), 1, true) then
        table.insert(out, item)
      end
    end
    return out
  end

  -- ── buffer / win ──

  local popup_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = popup_buf })

  -- Calculate float dimensions
  local function calc_width(flist)
    local min_w = math.max(#title + 6, 30)
    local max_w = math.min(vim.o.columns - 6, 70)
    local content_w = min_w
    for _, item in ipairs(flist) do
      content_w = math.max(content_w, #tostring(display(item)) + 6)
    end
    return clamp(content_w, min_w, max_w)
  end

  local function calc_height(flist)
    local item_count = math.max(1, #flist)  -- at least 1 for "(no items)"
    local overhead = 2  -- separator + footer
    return math.min(item_count + overhead, math.floor(vim.o.lines * 0.6))
  end

  -- Open the float (centered)
  local function open_win(w, h)
    return vim.api.nvim_open_win(popup_buf, true, {
      relative = "editor",
      row = math.floor((vim.o.lines - h) / 2),
      col = math.floor((vim.o.columns - w) / 2),
      width = w,
      height = h,
      style = "minimal",
      border = "rounded",
      title = " " .. title .. " ",
      title_pos = "center",
      zindex = 55,
    })
  end

  local win

  -- ── render ──

  local function render()
    if not vim.api.nvim_buf_is_valid(popup_buf) then return end

    local flist = filtered_items()
    cursor = clamp(cursor, 1, math.max(1, #flist))

    local lines = {}

    -- Filter indicator
    if filter ~= "" then
      table.insert(lines, "  / " .. filter)
    end

    -- Items
    if #flist == 0 then
      table.insert(lines, "  (no items)")
    else
      local w = vim.api.nvim_win_is_valid(win or 0)
          and vim.api.nvim_win_get_width(win)
          or calc_width(flist)
      local max_name = w - 6
      for i, item in ipairs(flist) do
        local label = tostring(display(item))
        if #label > max_name then
          label = label:sub(1, max_name - 1) .. "…"
        end
        local prefix = (i == cursor) and "  ▶ " or "    "
        table.insert(lines, prefix .. label)
      end
    end

    -- Separator + footer
    table.insert(lines, "")
    local footer_parts = { "Enter:select" }
    if on_delete then table.insert(footer_parts, "D:delete") end
    table.insert(footer_parts, "/:filter")
    table.insert(footer_parts, "q:close")
    table.insert(lines, "  " .. table.concat(footer_parts, "  "))

    -- Resize float to fit
    local new_w = calc_width(flist)
    local new_h = calc_height(flist) + (filter ~= "" and 1 or 0)

    vim.bo[popup_buf].modifiable = true
    vim.api.nvim_buf_set_lines(popup_buf, 0, -1, false, lines)
    vim.bo[popup_buf].modifiable = false

    if vim.api.nvim_win_is_valid(win or 0) then
      pcall(vim.api.nvim_win_set_width, win, new_w)
      pcall(vim.api.nvim_win_set_height, win, new_h)
      -- Move cursor to item row (skip filter line if present)
      local item_offset = (filter ~= "" and 1 or 0)
      local target_row = cursor + item_offset
      pcall(vim.api.nvim_win_set_cursor, win, { target_row, 0 })
    end
  end

  -- ── open initial window ──

  local initial_flist = filtered_items()
  local init_w = calc_width(initial_flist)
  local init_h = calc_height(initial_flist)
  win = open_win(init_w, init_h)

  -- ── keymaps ──

  local function map(keys, fn)
    for _, k in ipairs(type(keys) == "table" and keys or { keys }) do
      vim.keymap.set("n", k, fn, { buffer = popup_buf, nowait = true, silent = true })
    end
  end

  -- Close
  local function close()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end

  map({ "q", "<Esc>" }, close)

  -- Navigation
  map({ "j", "<Down>" }, function()
    local flist = filtered_items()
    if #flist == 0 then return end
    cursor = cursor >= #flist and 1 or cursor + 1
    render()
  end)

  map({ "k", "<Up>" }, function()
    local flist = filtered_items()
    if #flist == 0 then return end
    cursor = cursor <= 1 and #flist or cursor - 1
    render()
  end)

  -- Select
  map("<CR>", function()
    local flist = filtered_items()
    if #flist == 0 then return end
    local item = flist[cursor]
    if not item then return end
    close()
    if on_select then
      vim.schedule(function() on_select(item) end)
    end
  end)

  -- Delete
  if on_delete then
    map("D", function()
      local flist = filtered_items()
      if #flist == 0 then return end
      local item = flist[cursor]
      if not item then return end

      local function refresh_fn(new_items)
        items = new_items or {}
        -- Keep cursor in bounds after deletion
        local new_flist = filtered_items()
        cursor = clamp(cursor, 1, math.max(1, #new_flist))
        if vim.api.nvim_win_is_valid(win) then
          render()
        end
      end

      on_delete(item, refresh_fn)
    end)
  end

  -- Filter (/ or gp)
  local function activate_filter()
    local prompt = filter ~= "" and ("Filter [" .. filter .. "]: ") or "Filter: "
    vim.ui.input({ prompt = prompt, default = filter }, function(input)
      if input == nil then return end  -- cancelled
      filter = input
      cursor = 1
      -- Re-render after input closes (input may close float temporarily)
      vim.schedule(function()
        if vim.api.nvim_win_is_valid(win) then
          render()
        end
      end)
    end)
  end

  map({ "/", "gp" }, activate_filter)

  -- ── initial render ──

  render()
end

return M
