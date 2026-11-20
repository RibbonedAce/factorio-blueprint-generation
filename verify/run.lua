-- verify/run.lua
-- Runs the cases of verify/cases.txt (see .agents/verification.md): each one generates a blueprint from the game's recipes with the
-- repo's own modules and checks it with the validator and the belt tracer; a case marked `refused` has to be refused. Run it from the
-- repo root with Lua 5.2:   lua52 verify/run.lua [environment]   (the environment `a` or `b`; both by default)
-- Exit code 0 when every case is as expected.

package.path = "./?.lua;./?/init.lua;" .. package.path
local harness = require("verify.harness")

local only = arg[1]

-- The cases of the file, by environment, in the order of the file.
---@return table<string, table[]>
local function read_cases()
  local by_environment = {a = {}, b = {}}
  for line in io.lines("verify/cases.txt") do
    local letter, design, item, rate, expected = line:match("^(%S+) (%S+) (%S+) (%d+) (%S+)$")
    if letter then
      table.insert(by_environment[letter], {design = design, item = item, rate = tonumber(rate), expected = expected})
    end
  end
  return by_environment
end

-- What is wrong with one case, as text, or nil.
---@param inst table
---@param case table
---@return string|nil
local function trouble_with(inst, case)
  local ok, result = pcall(inst.generate, case.item, case.rate)
  if not ok then
    return "the generator stopped: " .. tostring(result)
  end
  if case.expected == "refused" then
    return result and "was built, and should be refused" or nil
  end
  if not result then
    return "was refused, and should be built"
  end
  local problems = inst.check(result)
  return #problems > 0 and (#problems .. " problems, the first: " .. tostring(problems[1])) or nil
end

local started, total, failed = os.clock(), 0, 0
local cases = read_cases()
for _, letter in ipairs({"a", "b"}) do
  if not only or only == letter then
    local insts = harness.environment(letter)
    for _, case in ipairs(cases[letter]) do
      total = total + 1
      local trouble = trouble_with(insts[case.design], case)
      if trouble then
        failed = failed + 1
        print(string.format("%s %s %s %d: %s", letter, case.design, case.item, case.rate, trouble))
      end
    end
  end
end
print(string.format("%d cases, %d wrong, %.0f seconds", total, failed, os.clock() - started))
os.exit(failed == 0 and 0 or 1)
