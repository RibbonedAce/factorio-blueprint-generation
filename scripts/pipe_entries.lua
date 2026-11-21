-- scripts/pipe_entries.lua
-- Brings the start of every pipe the player connects to the top left corner, where the belts they bring in start: each pipe goes up
-- from the tile it starts at, above the blueprint, and west along a row of its own to the west edge, where its end is open to the west
-- and the player joins it (as the water inlet of the concrete columns does, see scripts/rows.lua). Pure, like scripts/fluid_row.lua.
--
-- The pipes of the entries are ROWS_APART rows apart, so that no two touch (two fluids would mix), the one that starts furthest west
-- on the row nearest the blueprint and the one furthest east on the top row, as the belts of raw items have it, so that none crosses
-- another. Drawn for two pipes that start at the columns 1 and 5 of a blueprint (= a pipe, o the entry, whose open end is west):
--
--   o===========.     row -4: the entry of the pipe that starts at the column 5
--   . . . . . =
--   . . . . . =
--   o=. . . . =       row -1: the entry of the pipe that starts at the column 1
--   . = . . . =       row 0 and below: the blueprint, with its pipes starting here
--
-- The panels that tell which fluid is which are put beside the entries (scripts/labels.lua).

local entity_list = require("scripts.entity_list")
local grid = require("scripts.grid")

local pipe_entries = {}

local ROWS_APART = 3

-- The tile where a pipe starts, which opens to the north, and a name the caller gives it to find the entry again.
---@class bpgen.PipeStart
---@field key string
---@field x integer
---@field y integer

-- The pipes of the entries of `starts`, appended to `entities`. Gives the entry of each, at the west edge, in the order of the
-- starts from the west.
---@param entities bpgen.Entity[]
---@param pipe string  prototype name of the pipe
---@param starts bpgen.PipeStart[]
---@return bpgen.PipeStart[] entries  `x` is 0 and `y` the row of the entry
function pipe_entries.add(entities, pipe, starts)
  local ordered = {table.unpack(starts)}
  table.sort(ordered, function(first, second) return first.x < second.x end)
  local top = math.huge
  for _, start in ipairs(starts) do
    top = math.min(top, start.y)
  end
  local entries = {}
  for index, start in ipairs(ordered) do
    local row = top - 1 - ROWS_APART * (index - 1)
    for y = row, start.y - 1 do
      entity_list.append(entities, {name = pipe, position = grid.position(start.x, y)})
    end
    for x = 0, start.x - 1 do
      entity_list.append(entities, {name = pipe, position = grid.position(x, row)})
    end
    entries[index] = {key = start.key, x = 0, y = row}
  end
  return entries
end

return pipe_entries
