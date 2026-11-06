-- scripts/layout.lua
-- Turns "N machines" into the list of blueprint entities. Pure: it only builds
-- tables (it reads the constant table `defines`, but never the game world).
-- Positions are written as TILES (see scripts/grid.lua): the top-left tile an
-- entity covers, with y growing down the page.
--
-- The layout is one column of machines, drawn here as it looks from above
-- (north is up, items flow down). A machine is 2 or 3 tiles wide and tall; this
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
--        v     >    [M M M]     >      >      v    <- row 0: this inserter drops on the stub (>), which
--        v     >    [M M M]     >      v      <       feeds the outer belt from the west: its west lane
--        v     P    [M M M]     P      >      v    <- row 2: the inner belt joins the outer one again
--
-- The outer belt dips west in row 1, to pass the second inserter, which drops on
-- the inner belt (v): the east lane of the belt. Every machine repeats these three
-- rows, so the belt winds down the column and carries the product on both lanes.
-- The first stub has no belt behind the outer tile it feeds, so it bends into it;
-- the lane stays the same. The belt needs three rows per machine, which is exactly
-- what a 3x3 machine takes, so it only works for size 3.

local grid = require("scripts.grid")

local layout = {}

-- The tile column of each part of the layout (the x numbers in the diagrams above).
-- The machine starts at MACHINE_COLUMN and covers `machine_size` columns; the output
-- inserters and belt follow it.
local INPUT_BELT_COLUMN = 0
local INPUT_INSERTER_COLUMN = 1
local MACHINE_COLUMN = 2

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

-- What the layout needs to know about the machine.
---@class bpgen.Shape
---@field machine_size integer  tiles wide and tall; see `supports_machine_size`
---@field input_inserters integer  per machine, at most `machine_size`
---@field output_inserters integer  per machine, at most `machine_size`; a 3x3 machine with two (and no pole rows) gets a winding output belt

-- Where things go, worked out once from the shape.
---@class bpgen.Geometry
---@field size integer  machine size
---@field input_count integer  input inserters per machine
---@field output_count integer  output inserters per machine
---@field output_inserter_column integer
---@field output_belt_column integer  the belt the product leaves on: the outer one when the belt winds
---@field output_winds boolean  the output belt winds, so its two lanes both carry product
---@field has_pole_rows boolean  machines are separated by rows of poles
---@field first_row integer  tile row of the first machine's top edge, which is also where the belts start
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

---@param shape bpgen.Shape
---@return bpgen.Geometry
local function geometry_of(shape)
  local size = shape.machine_size
  local has_pole_rows = math.max(shape.input_inserters, shape.output_inserters) >= size
  local output_winds = winds_output(shape, has_pole_rows)
  return {
    size = size,
    input_count = shape.input_inserters,
    output_count = shape.output_inserters,
    output_inserter_column = MACHINE_COLUMN + size,
    output_belt_column = MACHINE_COLUMN + size + (output_winds and 2 or 1),
    output_winds = output_winds,
    has_pole_rows = has_pole_rows,
    first_row = has_pole_rows and 1 or 0,
    spacing = has_pole_rows and size + 1 or size,
  }
end

-- The poles added so far, on each side of the machines, top to bottom.
---@class bpgen.Poles
---@field input table<integer, bpgen.Entity>
---@field output table<integer, bpgen.Entity>

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
local Builder = {}
Builder.__index = Builder

---@param machine_count integer
---@param names bpgen.Names
---@param shape bpgen.Shape
---@return bpgen.Builder
function Builder.new(machine_count, names, shape)
  return setmetatable({
    entities = {},
    geometry = geometry_of(shape),
    names = names,
    machine_count = machine_count,
    poles = {input = {}, output = {}},
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
function Builder:connect(from, to)
  local connector = defines.wire_connector_id.pole_copper
  from.wires = from.wires or {}
  from.wires[#from.wires + 1] = {from.entity_number, connector, to.entity_number, connector}
end

-- The tile row of the top edge of machine number `index` (from 0).
---@param index integer
---@return integer
function Builder:machine_top(index)
  return self.geometry.first_row + index * self.geometry.spacing
end

---@param column integer  tile column
---@param row integer  tile row
---@param direction defines.direction  the way the belt runs
function Builder:add_belt(column, row, direction)
  self:add({name = self.names.belt, position = grid.position(column, row), direction = direction})
end

-- A run of belt tiles down one column of the layout, running south.
---@param column integer  tile column
---@param first_row integer  tile row of the first belt tile
---@param length integer  how many tiles
function Builder:add_belt_column(column, first_row, length)
  for row = first_row, first_row + length - 1 do
    self:add_belt(column, row, defines.direction.south)
  end
end

-- The winding output belt (see the diagram at the top): three rows per machine,
-- the inner column beside the output inserters and the outer column one further out.
function Builder:add_winding_output_belt()
  local direction = defines.direction
  local inner = self.geometry.output_inserter_column + 1
  local outer = self.geometry.output_belt_column
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

-- Both belts run south (down the page), from the first machine's top row. The
-- output belt keeps the full height of the column, so the products have somewhere
-- to go (and winds, for two output inserters on a 3x3 machine). The input belt
-- stops at the last input inserter: nothing below it would be picked up.
function Builder:add_belts()
  local geometry = self.geometry
  local first_row = geometry.first_row
  local last_input_row = self:machine_top(self.machine_count - 1) + geometry.input_count - 1
  self:add_belt_column(INPUT_BELT_COLUMN, first_row, last_input_row - first_row + 1)
  if geometry.output_winds then
    self:add_winding_output_belt()
  else
    local end_row = self:machine_top(self.machine_count) -- one past the last row of the column
    self:add_belt_column(geometry.output_belt_column, first_row, end_row - first_row)
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
  local input_pole = self:add({name = pole, position = grid.position(INPUT_INSERTER_COLUMN, input_row)})
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

  self:add({name = self.names.machine, position = grid.position(MACHINE_COLUMN, top, size, size)})
  self:add_inserters(INPUT_INSERTER_COLUMN, top, geometry.input_count)
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

-- names: {machine, belt, inserter, pole} prototype names.
-- Returns a list of blueprint entities (tables with entity_number, name, position, ...).
---@param machine_count integer  at least 1
---@param names bpgen.Names
---@param shape bpgen.Shape  the machine size must be one `supports_machine_size` accepts
---@return bpgen.Entity[]
function layout.build(machine_count, names, shape)
  local builder = Builder.new(machine_count, names, shape)
  builder:add_belts()
  builder:add_machines()
  builder:wire_poles()
  return builder.entities
end

return layout
