-- init.lua — wiring + :Grip command.
-- Entry point. Parses arg, validates connection, orchestrates modules.

local db     = require("dadbod-grip.db")
local data   = require("dadbod-grip.data")
local view   = require("dadbod-grip.view")
local editor = require("dadbod-grip.editor")
local sql    = require("dadbod-grip.sql")

local M = {}
M._version = "1.0.0"

-- Default options (overridden by setup)
local OPTS = {
  limit       = 100,
  max_col_width = 40,
  timeout     = 10000,
}

-- ── helpers ───────────────────────────────────────────────────────────────

-- Decide the SQL to run for a given :Grip argument.
local function resolve_sql(arg, limit)
  if not arg or arg == "" then
    -- Word under cursor
    arg = vim.fn.expand("<cword>")
  end
  if arg == "" then
    return nil, "No table name or query provided."
  end
  -- If it looks like a SELECT/WITH statement, run as-is
  local upper = arg:upper():match("^%s*(%u+)")
  if upper == "SELECT" or upper == "WITH" or upper == "TABLE" then
    return arg, nil
  end
  -- Otherwise treat as table name
  return string.format("SELECT * FROM %s LIMIT %d", arg, limit), arg
end

-- Extract table name from a SELECT * FROM <table> LIMIT query (best-effort).
local function extract_table_name(arg_original, sql_str)
  if arg_original then return arg_original end
  local tbl = sql_str:match("[Ff][Rr][Oo][Mm]%s+([%w_%.\"]+)")
  return tbl
end

-- ── apply staged changes ──────────────────────────────────────────────────
local function do_apply(bufnr, url)
  local session = view._sessions[bufnr]
  if not session then return end
  local st = session.state

  local updates = data.get_updates(st)
  local inserts = data.get_inserts(st)
  local deletes = data.get_deletes(st)

  local errors = {}

  -- Execute deletes first (avoids FK conflicts with inserts)
  for _, del in ipairs(deletes) do
    local stmt = sql.build_delete(st.table_name, del.pk_values)
    local result, err = db.execute(stmt, url)
    if err then
      table.insert(errors, { sql = stmt, err = err })
    elseif result.affected == 0 then
      table.insert(errors, {
        sql = stmt,
        err = "0 rows affected — row may have been modified externally. Press r to refresh.",
      })
    end
  end

  for _, upd in ipairs(updates) do
    local stmt = sql.build_update(st.table_name, upd.pk_values, upd.changes)
    local result, err = db.execute(stmt, url)
    if err then
      table.insert(errors, { sql = stmt, err = err })
    elseif result.affected == 0 then
      table.insert(errors, {
        sql = stmt,
        err = "0 rows affected — row may have been modified externally. Press r to refresh.",
      })
    end
  end

  for _, ins in ipairs(inserts) do
    local stmt = sql.build_insert(st.table_name, ins.values, ins.columns)
    local _, err = db.execute(stmt, url)
    if err then
      table.insert(errors, { sql = stmt, err = err })
    end
  end

  if #errors > 0 then
    -- Show first error. Changes are preserved (not undone).
    local first = errors[1]
    local lines = {
      "✗ " .. first.sql,
      "",
    }
    for chunk in (first.err .. "\n"):gmatch("([^\n]+)\n?") do
      if chunk ~= "" then table.insert(lines, "  " .. chunk) end
    end
    table.insert(lines, "")
    table.insert(lines, "  Your change is preserved. Fix the value or press u to undo.")
    editor.show_error("Apply failed", lines)
    return
  end

  -- Success — notify and refresh
  local parts = {}
  if #updates > 0 then table.insert(parts, #updates .. " update(s)") end
  if #deletes > 0 then table.insert(parts, #deletes .. " delete(s)") end
  if #inserts > 0 then table.insert(parts, #inserts .. " insert(s)") end
  vim.notify("Applied " .. table.concat(parts, ", "), vim.log.levels.INFO)
  session.on_refresh(bufnr)
end

