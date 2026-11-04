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

local grid = require("scripts.grid")

local layout = {}

-- The tile column of each part of the layout (the x numbers in the diagrams above).
-- The machine starts at MACHINE_COLUMN and covers `machine_size` columns; the output
-- inserters and belt follow it.
local INPUT_BELT_COLUMN = 0
local INPUT_INSERTER_COLUMN = 1
local MACHINE_COLUMN = 2

local MACHINES_PER_POLE = 2  -- a small pole's supply area covers two machines' inserters

-- Machines of these sizes (in tiles) can be powered by small poles placed as described above.
local SUPPORTED_MACHINE_SIZES = {[2] = true, [3] = true}

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
---@field output_inserters integer  per machine, at most `machine_size`

-- Where things go, worked out once from the shape.
---@class bpgen.Geometry
---@field size integer  machine size
---@field input_count integer  input inserters per machine
---@field output_count integer  output inserters per machine
---@field output_inserter_column integer
---@field output_belt_column integer
---@field has_pole_rows boolean  machines are separated by rows of poles
---@field first_row integer  tile row of the first machine's top edge, which is also where the belts start
---@field spacing integer  rows from one machine's top edge to the next

---@param shape bpgen.Shape
---@return bpgen.Geometry
local function geometry_of(shape)
  local size = shape.machine_size
  local has_pole_rows = math.max(shape.input_inserters, shape.output_inserters) >= size
  return {
    size = size,
    input_count = shape.input_inserters,
    output_count = shape.output_inserters,
    output_inserter_column = MACHINE_COLUMN + size,
    output_belt_column = MACHINE_COLUMN + size + 1,
    has_pole_rows = has_pole_rows,
    first_row = has_pole_rows and 1 or 0,
    spacing = has_pole_rows and size + 1 or size,
  }
end

-- The tile row of the top edge of machine number `index` (from 0).
---@param geometry bpgen.Geometry
---@param index integer
---@return integer
local function machine_top(geometry, index)
  return geometry.first_row + index * geometry.spacing
end

-- A blueprint under construction. `add` stores an entity and numbers it, because
-- blueprints identify entities by number; `connect` records a copper wire.
---@class bpgen.Blueprint  a blueprint under construction
---@field entities bpgen.Entity[]
---@field add fun(entity: bpgen.NewEntity): bpgen.Entity  numbers the entity and stores it
---@field connect fun(from: bpgen.Entity, to: bpgen.Entity)  adds a copper wire

---@class bpgen.Poles  the poles added so far, top to bottom
---@field input table<integer, bpgen.Entity>
---@field output table<integer, bpgen.Entity>

