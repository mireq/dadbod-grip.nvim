-- schema.lua — sidebar schema tree browser.
-- Tables/views with expandable columns showing types + PK/FK markers.
-- Lazy column fetching on expand.

local db      = require("dadbod-grip.db")
local VERSION = require("dadbod-grip.version")

local M = {}

-- Active schema state (one per connection URL)
local _states = {}
local _sidebar_bufnr = nil
local _sidebar_winid = nil

local SIDEBAR_WIDTH_RATIO = 0.25
local SIDEBAR_MAX_WIDTH = 36
local SIDEBAR_MIN_WIDTH = 24

--- Abbreviate data types for compact display.
local function abbrev_type(dtype)
  if not dtype or dtype == "" then return "" end
  local lower = dtype:lower()
  -- Exact matches
  if lower == "integer" or lower == "int" or lower == "int4" then return "int" end
  if lower == "bigint" or lower == "int8" then return "big" end
  if lower == "smallint" or lower == "int2" then return "small" end
  if lower == "boolean" or lower == "tinyint(1)" or lower == "bool" then return "bool" end
  if lower == "text" then return "text" end
  if lower == "date" then return "date" end
  if lower == "time" then return "time" end
  if lower == "json" or lower == "jsonb" then return "json" end
  if lower == "real" or lower == "float" then return "float" end
  if lower == "double precision" or lower == "double" then return "dbl" end
  if lower == "blob" or lower == "bytea" then return "bin" end
  if lower == "uuid" or lower == "char(36)" then return "uuid" end
  if lower == "interval" then return "intv" end
  -- Timestamp variants
  if lower:match("^timestamp") then return "ts" end
  -- Varchar with length
  local vc_len = lower:match("^character varying%((%d+)%)$") or lower:match("^varchar%((%d+)%)$")
  if vc_len then return "vc(" .. vc_len .. ")" end
  if lower:match("^varchar") or lower:match("^character varying") then return "vc" end
  -- Decimal/numeric with precision
  local dec_m, dec_n = lower:match("^decimal%((%d+),(%d+)%)$")
  if not dec_m then dec_m, dec_n = lower:match("^numeric%((%d+),(%d+)%)$") end
  if dec_m then return "dec(" .. dec_m .. "," .. dec_n .. ")" end
  if lower:match("^decimal") or lower:match("^numeric") then return "dec" end
  -- INT AUTO_INCREMENT → int
  if lower:match("^int") then return "int" end
  -- Enum
  if lower:match("^enum") or lower:match("^user%-defined") then return "enum" end
  -- Array types
  if lower:match("%[%]$") then return abbrev_type(lower:gsub("%[%]$", "")) .. "[]" end
  -- Fallback: truncate
  if #dtype > 8 then return dtype:sub(1, 7) .. "…" end
  return dtype
end

-- File extensions that DuckDB can query directly (mirrors init.lua).
local FILE_EXTENSIONS = { ".parquet", ".csv", ".tsv", ".json", ".ndjson", ".jsonl", ".xlsx", ".orc", ".arrow", ".ipc" }

