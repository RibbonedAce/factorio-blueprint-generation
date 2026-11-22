-- scripts/item_fluid_plants.lua
-- Plants that make a fluid from two items and a fluid, as the final plants of a recipe whose items other parts of the blueprint make: the
-- chemical plants that make sulfuric acid from sulfur, iron plates and water are the example of this file and of its specs. Pure, like
-- scripts/fluid_plant.lua, whose way of turning a plant it shares. It is the last part of the blueprint of scripts/item_fluid_chain.lua,
-- which brings the two items on one belt to the plants and the fluid they take (the water) to the trunk of pipes.
--
-- The plants stand one under the other, facing west, so that the side that takes what they eat is on the west, beside the belt, and the
-- side that gives the fluid they make (the acid) is on the east: the plants of plastic bar have the same sides (see scripts/fluid_plant.lua),
-- and the plants stand east of what makes their ingredients, as the final column of every blueprint does. From the west, the columns are:
-- the trunk of pipes that brings the fluid they take (T), the column where the underground pipes start (t, with the ends that open west to
-- the trunk, and the poles of the inserters), the belt of the two items (b, which runs north), the inserters (i, with the ends of the
-- underground pipes that open east to the plants at each connection of what they take), the plants, the pipe that takes the fluid they make
-- away (o, with a pipe at every row, past every connection of what they give) and a column of poles for the plants (P). As in the columns of
-- the other recipes that take a fluid and items (see scripts/layout.lua), the fluid goes under the belt from the trunk to every connection of
-- every plant, and an inserter at the row of each plant that has no connection takes the items from the belt, both of them, which share it,
-- one on each lane. Drawn for two plants of 3 x 3 with the connections at their top and bottom rows (u: an end of an underground pipe, =
-- a pipe, ^ a belt, < an inserter, + a pole), from the north, row 0 being the first row of the first plant:
--
--   x:   0 1 2 3  4 5 6  7 8
--
--     0  = u ^ u  [C C C] = .     the first plant: the connections of what it takes at its top row ...
--     1  = + ^ <  [C C C] = +     the pole and the inserter between the connections, and the pole of the plant
--     2  = u ^ u  [C C C] = .     ... and at its bottom row
--     3  = u ^ u  [C C C] = .
--     4  = + ^ <  [C C C] = +
--     5  = u ^ u  [C C C] = .
--
-- The belt b starts under the last plant, where the belts of the two items reach it (see scripts/item_fluid_chain.lua), and ends at the top of
-- the first plant. The pipe that takes the made fluid away ends at the last connection of the last plant, open to the south, where the player
-- takes it. The trunk has its top at the first row, where the pipe that brings the fluid joins it from above.

local entity_list = require("scripts.entity_list")
local fluid_plant = require("scripts.fluid_plant")
local grid = require("scripts.grid")
local layout = require("scripts.layout")

local item_fluid_plants = {}

local north, east, south, west = defines.direction.north, defines.direction.east, defines.direction.south, defines.direction.west

-- The columns of the blueprint, from its west edge (see the head of this file), for plants of `size` tiles.
---@param size integer
---@return {trunk: integer, tunnel: integer, belt: integer, inserter: integer, plant: integer, output: integer, pole: integer, width: integer}
function item_fluid_plants.columns(size)
  return {trunk = 0, tunnel = 1, belt = 2, inserter = 3, plant = 4, output = 4 + size, pole = 5 + size, width = 6 + size}
end

-- Which way a plant faces so that the side that takes what it eats is on the west: west (a quarter counterclockwise from north) when that
-- side is above it as it faces north, east (a quarter clockwise) when it is under it.
---@param rows bpgen.FluidRows
---@param size integer
---@return defines.direction
local function facing_of(rows, size)
  assert(rows.inputs == -1 or rows.inputs == size, "item_fluid_plants: the connections of what the plants take are not above or under them")
  return rows.inputs == -1 and west or east
end