---@return bpgen.Blueprint
local function new_blueprint()
  local blueprint = {entities = {}}

  function blueprint.add(entity)
    blueprint.entities[#blueprint.entities + 1] = entity
    entity.entity_number = #blueprint.entities
    return entity
  end

  -- Each wire is stored once, on the pole it starts from, as
  -- {from number, connector, to number, connector}.
  function blueprint.connect(from, to)
    local connector = defines.wire_connector_id.pole_copper
    from.wires = from.wires or {}
    from.wires[#from.wires + 1] = {from.entity_number, connector, to.entity_number, connector}
  end

  return blueprint
end

-- A run of belt tiles down one column of the layout, running south.
---@param blueprint bpgen.Blueprint
---@param column integer  tile column
---@param first_row integer  tile row of the first belt tile
---@param length integer  how many tiles
---@param names bpgen.Names
local function add_belt_column(blueprint, column, first_row, length, names)
  for row = first_row, first_row + length - 1 do
    blueprint.add({name = names.belt, position = grid.position(column, row), direction = defines.direction.south})
  end
end

-- Both belts run south (down the page), from the first machine's top row. The
-- output belt keeps the full height of the column, so the products have somewhere
-- to go. The input belt stops at the last input inserter: nothing below it would
-- be picked up.
---@param blueprint bpgen.Blueprint
---@param geometry bpgen.Geometry
---@param machine_count integer
---@param names bpgen.Names
local function add_belts(blueprint, geometry, machine_count, names)
  local first_row = geometry.first_row
  local last_input_row = machine_top(geometry, machine_count - 1) + geometry.input_count - 1
  add_belt_column(blueprint, INPUT_BELT_COLUMN, first_row, last_input_row - first_row + 1, names)
  local end_row = machine_top(geometry, machine_count) -- one past the last row of the column
  add_belt_column(blueprint, geometry.output_belt_column, first_row, end_row - first_row, names)
end

-- `count` inserters in a column, one under the next, from row `top`. An inserter's
-- `direction` is the side it PICKS UP from. All of them move things eastward
-- (belt -> machine, machine -> belt), so all pick up from the west.
---@param blueprint bpgen.Blueprint
---@param column integer
---@param top integer
---@param count integer
---@param names bpgen.Names
local function add_inserters(blueprint, column, top, count, names)
  for row = top, top + count - 1 do
    blueprint.add({name = names.inserter, position = grid.position(column, row), direction = defines.direction.west})
  end
end

-- One pole on each side, at the given rows, added to the top-to-bottom lists.
---@param blueprint bpgen.Blueprint
---@param geometry bpgen.Geometry
---@param input_row integer
---@param output_row integer
---@param names bpgen.Names
---@param poles bpgen.Poles
local function add_pole_pair(blueprint, geometry, input_row, output_row, names, poles)
  local input_pole = blueprint.add({name = names.pole, position = grid.position(INPUT_INSERTER_COLUMN, input_row)})
  local output_pole = blueprint.add({name = names.pole, position = grid.position(geometry.output_inserter_column, output_row)})
  poles.input[#poles.input + 1] = input_pole
  poles.output[#poles.output + 1] = output_pole
end

-- One machine with its inserters, and its poles if it is one of those that get them.
-- `index` counts machines from 0 down the column.
---@param blueprint bpgen.Blueprint
---@param geometry bpgen.Geometry
---@param index integer
---@param names bpgen.Names
---@param poles bpgen.Poles
local function add_machine_row(blueprint, geometry, index, names, poles)
  local top = machine_top(geometry, index)
  local size = geometry.size

  blueprint.add({name = names.machine, position = grid.position(MACHINE_COLUMN, top, size, size)})
  add_inserters(blueprint, INPUT_INSERTER_COLUMN, top, geometry.input_count, names)
  add_inserters(blueprint, geometry.output_inserter_column, top, geometry.output_count, names)

  if not geometry.has_pole_rows and index % MACHINES_PER_POLE == 0 then
    add_pole_pair(blueprint, geometry, top + geometry.input_count, top + geometry.output_count, names, poles)
  end
end

-- The rows of poles above the first machine, between machines and below the last.
---@param blueprint bpgen.Blueprint
---@param geometry bpgen.Geometry
---@param machine_count integer
---@param names bpgen.Names
---@param poles bpgen.Poles
local function add_pole_rows(blueprint, geometry, machine_count, names, poles)
  for index = 0, machine_count do
    local row = machine_top(geometry, index) - 1
    add_pole_pair(blueprint, geometry, row, row, names, poles)
  end
end

-- Returns the poles added, as {input = {...}, output = {...}}, top to bottom.
---@param blueprint bpgen.Blueprint
---@param geometry bpgen.Geometry
---@param machine_count integer
---@param names bpgen.Names
---@return bpgen.Poles
local function add_machines(blueprint, geometry, machine_count, names)
  local poles = {input = {}, output = {}}
  for index = 0, machine_count - 1 do
    add_machine_row(blueprint, geometry, index, names, poles)
  end
  if geometry.has_pole_rows then
    add_pole_rows(blueprint, geometry, machine_count, names, poles)
  end
  return poles
end

-- Chain the poles down each side, then join the two sides at the top.
---@param blueprint bpgen.Blueprint
---@param poles bpgen.Poles
local function wire_poles(blueprint, poles)
  for i = 2, #poles.input do
    blueprint.connect(poles.input[i - 1], poles.input[i])
    blueprint.connect(poles.output[i - 1], poles.output[i])
  end
  -- `layout.build` needs at least one machine, so there is a first pole on each side.
  blueprint.connect(poles.input[1], poles.output[1])
end

-- names: {machine, belt, inserter, pole} prototype names.
-- Returns a list of blueprint entities (tables with entity_number, name, position, ...).
---@param machine_count integer  at least 1
---@param names bpgen.Names
---@param shape bpgen.Shape  the machine size must be one `supports_machine_size` accepts
---@return bpgen.Entity[]
function layout.build(machine_count, names, shape)
  local geometry = geometry_of(shape)
  local blueprint = new_blueprint()
  add_belts(blueprint, geometry, machine_count, names)
  local poles = add_machines(blueprint, geometry, machine_count, names)
  wire_poles(blueprint, poles)
  return blueprint.entities
end

return layout
