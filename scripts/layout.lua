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
--        v      >      [F F]      >       v      <- top row of machine 1
--        v      P      [F F]      P       v      <- bottom row of machine 1 (P = pole)
--        v      >      [F F]      >       v      <- top row of machine 2
--                      [F F]              v      <- bottom row of machine 2 (no poles: they serve every second machine)
--
-- The input belt ends at the last input inserter; the output belt runs the full
-- height, so the products can carry on downstream. Inserters move the input
-- from the belt into the machine, and the product from the machine onto the
-- output belt. A machine may need several inserters on a side, one under the
-- next in the machine's top rows. Small poles supply the inserters and the
-- machine and are wired together.
--
-- While a side has a free tile beside the machine (fewer inserters than rows),
-- the poles go there, one per two machines on each side, in the first free tile
-- after that side's inserters. When a side is full, no tile is free, so the
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
-- each inserter fill a different lane (v > < are belts running south, east, west):
--
--   x:   0     1     2 3 4      5      6      7
--      input input  machine  output inner  outer
--      belt inserter (3x3)  inserter belt  belt
--
--                                             v    <- row -1: an empty belt, so the outer belt is straight
--        v     >    [M M M]     >      >      v    <- row 0: this inserter drops on the stub (>), which
--        v     >    [M M M]     >      v      <       feeds the outer belt from the west: its west lane
--        v     P    [M M M]     P      >      v    <- row 2: the inner belt joins the outer one again
--
-- The outer belt dips west in row 1, to pass the second inserter, which drops on
-- the inner belt (v): the east lane of the belt. Every machine repeats these three
-- rows, so the belt winds down the column and carries the product on both lanes.
-- The first stub would have no belt behind the outer tile it feeds, and Factorio
-- would bend that tile into a curve, so the outer belt starts one row higher, with a
-- tile that carries nothing (row -1 above, drawn as `d`), and the stub side-loads it.
-- The belt needs three rows per machine, which is exactly
-- what a 3x3 machine takes, so it only works for size 3.
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
-- Only the last column's belt winds: the belt between two columns is a plain one,
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
local MACHINES_PER_POLE = 2  -- a small pole's supply area covers two machines' inserters

-- The output belt winds (see the diagram above) for machines of this size with this many output inserters.
local WINDING_MACHINE_SIZE = 3
local WINDING_OUTPUT_INSERTERS = 2

-- Machines of these sizes (in tiles) can be powered by small poles placed as described above.
local SUPPORTED_MACHINE_SIZES = {[2] = true, [3] = true}

-- The most inserters the input side of a machine gets: one fewer than the machine
-- is tall, so one tile beside the machine stays free for a pole. With every tile
-- beside it taken by an inserter, the machines would have to be spaced apart with
-- a row of poles between them (see "pole row" below).
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
---@field input_belt_first_row integer  tile row where that belt starts: the first machine row, or higher when the belt comes down from above
---@field input_inserter_column integer
---@field machine_column integer
---@field input_count integer  input inserters per machine
---@field output_count integer  output inserters per machine
---@field output_inserter_column integer
---@field output_belt_column integer  the belt the product leaves on: the outer one when the belt winds
---@field output_winds boolean  the output belt winds, so its two lanes both carry product
---@field has_pole_rows boolean  machines are separated by rows of poles
---@field first_row integer  tile row of the first machine's top edge, which is also where the belts start (1 or more with pole rows)
---@field spacing integer  rows from one machine's top edge to the next

-- Whether the output belt winds: only for a 3x3 machine with two output
-- inserters, and not when pole rows take the rows the belt needs.
---@param shape bpgen.Shape
---@param has_pole_rows boolean
---@return boolean
local function winds_output(shape, has_pole_rows)
  return not has_pole_rows
    and shape.machine_size == WINDING_MACHINE_SIZE
    and shape.output_inserters == WINDING_OUTPUT_INSERTERS
end

-- Whether the machines are separated by rows of poles: when an inserter takes every
-- tile beside a machine on one side, no tile is free for a pole.
---@param shape bpgen.Shape
---@return boolean
local function needs_pole_rows(shape)
  return math.max(shape.input_inserters, shape.output_inserters) >= shape.machine_size
end

-- Where a column sits in its chain. A single column is a chain of one.
---@class bpgen.Place
---@field origin integer  tile column of the column's input belt
---@field first_row integer  tile row of the first machine's top edge: the same for every column of a chain
---@field feeds_next boolean  the output belt feeds another column of machines, so it stays a plain belt
---@field draws_input_belt boolean  false when the previous column's output belt is this one's input belt
---@field draws_output_belt boolean  false when whoever uses the block draws its product belt (see `bpgen.Block`)
---@field input_belt_rows_above integer  how many rows above the first machine row the input belt starts: 0, unless the belt comes down from above
---@field load number  how many machines' worth of work the column does (see `bpgen.StageLayout`)

