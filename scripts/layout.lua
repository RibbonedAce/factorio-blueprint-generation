-- scripts/layout.lua
-- Turns "N machines" into the list of blueprint entities. Pure: it only builds
-- tables (it reads the constant table `defines`, but never the game world).
-- Positions are written as TILES (see scripts/grid.lua): the top-left tile an
-- entity covers, with y growing down the page.
--
-- The layout is one column of machines, drawn here as it looks from above
-- (north is up, belts run down, except the one between two columns: see below). A
-- machine is 2 or 3 tiles wide and tall; this
-- is a 2x2 furnace with one inserter on each side:
--
--   x:   0       1      2 3      4       5
--      input  input   machine  output  output
--      belt  inserter (2x2)  inserter  belt
--
--        v      >      [F F]      >       v      <- top row of machine 1: its inserters
--        v      P      [F F]      P       v      <- bottom row of machine 1 (P = pole)
--        v             [F F]              v      <- top row of machine 2
--        v      >      [F F]      >       v      <- bottom row of machine 2: its inserters
--
-- The input belt ends at the last input inserter; the output belt runs the full
-- height, so the products can carry on downstream. Inserters move the input
-- from the belt into the machine, and the product from the machine onto the
-- output belt. A machine may need several inserters on a side, one under the
-- next. Poles supply the inserters and the machine and are wired together: the medium electric pole once it is
-- unlocked, else the small one (see `generator.lua`); the game says how far each powers (`layout.pole_reach`).
--
-- The machines go in twos: the inserters of the first machine of a pair (the first, third, ... machine) stand in its
-- top rows, those of the second (the second, fourth, ...) in its bottom rows, as drawn above, so that the second
-- machine of a pair and the first of the next have theirs together. A machine without a partner, the last of an odd
-- number, is like the first (in a column of five, machines 1 and 5 look alike). The long-handed inserters follow the
-- pattern too: under the plain ones in the first machine of a pair and above them in the second (`Builder:plain_input_top`).
-- It is the same on every belt, the one
-- between two columns too (see `Builder:inserter_top`), so that the inserters of two columns that share a belt agree.
--
-- While a side has a free tile beside the machine (fewer inserters than rows), the poles go there: under the
-- inserters of a machine whose inserters are in its top rows, above those of one whose inserters are in its bottom
-- rows. The machines go from the top down, each with a pole unless a pole above it reaches its inserters, which a
-- small pole does for two rows each way and a medium pole for three (see `Builder:side_pole_plan`). When a side is full, no tile is free, so the
-- machines are separated by a row of poles instead (a "pole row"), with one more
-- row of poles above the first machine and below the last. A 3x3 machine with
-- three inserters in, two out, drawn the same way:
--
--        P      row 0: poles
--        >      [M M M]      >       v      <- rows 1 to 3: machine 1, three inserters
--        >      [M M M]      >       v         in, two out
--        >      [M M M]              v
--        P      row 4: poles, then machine 2 from row 5 ...
--
-- An inserter drops items on the far lane of a belt, so inserters on one side of a
-- plain belt fill only one of its two lanes. A 3x3 machine with two output
-- inserters (and no pole rows) gets a winding output belt instead, which lets
-- the inserters fill different lanes (v > < are belts running south, east, west). Two machines:
--
--   x:   0     1     2 3 4      5      6      7
--      input input  machine  output inner  outer
--      belt inserter (3x3)  inserter belt  belt
--
--                                           v      .    <- row -1: the inner belt starts, a tile behind the first curve
--        v     >    [M M M]     }      >      v    <- row 0: this inserter drops on the curve (>): the outer lane
--        v     >    [M M M]     }      >      v    <- row 1: this one on the stub (>), which side-loads the outer belt: the inner lane
--        v     P    [M M M]     P      .      v    <- row 2: poles; the belt goes on in the outer column
--        v     P    [M M M]     P      .      v    <- row 3: the second machine, whose inserters are in its bottom rows
--        v     >    [M M M]     }      >      v    <- row 4: this inserter drops on the stub: the inner lane
--        v     >    [M M M]     }      v      <    <- row 5: the outer belt turns west into the inner column, so that
--                                                      this inserter drops on the curve: the outer lane
--
-- The belt has a seam for every two inserters in adjacent rows, and one for an inserter alone (see
-- `Builder:add_winding_output_belt`); each machine's two inserters are one seam, so each machine fills both lanes.
-- A first stub with no belt behind the tile it feeds would bend into a curve, so the belt starts in the inner column a
-- tile higher. With one fast inserter on each machine (which moves what two plain ones do) the seams are made of the
-- inserters of the second machine of a pair and the first of the next, and the machines alternate lanes: the belt
-- hops back to the outer column between seams so that each seam starts from it. The belt needs the rows a 3x3
-- machine takes, so it only works for size 3, but for paired machines (`Shape.output_paired`), which wind it whatever
-- their size, whatever the inserter and whether or not the belt feeds another column.
--
-- A column of furnaces that has to make more than one lane of plates is built wide (the planner decides, see
-- `bpgen.StageRequest.wide`): the machines go in twos with one output inserter each, the belt winds, and the input side is
-- full, two plain inserters for every furnace, one for each of two input belts that are woven so that both reach them
-- (`Shape.second_input_belt` makes the column draw them). Belt a (the ore on one lane and the coal on the other) runs in the
-- column beside the inserters and goes under it for two rows, so that belt b (the ore on both lanes) can come into that
-- column for those two rows from the column beside it and go back; the inserters take from the tiles of the underground
-- belt (its entrance and its exit) and from the tiles of belt b. A pair of furnaces takes four rows, and each furnace gets
-- one inserter on each belt, in the mirror order for the second of the pair. The side is full, so the poles stand on the
-- output side (the free tile of each machine) and reach the input inserters from there, three tiles away, with a medium pole
-- (`Shape.powered_from_output`). Four furnaces on their own (( ) the entrance and the exit of an underground belt, } an
-- inserter, F a furnace, + a pole):
--
--                           v        <- row -1: the belt starts a tile behind the first curve
--        v (  }  [F F]  }   >  v     <- row 0: belt a goes under (entrance), belt b runs on; the first furnace takes belt a
--        > v  }  [F F]  +   .  v     <- row 1: belt b comes into the column of belt a, where the first furnace takes it
--        v <  }  [F F]  .   .  v     <- row 2: the second furnace takes belt b, which goes back to its own column
--        v )  }  [F F]  }   >  v     <- row 3: belt a comes up, where the second furnace takes it
--        v (  }  [F F]  }   v  <
--        > v  }  [F F]  +   >  v
--        v <  }  [F F]  .   .  v
--        v )  }  [F F]  }   >  v     <- an odd number of furnaces ends in an exit two rows under the last inserter
--
-- The belt to the next column runs north or south as the plates need (see below): the north one is the south one reflected
-- (`Builder:add_winding_tile`) and starts a tile past its last row.
--
-- A column of steel furnaces after such a column (`Shape.fuel_belt`) takes its fuel on a belt of its own, woven the same
-- way with the belt of plates before it: the plates have both lanes of that belt (the iron furnaces wind it), so the fuel
-- cannot ride a lane of it. The fuel goes under in a new column beside the steel furnaces' inserters, and the winding belt's
-- outer column is the detour: it is straight in the rows 1 and 2 of every four (the output inserters of the iron furnaces
-- are in rows 0 and 3, where it winds), so it turns east into the column of the fuel in row 1 and back in row 2. The belt
-- of the plates runs south (the fuel comes down from the top), and iron and steel furnaces are as many (each eats what the
-- other makes: 18.75 plates a minute). The steel furnaces start one furnace lower than the iron furnaces, with the rows of the
-- weave kept to those of the winding belt (anchored to the first row of the chain, `Geometry.first_row`; the first
-- steel furnace stands in the rows 2 and 3 of the weave): a plate only goes the way the belt runs, and the inserter of a
-- steel furnace takes the plates from one tile, the detour, in its first or its second row, so that the plates of the lowest
-- iron furnace, which drop in the last row, would pass every inserter of the steel furnaces if they started as high.
-- Lower, the plates of every iron furnace pass the inserter of a steel furnace, and each steel furnace has the plates of at
-- least as many iron furnaces as there are steel furnaces up to it. The first four rows, from the inner and the outer column of the iron furnaces' winding belt on (S a steel
-- furnace, ( ) the entrance and the exit of the fuel's underground belt):
--
--        > v  (  .  [. .]  .   .  .     <- row 0: the fuel goes under (entrance), the plates run on
--        . >  v  .  [. .]  .   v  .     <- row 1: the plates turn east into the column of the fuel (the belt of the steel starts)
--        . v  <  }  [S S]  }   >  v     <- row 2: ... and come back, where the first steel furnace takes them
--        > v  )  }  [S S]  +   .  v     <- row 3: the fuel comes up, where the first steel furnace takes it
--
-- The belt of the steel runs north when the column after is the shorter one (it is, by far, for a steel furnace built
-- wide: it needs that rate), up to the first row of the chain, since the first inserters of the next column are above the
-- first steel furnace (`Builder:continue_belt_north`); a belt that runs south after a column that starts lower is refused.
--
-- A chain puts one such column after another, left to right, from the raw items to
-- the final product. The output belt of a column is the input belt of the next, so
-- the first column's product goes straight into the second column's machines (here
-- furnaces making plates, then assemblers making gears from them):
--
--        v   >  [F F]  >  v  >  [A A A]  >  >  v
--        v   >  [F F]  >  v  >  [A A A]  >  v  <
--        ore             plates           gears
--
-- Only the last column's belt winds (but for columns of paired machines): the belt between two columns is a plain one,
-- so the plates travel on one lane (see "plain belt" above). The columns need not
-- have the same number of machines nor the same machine size, so the plate belt
-- runs as far down as either column needs. One wire joins the top poles of each
-- column to the next one, so a single connection to the power network powers all.
--
-- A plate only travels the way its belt runs, so it can only reach inserters further
-- along the belt than the one that dropped it. The columns all start on the same row,
-- and the belt between two columns runs north when the first column is the longer of the
-- two for the work they do, and south otherwise, so that every plate has an inserter of
-- the second column ahead of it. The lengths come from how many machines' worth of work
-- each column does (a fraction), not from how many machines the rate rounds up to, so
-- the belt runs the same way at 1 item a minute and at 100. Next to 2 assemblers (rows 0 to 4), 11 furnaces
-- (rows 0 to 21) would waste the plates of the 8 lowest furnaces on a southbound belt:
-- they flow south past the last assembler. On a northbound belt (^) they all pass the
-- assemblers' inserters, and the lowest assembler has the first pick (a smaller chain,
-- 4 furnaces and 1 assembler):
--
--        v   >  [F F]  >  ^  >  [A A A]      <- row 0: the belt ends here
--        v      [F F]     ^  >  [A A A]
--        v   >  [F F]  >  ^     [A A A]
--        v      [F F]     ^                  <- furnaces below the assembler:
--        v   >  [F F]  >  ^                     their plates still pass its inserters
--        v      [F F]     ^
--        v   >  [F F]  >  ^
--               [F F]     ^                  <- the belt starts here

