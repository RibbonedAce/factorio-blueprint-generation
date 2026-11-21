-- scripts/fluid_plant.lua
-- Machines that make an item from a fluid, with the machines that make the fluid: the chemical plants that make solid fuel from
-- petroleum gas, fed by the oil refineries that make the gas from crude oil. Pure, like scripts/fluid_row.lua, which draws the
-- machines that make the fluid (turned, so that they stand one under the other facing east).
--
-- The pipe that takes the fluid out of the machines that make it is the pipe that brings it in to the plants, which stand east of
-- it, facing west (the side that takes the fluid is the one that faces the pipe). Each plant has an inserter beside the middle of
-- its east side, which drops the item on a belt that runs south beside the inserters; a pole stands in the column of the
-- inserters, beside the top row of each plant. A pole of the machines that make the fluid is wired to the poles of the plants
-- (with a pole between them where a wire does not reach). Drawn for two refineries (R) and three plants (C), with a pipe =, a pole
-- + and an inserter }, from the north (the crude oil pipe at the column 1 goes up to the west edge above the blueprint, where it
-- comes in, as `scripts/pipe_entries.lua` has it):
--
--   x:   0 1  2 3 4 5 6   7  8 9 10  11 12
--
--        + =  [R R R R R] =  [C C C]  +  v
--        . =  [R R R R R] =  [C C C]  }  v
--        . =  [R R R R R] =  [C C C]  .  v
--        . =  [R R R R R] =  [C C C]  +  v
--        + =  [R R R R R] =  [C C C]  }  v
--        . =  [R R R R R] =  [C C C]  .  v
--        . =  [R R R R R] =  =           ..
--
-- The machines that make the fluid have to take it in from the side that turns to the west when they are turned (see
-- `fluid_row.turn`), which puts the pipe that takes the fluid out on the east.
--
-- A recipe that takes a second fluid, one that nothing makes in the blueprint (sulfur: petroleum gas and water), has two more
-- columns of pipes between that pipe (G) and the plants. A plant takes one fluid at its top row and the other at its bottom row, and
-- every second plant is mirrored, so that the bottom row of a plant and the top row of the next take the same fluid. The column next
-- to the plants (i) has a pipe at the rows of both, and the pipes of the fluid that comes in (W) are joined by a pipe to ground
-- (n: the end whose open side is north, s: the one whose open side is south) past those of the fluid the machines make, which
-- have a pipe beside them in the column (o) beside the pipe G, and so are joined to it. Drawn for three plants (the top row of
-- the first takes W), from the north, the fluid W coming in at the top of the column i:
--
--   x:   G o i  plants
--
--        = . W  [C C C]
--        = . n  [C C C]
--        = o o  [C C C]     the rows of the pipes o: the bottom of the first plant and the top of the second take the fluid
--        = o o  [C C C]     the machines make
--        = . s  [C C C]
--        = . W  [C C C]
--        = . W  [C C C]
--        = . n  [C C C]

local entity_list = require("scripts.entity_list")
local fluid_row = require("scripts.fluid_row")
local grid = require("scripts.grid")
local layout = require("scripts.layout")
local pipe_entries = require("scripts.pipe_entries")
local poles = require("scripts.poles")

local fluid_plant = {}

local north, east, south, west = defines.direction.north, defines.direction.east, defines.direction.south, defines.direction.west

-- Which way a plant faces so that the side that takes the fluid is on the west: west (a quarter counterclockwise from north) when
-- that side is above it as it faces north, east (a quarter clockwise) when it is under it.
---@param rows bpgen.FluidRows
---@param size integer
---@return defines.direction
local function facing_of(rows, size)
  assert(rows.inputs == -1 or rows.inputs == size, "fluid_plant: the connections of what the plants take are not above or under them")
  return rows.inputs == -1 and west or east
end

-- Where a tile outside a plant facing north is when the plant faces west or east: the tiles are counted from the top-left tile
-- of the plant, which is (0, 0).
---@param tile {x: integer, y: integer}
---@param size integer
---@param facing defines.direction
---@return {x: integer, y: integer}
local function turned(tile, size, facing)
  if facing == west then
    return {x = tile.y, y = size - 1 - tile.x}
  end
  return {x = size - 1 - tile.y, y = tile.x}
