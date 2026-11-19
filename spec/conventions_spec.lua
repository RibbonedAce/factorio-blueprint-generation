-- spec/conventions_spec.lua
-- How the code of scripts/ is written, as rules (.agents/consistency.md): each `it` is one rule, and fails with the lines that
-- break it. The rules are what was found written two ways and made one; they keep a later piece of code from writing it the
-- old way again. The helpers that read the code (spec/support/source.lua) have their own spec.
---@diagnostic disable: undefined-field  -- luassert's `assert` has fields (`assert.are`, `assert.is_nil`, ...) the editor cannot see

local source = require("spec.support.source")

local FILES = source.scripts()

-- The lines of the code of the files of scripts/ that match the pattern, as "file:line:text", but for the files named in `except`.
-- The code is the text with its comments and strings blanked out, or with its comments only when `keep_strings` is set.
---@param pattern string  a Lua pattern
---@param except? table<string, true>  file names
---@param keep_strings? boolean
---@return string[]
local function lines_breaking(pattern, except, keep_strings)
  local found = {}
  for _, file in ipairs(FILES) do
    if not (except or {})[file.name] then
      for _, line in ipairs(source.lines_matching(source.blanked(file.text, keep_strings), pattern)) do
        found[#found + 1] = file.name .. ":" .. line
      end
    end
  end
  return found
end

describe("the code of scripts/", function()
  it("converts between positions and tiles only in grid.lua: no number added to or taken from the position of an entity", function()
    local breaking = lines_breaking("%.position%.[xy]%s*[-+]%s*%d", {["grid.lua"] = true})

    assert.are.same({}, breaking)
  end)

  it("converts between positions and tiles only in grid.lua: no number added to or taken from the centre of an entity", function()
    local breaking = lines_breaking("centre%.[xy]%s*[-+]%s*%d", {["grid.lua"] = true})

    assert.are.same({}, breaking)
  end)

  it("names a tile in a set of tiles only with grid.key: no key made by joining the numbers with a comma", function()
    local breaking = lines_breaking('%.%.%s*","%s*%.%.', nil, true)

    assert.are.same({}, breaking)
  end)

  it("has no tile key of its own: grid.key is the one", function()
    local breaking = lines_breaking("^local function [%w_]*key%(", {["grid.lua"] = true})

    assert.are.same({}, breaking)
  end)

  it("names the directions once at the top of a file, not defines.direction.north in the middle of the code", function()
    local breaking = {}
    for _, line in ipairs(lines_breaking("defines%.direction%.")) do
      if not line:find("^[%w_]+%.lua:%d+:local north, east") then
        breaking[#breaking + 1] = line
      end
    end

    assert.are.same({}, breaking)
  end)

  it("appends to a list with list[#list + 1] = item, and uses table.insert only to put an item at a place", function()
    local breaking = {}
    for _, line in ipairs(lines_breaking("table%.insert%(")) do
      if not line:find(", 1, ", 1, true) then
        breaking[#breaking + 1] = line
      end
    end

    assert.are.same({}, breaking)
  end)

  it("numbers an entity only with entity_list.append, but for the numbers a block of entities gets when it is added to the blueprint", function()
    local breaking = lines_breaking("entity_number%s*=[^=]", {["entity_list.lua"] = true, ["rows.lua"] = true})

    assert.are.same({}, breaking)
  end)

  it("starts every file with its own name, as a comment", function()
    local breaking = {}
    for _, file in ipairs(FILES) do
      local first = file.text:match("^[^\n]*")
      if first ~= "-- scripts/" .. file.name and file.name ~= "types.lua" then
        breaking[#breaking + 1] = file.name .. ": " .. first
      end
    end

    assert.are.same({}, breaking)
  end)

  it("keeps every function to about 25 lines and complexity 8, but for the two builders of the window", function()
    local exceptions = {["gui.lua"] = {open_window = true, generate_blueprint = true}} -- a long run of widgets, and no spec to show a change safe
    local breaking = {}
    for _, file in ipairs(FILES) do
      for _, found in ipairs(source.functions_of(file.text)) do
        if (found.length > 25 or found.complexity > 8) and not (exceptions[file.name] or {})[found.name] then
          breaking[#breaking + 1] = string.format("%s:%s: %d lines, complexity %d", file.name, found.name, found.length, found.complexity)
        end
      end
    end

    assert.are.same({}, breaking)
  end)
end)
