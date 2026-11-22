-- spec/item_fluid_chain_generator_spec.lua
-- The generator for a fluid made from two items and a fluid, one item made in plants from fluids and the other on belts from raw items:
-- sulfuric acid (5 sulfur, 1 iron plate and 100 water make 50 acid in 1 s), with sulfur from petroleum gas and water in 1 s (2 sulfur from 30
-- of each) and the gas from crude oil in the refineries (100 make 45 in 5 s), and iron plate from iron ore in furnaces. The stand-ins of the
-- game are those of spec/generator_spec.lua: a refinery of 5 x 5 and a chemical plant of 3 x 3 whose pipe connections are given as the game
-- gives them, a furnace and an inserter of the speeds of the fake game, which move 50.4 items a minute when their hand holds one.
---@diagnostic disable: undefined-field  -- luassert's `assert` has fields (`assert.are`, `assert.is_nil`, ...) the editor cannot see
---@diagnostic disable: need-check-nil  -- the assertion before each use fails the test first if the result is nil
---@diagnostic disable: global-in-non-module  -- `_G.prototypes = ...` is how a spec fakes the game's global

local builders = require("spec.support.builders")
local config = require("scripts.config")
local generator = require("scripts.generator")
local grid = require("scripts.grid")
local lights = require("scripts.lights")
local validator = require("spec.support.blueprint_validator")
local tracer = require("spec.support.belt_tracer")

local a_machine, a_recipe, amount_of, fluid_of, fake_force = builders.a_machine, builders.a_recipe, builders.amount_of, builders.fluid_of, builders.fake_force
local count_named = builders.count_named
local north, south = defines.direction.north, defines.direction.south

local REFINERY_BOXES = {
  {production_type = "input", position = {x = -1, y = 2}, direction = south}, {production_type = "input", position = {x = 1, y = 2}, direction = south},
  {production_type = "output", position = {x = -2, y = -2}, direction = north}, {production_type = "output", position = {x = 0, y = -2}, direction = north},
  {production_type = "output", position = {x = 2, y = -2}, direction = north},
}
local PLANT_BOXES = {
  {production_type = "input", position = {x = -1, y = -1}, direction = north}, {production_type = "input", position = {x = 1, y = -1}, direction = north},
  {production_type = "output", position = {x = -1, y = 1}, direction = south}, {production_type = "output", position = {x = 1, y = 1}, direction = south},
}

local gas = a_recipe{energy = 5, ingredients = {fluid_of(100, "crude-oil")}, products = {fluid_of(45, "petroleum-gas")}, category = "oil-processing"}
local sulfur = a_recipe{
  energy = 1, ingredients = {fluid_of(30, "water"), fluid_of(30, "petroleum-gas")}, products = {amount_of(2, "sulfur")}, category = "chemistry",
}
local acid = a_recipe{
  energy = 1, ingredients = {amount_of(5, "sulfur"), amount_of(1, "iron-plate"), fluid_of(100, "water")}, products = {fluid_of(50, "sulfuric-acid")},
  category = "chemistry",
}
local plate = a_recipe{energy = 3.2, ingredients = {amount_of(1, "iron-ore")}, products = {amount_of(1, "iron-plate")}, category = "smelting"}

-- The game with the recipes of the chain and the machines the layouts draw, with the changes the test says.
local function acid_game(changes)
  return builders.fake_prototypes(builders.merged({
    items = {"iron-ore", "iron-plate", "sulfur"},
    machines = {
      ["oil-refinery"] = a_machine{crafting_speed = 1, size = 5, pipe_boxes = REFINERY_BOXES},
      ["chemical-plant"] = a_machine{crafting_speed = 1, size = 3, pipe_boxes = PLANT_BOXES},
    },
    recipes = {["basic-oil-processing"] = gas, ["sulfur"] = sulfur, ["sulfuric-acid"] = acid, ["iron-plate"] = plate},
  }, changes))
end

local PLANT_NAMES = {sulfur = "sulfur-plant", explosives = "explosives-plant"}

-- The entities with each chemical plant named for what it makes, so that the validator, which knows machines by name, can tell the plants of
-- the sulfur (that take gas and water at two boxes, mirrored in turn) from the plants of the acid (that take water at both).
local function renamed(entities)
  local copies = {}
  for index, entity in ipairs(entities) do
    local copy = {}
    for key, value in pairs(entity) do
      copy[key] = value
    end
    if entity.name == "chemical-plant" then
      copy.name = PLANT_NAMES[entity.recipe] or "acid-plant"
    end
    copies[index] = copy
  end
  return copies
end