end

-- The first and the last row, from the top of a plant, of the pipe connections of what it takes.
---@param plants table  `bpgen.FluidPlantBuild.plants`
---@param facing defines.direction
---@return integer first
---@return integer last
local function input_rows(plants, facing)
  local first, last
  for _, box in ipairs(plants.boxes) do
    for _, tile in ipairs(box.production_type == "input" and box.tiles or {}) do
      local at = turned(tile, plants.size, facing)
      assert(at.x == -1, "fluid_plant: a pipe connection of what the plants take is not on their west side")
      first, last = math.min(first or at.y, at.y), math.max(last or at.y, at.y)
    end
  end
  return assert(first, "fluid_plant: the plants take no fluid"), last
end

-- The row from the top of a plant turned to face the way given, not mirrored, of the one pipe connection of a fluid box, or nil when
-- the box has not one, or it is not on the side that faces the pipes.
---@param box bpgen.FluidBox
---@param size integer
---@param facing defines.direction
---@return integer|nil
local function connection_row(box, size, facing)
  local at = #box.tiles == 1 and turned(box.tiles[1], size, facing)
  if at and at.x == -1 then
    return at.y
  end
  return nil
end

-- The row from the top of a plant, with the plant turned to face the way given and not mirrored, of the pipe connection of each of
-- its two fluid boxes that take a fluid, in the order of the boxes. Nil when the boxes are not two with one connection each, at the
-- top row and the bottom row of the side that faces the pipes (what a recipe with two fluids needs).
---@param boxes bpgen.FluidBox[]
---@param size integer
---@param plant_rows bpgen.FluidRows  the rows of the pipes of the plant, from `fluid_row.rows_of`: which way it faces comes of them
---@return integer[]|nil
function fluid_plant.two_input_rows(boxes, size, plant_rows)
  local facing, rows = facing_of(plant_rows, size), {}
  for _, box in ipairs(boxes) do
    if box.production_type == "input" then
      local row = connection_row(box, size, facing)
      if not row then
        return nil
      end
      rows[#rows + 1] = row
    end
  end
  if #rows == 2 and math.min(rows[1], rows[2]) == 0 and math.max(rows[1], rows[2]) == size - 1 then
    return rows
  end
  return nil
end

-- The plants, one under the other from the top, in a column. A plant is mirrored when `mirrored(index)` says so (index from 0).
---@param entities bpgen.Entity[]
---@param plants table
---@param column integer  of the plants
---@param facing defines.direction
---@param mirrored? fun(index: integer): boolean
local function add_plants(entities, plants, column, facing, mirrored)
  for index = 0, plants.count - 1 do
    entity_list.append(entities, {
      name = plants.machine, recipe = plants.recipe, direction = facing, mirror = mirrored and mirrored(index) or nil,
      position = grid.position(column, index * plants.size, plants.size, plants.size),
    })
  end
end

-- The pipes that are missing from the rows `first` to `last` of a column, and from the rows between that and the pipes already
-- there, so that the pipe is whole.
---@param entities bpgen.Entity[]
---@param pipe string
---@param column integer
---@param first integer
---@param last integer
local function fill_pipes(entities, pipe, column, first, last)
  local present = {}
  for _, entity in ipairs(entities) do
    local tile = entity.name == pipe and grid.top_left_tile(entity.position)
    if tile and tile.x == column then
      present[tile.y] = true
      first, last = math.min(first, tile.y), math.max(last, tile.y)
    end
  end
  for row = first, last do
    if not present[row] then
      entity_list.append(entities, {name = pipe, position = grid.position(column, row)})
    end
  end
end

-- A pipe in each of the rows `first` to `last` of a column.
---@param entities bpgen.Entity[]
---@param pipe string
---@param column integer
---@param first integer
---@param last integer
local function add_pipes(entities, pipe, column, first, last)
  for row = first, last do
    entity_list.append(entities, {name = pipe, position = grid.position(column, row)})
  end
end

-- The rows of the pipes at the connections that take the same fluid, the stretch `index` (from 0 to the number of plants): the
-- top row of the first plant alone, the bottom row of a plant with the top row of the next, and the bottom row of the last alone.
---@param plants table
---@param index integer
---@return integer first
---@return integer last
local function stretch_rows(plants, index)
  local size = plants.size
  if index == 0 then
    return 0, 0
  end
  if index == plants.count then
    return index * size - 1, index * size - 1
  end
  return index * size - 1, index * size
end

-- The pipes of the fluid that comes in and the fluid the machines make, in the two columns beside the plants (see the head of this
-- file): the stretches of an even index take the one that comes in. Gives the tile where the one that comes in enters.
---@param entities bpgen.Entity[]
---@param request bpgen.FluidPlantBuild
---@param column integer  of the pipe that takes the fluid out of the machines that make it
---@return {x: integer, y: integer}
local function add_two_fluid_pipes(entities, request, column)
  local plants, pipe, ground = request.plants, request.makers.pipe, request.pipe_to_ground
  assert(ground, "fluid_plant: no pipe to ground for the pipes of two fluids")
  assert(2 * plants.size - 3 <= request.underground_reach, "fluid_plant: a pipe to ground does not reach under the pipes of the other fluid")
  local outer, inner = column + 1, column + 2
  fill_pipes(entities, pipe, column, 0, plants.count * plants.size - 1)
  for index = 0, plants.count do
    local first, last = stretch_rows(plants, index)
    add_pipes(entities, pipe, inner, first, last)
    if index % 2 == 1 then
      add_pipes(entities, pipe, outer, first, last)
    else
      if index >= 2 then
        entity_list.append(entities, {name = ground, position = grid.position(inner, first - 1), direction = south})
      end
      if index + 2 <= plants.count then
        entity_list.append(entities, {name = ground, position = grid.position(inner, last + 1), direction = north})
      end
    end
  end
  return {x = inner, y = 0}
end

-- An inserter beside the middle of each plant, picking up from it (an inserter faces the side it picks up from), and the belt it
-- drops on, beside the inserters, running south as far as the plants go.
---@param entities bpgen.Entity[]
---@param request bpgen.FluidPlantBuild
---@param column integer  of the inserters
local function add_items_out(entities, request, column)
  local plants = request.plants
  for index = 0, plants.count - 1 do
    entity_list.append(entities, {
      name = request.inserter, position = grid.position(column, index * plants.size + math.floor(plants.size / 2)), direction = west,
    })
  end
  for row = 0, plants.count * plants.size - 1 do
    entity_list.append(entities, {name = request.belt, position = grid.position(column + 1, row), direction = south})
  end
end

-- A pole beside the top row of each plant, in the column of the inserters, wired to the one before it. Gives the poles.
---@param entities bpgen.Entity[]
---@param request bpgen.FluidPlantBuild
---@param column integer  of the inserters
---@return bpgen.Entity[]
local function add_plant_poles(entities, request, column)
  local plants, added = request.plants, {}
  for index = 0, plants.count - 1 do
    added[#added + 1] = entity_list.append(entities, {name = request.makers.pole, position = grid.position(column, index * plants.size)})
  end
  for index = 2, #added do
    layout.connect_poles(added[index - 1], added[index])
  end
  return added
end

-- The poles of the entities with the name.
---@param entities bpgen.Entity[]
---@param name string
---@return bpgen.Entity[]
local function poles_of(entities, name)
  local found = {}
  for _, entity in ipairs(entities) do
    if entity.name == name then
      found[#found + 1] = entity
    end
  end
  return found
end

-- Wires the top pole of the machines that make the fluid to the top pole of the plants (each group is wired inside already), with
-- poles between them where a wire does not reach. The top is where it is done because the tiles above the first row are free: the
-- nearest two poles of tall columns are in the middle, with the machines and pipes between them.
---@param entities bpgen.Entity[]
---@param request bpgen.FluidPlantBuild
---@param groups bpgen.Entity[][]  the poles of the machines that make the fluid and of the plants, from the top
local function join_poles(entities, request, groups)
  local sizes = {[request.makers.machine] = request.makers.size, [request.plants.machine] = request.plants.size}
  local taken = grid.taken_tiles(entities, function(entity)
    local across = sizes[entity.name] or 1
    return across, across
  end)
  poles.join({{groups[1][1]}, {groups[2][1]}}, {
    entities = entities, taken = taken, pole = request.makers.pole, wire_distance = request.makers.pole_wire_distance,
  })
end

-- The pipes that take the start of each pipe that comes in to the west edge, above the blueprint (see scripts/pipe_entries.lua): the one
-- that brings the fluid to the machines that make it, and the one of the fluid that comes in beside the plants, if there is one.
---@param entities bpgen.Entity[]
---@param pipe string
---@param entries table  `fluid_plant.build`'s
---@return bpgen.PipeStart[]
local function add_inlets(entities, pipe, entries)
  local starts = {{key = "input", x = entries.input.x, y = entries.input.y}}
  if entries.supplied then
    starts[#starts + 1] = {key = "supplied", x = entries.supplied.x, y = entries.supplied.y}
  end
  return pipe_entries.add(entities, pipe, starts)
end

-- The plants and the pipes beside them, east of the pipe that takes the fluid out of the machines that make it (the column given).
-- Gives the column of the plants.
---@param entities bpgen.Entity[]
---@param entries table  `fluid_plant.build`'s: gets the entry of the fluid that comes in, for plants that take two
---@param request bpgen.FluidPlantBuild
---@param column integer
---@param facing defines.direction
---@return integer
local function add_plants_and_pipes(entities, entries, request, column, facing)
  local plants = request.plants
  local first, last = input_rows(plants, facing)
  if not plants.fluid_boxes then
    add_plants(entities, plants, column + 1, facing)
    fill_pipes(entities, request.makers.pipe, column, first, (plants.count - 1) * plants.size + last)
    return column + 1
  end
  local rows = assert(fluid_plant.two_input_rows(plants.boxes, plants.size, plants.rows), "fluid_plant: the connections of what the plants take are not at their top and bottom rows")
  local source_on_top = rows[plants.fluid_boxes.source] == 0
  add_plants(entities, plants, column + 3, facing, function(index) return source_on_top == (index % 2 == 0) end)
  entries.supplied = add_two_fluid_pipes(entities, request, column)
  return column + 3
end

-- The entities of the machines that make the fluid (turned, see `fluid_row.build` and `fluid_row.turn`) and of the plants east of
-- the pipe that takes the fluid out, with the inserters, the belt and the poles, numbered, with the blueprint starting at its
-- top-left tile (0, 0). Gives the tiles where the pipes of the machines that make the fluid start and end too: the plants take
-- from the second.
---@param request bpgen.FluidPlantBuild
---@return bpgen.Entity[]
---@return {input: {x: integer, y: integer}, output: {x: integer, y: integer}, supplied?: {x: integer, y: integer}, inlets: bpgen.PipeStart[]} entries  `supplied`: where the fluid that comes in beside the machines that make the fluid starts, for plants that take two; `inlets`: the entries of the pipes that come in, at the west edge (keys "input" and "supplied"), see scripts/pipe_entries.lua
function fluid_plant.build(request)
  local makers, plants = request.makers, request.plants
  assert(makers.rows.inputs == makers.size, "fluid_plant: the machines that make the fluid have to take it in on the side that turns to the west")
  assert(layout.pole_reach(makers.pole_supply_distance) >= math.floor(plants.size / 2), "fluid_plant: a pole has to reach the inserter beside a plant")
  assert(plants.size <= makers.pole_wire_distance, "fluid_plant: a wire has to reach from the pole of one plant to the next")
  local entities, entries = fluid_row.build(makers)
  fluid_row.turn(entities, entries, makers.machine, makers.size)
  local maker_poles = poles_of(entities, makers.pole)
  local column = entries.output.x
  local plant_column = add_plants_and_pipes(entities, entries, request, column, facing_of(plants.rows, plants.size))
  entries.inlets = add_inlets(entities, makers.pipe, entries)
  local inserter_column = plant_column + plants.size
  add_items_out(entities, request, inserter_column)
  join_poles(entities, request, {maker_poles, add_plant_poles(entities, request, inserter_column)})
  return entities, entries
end

return fluid_plant
