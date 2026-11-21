-- spec/fluid_plant_spec.lua
-- A plant of machines that make an item from a fluid, with the machines that make the fluid (see scripts/fluid_plant.lua), drawn for
-- refineries of 5 x 5 that give gas (a pipe connection at the columns 0, 2 and 4 above them, as they face north) and chemical plants of
-- 3 x 3 that take it (one at the columns 0 and 2 above them). Positions are TILES: the top-left tile an entity covers, with y growing
-- down (see scripts/grid.lua). The refineries are turned and stand in the columns 2 to 6, with the pipe that brings the crude oil in
-- at the column 1 and the one that takes the gas out at the column 7; the plants are east of that pipe, in the columns 8 to 10.
---@diagnostic disable: undefined-field  -- luassert's `assert` has fields (`assert.are`, `assert.is_nil`, ...) the editor cannot see

local builders = require("spec.support.builders")
local grid = require("scripts.grid")
local fluid_plant = require("scripts.fluid_plant")
local validator = require("spec.support.blueprint_validator")

local NAMES = builders.NAMES
local range = builders.range
local east, south, west = defines.direction.east, defines.direction.south, defines.direction.west

local function refinery_boxes()
  return {
    {production_type = "input", tiles = {{x = 1, y = 5}}},
    {production_type = "input", tiles = {{x = 3, y = 5}}},
    {production_type = "output", tiles = {{x = 0, y = -1}}},
    {production_type = "output", tiles = {{x = 2, y = -1}}},
    {production_type = "output", tiles = {{x = 4, y = -1}}},
  }
end

-- The two boxes that take a fluid of a chemical plant are above it, the two that give one under it.
local function plant_boxes()
  return {
    {production_type = "input", tiles = {{x = 0, y = -1}}},
    {production_type = "input", tiles = {{x = 2, y = -1}}},
    {production_type = "output", tiles = {{x = 0, y = 3}}},
    {production_type = "output", tiles = {{x = 2, y = 3}}},
  }
end

-- What `fluid_plant.build` is asked for: `makers` refineries and `plants` chemical plants, with the changes the test says.
local function request(makers, plants, changes)
  return builders.merged({
    makers = {
      machine = "oil-refinery", recipe = "basic-oil-processing", size = 5, count = makers, boxes = refinery_boxes(),
      rows = {inputs = 5, outputs = -1}, pipe = NAMES.pipe, pole = NAMES.pole, pole_supply_distance = 2.5, pole_wire_distance = 7.5,
    },
    plants = {
      machine = "chemical-plant", recipe = "solid-fuel-from-petroleum-gas", size = 3, count = plants, boxes = plant_boxes(),
      rows = {inputs = -1, outputs = 3},
    },
    inserter = NAMES.inserter, belt = NAMES.belt,
  }, changes)
end

