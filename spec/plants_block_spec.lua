-- spec/plants_block_spec.lua
-- The blocks that make an item in plants or a fluid in machines, as the columns of a recipe take them (see scripts/plants_block.lua): the builders of
-- plastic bar (`fluid_plant.build_block`), of explosives and the sulfuric acid (`item_fluid_chain.build_block`), of battery
-- (`item_fluid_chain.build_nested_block`) and of the row of refineries (`fluid_row.build`) are called with the stand-ins of their own specs (refineries
-- of 5 x 5 and chemical plants of 3 x 3), and the module is asked for the block.
---@diagnostic disable: undefined-field  -- luassert's `assert` has fields (`assert.are`, `assert.is_nil`, ...) the editor cannot see

local builders = require("spec.support.builders")
local fluid_plant = require("scripts.fluid_plant")
local grid = require("scripts.grid")
local item_fluid_chain = require("scripts.item_fluid_chain")
local plants_block = require("scripts.plants_block")

local NAMES = builders.NAMES
local south = defines.direction.south

local SIZES = {["oil-refinery"] = 5, ["chemical-plant"] = 3, ["stone-furnace"] = 2}

local function refinery_boxes()
  return {
    {production_type = "input", tiles = {{x = 1, y = 5}}}, {production_type = "input", tiles = {{x = 3, y = 5}}},
    {production_type = "output", tiles = {{x = 0, y = -1}}}, {production_type = "output", tiles = {{x = 2, y = -1}}}, {production_type = "output", tiles = {{x = 4, y = -1}}},
  }
end

local function plant_boxes()
  return {
    {production_type = "input", tiles = {{x = 0, y = -1}}}, {production_type = "input", tiles = {{x = 2, y = -1}}},
    {production_type = "output", tiles = {{x = 0, y = 3}}}, {production_type = "output", tiles = {{x = 2, y = 3}}},
  }
end

-- What `fluid_plant.build_block` is asked for: `makers` refineries and `plants` chemical plants that take the gas and an item (plastic bar).
local function plastic_request(makers, plants)
  return {
    makers = {
      machine = "oil-refinery", recipe = "basic-oil-processing", size = 5, count = makers, boxes = refinery_boxes(),
      rows = {inputs = 5, outputs = -1}, pipe = NAMES.pipe, pole = NAMES.pole, pole_supply_distance = 2.5, pole_wire_distance = 7.5,
    },
    plants = {machine = "chemical-plant", recipe = "plastic-bar", size = 3, count = plants, boxes = plant_boxes(), rows = {inputs = -1, outputs = 3}},
    inserter = NAMES.inserter, belt = NAMES.belt, item_input = true, pipe_to_ground = NAMES.pipe_to_ground, underground_reach = 10,
  }
end

-- The request of a chain whose final plants make an item (explosives) or a fluid (acid): the sulfur from refineries and plants, the plants of
-- the final item, and a block of a raw item that comes in on a belt.
local function chain_request(final_makes_an_item)
  local sulfur = plastic_request(2, 3)
  sulfur.item_input, sulfur.plants = nil, {
    machine = "sulfur-plant", recipe = "sulfur", size = 3, count = 3, boxes = plant_boxes(), rows = {inputs = -1, outputs = 3}, fluid_boxes = {source = 1, supplied = 2},
  }
  local coal = {
    entities = {{entity_number = 1, name = NAMES.belt, position = grid.position(0, 0), direction = south}}, poles = {}, product = {column = 0, last_row = 0},
    raw = {{key = "coal", x = 0, y = 0, feed = {items = {{name = "coal", amount = 5}}}}},
  }
  return {
    plants_part = sulfur, belts_part = coal, shared_fluid = true,
    final_plants = {
      plants = {machine = "explosives-plant", recipe = "explosives", size = 3, count = 2, boxes = plant_boxes(), rows = {inputs = -1, outputs = 3}, item_output = final_makes_an_item},
      inserter = NAMES.inserter, belt = NAMES.belt, pipe = NAMES.pipe, pipe_to_ground = NAMES.pipe_to_ground, pole = NAMES.pole,
      pole_supply_distance = 2.5, pole_wire_distance = 7.5, underground_reach = 10,
    },
    size_of = function(entity)
      local size = SIZES[entity.name] or (entity.name == "sulfur-plant" or entity.name == "explosives-plant") and 3 or 1
      return size, size
    end,
  }
end

