-- spec/item_fluid_plants_spec.lua
-- The plants that make a fluid from two items and a fluid, with the belt, the pipes and the poles beside them (see scripts/item_fluid_plants.lua).
-- Positions are TILES: the top-left tile an entity covers, with y growing down (see scripts/grid.lua). The plants are chemical plants of
-- 3 x 3 that take what they eat at two connections above them as they face north (the columns 0 and 2) and give what they make at two
-- connections under them. The blueprint of the module is in the frame of its trunk: the trunk of the water is the column 0, the tunnels the
-- column 1, the belt the column 2, the inserters the column 3, the plants the columns 4 to 6, the pipe of the acid the column 7 and the poles
-- of the plants the column 8; the first plant is in the rows 0 to 2.
---@diagnostic disable: undefined-field  -- luassert's `assert` has fields (`assert.are`, `assert.is_nil`, ...) the editor cannot see

local builders = require("spec.support.builders")
local grid = require("scripts.grid")
local item_fluid_plants = require("scripts.item_fluid_plants")
local poles = require("scripts.poles")
local validator = require("spec.support.blueprint_validator")

local NAMES = builders.NAMES
local range = builders.range
local east, south, west = defines.direction.east, defines.direction.south, defines.direction.west
local north = defines.direction.north

-- The boxes of the plants as they face north: what they take above them, what they give under them.
local function boxes_above()
  return {
    {production_type = "input", tiles = {{x = 0, y = -1}}}, {production_type = "input", tiles = {{x = 2, y = -1}}},
    {production_type = "output", tiles = {{x = 0, y = 3}}}, {production_type = "output", tiles = {{x = 2, y = 3}}},
  }
end

-- The same with what they take under them and what they give above them.
local function boxes_below()
  return {
    {production_type = "input", tiles = {{x = 0, y = 3}}}, {production_type = "input", tiles = {{x = 2, y = 3}}},
    {production_type = "output", tiles = {{x = 0, y = -1}}}, {production_type = "output", tiles = {{x = 2, y = -1}}},
  }
end

-- What `item_fluid_plants.build` is asked for `count` plants, with the changes the test says (of the fields of the request, whole: a table in
-- the changes takes the place of the one of the request).
local function request(count, changes)
  local asked = {
    plants = {machine = "chemical-plant", recipe = "sulfuric-acid", size = 3, count = count, boxes = boxes_above(), rows = {inputs = -1, outputs = 3}},
    inserter = NAMES.inserter, belt = NAMES.belt, pipe = NAMES.pipe, pipe_to_ground = NAMES.pipe_to_ground, pole = NAMES.pole,
    pole_supply_distance = 2.5, pole_wire_distance = 7.5, underground_reach = 10,
  }
  for key, value in pairs(changes or {}) do
    asked[key] = value
  end
  return asked
end

-- The plants of a request of `count` of them with other boxes and rows.
local function plants_with(count, boxes, rows)
  return {machine = "chemical-plant", recipe = "sulfuric-acid", size = 3, count = count, boxes = boxes, rows = rows}
end

