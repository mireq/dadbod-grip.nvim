-- filters.lua -- saved filter presets per table.
-- Stored in .grip/filters.json keyed by table name.
-- Picker uses telescope -> fzf-lua -> vim.ui.select.

local M = {}

-- ── storage helpers ─────────────────────────────────────────────────────

local function project_root()
  local dir = vim.fn.getcwd()
  while dir ~= "/" do
    if vim.fn.isdirectory(dir .. "/.git") == 1 or vim.fn.isdirectory(dir .. "/.grip") == 1 then
      return dir
    end
    dir = vim.fn.fnamemodify(dir, ":h")
  end
  return vim.fn.getcwd()
end

local function filters_path()
  return project_root() .. "/.grip/filters.json"
end

local function ensure_dir()
  local dir = project_root() .. "/.grip"
  if vim.fn.isdirectory(dir) == 0 then
    vim.fn.mkdir(dir, "p")
  end
end

--- Read all filter presets from disk. Mockable via M._read_all.
function M._read_all()
  local path = filters_path()
  if vim.fn.filereadable(path) == 0 then return {} end
  local raw = table.concat(vim.fn.readfile(path), "\n")
  local ok, data = pcall(vim.fn.json_decode, raw)
  if not ok or type(data) ~= "table" then return {} end
  return data
end

--- Write all filter presets to disk. Mockable via M._write_all.
function M._write_all(data)
  ensure_dir()
  local json = vim.fn.json_encode(data)
  vim.fn.writefile({ json }, filters_path())
end

-- ── public API ──────────────────────────────────────────────────────────

--- List presets for a table. Returns { {name, clause}, ... }.
function M.list(table_name)
  local all = M._read_all()
  local entries = all[table_name]
  if type(entries) ~= "table" then return {} end
  local result = {}
  for _, e in ipairs(entries) do
    if type(e) == "table" and e.name and e.clause then
      table.insert(result, { name = e.name, clause = e.clause })
    end
  end
  return result
end

--- Save a filter preset for a table.
function M.save(table_name, name, clause)
  if not table_name or table_name == "" then
    vim.notify("Grip: no table context for filter preset", vim.log.levels.ERROR)
    return
  end
  if not name or name == "" then
    vim.notify("Grip: preset name required", vim.log.levels.ERROR)
    return
  end
  local all = M._read_all()
  if type(all[table_name]) ~= "table" then all[table_name] = {} end
  -- Replace existing preset with same name, or append
  local found = false
  for i, e in ipairs(all[table_name]) do
    if e.name == name then
      all[table_name][i] = { name = name, clause = clause }
      found = true
      break
    end
  end
  if not found then
    table.insert(all[table_name], { name = name, clause = clause })
  end
  M._write_all(all)
  vim.notify("Grip: saved filter preset \"" .. name .. "\" for " .. table_name, vim.log.levels.INFO)
end

--- Delete a preset by name.
function M.delete(table_name, name)
  local all = M._read_all()
  if type(all[table_name]) ~= "table" then return end
  local filtered = {}
  for _, e in ipairs(all[table_name]) do
    if e.name ~= name then table.insert(filtered, e) end
  end
  all[table_name] = #filtered > 0 and filtered or nil
  M._write_all(all)
  vim.notify("Grip: deleted filter preset \"" .. name .. "\"", vim.log.levels.INFO)
end

-- ── pickers ─────────────────────────────────────────────────────────────

local function telescope_pick(presets, callback)
  local pickers = require("telescope.pickers")
  local finders = require("telescope.finders")
  local conf = require("telescope.config").values
  local actions = require("telescope.actions")
  local action_state = require("telescope.actions.state")
  local previewers = require("telescope.previewers")

  pickers.new({}, {
    prompt_title = "Grip Filter Presets",
    finder = finders.new_table({
      results = presets,
      entry_maker = function(entry)
        return {
          value = entry,
          display = entry.name,
          ordinal = entry.name,
        }
      end,
    }),
    sorter = conf.generic_sorter({}),
    previewer = previewers.new_buffer_previewer({
      title = "WHERE clause",
      define_preview = function(self, entry)
        local lines = vim.split(entry.value.clause, "\n")
        vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, lines)
        vim.bo[self.state.bufnr].filetype = "sql"
      end,
    }),
    attach_mappings = function(prompt_bufnr)
      actions.select_default:replace(function()
        local entry = action_state.get_selected_entry()
        actions.close(prompt_bufnr)
        if entry then callback(entry.value) end
      end)
      return true
    end,
  }):find()
end

local function fzf_pick(presets, callback)
  local fzf = require("fzf-lua")
  local names = {}
  local by_name = {}
  for _, p in ipairs(presets) do
    table.insert(names, p.name)
    by_name[p.name] = p
  end

  fzf.fzf_exec(names, {
    prompt = "Grip Filters> ",
    previewer = false,
    actions = {
      ["default"] = function(selected)
        if selected and selected[1] then
          local p = by_name[selected[1]]
          if p then callback(p) end
        end
      end,
    },
  })
end

local function native_pick(presets, callback)
  local labels = {}
  for _, p in ipairs(presets) do
    table.insert(labels, p.name .. "  (" .. p.clause:sub(1, 40) .. ")")
  end

  vim.ui.select(labels, { prompt = "Load Filter Preset:" }, function(_, idx)
    if not idx then return end
    callback(presets[idx])
  end)
end

--- Open a picker to select a filter preset. Calls callback({name, clause}).
function M.pick(table_name, callback)
  local presets = M.list(table_name)
  if #presets == 0 then
    vim.notify("Grip: no filter presets for " .. (table_name or "this table"), vim.log.levels.INFO)
    return
  end

  local has_telescope = pcall(require, "telescope")
  if has_telescope then
    return telescope_pick(presets, callback)
  end

  local has_fzf = pcall(require, "fzf-lua")
  if has_fzf then
    return fzf_pick(presets, callback)
  end

  return native_pick(presets, callback)
end

return M
