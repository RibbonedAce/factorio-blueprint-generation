-- scripts/output_side.lua
-- The output side of a column of machines: the inserters that take the product out of each machine, the poles that power them and
-- the belt they drop it on. The one place that decides where those stand, for every column of machines whose product leaves by
-- inserters onto a belt: the assembling machines and furnaces of `scripts/layout.lua` (which asks for the rows and the tiles) and the
-- chemical plants that make an item (`scripts/fluid_plant.lua` and `scripts/item_fluid_plants.lua`, which call `output_side.add`). What
-- the machines take in is another matter, and each of them has its own. Pure, like scripts/layout.lua.
--
-- The machines go in twos: the inserters of the first machine of a pair (the first, third, ... machine) stand in its top rows, those of
-- the second (the second, fourth, ...) in its bottom rows, so that the second machine of a pair and the first of the next have theirs
-- together (`output_side.inserter_top`). An inserter drops on the far lane of a belt, so inserters on one side of a plain belt fill only
-- one of its two lanes, and a belt that is to carry two lanes of product winds: it comes down the inner column (beside the inserters) and
-- curves east in the row of the first of two inserters, which drops on the curve (the outer lane), and runs on in the outer column, where
-- a stub in the row of the second inserter side-loads it (the inner lane). The next seam does it the other way round: the first
-- inserter's stub side-loads the belt coming down the outer column, and in the second row the belt turns west into the inner column,
-- where the second inserter drops on the curve (the outer lane). With two inserters for each machine, every machine fills both lanes; with
-- one, the machines fill the lanes in turn. The belt starts in the inner column one row above the first curve: without a belt behind it
-- Factorio would bend the first stub into a curve. For 3 x 3 machines this is the diagram, four machines of one inserter each, which stand
-- west of it in the rows 0 to 2, 3 to 5, 6 to 8 and 9 to 11 (columns: the inserters, the inner belt, the outer belt; `i` an inserter, `+` a
-- pole, `>` `v` `<` belts):
--
--   . v .     row -1: the belt starts in the inner column, a tile behind the first curve
--   i > v     row 0:  the first machine's inserter drops on the curve (the outer lane)
--   + . v     row 1:  the pole of the first machine, under its inserter
--   . . v     rows 2 and 3
--   + . v     row 4:  the pole of the second machine, above its inserter
--   i > v     row 5:  the second machine's inserter drops on a stub that side-loads the belt (the inner lane)
--   i v <     row 6:  the belt turns west; the third machine's inserter drops on the curve (the outer lane); a pole above reaches it
--   . > v     row 7:  the belt hops back to the outer column
--   . . v     rows 8 and 9
--   + . v     row 10: the pole of the fourth machine, above its inserter
--   i > v     row 11: the fourth machine's inserter drops on a stub (the inner lane); the belt goes on in the outer column
--
-- The poles stand in the column of the inserters, in the free tile under the inserters of a machine whose are in its top rows and above
-- those of a machine whose are in its bottom rows (`output_side.pole_plan`), except that a machine has none when a pole above it reaches
-- its inserters (the third machine here).

local constants = require("scripts.constants")
local entity_list = require("scripts.entity_list")
local grid = require("scripts.grid")

local output_side = {}

local north, east, south, west = defines.direction.north, defines.direction.east, defines.direction.south, defines.direction.west

-- Machines of this size (in tiles) can have a belt that winds, with this many inserters that fill a lane each.
local WINDING_MACHINE_SIZE = constants.WINDING_MACHINE_SIZE
local WINDING_OUTPUT_INSERTERS = constants.WINDING_OUTPUT_INSERTERS

-- The tile row of the top of machine number `index` (from 0).
---@param column bpgen.MachineColumn
---@param index integer
---@return integer
function output_side.machine_top(column, index)
  return column.first_row + index * column.spacing
end

-- The tile row of the first of `count` inserters in a column beside machine number `index` (from 0): in the top rows of a machine that is
-- the first of its pair, in the bottom rows of the second. A machine without a partner, the last of an odd number, is like the first.
-- The same on every belt, so that the inserters of two columns that share a belt agree.
---@param column bpgen.MachineColumn
---@param index integer
---@param count integer
---@return integer
function output_side.inserter_top(column, index, count)
  local top = output_side.machine_top(column, index)
  if index % 2 == 1 then
    return top + column.size - count
  end
  return top
