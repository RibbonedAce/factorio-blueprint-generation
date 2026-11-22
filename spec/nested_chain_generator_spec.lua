-- spec/nested_chain_generator_spec.lua
-- The generator for an item made from two items made on belts and a fluid that a chain of its own makes: battery (1 iron plate, 1 copper plate and
-- 20 sulfuric acid make 1 battery in 4 s). The iron plate and the copper plate come from furnaces, and the acid from the whole chain of
-- spec/item_fluid_chain_generator_spec.lua (sulfur from petroleum gas and water in plants fed by refineries, iron plates in furnaces, and the
-- plants of the acid), drawn beside the plants of the battery with its pipe running into their trunk (see scripts/item_fluid_chain.lua). The stand-ins
-- of the game are those of that spec: a refinery of 5 x 5 and a chemical plant of 3 x 3, a furnace and an inserter that move 50.4 items a minute.
---@diagnostic disable: undefined-field  -- luassert's `assert` has fields (`assert.are`, `assert.is_nil`, ...) the editor cannot see
---@diagnostic disable: need-check-nil  -- the assertion before each use fails the test first if the result is nil
---@diagnostic disable: global-in-non-module  -- `_G.prototypes = ...` is how a spec fakes the game's global

local builders = require("spec.support.builders")
local generator = require("scripts.generator")
local grid = require("scripts.grid")
local tracer = require("spec.support.belt_tracer")
local validator = require("spec.support.blueprint_validator")

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
local iron = a_recipe{energy = 3.2, ingredients = {amount_of(1, "iron-ore")}, products = {amount_of(1, "iron-plate")}, category = "smelting"}
local copper = a_recipe{energy = 3.2, ingredients = {amount_of(1, "copper-ore")}, products = {amount_of(1, "copper-plate")}, category = "smelting"}
-- 1 iron plate, 1 copper plate and 20 acid make 1 battery in 4 s: a plant of speed 1 makes 15 a minute and takes 300 acid
local battery = a_recipe{
  energy = 4, ingredients = {amount_of(1, "iron-plate"), amount_of(1, "copper-plate"), fluid_of(20, "sulfuric-acid")}, products = {amount_of(1, "battery")},
  category = "chemistry",
}

-- The game with the recipes of the chain and the machines the layouts draw, with the changes the test says.
local function battery_game(changes)
  return builders.fake_prototypes(builders.merged({
    items = {"iron-ore", "iron-plate", "copper-ore", "copper-plate", "sulfur", "battery"},
    machines = {
      ["oil-refinery"] = a_machine{crafting_speed = 1, size = 5, pipe_boxes = REFINERY_BOXES},
      ["chemical-plant"] = a_machine{crafting_speed = 1, size = 3, pipe_boxes = PLANT_BOXES},
    },
    recipes = {
      ["basic-oil-processing"] = gas, ["sulfur"] = sulfur, ["sulfuric-acid"] = acid, ["iron-plate"] = iron, ["copper-plate"] = copper, ["battery"] = battery,
    },
  }, changes))
end

-- All the recipes of the game, with those the test gives instead (`battery_game` takes a table of recipes whole).
local function recipes_with(replacements)
  local recipes = {
    ["basic-oil-processing"] = gas, ["sulfur"] = sulfur, ["sulfuric-acid"] = acid, ["iron-plate"] = iron, ["copper-plate"] = copper, ["battery"] = battery,
  }
  for name, recipe in pairs(replacements) do
    recipes[name] = recipe
  end
  return recipes
end

local PLANT_NAMES = {sulfur = "sulfur-plant", ["sulfuric-acid"] = "acid-plant", battery = "battery-plant"}
-- The furnaces stand in three columns, from the west: the iron plates of the batteries, the copper plates, the iron plates of the acid.
local FURNACE_NAMES = {"iron-furnace", "copper-furnace", "acid-iron-furnace"}

