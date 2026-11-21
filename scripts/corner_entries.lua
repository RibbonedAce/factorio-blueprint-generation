-- scripts/corner_entries.lua
-- Brings the start of everything the player connects to the top left corner, where the belts they bring in start: each pipe or belt
-- goes up from the tile it starts at, above the blueprint, and west along a row of its own to the west edge, where its end is open
-- to the west and the player joins it (as the water inlet of the concrete columns does, see scripts/rows.lua). Pure, like
-- scripts/fluid_row.lua.
--
-- The rows are ROWS_APART rows apart, so that no two touch (two fluids would mix, and the panels need room), the one that starts
-- furthest west on the row nearest the blueprint and the one furthest east on the top row, as the belts of raw items have it, so that
-- none crosses another. Drawn for a pipe and a belt that start at the columns 1 and 5 of a blueprint (= a pipe, > and v a belt, o the
-- entry, whose open end is west):
--
--   o>>>>v            row -4: the entry of the belt that starts at the column 5
--   . . . v
--   . . . v
--   o=. . v           row -1: the entry of the pipe that starts at the column 1
--   . = . . v         row 0 and below: the blueprint, with its pipe and belt starting here
--
-- The panels that tell what each entry is are put beside them (scripts/labels.lua).

local entity_list = require("scripts.entity_list")
local grid = require("scripts.grid")

local corner_entries = {}

local north, east, south, west = defines.direction.north, defines.direction.east, defines.direction.south, defines.direction.west

local ROWS_APART = 3

-- The tile where a pipe or a belt starts (a pipe opens to the north, a belt runs south), what it is made of, and a key the caller
-- gives it to find the entry again.
---@class bpgen.EntryStart
---@field key string
---@field x integer
---@field y integer
---@field name string  prototype name of the pipe or the belt
---@field belt? boolean  a belt: the tiles run east along the row and south down the column, where a pipe has no direction

-- The tiles of one entry: up from the tile where it starts to the row, and west along it to the edge.
---@param entities bpgen.Entity[]
---@param start bpgen.EntryStart
---@param row integer
local function add_line(entities, start, row)
  local up, along = start.belt and south or nil, start.belt and east or nil
  for y = row, start.y - 1 do
    entity_list.append(entities, {name = start.name, position = grid.position(start.x, y), direction = up})
  end
  for x = 0, start.x - 1 do
    entity_list.append(entities, {name = start.name, position = grid.position(x, row), direction = along})
  end
end

-- The pipes and belts of the entries of `starts`, appended to `entities`. Gives the entry of each, at the west edge, in the order of
-- the starts from the west.
---@param entities bpgen.Entity[]
---@param starts bpgen.EntryStart[]
---@return {key: string, x: integer, y: integer}[] entries  `x` is 0 and `y` the row of the entry
function corner_entries.add(entities, starts)
  local ordered = {table.unpack(starts)}
  table.sort(ordered, function(first, second) return first.x < second.x end)
  local top = math.huge
  for _, start in ipairs(starts) do
    top = math.min(top, start.y)
  end
  local entries = {}
  for index, start in ipairs(ordered) do
    local row = top - 1 - ROWS_APART * (index - 1)
    add_line(entities, start, row)
    entries[index] = {key = start.key, x = 0, y = row}
  end
  return entries
end

return corner_entries
