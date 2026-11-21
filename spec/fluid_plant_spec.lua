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
local north, east, south, west = defines.direction.north, defines.direction.east, defines.direction.south, defines.direction.west

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

    describe("for plants that take two fluids, one of them that nothing makes in the blueprint", function()
      -- The first of the two boxes of a plant that take a fluid takes the fluid the machines make ("gas") and the second the one that
      -- comes in ("water"). The boxes are above the plant as it faces north, in its columns 0 and 2, so a plant facing west has the first at
      -- its bottom row, and the pipes of the machines that make the gas are in the column 7, the pipes beside the plants in the columns 8
      -- (gas only) and 9 (both), and the plants in the columns 10 to 12.
      local function two_fluids(makers, plants, source)
        local asked = request(makers, plants)
        asked.plants.fluid_boxes = {source = source or 1, supplied = (source or 1) == 1 and 2 or 1}
        asked.pipe_to_ground, asked.underground_reach = NAMES.pipe_to_ground, 10
        return asked
      end

      local function catalog_for_two()
        local entries = catalog()
        entries["chemical-plant"] = {
          kind = "machine", width = 3, height = 3, needs_power = true,
          fluid_connections = {gas = {{x = 0, y = -1}}, water = {{x = 2, y = -1}}},
        }
        entries[NAMES.pipe_to_ground] = {kind = "pipe_to_ground", width = 1, height = 1, reach = 10}
        return entries
      end

      -- What stands in a column of pipes, from the top: "pipe" or "pipe-to-ground" with the way its open end faces, by row.
      local function pipes_in_column(entities, column)
        local found = {}
        for _, entity in ipairs(entities) do
          local tile = grid.top_left_tile(entity.position)
          if tile.x == column and (entity.name == NAMES.pipe or entity.name == NAMES.pipe_to_ground) then
            found[tile.y] = entity.name == NAMES.pipe and "pipe" or ("ground " .. entity.direction)
          end
        end
        return found
      end

      it("stands the plants east of the two columns of pipes, one under the other from the top", function()
        local entities = fluid_plant.build(two_fluids(2, 3))

        assert.are.same({{10, 0}, {10, 3}, {10, 6}}, tiles_of(entities, "chemical-plant", 3))
      end)

      it("mirrors every second plant, those that have the fluid that comes in at the bottom row first", function()
        local entities = fluid_plant.build(two_fluids(2, 4))

        local plants = builders.entities_named(entities, "chemical-plant")
        assert.are.same({nil, true, nil, true}, {plants[1].mirror, plants[2].mirror, plants[3].mirror, plants[4].mirror})
      end)

      it("mirrors the others when the fluid the machines make is taken at the top row, so that the first plant has the fluid that comes in there", function()
        local entities = fluid_plant.build(two_fluids(2, 4, 2))

        local plants = builders.entities_named(entities, "chemical-plant")
        assert.are.same({true, nil, true, nil}, {plants[1].mirror, plants[2].mirror, plants[3].mirror, plants[4].mirror})
      end)

      it("runs the pipes of the fluid that comes in beside the plants, under the pipes of the fluid the machines make", function()
        local entities = fluid_plant.build(two_fluids(2, 3))

        assert.are.same({
          [0] = "pipe", [1] = "ground " .. defines.direction.north, [2] = "pipe", [3] = "pipe", [4] = "ground " .. defines.direction.south,
          [5] = "pipe", [6] = "pipe", [8] = "pipe",
        }, pipes_in_column(entities, 9))
      end)

      it("has a pipe beside each pipe of the fluid the machines make, in the column that is beside their pipe, and none for the other", function()
        local entities = fluid_plant.build(two_fluids(2, 3))

        assert.are.same({2, 3, 8}, builders.rows_in_column(entities, NAMES.pipe, 8))
      end)

      it("runs the pipe that takes the fluid out along the machines that make it and the plants, whichever is longer", function()
        local more_plants = fluid_plant.build(two_fluids(1, 4))
        local more_makers = fluid_plant.build(two_fluids(3, 1))

        assert.are.same({range(0, 11), range(0, 14)}, {builders.rows_in_column(more_plants, NAMES.pipe, 7), builders.rows_in_column(more_makers, NAMES.pipe, 7)})
      end)

      it("gives the tile where the pipe of the fluid that comes in starts", function()
        local _, entries = fluid_plant.build(two_fluids(2, 3))

        assert.are.same({x = 9, y = 0}, entries.supplied)
      end)

      it("puts the inserters and the belt east of the plants all the same", function()
        local entities = fluid_plant.build(two_fluids(2, 3))

        assert.are.same({{13, 1}, {13, 4}, {13, 7}}, tiles_of(entities, NAMES.inserter, 1))
        assert.are.same(range(0, 8), builders.rows_in_column(entities, NAMES.belt, 14))
      end)

      for _, counts in ipairs({{1, 1}, {2, 2}, {4, 3}, {3, 4}, {5, 10}}) do
        it(string.format("passes the validator for %d machines that make the fluid and %d plants: three networks of pipes, powered, wired", counts[1], counts[2]), function()
          local entities = fluid_plant.build(two_fluids(counts[1], counts[2]))

          assert.are.same({}, validator.validate(entities, catalog_for_two()))
        end)
      end

      it("passes the validator with the first box taking the fluid the machines make at the top row", function()
        local entities = fluid_plant.build(two_fluids(3, 4, 2))
        local entries = catalog_for_two()
        entries["chemical-plant"].fluid_connections = {water = {{x = 0, y = -1}}, gas = {{x = 2, y = -1}}}

        assert.are.same({}, validator.validate(entities, entries))
      end)

      it("refuses a pipe to ground that does not reach under the two rows of the pipes of the other fluid", function()
        local asked = two_fluids(2, 3)
        asked.underground_reach = 2

        local build = function() fluid_plant.build(asked) end

        assert.has_error(build, "fluid_plant: a pipe to ground does not reach under the pipes of the other fluid")
      end)

      it("takes a pipe to ground that reaches exactly as far as it has to, 3 tiles for plants of 3 x 3", function()
        local asked = two_fluids(2, 3)
        asked.underground_reach = 3

        local build = function() fluid_plant.build(asked) end

        assert.has_no.errors(build)
      end)

      it("refuses plants whose connections are not at their top and bottom rows", function()
        local asked = two_fluids(2, 3)
        asked.plants.boxes[2].tiles = {{x = 1, y = -1}}

        local build = function() fluid_plant.build(asked) end

        assert.has_error(build, "fluid_plant: the connections of what the plants take are not at their top and bottom rows")
      end)

      describe("two_input_rows", function()
        it("gives the row of each connection of a plant facing west, the first box's at the bottom", function()
          assert.are.same({2, 0}, fluid_plant.two_input_rows(plant_boxes(), 3, {inputs = -1, outputs = 3}))
        end)

        it("gives the rows in the order of the boxes whichever is at the top: the first box's at the top for plants facing east", function()
          local swapped = plant_boxes()
          swapped[1].tiles, swapped[2].tiles = swapped[2].tiles, swapped[1].tiles
          local from_below = {
            {production_type = "input", tiles = {{x = 0, y = 3}}}, {production_type = "input", tiles = {{x = 2, y = 3}}},
          }

          assert.are.same({0, 2}, fluid_plant.two_input_rows(from_below, 3, {inputs = 3, outputs = -1}))
          assert.are.same({0, 2}, fluid_plant.two_input_rows(swapped, 3, {inputs = -1, outputs = 3}))
        end)

        it("gives nil for boxes that are not two, with one connection each, on the side that faces the pipes", function()
          local one_box = {plant_boxes()[1], plant_boxes()[3]}
          local two_tiles = plant_boxes()
          two_tiles[1].tiles = {{x = 0, y = -1}, {x = 1, y = -1}}
          local side = plant_boxes()
          side[1].tiles = {{x = -1, y = 0}}

          local results = {
            fluid_plant.two_input_rows(one_box, 3, {inputs = -1, outputs = 3}), fluid_plant.two_input_rows(two_tiles, 3, {inputs = -1, outputs = 3}),
            fluid_plant.two_input_rows(side, 3, {inputs = -1, outputs = 3}),
          }

          assert.are.same({}, results)
        end)

        it("gives nil for two connections that are not at the top and bottom rows", function()
          local middle = plant_boxes()
          middle[2].tiles = {{x = 1, y = -1}}

          assert.is_nil(fluid_plant.two_input_rows(middle, 3, {inputs = -1, outputs = 3}))
        end)
      end)

      describe("the layout the owner built by hand for sulfur", function()
        -- Four plants facing west, every second mirrored, and two columns of pipes beside them (from a blueprint string). The first column
        -- (117.5) goes on underground at both ends, which a blueprint of this size cannot show.
        local BY_HAND = {
          {name = "pipe-to-ground", x = 117.5, y = -678.5, direction = 8}, {name = "pipe", x = 117.5, y = -677.5, direction = 0},
          {name = "pipe", x = 117.5, y = -676.5, direction = 0}, {name = "pipe-to-ground", x = 117.5, y = -675.5, direction = 0},
          {name = "pipe-to-ground", x = 117.5, y = -672.5, direction = 8}, {name = "pipe", x = 117.5, y = -671.5, direction = 0},
          {name = "pipe", x = 117.5, y = -670.5, direction = 0}, {name = "pipe-to-ground", x = 117.5, y = -669.5, direction = 0},
          {name = "pipe", x = 118.5, y = -679.5, direction = 0}, {name = "pipe-to-ground", x = 118.5, y = -678.5, direction = 0},
          {name = "pipe", x = 118.5, y = -677.5, direction = 0}, {name = "pipe", x = 118.5, y = -676.5, direction = 0},
          {name = "pipe-to-ground", x = 118.5, y = -675.5, direction = 8}, {name = "pipe", x = 118.5, y = -674.5, direction = 0},
          {name = "pipe", x = 118.5, y = -673.5, direction = 0}, {name = "pipe-to-ground", x = 118.5, y = -672.5, direction = 0},
          {name = "pipe", x = 118.5, y = -671.5, direction = 0}, {name = "pipe", x = 118.5, y = -670.5, direction = 0},
          {name = "pipe-to-ground", x = 118.5, y = -669.5, direction = 8}, {name = "pipe", x = 118.5, y = -668.5, direction = 0},
          {name = "chemical-plant", x = 120.5, y = -678.5, direction = 12}, {name = "chemical-plant", x = 120.5, y = -675.5, direction = 12, mirror = true},
          {name = "chemical-plant", x = 120.5, y = -672.5, direction = 12}, {name = "chemical-plant", x = 120.5, y = -669.5, direction = 12, mirror = true},
        }

        -- The blueprint string gives the way an entity faces as a number: 0 north, 4 east, 8 south, 12 west.
        local FACING = {[0] = north, [4] = east, [8] = south, [12] = west}

        local function by_hand()
          local entities = {}
          for number, entity in ipairs(BY_HAND) do
            entities[number] = {
              entity_number = number, name = entity.name, position = {x = entity.x, y = entity.y}, direction = FACING[entity.direction], mirror = entity.mirror,
            }
          end
          return entities
        end

        it("has the pipes beside the plants where this layout has them, for four plants", function()
          local entities = fluid_plant.build(two_fluids(4, 4))

          local ours, theirs = pipes_in_column(entities, 9), {}
          for _, entity in ipairs(by_hand()) do
            local row = math.floor(entity.position.y + 679.5)
            if entity.position.x == 118.5 then
              theirs[row] = entity.name == NAMES.pipe and "pipe" or ("ground " .. entity.direction)
            end
          end
          assert.are.same(theirs, ours)
        end)

        it("has the plants mirrored as this layout has them", function()
          local entities = fluid_plant.build(two_fluids(4, 4))

          local ours, theirs = {}, {}
          for _, entity in ipairs(builders.entities_named(entities, "chemical-plant")) do
            ours[#ours + 1] = entity.mirror or false
          end
          for _, entity in ipairs(by_hand()) do
            if entity.name == "chemical-plant" then
              theirs[#theirs + 1] = entity.mirror or false
            end
          end
          assert.are.same(theirs, ours)
        end)

        it("passes the validator but for the two pipes to ground that go on underground beyond the blueprint (it has no poles either)", function()
          local entries = catalog_for_two()
          entries["chemical-plant"].needs_power = false

          local problems = validator.validate(by_hand(), entries)

          local others = {}
          for _, problem in ipairs(problems) do
            if not problem:find("is an end of an underground pipe with no other end behind it within reach", 1, true) then
              others[#others + 1] = problem
            end
          end
          assert.are.same({}, others)
          assert.is_true(#problems > 0)
        end)
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
