-- ai.lua -- AI SQL generation from natural language.
-- Multi-provider: Anthropic, OpenAI, Gemini, Ollama.
-- Schema context auto-assembled from grip metadata.

local db = require("dadbod-grip.db")
local sql_mod = require("dadbod-grip.sql")

local M = {}

local _opts = {}

-- ── providers ─────────────────────────────────────────────────────────────────

local PROVIDERS = {
  anthropic = {
    name = "Anthropic",
    default_model = "claude-haiku-4-5-20251001",
    env_var = "ANTHROPIC_API_KEY",
    build_request = function(system_prompt, question, model, api_key, base_url)
      local url = (base_url or "https://api.anthropic.com") .. "/v1/messages"
      return {
        url = url,
        headers = {
          "x-api-key: " .. api_key,
          "anthropic-version: 2023-06-01",
          "Content-Type: application/json",
        },
        body = {
          model = model,
          max_tokens = 1024,
          system = system_prompt,
          messages = {{ role = "user", content = question }},
        },
      }
    end,
    parse_response = function(body)
      if body.content and body.content[1] then
        return body.content[1].text
      end
      return nil, "Unexpected Anthropic response format"
    end,
  },
  openai = {
    name = "OpenAI",
    default_model = "gpt-4o-mini",
    env_var = "OPENAI_API_KEY",
    build_request = function(system_prompt, question, model, api_key, base_url)
      local url = (base_url or "https://api.openai.com") .. "/v1/chat/completions"
      return {
        url = url,
        headers = {
          "Authorization: Bearer " .. api_key,
          "Content-Type: application/json",
        },
        body = {
          model = model,
          messages = {
            { role = "system", content = system_prompt },
            { role = "user", content = question },
          },
          temperature = 0,
        },
      }
    end,
    parse_response = function(body)
      if body.choices and body.choices[1] and body.choices[1].message then
        return body.choices[1].message.content
      end
      return nil, "Unexpected OpenAI response format"
    end,
  },
  gemini = {
    name = "Gemini",
    default_model = "gemini-2.5-flash",
    env_var = "GEMINI_API_KEY",
    build_request = function(system_prompt, question, model, api_key, base_url)
      local url = (base_url or "https://generativelanguage.googleapis.com")
        .. "/v1beta/models/" .. model .. ":generateContent?key=" .. api_key
      return {
        url = url,
        headers = { "Content-Type: application/json" },
        body = {
          system_instruction = { parts = {{ text = system_prompt }} },
          contents = {{ parts = {{ text = question }} }},
        },
      }
    end,
    parse_response = function(body)
      if body.candidates and body.candidates[1]
        and body.candidates[1].content and body.candidates[1].content.parts then
        return body.candidates[1].content.parts[1].text
      end
      return nil, "Unexpected Gemini response format"
    end,
  },
  ollama = {
    name = "Ollama",
    default_model = "codellama",
    env_var = nil,
    build_request = function(system_prompt, question, model, _, base_url)
      local url = (base_url or "http://localhost:11434") .. "/api/chat"
      return {
        url = url,
        headers = { "Content-Type: application/json" },
        body = {
          model = model,
          stream = false,
          messages = {
            { role = "system", content = system_prompt },
            { role = "user", content = question },
          },
        },
      }
    end,
    parse_response = function(body)
      if body.message and body.message.content then
        return body.message.content
      end
      return nil, "Unexpected Ollama response format"
    end,
  },
}

-- ── configuration ─────────────────────────────────────────────────────────────

function M.setup(opts)
  _opts = vim.tbl_extend("force", {
    provider = nil,
    model = nil,
    api_key = nil,
    base_url = nil,
  }, opts or {})
end

-- ── key resolution ────────────────────────────────────────────────────────────

--- Resolve API key. Supports direct string, "env:VAR", "cmd:command".
function M.resolve_api_key(provider_name)
  local provider = PROVIDERS[provider_name]
  if not provider then return nil, "Unknown provider: " .. tostring(provider_name) end

  -- 1. Explicit config
  local key = _opts.api_key
  if key then
    if key:match("^env:") then
      local var = key:sub(5)
      local val = os.getenv(var)
      if val and val ~= "" then return val end
      return nil, "Environment variable " .. var .. " is not set"
    elseif key:match("^cmd:") then
      local cmd = key:sub(5)
      local result = vim.system({"sh", "-c", cmd}, { text = true }):wait()
      if result.code == 0 and result.stdout ~= "" then
        return vim.trim(result.stdout)
      end
      return nil, "Command failed: " .. cmd
    else
      return key
    end
  end

  -- 2. Provider's default env var
  if provider.env_var then
    local val = os.getenv(provider.env_var)
    if val and val ~= "" then return val end
  end

  -- 3. Ollama needs no key
  if provider_name == "ollama" then return "" end

  return nil, "No API key found. Set " .. (provider.env_var or "api_key in setup()") .. " or configure ai.api_key"
end

--- Auto-detect provider from available env vars.
function M.resolve_provider()
  -- 1. Explicit config always wins
  if _opts.provider then return _opts.provider end

  -- 2. Auto-detect: Anthropic > OpenAI > Gemini > Ollama
  if os.getenv("ANTHROPIC_API_KEY") and os.getenv("ANTHROPIC_API_KEY") ~= "" then return "anthropic" end
  if os.getenv("OPENAI_API_KEY") and os.getenv("OPENAI_API_KEY") ~= "" then return "openai" end
  if os.getenv("GEMINI_API_KEY") and os.getenv("GEMINI_API_KEY") ~= "" then return "gemini" end
  return "ollama"
end

-- ── schema context ────────────────────────────────────────────────────────────

