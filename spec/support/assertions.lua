-- spec/support/assertions.lua
-- Custom assertions for busted's `assert`, for things luassert does not have.
-- Loaded by spec/helper.lua. Argument order follows luassert: expected first.
--
--     assert.has_item_containing("overlaps", problems)
--     assert.is_not.has_item_containing("overlaps", problems)
--     assert.has_consecutive_numbers(entities)

---@diagnostic disable-next-line: unresolved-require  -- busted's own libraries, installed with LuaRocks, not in this repo
local assert = require("luassert")
---@diagnostic disable-next-line: unresolved-require  -- as above
local say = require("say")

-- A list in which at least one string contains `text` (plain text, not a pattern).
---@param _ table  luassert's state, unused
---@param arguments any[]  {text, list}
---@return boolean
local function has_item_containing(_, arguments)
  local text, list = arguments[1], arguments[2]
  if type(text) ~= "string" or type(list) ~= "table" then
    return false
  end
  for _, item in ipairs(list) do
    if type(item) == "string" and item:find(text, 1, true) then
      return true
    end
  end
  return false
end

say:set("assertion.has_item_containing.positive", "Expected a list with an item containing:\n%s\nbut the list was:\n%s")
say:set("assertion.has_item_containing.negative", "Expected a list with NO item containing:\n%s\nbut the list was:\n%s")
assert:register("assertion", "has_item_containing", has_item_containing,
  "assertion.has_item_containing.positive", "assertion.has_item_containing.negative")

-- A list of entities whose `entity_number`s are 1, 2, 3, ... in the order of the list, as a blueprint numbers them.
---@param _ table  luassert's state, unused
---@param arguments any[]  {list}
---@return boolean
local function has_consecutive_numbers(_, arguments)
  local list = arguments[1]
  if type(list) ~= "table" then
    return false
  end
  for index, entity in ipairs(list) do
    if entity.entity_number ~= index then
      return false
    end
  end
  return true
end

say:set("assertion.has_consecutive_numbers.positive", "Expected entities numbered 1, 2, 3, ... in the order of the list, but got:\n%s")
say:set("assertion.has_consecutive_numbers.negative", "Expected entities that are NOT numbered 1, 2, 3, ... in the order of the list, but got:\n%s")
assert:register("assertion", "has_consecutive_numbers", has_consecutive_numbers,
  "assertion.has_consecutive_numbers.positive", "assertion.has_consecutive_numbers.negative")
