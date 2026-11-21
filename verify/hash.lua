-- verify/hash.lua
-- Shows that a change leaves the blueprints of the cases as they were (see .agents/verification.md). Run from a repo root with Lua 5.2:
--   lua52 verify/hash.lua [a|b]
-- It prints one line for each case of verify/cases.txt: the case, and a hash of the blueprint (or "refused"). Run it in two trees (the
-- working tree, and a checkout of the commit before: `git worktree add <dir> HEAD`) and compare the outputs with diff. The hash is of the
-- blueprint as a set of entities: their order and their numbers depend on the order `pairs` gives, which differs from run to run.
package.path = "./?.lua;./?/init.lua;" .. package.path
local harness = require("verify.harness")

local function serialize(value)
  if type(value) ~= "table" then
    return type(value) == "string" and string.format("%q", value) or tostring(value)
  end
  local keys = {}
  for key in pairs(value) do
    keys[#keys + 1] = key
  end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  local parts = {}
  for _, key in ipairs(keys) do
    parts[#parts + 1] = tostring(key) .. "=" .. serialize(value[key])
  end
  return "{" .. table.concat(parts, ",") .. "}"
end

-- The blueprint as a set: no entity numbers (their order depends on the order `pairs` gives), the wires by the entities they join.
local function canonical(entities)
  local key_of = {}
  for _, entity in ipairs(entities) do
    key_of[entity.entity_number] = string.format("%s@%s,%s", entity.name, entity.position.x, entity.position.y)
  end
  local lines = {}
  for _, entity in ipairs(entities) do
    local copy = {}
    for key, value in pairs(entity) do
      if key ~= "entity_number" and key ~= "wires" then
        copy[key] = value
      end
    end
    local wires = {}
    for _, wire in ipairs(entity.wires or {}) do
      wires[#wires + 1] = key_of[wire[1]] .. ">" .. key_of[wire[3]]
    end
    table.sort(wires)
    copy.wires = wires
    lines[#lines + 1] = serialize(copy)
  end
  table.sort(lines)
  return table.concat(lines, "\n")
end

-- A simple 32-bit string hash, twice with different seeds, which is plenty to tell two blueprints apart.
local function hash(text)
  local a, b = 5381, 52711
  for index = 1, #text do
    local byte = text:byte(index)
    a = (a * 33 + byte) % 4294967296
    b = (b * 31 + byte * 7 + index) % 4294967296
  end
  return string.format("%08x%08x", a, b)
end

local only = arg[1]
local cases = {a = {}, b = {}}
for line in io.lines("verify/cases.txt") do
  local letter, design, recipe, rate = line:match("^(%S+) (%S+) (%S+) (%d+) (%S+)$")
  if letter then
    table.insert(cases[letter], {design = design, recipe = recipe, rate = tonumber(rate)})
  end
end
for _, letter in ipairs({"a", "b"}) do
  if not only or only == letter then
    local insts = harness.environment(letter)
    for _, case in ipairs(cases[letter]) do
      local ok, result = pcall(insts[case.design].generate, case.recipe, case.rate)
      local what = ok and (result and hash(canonical(result.entities)) or "refused") or "error"
      print(string.format("%s %s %s %d %s", letter, case.design, case.recipe, case.rate, what))
    end
  end
end
