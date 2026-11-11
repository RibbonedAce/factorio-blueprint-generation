-- scripts/inputs.lua
-- The top band of a blueprint that takes one belt of each material (see .agents/inputs-plan.md and
-- scripts/feeds.lua, which decides what feeds what): the belts that come in, the buses that divide
-- them, the mixers that put the ore on one lane and the fuel on the other, the trunks along the top
-- and the belts that come down from them to the chains. Pure, like scripts/layout.lua.
--
-- Circuits from iron plates and cables (i iron furnace, c copper furnace, O cable assembler, E circuit assembler,
-- } an inserter, + a pole, S a splitter, ( ) the entrance and the exit of an underground belt that runs east):
--
--       012345678901234567890123456789012
--    0 |>>v.......................^}EEE}v|   the coal comes in and runs down its bus, column 2
--    1 |..v.......................^}EEE+v|
--    2 |>(v.)v....................^+EEE.v|   the copper ore goes under the bus and turns south into the copper mixer
--    3 |..SS.>>>>>>>>>v...........^......|   the splitter of the bus; the copper trunk (its first tile is the mixer)
--    4 |..v>>^........v...........^......|   the coal turns north into the copper mixer; the copper belt comes down
--    5 |>(v.)v........v}cc}v}OOO}v^......|   the iron ore goes under the bus and turns south into the iron mixer
--    6 |..v..>>>v......+cc+.+OOO}v^......|   the iron trunk, which turns south in column 8, at the iron furnaces
--    7 |..>>>^..v............OOO+>^......|   the end of the bus: the coal turns north into the iron mixer
--    8 |........v}ii}v............^......|
--    9 |.........+ii+v>>>>>>>>>>>>^......|   the iron plates reach belt a (column 26) through the lane gadget of rows 9 and 10
--   10 |.............>>^.................|
--
-- With N buses (the pure belts that feed two trunks or more), the rules are:
--   * a bus comes in at row b (0 for the one furthest east), runs east to column 4N - 2 - 4b and down it; a
--     splitter above every feeder but the last sends the feeder out to the east. A pure belt that feeds one
--     trunk comes in at x = 0 on the row of its feeder.
--   * a feeder runs east along its row to the column before the mixer. Where a bus stands in its way it goes
--     under it (in at the column before the bus, out two after it); buses are 4 columns apart so that an exit
--     and the next entrance can be side by side.
--   * the mixer of a trunk with two items is in column 4N + 1: the trunk's first tile faces east with nothing
--     behind it, the ore feeder turns south into its north side and the fuel feeder north into its south side.
--     A belt fed from both sides stays straight, so each side-loads one lane. A trunk with one item has no mixer:
--     its feeder row is the trunk.
--   * the trunks are 3 rows apart (the ore feeder above, the fuel feeder below), the first N + 2 rows from the
--     top (1 without a bus). A trunk runs east; at each of its leaves but the last a splitter facing east (the
--     leaf's column minus 1) sends the leaf's belt out, and the trunk turns south at the last.
--   * the belt of a leaf comes down from the trunk, under every trunk below that reaches further east than the
--     leaf (in the row before the trunk, out the row after it).
--   * the columns of the blueprint start in column 4N + 4.

local grid = require("scripts.grid")

local inputs = {}

local north, east, south = defines.direction.north, defines.direction.east, defines.direction.south

-- Buses stand this many columns apart, so that where a feeder goes under a bus the exit and the next entrance can be side by side.
local BUS_SPACING = 4
-- A trunk takes this many rows: the ore feeder above it, the trunk, the fuel feeder below.
local TRUNK_ROWS = 3
-- The fewest rows between two feeders of one bus (see `feeder_rows`).
local MIN_FEEDER_GAP = 2
-- The fewest tiles an underground belt has to span: a feeder goes under a bus from the tile before it to the tile two after it.
inputs.MIN_REACH = 3
local MIN_REACH = inputs.MIN_REACH
-- How far a feeder row is from its trunk's row, by the role of the feeder.
local FEEDER_OFFSET = {a = -1, b = 1, pure = 0}

-- The entities of the top band as they are drawn, without their numbers.
---@class bpgen.Band
---@field entities bpgen.NewEntity[]
---@field names bpgen.SharedNames
---@field buses bpgen.PureBelt[]
---@field supplies bpgen.Input[]
local Band = {}
Band.__index = Band

---@param names bpgen.SharedNames
---@param buses bpgen.PureBelt[]
---@return bpgen.Band
local function new_band(names, buses)
  return setmetatable({entities = {}, names = names, buses = buses, supplies = {}}, Band)
end

---@param column integer
---@param row integer
---@param way defines.direction
function Band:belt(column, row, way)
  self.entities[#self.entities + 1] = {name = self.names.belt, position = grid.position(column, row), direction = way}
end

-- A splitter covers two tiles across the way it faces, from (column, row): to the east of it when it faces north
-- or south, under it when it faces east or west.
---@param column integer
---@param row integer
---@param way defines.direction
function Band:splitter(column, row, way)
  local width, height = 1, 2
  if way == north or way == south then
    width, height = 2, 1
  end
  self.entities[#self.entities + 1] = {name = self.names.splitter, position = grid.position(column, row, width, height), direction = way}
end

---@param column integer
---@param row integer
---@param way defines.direction
---@param kind "input"|"output"  the entrance or the exit
function Band:underground(column, row, way, kind)
  self.entities[#self.entities + 1] = {name = self.names.underground, position = grid.position(column, row), direction = way, type = kind}
end

-- Belts east along `row` from column `first` to column `last`.
---@param first integer
---@param last integer
---@param row integer
function Band:across(first, last, row)
  for column = first, last do
    self:belt(column, row, east)
  end
end

-- The bus whose entrance is the tile at `column` in `row`: a feeder there goes under it.
---@param column integer
---@param row integer
---@return bpgen.PureBelt|nil
function Band:bus_ahead(column, row)
  for _, bus in ipairs(self.buses) do
    if bus.column - 1 == column and row >= bus.entry and row <= bus.last then
      return bus
    end
  end
  return nil
end

-- Belts east along `row` from column `first` to column `last`, going under the buses that stand in the way in that row.
---@param row integer
---@param first integer
---@param last integer
function Band:route(row, first, last)
  local column = first
  while column <= last do
    local bus = self:bus_ahead(column, row)
    if bus then
      self:underground(column, row, east, "input")
      self:underground(bus.column + 2, row, east, "output")
      column = bus.column + 3
    else
      self:belt(column, row, east)
      column = column + 1
    end
  end
end

-- How many tiles an entity of the blueprint covers across and along the map: a splitter two across the way it faces,
-- a machine as many as `machine_sizes` says of its name, anything else (belts, inserters, poles) one.
---@param entity bpgen.Entity
---@param names bpgen.SharedNames
---@param machine_sizes table<string, integer>  the tiles on a side of each machine, by name
---@return integer width
---@return integer height
function inputs.footprint(entity, names, machine_sizes)
  if entity.name == names.splitter then
    local across_x = entity.direction == north or entity.direction == south
    return across_x and 2 or 1, across_x and 1 or 2
  end
  local size = machine_sizes[entity.name] or 1
  return size, size
end

-- The tile column of the mixers: after the buses, which are 4 columns apart, the first one 3 columns before it.
---@param plan bpgen.FeedPlan
---@return integer
local function mixer_column(plan)
  return BUS_SPACING * #plan.buses + 1
end

-- The tile column the first column of the blueprint starts in: after the mixers, with room for the first splitter.
---@param plan bpgen.FeedPlan
---@return integer
function inputs.start_column(plan)
  return mixer_column(plan) + 3
end

-- The first row a column may start in when its product belt stands in column `x`: two rows under the lowest
-- trunk that reaches further east than `x` (the row between is left free), or the top row when none does.
---@param plan bpgen.FeedPlan
---@param x integer
---@return integer
function inputs.first_row_under(plan, x)
  local lowest
  for _, trunk in ipairs(plan.trunks) do
    if trunk.east > x then
      lowest = math.max(lowest or 0, trunk.row)
    end
  end
  return lowest and lowest + 2 or 0
end

-- Gives the trunks their rows, 3 apart from the first row under the entrances of the buses, and the column of
-- their last leaf.
---@param plan bpgen.FeedPlan
local function give_trunk_rows(plan)
  local first = #plan.buses > 0 and #plan.buses + 2 or 1
  for number, trunk in ipairs(plan.trunks) do
    trunk.row = first + TRUNK_ROWS * (number - 1)
    trunk.east = 0
    for _, leaf in ipairs(trunk.leaves) do
      trunk.east = math.max(trunk.east, leaf.drop_x)
    end
  end
end

-- Gives every feeder the row of the belt that brings it: above its trunk for the ore, below for the fuel, on it for a trunk with one item.
---@param plan bpgen.FeedPlan
local function give_feeder_rows(plan)
  for _, belt in ipairs(plan.belts) do
    for _, feeder in ipairs(belt.feeders) do
      feeder.row = feeder.trunk.row + FEEDER_OFFSET[feeder.role]
    end
  end
end

-- The rows of the feeders of a belt, from the top. Two feeders of a bus are at least 2 rows apart: the splitter above a feeder
-- takes the row after the belt that leaves the splitter before it, so the splitters do not meet. (The coal of a trunk that
-- carries it alone, row f + 2, can be that close to the fuel feeder of the trunk above it, row f.)
---@param belt bpgen.PureBelt
---@return integer[]
local function feeder_rows(belt)
  local found = {}
  for _, feeder in ipairs(belt.feeders) do
    found[#found + 1] = feeder.row
  end
  table.sort(found)
  for index = 2, #found do
    assert(found[index] - found[index - 1] >= MIN_FEEDER_GAP, "inputs: two feeders of a bus are too close")
  end
  return found
end

-- Says where a bus stands: the column it comes down, the row it comes in, and the row of its last feeder.
---@param bus bpgen.PureBelt
---@param bus_count integer
local function place_bus(bus, bus_count)
  local rows_of_feeders = feeder_rows(bus)
  bus.column = BUS_SPACING * bus_count - 2 - BUS_SPACING * bus.bus
  bus.entry = bus.bus
  bus.last = rows_of_feeders[#rows_of_feeders]
end

-- Notes a belt that the player brings in, at the west edge.
---@param row integer
---@param item string
function Band:supply(row, item)
  self.supplies[#self.supplies + 1] = {x = 0, y = row, item = item}
end

-- One tile of a bus: a splitter where it is the row above a feeder, else a belt down, with the start of the
-- feeder beside it where a feeder leaves.
---@param column integer
---@param row integer
---@param peel table<integer, true>  the rows where a feeder leaves
---@param split table<integer, true>  the rows of the splitters
function Band:bus_tile(column, row, peel, split)
  if split[row] then
    self:splitter(column, row, south)
    return
  end
  self:belt(column, row, south)
  if peel[row] then
    self:belt(column + 1, row, east)
  end
end

-- A bus: it comes in from the west, runs down its column with a splitter above every feeder but the last, and ends
-- turning east in the row of the last feeder.
---@param bus bpgen.PureBelt
function Band:draw_bus(bus)
  self:supply(bus.entry, bus.item)
  self:across(0, bus.column - 1, bus.entry)
  self:belt(bus.column, bus.entry, south)
  local rows_of_feeders = feeder_rows(bus)
  local peel, split = {}, {}
  for index = 1, #rows_of_feeders - 1 do
    peel[rows_of_feeders[index]] = true
    split[rows_of_feeders[index] - 1] = true
  end
  for row = bus.entry + 1, bus.last - 1 do
    self:bus_tile(bus.column, row, peel, split)
  end
  self:belt(bus.column, bus.last, east)
end

-- A feeder from where it leaves its bus (or comes in, for a pure belt that feeds one trunk) to the column before the mixer.
---@param belt bpgen.PureBelt
---@param feeder bpgen.Feeder
---@param mixer integer  the tile column of the mixers
function Band:draw_feeder(belt, feeder, mixer)
  if belt.bus == nil then
    self:supply(feeder.row, belt.item)
    self:route(feeder.row, 0, mixer - 1)
    return
  end
  local starts_at = feeder.row == belt.last and belt.column + 1 or belt.column + 2 -- the last feeder is the end of the bus itself
  self:route(feeder.row, starts_at, mixer - 1)
end

-- The first tiles of a trunk with two items: the mixer, where the ore feeder turns into the north side of the
-- trunk's first tile and the fuel feeder into its south side. A trunk with one item starts as a belt east.
---@param trunk bpgen.Trunk
---@param mixer integer
function Band:draw_mixer(trunk, mixer)
  if trunk.mixed then
    self:belt(mixer, trunk.row - 1, south)
    self:belt(mixer, trunk.row + 1, north)
  end
  self:belt(mixer, trunk.row, east)
end

-- The rows of the trunks below `trunk` that reach further east than `leaf`, from the top: its belt goes under them.
---@param plan bpgen.FeedPlan
---@param trunk bpgen.Trunk
---@param leaf bpgen.FeedLeaf
---@return integer[]
local function rows_to_cross(plan, trunk, leaf)
  local found = {}
  for _, other in ipairs(plan.trunks) do
    if other.row > trunk.row and other.east > leaf.drop_x then
      found[#found + 1] = other.row
    end
  end
  table.sort(found)
  return found
end

-- The belt that comes down from `trunk` to `leaf`, under the trunks in its way. Returns the row of its last tile.
-- The trunks in its way are the ones right below, with no other trunk between (the trunks that reach furthest east are
-- on top), and trunks are 3 rows apart, so each entrance is in the row right after the last tile before it.
---@param plan bpgen.FeedPlan
---@param trunk bpgen.Trunk
---@param leaf bpgen.FeedLeaf
---@return integer
function Band:descend(plan, trunk, leaf)
  local column, last = leaf.drop_x, trunk.row + 1
  self:belt(column, last, south)
  for _, row in ipairs(rows_to_cross(plan, trunk, leaf)) do
    assert(row - 1 == last + 1, "inputs: the trunks in the way are not right below each other")
    self:underground(column, row - 1, south, "input")
    self:underground(column, row + 1, south, "output")
    last = row + 1
  end
  return last
end

-- The trunk from its mixer to its last leaf, with a splitter before every leaf but the last, and the belt of every
-- leaf down from it. Adds the row of the last tile of each belt to `ends`.
---@param plan bpgen.FeedPlan
---@param trunk bpgen.Trunk
---@param mixer integer
---@param ends table<bpgen.FeedLeaf, integer>
function Band:draw_trunk(plan, trunk, mixer, ends)
  local column = mixer + 1
  for index, leaf in ipairs(trunk.leaves) do
    local is_last = index == #trunk.leaves
    self:across(column, leaf.drop_x - (is_last and 1 or 2), trunk.row)
    if is_last then
      self:belt(leaf.drop_x, trunk.row, south)
    else
      self:splitter(leaf.drop_x - 1, trunk.row, east)
      self:belt(leaf.drop_x, trunk.row, east)
      column = leaf.drop_x + 1
    end
    ends[leaf] = self:descend(plan, trunk, leaf)
  end
end

-- The belt that brings fuel to the head of the belt between two stages of a chain, from the last tile of its descent
-- (the band draws the descent itself): down the column of the output inserters of the stage before, then east into
-- the tile above the head. That tile runs south with a stub behind it, so it stays straight and the side-load puts
-- the fuel on its near (west) lane, which the plates, dropped on the far lane, leave free; it runs on into the head.
--
--      c c+1
--    v .         <- last row of the descent, drawn by the band
--    v .         <- rows between, as many as it takes
--    v v         <- the stub, on the row above the side-load
--    > v         <- the fuel turns east into the tile above the head
--    . .         <- the first tile of the belt between the two stages (drawn by its stage)
---@param names bpgen.SharedNames
---@param column integer  the tile column the fuel comes down
---@param last integer  the row of the last tile of the descent
---@param head integer  the row of the first tile of the belt between the two stages, at least two rows below `last`
---@return bpgen.NewEntity[]
function inputs.fuel_tail(names, column, last, head)
  assert(head >= last + 2, "inputs: no room for the fuel to turn into the head of the belt")
  local band = new_band(names, {})
  for row = last + 1, head - 2 do
    band:belt(column, row, south)
  end
  band:belt(column, head - 1, east)
  band:belt(column + 1, head - 2, south)
  band:belt(column + 1, head - 1, south)
  return band.entities
end

-- The top band for this plan, once the columns are placed (every leaf has its `drop_x`): the entities (without
-- numbers), the belts the player brings in from the top down, and for every leaf the row of the last tile of its belt.
-- Gives the trunks and the feeders their rows and the buses their places.
---@param plan bpgen.FeedPlan
---@param names bpgen.SharedNames
---@param reach integer  the most tiles an underground belt spans
---@return bpgen.NewEntity[] entities
---@return bpgen.Input[] supplies
---@return table<bpgen.FeedLeaf, integer> ends
function inputs.lay(plan, names, reach)
  assert(reach >= MIN_REACH, "inputs: the underground belt does not span enough tiles")
  local band = new_band(names, plan.buses)
  give_trunk_rows(plan)
  give_feeder_rows(plan)
  for _, bus in ipairs(plan.buses) do
    place_bus(bus, #plan.buses)
  end
  for _, bus in ipairs(plan.buses) do
    band:draw_bus(bus)
  end
  local mixer, ends = mixer_column(plan), {}
  for _, belt in ipairs(plan.belts) do
    for _, feeder in ipairs(belt.feeders) do
      band:draw_feeder(belt, feeder, mixer)
    end
  end
  for _, trunk in ipairs(plan.trunks) do
    band:draw_mixer(trunk, mixer)
    band:draw_trunk(plan, trunk, mixer, ends)
  end
  table.sort(band.supplies, function(first, second) return first.y < second.y end)
  return band.entities, band.supplies, ends
end

return inputs