-- The catalog of the validator. The water the plants of the acid take is the water the plants of the sulfur take, so the two are one network
-- of pipes, unless `final_fluid` names another fluid for the plants of the acid, which is a network of its own.
local function catalog(final_fluid)
  local entries = builders.a_catalog{}
  entries["oil-refinery"] = {
    kind = "machine", width = 5, height = 5, needs_power = true, networks = {input = "crude", output = "gas"},
    fluid_connections = {input = {{x = 1, y = 5}, {x = 3, y = 5}}, output = {{x = 0, y = -1}, {x = 2, y = -1}, {x = 4, y = -1}}},
  }
  entries["sulfur-plant"] = {
    kind = "machine", width = 3, height = 3, needs_power = true, fluid_connections = {water = {{x = 0, y = -1}}, gas = {{x = 2, y = -1}}},
  }
  entries["acid-plant"] = {
    kind = "machine", width = 3, height = 3, needs_power = true,
    fluid_connections = {[final_fluid or "water"] = {{x = 0, y = -1}, {x = 2, y = -1}}, acid = {{x = 0, y = 3}, {x = 2, y = 3}}},
  }
  entries["explosives-plant"] = {
    kind = "machine", width = 3, height = 3, needs_power = true, fluid_connections = {water = {{x = 0, y = -1}, {x = 2, y = -1}}},
  }
  return entries
end