-- The rows from the top of a plant, once each from the top, of the pipe connections of the boxes of a production type, as the plant
-- faces the way given. Stops when one is not on the side `at_x` tiles from the plant's own tiles (-1: west of it, `size`: east of it).
---@param plants table  `bpgen.ItemFluidPlantsBuild.plants`
---@param production_type "input"|"output"
---@param facing defines.direction
---@param at_x integer
---@return integer[]
local function connection_rows(plants, production_type, facing, at_x)
  local seen, rows = {}, {}
  for _, box in ipairs(plants.boxes) do
    for _, tile in ipairs(box.production_type == production_type and box.tiles or {}) do
      local turned = fluid_plant.turn_tile(tile, plants.size, facing)
      assert(turned.x == at_x, "item_fluid_plants: a pipe connection of the plants is not on the side that the layout expects")
      if not seen[turned.y] then
        seen[turned.y] = true
        rows[#rows + 1] = turned.y
      end
    end
  end
  assert(#rows > 0, "item_fluid_plants: the plants have no connection of what they " .. (production_type == "input" and "take" or "give"))
  table.sort(rows)
  return rows
end

-- Whether plants with these pipe connections can be laid out by `build`: what they take is above or under them and what they give on the
-- opposite side, the connections are at the sides the layout expects, and a row of a plant has none, for the inserter.
---@param plants table  `bpgen.ItemFluidPlantsBuild.plants`, with `rows` and `boxes`
---@return boolean
function item_fluid_plants.fits(plants)
  return (pcall(function()
    local facing = facing_of(plants.rows, plants.size)
    local inputs = connection_rows(plants, "input", facing, -1)
    if not plants.item_output then
      connection_rows(plants, "output", facing, plants.size)
    end
    fluid_plant.inserter_row(plants, inputs)
  end))
end

-- A pipe at each row from `first` to `last` of a column.
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

-- The two ends of an underground pipe at each connection of what the plants take, under the belt: the end beside the plant opens east to
-- it and the end in the column of the tunnels opens west, where the trunk of pipes is.
---@param entities bpgen.Entity[]
---@param request bpgen.ItemFluidPlantsBuild
---@param columns table
---@param rows integer[]  the connection rows of a plant
local function add_tunnels(entities, request, columns, rows)
  local plants = request.plants
  for index = 0, plants.count - 1 do
    for _, row in ipairs(rows) do
      local at = index * plants.size + row
      entity_list.append(entities, {name = request.pipe_to_ground, position = grid.position(columns.inserter, at), direction = east})
      entity_list.append(entities, {name = request.pipe_to_ground, position = grid.position(columns.tunnel, at), direction = west})
    end
  end
end

-- The belt b beside the plants, from the first row to the last row of the last plant, running north: the belts of the two items reach its
-- south end (see scripts/item_fluid_chain.lua) and the inserters of the plants take from it as it passes.
---@param entities bpgen.Entity[]
---@param request bpgen.ItemFluidPlantsBuild
---@param columns table
---@param last_row integer
local function add_belt(entities, request, columns, last_row)
  for row = 0, last_row do
    entity_list.append(entities, {name = request.belt, position = grid.position(columns.belt, row), direction = north})
  end
end

-- An inserter of each plant at its row without a connection, which takes from the belt b into the plant (an inserter faces the side it
-- picks up from: west), and a pole for it in the column of the tunnels, wired to the one before it. Gives the poles.
---@param entities bpgen.Entity[]
---@param request bpgen.ItemFluidPlantsBuild
---@param columns table
---@param row integer  the row of a plant that has no connection
---@return bpgen.Entity[]
local function add_inserters(entities, request, columns, row)
  local plants, added = request.plants, {}
  for index = 0, plants.count - 1 do
    local at = index * plants.size + row
    entity_list.append(entities, {name = request.inserter, position = grid.position(columns.inserter, at), direction = west})
    added[#added + 1] = entity_list.append(entities, {name = request.pole, position = grid.position(columns.tunnel, at)})
  end
  for index = 2, #added do
    layout.connect_poles(added[index - 1], added[index])
  end
  return added
end

-- A pole for each plant, east of the pipe that takes the made fluid away, in the middle row of the plant, wired to the one before it. Gives
-- the poles.
---@param entities bpgen.Entity[]
---@param request bpgen.ItemFluidPlantsBuild
---@param columns table
---@return bpgen.Entity[]
local function add_plant_poles(entities, request, columns)
  local plants, added = request.plants, {}
  for index = 0, plants.count - 1 do
    local at = index * plants.size + math.floor(plants.size / 2)
    added[#added + 1] = entity_list.append(entities, {name = request.pole, position = grid.position(columns.pole, at)})
  end
  for index = 2, #added do
    layout.connect_poles(added[index - 1], added[index])
  end
  return added
end

-- The plants, one under the other from the first row, facing the way given, with the recipe set.
---@param entities bpgen.Entity[]
---@param plants table  `bpgen.ItemFluidPlantsBuild.plants`
---@param columns table
---@param facing defines.direction
local function add_plants(entities, plants, columns, facing)
  for index = 0, plants.count - 1 do
    entity_list.append(entities, {
      name = plants.machine, recipe = plants.recipe, direction = facing,
      position = grid.position(columns.plant, index * plants.size, plants.size, plants.size),
    })
  end
end

-- The east side of plants that make an item: an inserter at the middle row of each plant that takes the item away (an inserter faces the side
-- it picks up from: west), the belt it drops on, which runs south beside the inserters as far as the plants go, and a pole at the top row of
-- each plant, in the column of the inserters, wired to the one before it. Gives the poles.
---@param entities bpgen.Entity[]
---@param request bpgen.ItemFluidPlantsBuild
---@param columns table
---@return bpgen.Entity[]
local function add_item_output(entities, request, columns)
  local plants, added = request.plants, {}
  for index = 0, plants.count - 1 do
    local top = index * plants.size
    entity_list.append(entities, {
      name = request.inserter, position = grid.position(columns.output, top + math.floor(plants.size / 2)), direction = west,
    })
    added[#added + 1] = entity_list.append(entities, {name = request.pole, position = grid.position(columns.output, top)})
  end
  for row = 0, plants.count * plants.size - 1 do
    entity_list.append(entities, {name = request.belt, position = grid.position(columns.pole, row), direction = south})
  end
  for index = 2, #added do
    layout.connect_poles(added[index - 1], added[index])
  end
  return added
end

-- The east side of the plants: for plants that make a fluid, the pipe that takes it away along every connection of what they give and a pole
-- beside it for each plant; for plants that make an item, an inserter and a belt for it (`add_item_output`). Gives the poles of the plants
-- and the last row of the pipe, nil for an item.
---@param entities bpgen.Entity[]
---@param request bpgen.ItemFluidPlantsBuild
---@param columns table
---@param facing defines.direction
---@return bpgen.Entity[] poles
---@return integer|nil exit_row
local function add_output_side(entities, request, columns, facing)
  local plants = request.plants
  if plants.item_output then
    return add_item_output(entities, request, columns), nil
  end
  local outputs = connection_rows(plants, "output", facing, plants.size)
  local last = (plants.count - 1) * plants.size + outputs[#outputs]
  add_pipes(entities, request.pipe, columns.output, outputs[1], last)
  return add_plant_poles(entities, request, columns), last
end

-- Stops when the poles, the wires or the underground pipes of the request cannot do what the layout needs of them.
---@param request bpgen.ItemFluidPlantsBuild
local function check_reaches(request)
  assert(request.plants.size <= request.pole_wire_distance, "item_fluid_plants: a wire has to reach from the pole of one plant to the next")
  assert(layout.pole_reach(request.pole_supply_distance) >= 2, "item_fluid_plants: a pole has to reach two tiles to power a plant or an inserter from beyond the pipes")
  assert(request.underground_reach >= 2, "item_fluid_plants: an underground pipe has to reach under the belt")
end

-- The entities of the plants and what is beside them, numbered from 1, in a frame whose x = 0 is the column of the trunk of the fluid and
-- whose row 0 is the first row of the first plant. Gives where things are (see the head of this file) and the poles, in two groups that
-- are each wired inside: the poles of the plants and those of the inserters.
---@param request bpgen.ItemFluidPlantsBuild
---@return bpgen.ItemFluidPlantsBlock
function item_fluid_plants.build(request)
  check_reaches(request)
  local plants = request.plants
  local columns, facing = item_fluid_plants.columns(plants.size), facing_of(plants.rows, plants.size)
  local inputs = connection_rows(plants, "input", facing, -1)
  local last_plant = (plants.count - 1) * plants.size
  local entities = {}
  add_plants(entities, plants, columns, facing)
  add_tunnels(entities, request, columns, inputs)
  add_pipes(entities, request.pipe, columns.trunk, 0, last_plant + inputs[#inputs])
  add_belt(entities, request, columns, last_plant + plants.size - 1)
  local inserter_poles = add_inserters(entities, request, columns, fluid_plant.inserter_row(plants, inputs))
  local plant_poles, exit_row = add_output_side(entities, request, columns, facing)
  return {
    entities = entities, columns = columns, groups = {plant_poles, inserter_poles}, last_row = last_plant + plants.size - 1, output_exit_row = exit_row,
  }
end

return item_fluid_plants