local grid = require("scripts.grid")

local layout = {}

-- The tile column of each part of a column of machines, counted from the column's
-- own input belt (the x numbers in the diagrams above). The machine starts at
-- MACHINE_OFFSET and covers `machine_size` columns; the output inserters and belt
-- follow it.
local INPUT_INSERTER_OFFSET = 1
local MACHINE_OFFSET = 2

local LENGTH_TOLERANCE = 1e-9  -- two lengths this close (relative) are equal

-- The output belt winds (see the diagram above) for machines of this size with this many output inserters.
local WINDING_MACHINE_SIZE = 3
local WINDING_OUTPUT_INSERTERS = 2

-- The rows of the pattern of the two input belts of a column built wide: a pair of furnaces (see the diagram above).
local WEAVE_ROWS = 4

-- Machines of these sizes (in tiles) can be powered by poles placed as described above.
local SUPPORTED_MACHINE_SIZES = {[2] = true, [3] = true}

-- How many tiles away from its own, along a row or a column, a pole powers. An entity is powered when the supply area
-- covers part of it, so the supply distance 2.5 of a small pole reaches the tiles up to 2 away, the 3.5 of a medium
-- pole up to 3.
---@param supply_distance number  how far from its centre the pole powers, in tiles
---@return integer
function layout.pole_reach(supply_distance)
  return math.ceil(supply_distance - 0.5)
end

-- The most inserters the input side of a machine gets, plain and long-handed together:
-- one fewer than the machine is tall, so one tile beside the machine stays free for a
-- pole. With every tile beside it taken by an inserter, the machines would have to be
-- spaced apart with a row of poles between them (see "pole row" below).
-- (Fast inserters take the same slots as plain ones: two on a side of a 3x3 machine, which a fast
-- inserter serves nearly six plain ones' worth. A shape with an inserter on every tile, and rows of
-- poles between the machines, is laid out but not asked for.)
---@param machine_size integer
---@return integer
function layout.max_input_inserters(machine_size)
  return machine_size - 1
end

-- The most inserters the output side gets: the same, but never more than the two
-- that the winding output belt serves (one for each lane). More would need splitters
-- or underground belts.
---@param machine_size integer
---@return integer
function layout.max_output_inserters(machine_size)
  return math.min(WINDING_OUTPUT_INSERTERS, machine_size - 1)
end

-- Whether `layout.build` can lay out a machine this many tiles wide and tall.
---@param machine_size integer|nil
---@return boolean
function layout.supports_machine_size(machine_size)
  return SUPPORTED_MACHINE_SIZES[machine_size] == true
end