---@param shape bpgen.Shape
---@param place bpgen.Place
---@return bpgen.Geometry
local function geometry_of(shape, place)
  local size = shape.machine_size
  local has_pole_rows = needs_pole_rows(shape)
  local output_winds = not place.feeds_next and winds_output(shape, has_pole_rows)
  local machine_column = place.origin + MACHINE_OFFSET
  return {
    size = size,
    input_count = shape.input_inserters,
    output_count = shape.output_inserters,
    input_belt_column = place.origin,
    input_belt_first_row = place.first_row - place.input_belt_rows_above,
    input_inserter_column = place.origin + INPUT_INSERTER_OFFSET,
    machine_column = machine_column,
    output_inserter_column = machine_column + size,
    output_belt_column = machine_column + size + (output_winds and 2 or 1),
    output_winds = output_winds,
    has_pole_rows = has_pole_rows,
    first_row = place.first_row,
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
---@field machine_count integer
---@field poles bpgen.Poles
---@field draws_input_belt boolean  false when the previous column's output belt is this one's input belt
---@field draws_output_belt boolean  false when whoever uses the block draws its product belt
---@field load number  how many machines' worth of work the column does, which decides which way the belt to the next column runs
---@field shared_belt? bpgen.SharedBelt  how the output belt runs, when the next column shares it
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
  return setmetatable({
    entities = entities,
    geometry = geometry_of(shape, place),
    names = names,
    machine_count = machine_count,
    poles = {input = {}, output = {}},
    draws_input_belt = place.draws_input_belt,
    draws_output_belt = place.draws_output_belt,
    load = place.load,
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
  return self.geometry.first_row + index * self.geometry.spacing
end

-- The tile row of the last input inserter, where the input belt ends.
---@return integer
function Builder:last_input_row()
  return self:machine_top(self.machine_count - 1) + self.geometry.input_count - 1
end

-- The tile row of the last output inserter, where the last machine drops its product.
---@return integer
function Builder:last_output_row()
  return self:machine_top(self.machine_count - 1) + self.geometry.output_count - 1
end

-- One past the last row of the column of machines.
---@return integer
function Builder:end_row()
  return self:machine_top(self.machine_count)
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

-- The winding output belt (see the diagram at the top): three rows per machine,
-- the inner column beside the output inserters and the outer column one further out.
-- One more belt runs south in the outer column, in the row above the first machine's
-- top, and carries nothing: without a belt behind it, Factorio bends the first outer
-- tile to meet the stub beside it, which does not work for the first inserter's lane.
-- With the belt behind it, the stub side-loads a straight belt instead.
function Builder:add_winding_output_belt()
  local direction = defines.direction
  local inner = self.geometry.output_inserter_column + 1
  local outer = self.geometry.output_belt_column
  self:add_belt(outer, self:machine_top(0) - 1, direction.south)
  for index = 0, self.machine_count - 1 do
    local top = self:machine_top(index)
    self:add_belt(inner, top, direction.east)
    self:add_belt(inner, top + 1, direction.south)
    self:add_belt(inner, top + 2, direction.east)
    self:add_belt(outer, top, direction.south)
    self:add_belt(outer, top + 1, direction.west)
    self:add_belt(outer, top + 2, direction.south)
  end
end

-- The input belt runs south from its first row (the first machine's top row, unless it
-- comes down from above) and stops at the last input inserter: nothing below it
-- would be picked up.
function Builder:add_input_belt()
  local geometry = self.geometry
  local first_row = geometry.input_belt_first_row
  self:add_belt_column(geometry.input_belt_column, first_row, self:last_input_row() - first_row + 1, defines.direction.south)
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
  local belt_end_row = shared and shared.end_row or self:end_row()
  local direction = shared and shared.direction or defines.direction.south
  self:add_belt_column(geometry.output_belt_column, geometry.first_row, belt_end_row - geometry.first_row, direction)
end

-- The belts this column is responsible for: it draws no input belt when the previous
-- column's output belt is its input belt, and no output belt when whoever uses the block
-- draws the product belt.
function Builder:add_belts()
  if self.draws_input_belt then
    self:add_input_belt()
  end
  if self.draws_output_belt then
    self:add_output_belt()
  end
end

-- `count` inserters in a column, one under the next, from row `top`. An inserter's
-- `direction` is the side it PICKS UP from. All of them move things eastward
-- (belt -> machine, machine -> belt), so all pick up from the west.
---@param column integer
---@param top integer
---@param count integer
function Builder:add_inserters(column, top, count)
  for row = top, top + count - 1 do
    self:add({name = self.names.inserter, position = grid.position(column, row), direction = defines.direction.west})
  end
end

-- One pole on each side, at the given rows, added to the top-to-bottom lists.
---@param input_row integer
---@param output_row integer
function Builder:add_pole_pair(input_row, output_row)
  local pole = self.names.pole
  local input_pole = self:add({name = pole, position = grid.position(self.geometry.input_inserter_column, input_row)})
  local output_pole = self:add({name = pole, position = grid.position(self.geometry.output_inserter_column, output_row)})
  self.poles.input[#self.poles.input + 1] = input_pole
  self.poles.output[#self.poles.output + 1] = output_pole
end

-- One machine with its inserters, and its poles if it is one of those that get them.
-- `index` counts machines from 0 down the column.
---@param index integer
function Builder:add_machine_row(index)
  local geometry = self.geometry
  local top = self:machine_top(index)
  local size = geometry.size

  self:add({name = self.names.machine, position = grid.position(geometry.machine_column, top, size, size)})
  self:add_inserters(geometry.input_inserter_column, top, geometry.input_count)
  self:add_inserters(geometry.output_inserter_column, top, geometry.output_count)

  if not geometry.has_pole_rows and index % MACHINES_PER_POLE == 0 then
    self:add_pole_pair(top + geometry.input_count, top + geometry.output_count)
  end
end

-- The rows of poles above the first machine, between machines and below the last.
function Builder:add_pole_rows()
  for index = 0, self.machine_count do
    local row = self:machine_top(index) - 1
    self:add_pole_pair(row, row)
  end
end

-- The machines with their inserters, and the poles: in rows between them when the
-- sides are full, otherwise in the free tiles beside them.
function Builder:add_machines()
  for index = 0, self.machine_count - 1 do
    self:add_machine_row(index)
  end
  if self.geometry.has_pole_rows then
    self:add_pole_rows()
  end
end

-- Chain the poles down each side, then join the two sides at the top.
function Builder:wire_poles()
  local poles = self.poles
  for i = 2, #poles.input do
    self:connect(poles.input[i - 1], poles.input[i])
    self:connect(poles.output[i - 1], poles.output[i])
  end
  -- `layout.build` needs at least one machine, so there is a first pole on each side.
  self:connect(poles.input[1], poles.output[1])
end

-- The columns of a chain, left to right, joined by wire: the top output pole of each
-- column to the top input pole of the next.
---@param builders bpgen.Builder[]
local function wire_columns(builders)
  ---@type bpgen.Builder|nil
  local previous
  for _, builder in ipairs(builders) do
    if previous then
      previous:connect(previous.poles.output[1], builder.poles.input[1])
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
  local runs_north = builder:length_for_load() >= next_builder:length_for_load() * (1 - LENGTH_TOLERANCE)
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
    input_belt_rows_above = options.input_belt_rows_above,
    load = stage.load or stage.machine_count,
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
    local stage_names = {machine = stage.machine, belt = names.belt, inserter = names.inserter, pole = names.pole}
    local place = place_of(stage, index, #stages, origin, first_row, options)
    local builder = Builder.new(stage.machine_count, stage_names, stage.shape, entities, place)
    builders[index] = builder
    origin = builder.geometry.output_belt_column -- the next column's input belt
    if index > 1 then
      share_belt(builders[index - 1], builder)
    end
  end
  return builders
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

-- One past the last row of the tallest column.
---@param builders bpgen.Builder[]
---@return integer
local function tallest_end_row(builders)
  local height = 0
  for _, builder in ipairs(builders) do
    height = math.max(height, builder:end_row())
  end
  return height
end

-- `stages` go from the one fed raw items (or, for a column that stands to the right of
-- other blocks, from the one whose input belt `options.input_belt_rows_above` lengthens)
-- to the last. Returns the chain as a block: its entities, which are numbered from 1 in
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
  return {
    entities = entities,
    poles = poles_of(builders),
    product_column = builders[#builders].geometry.output_belt_column,
    height = tallest_end_row(builders),
    raw_belts = {{
      stage = stages[1],
      column = builders[1].geometry.input_belt_column,
      row = builders[1].geometry.input_belt_first_row,
    }},
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
  return layout.chain_block(stages, names, {product_belt = true, input_belt_rows_above = 0}).entities
end

-- One column on its own: a chain of one stage.
-- names: {machine, belt, inserter, pole} prototype names.
-- Returns a list of blueprint entities (tables with entity_number, name, position, ...).
---@param machine_count integer  at least 1
---@param names bpgen.Names
---@param shape bpgen.Shape  the machine size must be one `supports_machine_size` accepts
---@return bpgen.Entity[]
function layout.build(machine_count, names, shape)
  return layout.build_chain({{machine_count = machine_count, machine = names.machine, shape = shape}}, names)
end

return layout