describe("plants_block", function()
  describe("of_fluid_plant", function()
    local function block(fluids, feeds)
      return plants_block.of_fluid_plant(fluid_plant.build_block(plastic_request(2, 1)), fluids or {input = "crude-oil"}, feeds or {items = {items = {{name = "coal", amount = 20}}}}, SIZES)
    end

    it("gives the entities, the groups of poles, the product belt of the plants and the sizes of its machines as they are", function()
      local made = fluid_plant.build_block(plastic_request(2, 1))

      local result = plants_block.of_fluid_plant(made, {input = "crude-oil"}, {}, SIZES)

      assert.are.same({made.entities, made.groups, made.product_belt, SIZES}, {result.entities, result.pole_groups, result.product, result.sizes})
    end)

    it("says the fluid of the pipe and what the belt of the item takes, by the key of the start", function()
      local result = plants_block.of_fluid_plant(
        fluid_plant.build_block(plastic_request(2, 1)), {input = "crude-oil"}, {items = {items = {{name = "coal", amount = 20}}}}, SIZES)

      local by_key = {}
      for _, start in ipairs(result.starts) do
        by_key[start.key] = start
      end
      assert.are.same({"crude-oil", {items = {{name = "coal", amount = 20}}}}, {by_key.input.fluid, by_key.items.feed})
    end)

    it("is as high as the lowest of its machines, the refineries of 5 x 5 or the plants", function()
      local result = block()

      -- two refineries stand one under the other: 10 rows, and the pipes and poles around them
      assert.is_true(result.height >= 10)
    end)

    it("stops when a pipe has no fluid said for it", function()
      local build = function() block({}) end

      assert.has_error(build, "plants_block: no fluid is said for the pipe that starts as input")
    end)
  end)

  describe("of_chain", function()
    it("gives the product belt of its final plants when they make an item: the column of their belt, down to the last row of the last plant", function()
      local made = item_fluid_chain.build_block(chain_request(true))

      local result = plants_block.of_chain(made, {input = "crude-oil", supplied = "water", final_fluid = "water"}, {}, SIZES)

      assert.are.same({made.places.final_x + made.final.output_belt, made.final.last_row}, {result.product.column, result.product.last_row})
    end)

    it("keeps the feed that the belt of raw items of its belts part has", function()
      local made = item_fluid_chain.build_block(chain_request(true))

      local result = plants_block.of_chain(made, {input = "crude-oil", supplied = "water", final_fluid = "water"}, {}, SIZES)

      local feeds = {}
      for _, start in ipairs(result.starts) do
        feeds[#feeds + 1] = start.feed
      end
      assert.are.same({{items = {{name = "coal", amount = 5}}}}, feeds)
    end)

    it("gives the pipe their fluid leaves by when the final plants make a fluid: the column of their output pipe, down to its last row", function()
      local made = item_fluid_chain.build_block(chain_request(false))

      local result = plants_block.of_chain(made, {input = "crude-oil", supplied = "water", final_fluid = "water"}, {}, SIZES)

      assert.are.same(
        {made.places.final_x + made.final.columns.output, made.final.output_exit_row, true}, {result.product.column, result.product.last_row, result.product.fluid})
    end)

    it("is as wide as its entities, so that the pole east of the output pipe of a chain is inside the block", function()
      local made = item_fluid_chain.build_block(chain_request(false))

      local result = plants_block.of_chain(made, {input = "crude-oil", supplied = "water", final_fluid = "water"}, {}, SIZES)

      -- the plants are 3 wide, the pipe is the column after them and the pole the one after the pipe
      assert.are.same({true, result.product.column + 2}, {result.product.column + 1 < result.width, result.width})
    end)
  end)

  describe("of_fluid_row", function()
    -- Two refineries as `fluid_row.build` and `fluid_row.turn` leave them: the pipe that brings in the crude oil in column 1, the machines in
    -- columns 2 to 6 and the pipe the gas leaves by in column 7, with the poles in column 0.
    local function row_of_refineries(count)
      local fluid_row = require("scripts.fluid_row")
      local entities, entries = fluid_row.build{
        machine = "oil-refinery", recipe = "basic-oil-processing", size = 5, count = count, boxes = refinery_boxes(), rows = {inputs = 5, outputs = -1},
        pipe = NAMES.pipe, pole = NAMES.pole, pole_supply_distance = 2.5, pole_wire_distance = 7.5,
      }
      fluid_row.turn(entities, entries, "oil-refinery", 5)
      return {entities = entities, entries = entries}
    end

    it("makes the pipe the gas leaves by the product: the last column, down to the end of the pipe", function()
      local result = plants_block.of_fluid_row(row_of_refineries(2), "crude-oil", SIZES, NAMES)

      assert.are.same({7, true, 8}, {result.product.column, result.product.fluid, result.width})
      assert.is_true(result.product.last_row >= 4)
    end)

    it("starts the one pipe at the top of the pipe that brings the crude oil in, and says its fluid", function()
      local result = plants_block.of_fluid_row(row_of_refineries(2), "crude-oil", SIZES, NAMES)

      assert.are.same({{key = "input", x = 1, y = 0, name = NAMES.pipe, fluid = "crude-oil"}}, result.starts)
    end)

    it("stops when the pipe the product leaves by is not among the entities", function()
      local row = row_of_refineries(2)
      row.entries.output.x = 8 -- the column after the last one of the block

      local build = function() plants_block.of_fluid_row(row, "crude-oil", SIZES, NAMES) end

      assert.has_error(build, "plants_block: the belt the product leaves on is not among the entities of the block")
    end)

    it("has the poles of the machines in one group", function()
      local result = plants_block.of_fluid_row(row_of_refineries(3), "crude-oil", SIZES, NAMES)

      assert.are.same({1, 3}, {#result.pole_groups, #result.pole_groups[1]})
    end)
  end)
end)