-- The entities with each chemical plant named for what it makes and each furnace for what its column makes, so that the validator and the belt
-- tracer, which know machines by name, can tell them apart.
local function renamed(entities)
  local columns, furnace_of = {}, {}
  for _, entity in ipairs(entities) do
    if entity.name == "stone-furnace" then
      columns[grid.top_left_tile(entity.position, 2, 2).x] = true
    end
  end
  local xs = {}
  for x in pairs(columns) do
    xs[#xs + 1] = x
  end
  table.sort(xs)
  for index, x in ipairs(xs) do
    furnace_of[x] = FURNACE_NAMES[index]
  end
  local copies = {}
  for index, entity in ipairs(entities) do
    local copy = {}
    for key, value in pairs(entity) do
      copy[key] = value
    end
    if entity.name == "chemical-plant" then
      copy.name = PLANT_NAMES[entity.recipe]
    elseif entity.name == "stone-furnace" then
      copy.name = furnace_of[grid.top_left_tile(entity.position, 2, 2).x]
    end
    copies[index] = copy
  end
  return copies
end

-- The catalog of the validator: the plants of the acid give the acid at the two connections under them, which the plants of the battery take at the
-- two connections above them, so the two are one network of pipes.
local function catalog()
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
    fluid_connections = {water = {{x = 0, y = -1}, {x = 2, y = -1}}, acid = {{x = 0, y = 3}, {x = 2, y = 3}}},
  }
  entries["battery-plant"] = {
    kind = "machine", width = 3, height = 3, needs_power = true, fluid_connections = {acid = {{x = 0, y = -1}, {x = 2, y = -1}}},
  }
  for _, name in ipairs(FURNACE_NAMES) do
    entries[name] = entries["stone-furnace"]
  end
  return entries
end