end

-- The tile rows of every one of `count` inserters of each machine of the column, top to bottom.
---@param column bpgen.MachineColumn
---@param count integer
---@return integer[]
function output_side.inserter_rows(column, count)
  local rows = {}
  for index = 0, column.count - 1 do
    local first = output_side.inserter_top(column, index, count)
    for row = first, first + count - 1 do
      rows[#rows + 1] = row
    end
  end
  return rows
end

-- The row of the pole of machine number `index` of a column, or nil when the poles above it (which power the rows down to `reached`) reach
-- its `count` inserters. A machine whose inserters are in its top rows has its pole in the free tile under them, one whose inserters are
-- in its bottom rows in the free tile above them. With `whole_machine` the poles also have to reach every row of the machine, which is
-- where the inserters of a full side on the other side of it stand.
---@param column bpgen.MachineColumn
---@param index integer
---@param count integer
---@param reached number
---@param whole_machine? boolean
---@return integer|nil
local function pole_row(column, index, count, reached, whole_machine)
  local first = output_side.inserter_top(column, index, count)
  local last = whole_machine and output_side.machine_top(column, index) + column.size - 1 or first + count - 1
  if last <= reached then
    return nil
  end
  return index % 2 == 1 and first - 1 or first + count
end

-- Which machines get a pole on one side, and where, for `count` inserters on the side: the machines from the top down, each unless a pole
-- above it reaches its inserters (a pole powers `reach` tiles each way: two for a small pole, three for a medium one, which so powers the
-- inserters of two machines of a pair with one pole), see `pole_row`.
---@param column bpgen.MachineColumn
---@param count integer
---@param reach integer
---@param whole_machine? boolean
---@return table<integer, integer>  the tile row of the pole of each machine that has one, by machine number from 0
function output_side.pole_plan(column, count, reach, whole_machine)
  local plan, reached = {}, -math.huge
  for index = 0, column.count - 1 do
    local row = pole_row(column, index, count, reached, whole_machine)
    if row then
      plan[index], reached = row, row + reach
    end
  end
  return plan
end

-- The most rows between two poles of a column of machines of `size` with `count` inserters each, however many machines there are. The
-- poles are those of `output_side.pole_plan`, walked down the column until they repeat: a pole stands at the same row of its machine
-- whichever machine it is, for the first of a pair and for the second, and powers `reach` rows on from there, so where the next pole
-- stands depends only on whether the machine that has this one is the first or the second of its pair. The walk ends at the first pole
-- whose kind of machine has had a pole before, which is the third one at the latest.
---@param size integer
---@param count integer
---@param reach integer
---@return integer
local function longest_gap(size, count, reach)
  local column = {first_row = 0, spacing = size, size = size, count = 0}
  local longest, previous, reached, seen, index = 0, nil, -math.huge, {}, 0
  while true do
    local row = pole_row(column, index, count, reached)
    if row then
      if previous then
        longest = math.max(longest, row - previous)
      end
      previous, reached = row, row + reach
      if seen[index % 2] then
        return longest
      end
      seen[index % 2] = true
    end
    index = index + 1
  end
end

-- The longest wire the poles of a column of machines of `size` need between one pole and the next, for one or for two inserters beside
-- each machine, with poles that power `reach` tiles each way: the poles under the inserters of a machine that is the first of a pair and
-- above those of the second stand up to twice the size apart, and a pole that reaches the next machine's inserters saves one.
---@param size integer
---@param reach integer
---@return integer
function output_side.longest_wire(size, reach)
  local longest = 0
  for count = 1, WINDING_OUTPUT_INSERTERS do
    longest = math.max(longest, longest_gap(size, count, reach))
  end
  return longest
end

-- Whether the belt of machines of `size` with `per_machine` inserters each winds, when there are `machines` of them: with two inserters,
-- which fill a lane each, and with one when the machines go in twos (it needs two of them, since one alone fills one lane) and the caller
-- allows it (`one_inserter_winds`: the assembling machines only do it with a fast inserter, which moves what two plain ones do). Only
-- for the machines of the size the belt is drawn for.
---@param size integer
---@param per_machine integer
---@param machines integer
---@param one_inserter_winds boolean
---@return boolean
function output_side.winds(size, per_machine, machines, one_inserter_winds)
  if size ~= WINDING_MACHINE_SIZE then
    return false
  end
  return per_machine == WINDING_OUTPUT_INSERTERS or (per_machine == 1 and machines >= 2 and one_inserter_winds)
end

-- The rows of the inserters of a belt that runs north, as the belt that runs south sees them: reflected in the rows the belt takes, from
-- the top of that belt down (`mirror` is the sum of the rows a tile and its reflection are in).
---@param rows integer[]  the tile rows of the output inserters, top to bottom
---@param mirror integer
---@return integer[]
function output_side.reflected(rows, mirror)
  local found = {}
  for index = #rows, 1, -1 do
    found[#found + 1] = mirror - rows[index]
  end
  return found
end

-- The tiles being collected, with the request they are for.
---@class bpgen.WindingTiles
---@field request bpgen.WindingRequest
---@field tiles bpgen.BeltTile[]

-- Adds a tile.
---@param drawn bpgen.WindingTiles
---@param column integer
---@param row integer
---@param direction defines.direction
local function add_tile(drawn, column, row, direction)
  drawn.tiles[#drawn.tiles + 1] = {column = column, row = row, direction = direction}
end

-- A run of tiles facing south down one column, `length` of them from `first_row` (none when it is not positive).
---@param drawn bpgen.WindingTiles
---@param column integer
---@param first_row integer
---@param length integer
local function add_run(drawn, column, first_row, length)
  for row = first_row, first_row + length - 1 do
    add_tile(drawn, column, row, south)
  end
end

-- The two rows (or the one, for an inserter alone) of a seam, for the belt coming down `column`. From the inner column it curves east in the
-- first row, where the first inserter drops on the curve (the outer lane), and runs on in the outer column, which the second inserter's stub
-- side-loads (the inner lane). From the outer column the first inserter's stub side-loads it (the inner lane), and in the second row it
-- turns west into the inner column, where the second inserter drops on the curve (the outer lane). An inserter alone at the end has only
-- the first row. Gives the first row after the seam and the column the belt runs on in.
---@param drawn bpgen.WindingTiles
---@param row integer  the row of the first inserter
---@param column integer
---@param has_lower boolean  whether a second inserter stands under the first
---@return integer next_row
---@return integer next_column
local function add_seam(drawn, row, column, has_lower)
  local inner, outer = drawn.request.inner, drawn.request.outer
  add_tile(drawn, inner, row, east)
  add_tile(drawn, outer, row, south)
  if not has_lower then
    return row + 1, outer
  end
  if column == inner then
    add_tile(drawn, inner, row + 1, east)
    add_tile(drawn, outer, row + 1, south)
    return row + 2, outer
  end
  add_tile(drawn, inner, row + 1, south)
  add_tile(drawn, outer, row + 1, west)
  return row + 2, inner
end

-- Runs the belt on from `row` to `stop` in the column it came down in, hopping to the outer column in the first row when it is in the inner
-- one and there is a row to spare, so that the next seam starts in the outer column. Gives the column it comes down in after.
---@param drawn bpgen.WindingTiles
---@param row integer
---@param column integer
---@param stop integer  the last row of the stretch (above `row` when there is none)
---@return integer
local function add_stretch(drawn, row, column, stop)
  local inner, outer = drawn.request.inner, drawn.request.outer
  if column == inner and stop >= row then
    add_tile(drawn, inner, row, east)
    add_tile(drawn, outer, row, south)
    add_run(drawn, outer, row + 1, stop - row)
    return outer
  end
  add_run(drawn, column, row, stop - row + 1)
  return column
end

-- The tiles of the winding belt of a belt that runs south, in the order they are drawn: from the row above the first inserter, past a seam for
-- every two inserters in adjacent rows (one for an inserter alone), down to the row before `end_row`. A belt that runs north is the same
-- belt reflected: the caller reflects the rows (`output_side.reflected`) and the tiles. Also gives the column the belt ends in, which is the
-- inner one when the last seam turns it west and no row is left to hop back (an even number of machines with an inserter pair each, in
-- twos), the outer one else.
---@param request bpgen.WindingRequest
---@return bpgen.BeltTile[]
---@return integer end_column
function output_side.winding_tiles(request)
  local drawn = {request = request, tiles = {}}
  local rows = request.inserter_rows
  add_run(drawn, request.inner, request.start_row, rows[1] - request.start_row)
  local column, k = request.inner, 1
  while k <= #rows do
    local width = rows[k + 1] == rows[k] + 1 and 2 or 1
    local next_row, next_column = add_seam(drawn, rows[k], column, width == 2)
    column = add_stretch(drawn, next_row, next_column, (rows[k + width] or request.end_row) - 1)
    k = k + width
  end
  return drawn.tiles, column
end

-- The inserters of each machine, picking up from it (an inserter faces the side it picks up from: west).
---@param entities bpgen.Entity[]
---@param request bpgen.OutputSideRequest
---@return integer[] rows  of the inserters, top to bottom
local function add_inserters(entities, request)
  local rows = output_side.inserter_rows(request.column, request.inserters)
  for _, row in ipairs(rows) do
    entity_list.append(entities, {name = request.inserter, position = grid.position(request.inserter_column, row), direction = west})
  end
  return rows
end

-- The poles of the machines (see `output_side.pole_plan`), in the column of the inserters, each wired to the one before it, which a wire has to
-- reach. Gives them.
---@param entities bpgen.Entity[]
---@param request bpgen.OutputSideRequest
---@return bpgen.Entity[]
local function add_poles(entities, request)
  local plan, poles, previous = output_side.pole_plan(request.column, request.inserters, request.pole_reach), {}, nil
  for index = 0, request.column.count - 1 do
    if plan[index] then
      assert(not previous or plan[index] - previous <= request.pole_wire_distance, "output_side: a wire has to reach from the pole of one machine to the next")
      poles[#poles + 1] = entity_list.append(entities, {name = request.pole, position = grid.position(request.inserter_column, plan[index])})
      if #poles > 1 then
        entity_list.connect_poles(poles[#poles - 1], poles[#poles])
      end
      previous = plan[index]
    end
  end
  return poles
end

-- The belt the inserters drop on: plain, one column, from the first row to the last row of the last machine; or winding, in two.
---@param entities bpgen.Entity[]
---@param request bpgen.OutputSideRequest
---@param rows integer[]  of the inserters
---@return integer column  the belt ends in: the column the belt that takes the product on goes on in
local function add_belt(entities, request, rows)
  local column = request.column
  local first, end_row = column.first_row, output_side.machine_top(column, column.count)
  local inner = request.inserter_column + 1
  if not request.winds then
    for row = first, end_row - 1 do
      entity_list.append(entities, {name = request.belt, position = grid.position(inner, row), direction = south})
    end
    return inner
  end
  local tiles, end_column = output_side.winding_tiles({inserter_rows = rows, inner = inner, outer = inner + 1, start_row = first - 1, end_row = end_row})
  for _, tile in ipairs(tiles) do
    entity_list.append(entities, {name = request.belt, position = grid.position(tile.column, tile.row), direction = tile.direction})
  end
  return end_column
end

-- The output side of a column of machines, appended to `entities`: the inserters, their poles and the belt. Gives the poles, wired from the
-- top down, and the column the belt ends in (the one beside the inserters for a plain belt; for a winding belt see `output_side.winding_tiles`).
---@param entities bpgen.Entity[]
---@param request bpgen.OutputSideRequest
---@return bpgen.Entity[] poles
---@return integer belt_column
function output_side.add(entities, request)
  local rows = add_inserters(entities, request)
  local poles = add_poles(entities, request)
  return poles, add_belt(entities, request, rows)
end

return output_side