-- What the belt tracer finds wrong with the lanes of the belts of a blueprint: a lane that carries two items, an inserter of a machine that
-- never sees what it eats, an item nobody eats. For the design with one belt of each material (`belts_come_in`) it is told where the two belts
-- of raw items start, at the west edge above the blueprint, the ore on the top row, and that a furnace takes the ore on one lane and the fuel
-- on the other.
local function lane_problems(entities, belts_come_in)
  local options = {
    machines = {
      ["sulfur-plant"] = {size = 3, eats = {}, makes = "sulfur"}, ["acid-plant"] = {size = 3, eats = {"sulfur", "iron-plate"}, makes = "sulfuric-acid"},
      ["stone-furnace"] = {size = 2, eats = {"iron-ore"}, makes = "iron-plate"}, ["oil-refinery"] = {size = 5, eats = {}, makes = "petroleum-gas"},
    },
    raw = {["stone-furnace"] = true}, product = "sulfuric-acid",
  }
  if belts_come_in then
    local rows = {}
    for _, belt in ipairs(builders.entities_named(entities, "transport-belt")) do
      local tile = grid.top_left_tile(belt.position)
      if tile.x == 0 and tile.y < 0 then
        rows[#rows + 1] = tile.y
      end
    end
    table.sort(rows)
    options.raw_lanes, options.underground_reach = {["stone-furnace"] = {"iron-ore", "coal"}}, 5
    options.supplies = {{x = 0, y = rows[1], item = "iron-ore"}, {x = 0, y = rows[2], item = "coal"}}
  end
  return tracer.problems(renamed(entities), options)
end

-- The recipe of each chemical plant of the blueprint, by how many there are.
local function plants_by_recipe(entities)
  local counts = {}
  for _, plant in ipairs(builders.entities_named(entities, "chemical-plant")) do
    counts[plant.recipe] = (counts[plant.recipe] or 0) + 1
  end
  return counts
end

describe("the generator for a fluid made from two items and a fluid", function()
  it("makes the acid in plants, with the sulfur in plants fed by refineries and the plates in furnaces", function()
    _G.prototypes = acid_game()

    local result = generator.generate("sulfuric-acid", 1000)

    -- 3 plants make 420 a minute each, held down to what the one inserter of each brings of the 6 items of a craft: 8.4 crafts; they take 126
    -- sulfur and 25.2 plates a minute: 2 plants of the sulfur, which make 100.8 a minute each (two output inserters wind their belt), and 2
    -- furnaces of 18.75; the sulfur plants take 3,024 gas, which takes 6 refineries
    assert.are.equal("sulfuric-acid: 1260 per minute from 6 x oil-refinery, 5 x chemical-plant, 2 x stone-furnace", result.description)
    assert.are.same({sulfur = 2, ["sulfuric-acid"] = 3}, plants_by_recipe(result.entities))
    assert.are.same({6, 2}, {count_named(result.entities, "oil-refinery"), count_named(result.entities, "stone-furnace")})
  end)

  it("says what it makes and what it takes in a minute: the ore, the fuel, the water of both plants together and the crude oil", function()
    _G.prototypes = acid_game()

    local result = generator.generate("sulfuric-acid", 1000)

    local amounts = result.message[4]
    assert.are.same({"blueprint-generation.generated", "1260", {"fluid-name.sulfuric-acid"}}, {result.message[1], result.message[2], result.message[3]})
    assert.are.same({"blueprint-generation.raw-amount", "37.5", {"item-name.iron-ore"}}, amounts[2])
    assert.are.same({"blueprint-generation.raw-amount", "2.7", {"item-name.coal"}}, amounts[4])
    assert.are.same({"blueprint-generation.raw-amount", "5544", {"fluid-name.water"}}, amounts[6]) -- 2,520 for the acid and 3,024 for the sulfur
    assert.are.same({"blueprint-generation.raw-amount", "6720", {"fluid-name.crude-oil"}}, amounts[8])
  end)

  it("names the belts that come in, from the top down, once the force has what the design with one belt of each material needs", function()
    _G.prototypes = acid_game()

    local result = generator.generate("sulfuric-acid", 1000, fake_force{})

    assert.are.same({"blueprint-generation.generated-with-belts", {"", {"item-name.iron-ore"}, ", ", {"item-name.coal"}}}, {result.message[1], result.message[5]})
  end)

  for _, design in ipairs({"the original design of the belts", "the design with one belt of each material"}) do
    it("builds a blueprint that passes the validator in " .. design .. ": powered, one network of poles, the pipes meet, four networks of pipes (the water is one)", function()
      _G.prototypes = acid_game()
      local force = design:find("one belt") and fake_force{} or nil

      local result = generator.generate("sulfuric-acid", 1000, force)

      assert.are.same({}, validator.validate(renamed(result.entities), catalog()))
    end)
  end

  for _, design in ipairs({"the original design of the belts", "the design with one belt of each material"}) do
    it("carries the two items to the plants of the acid on a lane each, in " .. design .. ": the belt tracer finds nothing wrong", function()
      _G.prototypes = acid_game()
      local new = design:find("one belt") ~= nil

      local result = generator.generate("sulfuric-acid", 3000, new and fake_force{} or nil)

      assert.are.same({}, lane_problems(result.entities, new))
    end)
  end

  it("builds more plants for a higher rate and still passes the validator", function()
    _G.prototypes = acid_game()

    local result = generator.generate("sulfuric-acid", 3000)

    -- 8 plants of the acid take 336 sulfur a minute: 4 plants of the sulfur of 100.8
    assert.are.same({sulfur = 4, ["sulfuric-acid"] = 8}, plants_by_recipe(result.entities))
    assert.are.same({}, validator.validate(renamed(result.entities), catalog()))
  end)

  it("takes everything that comes in to the top left corner: the belt of the furnaces, the pipe of the crude oil and the one pipe of the water of both", function()
    _G.prototypes = acid_game()

    local result = generator.generate("sulfuric-acid", 1000)

    local ends = {}
    for _, entity in ipairs(result.entities) do
      local tile = grid.top_left_tile(entity.position)
      if tile.x == 0 and tile.y < 0 then
        ends[#ends + 1] = tile.y .. " " .. entity.name
      end
    end
    table.sort(ends)
    -- the furnaces start furthest west, the water of the acid plants furthest east, so the belt is on the row nearest the blueprint and the water
    -- on the top row
    assert.are.same({"-1 transport-belt", "-4 pipe", "-7 pipe"}, ends)
  end)

  describe("when the plants of the acid take another fluid than the plants of the sulfur", function()
    -- the acid made with steam instead of water: the plants of the sulfur still take water, so each has a pipe that comes in
    local acid_from_steam = a_recipe{
      energy = 1, ingredients = {amount_of(5, "sulfur"), amount_of(1, "iron-plate"), fluid_of(100, "steam")}, products = {fluid_of(50, "sulfuric-acid")},
      category = "chemistry",
    }

    it("brings each by a pipe of its own: the crude oil, the water and the steam, with the belt of the furnaces", function()
      _G.prototypes = acid_game{recipes = {["basic-oil-processing"] = gas, ["sulfur"] = sulfur, ["sulfuric-acid"] = acid_from_steam, ["iron-plate"] = plate}}

      local result = generator.generate("sulfuric-acid", 1000)

      local ends = {}
      for _, entity in ipairs(result.entities) do
        local tile = grid.top_left_tile(entity.position)
        if tile.x == 0 and tile.y < 0 then
          ends[#ends + 1] = tile.y .. " " .. entity.name
        end
      end
      table.sort(ends)
      assert.are.same({"-1 transport-belt", "-10 pipe", "-4 pipe", "-7 pipe"}, ends)
      assert.are.same({}, validator.validate(renamed(result.entities), catalog("steam")))
    end)

    it("puts a panel beside each of the pipes: the crude oil, the water and the steam", function()
      _G.prototypes = acid_game{recipes = {["basic-oil-processing"] = gas, ["sulfur"] = sulfur, ["sulfuric-acid"] = acid_from_steam, ["iron-plate"] = plate}}

      local result = generator.generate("sulfuric-acid", 1000, fake_force{})

      local icons = {}
      for _, panel in ipairs(builders.entities_named(result.entities, "display-panel")) do
        icons[#icons + 1] = panel.icon.type .. " " .. panel.icon.name
      end
      table.sort(icons)
      assert.are.same({"fluid crude-oil", "fluid steam", "fluid water", "item coal", "item iron-ore"}, icons)
    end)
  end)

  it("takes the belt of the furnaces of the original design down to the first tile of their belt of raw items, which has their inserters beside it", function()
    _G.prototypes = acid_game()

    local result = generator.generate("sulfuric-acid", 1000)

    -- the only belt that runs south in the row above the blueprint is the one that comes down to the block, in the column where it starts
    local columns = {}
    for _, belt in ipairs(builders.entities_named(result.entities, "transport-belt")) do
      local tile = grid.top_left_tile(belt.position)
      if tile.y == -1 and belt.direction == south then
        columns[#columns + 1] = tile.x
      end
    end
    table.sort(columns) -- the others are the first tiles of the winding belts of the plants, which stand east of the block of furnaces
    assert.are.equal(2, #columns)
    columns = {columns[1]}
    local below, beside = nil, nil
    for _, entity in ipairs(result.entities) do
      local tile = grid.top_left_tile(entity.position)
      if tile.y == 0 and tile.x == columns[1] then
        below = entity.name .. " " .. entity.direction
      elseif tile.y == 0 and tile.x == columns[1] + 1 then
        beside = entity.name
      end
    end
    assert.are.same({"transport-belt south", "inserter"}, {below, beside})
  end)

  it("puts a display panel with the fluid or the item beside each entry, once the force has unlocked it", function()
    _G.prototypes = acid_game()

    local result = generator.generate("sulfuric-acid", 1000, fake_force{})

    local icons = {}
    for _, panel in ipairs(builders.entities_named(result.entities, "display-panel")) do
      icons[#icons + 1] = panel.icon.type .. " " .. panel.icon.name
    end
    table.sort(icons)
    assert.are.same({"fluid crude-oil", "fluid water", "item coal", "item iron-ore"}, icons) -- one panel for the water of both plants
  end)

  it("puts a panel beside the entries of the pipes only in the original design, whose belt carries two items", function()
    _G.prototypes = acid_game()

    local result = generator.generate("sulfuric-acid", 1000, fake_force{locked = {"splitter"}})

    local icons = {}
    for _, panel in ipairs(builders.entities_named(result.entities, "display-panel")) do
      icons[#icons + 1] = panel.icon.type .. " " .. panel.icon.name
    end
    table.sort(icons)
    assert.are.same({"fluid crude-oil", "fluid water"}, icons)
  end)

  it("keeps the tile west of each entry free of lamps, where the player joins it", function()
    _G.prototypes = acid_game()
    local add, told = lights.add, nil
    lights.add = function(entities, options) told = options return add(entities, options) end

    generator.generate("sulfuric-acid", 1000, fake_force{})
    lights.add = add

    -- the coal, the iron ore, the crude oil and the water of both plants
    assert.are.same({{x = -1, y = -1}, {x = -1, y = -4}, {x = -1, y = -7}, {x = -1, y = -10}}, told.free_tiles)
  end)

  describe("an item made from an item made in plants, a raw item and a fluid (explosives)", function()
    -- 1 sulfur, 1 coal and 10 water make 2 explosives in 4 s: a plant of speed 1 makes 15 crafts, 30 a minute
    local explosives = a_recipe{
      energy = 4, ingredients = {amount_of(1, "sulfur"), amount_of(1, "coal"), fluid_of(10, "water")}, products = {amount_of(2, "explosives")},
      category = "chemistry",
    }

    local function explosives_game(changes)
      return acid_game(builders.merged({
        items = {"sulfur", "coal", "explosives"},
        recipes = {["basic-oil-processing"] = gas, ["sulfur"] = sulfur, ["explosives"] = explosives},
      }, changes))
    end

    -- What the belt tracer finds wrong with the lanes: the coal comes in on the row above the blueprint and the plants eat the sulfur and the coal.
    local function coal_lane_problems(entities)
      local rows = {}
      for _, belt in ipairs(builders.entities_named(entities, "transport-belt")) do
        local tile = grid.top_left_tile(belt.position)
        if tile.x == 0 and tile.y < 0 then
          rows[#rows + 1] = tile.y
        end
      end
      return tracer.problems(renamed(entities), {
        machines = {
          ["sulfur-plant"] = {size = 3, eats = {}, makes = "sulfur"}, ["explosives-plant"] = {size = 3, eats = {"sulfur", "coal"}, makes = "explosives"},
          ["oil-refinery"] = {size = 5, eats = {}, makes = "petroleum-gas"},
        },
        raw = {}, product = "explosives", supplies = {{x = 0, y = rows[1], item = "coal"}},
      })
    end

    it("makes the explosives in plants east of the sulfur plants, and no furnace: the coal is a belt that comes in", function()
      _G.prototypes = explosives_game()

      local result = generator.generate("explosives", 100)

      -- 4 plants make 30 a minute each, for 100; they take 60 sulfur a minute: 1 plant of the sulfur (100.8), which takes 1,512 gas: 3 refineries
      assert.are.equal("explosives: 120 per minute from 3 x oil-refinery, 5 x chemical-plant", result.description)
      assert.are.same({sulfur = 1, explosives = 4}, plants_by_recipe(result.entities))
    end)

    it("says the coal comes in by a belt, with the amounts a minute: 60 crafts take 60 sulfur and coal and 600 water", function()
      _G.prototypes = explosives_game()

      local result = generator.generate("explosives", 100)

      assert.are.same({"blueprint-generation.generated-with-belts", {"", {"item-name.coal"}}}, {result.message[1], result.message[5]})
      assert.are.same({"blueprint-generation.raw-amount", "60", {"item-name.coal"}}, result.message[4][2])
    end)

    for _, design in ipairs({"the original design of the belts", "the design with one belt of each material"}) do
      it("builds a blueprint that passes the validator and the belt tracer in " .. design .. ", at 100 and at the most", function()
        _G.prototypes = explosives_game()
        local force = design:find("one belt") and fake_force{} or nil

        for _, rate in ipairs({100, 900}) do
          local result = generator.generate("explosives", rate, force)

          assert.are.same({}, validator.validate(renamed(result.entities), catalog()))
          assert.are.same({}, coal_lane_problems(result.entities))
        end
      end)
    end

    it("takes the explosives out by a belt on the east side of the plants, one inserter for each plant, and brings the coal in at the top left", function()
      _G.prototypes = explosives_game()

      local result = generator.generate("explosives", 100)

      local inserters, ends = 0, {}
      for _, entity in ipairs(result.entities) do
        local tile = grid.top_left_tile(entity.position)
        inserters = inserters + (entity.name == "inserter" and entity.direction == defines.direction.west and 1 or 0)
        if tile.x == 0 and tile.y < 0 then
          ends[#ends + 1] = tile.y .. " " .. entity.name
        end
      end
      table.sort(ends)
      assert.are.same({"-1 transport-belt", "-4 pipe", "-7 pipe"}, ends)
      assert.are.equal(10, inserters) -- two for each of the 4 plants (the items in, the explosives out) and one for each of the 2 sulfur plants
    end)

    describe("with chemical plants of crafting speed 4, which make more than one inserter moves", function()
      local function fast_game()
        return explosives_game{machines = {
          ["oil-refinery"] = a_machine{crafting_speed = 1, size = 5, pipe_boxes = REFINERY_BOXES},
          ["chemical-plant"] = a_machine{crafting_speed = 4, size = 3, pipe_boxes = PLANT_BOXES},
        }}
      end

      it("gives each plant two output inserters, which wind the belt, so that both lanes carry explosives", function()
        _G.prototypes = fast_game()

        local result = generator.generate("explosives", 100)

        -- the final plants have an input inserter and two output inserters each, and each sulfur plant two output inserters
        local plants = plants_by_recipe(result.entities)
        assert.are.equal(plants.explosives * 3 + plants.sulfur * 2, count_named(result.entities, "inserter"))
      end)

      it("builds a blueprint that passes the validator and the belt tracer, in both designs of the belts", function()
        _G.prototypes = fast_game()

        for _, force in ipairs({false, fake_force{}}) do
          local result = generator.generate("explosives", 600, force or nil)

          assert.are.same({}, validator.validate(renamed(result.entities), catalog()))
          assert.are.same({}, coal_lane_problems(result.entities))
        end
      end)

      it("makes the most that two lanes carry, where one inserter would be limited to a lane's 450", function()
        _G.prototypes = fast_game()

        local max = generator.max_rate_message("explosives")

        -- the input inserter lets a plant craft 25.2 a minute, 50.4 explosives: 17 plants fit in 900
        assert.are.same({"blueprint-generation.max-rate", "856.8"}, max)
      end)
    end)

    it("puts a panel beside the coal, the crude oil and the water, which is one entry", function()
      _G.prototypes = explosives_game()

      local result = generator.generate("explosives", 100, fake_force{})

      local icons = {}
      for _, panel in ipairs(builders.entities_named(result.entities, "display-panel")) do
        icons[#icons + 1] = panel.icon.type .. " " .. panel.icon.name
      end
      table.sort(icons)
      assert.are.same({"fluid crude-oil", "fluid water", "item coal"}, icons)
    end)

    it("makes the most the two lanes of the belt carry, which the plants fill in turn, one inserter each: 900 a minute", function()
      _G.prototypes = explosives_game()

      assert.are.same({"blueprint-generation.max-rate", "900"}, generator.max_rate_message("explosives"))
    end)

    it("is limited by the lanes of the belt the explosives leave on, and names the most", function()
      _G.prototypes = explosives_game()

      local max = generator.max_rate_message("explosives")
      local result, error_message = generator.generate("explosives", tonumber(max[2]) + 1)

      assert.are.same({nil, {"blueprint-generation.error-rate-too-high", max[2]}}, {result, error_message})
    end)

    it("refuses an item made in plants that takes an item as well, as it refuses the chain of the acid", function()
      local sulfur_from_coal = a_recipe{
        energy = 1, ingredients = {amount_of(1, "coal"), fluid_of(30, "water"), fluid_of(30, "petroleum-gas")}, products = {amount_of(2, "sulfur")},
        category = "chemistry",
      }
      _G.prototypes = explosives_game{recipes = {["sulfur"] = sulfur_from_coal}}

      local result = generator.generate("explosives", 100)

      assert.is_nil(result)
    end)
  end)

  describe("the most one blueprint makes", function()
    it("is what as many acid plants as the lane of sulfur can feed make: 450 sulfur, 10 plants of the acid of 42", function()
      _G.prototypes = acid_game()

      -- the sulfur plants could make 806.4 a minute (8 of 100.8) but the belt of the sulfur side-loads one lane of the belt b, which carries 450;
      -- an acid plant takes 42: 10 plants, 4,200 acid
      assert.are.same({"blueprint-generation.max-rate", "4200"}, generator.max_rate_message("sulfuric-acid"))
    end)

    it("is refused above, naming the most", function()
      _G.prototypes = acid_game()

      local result, error_message = generator.generate("sulfuric-acid", 4201)

      assert.are.same({nil, {"blueprint-generation.error-rate-too-high", "4200"}}, {result, error_message})
    end)

    it("is allowed", function()
      _G.prototypes = acid_game()

      local result = generator.generate("sulfuric-acid", 4200)

      -- 10 plants of the acid take 420 sulfur a minute: 5 plants of the sulfur
      assert.are.same({sulfur = 5, ["sulfuric-acid"] = 10}, plants_by_recipe(result.entities))
    end)
  end)

  describe("refusals", function()
    it("refuses the fluid made in plants when no recipe makes the gas, naming it", function()
      _G.prototypes = acid_game{recipes = {["sulfur"] = sulfur, ["sulfuric-acid"] = acid, ["iron-plate"] = plate}}

      local result, error_message = generator.generate("sulfuric-acid", 1000)

      assert.are.same({nil, {"blueprint-generation.error-no-recipe", {"fluid-name.petroleum-gas"}}}, {result, error_message})
    end)

    it("stops with a message when the game has no pipe to ground", function()
      _G.prototypes = acid_game{missing_entities = {"pipe-to-ground"}}

      local result, error_message = generator.generate("sulfuric-acid", 1000)

      assert.are.same({nil, {"blueprint-generation.error-missing-prototype"}}, {result, error_message})
    end)

    it("refuses plants that have a pipe connection at every row, which leave no row for an inserter", function()
      local every_row = {
        {production_type = "input", position = {x = -1, y = -1}, direction = north}, {production_type = "input", position = {x = 0, y = -1}, direction = north},
        {production_type = "input", position = {x = 1, y = -1}, direction = north},
        {production_type = "output", position = {x = -1, y = 1}, direction = south}, {production_type = "output", position = {x = 1, y = 1}, direction = south},
      }
      _G.prototypes = acid_game{machines = {
        ["oil-refinery"] = a_machine{crafting_speed = 1, size = 5, pipe_boxes = REFINERY_BOXES},
        ["chemical-plant"] = a_machine{crafting_speed = 1, size = 3, pipe_boxes = every_row},
      }}

      local result, error_message = generator.generate("sulfuric-acid", 1000)

      assert.are.same({nil, "blueprint-generation.error-fluid-row-pipes"}, {result, error_message[1]})
    end)

    it("refuses a recipe whose two fluids both have a recipe in the config, which the plants cannot be fed from", function()
      _G.prototypes = acid_game()
      config.fluid_makers["water"] = "basic-oil-processing"

      local result, error_message = generator.generate("sulfuric-acid", 1000)
      config.fluid_makers["water"] = nil

      assert.are.same({nil, "blueprint-generation.error-fluid-row-recipe"}, {result, error_message[1]})
    end)

    it("refuses a recipe whose water has a recipe in the config, which the plants of the acid cannot be fed from", function()
      local water_recipe = a_recipe{energy = 1, ingredients = {fluid_of(1, "steam")}, products = {fluid_of(1, "water")}, category = "oil-processing"}
      _G.prototypes = acid_game{recipes = {
        ["basic-oil-processing"] = gas, ["sulfur"] = sulfur, ["sulfuric-acid"] = acid, ["iron-plate"] = plate, ["water-from-steam"] = water_recipe,
      }}
      config.fluid_makers["water"] = "water-from-steam"

      local result, error_message = generator.generate("sulfuric-acid", 1000)
      config.fluid_makers["water"] = nil

      assert.are.same({nil, "blueprint-generation.error-fluid-row-recipe"}, {result, error_message[1]})
    end)

    it("refuses an acid of three items, which the plants have no belt for, as a fluid made from a fluid", function()
      local three = a_recipe{
        energy = 1, ingredients = {amount_of(5, "sulfur"), amount_of(1, "iron-plate"), amount_of(1, "coal"), fluid_of(100, "water")},
        products = {fluid_of(50, "sulfuric-acid")}, category = "chemistry",
      }
      _G.prototypes = acid_game{recipes = {["basic-oil-processing"] = gas, ["sulfur"] = sulfur, ["sulfuric-acid"] = three, ["iron-plate"] = plate}}

      local result, error_message = generator.generate("sulfuric-acid", 1000)

      assert.are.same({nil, {"blueprint-generation.error-fluid-row-recipe", {"fluid-name.sulfuric-acid"}}}, {result, error_message})
    end)

    describe("a recipe that is not of the shape of the chain: an item made in plants from fluids and an item made on belts from raw items", function()
      local function refused_as_a_fluid_made_from_a_fluid(game)
        _G.prototypes = game

        local result, error_message = generator.generate("sulfuric-acid", 1000)

        assert.are.same({nil, {"blueprint-generation.error-fluid-row-recipe", {"fluid-name.sulfuric-acid"}}}, {result, error_message})
      end

      it("refuses an item made on belts that takes a fluid", function()
        local wet_plate = a_recipe{
          energy = 3.2, ingredients = {amount_of(1, "iron-ore"), fluid_of(10, "water")}, products = {amount_of(1, "iron-plate")}, category = "smelting",
        }

        refused_as_a_fluid_made_from_a_fluid(acid_game{recipes = {["basic-oil-processing"] = gas, ["sulfur"] = sulfur, ["sulfuric-acid"] = acid, ["iron-plate"] = wet_plate}})
      end)

      it("refuses an item made on belts from an item that takes a fluid", function()
        local powder = a_recipe{
          energy = 1, ingredients = {amount_of(1, "iron-ore"), fluid_of(10, "water")}, products = {amount_of(1, "iron-powder")}, category = "crafting",
        }
        local plate_from_powder = a_recipe{
          energy = 3.2, ingredients = {amount_of(1, "iron-powder")}, products = {amount_of(1, "iron-plate")}, category = "smelting",
        }

        refused_as_a_fluid_made_from_a_fluid(acid_game{
          items = {"iron-ore", "iron-plate", "sulfur", "iron-powder"},
          machines = {
            ["oil-refinery"] = a_machine{crafting_speed = 1, size = 5, pipe_boxes = REFINERY_BOXES},
            ["chemical-plant"] = a_machine{crafting_speed = 1, size = 3, pipe_boxes = PLANT_BOXES},
            ["assembling-machine-1"] = a_machine{crafting_speed = 0.5, size = 3},
          },
          recipes = {["basic-oil-processing"] = gas, ["sulfur"] = sulfur, ["sulfuric-acid"] = acid, ["iron-plate"] = plate_from_powder, ["iron-powder"] = powder},
        })
      end)

      it("refuses an item made in plants that takes an item as well", function()
        local sulfur_from_coal = a_recipe{
          energy = 1, ingredients = {amount_of(1, "coal"), fluid_of(30, "water"), fluid_of(30, "petroleum-gas")}, products = {amount_of(2, "sulfur")},
          category = "chemistry",
        }

        refused_as_a_fluid_made_from_a_fluid(acid_game{recipes = {["basic-oil-processing"] = gas, ["sulfur"] = sulfur_from_coal, ["sulfuric-acid"] = acid, ["iron-plate"] = plate}})
      end)

      it("refuses a recipe that takes two fluids", function()
        local two_fluids = a_recipe{
          energy = 1, ingredients = {amount_of(5, "sulfur"), amount_of(1, "iron-plate"), fluid_of(100, "water"), fluid_of(1, "steam")},
          products = {fluid_of(50, "sulfuric-acid")}, category = "chemistry",
        }

        refused_as_a_fluid_made_from_a_fluid(acid_game{recipes = {["basic-oil-processing"] = gas, ["sulfur"] = sulfur, ["sulfuric-acid"] = two_fluids, ["iron-plate"] = plate}})
      end)

      it("takes the item that nothing makes as a raw item that comes in by a belt, as the coal of explosives does", function()
        _G.prototypes = acid_game{recipes = {["basic-oil-processing"] = gas, ["sulfur"] = sulfur, ["sulfuric-acid"] = acid}}

        local result = generator.generate("sulfuric-acid", 1000)

        assert.are.equal("sulfuric-acid: 1260 per minute from 6 x oil-refinery, 5 x chemical-plant", result.description)
      end)

      it("takes the two items in the other order, the item made on belts first", function()
        local plates_first = a_recipe{
          energy = 1, ingredients = {amount_of(1, "iron-plate"), amount_of(5, "sulfur"), fluid_of(100, "water")}, products = {fluid_of(50, "sulfuric-acid")},
          category = "chemistry",
        }
        _G.prototypes = acid_game{recipes = {["basic-oil-processing"] = gas, ["sulfur"] = sulfur, ["sulfuric-acid"] = plates_first, ["iron-plate"] = plate}}

        local result = generator.generate("sulfuric-acid", 1000)

        assert.are.equal("sulfuric-acid: 1260 per minute from 6 x oil-refinery, 5 x chemical-plant, 2 x stone-furnace", result.description)
      end)
    end)

    it("refuses the chain when the refineries cannot be built: a refinery that burns fuel", function()
      _G.prototypes = acid_game{machines = {
        ["oil-refinery"] = a_machine{crafting_speed = 1, size = 5, pipe_boxes = REFINERY_BOXES, burns = {"chemical"}},
        ["chemical-plant"] = a_machine{crafting_speed = 1, size = 3, pipe_boxes = PLANT_BOXES},
      }}

      local result, error_message = generator.generate("sulfuric-acid", 1000)

      assert.are.same({nil, {"blueprint-generation.error-unsupported-energy"}}, {result, error_message})
    end)

    it("refuses the chain when the steps on belts cannot be built: a furnace that takes more fuel than a belt brings", function()
      local instant_plate = a_recipe{energy = 0, ingredients = {amount_of(1, "iron-ore")}, products = {amount_of(1, "iron-plate")}, category = "smelting"}
      _G.prototypes = acid_game{recipes = {["basic-oil-processing"] = gas, ["sulfur"] = sulfur, ["sulfuric-acid"] = acid, ["iron-plate"] = instant_plate}}

      local result, error_message = generator.generate("sulfuric-acid", 1000)

      assert.are.same({nil, {"blueprint-generation.error-unsupported-recipe"}}, {result, error_message})
    end)

    it("is limited by the steps on belts when the plates are what the plants of the acid need most", function()
      -- 100 plates and 5 sulfur for a craft: the one inserter brings the 105 items in 0.48 crafts a minute, which takes 48 plates a minute
      -- and 2.4 sulfur and makes 24 acid; the plates a blueprint makes are what one lane of a belt carries, which is 9 plants of them
      local heavy = a_recipe{
        energy = 1, ingredients = {amount_of(5, "sulfur"), amount_of(100, "iron-plate"), fluid_of(100, "water")}, products = {fluid_of(50, "sulfuric-acid")},
        category = "chemistry",
      }
      _G.prototypes = acid_game{recipes = {["basic-oil-processing"] = gas, ["sulfur"] = sulfur, ["sulfuric-acid"] = heavy, ["iron-plate"] = plate}}

      assert.are.same({"blueprint-generation.max-rate", "216"}, generator.max_rate_message("sulfuric-acid"))
    end)

    it("refuses an acid whose recipe the force has not unlocked, naming it", function()
      _G.prototypes = acid_game()

      local result, error_message = generator.generate("sulfuric-acid", 1000, fake_force{locked = {"sulfuric-acid"}})

      assert.are.same({nil, {"blueprint-generation.error-locked", {"fluid-name.sulfuric-acid"}}}, {result, error_message})
    end)
  end)
end)