--- Format one table as compact DDL. Exposed for testing.
function M._format_ddl_line(table_name, columns, pks, fks)
  local pk_set = {}
  for _, pk in ipairs(pks or {}) do pk_set[pk] = true end

  local fk_map = {}
  for _, fk in ipairs(fks or {}) do
    if fk.column_name and fk.foreign_table_name then
      fk_map[fk.column_name] = fk.foreign_table_name .. "." .. (fk.foreign_column_name or "id")
    end
  end

  local parts = {}
  for _, col in ipairs(columns or {}) do
    local name = col.column_name or ""
    local dtype = (col.data_type or ""):gsub("%s+", " ")
    local s = name .. " " .. dtype
    if pk_set[name] then s = s .. " PK" end
    if col.is_nullable == "NO" and not pk_set[name] then s = s .. " NOT NULL" end
    if fk_map[name] then s = s .. " FK->" .. fk_map[name] end
    table.insert(parts, s)
  end

  return "CREATE TABLE " .. table_name .. " (" .. table.concat(parts, ", ") .. ");"
end

--- Build schema context DDL from database metadata.
function M.build_schema_context(url, question)
  local tables, err = db.list_tables(url)
  if not tables then return "", "unknown" end

  -- Detect adapter name
  local adapter_name = "SQL"
  local u = (url or ""):lower()
  if u:match("^postgres") then adapter_name = "PostgreSQL"
  elseif u:match("^mysql") or u:match("^mariadb") then adapter_name = "MySQL"
  elseif u:match("^sqlite") then adapter_name = "SQLite"
  elseif u:match("^duckdb") then adapter_name = "DuckDB"
  end

  -- Limit tables
  local table_names = {}
  if type(tables) == "table" and tables.rows then
    for _, row in ipairs(tables.rows) do
      if row[1] then table.insert(table_names, row[1]) end
    end
  end
  if #table_names > 30 then
    -- Prioritize tables mentioned in question
    local q = (question or ""):lower()
    local mentioned = {}
    local others = {}
    for _, t in ipairs(table_names) do
      if q:find(t:lower(), 1, true) then
        table.insert(mentioned, t)
      else
        table.insert(others, t)
      end
    end
    table_names = mentioned
    for i = 1, math.min(30 - #table_names, #others) do
      table.insert(table_names, others[i])
    end
  end

  -- Build DDL for each table
  local ddl_lines = {}
  for _, tbl in ipairs(table_names) do
    local cols = db.get_column_info(tbl, url)
    local pks = db.get_primary_keys(tbl, url)
    local fks_ok, fks = pcall(db.get_foreign_keys, tbl, url)
    if not fks_ok then fks = {} end
    if cols and #cols > 0 then
      table.insert(ddl_lines, M._format_ddl_line(tbl, cols, pks, fks))
    end
  end

  return table.concat(ddl_lines, "\n"), adapter_name
end

-- ── SQL cleanup ───────────────────────────────────────────────────────────────

--- Strip markdown code fences from LLM response.
function M._strip_fences(text)
  if not text then return "" end
  local s = text
  -- Remove ```sql ... ``` or ``` ... ```
  s = s:gsub("^%s*```%w*%s*\n?", "")
  s = s:gsub("\n?%s*```%s*$", "")
  return vim.trim(s)
end

-- ── generation ────────────────────────────────────────────────────────────────

--- Generate SQL from natural language. Async via curl.
function M.generate_sql(question, url, callback)
  local provider_name = M.resolve_provider()
  local provider = PROVIDERS[provider_name]
  if not provider then
    callback(nil, "Unknown provider: " .. provider_name)
    return
  end

  local api_key, key_err = M.resolve_api_key(provider_name)
  if not api_key then
    callback(nil, key_err)
    return
  end

  local ddl, adapter_name = M.build_schema_context(url, question)
  local system_prompt = "You are a SQL expert. Generate only the SQL query, no explanation, "
    .. "no markdown code blocks. Use " .. adapter_name .. "-compatible SQL.\n\nDatabase schema:\n" .. ddl

  local model = _opts.model or provider.default_model
  local req = provider.build_request(system_prompt, question, model, api_key, _opts.base_url)

  -- Build curl args
  local curl_args = { "curl", "-s", "-X", "POST" }
  for _, h in ipairs(req.headers) do
    table.insert(curl_args, "-H")
    table.insert(curl_args, h)
  end
  table.insert(curl_args, "-d")
  table.insert(curl_args, vim.fn.json_encode(req.body))
  table.insert(curl_args, req.url)

  vim.system(curl_args, { text = true }, function(result)
    vim.schedule(function()
      if result.code ~= 0 then
        callback(nil, "curl failed: " .. (result.stderr or "unknown error"))
        return
      end

      local ok, body = pcall(vim.fn.json_decode, result.stdout)
      if not ok then
        callback(nil, "Failed to parse response JSON")
        return
      end

      -- Check for API error
      if body.error then
        local err_msg = type(body.error) == "table" and (body.error.message or "API error") or tostring(body.error)
        callback(nil, err_msg)
        return
      end

      local sql_text, parse_err = provider.parse_response(body)
      if not sql_text then
        callback(nil, parse_err or "Failed to extract SQL from response")
        return
      end

      callback(M._strip_fences(sql_text))
    end)
  end)
end

--- Open the AI ask UI: input -> generate SQL -> insert into query pad.
function M.ask(url)
  vim.ui.input({ prompt = "Ask about your data: " }, function(question)
    if not question or question == "" then return end
    vim.notify("Generating SQL...", vim.log.levels.INFO)
    M.generate_sql(question, url, function(result_sql, err)
      if err then
        vim.notify("AI: " .. err, vim.log.levels.ERROR)
        return
      end
      local query_pad = require("dadbod-grip.query_pad")
      query_pad.open(url, { initial_sql = result_sql })
    end)
  end)
end

return M