-- Where things go, worked out once from the shape.
---@class bpgen.Geometry
---@field size integer  machine size
---@field input_belt_column integer  where the belt that feeds the machines runs (the previous column's output belt, in a chain)
---@field input_inserter_column integer
---@field machine_column integer
---@field input_count integer  input inserters per machine
---@field input_fast boolean  whether those are fast inserters
---@field long_count integer  long-handed input inserters per machine, in the rows under the plain ones
---@field output_count integer  output inserters per machine
---@field output_fast boolean  whether those are fast inserters
---@field output_inserter_column integer
---@field output_belt_column integer  the belt the product leaves on: the outer one when the belt winds
---@field output_winds boolean  the output belt winds, so that the output inserters fill a lane each and both lanes carry product (see `Builder:add_winding_output_belt`)
---@field has_pole_rows boolean  machines are separated by rows of poles
---@field powered_from_output boolean  the poles beside the output side power the inserters of the input side too (see `bpgen.Shape.powered_from_output`)
---@field second_belt boolean  the column draws its two input belts woven, the second in the column west of the input belt (see `Builder:add_woven_input_belts`)
---@field fuel_weave boolean  the column's fuel has a belt of its own in the column east of the input belt, woven with it (see `Builder:add_fuel_weave`); the inserters and the machines stand one column further east
---@field first_row integer  tile row where the belts start, the first machine's top edge (1 or more with pole rows) unless the column has a belt of fuel, and the row every column of a chain starts on
---@field first_machine_row integer  tile row of the first machine's top edge: `first_row`, or one machine lower for a column with a belt of fuel (`Shape.fuel_belt`), so that the plates of all the furnaces before it reach its inserters
---@field spacing integer  rows from one machine's top edge to the next

-- Whether the machines are separated by rows of poles: when an inserter takes every
-- tile beside a machine on one side, no tile is free for a pole. A full input side does not
-- count when the poles beside the output side reach it (`Shape.powered_from_output`).
---@param shape bpgen.Shape
---@return boolean
local function needs_pole_rows(shape)
  local input = shape.powered_from_output and 0 or shape.input_inserters + (shape.long_inserters or 0)
  return math.max(input, shape.output_inserters) >= shape.machine_size
end

-- Where a column sits in its chain. A single column is a chain of one.
---@class bpgen.Place
---@field origin integer  tile column of the column's input belt
---@field first_row integer  tile row of the first machine's top edge: the same for every column of a chain
---@field feeds_next boolean  the output belt feeds another column of machines, so it stays a plain belt (but for a column of paired machines, whose belt winds in either case)
---@field draws_input_belt boolean  false when the previous column's output belt is this one's input belt
---@field draws_output_belt boolean  false when whoever uses the block draws its product belt (see `bpgen.Block`)
---@field load number  how many machines' worth of work the column does (see `bpgen.StageLayout`)
---@field takes_fuel boolean  the column burns fuel that rides the free lane of its input belt, which therefore runs south (see `bpgen.StageLayout.fuel_feed`)

-- Whether the output belt of a column winds, so that both its lanes carry product. Without pole rows, which would take the
-- rows the belt needs, it does for:
--   * paired machines (`Shape.output_paired`) with one output inserter each, of any size, whatever the belt feeds: the
--     machines go in twos and fill a lane each (see `Builder:add_winding_output_belt`), which needs at least two of them,
--     since one alone fills one lane;
--   * the last column of the blueprint (the belt of a column that feeds another is the next one's input belt, so it stays a
--     plain one) of 3x3 machines: with two output inserters, which fill a lane each, or with one fast inserter, when the
--     machines go in twos, as above.
---@param shape bpgen.Shape
---@param place bpgen.Place
---@param has_pole_rows boolean
---@param machine_count integer
---@return boolean
local function winds_output(shape, place, has_pole_rows, machine_count)
  if has_pole_rows then
    return false
  end
  local fills_a_lane = shape.output_inserters == 1 and machine_count >= 2 -- one inserter each, with a partner to fill the other lane
  if shape.output_paired then
    return fills_a_lane
  end
  if place.feeds_next or shape.machine_size ~= WINDING_MACHINE_SIZE then
    return false
  end
  return shape.output_inserters == WINDING_OUTPUT_INSERTERS or (fills_a_lane and shape.output_fast == true)
end

-- The columns of the input inserters and of the machines, from the column of the input belt. The belt of the fuel of a
-- stage that has one (`Shape.fuel_belt`) is between the input belt and the inserters, which takes a column.
---@param shape bpgen.Shape
---@param origin integer  tile column of the input belt
---@return integer inserter_column
---@return integer machine_column
local function input_columns(shape, origin)
  local shift = shape.fuel_belt and 1 or 0
  return origin + INPUT_INSERTER_OFFSET + shift, origin + MACHINE_OFFSET + shift
end

---@param shape bpgen.Shape
---@param place bpgen.Place
---@param machine_count integer
---@return bpgen.Geometry
local function geometry_of(shape, place, machine_count)
  local has_pole_rows = needs_pole_rows(shape)
  local output_winds = winds_output(shape, place, has_pole_rows, machine_count)
  local inserter_column, machine_column = input_columns(shape, place.origin)
  local size = shape.machine_size
  return {
    size = size,
    input_count = shape.input_inserters,
    input_fast = shape.input_fast == true,
    long_count = shape.long_inserters or 0,
    output_count = shape.output_inserters,
    output_fast = shape.output_fast == true,
    input_belt_column = place.origin,
    input_inserter_column = inserter_column,
    machine_column = machine_column,
    output_inserter_column = machine_column + size,
    output_belt_column = machine_column + size + (output_winds and 2 or 1),
    output_winds = output_winds,
    has_pole_rows = has_pole_rows,
    powered_from_output = shape.powered_from_output == true,
    second_belt = shape.second_input_belt == true,
    fuel_weave = shape.fuel_belt == true,
    first_row = place.first_row,
    first_machine_row = place.first_row + (shape.fuel_belt and size or 0),
    spacing = has_pole_rows and size + 1 or size,
  }
end

-- The poles added so far, on each side of the machines, top to bottom.
---@class bpgen.Poles
---@field input table<integer, bpgen.Entity>
---@field output table<integer, bpgen.Entity>

-- How a belt shared by two columns runs.
---@class bpgen.SharedBelt
---@field end_row integer  one past the belt's last tile
---@field direction defines.direction  the way the belt runs

-- A blueprint under construction: everything the steps of the layout share
-- (what is being built, where things go, the poles so far) lives in one table,
-- and each step is a method that reads and adds to it. `Builder.__index = Builder`
-- is Lua's way of giving every builder these methods: when `builder:add_belts()`
-- finds no `add_belts` in the builder itself, Lua looks it up in `Builder`. A
-- builder only lives for one `layout.build` call and is never stored in the save.
---@class bpgen.Builder
---@field entities bpgen.Entity[]  the blueprint so far
---@field geometry bpgen.Geometry
---@field names bpgen.Names
---@field pole_reach integer  how many rows above and below itself a pole powers (see `layout.pole_reach`)
---@field machine_count integer
---@field poles bpgen.Poles
---@field draws_input_belt boolean  false when the previous column's output belt is this one's input belt
---@field draws_output_belt boolean  false when whoever uses the block draws its product belt
---@field load number  how many machines' worth of work the column does, which decides which way the belt to the next column runs
---@field takes_fuel boolean  whether the column's input belt carries its fuel on the lane the product does not use
---@field shared_belt? bpgen.SharedBelt  how the output belt runs, when the next column shares it
---@field winding_mirror? integer  while the winding belt that runs north is drawn: the sum of the rows a tile and its reflection are in (see `Builder:add_winding_tile`)
---@field pole_plan? {input: table<integer, integer>, output: table<integer, integer>}  the rows of the poles beside the machines, by machine number, once the machines are added (see `Builder:side_pole_plan`)
local Builder = {}
Builder.__index = Builder

-- `entities` is the list the blueprint is collected in, shared by all the columns
-- of a chain (so that the numbers are unique). `place` tells where the column sits.
---@param machine_count integer
---@param names bpgen.Names
---@param shape bpgen.Shape
---@param entities bpgen.Entity[]
---@param place bpgen.Place
---@return bpgen.Builder
function Builder.new(machine_count, names, shape, entities, place)
  local geometry = geometry_of(shape, place, machine_count)
  local pole_reach = layout.pole_reach(assert(names.pole_supply_distance, "layout: the names give no supply distance for the pole"))
  assert(not geometry.powered_from_output or pole_reach > geometry.size,
    "layout: the poles beside the output side do not reach the input inserters")
  return setmetatable({
    entities = entities,
    geometry = geometry,
    names = names,
    pole_reach = pole_reach,
    machine_count = machine_count,
    poles = {input = {}, output = {}},
    draws_input_belt = place.draws_input_belt,
    draws_output_belt = place.draws_output_belt,
    load = place.load,
    takes_fuel = place.takes_fuel,
  }, Builder)
end

-- Stores an entity and numbers it, because blueprints identify entities by number.
---@param entity bpgen.NewEntity
---@return bpgen.Entity
function Builder:add(entity)
  local numbered = entity --[[@as bpgen.Entity]] -- it gets its number just below
  self.entities[#self.entities + 1] = numbered
  numbered.entity_number = #self.entities
  return numbered
end

-- Records a copper wire. Each wire is stored once, on the pole it starts from, as
-- {from number, connector, to number, connector}.
---@param from bpgen.Entity
---@param to bpgen.Entity
function layout.connect_poles(from, to)
  local connector = defines.wire_connector_id.pole_copper
  from.wires = from.wires or {}
  from.wires[#from.wires + 1] = {from.entity_number, connector, to.entity_number, connector}
end

---@param from bpgen.Entity
---@param to bpgen.Entity
function Builder:connect(from, to)
  layout.connect_poles(from, to)
end

-- The tile row of the top edge of machine number `index` (from 0).
---@param index integer
---@return integer
function Builder:machine_top(index)
  return self.geometry.first_machine_row + index * self.geometry.spacing
end

-- The tile row of the first of `count` inserters in a column beside machine number `index` (from 0). The machines go in
-- twos: the inserters of the first machine of a pair (the first, third, ... machine) stand in its top rows, those of
-- the second (the second, fourth, ...) in its bottom rows, so that the second machine of a pair and the first of the
-- next have theirs together. A machine without a partner, the last of an odd number, is like the first. The same on
-- every belt, so that the inserters of two columns that share a belt agree.
---@param index integer
---@param count integer
---@return integer
function Builder:inserter_top(index, count)
  local top = self:machine_top(index)
  if index % 2 == 1 then
    return top + self.geometry.size - count
  end
  return top
end

-- The tile row of the first input inserter of machine `index`, plain and long-handed together.
---@param index integer
---@return integer
function Builder:input_top(index)
  return self:inserter_top(index, self.geometry.input_count + self.geometry.long_count)
end

-- The tile row of the first plain input inserter of machine `index`. The input inserters follow the same pattern
-- as the machines: the plain ones, then the long-handed ones under them, for a machine whose inserters are in its top
-- rows, and the mirror image for one whose inserters are in its bottom rows (plain, long | long, plain for two
-- machines), so that the plain inserters of two machines side by side stand together too.
---@param index integer
---@return integer
function Builder:plain_input_top(index)
  if index % 2 == 1 then
    return self:input_top(index) + self.geometry.long_count
  end
  return self:input_top(index)
end

-- The tile row of the first long-handed input inserter of machine `index`.
---@param index integer
---@return integer
function Builder:long_input_top(index)
  if index % 2 == 1 then
    return self:input_top(index)
  end
  return self:input_top(index) + self.geometry.input_count
end

-- The tile row of the last plain input inserter, where the input belt ends (the long-handed ones reach over it to
-- another belt).
---@return integer
function Builder:last_input_row()
  return self:plain_input_top(self.machine_count - 1) + self.geometry.input_count - 1
end

-- The tile row of the first long-handed input inserter, in the first machine.
---@return integer
function Builder:first_long_row()
  return self:long_input_top(0)
end

-- The tile row of the last long-handed input inserter, in the last machine.
---@return integer
function Builder:last_long_row()
  return self:long_input_top(self.machine_count - 1) + self.geometry.long_count - 1
end

-- The tile row of the last tile of the input belts that the column draws. Belt a of a column built wide ends in the exit
-- of its hop under belt b's detour, which an odd number of furnaces leaves two rows under the last inserter (the pattern
-- is four rows for each pair of furnaces, and the last furnace takes its first two).
---@return integer
function Builder:last_input_belt_row()
  local last = self:last_input_row()
  local woven = self.geometry.second_belt or self.geometry.fuel_weave
  if woven and (last - self.geometry.first_row) % WEAVE_ROWS == 1 then
    return last + 2
  end
  return last
end

-- The tile row of the first output inserter of machine number `index` (from 0).
---@param index integer
---@return integer
function Builder:output_inserter_row(index)
  return self:inserter_top(index, self.geometry.output_count)
end

-- The tile row of the last output inserter, where the last machine drops its product.
---@return integer
function Builder:last_output_row()
  return self:output_inserter_row(self.machine_count - 1) + self.geometry.output_count - 1
end

-- One past the last row of the column of machines.
---@return integer
function Builder:end_row()
  return self:machine_top(self.machine_count)
end

-- One past the last row the output belt runs to: where the belt to the next column ends when that column shares it
-- (see `bpgen.SharedBelt`), else the end of the column.
---@return integer
function Builder:output_belt_end_row()
  return self.shared_belt and self.shared_belt.end_row or self:end_row()
end

-- Whether the output belt runs north, to the next column, which needs the plates of the lowest machines.
---@return boolean
function Builder:output_runs_north()
  return self.shared_belt ~= nil and self.shared_belt.direction == defines.direction.north
end

-- One past the last row that the column takes with its belts: the winding belt that runs north starts a tile past the
-- end of its belt, which it needs behind its first stub (see `Builder:add_winding_output_belt`).
---@return integer
function Builder:extent_end_row()
  if self.geometry.output_winds and self:output_runs_north() then
    return math.max(self:end_row(), self:output_belt_end_row() + 1)
  end
  return self:end_row()
end

---@param column integer  tile column
---@param row integer  tile row
---@param direction defines.direction  the way the belt runs
function Builder:add_belt(column, row, direction)
  self:add({name = self.names.belt, position = grid.position(column, row), direction = direction})
end

-- A run of belt tiles down one column of the layout, all running the same way.
---@param column integer  tile column
---@param first_row integer  tile row of the first belt tile
---@param length integer  how many tiles
---@param direction defines.direction  the way the belt runs
function Builder:add_belt_column(column, first_row, length, direction)
  for row = first_row, first_row + length - 1 do
    self:add_belt(column, row, direction)
  end
end

-- One tile of the winding belt. The belt is worked out as if it ran south; a belt that runs north is that belt reflected
-- in the rows it takes (row r of the one that runs south is row `winding_mirror - r` of the one that runs north, and
-- every tile that faces south or north faces the other way), which gives the same inserters the same lanes: a lane is the
-- same side of the belt, east or west, whichever way the belt runs.
---@param column integer  tile column
---@param row integer  tile row, in the frame of the belt that runs south
---@param direction defines.direction  the way the tile faces, in that frame
function Builder:add_winding_tile(column, row, direction)
  local mirror = self.winding_mirror
  if mirror then
    local south, north = defines.direction.south, defines.direction.north
    row = mirror - row
    direction = (direction == south and north) or (direction == north and south) or direction
  end
  self:add_belt(column, row, direction)
end

-- A run of winding belt tiles down one column, all facing south (in the frame of the belt that runs south).
---@param column integer  tile column
---@param first_row integer  tile row of the first tile
---@param length integer  how many tiles
function Builder:add_winding_column(column, first_row, length)
  for row = first_row, first_row + length - 1 do
    self:add_winding_tile(column, row, defines.direction.south)
  end
end

-- The first tile of the next stretch of the winding belt, and the column it runs in, for a seam: two rows (`row` and the
-- one under it) beside two output inserters. The belt comes down in the column `column` (inner, beside the inserters,
-- or outer). From the inner column it curves east in the first row, where the first inserter drops on the curve (the
-- outer lane), and runs on in the outer column, which the second inserter's stub side-loads (the inner lane). From the
-- outer column the first inserter's stub side-loads it (the inner lane), and in the second row it turns west into the
-- inner column, where the second inserter drops on the curve (the outer lane). An inserter alone at the end has only
-- the first row.
---@param row integer  the row of the first inserter
---@param column integer  the column the belt comes down in
---@param has_lower boolean  whether a second inserter stands under the first
---@return integer next_row  the first row after the seam
---@return integer next_column  the column the belt runs on in
function Builder:add_seam(row, column, has_lower)
  local inner = self.geometry.output_inserter_column + 1
  local outer = self.geometry.output_belt_column
  local south, east, west = defines.direction.south, defines.direction.east, defines.direction.west
  self:add_winding_tile(inner, row, east)
  self:add_winding_tile(outer, row, south)
  if not has_lower then
    return row + 1, outer
  end
  if column == inner then
    self:add_winding_tile(inner, row + 1, east)
    self:add_winding_tile(outer, row + 1, south)
    return row + 2, outer
  end
  self:add_winding_tile(inner, row + 1, south)
  self:add_winding_tile(outer, row + 1, west)
  return row + 2, inner
end

-- The tile rows of every output inserter of the column, top to bottom.
---@return integer[]
function Builder:output_inserter_rows()
  local rows = {}
  for index = 0, self.machine_count - 1 do
    local first = self:output_inserter_row(index)
    for row = first, first + self.geometry.output_count - 1 do
      rows[#rows + 1] = row
    end
  end
  return rows
end

-- Runs the winding belt on from `row` to `stop` in the column it came down in, hopping to the outer column in the
-- first row if it is in the inner one and there is a row to spare, so that the next seam starts in the outer column.
---@param row integer  the first row of the stretch
---@param column integer  the column the belt comes down in
---@param stop integer  the last row of the stretch (above `row` when there is none)
---@return integer column  the column the belt comes down in after it
function Builder:add_winding_run(row, column, stop)
  local inner = self.geometry.output_inserter_column + 1
  local outer = self.geometry.output_belt_column
  if column == inner and stop >= row then
    self:add_winding_tile(inner, row, defines.direction.east)
    self:add_winding_tile(outer, row, defines.direction.south)
    self:add_winding_column(outer, row + 1, stop - row)
    return outer
  end
  self:add_winding_column(column, row, stop - row + 1)
  return column
end

-- The rows of the inserters of the belt that runs north, as the belt that runs south sees them: reflected in the rows
-- the belt takes, from the top of that belt down.
---@param rows integer[]  the tile rows of the output inserters, top to bottom
---@param mirror integer  see `Builder:add_winding_tile`
---@return integer[]
local function reflected(rows, mirror)
  local found = {}
  for index = #rows, 1, -1 do
    found[#found + 1] = mirror - rows[index]
  end
  return found
end

-- The winding output belt, so that the product rides both lanes of one belt: of the last column of a blueprint of 3x3
-- machines, and of columns of paired machines of any size, which may feed another column (see `winds_output`). The
-- inserters stand together at the seams (see `inserter_top`): the belt has a seam (see `add_seam`) for
-- every two inserters in adjacent rows, and one for an inserter alone, from the top. Between two seams it hops from
-- the inner to the outer column if it has a row to spare, so that every seam after the first starts in the outer
-- column. A belt that runs north, to a next column that needs the plates of the lowest machines, is the same belt
-- reflected (see `add_winding_tile`), so it starts a tile past its last row, in row `end` (`extent_end_row`).
-- Drawn for four machines with one fast inserter each (rows 0 to 14, `}` the inserters):
--
--        v       row -1: the belt starts in the inner column, a tile behind the first curve
--      } > v     row 0: the first machine's inserter drops on the curve (outer lane)
--          v     rows 1 to 4: the belt runs on in the outer column
--          v
--          v
--          v
--      } > v     row 5: the second machine's inserter drops on a stub that side-loads (inner lane)
--      } v <     row 6: the belt turns west; the third machine's inserter drops on the curve (outer lane)
--        v       rows 7 to 10: it runs on in the inner column and hops to the outer one in row 7
--        v
--        v
--        v
--      } > v     row 11: the fourth machine's inserter drops on a stub (inner lane)
--
-- So the lanes go outer, inner, outer, inner, ...: every machine takes the other lane than the one before it.
-- With two inserters on each machine the two of a machine are one seam, so each machine fills both lanes.
function Builder:add_winding_output_belt()
  local inner = self.geometry.output_inserter_column + 1
  local first, end_row = self:machine_top(0), self:output_belt_end_row()
  local rows = self:output_inserter_rows()
  if self:output_runs_north() then
    self.winding_mirror = first + end_row - 1
    rows = reflected(rows, self.winding_mirror)
  end
  local start = first - 1
  self:add_winding_column(inner, start, rows[1] - start) -- a tile behind the first curve, which it needs
  local column, k = inner, 1
  while k <= #rows do
    local width = rows[k + 1] == rows[k] + 1 and 2 or 1
    local next_row, next_column = self:add_seam(rows[k], column, width == 2)
    local following = rows[k + width] or end_row
    column = self:add_winding_run(next_row, next_column, following - 1)
    k = k + width
  end
  self.winding_mirror = nil
  self:continue_belt_north()