-- What the belt tracer finds wrong with the lanes of the belts. For the design with one belt of each material (`belts` names the belts that
-- come in, from the top down) it is told where each starts, at the west edge above the blueprint, and that a furnace takes the ore on one lane and
-- the fuel on the other.
local function lane_problems(entities, belts)
  local options = {
    machines = {
      ["sulfur-plant"] = {size = 3, eats = {}, makes = "sulfur"}, ["acid-plant"] = {size = 3, eats = {"sulfur", "iron-plate"}, makes = "sulfuric-acid"},
      ["battery-plant"] = {size = 3, eats = {"iron-plate", "copper-plate"}, makes = "battery"}, ["oil-refinery"] = {size = 5, eats = {}, makes = "petroleum-gas"},
      ["iron-furnace"] = {size = 2, eats = {"iron-ore"}, makes = "iron-plate"}, ["acid-iron-furnace"] = {size = 2, eats = {"iron-ore"}, makes = "iron-plate"},
      ["copper-furnace"] = {size = 2, eats = {"copper-ore"}, makes = "copper-plate"},
    },
    raw = {["iron-furnace"] = true, ["copper-furnace"] = true, ["acid-iron-furnace"] = true}, product = "battery",
  }
  if belts then
    local rows = {}
    for _, belt in ipairs(builders.entities_named(entities, "transport-belt")) do
      local tile = grid.top_left_tile(belt.position)
      if tile.x == 0 then
        rows[#rows + 1] = tile.y
      end
    end
    table.sort(rows)
    options.underground_reach = 5
    options.raw_lanes = {["iron-furnace"] = {"iron-ore", "coal"}, ["copper-furnace"] = {"copper-ore", "coal"}, ["acid-iron-furnace"] = {"iron-ore", "coal"}}
    options.supplies = {}
    for index, item in ipairs(belts) do
      options.supplies[index] = {x = 0, y = rows[index], item = item}
    end
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

describe("the generator for an item made from two items on belts and a fluid that a chain makes", function()
  it("makes the batteries in plants, with the acid from its chain and the plates from furnaces: 100 a minute take 7 plants", function()
    _G.prototypes = battery_game()

    local result = generator.generate("battery", 100)

    -- 7 plants make 105 and take 105 iron plates and 105 copper plates (6 furnaces each, of 18.75) and 2,100 acid: 42 crafts of the acid, which take
    -- 210 sulfur and 42 plates (3 furnaces), so 5 plants of the acid (8.4 crafts each) and 3 of the sulfur (2 x 50.4 a minute each), and 9 refineries
    assert.are.equal("battery: 105 per minute from 15 x stone-furnace, 9 x oil-refinery, 15 x chemical-plant", result.description)
    assert.are.same({battery = 7, ["sulfuric-acid"] = 5, sulfur = 3}, plants_by_recipe(result.entities))
  end)

  it("builds a plant of the battery and a furnace of each kind for a rate of one", function()
    _G.prototypes = battery_game()

    local result = generator.generate("battery", 1)

    assert.are.same({battery = 1, ["sulfuric-acid"] = 1, sulfur = 1}, plants_by_recipe(result.entities))
  end)

  for _, design in ipairs({"the original design of the belts", "the design with one belt of each material"}) do
    it("builds a blueprint that passes the validator and the belt tracer in " .. design .. ", at 1, at 100 and at the most", function()
      _G.prototypes = battery_game()
      local force = design:find("one belt") and fake_force{} or nil

      for _, rate in ipairs({1, 100, 210}) do
        local result = generator.generate("battery", rate, force)

        assert.are.same({}, validator.validate(renamed(result.entities), catalog()))
        assert.are.same({}, lane_problems(result.entities, force and builders.belts_named(result.message) or nil))
      end
    end)
  end

  it("says what it takes in a minute: the ore, the fuel, the water and the crude oil of all of its parts together", function()
    _G.prototypes = battery_game()

    local result = generator.generate("battery", 100)

    -- the furnaces take what they can smelt, 18.75 a minute each: 6 for the iron plates of the batteries and 6 for the copper plates (112.5 each) and 3 for
    -- the iron plates of the acid (56.25), which are 168.75 iron ore and 112.5 copper ore; the fuel of the 15 furnaces, the water and the crude oil
    local amounts, count = {}, 0
    for _, raw in ipairs(result.message[4]) do
      if type(raw) == "table" then -- the list has the separators between them
        amounts[raw[3][1]], count = raw[2], count + 1
      end
    end
    assert.are.same({"168.75", "112.5", 5}, {amounts["item-name.iron-ore"], amounts["item-name.copper-ore"], count})
  end)

  it("names the belts that come in, from the top down, once the force has what the design with one belt of each material needs", function()
    _G.prototypes = battery_game()

    local result = generator.generate("battery", 100, fake_force{})

    -- three belts, one for each material: the ore of the iron of the batteries and of the acid together, the copper ore and the coal of the three furnaces
    assert.are.equal("blueprint-generation.generated-with-belts", result.message[1])
    assert.are.same({"coal", "iron-ore", "copper-ore"}, builders.belts_named(result.message))
  end)

  it("puts a display panel beside each of the three belts, the crude oil and the water, once the force has unlocked it", function()
    _G.prototypes = battery_game()

    local result = generator.generate("battery", 100, fake_force{})

    assert.are.equal(5, count_named(result.entities, "display-panel"))
  end)

  it("brings every entry to the top left corner, on a row of its own: the pipes above the band, the belts in it", function()
    _G.prototypes = battery_game()

    local result = generator.generate("battery", 100, fake_force{})

    local rows = {}
    for _, entity in ipairs(result.entities) do
      local tile = grid.top_left_tile(entity.position)
      if tile.x == 0 and (entity.name == "transport-belt" or entity.name == "pipe") then
        rows[#rows + 1] = tile.y
      end
    end
    table.sort(rows)
    assert.are.same({-6, -3, 0, 2, 5}, rows)
  end)

  describe("the most one blueprint makes", function()
    it("is what the acid chain makes: 4,200 acid a minute, which are 210 batteries of 20", function()
      _G.prototypes = battery_game()

      local max = generator.max_rate_message("battery")

      assert.are.same({"blueprint-generation.max-rate", "210"}, max)
    end)

    it("is refused above, naming the most", function()
      _G.prototypes = battery_game()

      local result, error_message = generator.generate("battery", 211)

      assert.are.same({nil, "blueprint-generation.error-rate-too-high", "210"}, {result, error_message[1], error_message[2]})
    end)
  end)

  describe("when a plate, not the acid, is what limits it", function()
    -- a plant of speed 1 makes 15 a minute, so a recipe of 3 plates of one kind takes 45 of them a minute from each plant; the furnaces of that plate and
    -- the lane of the belt b carry 415.8 of them a minute, which feed 9.24 plants, that is 138.6 batteries
    local function with_plates(iron_plates, copper_plates)
      return battery_game{recipes = recipes_with{["battery"] = a_recipe{
        energy = 4, ingredients = {amount_of(iron_plates, "iron-plate"), amount_of(copper_plates, "copper-plate"), fluid_of(20, "sulfuric-acid")},
        products = {amount_of(1, "battery")}, category = "chemistry",
      }}}
    end

    it("makes 138.6 a minute at the most when the battery takes 3 iron plates: the lane of the belt b carries 415.8 of them", function()
      _G.prototypes = with_plates(3, 1)

      assert.are.same({"blueprint-generation.max-rate", "138.6"}, generator.max_rate_message("battery"))
    end)

    it("makes 138.6 a minute at the most when the battery takes 3 copper plates", function()
      _G.prototypes = with_plates(1, 3)

      assert.are.same({"blueprint-generation.max-rate", "138.6"}, generator.max_rate_message("battery"))
    end)

    it("builds a blueprint at that most, which passes the validator", function()
      _G.prototypes = with_plates(3, 1)

      local result = generator.generate("battery", 138.6)

      assert.are.same({}, validator.validate(renamed(result.entities), catalog()))
    end)

    it("refuses a rate above that most, naming it", function()
      _G.prototypes = with_plates(3, 1)

      local result, error_message = generator.generate("battery", 140)

      assert.are.same({nil, "blueprint-generation.error-rate-too-high", "138.6"}, {result, error_message[1], error_message[2]})
    end)
  end)

  describe("refusals", function()
    it("refuses a recipe of a part that the planner cannot handle: a copper plate that takes no time", function()
      _G.prototypes = battery_game{recipes = recipes_with{["copper-plate"] = a_recipe{
        energy = 0, ingredients = {amount_of(1, "copper-ore")}, products = {amount_of(1, "copper-plate")}, category = "smelting",
      }}}

      local result = generator.generate("battery", 100)

      assert.is_nil(result)
    end)

    it("refuses a battery that takes no time", function()
      _G.prototypes = battery_game{recipes = recipes_with{["battery"] = a_recipe{
        energy = 0, ingredients = {amount_of(1, "iron-plate"), amount_of(1, "copper-plate"), fluid_of(20, "sulfuric-acid")},
        products = {amount_of(1, "battery")}, category = "chemistry",
      }}}

      local result = generator.generate("battery", 100)

      assert.is_nil(result)
    end)

    for _, plate in ipairs({"iron-plate", "copper-plate"}) do
      it("does not make the chain of a battery when its " .. plate .. " takes a fluid, which the furnaces cannot", function()
        local ore = plate == "iron-plate" and "iron-ore" or "copper-ore"
        _G.prototypes = battery_game{recipes = recipes_with{[plate] = a_recipe{
          energy = 3.2, ingredients = {amount_of(1, ore), fluid_of(1, "water")}, products = {amount_of(1, plate)}, category = "smelting",
        }}}

        local result = generator.generate("battery", 100)

        assert.is_nil(result)
      end)
    end

    it("refuses when no recipe makes the petroleum gas of the sulfur of the acid, naming it", function()
      _G.prototypes = battery_game{recipes = {
        ["sulfur"] = sulfur, ["sulfuric-acid"] = acid, ["iron-plate"] = iron, ["copper-plate"] = copper, ["battery"] = battery,
      }}

      local result, error_message = generator.generate("battery", 100)

      assert.are.same({nil, {"blueprint-generation.error-no-recipe", {"fluid-name.petroleum-gas"}}}, {result, error_message})
    end)

    it("refuses a battery whose recipe the force has not unlocked, naming it", function()
      _G.prototypes = battery_game()

      local result, error_message = generator.generate("battery", 100, fake_force{locked = {"battery"}})

      assert.are.same({nil, {"blueprint-generation.error-locked", {"item-name.battery"}}}, {result, error_message})
    end)
  end)
end)
