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
-- + and an inserter }, from the north, crude oil coming in at the top of the pipe at the column 1:
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

local entity_list = require("scripts.entity_list")
local fluid_row = require("scripts.fluid_row")
local grid = require("scripts.grid")
local layout = require("scripts.layout")
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

-- The plants, one under the other from the top, east of the column of the pipe.
---@param entities bpgen.Entity[]
---@param plants table
---@param column integer  of the pipe
---@param facing defines.direction
local function add_plants(entities, plants, column, facing)
  for index = 0, plants.count - 1 do
    entity_list.append(entities, {
      name = plants.machine, recipe = plants.recipe, direction = facing,
      position = grid.position(column + 1, index * plants.size, plants.size, plants.size),
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

-- The entities of the machines that make the fluid (turned, see `fluid_row.build` and `fluid_row.turn`) and of the plants east of
-- the pipe that takes the fluid out, with the inserters, the belt and the poles, numbered, with the blueprint starting at its
-- top-left tile (0, 0). Gives the tiles where the pipes of the machines that make the fluid start and end too: the plants take
-- from the second.
---@param request bpgen.FluidPlantBuild
---@return bpgen.Entity[]
---@return {input: {x: integer, y: integer}, output: {x: integer, y: integer}} entries
function fluid_plant.build(request)
  local makers, plants = request.makers, request.plants
  assert(makers.rows.inputs == makers.size, "fluid_plant: the machines that make the fluid have to take it in on the side that turns to the west")
  assert(layout.pole_reach(makers.pole_supply_distance) >= math.floor(plants.size / 2), "fluid_plant: a pole has to reach the inserter beside a plant")
  assert(plants.size <= makers.pole_wire_distance, "fluid_plant: a wire has to reach from the pole of one plant to the next")
  local entities, entries = fluid_row.build(makers)
  fluid_row.turn(entities, entries, makers.machine, makers.size)
  local maker_poles = poles_of(entities, makers.pole)
  local column, facing = entries.output.x, facing_of(plants.rows, plants.size)
  local first, last = input_rows(plants, facing)
  add_plants(entities, plants, column, facing)
  fill_pipes(entities, makers.pipe, column, first, (plants.count - 1) * plants.size + last)
  local inserter_column = column + 1 + plants.size
  add_items_out(entities, request, inserter_column)
  join_poles(entities, request, {maker_poles, add_plant_poles(entities, request, inserter_column)})
  return entities, entries
end

return fluid_plant