end

-- A belt that runs north ends at the top, and a column that starts lower than the next column (the steel furnaces, one furnace
-- lower) leaves that column's first inserters above the belt: it goes on up to the first row of the chain, in the column the
-- belt leaves on (the outer one, for the winding belt, which ends there).
function Builder:continue_belt_north()
  local geometry = self.geometry
  if self:output_runs_north() then
    self:add_belt_column(geometry.output_belt_column, geometry.first_row, self:machine_top(0) - geometry.first_row, defines.direction.north)
  end
end

-- The input belt runs south from the first machine's top row and stops at the last
-- input inserter: nothing below it would be picked up. (A column that eats what other
-- columns make gets the rest of its input belt, below it, from whoever uses it, and turns
-- the belt to run north: the products reach it from below.)
function Builder:add_input_belt()
  local geometry = self.geometry
  local first_row = geometry.first_row
  self:add_belt_column(geometry.input_belt_column, first_row, self:last_input_row() - first_row + 1, defines.direction.south)
end

---@param column integer  tile column
---@param row integer  tile row
---@param kind "input"|"output"  the entrance or the exit
function Builder:add_underground(column, row, kind)
  local name = assert(self.names.underground, "layout: the names give no underground belt for the woven input belts")
  self:add({name = name, position = grid.position(column, row), direction = defines.direction.south, type = kind})
