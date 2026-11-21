-- scripts/fluid_row.lua
-- A row of machines that take a fluid and give one, with no belt and no inserter: the oil refinery that makes petroleum gas from
-- crude oil. Pure, like scripts/layout.lua.
--
-- The machines stand side by side with no gap, facing north (the way a blueprint entity faces with no direction), and the finished
-- row is turned a quarter clockwise (`fluid_row.turn`): they then stand one under the other, facing east, with the fluid coming in
-- at the north end and going out at the south end. The picture below is the row before it is turned. Each has
-- pipe connections on two opposite sides, the ones of the fluids it takes on one and the ones of the fluids it gives on the
-- other (the game says where, see `bpgen.FluidBox`); a row of pipes runs along each side, past every connection of every
-- machine, so that the one the recipe uses is joined whichever of them it is. The pipe of the fluid that comes in starts at the
-- west edge of the blueprint, where the player joins it, and the one of the fluid that goes out ends at the east edge. A pole
-- stands beyond the pipes that bring the fluid in, one for each machine. Drawn for three machines of 5 x 5 with the connections of
-- the oil refinery (the fluids it takes at columns 1 and 3 under it, the fluids it gives at columns 0, 2 and 4 above it),
-- = a pipe and + a pole:
--
--   =============== the fluid that goes out, from column 0 to the last column of the last machine
--   [ M ][ M ][ M ]
--   [ M ][ M ][ M ]
--   ============== the fluid that comes in, from column 0 (the west edge) to column 3 of the last machine
--   ..+....+....+   a pole under the middle column of each machine
--
-- A machine whose connections are not in such rows (see `fluid_row.rows_of`) is not laid out.

local entity_list = require("scripts.entity_list")
local grid = require("scripts.grid")
local layout = require("scripts.layout")

local fluid_row = {}

local north, east = defines.direction.north, defines.direction.east

-- Whether a pipe connection is on the tile just outside the machine, above or under it, in line with one of its columns.
---@param tile {x: integer, y: integer}
---@param size integer
---@return boolean
local function outside(tile, size)
  return (tile.y == -1 or tile.y == size) and tile.x >= 0 and tile.x < size
end

-- The tile row of the pipe connections of the boxes of a production type, or nil when none has one, one is not outside the machine
-- above or under it, or they are not all in the same row.
---@param boxes bpgen.FluidBox[]
---@param production_type string
---@param size integer
---@return integer|nil
local function row_of(boxes, production_type, size)
  local row
  for _, box in ipairs(boxes) do
    if box.production_type == production_type then
      for _, tile in ipairs(box.tiles) do
        if not outside(tile, size) or (row and row ~= tile.y) then
          return nil
        end
        row = tile.y
      end
    end
  end
  return row
end

-- The rows of pipes of a machine: the one of the fluids it takes and the one of the fluids it gives, on opposite sides of it. Nil
-- when its connections are not in rows like that (a box that takes and gives, a connection at the side, both kinds on one side).
---@param boxes bpgen.FluidBox[]
---@param size integer  tiles across and along the map
---@return bpgen.FluidRows|nil
function fluid_row.rows_of(boxes, size)
  local inputs, outputs = row_of(boxes, "input", size), row_of(boxes, "output", size)
  if inputs and outputs and inputs ~= outputs then
    return {inputs = inputs, outputs = outputs}
  end
  return nil
end

-- The first and the last column, in a machine, of the pipe connections of the boxes of a production type.
---@param boxes bpgen.FluidBox[]
---@param production_type string
---@return integer first
---@return integer last
local function columns_of(boxes, production_type)
  local first, last
  for _, box in ipairs(boxes) do
    if box.production_type == production_type then
      for _, tile in ipairs(box.tiles) do
        first, last = math.min(first or tile.x, tile.x), math.max(last or tile.x, tile.x)
      end
    end
  end
  return first, last
end

---@param entities bpgen.Entity[]
---@param request bpgen.FluidRowBuild
---@param top integer  the tile row of the top of the machines
local function add_machines(entities, request, top)
  for index = 0, request.count - 1 do
    entity_list.append(entities, {
      name = request.machine, recipe = request.recipe,
      position = grid.position(index * request.size, top, request.size, request.size),
    })
  end
end

-- A row of pipes from tile column `first` to `last`.
---@param entities bpgen.Entity[]
---@param pipe string
---@param row integer
---@param first integer
---@param last integer
local function add_pipes(entities, pipe, row, first, last)
  for column = first, last do
    entity_list.append(entities, {name = pipe, position = grid.position(column, row)})
  end
