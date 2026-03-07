-- ui_spec.lua: unit tests for ui.blocking()
dofile("tests/minimal_init.lua")
local ui = require("dadbod-grip.ui")

local pass, fail = 0, 0
local function test(name, fn)
  local ok, err = pcall(fn)
  if ok then pass = pass + 1
  else fail = fail + 1; print("FAIL: " .. name .. ": " .. tostring(err)) end
end
local function eq(a, b, msg)
  assert(a == b, (msg or "") .. ": expected " .. tostring(b) .. ", got " .. tostring(a))
end

local function win_count()
  return #vim.api.nvim_list_wins()
end

test("blocking: returns single value", function()
  local result = ui.blocking("test", function() return 42 end)
  eq(result, 42, "return value")
end)

test("blocking: returns multiple values", function()
  local a, b, c = ui.blocking("test", function() return 1, 2, 3 end)
  eq(a, 1, "first"); eq(b, 2, "second"); eq(c, 3, "third")
end)

test("blocking: no extra windows after success", function()
  local before = win_count()
  ui.blocking("test", function() return "ok" end)
  local after = win_count()
  eq(after, before, "window count unchanged after success")
end)

test("blocking: no extra windows after error", function()
  local before = win_count()
  pcall(ui.blocking, "test", function() error("intentional") end)
  local after = win_count()
  eq(after, before, "window count unchanged after error")
end)

test("blocking: error is re-raised", function()
  local ok, err = pcall(ui.blocking, "test", function() error("boom") end)
  eq(ok, false, "should error")
  assert(tostring(err):find("boom"), "error msg should contain 'boom'")
end)

test("blocking: nil return values handled", function()
  local a, b = ui.blocking("test", function() return nil, nil end)
  eq(a, nil, "first nil")
  eq(b, nil, "second nil")
end)

print(string.format("ui_spec: %d passed, %d failed", pass, fail))
if fail > 0 then os.exit(1) end
