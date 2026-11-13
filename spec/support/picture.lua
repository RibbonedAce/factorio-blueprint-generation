-- spec/support/picture.lua
-- Draws entities as text, one character per tile, so that a spec can compare what the layout built with the
-- diagram that explains it (the diagrams in the comments of the specs and of scripts/rows.lua are drawn the same way).
--
--   ^ > v <   a belt, the way it runs
--   S         a splitter, on both of its tiles (the way it faces shows in the shape: side by side or one above the other)
--   ( )       the entrance and the exit of an underground belt that runs east
--   n u       the entrance and the exit of one that runs south
--   }         an inserter, fast or long-handed or not
--   +         a pole
--   letters   the machines, as `machines` says: {[entity name] = {size = 2, glyph = "i"}}
--   .         nothing
--   ?         an entity this module does not know

local builders = require("spec.support.builders")
local grid = require("scripts.grid")

local picture = {}

local NAMES = builders.NAMES
local north, east, south, west = defines.direction.north, defines.direction.east, defines.direction.south, defines.direction.west

local BELTS = {[north] = "^", [east] = ">", [south] = "v", [west] = "<"}
local ENTRANCES = {[east] = "(", [south] = "n"}
local EXITS = {[east] = ")", [south] = "u"}

-- What each kind of entity is drawn as, by name.
local GLYPHS = {
  [NAMES.belt] = function(entity) return BELTS[entity.direction] end,
  [NAMES.splitter] = function() return "S" end,
  [NAMES.underground] = function(entity) return (entity.type == "input" and ENTRANCES or EXITS)[entity.direction] end,
  [NAMES.inserter] = function() return "}" end,
  [NAMES.fast_inserter] = function() return "}" end,
  [NAMES.long_inserter] = function() return "}" end,
  [NAMES.pole] = function() return "+" end,
  [builders.POLES.medium.name] = function() return "+" end,
}

-- How many tiles the entity covers across and along the map.
---@param entity table
---@param machines table<string, {size: integer, glyph: string}>
---@return integer width
---@return integer height
local function size_of(entity, machines)
  if entity.name == NAMES.splitter then
    local faces_along_y = entity.direction == north or entity.direction == south
    return faces_along_y and 2 or 1, faces_along_y and 1 or 2
  end
  local machine = machines[entity.name]
  local size = machine and machine.size or 1
  return size, size
end

---@param entity table
---@param machines table<string, {size: integer, glyph: string}>
---@return string
local function glyph_of(entity, machines)
  local machine = machines[entity.name]
  if machine then
    return machine.glyph
  end
  local draw = GLYPHS[entity.name]
  return draw and draw(entity) or "?"
end

---@param column number
---@param row number
---@return string
local function key(column, row)
  return string.format("%g,%g", column, row)
end

-- The tiles of a box, one string for each row from `first_row` to `last_row`, each from `first_column` to `last_column`.
---@param entities table[]
---@param machines table<string, {size: integer, glyph: string}>  the machines, by entity name
---@param first_column integer
---@param first_row integer
---@param last_column integer
---@param last_row integer
---@return string[]
function picture.draw(entities, machines, first_column, first_row, last_column, last_row)
  local tiles = {}
  for _, entity in ipairs(entities) do
    local width, height = size_of(entity, machines)
    local tile = grid.top_left_tile(entity.position, width, height)
    local glyph = glyph_of(entity, machines)
    for dx = 0, width - 1 do
      for dy = 0, height - 1 do
        tiles[key(tile.x + dx, tile.y + dy)] = glyph
      end
    end
  end
  local lines = {}
  for row = first_row, last_row do
    local line = {}
    for column = first_column, last_column do
      line[#line + 1] = tiles[key(column, row)] or "."
    end
    lines[#lines + 1] = table.concat(line)
  end
  return lines
end

return picture
