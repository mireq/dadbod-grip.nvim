-- db.lua — I/O boundary. Only module that talks to postgres.
-- All functions return (result, err). Never throw.

local M = {}

local DEFAULT_TIMEOUT = 10000  -- ms

-- Retrieve the connection URL from buffer-local or global dadbod var.
local function get_url(url)
  if url and url ~= "" then return url end
  local buf_url = vim.b.db
  if buf_url and buf_url ~= "" then return buf_url end
  local global_url = vim.g.db
  if global_url and global_url ~= "" then return global_url end
  return nil, "No database connection. Open DBUI first or set vim.g.db."
end

-- Run psql and return stdout, stderr, exit code.
local function psql(url, sql, timeout_ms)
  local result = vim.system(
    { "psql", url, "--no-password", "-A", "-F", "|", "--csv", "-c", sql },
    { text = true, timeout = timeout_ms or DEFAULT_TIMEOUT }
  ):wait()
  return result.stdout or "", result.stderr or "", result.code
end

-- Parse CSV output from psql --csv into rows + columns.
-- Returns {columns=[], rows=[[...]]} or nil, err.
local function parse_csv(raw)
  if not raw or raw == "" then
    return { columns = {}, rows = {} }
  end

  local lines = {}
  for line in (raw .. "\n"):gmatch("([^\n]*)\n") do
    if line ~= "" then table.insert(lines, line) end
  end

  if #lines == 0 then return { columns = {}, rows = {} } end

  -- Parse a single CSV line respecting quoted fields.
  local function parse_line(line)
    local fields = {}
    local i = 1
    while i <= #line do
      if line:sub(i, i) == '"' then
        -- Quoted field
        local field = ""
        i = i + 1
        while i <= #line do
          local ch = line:sub(i, i)
          if ch == '"' then
            if line:sub(i + 1, i + 1) == '"' then
              field = field .. '"'
              i = i + 2
            else
              i = i + 1
              break
            end
          else
            field = field .. ch
            i = i + 1
          end
        end
        table.insert(fields, field)
        if line:sub(i, i) == "," then i = i + 1 end
      else
        -- Unquoted field
        local start = i
        while i <= #line and line:sub(i, i) ~= "," do i = i + 1 end
        table.insert(fields, line:sub(start, i - 1))
        if line:sub(i, i) == "," then i = i + 1 end
      end
    end
    return fields
  end

  local columns = parse_line(lines[1])
  local rows = {}
  for li = 2, #lines do
    -- psql appends "(N rows)" summary line — skip it
    if not lines[li]:match("^%(%d+ rows?%)$") then
      local fields = parse_line(lines[li])
      -- Pad to column count
      while #fields < #columns do table.insert(fields, "") end
      table.insert(rows, fields)
    end
  end

  return { columns = columns, rows = rows }
end

-- M.query(sql, url) → {rows, columns, primary_keys}, err
function M.query(sql, url)
  local conn, conn_err = get_url(url)
  if not conn then return nil, conn_err end

  -- Check psql exists
  if vim.fn.executable("psql") == 0 then
    return nil, "psql not found. Install postgresql-client."
  end

  local stdout, stderr, code = psql(conn, sql)

  if code ~= 0 then
    local msg = stderr ~= "" and stderr or ("psql exited with code " .. code)
    return nil, msg
  end

  local parsed, parse_err = parse_csv(stdout)
  if not parsed then return nil, parse_err end

  return {
    rows = parsed.rows,
    columns = parsed.columns,
    primary_keys = {},  -- filled by get_primary_keys() in init
  }, nil
end

-- M.get_primary_keys(table_name, url) → []string, err
function M.get_primary_keys(table_name, url)
  local conn, conn_err = get_url(url)
  if not conn then return nil, conn_err end

  -- Handle schema-qualified names (schema.table)
  local schema, tbl = table_name:match("^([^.]+)%.(.+)$")
  if not schema then
    schema = "public"
    tbl = table_name
  end

  local sql = string.format([[
    SELECT kcu.column_name
    FROM information_schema.table_constraints tc
    JOIN information_schema.key_column_usage kcu
      ON tc.constraint_name = kcu.constraint_name
      AND tc.table_schema = kcu.table_schema
    WHERE tc.constraint_type = 'PRIMARY KEY'
      AND tc.table_schema = '%s'
      AND tc.table_name = '%s'
    ORDER BY kcu.ordinal_position
  ]], schema:gsub("'", "''"), tbl:gsub("'", "''"))

  local stdout, stderr, code = psql(conn, sql)
  if code ~= 0 then
    return {}, stderr ~= "" and stderr or "Failed to query primary keys"
  end

  local parsed = parse_csv(stdout)
  if not parsed then return {} end

  local pks = {}
  for _, row in ipairs(parsed.rows) do
    if row[1] and row[1] ~= "" then
      table.insert(pks, row[1])
    end
  end
  return pks, nil
end

-- M.get_column_info(table_name, url) → [{column_name, data_type, is_nullable, column_default, constraint}], err
function M.get_column_info(table_name, url)
  local conn, conn_err = get_url(url)
  if not conn then return nil, conn_err end

  local schema, tbl = table_name:match("^([^.]+)%.(.+)$")
  if not schema then
    schema = "public"
    tbl = table_name
  end

  local info_sql = string.format([[
    SELECT
      c.column_name,
      c.data_type || COALESCE('(' || c.character_maximum_length || ')', '') AS data_type,
      c.is_nullable,
      COALESCE(c.column_default, '') AS column_default,
      COALESCE(
        (SELECT string_agg(tc.constraint_type, ', ')
         FROM information_schema.key_column_usage kcu
         JOIN information_schema.table_constraints tc
           ON tc.constraint_name = kcu.constraint_name
           AND tc.table_schema = kcu.table_schema
         WHERE kcu.table_schema = '%s'
           AND kcu.table_name = '%s'
           AND kcu.column_name = c.column_name),
        ''
      ) AS constraints
    FROM information_schema.columns c
    WHERE c.table_schema = '%s'
      AND c.table_name = '%s'
    ORDER BY c.ordinal_position
  ]], schema:gsub("'", "''"), tbl:gsub("'", "''"),
      schema:gsub("'", "''"), tbl:gsub("'", "''"))

  local stdout, stderr, code = psql(conn, info_sql)
  if code ~= 0 then
    return nil, stderr ~= "" and stderr or "Failed to query column info"
  end

  local parsed = parse_csv(stdout)
  if not parsed then return nil, "Failed to parse column info" end

  local cols = {}
  for _, row in ipairs(parsed.rows) do
    table.insert(cols, {
      column_name = row[1] or "",
      data_type = row[2] or "",
      is_nullable = row[3] or "",
      column_default = row[4] or "",
      constraints = row[5] or "",
    })
  end
  return cols, nil
end

-- M.execute(sql, url) → {affected, message}, err
function M.execute(sql, url)
  local conn, conn_err = get_url(url)
  if not conn then return nil, conn_err end

  if vim.fn.executable("psql") == 0 then
    return nil, "psql not found. Install postgresql-client."
  end

  local stdout, stderr, code = psql(conn, sql)

  if code ~= 0 then
    local msg = stderr ~= "" and stderr or ("psql exited with code " .. code)
    return nil, msg
  end

  -- Parse "UPDATE 1" / "INSERT 0 1" / "DELETE 2" from stdout
  local n = stdout:match("UPDATE (%d+)") or
            stdout:match("INSERT %d+ (%d+)") or
            stdout:match("DELETE (%d+)") or
            "0"
  return { affected = tonumber(n) or 0, message = stdout:gsub("%s+$", "") }, nil
end

return M