--- Returns true when the URL is a file path or remote file (not a DB connection).
local function is_file_url(url)
  if not url then return false end
  if url:match("^https?://") then
    local path = url:gsub("[?#].*$", ""):lower()
    for _, ext in ipairs(FILE_EXTENSIONS) do
      if path:sub(-#ext) == ext then return true end
    end
  end
  if url:match("^/") or url:match("^~/") or url:match("^%.%.?/") then
    local lower = url:lower()
    for _, ext in ipairs(FILE_EXTENSIONS) do
      if lower:sub(-#ext) == ext then return true end
    end
  end
  return false
end

--- Get or create state for a URL.
local function get_state(url)
  if not _states[url] then
    _states[url] = {
      url = url,
      items = nil,       -- { {name, type}, ... } — nil = not fetched
      file_cols = nil,   -- for file-as-table: { {column_name, data_type}, ... }
      expanded = {},      -- set of expanded table names
      col_cache = {},     -- table_name → column_info[]
      pk_cache = {},      -- table_name → set
      fk_cache = {},      -- table_name → fk_info[]
      nodes = {},         -- flat rendered node list
      filter = nil,       -- search filter string
    }
  end
  return _states[url]
end

--- Fetch table list for a persistent DB state.
local function fetch_tables(state)
  local tables, err = db.list_tables(state.url)
  if not tables then
    vim.notify("Grip: " .. (err or "Failed to list tables"), vim.log.levels.ERROR)
    return
  end
  state.items = tables
end

--- Fetch column schema for a file-as-table URL (Parquet, CSV, remote file).
--- Uses DuckDB's DESCRIBE to get column names and types without needing a DB.
local function fetch_file_schema(state)
  local file_url = state.url
  local safe_url = file_url:gsub("'", "''")
  local sql = string.format("DESCRIBE SELECT * FROM '%s' LIMIT 0", safe_url)
  local result, err = db.query(sql, "duckdb::memory:")
  if not result then
    vim.notify("Grip: could not read file schema: " .. (err or "unknown"), vim.log.levels.WARN)
    state.file_cols = {}
    state.items = {}
    return
  end
  local cols = {}
  for _, row in ipairs(result.rows or {}) do
    local col_name  = type(row) == "table" and (row.column_name  or row[1]) or row
    local col_type  = type(row) == "table" and (row.column_type  or row[2]) or ""
    if col_name and col_name ~= "" then
      table.insert(cols, { column_name = col_name, data_type = col_type })
    end
  end
  state.file_cols = cols
  state.items = {}  -- Mark as fetched (empty = no DB tables, which is correct)
end

--- Fetch column info for a table (lazy, cached).
local function ensure_columns(state, table_name)
  if state.col_cache[table_name] then return end

  local cols = db.get_column_info(table_name, state.url)
  state.col_cache[table_name] = cols or {}

  local pks = db.get_primary_keys(table_name, state.url)
  local pk_set = {}
  for _, pk in ipairs(pks or {}) do pk_set[pk] = true end
  state.pk_cache[table_name] = pk_set

  local fks = db.get_foreign_keys(table_name, state.url)
  local fk_map = {}
  for _, fk in ipairs(fks or {}) do fk_map[fk.column] = fk.ref_table end
  state.fk_cache[table_name] = fk_map
end

--- Build flat node list from state.
local function build_nodes(state)
  local nodes = {}

  -- File-as-table mode: show columns of the file directly, no DB schema needed
  if state.file_cols then
    local fname = state.url:match("[^/\\]+$") or state.url
    local expanded = state.expanded["__file__"] ~= false  -- default expanded
    table.insert(nodes, { kind = "header", text = "File" })
    table.insert(nodes, {
      kind = "table", name = fname, expanded = expanded,
      is_file = true, file_key = "__file__",
    })
    if expanded then
      for _, col in ipairs(state.file_cols) do
        table.insert(nodes, {
          kind = "column",
          name = col.column_name,
          dtype = abbrev_type(col.data_type),
          pk = false, fk = false,
          table_name = "__file__",
          is_file = true,
        })
      end
    end
    state.nodes = nodes
    return nodes
  end

  if not state.items then return nodes end

  local tables = {}
  local views = {}
  for _, item in ipairs(state.items) do
    if state.filter then
      if not item.name:lower():find(state.filter:lower(), 1, true) then
        goto continue
      end
    end
    if item.type == "view" then
      table.insert(views, item)
    else
      table.insert(tables, item)
    end
    ::continue::
  end

  -- Tables section
  if #tables > 0 then
    table.insert(nodes, { kind = "header", text = "Tables (" .. #tables .. ")" })
    for _, item in ipairs(tables) do
      local expanded = state.expanded[item.name] or false
      table.insert(nodes, { kind = "table", name = item.name, type = item.type, expanded = expanded })

      if expanded then
        ensure_columns(state, item.name)
        local cols = state.col_cache[item.name] or {}
        local pk_set = state.pk_cache[item.name] or {}
        local fk_map = state.fk_cache[item.name] or {}

        for _, col in ipairs(cols) do
          local is_pk = pk_set[col.column_name] or false
          local is_fk = fk_map[col.column_name] ~= nil
          table.insert(nodes, {
            kind = "column",
            name = col.column_name,
            dtype = abbrev_type(col.data_type),
            pk = is_pk,
            fk = is_fk,
            fk_ref = fk_map[col.column_name],
            table_name = item.name,
          })
        end
      end
    end
  end

  -- Views section
  if #views > 0 then
    if #tables > 0 then
      table.insert(nodes, { kind = "sep" })
    end
    table.insert(nodes, { kind = "header", text = "Views (" .. #views .. ")" })
    for _, item in ipairs(views) do
      local expanded = state.expanded[item.name] or false
      table.insert(nodes, { kind = "table", name = item.name, type = item.type, expanded = expanded })

      if expanded then
        ensure_columns(state, item.name)
        local cols = state.col_cache[item.name] or {}
        for _, col in ipairs(cols) do
          table.insert(nodes, {
            kind = "column",
            name = col.column_name,
            dtype = abbrev_type(col.data_type),
            pk = false,
            fk = false,
            table_name = item.name,
          })
        end
      end
    end
  end

  state.nodes = nodes
  return nodes
end

--- Render nodes into buffer lines + highlights.
local function render(state)
  if not _sidebar_bufnr or not vim.api.nvim_buf_is_valid(_sidebar_bufnr) then return end

  local nodes = build_nodes(state)
  local lines = {}
  local highlights = {}

  -- Title: file name for file-as-table, connection name for DB connections
  local title
  if state.file_cols ~= nil then
    title = state.url:match("[^/\\]+$") or state.url
    if #title > 34 then title = "…" .. title:sub(-33) end
  else
    local connections = require("dadbod-grip.connections")
    local current = connections.current()
    title = current and current.name or state.url:match("^%w+://[^/]*/?([^?]*)") or state.url
  end
  table.insert(lines, " " .. title)
  table.insert(highlights, { line = 0, col = 0, end_col = #lines[1], hl = "GripBorder" })
  table.insert(lines, "")

  if state.filter then
    table.insert(lines, " / " .. state.filter)
    table.insert(highlights, { line = #lines - 1, col = 0, end_col = #lines[#lines], hl = "Search" })
    table.insert(lines, "")
  end

  for _, node in ipairs(nodes) do
    if node.kind == "header" then
      table.insert(lines, " " .. node.text)
      table.insert(highlights, { line = #lines - 1, col = 0, end_col = #lines[#lines], hl = "GripHeader" })
    elseif node.kind == "table" then
      local arrow = node.expanded and " ▼ " or " ▶ "
      local max_name = SIDEBAR_MAX_WIDTH - 3  -- subtract arrow chars
      local display_name = #node.name > max_name
          and ("…" .. node.name:sub(-(max_name - 1))) or node.name
      table.insert(lines, arrow .. display_name)
      -- No special hl for table names — keep it clean
    elseif node.kind == "column" then
      local prefix
      if node.pk and node.fk then prefix = "   🔑🔗"
      elseif node.pk then prefix = "   🔑 "
      elseif node.fk then prefix = "   🔗 "
      else prefix = "      " end
      local pad = string.rep(" ", math.max(1, 16 - #node.name))
      local line = prefix .. " " .. node.name .. pad .. node.dtype
      table.insert(lines, line)
      -- Highlight type dim
      local type_start = #prefix + 1 + #node.name + #pad
      table.insert(highlights, { line = #lines - 1, col = type_start, end_col = #lines[#lines], hl = "GripReadonly" })
      if node.pk then
        table.insert(highlights, { line = #lines - 1, col = 3, end_col = 3 + #"🔑", hl = "GripBoolTrue" })
      end
      if node.fk then
        local fk_start = node.pk and 3 + #"🔑" or 3
        table.insert(highlights, { line = #lines - 1, col = fk_start, end_col = fk_start + #"🔗", hl = "GripUrl" })
      end
    elseif node.kind == "sep" then
      table.insert(lines, "")
    end
  end

  if #nodes == 0 and state.items then
    table.insert(lines, "")
    table.insert(lines, " (no tables found)")
    table.insert(highlights, { line = #lines - 1, col = 0, end_col = #lines[#lines], hl = "GripReadonly" })
  end

  -- Hint line at bottom (wrap for narrow sidebars)
  table.insert(lines, "")
  local sw = math.max(SIDEBAR_MIN_WIDTH, math.min(SIDEBAR_MAX_WIDTH, math.floor(vim.o.columns * SIDEBAR_WIDTH_RATIO)))
  if sw >= 40 then
    table.insert(lines, " CR:open  go:tables  q:query  gq:saved  gw:grid  gc:conn  /:filter  F:clear  ?:help")
    table.insert(highlights, { line = #lines - 1, col = 0, end_col = #lines[#lines], hl = "GripReadonly" })
  else
    table.insert(lines, " CR:open  go:tables  q:query  gq:saved  gw:grid")
    table.insert(highlights, { line = #lines - 1, col = 0, end_col = #lines[#lines], hl = "GripReadonly" })
    table.insert(lines, " gc:conn  /:filter  F:clear  ?:help")
    table.insert(highlights, { line = #lines - 1, col = 0, end_col = #lines[#lines], hl = "GripReadonly" })
  end

  vim.bo[_sidebar_bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(_sidebar_bufnr, 0, -1, false, lines)
  vim.bo[_sidebar_bufnr].modifiable = false

  -- Apply highlights
  local ns = vim.api.nvim_create_namespace("grip_schema")
  vim.api.nvim_buf_clear_namespace(_sidebar_bufnr, ns, 0, -1)
  for _, hl in ipairs(highlights) do
    pcall(vim.api.nvim_buf_add_highlight, _sidebar_bufnr, ns, hl.hl, hl.line, hl.col, hl.end_col)
  end
end

--- Get the node at the current cursor line.
local function node_at_cursor(state)
  if not _sidebar_winid or not vim.api.nvim_win_is_valid(_sidebar_winid) then return nil end
  local cursor = vim.api.nvim_win_get_cursor(_sidebar_winid)
  local line = cursor[1]
  -- Account for title line + blank line + optional filter lines
  local offset = 2
  if state.filter then offset = offset + 2 end
  local node_idx = line - offset
  if node_idx >= 1 and node_idx <= #state.nodes then
    return state.nodes[node_idx]
  end
  return nil
end

--- Find the best non-sidebar window to reuse for a new grid.
--- Prefers an existing grip grid window over the query pad.
local function find_right_win()
  local view = require("dadbod-grip.view")
  local fallback = nil
  for _, winid in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local bufnr = vim.api.nvim_win_get_buf(winid)
    if bufnr ~= _sidebar_bufnr then
      -- Prefer a grip grid window
      if view._sessions[bufnr] then
        return winid
      end
      if not fallback then fallback = winid end
    end
  end
  return fallback
end

--- Open a table in a grip grid, reusing the adjacent window.
local function open_table(table_name, url)
  local grip = require("dadbod-grip")
  local target_win = find_right_win()
  if target_win then
    vim.api.nvim_set_current_win(target_win)
  end
  grip.open(table_name, url, { reuse_win = target_win })
end

--- Open a table in a new split (explicit second grid).
local function open_table_split(table_name, url)
  local grip = require("dadbod-grip")
  local target_win = find_right_win()
  if target_win then
    vim.api.nvim_set_current_win(target_win)
  end
  grip.open(table_name, url, { force_split = true })
end

--- Line number offset for node list (title + blank [+ filter + blank]).
local function node_offset(state)
  return state.filter and 4 or 2
end

--- Move sidebar cursor to first table node.
local function jump_to_first_table(state)
  if not _sidebar_winid or not vim.api.nvim_win_is_valid(_sidebar_winid) then return end
  local offset = node_offset(state)
  for i, node in ipairs(state.nodes) do
    if node.kind == "table" then
      pcall(vim.api.nvim_win_set_cursor, _sidebar_winid, { offset + i, 0 })
      return
    end
  end
end

--- Navigate to next (+1) or prev (-1) table node, wrapping at ends.
local function jump_to_next_table(state, direction)
  if not _sidebar_winid or not vim.api.nvim_win_is_valid(_sidebar_winid) then return end
  local offset = node_offset(state)
  local cur_line = vim.api.nvim_win_get_cursor(_sidebar_winid)[1]
  local tlines = {}
  for i, node in ipairs(state.nodes) do
    if node.kind == "table" then table.insert(tlines, offset + i) end
  end
  if #tlines == 0 then return end
  if direction > 0 then
    for _, ln in ipairs(tlines) do
      if ln > cur_line then pcall(vim.api.nvim_win_set_cursor, _sidebar_winid, { ln, 0 }); return end
    end
    pcall(vim.api.nvim_win_set_cursor, _sidebar_winid, { tlines[1], 0 })
  else
    for i = #tlines, 1, -1 do
      if tlines[i] < cur_line then pcall(vim.api.nvim_win_set_cursor, _sidebar_winid, { tlines[i], 0 }); return end
    end
    pcall(vim.api.nvim_win_set_cursor, _sidebar_winid, { tlines[#tlines], 0 })
  end
end

--- Set up buffer-local keymaps.
local function setup_keymaps(url)
  local buf = _sidebar_bufnr
  local function map(key, fn)
    vim.keymap.set("n", key, fn, { buffer = buf, silent = true })
  end

  local state = get_state(url)

  -- Open table / expand column (reuses existing grid window)
  map("<CR>", function()
    local node = node_at_cursor(state)
    if not node then return end
    if node.is_file then
      if node.kind == "table" then
        -- File table node: focus the grid (or re-open it)
        local target_win = find_right_win()
        if target_win then
          vim.api.nvim_set_current_win(target_win)
        else
          require("dadbod-grip").open(url, nil, {})
        end
      else
        -- File column node: collapse/expand parent
        state.expanded["__file__"] = not state.expanded["__file__"]
        render(state)
      end
    elseif node.kind == "table" then
      open_table(node.name, url)
    elseif node.kind == "column" and node.table_name then
      open_table(node.table_name, url)
    end
  end)

  -- Open table in new split (explicit second grid)
  map("<S-CR>", function()
    local node = node_at_cursor(state)
    if not node then return end
    if node.is_file then return end  -- file nodes have no separate split action
    if node.kind == "table" then
      open_table_split(node.name, url)
    elseif node.kind == "column" and node.table_name then
      open_table_split(node.table_name, url)
    end
  end)

  -- Expand
  map("l", function()
    local node = node_at_cursor(state)
    if not node or node.kind ~= "table" or node.expanded then return end
    local key = node.file_key or node.name
    state.expanded[key] = true
    render(state)
  end)
  map("zo", function()
    local node = node_at_cursor(state)
    if node and node.kind == "table" then
      state.expanded[node.name] = true
      render(state)
    end
  end)

  -- Collapse
  map("h", function()
    local node = node_at_cursor(state)
    if not node then return end
    if node.kind == "table" and node.expanded then
      local key = node.file_key or node.name
      state.expanded[key] = false
      render(state)
    elseif node.kind == "column" and node.table_name then
      local key = node.file_key and "__file__" or node.table_name
      state.expanded[key] = false
      render(state)
    end
  end)
  map("zc", function()
    local node = node_at_cursor(state)
    if not node or node.kind ~= "table" then return end
    local key = node.file_key or node.name
    state.expanded[key] = false
    render(state)
  end)

  -- Expand all
  map("L", function()
    if not state.items then return end
    for _, item in ipairs(state.items) do
      state.expanded[item.name] = true
    end
    render(state)
  end)

  -- Collapse all
  map("H", function()
    for k in pairs(state.expanded) do
      state.expanded[k] = false
    end
    render(state)
  end)

  -- Filter/search — vim.fn.input() avoids dressing/noice float interception
  map("/", function()
    local CANCEL = "\0"
    local ok, input = pcall(vim.fn.input, { prompt = "Filter: ", default = state.filter or "", cancelreturn = CANCEL })
    if not ok or input == CANCEL then return end
    state.filter = (input ~= "") and input or nil
    render(state)
    if state.filter then
      vim.schedule(function() jump_to_first_table(state) end)
    end
  end)

  -- F: clear filter and jump to first table
  map("F", function()
    state.filter = nil
    render(state)
    vim.schedule(function() jump_to_first_table(state) end)
  end)

  -- n/N: navigate between table nodes (wraps)
  map("n", function() jump_to_next_table(state, 1) end)
  map("N", function() jump_to_next_table(state, -1) end)

  -- Refresh
  map("r", function()
    state.items = nil
    state.col_cache = {}
    state.pk_cache = {}
    state.fk_cache = {}
    fetch_tables(state)
    render(state)
  end)

  -- Yank table/column name to clipboard
  map("y", function()
    local node = node_at_cursor(state)
    if not node then return end
    local name = (node.kind == "table" and node.name)
              or (node.kind == "column" and node.name)
              or nil
    if name then
      vim.fn.setreg("+", name)
      vim.fn.setreg('"', name)
      vim.notify("Copied: " .. name, vim.log.levels.INFO)
    end
  end)

  -- gT / gt: table picker
  local function _pick_table()
    require("dadbod-grip.picker").pick_table(url, function(name) open_table(name, url) end)
  end
  map("gT", _pick_table)
  map("gt", _pick_table)

  -- go: open table under cursor with smart ORDER BY (latest rows first)
  map("go", function()
    local node = node_at_cursor(state)
    if not node then return end

    -- File nodes: focus grid or re-open the file (no ORDER BY for file-as-table)
    if node.is_file then
      local target_win = find_right_win()
      if target_win then
        vim.api.nvim_set_current_win(target_win)
      else
        require("dadbod-grip").open(url, nil, {})
      end
      return
    end

    local tbl = (node.kind == "table" and node.name)
             or (node.kind == "column" and node.table_name)
    if not tbl then return end

    ensure_columns(state, tbl)
    local cols   = state.col_cache[tbl] or {}
    local pk_set = state.pk_cache[tbl]  or {}

    -- Build lowercase name → original-case map for O(1) lookup
    local col_map = {}
    for _, col in ipairs(cols) do col_map[col.column_name:lower()] = col.column_name end

    -- Prefer timestamp columns so the grid opens showing the latest rows first
    local order_col
    for _, ts in ipairs({ "created_at", "inserted_at", "date_created", "created_on",
                          "updated_at", "modified_at", "date_updated", "updated_on",
                          "timestamp", "ts" }) do
      if col_map[ts] then order_col = col_map[ts]; break end
    end

    -- Fall back to any PK column
    if not order_col then
      for _, col in ipairs(cols) do
        if pk_set[col.column_name] then order_col = col.column_name; break end
      end
    end

    local grip = require("dadbod-grip")
    local target_win = find_right_win()
    if target_win then vim.api.nvim_set_current_win(target_win) end
    local arg = order_col
      and ("SELECT * FROM " .. tbl .. " ORDER BY " .. order_col .. " DESC")
      or tbl
    grip.open(arg, url, { reuse_win = target_win })
  end)

  -- gb: close sidebar (from inside; gb elsewhere opens/focuses it)
  map("gb", function() M.close() end)

  -- Query pad
  map("q", function()
    local query_pad = require("dadbod-grip.query_pad")
    query_pad.open(url)
  end)

  -- Load saved query into query pad
  map("gq", function()
    local saved = require("dadbod-grip.saved")
    saved.pick(function(sql_content)
      require("dadbod-grip.query_pad").open(url, { initial_sql = sql_content })
    end)
  end)

  -- Query history → load into query pad
  map("gh", function()
    require("dadbod-grip.history").pick(function(sql_content)
      require("dadbod-grip.query_pad").open(url, { initial_sql = sql_content })
    end)
  end)

  -- Jump to grid window
  map("gw", function()
    local view = require("dadbod-grip.view")
    for _, winid in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      local wbuf = vim.api.nvim_win_get_buf(winid)
      if view._sessions[wbuf] then
        vim.api.nvim_set_current_win(winid)
        return
      end
    end
    vim.notify("No grid window open", vim.log.levels.INFO)
  end)

  -- Switch connection (gC, gc, and C-g)
  local function _pick_conn()
    require("dadbod-grip.connections").pick()
  end
  map("gC", _pick_conn)
  map("gc", _pick_conn)
  map("<C-g>", _pick_conn)

  -- DDL: drop table
  map("D", function()
    local node = node_at_cursor(state)
    if not node or node.kind ~= "table" then
      vim.notify("Move cursor to a table", vim.log.levels.INFO)
      return
    end
    local ddl = require("dadbod-grip.ddl")
    ddl.drop_table(node.name, url, function()
      state.items = nil
      state.col_cache = {}
      fetch_tables(state)
      render(state)
    end)
  end)

  -- DDL: create table
  map("+", function()
    local ddl = require("dadbod-grip.ddl")
    ddl.create_table(url, function()
      state.items = nil
      state.col_cache = {}
      fetch_tables(state)
      render(state)
    end)
  end)

  -- 1: table picker (mirrors grid keymap)
  map("1", _pick_table)

  -- Tab views: 2-9 open a table directly into a specific view facet
  local TAB_VIEWS = { [2]="records", [3]="history", [4]="stats", [5]="explain",
                      [6]="columns", [7]="fk", [8]="indexes", [9]="constraints" }
  for n = 2, 9 do
    local view_name = TAB_VIEWS[n]
    map(tostring(n), function()
      local node = node_at_cursor(state)
      if not node then return end
      local tbl = (node.kind == "table" and node.name)
               or (node.kind == "column" and node.table_name)
      if not tbl then return end
      local grip = require("dadbod-grip")
      local target_win = find_right_win()
      if target_win then vim.api.nvim_set_current_win(target_win) end
      grip.open(tbl, url, { reuse_win = target_win, view = view_name })
    end)
  end

  -- Close
  map("<Esc>", function() M.close() end)

  -- Help
  map("?", function()
    local lines = {
      "",
      "  Schema Browser",
      " ─────────────────────────────────────────",
      "",
      "  Navigation",
      "  j/k       Move between items",
      "  <CR>      Open table in grid (reuse win)",
      "  S-CR      Open table in new split",
      "  l / zo    Expand table columns",
      "  h / zc    Collapse table",
      "  L         Expand all",
      "  H         Collapse all",
      "  /         Filter by name",
      "  F         Clear filter",
      "",
      "  Tab Views",
      "  1         Table picker",
      "  2         Records (default)",
      "  3         Columns",
      "  4         Foreign Keys",
      "  5         Indexes",
      "  6         Constraints",
      "  7         Column Stats",
      "  8         History",
      "  9         Explain",
      "",
      "  Actions",
      "  r         Refresh schema",
      "  y         Yank table/column name",
      "  go        Open table, ORDER BY latest (created_at / PK)",
      "  gT / gt   Table picker (fuzzy finder)",
      "  gb        Close browser (gb outside: open/focus)",
      "  gw        Jump to grid",
      "  gC / gc   Switch connection",
      "  gh        Query history",
      "  gq        Saved queries",
      "  q         Query pad",
      "  D         Drop table (confirm)",
      "  +         Create table",
      "  Esc       Close sidebar",
      "  ?         Toggle this help",
      "",
      " ─────────────────────────────────────────",
      "",
      "  ╔═╦═╦═╗",
      "  ║d║b║g║  ᕦ( ᐛ )ᕤ  dadbod-grip v" .. VERSION,
      "  ╚═╩═╩═╝",
      "",
    }
    local grip_win = vim.api.nvim_get_current_win()
    local max_w = 0
    for _, line in ipairs(lines) do max_w = math.max(max_w, #line) end
    max_w = math.max(max_w + 2, 44)
    local popup_buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(popup_buf, 0, -1, false, lines)
    local win = vim.api.nvim_open_win(popup_buf, true, {
      relative = "editor",
      row = math.floor((vim.o.lines - #lines) / 2),
      col = math.floor((vim.o.columns - max_w) / 2),
      width = max_w,
      height = #lines,
      style = "minimal",
      border = "rounded",
      title = " Schema Help ",
      title_pos = "center",
      zindex = 50,
    })
    local function close()
      if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end
    end

    vim.api.nvim_create_autocmd("WinLeave", {
      buffer = popup_buf,
      once = true,
      callback = function() vim.schedule(close) end,
    })

    for _, key in ipairs({ "q", "?", "<Esc>" }) do
      vim.keymap.set("n", key, function()
        close()
        if vim.api.nvim_win_is_valid(grip_win) then
          vim.api.nvim_set_current_win(grip_win)
        end
      end, { buffer = popup_buf })
    end
  end)
end

--- Compute sidebar width.
local function sidebar_width()
  local w = math.floor(vim.o.columns * SIDEBAR_WIDTH_RATIO)
  return math.max(SIDEBAR_MIN_WIDTH, math.min(SIDEBAR_MAX_WIDTH, w))
end

--- Open or toggle the schema sidebar.
-- From outside the sidebar: focus it (open if needed).
-- From inside the sidebar: close it.
function M.toggle(url)
  if _sidebar_winid and vim.api.nvim_win_is_valid(_sidebar_winid) then
    if vim.api.nvim_get_current_win() == _sidebar_winid then
      -- Already in sidebar → close (toggle off)
      M.close()
    else
      -- Not in sidebar → just focus it
      vim.api.nvim_set_current_win(_sidebar_winid)
    end
    return
  end

  if not url then
    local db_mod = require("dadbod-grip.db")
    url = db_mod.get_url()
    if not url then
      vim.notify("Grip: no database connection. Use :GripConnect or set vim.g.db.", vim.log.levels.WARN)
      return
    end
  end

  local state = get_state(url)

  -- Create buffer if needed
  if not _sidebar_bufnr or not vim.api.nvim_buf_is_valid(_sidebar_bufnr) then
    _sidebar_bufnr = vim.api.nvim_create_buf(false, true)
    vim.bo[_sidebar_bufnr].buftype = "nofile"
    vim.bo[_sidebar_bufnr].bufhidden = "hide"
    vim.bo[_sidebar_bufnr].swapfile = false
    vim.bo[_sidebar_bufnr].filetype = "grip_schema"
    vim.api.nvim_buf_set_name(_sidebar_bufnr, "grip://schema")
    setup_keymaps(url)
  end

  -- Open left split
  local width = sidebar_width()
  vim.cmd("topleft vertical " .. width .. "split")
  _sidebar_winid = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(_sidebar_winid, _sidebar_bufnr)

  -- Window options
  vim.wo[_sidebar_winid].number = false
  vim.wo[_sidebar_winid].relativenumber = false
  vim.wo[_sidebar_winid].signcolumn = "no"
  vim.wo[_sidebar_winid].cursorline = true
  vim.wo[_sidebar_winid].winfixwidth = true
  vim.wo[_sidebar_winid].wrap = false

  -- Fetch schema if not cached
  if not state.items then
    if is_file_url(url) then
      fetch_file_schema(state)
    else
      fetch_tables(state)
    end
  end

  render(state)
end

--- Close the schema sidebar.
function M.close()
  if _sidebar_winid and vim.api.nvim_win_is_valid(_sidebar_winid) then
    vim.api.nvim_win_close(_sidebar_winid, true)
  end
  _sidebar_winid = nil
end

function M.is_open()
  return _sidebar_winid ~= nil and vim.api.nvim_win_is_valid(_sidebar_winid)
end

function M.get_winid()
  if _sidebar_winid and vim.api.nvim_win_is_valid(_sidebar_winid) then
    return _sidebar_winid
  end
  return nil
end

--- Get first non-sidebar window (the right content area).
function M.get_right_win()
  if not M.is_open() then return nil end
  for _, winid in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local bufnr = vim.api.nvim_win_get_buf(winid)
    if bufnr ~= _sidebar_bufnr then
      return winid
    end
  end
  return nil
end

--- Refresh sidebar if visible (e.g., after connection switch).
function M.refresh(url)
  if not _sidebar_winid or not vim.api.nvim_win_is_valid(_sidebar_winid) then return end
  if not url then return end
  local state = get_state(url)
  state.items = nil
  state.col_cache = {}
  state.pk_cache = {}
  state.fk_cache = {}
  fetch_tables(state)
  -- Re-setup keymaps for new URL
  if _sidebar_bufnr and vim.api.nvim_buf_is_valid(_sidebar_bufnr) then
    setup_keymaps(url)
  end
  render(state)
end

return M