end

-- The place of a row in the weave of the input belts: 0 to `WEAVE_ROWS` - 1, from the first row of the column.
---@param row integer
---@return integer
function Builder:weave_step(row)
  return (row - self.geometry.first_row) % WEAVE_ROWS
end

-- The inner column of the weave of two input belts, the one beside the inserters, which holds the belt that goes under:
-- an entrance in step 0, the detour of the other belt in steps 1 and 2 (it comes in, east to west, in a tile that runs
-- south and one that runs west), an exit in step 3, and the next entrance right under it. An odd number of machines ends
-- in step 1, where an entrance would have no exit: an exit follows two rows under the last inserter.
---@param inner integer  tile column
function Builder:add_weave_hop(inner)
  local first_row, direction = self.geometry.first_row, defines.direction
  for row = first_row, self:last_input_row() do
    local step = self:weave_step(row)
    if step == 0 then
      self:add_underground(inner, row, "input")
    elseif step == 3 then
      self:add_underground(inner, row, "output")
    else
      self:add_belt(inner, row, step == 1 and direction.south or direction.west)
    end
  end
  if self:last_input_belt_row() > self:last_input_row() then
    self:add_underground(inner, self:last_input_belt_row(), "output")
  end
end

-- The input belts of a column built wide (see `Shape.second_input_belt`), which both come down from the band, woven so
-- that the two plain inserters of every furnace reach both. In the inner column, beside the inserters, belt a goes
-- under for two rows (see `add_weave_hop`), and in those two rows belt b comes into the inner column from the outer one
-- and goes back (only curves, so that its lanes stay as they are): the outer column turns east in step 1. The inserters
-- take from the tiles of the entrances and exits (belt a) and from the tiles of the detour (belt b). The pattern is
-- `WEAVE_ROWS` rows for each pair of furnaces.
function Builder:add_woven_input_belts()
  local geometry = self.geometry
  self:add_weave_hop(geometry.input_belt_column)
  for row = geometry.first_row, self:last_input_row() do
    self:add_belt(geometry.input_belt_column - 1, row, self:weave_step(row) == 1 and defines.direction.east or defines.direction.south)
  end