-- The top-left tiles of the entities of one name, as {x, y} in the order of the list; `size` is how many tiles a side of one covers.
local function tiles_of(entities, name, size)
  local tiles = {}
  for _, entity in ipairs(entities) do
    if entity.name == name then
      local tile = grid.top_left_tile(entity.position, size, size)
      tiles[#tiles + 1] = {tile.x, tile.y}
    end
  end
  return tiles
end

-- The catalog of the validator for these machines.
local function catalog()
  local entries = builders.a_catalog{}
  entries["oil-refinery"] = {
    kind = "machine", width = 5, height = 5, needs_power = true, networks = {input = "crude", output = "gas"},
    fluid_connections = {input = {{x = 1, y = 5}, {x = 3, y = 5}}, output = {{x = 0, y = -1}, {x = 2, y = -1}, {x = 4, y = -1}}},
  }
  entries["chemical-plant"] = {
    kind = "machine", width = 3, height = 3, needs_power = true, networks = {input = "gas"},
    fluid_connections = {input = {{x = 0, y = -1}, {x = 2, y = -1}}},
  }
  return entries
end

describe("fluid_plant", function()
  describe("build", function()
    it("turns the machines that make the fluid and stands them one under the other, as a row of them is", function()
      local entities = fluid_plant.build(request(2, 3))

      assert.are.same({{2, 0}, {2, 5}}, tiles_of(entities, "oil-refinery", 5))
      assert.are.same({east, east}, {entities[1].direction, entities[2].direction})
    end)

    it("stands the plants east of the pipe that takes the fluid out, one under the other from the top, facing west with the recipe set", function()
      local entities = fluid_plant.build(request(2, 3))

      local plants = builders.entities_named(entities, "chemical-plant")
      assert.are.same({{8, 0}, {8, 3}, {8, 6}}, tiles_of(entities, "chemical-plant", 3))
      assert.are.same({west, "solid-fuel-from-petroleum-gas"}, {plants[1].direction, plants[1].recipe})
    end)

    it("runs the pipe that takes the fluid out along the machines that make it and the plants, whichever is longer", function()
      local more_makers = fluid_plant.build(request(2, 3))
      local more_plants = fluid_plant.build(request(1, 4))

      -- 2 refineries: the connections at the rows 0 to 9; 3 plants: the rows 0 to 8. 1 refinery: 0 to 4; 4 plants: 0 to 11
      assert.are.same({range(0, 9), range(0, 11)}, {builders.rows_in_column(more_makers, NAMES.pipe, 7), builders.rows_in_column(more_plants, NAMES.pipe, 7)})
    end)

    it("leaves the pipe that brings the fluid in as it is for the row of machines alone", function()
      local entities = fluid_plant.build(request(2, 3))

      assert.are.same(range(0, 8), builders.rows_in_column(entities, NAMES.pipe, 1))
    end)

    it("puts an inserter beside the middle of each plant, picking up from the plant", function()
      local entities = fluid_plant.build(request(2, 3))

      local inserters = builders.entities_named(entities, NAMES.inserter)
      assert.are.same({{11, 1}, {11, 4}, {11, 7}}, tiles_of(entities, NAMES.inserter, 1))
      assert.are.same({west, west, west}, {inserters[1].direction, inserters[2].direction, inserters[3].direction})
    end)

    it("runs a belt south beside the inserters, as far as the plants go", function()
      local entities = fluid_plant.build(request(2, 3))

      local belts = builders.entities_named(entities, NAMES.belt)
      assert.are.same(range(0, 8), builders.rows_in_column(entities, NAMES.belt, 12))
      assert.are.same({south, south}, {belts[1].direction, belts[#belts].direction})
    end)

    it("powers each plant and its inserter from a pole beside the plant, wired to the next", function()
      local entities = fluid_plant.build(request(2, 3))

      local poles = {}
      for _, pole in ipairs(builders.entities_named(entities, NAMES.pole)) do
        local tile = grid.top_left_tile(pole.position)
        if tile.x == 11 then
          poles[#poles + 1] = pole
        end
      end
      local copper = defines.wire_connector_id.pole_copper
      assert.are.same({{11, 0}, {11, 3}, {11, 6}}, tiles_of(poles, NAMES.pole, 1))
      assert.are.same({{poles[1].entity_number, copper, poles[2].entity_number, copper}}, poles[1].wires)
    end)

    it("joins the poles of the machines that make the fluid to those of the plants, with a pole between them where they are too far apart", function()
      local entities = fluid_plant.build(request(2, 3))

      -- the poles of the refineries are in the column 0 and those of the plants in the column 11: too far for a wire of 7.5
      assert.are.same({}, validator.validate(entities, catalog()))
      assert.is_true(#builders.entities_named(entities, NAMES.pole) > 5)
    end)

    it("gives the tile where the pipe that brings the fluid in starts", function()
      local _, entries = fluid_plant.build(request(2, 3))

      assert.are.same({x = 1, y = 0}, entries.input)
    end)

    it("numbers the entities from 1 with no gap", function()
      local entities = fluid_plant.build(request(3, 5))

      assert.has_consecutive_numbers(entities)
    end)

    for _, counts in ipairs({{1, 1}, {1, 4}, {2, 3}, {3, 5}, {5, 10}}) do
      it(string.format("passes the validator for %d machines that make the fluid and %d plants: powered, wired, two networks of pipes", counts[1], counts[2]), function()
        local entities = fluid_plant.build(request(counts[1], counts[2]))

        assert.are.same({}, validator.validate(entities, catalog()))
      end)
    end

    describe("for plants that take their fluid in from below", function()
      local from_below = {inputs = 3, outputs = -1}

      local function below(makers, plants)
        local changes = request(makers, plants)
        changes.plants.rows = from_below
        changes.plants.boxes = {
          {production_type = "input", tiles = {{x = 0, y = 3}}}, {production_type = "input", tiles = {{x = 2, y = 3}}},
          {production_type = "output", tiles = {{x = 0, y = -1}}}, {production_type = "output", tiles = {{x = 2, y = -1}}},
        }
        return changes
      end

      it("turns them to face east, which puts the side that takes the fluid on the west all the same", function()
        local entities = fluid_plant.build(below(2, 3))

        local plants = builders.entities_named(entities, "chemical-plant")
        assert.are.same({east, {{8, 0}, {8, 3}, {8, 6}}}, {plants[1].direction, tiles_of(entities, "chemical-plant", 3)})
      end)

      it("passes the validator", function()
        local entities = fluid_plant.build(below(2, 3))
        local entries = catalog()
        entries["chemical-plant"].fluid_connections = {input = {{x = 0, y = 3}, {x = 2, y = 3}}}

        assert.are.same({}, validator.validate(entities, entries))
      end)
    end)

    it("refuses machines that make the fluid and take it in from above, whose gas would come out on the west", function()
      local from_above = request(2, 3)
      from_above.makers.rows = {inputs = -1, outputs = 5}

      local build = function() fluid_plant.build(from_above) end

      assert.has_error(build, "fluid_plant: the machines that make the fluid have to take it in on the side that turns to the west")
    end)

    describe("for plants of 7 x 7, whose middle row is the third and which the poles have to reach further for", function()
      -- Plants of 7 x 7 take their fluid at the columns 1 and 5 above them. The poles are the medium pole's (3 tiles each way, a wire of 9)
      -- unless the test says otherwise.
      local function big(changes)
        local big_request = request(2, 2)
        big_request.makers.pole_supply_distance, big_request.makers.pole_wire_distance = 3.5, 9
        big_request.plants = {
          machine = "big-plant", recipe = "r", size = 7, count = 2, rows = {inputs = -1, outputs = 7},
          boxes = {{production_type = "input", tiles = {{x = 1, y = -1}}}, {production_type = "input", tiles = {{x = 5, y = -1}}}},
        }
        return builders.merged(big_request, changes)
      end

      it("puts each inserter beside the middle row of its plant, which is the third", function()
        local entities = fluid_plant.build(big{})

        assert.are.same({{15, 3}, {15, 10}}, tiles_of(entities, NAMES.inserter, 1)) -- the plants are in the columns 8 to 14
      end)

      it("takes a pole that reaches the inserter beside the middle row, three tiles from the pole", function()
        local build = function() fluid_plant.build(big{}) end

        assert.has_no.errors(build)
      end)

      it("refuses a pole that reaches only two tiles, which does not reach the inserter beside the middle row", function()
        local changes = big{}
        changes.makers.pole_supply_distance = 2.5

        local build = function() fluid_plant.build(changes) end

        assert.has_error(build, "fluid_plant: a pole has to reach the inserter beside a plant")
      end)

      it("takes a wire exactly as long as a plant is wide", function()
        local changes = big{}
        changes.makers.pole_wire_distance = 7

        local build = function() fluid_plant.build(changes) end

        assert.has_no.errors(build)
      end)

      it("refuses a wire that does not reach from the pole of one plant to the next", function()
        local changes = big{}
        changes.makers.pole_wire_distance = 6

        local build = function() fluid_plant.build(changes) end

        assert.has_error(build, "fluid_plant: a wire has to reach from the pole of one plant to the next")
      end)
    end)

    it("refuses a wire that does not reach from the pole of one plant to the next", function()
      local short = request(2, 3)
      short.makers.pole_wire_distance = 2

      local build = function() fluid_plant.build(short) end

      assert.has_error(build)
    end)
  end)
end)