-- What stands in a column, as {row, direction} sorted by row, for the entities with the name.
local function in_column(entities, name, column)
  local found = {}
  for _, entity in ipairs(entities) do
    local tile = grid.top_left_tile(entity.position)
    if entity.name == name and tile.x == column then
      found[#found + 1] = {tile.y, entity.direction}
    end
  end
  table.sort(found, function(first, second) return first[1] < second[1] end)
  return found
end

-- The rows of what stands in a column.
local function rows_in(entities, name, column)
  local rows = {}
  for _, found in ipairs(in_column(entities, name, column)) do
    rows[#rows + 1] = found[1]
  end
  return rows
end

-- Every row of the list with the direction.
local function with_direction(rows, direction)
  local list = {}
  for _, row in ipairs(rows) do
    list[#list + 1] = {row, direction}
  end
  return list
end

-- The catalog of the validator for the plants, whose connections are as `boxes` says.
local function catalog(inputs, outputs)
  local entries = builders.a_catalog{}
  entries["chemical-plant"] = {
    kind = "machine", width = 3, height = 3, needs_power = true,
    fluid_connections = {water = inputs, acid = outputs},
  }
  return entries
end

describe("item_fluid_plants", function()
  describe("columns", function()
    it("gives the columns for plants of 3 x 3", function()
      assert.are.same({trunk = 0, tunnel = 1, belt = 2, inserter = 3, plant = 4, output = 7, pole = 8, width = 9}, item_fluid_plants.columns(3))
    end)

    it("moves the columns east of the plants as far as the plants are wide", function()
      assert.are.same({trunk = 0, tunnel = 1, belt = 2, inserter = 3, plant = 4, output = 9, pole = 10, width = 11}, item_fluid_plants.columns(5))
    end)
  end)

  describe("fits", function()
    local function plants(boxes, rows)
      return {machine = "chemical-plant", recipe = "sulfuric-acid", size = 3, count = 1, boxes = boxes, rows = rows}
    end

    it("takes plants whose connections of what they take are above them, and of what they give under them", function()
      assert.is_true(item_fluid_plants.fits(plants(boxes_above(), {inputs = -1, outputs = 3})))
    end)

    it("takes plants whose connections of what they take are under them, and of what they give above them", function()
      assert.is_true(item_fluid_plants.fits(plants(boxes_below(), {inputs = 3, outputs = -1})))
    end)

    it("refuses plants whose connections are not above or under them", function()
      assert.is_false(item_fluid_plants.fits(plants(boxes_above(), {inputs = 1, outputs = 3})))
    end)

    it("refuses plants with a connection that is not on the side the layout expects", function()
      local sideways = boxes_above()
      sideways[1].tiles = {{x = -1, y = 0}}

      assert.is_false(item_fluid_plants.fits(plants(sideways, {inputs = -1, outputs = 3})))
    end)

    it("refuses plants that take nothing in, or give nothing", function()
      local gives_nothing = {{production_type = "input", tiles = {{x = 0, y = -1}}}}
      local takes_nothing = {{production_type = "output", tiles = {{x = 0, y = 3}}}}

      assert.are.same({false, false}, {
        item_fluid_plants.fits(plants(gives_nothing, {inputs = -1, outputs = 3})), item_fluid_plants.fits(plants(takes_nothing, {inputs = -1, outputs = 3})),
      })
    end)

    it("refuses plants that have a pipe connection at every row, which leave no row for the inserter", function()
      local full = {
        {production_type = "input", tiles = {{x = 0, y = -1}}}, {production_type = "input", tiles = {{x = 1, y = -1}}},
        {production_type = "input", tiles = {{x = 2, y = -1}}}, {production_type = "output", tiles = {{x = 0, y = 3}}},
      }

      assert.is_false(item_fluid_plants.fits(plants(full, {inputs = -1, outputs = 3})))
    end)
  end)

  describe("build", function()
    it("stands the plants one under the other from the first row, facing west, with the recipe set", function()
      local block = item_fluid_plants.build(request(3))

      local plants = builders.entities_named(block.entities, "chemical-plant")
      local tiles = {}
      for _, plant in ipairs(plants) do
        local tile = grid.top_left_tile(plant.position, 3, 3)
        tiles[#tiles + 1] = {tile.x, tile.y}
      end
      assert.are.same({{4, 0}, {4, 3}, {4, 6}}, tiles)
      assert.are.same({west, "sulfuric-acid"}, {plants[1].direction, plants[1].recipe})
    end)

    it("faces the plants east when what they take is under them, which puts that side on the west all the same", function()
      local below = request(2, {plants = plants_with(2, boxes_below(), {inputs = 3, outputs = -1})})

      local block = item_fluid_plants.build(below)

      assert.are.equal(east, builders.entities_named(block.entities, "chemical-plant")[1].direction)
    end)

    it("runs the belt b north, from the last row of the last plant to the first row of the first", function()
      local block = item_fluid_plants.build(request(3))

      local belt = in_column(block.entities, NAMES.belt, 2)
      assert.are.same(with_direction(range(0, 8), north), belt)
    end)

    it("takes the water under the belt at each connection of each plant: the end beside the plant opens east, the end by the trunk west", function()
      local block = item_fluid_plants.build(request(3))

      local rows = {0, 2, 3, 5, 6, 8}
      assert.are.same(with_direction(rows, east), in_column(block.entities, NAMES.pipe_to_ground, 3))
      assert.are.same(with_direction(rows, west), in_column(block.entities, NAMES.pipe_to_ground, 1))
    end)

    it("runs the trunk from the first row to the last connection of what the plants take, plain pipes all the way", function()
      local block = item_fluid_plants.build(request(3))

      assert.are.same(range(0, 8), builders.rows_in_column(block.entities, NAMES.pipe, 0))
    end)

    it("runs the pipe of the acid along every row from the first connection of what the plants give to the last", function()
      local block = item_fluid_plants.build(request(3))

      assert.are.same(range(0, 8), builders.rows_in_column(block.entities, NAMES.pipe, 7))
    end)

    it("puts an inserter in the row of each plant between its connections, facing the belt it takes from", function()
      local block = item_fluid_plants.build(request(3))

      assert.are.same({{1, west}, {4, west}, {7, west}}, in_column(block.entities, NAMES.inserter, 3))
    end)

    it("powers the inserters from poles in the column of the tunnels, in the row of each inserter", function()
      local block = item_fluid_plants.build(request(3))

      assert.are.same({1, 4, 7}, rows_in(block.entities, NAMES.pole, 1))
    end)

    it("powers the plants from poles east of the pipe of the acid, in the middle row of each plant", function()
      local block = item_fluid_plants.build(request(3))

      assert.are.same({1, 4, 7}, rows_in(block.entities, NAMES.pole, 8))
    end)

    it("wires the poles of each group to the one before it, and gives them in two groups", function()
      local block = item_fluid_plants.build(request(3))

      local copper = defines.wire_connector_id.pole_copper
      assert.are.equal(2, #block.groups)
      for _, group in ipairs(block.groups) do
        assert.are.same({3, {group[1].entity_number, copper, group[2].entity_number, copper}}, {#group, group[1].wires[1]})
      end
    end)

    it("says where the parts are: the last row of the plants, where the belt b ends in the block, and where the acid leaves", function()
      local block = item_fluid_plants.build(request(3))

      assert.are.same({8, 8}, {block.last_row, block.output_exit_row})
      assert.are.same(item_fluid_plants.columns(3), block.columns)
    end)

    it("numbers the entities from 1 with no gap", function()
      local block = item_fluid_plants.build(request(4))

      assert.has_consecutive_numbers(block.entities)
    end)

    for _, count in ipairs({1, 2, 3, 5}) do
      it(string.format("passes the validator for %d plants: powered, wired, the underground pipes meet, two networks of pipes", count), function()
        local block = item_fluid_plants.build(request(count))
        poles.join({{block.groups[1][1]}, {block.groups[2][1]}})

        local problems = validator.validate(block.entities, catalog({{x = 0, y = -1}, {x = 2, y = -1}}, {{x = 0, y = 3}, {x = 2, y = 3}}))

        assert.are.same({}, problems)
      end)
    end

    it("passes the validator for plants that take what they eat under them, facing east", function()
      local below = request(3, {plants = plants_with(3, boxes_below(), {inputs = 3, outputs = -1})})
      local block = item_fluid_plants.build(below)
      poles.join({{block.groups[1][1]}, {block.groups[2][1]}})

      local problems = validator.validate(block.entities, catalog({{x = 0, y = 3}, {x = 2, y = 3}}, {{x = 0, y = -1}, {x = 2, y = -1}}))

      assert.are.same({}, problems)
    end)

    describe("for plants that make an item, which leaves each by an inserter onto a belt on their east side", function()
      local function item_request(count)
        local asked = request(count)
        asked.plants.item_output = true
        return asked
      end

      it("puts an inserter beside each plant, taking from it, in the column where the pipe of a fluid would be: in the top row of the first plant of a pair, the bottom row of the second, as the assembling machines have them", function()
        local block = item_fluid_plants.build(item_request(3))

        assert.are.same({{0, west}, {5, west}, {6, west}}, in_column(block.entities, NAMES.inserter, 7))
      end)

      it("runs the belt it drops on south beside the inserters, from the first row to the last row of the last plant", function()
        local block = item_fluid_plants.build(item_request(3))

        assert.are.same(with_direction(range(0, 8), south), in_column(block.entities, NAMES.belt, 8))
      end)

      it("puts a pipe nowhere on the east side, and the poles in the column of the inserters: under the first inserter, above the second, which reaches the third", function()
        local block = item_fluid_plants.build(item_request(3))

        assert.are.same({{}, {1, 4}}, {builders.rows_in_column(block.entities, NAMES.pipe, 7), rows_in(block.entities, NAMES.pole, 7)})
      end)

      it("gives no last row of a pipe of the fluid, and the poles of the plants wired to each other", function()
        local block = item_fluid_plants.build(item_request(3))

        assert.is_nil(block.output_exit_row)
        assert.are.equal(2, #block.groups[1])
        assert.are.same({block.groups[1][1].entity_number, defines.wire_connector_id.pole_copper, block.groups[1][2].entity_number, defines.wire_connector_id.pole_copper}, block.groups[1][1].wires[1])
      end)

      describe("with two output inserters for each plant, which wind the belt", function()
        local function winding_request(count)
          local asked = item_request(count)
          asked.plants.output_inserters, asked.plants.output_winds = 2, true
          return asked
        end

        it("puts the inserters in the top rows of the first plant of a pair and the bottom rows of the second, with a pole beside each pair", function()
          local block = item_fluid_plants.build(winding_request(3))

          assert.are.same({0, 1, 4, 5, 6, 7}, rows_in(block.entities, NAMES.inserter, 7))
          assert.are.same({2, 3, 8}, rows_in(block.entities, NAMES.pole, 7))
        end)

        it("puts one inserter for each plant in twos, in the first row of an even plant and the last row of an odd one, with the poles beside them", function()
          local asked = item_request(4)
          asked.plants.output_inserters, asked.plants.output_winds = 1, true

          local block = item_fluid_plants.build(asked)

          assert.are.same({0, 5, 6, 11}, rows_in(block.entities, NAMES.inserter, 7))
          assert.are.same({1, 4, 10}, rows_in(block.entities, NAMES.pole, 7)) -- the pole at the row 4 reaches the inserter in the row 6
        end)

        it("winds the belt in the two columns east of the inserters, and takes one column more", function()
          local block = item_fluid_plants.build(winding_request(3))

          local first = in_column(block.entities, NAMES.belt, 8)
          assert.are.same({{-1, south}, {0, east}, {1, east}}, {first[1], first[2], first[3]})
          assert.are.same({{0, south}, {1, south}}, {in_column(block.entities, NAMES.belt, 9)[1], in_column(block.entities, NAMES.belt, 9)[2]})
          assert.are.equal(10, block.columns.width)
        end)

        it("passes the validator for 1, 2 and 5 plants", function()
          for _, count in ipairs({1, 2, 5}) do
            local block = item_fluid_plants.build(winding_request(count))
            poles.join({{block.groups[1][1]}, {block.groups[2][1]}})
            local entries = builders.a_catalog{}
            entries["chemical-plant"] = {
              kind = "machine", width = 3, height = 3, needs_power = true, fluid_connections = {water = {{x = 0, y = -1}, {x = 2, y = -1}}},
            }

            assert.are.same({}, validator.validate(block.entities, entries))
          end
        end)
      end)

      -- The column of the lowest tile of the belts east of the inserters, where the belt of the product ends.
      local function lowest_belt_column(block)
        local lowest, column = -1, nil
        for _, belt in ipairs(builders.entities_named(block.entities, NAMES.belt)) do
          local tile = grid.top_left_tile(belt.position)
          if tile.x > block.columns.output and tile.y > lowest then
            lowest, column = tile.y, tile.x
          end
        end
        return column
      end

      it("says the column the belt of the product ends in: the one beside the inserters for a plain belt", function()
        local block = item_fluid_plants.build(item_request(2))

        assert.are.same({block.columns.output + 1, lowest_belt_column(block)}, {block.output_belt, block.output_belt})
      end)

      it("says the column the belt of the product ends in for a winding belt too, whichever of its two columns that is", function()
        for _, count in ipairs({2, 3, 4}) do
          local asked = item_request(count)
          asked.plants.output_winds, asked.plants.output_inserters = true, 2

          local block = item_fluid_plants.build(asked)

          assert.are.equal(lowest_belt_column(block), block.output_belt)
        end
      end)

      it("gives no column of a product belt for plants that make a fluid", function()
        assert.is_nil(item_fluid_plants.build(request(2)).output_belt)
      end)

      it("takes plants with no connection of what they give", function()
        local gives_nothing = {{production_type = "input", tiles = {{x = 0, y = -1}}}, {production_type = "input", tiles = {{x = 2, y = -1}}}}
        local plants = plants_with(1, gives_nothing, {inputs = -1, outputs = 3})
        plants.item_output = true

        assert.is_true(item_fluid_plants.fits(plants))
      end)

      it("passes the validator for 1, 2 and 5 plants: powered, wired, the inserter on both sides of each", function()
        for _, count in ipairs({1, 2, 5}) do
          local block = item_fluid_plants.build(item_request(count))
          poles.join({{block.groups[1][1]}, {block.groups[2][1]}})
          local entries = builders.a_catalog{}
          entries["chemical-plant"] = {
            kind = "machine", width = 3, height = 3, needs_power = true, fluid_connections = {water = {{x = 0, y = -1}, {x = 2, y = -1}}},
          }

          assert.are.same({}, validator.validate(block.entities, entries))
        end
      end)
    end)

    it("takes a wire exactly as long as a plant is wide, and an underground pipe that spans exactly the two tiles under the belt", function()
      local build = function() item_fluid_plants.build(request(2, {pole_wire_distance = 3, underground_reach = 2})) end

      assert.has_no.errors(build)
    end)

    it("takes two boxes that have their connection at the same row for one connection: one underground pipe at each end", function()
      local doubled = request(2)
      doubled.plants.boxes = {
        {production_type = "input", tiles = {{x = 0, y = -1}}}, {production_type = "input", tiles = {{x = 0, y = -1}}},
        {production_type = "input", tiles = {{x = 2, y = -1}}}, {production_type = "output", tiles = {{x = 0, y = 3}}}, {production_type = "output", tiles = {{x = 0, y = 3}}},
      }

      local block = item_fluid_plants.build(doubled)

      assert.are.same(with_direction({0, 2, 3, 5}, east), in_column(block.entities, NAMES.pipe_to_ground, 3))
      assert.are.same(range(2, 5), builders.rows_in_column(block.entities, NAMES.pipe, 7)) -- the only connection of what they give is at the last row of a plant
    end)

    describe("for plants of 5 x 5, whose connections of what they take are at their second and fourth rows and of what they give at their second and fourth", function()
      -- as they face north: what they take above them at the columns 1 and 3, what they give under them at the columns 1 and 3. Facing west
      -- the connections are at the rows 1 and 3, so the rows 0, 2 and 4 have none: the inserter of the first plant stands in the first of them,
      -- that of the second in the last (the second plant starts at the row 5, so its last row is the row 9)
      local function five(count)
        local asked = request(count)
        asked.plants = {
          machine = "chemical-plant", recipe = "sulfuric-acid", size = 5, count = count, rows = {inputs = -1, outputs = 5},
          boxes = {
            {production_type = "input", tiles = {{x = 1, y = -1}}}, {production_type = "input", tiles = {{x = 3, y = -1}}},
            {production_type = "output", tiles = {{x = 1, y = 5}}}, {production_type = "output", tiles = {{x = 3, y = 5}}},
          },
        }
        asked.pole_wire_distance = 7.5
        return asked
      end

      it("puts the inserter of the first plant in its first free row and that of the second in its last, with the poles in the free tiles that reach them", function()
        local block = item_fluid_plants.build(five(2))

        assert.are.same({{0, west}, {9, west}}, in_column(block.entities, NAMES.inserter, 3))
        assert.are.same({2, 9}, rows_in(block.entities, NAMES.pole, 1))
      end)

      it("puts the pole of each plant in its middle row, east of the pipe of the acid", function()
        local block = item_fluid_plants.build(five(2))

        assert.are.same({2, 7}, rows_in(block.entities, NAMES.pole, 10))
      end)

      it("runs the pipe of the acid from the first connection of what the plants give to the last, and the trunk from the first row", function()
        local block = item_fluid_plants.build(five(2))

        -- the first plant is in the rows 0 to 4 and the second in the rows 5 to 9: the connections are in the rows 1, 3, 6 and 8
        assert.are.same(range(1, 8), builders.rows_in_column(block.entities, NAMES.pipe, 9))
        assert.are.same(range(0, 8), builders.rows_in_column(block.entities, NAMES.pipe, 0))
      end)

      it("passes the validator", function()
        local block = item_fluid_plants.build(five(2))
        poles.join({{block.groups[1][1]}, {block.groups[2][1]}})
        local entries = builders.a_catalog{pole_wire_reach = 10} -- the two columns of poles are 9 apart, which the blueprint of the chain bridges
        entries["chemical-plant"] = {
          kind = "machine", width = 5, height = 5, needs_power = true,
          fluid_connections = {water = {{x = 1, y = -1}, {x = 3, y = -1}}, acid = {{x = 1, y = 5}, {x = 3, y = 5}}},
        }

        assert.are.same({}, validator.validate(block.entities, entries))
      end)
    end)

    it("refuses a wire that does not reach from the pole of one plant to the next", function()
      local build = function() item_fluid_plants.build(request(2, {pole_wire_distance = 2})) end

      assert.has_error(build, "item_fluid_plants: a wire has to reach from the pole of one plant to the next")
    end)

    it("refuses a pole that does not reach two tiles", function()
      local build = function() item_fluid_plants.build(request(2, {pole_supply_distance = 1.5})) end

      assert.has_error(build, "item_fluid_plants: a pole has to reach two tiles to power a plant or an inserter from beyond the pipes")
    end)

    it("refuses an underground pipe that does not reach under the belt", function()
      local build = function() item_fluid_plants.build(request(2, {underground_reach = 1})) end

      assert.has_error(build, "item_fluid_plants: an underground pipe has to reach under the belt")
    end)

    it("refuses plants whose connections of what they take are not above or under them", function()
      local build = function() item_fluid_plants.build(request(2, {plants = plants_with(2, boxes_above(), {inputs = 1, outputs = 3})})) end

      assert.has_error(build, "item_fluid_plants: the connections of what the plants take are not above or under them")
    end)

    it("refuses a connection that is not on the side the layout expects", function()
      local sideways = request(2)
      sideways.plants.boxes[1].tiles = {{x = -1, y = 0}}

      local build = function() item_fluid_plants.build(sideways) end

      assert.has_error(build, "item_fluid_plants: a pipe connection of the plants is not on the side that the layout expects")
    end)

    it("refuses plants that take nothing in", function()
      local nothing = request(2)
      nothing.plants.boxes = {{production_type = "output", tiles = {{x = 0, y = 3}}}}

      local build = function() item_fluid_plants.build(nothing) end

      assert.has_error(build, "item_fluid_plants: the plants have no connection of what they take")
    end)

    it("refuses plants that give nothing", function()
      local nothing = request(2)
      nothing.plants.boxes = {{production_type = "input", tiles = {{x = 0, y = -1}}}}

      local build = function() item_fluid_plants.build(nothing) end

      assert.has_error(build, "item_fluid_plants: the plants have no connection of what they give")
    end)

    it("refuses plants that have a pipe connection at every row, which leave no row for the inserter", function()
      local full = request(2)
      full.plants.boxes = {
        {production_type = "input", tiles = {{x = 0, y = -1}}}, {production_type = "input", tiles = {{x = 1, y = -1}}},
        {production_type = "input", tiles = {{x = 2, y = -1}}}, {production_type = "output", tiles = {{x = 0, y = 3}}},
      }

      local build = function() item_fluid_plants.build(full) end

      assert.has_error(build, "input_side: a machine has fewer rows without a pipe connection than input inserters")
    end)
  end)
end)