end

-- Turns the tile of the belt that the column before shares with this one (a belt that runs south) to run east, for the
-- detour of the weave: the plates of that belt go into the column of the fuel and come back (see `add_fuel_weave`).
---@param row integer  tile row
function Builder:turn_shared_belt(row)
  local column = self.geometry.input_belt_column
  for _, entity in ipairs(self.entities) do
    local tile = grid.top_left_tile(entity.position)
    if entity.name == self.names.belt and tile.x == column and tile.y == row then
      assert(entity.direction == defines.direction.south, "layout: the belt before a stage with a belt of fuel does not run south there")
      entity.direction = defines.direction.east
      return
    end
  end
  error("layout: no belt before a stage with a belt of fuel in its row " .. row)
end

-- The belt of fuel of a column built wide that burns fuel (see `Shape.fuel_belt`), woven with the belt before it, the
-- belt of plates of the column before, which winds and puts them on both lanes. The fuel goes under in the column beside
-- the inserters (see `add_weave_hop`), and the plates, in the column before it, turn into that column in step 1 and
-- come back in step 2: each machine takes the fuel with one inserter and the plates with the other.
function Builder:add_fuel_weave()
  local geometry = self.geometry
  self:add_weave_hop(geometry.input_belt_column + 1)
  for row = geometry.first_row, self:last_input_row() do
    if self:weave_step(row) == 1 then
      self:turn_shared_belt(row)
    end
  end
end

-- The output belt starts at the first machine's top row and runs south (down the
-- page), unless the next column shares it and needs it to run north. It keeps the full
-- height of the column, so the products have somewhere to go (and winds, for two output
-- inserters on a 3x3 machine). In a chain the next column's input belt is this output
-- belt, so that one is drawn here, as far as either column needs it.
function Builder:add_output_belt()
  local geometry = self.geometry
  if geometry.output_winds then
    self:add_winding_output_belt()
    return
  end
  local shared = self.shared_belt
  local direction = shared and shared.direction or defines.direction.south
  self:add_belt_column(geometry.output_belt_column, geometry.first_row, self:output_belt_end_row() - geometry.first_row, direction)
end

-- The belts this column is responsible for: it draws no input belt when the previous
-- column's output belt is its input belt, and no output belt when whoever uses the block
-- draws the product belt.
function Builder:add_belts()
  if self.geometry.fuel_weave then
    self:add_fuel_weave()
  elseif self.draws_input_belt and self.geometry.second_belt then
    self:add_woven_input_belts()
  elseif self.draws_input_belt then
    self:add_input_belt()
  end
  if self.draws_output_belt then
    self:add_output_belt()
  end
end

-- The prototype name of the plain or the fast inserter.
---@param fast boolean
---@return string
function Builder:inserter_name(fast)
  if not fast then
    return self.names.inserter
  end
  return assert(self.names.fast_inserter, "layout: a side of fast inserters needs the name of the fast inserter")
end

-- `count` inserters of prototype `name` in a column, one under the next, from row `top`.
-- An inserter's `direction` is the side it PICKS UP from. All of them move things
-- eastward (belt -> machine, machine -> belt), so all pick up from the west.
---@param name string
---@param column integer
---@param top integer
---@param count integer
function Builder:add_inserters(name, column, top, count)
  for row = top, top + count - 1 do
    self:add({name = name, position = grid.position(column, row), direction = defines.direction.west})
  end