-- ── refresh ───────────────────────────────────────────────────────────────
local function do_refresh(bufnr, url, query_sql, table_name)
  local result, err = db.query(query_sql, url)
  if err then
    vim.notify("Grip: query failed: " .. err, vim.log.levels.ERROR)
    return
  end

  -- Re-fetch primary keys
  if table_name then
    local pks, pk_err = db.get_primary_keys(table_name, url)
    result.primary_keys = (pk_err == nil) and pks or {}
  else
    result.primary_keys = {}
  end

  result.table_name = table_name
  result.url = url
  result.sql = query_sql

  local new_state = data.new(result)
  view.render(bufnr, new_state)
end

-- ── edit cell ─────────────────────────────────────────────────────────────
local function do_edit(bufnr, cell, url)
  local session = view._sessions[bufnr]
  if not session then return end

  -- Binary columns: not editable
  local val = cell.value or ""
  if val:sub(1, #"<binary") == "<binary" then
    vim.notify("Binary column: not editable", vim.log.levels.INFO)
    return
  end

  local prompt = (session.state.table_name or "row") .. "." .. cell.col_name
  editor.open(prompt, cell.value, function(new_val)
    if new_val == nil then return end  -- cancelled

    -- nil = NULL, anything else = new value
    local actual_val = new_val == editor.NULL_VALUE and nil or new_val

    local new_state = data.add_change(session.state, cell.row_idx, cell.col_name, actual_val)
    view.render(bufnr, new_state)
  end)
end

-- ── open ──────────────────────────────────────────────────────────────────
function M.open(arg, url, opts)
  -- Resolve connection URL
  local conn = url
  if not conn or conn == "" then
    conn = vim.b.db
    if not conn or conn == "" then conn = vim.g.db end
  end
  if not conn or conn == "" then
    vim.notify("Grip: no database connection. Open DBUI first or set vim.g.db.", vim.log.levels.WARN)
    return
  end

  -- Resolve SQL
  local table_name_arg = nil
  local query_sql, err_or_tbl = resolve_sql(arg, OPTS.limit)
  if not query_sql then
    vim.notify("Grip: " .. err_or_tbl, vim.log.levels.WARN)
    return
  end
  -- err_or_tbl holds original arg (table name) when not a raw query
  local upper = (arg or ""):upper():match("^%s*(%u+)")
  if upper ~= "SELECT" and upper ~= "WITH" and upper ~= "TABLE" then
    table_name_arg = arg ~= "" and arg or vim.fn.expand("<cword>")
    if table_name_arg == "" then table_name_arg = nil end
  end

  -- Run query
  local result, qerr = db.query(query_sql, conn)
  if not result then
    vim.notify("Grip: " .. (qerr or "query failed"), vim.log.levels.ERROR)
    return
  end

  -- Fetch primary keys if we have a table name
  if table_name_arg then
    local pks, _ = db.get_primary_keys(table_name_arg, conn)
    result.primary_keys = pks or {}
  else
    result.primary_keys = {}
  end

  result.table_name = table_name_arg
  result.url = conn
  result.sql = query_sql

  local state = data.new(result)

  -- Open the view (caller opts take precedence over defaults via "force")
  local view_opts = vim.tbl_extend("force", { max_col_width = OPTS.max_col_width }, opts or {})
  local bufnr = view.open(state, conn, query_sql, view_opts)

  -- Wire callbacks
  view.set_callbacks(bufnr, {
    on_refresh = function(bid)
      do_refresh(bid, conn, query_sql, table_name_arg)
    end,
    on_apply = function(bid)
      do_apply(bid, conn)
    end,
    on_edit = function(bid, cell)
      do_edit(bid, cell, conn)
    end,
    on_delete = function(bid, row_idx)
      local session = view._sessions[bid]
      if not session then return end
      local was_deleted = session.state.deleted[row_idx]
      local new_state = data.toggle_delete(session.state, row_idx)
      if was_deleted then
        vim.notify("Row " .. row_idx .. " unmarked", vim.log.levels.INFO)
      else
        vim.notify("Row " .. row_idx .. " marked for deletion", vim.log.levels.INFO)
      end
      view.render(bid, new_state)
    end,
    on_insert = function(bid, after_idx)
      local session = view._sessions[bid]
      if not session then return end
      local new_state = data.insert_row(session.state, after_idx)
      view.render(bid, new_state)
      vim.notify("Inserted blank row", vim.log.levels.INFO)
      -- Move cursor to first cell of the new row
      local r = session._render
      if r then
        local ordered = r.ordered
        for i, idx in ipairs(ordered) do
          if new_state.inserted[idx] and idx == new_state._next_insert_idx - 1 then
            local line_nr = i + (r.data_start or 4) - 1
            local bp_row = r.byte_positions and r.byte_positions[i]
            local col_byte = bp_row and bp_row[new_state.columns[1]] and bp_row[new_state.columns[1]].start or #("║ ")
            pcall(vim.api.nvim_win_set_cursor, 0, { line_nr, col_byte })
            break
          end
        end
      end
    end,
  })
end

-- ── open_smart ───────────────────────────────────────────────────────────
-- DBUI-aware smart open: detects context from current buffer and opens
-- the appropriate table in the grid. Works from SQL query buffers,
-- dbout result buffers, and normal buffers (word under cursor).
function M.open_smart()
  local bufnr = vim.api.nvim_get_current_buf()

  -- Case 1: DBUI SQL query buffer — has b:dbui_table_name + b:db (string URL)
  local dbui_table = vim.b[bufnr].dbui_table_name
  if dbui_table and dbui_table ~= "" then
    local url = vim.b[bufnr].db
    if type(url) ~= "string" or url == "" then url = vim.g.db end
    if not url or url == "" then
      vim.notify("Grip: no database connection", vim.log.levels.WARN)
      return
    end
    -- Find the dbout window to reuse (keeps two-pane layout)
    local reuse_win
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      local wb = vim.api.nvim_win_get_buf(win)
      if vim.api.nvim_buf_get_name(wb):match("%.dbout$") then
        reuse_win = win
        break
      end
    end
    local opts = reuse_win and { reuse_win = reuse_win } or nil
    M.open(dbui_table, url, opts)
    return
  end

  -- Case 2: dbout result buffer — b:db is a dict with db_url
  local db_obj = vim.b[bufnr].db
  if type(db_obj) == "table" and db_obj.db_url then
    local url = db_obj.db_url
    if not url or url == "" then url = vim.w.db end
    if not url or url == "" then url = vim.g.db end
    if not url or url == "" then
      vim.notify("Grip: no database connection", vim.log.levels.WARN)
      return
    end
    local table_name
    local db_input = vim.b[bufnr].db_input
    if db_input then
      local input_resolved = vim.fn.resolve(db_input)
      for _, b in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_loaded(b) then
          local bname = vim.fn.resolve(vim.api.nvim_buf_get_name(b))
          if bname == input_resolved then
            table_name = vim.b[b].dbui_table_name
            break
          end
        end
      end
      if (not table_name or table_name == "")
        and vim.fn.filereadable(db_input) == 1 then
        local sql_text = table.concat(vim.fn.readfile(db_input), " ")
        table_name = sql_text:match("[Ff][Rr][Oo][Mm]%s+([%w_%.]+)")
      end
    end
    -- Fallback: search visible windows for a buffer with dbui_table_name
    if not table_name or table_name == "" then
      for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
        local wb = vim.api.nvim_win_get_buf(win)
        local tname = vim.b[wb].dbui_table_name
        if tname and tname ~= "" then
          table_name = tname
          break
        end
      end
    end
    if not table_name or table_name == "" then
      vim.notify("Grip: only works for table results, not raw queries", vim.log.levels.WARN)
      return
    end
    local winid = vim.api.nvim_get_current_win()
    M.open(table_name, url, { reuse_win = winid })
    return
  end

  -- Case 3: Normal buffer — word under cursor
  M.open(vim.fn.expand("<cword>"), nil)
end

-- ── setup ─────────────────────────────────────────────────────────────────
function M.setup(opts)
  opts = opts or {}
  OPTS.limit        = opts.limit        or 100
  OPTS.max_col_width = opts.max_col_width or 40
  OPTS.timeout      = opts.timeout      or 10000

  -- Register :Grip command
  vim.api.nvim_create_user_command("Grip", function(cmd_opts)
    local arg = vim.trim(cmd_opts.args or "")
    M.open(arg, nil)
  end, {
    nargs = "?",
    desc  = "Open dadbod-grip result grid for table or query",
  })
end

return M