end

-- A pole under the middle column of each machine, wired to the one before it.
---@param entities bpgen.Entity[]
---@param request bpgen.FluidRowBuild
---@param row integer
local function add_poles(entities, request, row)
  local poles = {}
  for index = 0, request.count - 1 do
    local column = index * request.size + math.floor(request.size / 2)
    poles[#poles + 1] = entity_list.append(entities, {name = request.pole, position = grid.position(column, row)})
  end
  for index = 2, #poles do
    layout.connect_poles(poles[index - 1], poles[index])
  end
end

-- The entities of a row of `request.count` machines with the pipes and the poles, numbered, with the blueprint starting at its
-- top-left tile (0, 0). The pole beyond the pipes of the fluid that comes in is two tiles from the machine, which a pole
-- has to reach, and the poles are a machine apart, which a wire has to reach.
---@param request bpgen.FluidRowBuild
---@return bpgen.Entity[]
---@return {input: {x: integer, y: integer}, output: {x: integer, y: integer}} entries  the tiles where the pipes start and end
function fluid_row.build(request)
  assert(layout.pole_reach(request.pole_supply_distance) >= 2, "fluid_row: a pole has to reach two tiles to power a machine from beyond its pipes")
  assert(request.size <= request.pole_wire_distance, "fluid_row: a wire has to reach from the pole of one machine to the next")
  local rows = request.rows
  local pole_row = rows.inputs == request.size and request.size + 1 or -2
  local top = -math.min(rows.inputs, rows.outputs, pole_row) -- one of the pipe rows is above the machines (-1), so this is 1 or 2
  local _, last_in = columns_of(request.boxes, "input")
  local first_out, last_out = columns_of(request.boxes, "output")
  local last_machine = (request.count - 1) * request.size
  local entities = {}
  add_machines(entities, request, top)
  add_pipes(entities, request.pipe, rows.inputs + top, 0, last_machine + last_in)
  add_pipes(entities, request.pipe, rows.outputs + top, first_out, last_machine + last_out)
  add_poles(entities, request, pole_row + top)
  local entries = {input = {x = 0, y = rows.inputs + top}, output = {x = last_machine + last_out, y = rows.outputs + top}}
  return entities, entries
end

-- Turns a finished row a quarter clockwise: the machines then face east instead of north, and the row stands from north to south
-- instead of from west to east, so that the fluid comes in at the north end and goes out at the south end. The entities and the
-- tiles of `entries` are moved in place; the entries are returned.
---@param entities bpgen.Entity[]
---@param entries {input: {x: integer, y: integer}, output: {x: integer, y: integer}}
---@param machine string  the name of the machines, which are `size` tiles on a side
---@param size integer
---@return {input: {x: integer, y: integer}, output: {x: integer, y: integer}}
function fluid_row.turn(entities, entries, machine, size)
  local function tiles_of(entity)
    local across = entity.name == machine and size or 1
    return grid.top_left_tile(entity.position, across, across), across
  end
  local height = 0
  for _, entity in ipairs(entities) do
    local tile, across = tiles_of(entity)
    height = math.max(height, tile.y + across)
  end
  for _, entity in ipairs(entities) do
    local tile, across = tiles_of(entity)
    entity.position = grid.position(height - across - tile.y, tile.x, across, across)
    if entity.name == machine then
      entity.direction = east
    end
  end
  for _, entry in pairs(entries) do
    entry.x, entry.y = height - 1 - entry.y, entry.x
  end
  return entries
end

-- A display panel beside the tile where the pipe that brings the fluid in starts, on the side away from the machines, showing the
-- fluid, as the panels of the belts the player brings in do (the pipe that takes the product away has none). For a row that has
-- been turned. A panel needs no power.
---@param entities bpgen.Entity[]
---@param entries {input: {x: integer, y: integer}, output: {x: integer, y: integer}}  where the pipes start and end
---@param options {panel: string, machine: string, input: string}  the names of the panel, the machines and the fluid that comes in
function fluid_row.add_panels(entities, entries, options)
  local machine_x
  for _, entity in ipairs(entities) do
    if entity.name == options.machine then
      machine_x = entity.position.x
      break
    end
  end
  local entry = entries.input
  local away = entry.x + 0.5 < machine_x and -1 or 1
  entity_list.append(entities, {
    name = options.panel, position = grid.position(entry.x + away, entry.y),
    icon = {type = "fluid", name = options.input}, always_show = true,
  })
end

return fluid_row