end

-- One pole on one side of the machines, at the given row, added to that side's top-to-bottom list.
---@param side "input"|"output"
---@param row integer
function Builder:add_pole(side, row)
  local geometry = self.geometry
  local column = side == "input" and geometry.input_inserter_column or geometry.output_inserter_column
  local pole = self:add({name = self.names.pole, position = grid.position(column, row)})
  self.poles[side][#self.poles[side] + 1] = pole
end

-- Which machines get a pole on one side, and where, for `count` inserters on the side: the machines from the top down,
-- each unless a pole above it reaches its inserters (a pole powers `pole_reach` tiles each way: two for a small pole,
-- three for a medium one, which so powers the inserters of two machines of a pair with one pole). A machine whose
-- inserters are in its top rows has its pole in the free tile under them, one whose inserters are in its bottom rows
-- in the free tile above them. With `whole_machine` the poles also have to reach every row of the machine, which is
-- where the inserters of a full side on the other side of it stand (`Shape.powered_from_output`).
---@param count integer
---@param whole_machine? boolean
---@return table<integer, integer>  the tile row of the pole of each machine that has one, by machine number from 0
function Builder:side_pole_plan(count, whole_machine)
  local plan, reach = {}, -math.huge
  for index = 0, self.machine_count - 1 do
    local first = self:inserter_top(index, count)
    local last = whole_machine and self:machine_top(index) + self.geometry.size - 1 or first + count - 1
    if last > reach then
      local row = index % 2 == 1 and first - 1 or first + count
      plan[index] = row
      reach = row + self.pole_reach
    end
  end
  return plan
end

-- The poles beside the free tiles of one machine's two sides.
---@param index integer
function Builder:add_machine_poles(index)
  for _, side in ipairs({"input", "output"}) do
    local row = self.pole_plan[side][index]
    if row then
      self:add_pole(side, row)
    end
  end
end

-- One machine with its inserters, and its poles if it is one of those that get them.
-- `index` counts machines from 0 down the column.
---@param index integer
function Builder:add_machine_row(index)
  local geometry = self.geometry
  local size = geometry.size

  self:add({name = self.names.machine, position = grid.position(geometry.machine_column, self:machine_top(index), size, size), recipe = self.names.recipe})
  self:add_inserters(self:inserter_name(geometry.input_fast), geometry.input_inserter_column, self:plain_input_top(index), geometry.input_count)
  self:add_inserters(self.names.long_inserter, geometry.input_inserter_column, self:long_input_top(index), geometry.long_count)
  self:add_inserters(self:inserter_name(geometry.output_fast), geometry.output_inserter_column, self:output_inserter_row(index), geometry.output_count)

  if not geometry.has_pole_rows then
    self:add_machine_poles(index)
  end
end

-- The rows of poles above the first machine, between machines and below the last.
function Builder:add_pole_rows()
  for index = 0, self.machine_count do
    local row = self:machine_top(index) - 1
    self:add_pole("input", row)
    self:add_pole("output", row)
  end
end

-- The machines with their inserters, and the poles: in rows between them when the
-- sides are full, otherwise in the free tiles beside them.
function Builder:add_machines()
  local geometry = self.geometry
  local from_output = geometry.powered_from_output
  self.pole_plan = {
    input = from_output and {} or self:side_pole_plan(geometry.input_count + geometry.long_count),
    output = self:side_pole_plan(geometry.output_count, from_output),
  }
  for index = 0, self.machine_count - 1 do
    self:add_machine_row(index)
  end
  if self.geometry.has_pole_rows then
    self:add_pole_rows()
  end
end

-- Chain the poles down each side, then join the two sides at the top (a column whose input side is powered from the
-- output side has poles on the output side only).
function Builder:wire_poles()
  local poles = self.poles
  for _, side in ipairs({poles.input, poles.output}) do
    for i = 2, #side do
      self:connect(side[i - 1], side[i])
    end
  end
  -- `layout.build` needs at least one machine, so there is a first pole on the output side.
  if poles.input[1] then
    self:connect(poles.input[1], poles.output[1])
  end
end

-- The columns of a chain, left to right, joined by wire: the top output pole of each
-- column to the top input pole of the next.
---@param builders bpgen.Builder[]
local function wire_columns(builders)
  ---@type bpgen.Builder|nil
  local previous
  for _, builder in ipairs(builders) do
    if previous then
      previous:connect(previous.poles.output[1], builder.poles.input[1] or builder.poles.output[1])
    end
    previous = builder
  end
end

-- How many rows the column would take if it had only the machines the work needs (a
-- machine that is used for a fifth counts as a fifth). That grows in step with the
-- rate, so comparing two columns' lengths gives the same answer at any rate.
---@return number
function Builder:length_for_load()
  return self.load * self.geometry.spacing
end

-- How the belt between a column and the next one runs: down to the lower of the
-- two columns' last needs, and north when the column is the longer of the two for the
-- work it does, so that the plates of its lowest machines still pass the next
-- column's inserters (see the diagram of the chain above). Otherwise it runs south,
-- which carries the plates on to the next column's lower machines. The lengths come
-- from the work and not from the machines built, so the belt runs the same way for
-- 1 item a minute and for 100 (owner, 2026-11-06 22:59). Equal lengths (within
-- rounding) run north.
---@param builder bpgen.Builder
---@param next_builder bpgen.Builder
local function share_belt(builder, next_builder)
  local last_pickup_row = next_builder:last_input_row()
  local runs_north = not next_builder.takes_fuel -- fuel is side-loaded at the head, which has to be the top
    and builder:length_for_load() >= next_builder:length_for_load() * (1 - LENGTH_TOLERANCE)
    and builder:last_output_row() >= last_pickup_row -- else a plate dropped on it would have no inserter ahead of it
  -- A belt that runs south only reaches the inserters under the first drop: a column that starts lower (`first_machine_row`) than the
  -- next one must not leave an inserter of it above that.
  assert(runs_north or next_builder.takes_fuel or next_builder:input_top(0) >= builder:machine_top(0),
    "layout: a column that starts lower than the next one, whose belt runs south, leaves the inserters above it without plates")
  builder.shared_belt = {
    end_row = math.max(builder:last_output_row(), last_pickup_row) + 1, -- no tail below the last inserter that uses the belt
    direction = runs_north and defines.direction.north or defines.direction.south,
  }
end

-- The row every column of a chain starts on: one below the pole row that a column
-- with pole rows needs above its first machine, so that all the columns line up.
---@param stages bpgen.StageLayout[]
---@return integer
local function chain_first_row(stages)
  for _, stage in ipairs(stages) do
    if needs_pole_rows(stage.shape) then
      return 1
    end
  end
  return 0
end

-- Where column `index` of a chain of `count` goes. The last column's output belt is the
-- chain's product belt: `options.product_belt` says whether this chain draws it (and
-- may wind it) or whoever uses the block does.
---@param stage bpgen.StageLayout
---@param index integer
---@param count integer
---@param origin integer  tile column of the column's input belt
---@param first_row integer
---@param options bpgen.BlockOptions
---@return bpgen.Place
local function place_of(stage, index, count, origin, first_row, options)
  local is_last = index == count
  return {
    origin = origin,
    first_row = first_row,
    feeds_next = not (is_last and options.product_belt),
    draws_input_belt = index == 1,
    draws_output_belt = not is_last or options.product_belt,
    load = stage.load or stage.machine_count,
    takes_fuel = stage.fuel_feed ~= nil,
  }
end

-- One builder per column of a chain, left to right, each starting where the previous
-- column's output belt is, and the belt between two columns shared.
---@param stages bpgen.StageLayout[]
---@param names bpgen.SharedNames
---@param entities bpgen.Entity[]
---@param options bpgen.BlockOptions
---@return bpgen.Builder[]
local function columns_of(stages, names, entities, options)
  local builders = {}
  local origin = 0
  local first_row = chain_first_row(stages)
  for index, stage in ipairs(stages) do
    local stage_names = {
      machine = stage.machine, recipe = stage.recipe, belt = names.belt, inserter = names.inserter,
      long_inserter = names.long_inserter, fast_inserter = names.fast_inserter, underground = names.underground, pole = names.pole,
      pole_supply_distance = names.pole_supply_distance, pole_wire_distance = names.pole_wire_distance,
    }
    local place = place_of(stage, index, #stages, origin, first_row, options)
    local builder = Builder.new(stage.machine_count, stage_names, stage.shape, entities, place)
    builders[index] = builder
    origin = builder.geometry.output_belt_column -- the next column's input belt
    if index > 1 then
      share_belt(builders[index - 1], builder)
    end
    assert(not builder.takes_fuel or (index > 1 and not builders[index - 1].geometry.has_pole_rows),
      "layout: fuel comes down beside the output inserters of the column before, which needs a column with no pole row")
  end
  return builders
end

-- Where the fuel has to arrive for each column of the chain that takes it from the belt before it.
---@param stages bpgen.StageLayout[]
---@param builders bpgen.Builder[]
---@return bpgen.FuelFeed[]
local function fuel_feeds_of(stages, builders)
  local feeds = {}
  for index, builder in ipairs(builders) do
    if builder.takes_fuel then
      local woven = builder.geometry.fuel_weave
      feeds[#feeds + 1] = {
        stage = stages[index], belt_column = builder.geometry.input_belt_column + (woven and 1 or 0), row = builder.geometry.first_row, woven = woven,
      }
    end
  end
  return feeds
end

-- The poles of every column.
---@param builders bpgen.Builder[]
---@return bpgen.Entity[]
local function poles_of(builders)
  local poles = {}
  for _, builder in ipairs(builders) do
    for _, side in ipairs({builder.poles.input, builder.poles.output}) do
      for _, pole in ipairs(side) do
        poles[#poles + 1] = pole
      end
    end
  end
  return poles
end

-- One past the last row of the tallest column (and of the winding belt that runs north, which starts below the end of
-- its belt). When the first column is fed raw items, also one past the free row that
-- its belts need under their last tile, which would otherwise flow into whatever runs under the column (the last
-- machine of an odd number has its inserters in its bottom rows, so the belt reaches the bottom of the column). A column
-- that eats what other columns make has the rest of its belt drawn by whoever uses it.
---@param builders bpgen.Builder[]
---@param raw_fed boolean  whether the first column is fed raw items
---@return integer
local function tallest_end_row(builders, raw_fed)
  local height = 0
  for _, builder in ipairs(builders) do
    height = math.max(height, builder:extent_end_row())
    if builder.geometry.fuel_weave then
      height = math.max(height, builder:last_input_belt_row() + 2) -- the belt of its fuel ends in an exit, like a belt of raw items
    end
  end
  if raw_fed then
    height = math.max(height, builders[1]:last_input_belt_row() + 2)
  end
  return height
end

-- Where the belts of raw items start, in the block's frame: the input belt of the first column, and its second input belt
-- when the column draws one (every machine of such a column has an inserter that takes from it).
---@param stage bpgen.StageLayout
---@param first bpgen.Builder  the builder of the first column
---@return bpgen.RawBelt[]
local function raw_belts_of(stage, first)
  local geometry = first.geometry
  local belts = {{stage = stage, column = geometry.input_belt_column, row = geometry.first_row}}
  if geometry.second_belt then
    belts[2] = {stage = stage, column = geometry.input_belt_column - 1, row = geometry.first_row}
  end
  return belts
end

-- `stages` go from the one fed raw items (or, for a column that eats what other columns
-- make, that column alone, whose input belt whoever uses it extends) to the last. Returns the
-- chain as a block: its entities, which are numbered from 1 in
-- a frame whose x = 0 is the input belt of the first column and y = 0 its first row, and
-- what whoever uses it needs to know about it (see `bpgen.Block`). The belt of the first
-- column is listed in `raw_belts`, as if it carried raw items: whoever uses a column that
-- is not fed raw items ignores it.
---@param stages bpgen.StageLayout[]  at least one
---@param names bpgen.SharedNames
---@param options bpgen.BlockOptions
---@return bpgen.Block
function layout.chain_block(stages, names, options)
  local entities = {}
  local builders = columns_of(stages, names, entities, options)
  for _, builder in ipairs(builders) do
    builder:add_belts()
    builder:add_machines()
    builder:wire_poles()
  end
  wire_columns(builders)
  local first, last = builders[1], builders[#builders]
  return {
    entities = entities,
    poles = poles_of(builders),
    product_column = last.geometry.output_belt_column,
    output_rows = {first = last:machine_top(0), last = last:last_output_row()},
    long_rows = first.geometry.long_count > 0 and {first = first:first_long_row(), last = first:last_long_row()} or nil,
    height = tallest_end_row(builders, stages[1].suppliers == nil or stages[1].feed ~= nil),
    raw_belts = raw_belts_of(stages[1], first),
    fuel_feeds = fuel_feeds_of(stages, builders),
  }
end

-- The columns of a chain, from the raw items to the final product, which is drawn
-- (and may wind) at the end.
-- names: {belt, inserter, pole} prototype names (`machine` is each stage's own).
-- `stages` go from the one fed raw items to the one that makes the final product.
-- Returns a list of blueprint entities (tables with entity_number, name, position, ...).
---@param stages bpgen.StageLayout[]  at least one
---@param names bpgen.SharedNames
---@return bpgen.Entity[]
function layout.build_chain(stages, names)
  return layout.chain_block(stages, names, {product_belt = true}).entities
end

-- One column on its own: a chain of one stage.
-- names: {machine, recipe (optional), belt, inserter, pole} prototype names.
-- Returns a list of blueprint entities (tables with entity_number, name, position, ...).
---@param machine_count integer  at least 1
---@param names bpgen.Names
---@param shape bpgen.Shape  the machine size must be one `supports_machine_size` accepts
---@return bpgen.Entity[]
function layout.build(machine_count, names, shape)
  return layout.build_chain({{machine_count = machine_count, machine = names.machine, recipe = names.recipe, shape = shape}}, names)
end

return layout
