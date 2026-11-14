-- spec/generator_spec.lua
-- The generator reads the game's prototype data (here a stand-in assigned to
-- the global `prototypes`) and ties the planner and layout together.
--
-- Each test says which prototypes exist: the recipe it needs, and the furnace and
-- belt speeds its numbers depend on. A furnace of speed 1 on a 3.2 s recipe makes
-- 60 / 3.2 = 18.75 items a minute. Which items can be generated is decided by
-- scripts/config.lua, so the tests use `iron-plate` and `stone-brick` for the two
-- recipe shapes; the shapes, not the names, are what is being tested. The electric
-- shapes (no fuel) use `iron-gear-wheel`, the one electric product, as a label.
--
-- Busted runs each spec file in its own sandbox, where a plain assignment would
-- only be visible inside the spec. The generator reads the REAL global
-- `prototypes`, so the specs assign `_G.prototypes` explicitly.
---@diagnostic disable: undefined-field  -- luassert's `assert` has fields (`assert.are`, `assert.is_nil`, ...) the editor cannot see
---@diagnostic disable: need-check-nil  -- the assertion before each use fails the test first if the result is nil
---@diagnostic disable: global-in-non-module  -- `_G.prototypes = ...` is how a spec fakes the game's global (see the note above)

local builders = require("spec.support.builders")
local generator = require("scripts.generator")
local validator = require("spec.support.blueprint_validator")
local grid = require("scripts.grid")

local fake_prototypes = builders.fake_prototypes
local a_recipe = builders.a_recipe
local a_machine = builders.a_machine
local fake_force = builders.fake_force
local amount_of = builders.amount_of
local fluid_of = builders.fluid_of

-- The message for a blueprint that is ready: how much of the product it makes a minute, then the raw
-- items and the fuel as {item, amount a minute} pairs, in the order the message lists them.
local function ready_message(product, per_minute, raws)
  local list = {""}
  for index, raw in ipairs(raws) do
    if index > 1 then
      list[#list + 1] = ", "
    end
    list[#list + 1] = {"blueprint-generation.raw-amount", raw[2], {"item-name." .. raw[1]}}
  end
  return {"blueprint-generation.generated", per_minute, {"item-name." .. product}, list}
end

-- The message for a blueprint that takes one belt of each material: the same, and the items of the belts that come in,
-- from the top of the blueprint down.
local function ready_message_with_belts(product, per_minute, raws, belts)
  local message = ready_message(product, per_minute, raws)
  message[1] = "blueprint-generation.generated-with-belts"
  local list = {""}
  for index, name in ipairs(belts) do
    if index > 1 then
      list[#list + 1] = ", "
    end
    list[#list + 1] = {"item-name." .. name}
  end
  message[5] = list
  return message
end

local function count_named(entities, name)
  local total = 0
  for _, entity in ipairs(entities) do
    if entity.name == name then
      total = total + 1
    end
  end
  return total
end

-- The distinct entity names used, sorted, as a list.
local function distinct_names_of(entities)
  local seen, names = {}, {}
  for _, entity in ipairs(entities) do
    if entity.name and not seen[entity.name] then
      seen[entity.name] = true
      names[#names + 1] = entity.name
    end
  end
  table.sort(names)
  return names
end

describe("generator", function()
  describe("a recipe of one ingredient to one product", function()
    it("rounds the machine count up when the rate is not a multiple of one machine's output", function()
      _G.prototypes = fake_prototypes{
        furnace_speed = 1,
        recipes = {["iron-plate"] = a_recipe{energy = 3.2, ingredients = {amount_of(1, "iron-ore")}, products = {amount_of(1, "iron-plate")}, category = "smelting"}},
      }

      local result = generator.generate("iron-plate", 50)

      assert.are.equal(3, count_named(result.entities, "stone-furnace")) -- 50 / 18.75 = 2.67, rounded up
    end)

    it("adds a pole pair for every second machine when the machines need power", function()
      _G.prototypes = fake_prototypes{
        furnace_speed = 1,
        recipes = {["iron-plate"] = a_recipe{energy = 3.2, ingredients = {amount_of(1, "iron-ore")}, products = {amount_of(1, "iron-plate")}, category = "smelting"}},
      }

      local result = generator.generate("iron-plate", 50)

      assert.are.equal(4, count_named(result.entities, "small-electric-pole"))
    end)

    it("builds only with the buildings the game provides when generating a blueprint", function()
      _G.prototypes = fake_prototypes{
        recipes = {["iron-plate"] = a_recipe{energy = 3.2, ingredients = {amount_of(1, "iron-ore")}, products = {amount_of(1, "iron-plate")}, category = "smelting"}},
      }

      local result = generator.generate("iron-plate", 50)

      assert.are.same(
        {"inserter", "small-electric-pole", "stone-furnace", "transport-belt"},
        distinct_names_of(result.entities))
    end)

    it("tells the player how much it makes a minute, as much as its machines really make, and what it uses", function()
      _G.prototypes = fake_prototypes{
        furnace_speed = 1,
        recipes = {["iron-plate"] = a_recipe{energy = 3.2, ingredients = {amount_of(1, "iron-ore")}, products = {amount_of(1, "iron-plate")}, category = "smelting"}},
      }

      local result = generator.generate("iron-plate", 50)

      -- 3 furnaces x 18.75 = 56.25 plates (50 were asked for) eat 56.25 ore, and burn coal while they craft:
      -- 56.25 crafts of 3.2 s are 3 furnaces working all the time, and a furnace (90 kW) burns 1.35 coal of 4 MJ a minute.
      assert.are.same(ready_message("iron-plate", "56.25", {{"iron-ore", "56.25"}, {"coal", "4.05"}}), result.message)
    end)

    it("burns the coal the game's numbers say: more for a machine that uses more energy, a weaker burner, or a fuel with less in it", function()
      local recipes = {["iron-plate"] = a_recipe{energy = 3.2, ingredients = {amount_of(1, "iron-ore")}, products = {amount_of(1, "iron-plate")}, category = "smelting"}}

      -- 56.25 plates are 3 furnaces' worth of crafting; 3 x 1.35 = 4.05 coal with the defaults
      local function coal_for(options)
        options.furnace_speed = options.furnace_speed or 1
        options.recipes = recipes
        _G.prototypes = fake_prototypes(options)
        return generator.generate("iron-plate", 50).message[4][4][2]
      end

      assert.are.equal("4.05", coal_for({}))
      assert.are.equal("8.1", coal_for({furnace_energy_usage = 3000}))   -- twice the energy
      assert.are.equal("8.1", coal_for({furnace_effectivity = 0.5}))     -- half of it is lost
      assert.are.equal("8.1", coal_for({coal_fuel_value = 2000000}))     -- half the energy in a coal
      -- a furnace twice as fast crafts the 75 plates that 2 furnaces make in 3.2 / 2 s each: 2 furnaces' worth, 2 x 1.35
      assert.are.equal("2.7", coal_for({furnace_speed = 2}))
    end)

    it("leaves the fuel out of the message when the game does not say how much energy the machine uses", function()
      _G.prototypes = fake_prototypes{
        furnace_speed = 1,
        furnace_energy_usage = false,
        recipes = {["iron-plate"] = a_recipe{energy = 3.2, ingredients = {amount_of(1, "iron-ore")}, products = {amount_of(1, "iron-plate")}, category = "smelting"}},
      }

      local result = generator.generate("iron-plate", 50)

      assert.are.same(ready_message("iron-plate", "56.25", {{"iron-ore", "56.25"}}), result.message)
    end)

    it("prints whole numbers without decimals when the number is whole", function()
      _G.prototypes = fake_prototypes{
        furnace_speed = 1,
        recipes = {["iron-plate"] = a_recipe{energy = 3.2, ingredients = {amount_of(1, "iron-ore")}, products = {amount_of(1, "iron-plate")}, category = "smelting"}},
      }

      local result = generator.generate("iron-plate", 60)

      -- 4 furnaces x 18.75 = 75, not "75.00"; 75 crafts of 3.2 s are 4 furnaces working all the time: 4 x 1.35 coal, not "5.40"
      assert.are.same(ready_message("iron-plate", "75", {{"iron-ore", "75"}, {"coal", "5.4"}}), result.message)
    end)

    it("describes the blueprint with the rate achieved and the machines used when generating", function()
      _G.prototypes = fake_prototypes{
        furnace_speed = 1,
        recipes = {["iron-plate"] = a_recipe{energy = 3.2, ingredients = {amount_of(1, "iron-ore")}, products = {amount_of(1, "iron-plate")}, category = "smelting"}},
      }

      local result = generator.generate("iron-plate", 50)

      assert.are.equal("iron-plate: 56.25 per minute from 3 x stone-furnace", result.description)
    end)

    it("refuses the rate when it is more than one belt lane carries, naming the most", function()
      _G.prototypes = fake_prototypes{
        belt_speed = 0.03125,
        furnace_speed = 1,
        recipes = {["iron-plate"] = a_recipe{energy = 3.2, ingredients = {amount_of(1, "iron-ore")}, products = {amount_of(1, "iron-plate")}, category = "smelting"}},
      }

      local result, error_message = generator.generate("iron-plate", 1000)

      assert.is_nil(result)
      assert.are.same({"blueprint-generation.error-rate-too-high", "450"}, error_message)
    end)
  end)

  describe("a recipe of two of one ingredient to one product", function()
    it("allows the rate when the ingredient lane is exactly full", function()
      _G.prototypes = fake_prototypes{
        belt_speed = 0.03125,
        furnace_speed = 1,
        recipes = {["stone-brick"] = a_recipe{energy = 3.2, ingredients = {amount_of(2, "stone")}, products = {amount_of(1, "stone-brick")}, category = "smelting"}},
      }

      local result = generator.generate("stone-brick", 225)

      assert.are.equal(12, count_named(result.entities, "stone-furnace")) -- 12 x 37.5 ingredients = 450, one lane
    end)

    it("refuses the rate when the ingredient lane fills before the product lane", function()
      _G.prototypes = fake_prototypes{
        belt_speed = 0.03125,
        furnace_speed = 1,
        recipes = {["stone-brick"] = a_recipe{energy = 3.2, ingredients = {amount_of(2, "stone")}, products = {amount_of(1, "stone-brick")}, category = "smelting"}},
      }

      local result, error_message = generator.generate("stone-brick", 300)

      assert.is_nil(result)
      assert.are.same({"blueprint-generation.error-rate-too-high", "225"}, error_message) -- 12 furnaces x 18.75
    end)
  end)

  describe("a recipe of one ingredient to two products", function()
    it("reads how many items a craft makes from the recipe when it makes several", function()
      _G.prototypes = fake_prototypes{
        furnace_speed = 1,
        recipes = {["iron-plate"] = a_recipe{energy = 3.2, ingredients = {amount_of(1, "iron-ore")}, products = {amount_of(2, "iron-plate")}, category = "smelting"}},
      }

      local result = generator.generate("iron-plate", 75)

      assert.are.equal(2, count_named(result.entities, "stone-furnace")) -- 75 / (18.75 crafts x 2 items)
    end)
  end)

  describe("the belt's speed sets the limit, not a constant", function()
    it("allows a higher rate when the belt is faster", function()
      _G.prototypes = fake_prototypes{
        belt_speed = 0.0625, -- a lane holds 900 a minute
        furnace_speed = 1,
        recipes = {["iron-plate"] = a_recipe{energy = 3.2, ingredients = {amount_of(1, "iron-ore")}, products = {amount_of(1, "iron-plate")}, category = "smelting"}},
      }

      local result = generator.generate("iron-plate", 800)

      assert.are.equal(43, count_named(result.entities, "stone-furnace")) -- 800 / 18.75 = 42.7, rounded up
    end)

    it("refuses the rate, naming a higher most, when the belt is faster but still too slow", function()
      _G.prototypes = fake_prototypes{
        belt_speed = 0.0625,
        furnace_speed = 1,
        recipes = {["iron-plate"] = a_recipe{energy = 3.2, ingredients = {amount_of(1, "iron-ore")}, products = {amount_of(1, "iron-plate")}, category = "smelting"}},
      }

      local result, error_message = generator.generate("iron-plate", 1000)

      assert.is_nil(result)
      assert.are.same({"blueprint-generation.error-rate-too-high", "900"}, error_message) -- 48 furnaces x 18.75
    end)
  end)

  describe("a recipe made in an electric machine, with its one ingredient on both input lanes", function()
    local gear = a_recipe{energy = 0.5, ingredients = {amount_of(2, "iron-plate")}, products = {amount_of(1, "iron-gear-wheel")}}
    local assembler = a_machine{crafting_speed = 0.5, size = 3}

    it("needs more machines when the inserters cannot feed a machine at full speed", function()
      _G.prototypes = fake_prototypes{
        inserter_rotation_speed = 0.014, -- 50.4 items a minute
        machines = {["assembling-machine-1"] = assembler},
        recipes = {["iron-gear-wheel"] = gear},
      }

      local result = generator.generate("iron-gear-wheel", 100)

      assert.are.equal(2, count_named(result.entities, "assembling-machine-1")) -- a machine makes 60 x 100.8 / 120 = 50.4 gears; 100 / 50.4 = 1.98
    end)

    it("places as many inserters on each side as the machine's flow needs when generating", function()
      _G.prototypes = fake_prototypes{
        inserter_rotation_speed = 0.014,
        machines = {["assembling-machine-1"] = assembler},
        recipes = {["iron-gear-wheel"] = gear},
      }

      local result = generator.generate("iron-gear-wheel", 100)

      local input_column, output_column = 0, 0
      for _, entity in ipairs(result.entities) do
        if entity.name == "inserter" and entity.position.x == 1.5 then
          input_column = input_column + 1
        elseif entity.name == "inserter" and entity.position.x == 5.5 then
          output_column = output_column + 1
        end
      end
      assert.are.equal(4, input_column)  -- 2 machines x 2 (100.8 plates a minute / 50.4), in tile column 1
      assert.are.equal(2, output_column) -- 2 machines x 1 (50.4 gears a minute / 50.4), in tile column 5, after the 3 tile wide machine
    end)

    it("packs the machines with no gap when each side leaves a tile free for a pole", function()
      _G.prototypes = fake_prototypes{
        inserter_rotation_speed = 0.014,
        machines = {["assembling-machine-1"] = assembler},
        recipes = {["iron-gear-wheel"] = gear},
      }

      local result = generator.generate("iron-gear-wheel", 100)

      local centres = {}
      for _, entity in ipairs(result.entities) do
        if entity.name == "assembling-machine-1" then
          centres[#centres + 1] = {x = entity.position.x, y = entity.position.y}
        end
      end
      assert.are.same({{x = 3.5, y = 1.5}, {x = 3.5, y = 4.5}}, centres) -- 3 wide from column 2; rows 0 to 2, then 3 to 5
    end)

    it("needs fewer machines when the inserters are fast enough to run each machine at full speed", function()
      _G.prototypes = fake_prototypes{
        inserter_rotation_speed = 0.04, -- 144 items a minute, so two of them move more than the 120 a machine eats
        machines = {["assembling-machine-1"] = assembler},
        recipes = {["iron-gear-wheel"] = gear},
      }

      local result = generator.generate("iron-gear-wheel", 120)

      assert.are.equal(2, count_named(result.entities, "assembling-machine-1")) -- 120 / 60 gears a minute each
    end)

    it("names the one ingredient a machine that burns nothing eats, and no fuel", function()
      _G.prototypes = fake_prototypes{
        inserter_rotation_speed = 0.014,
        machines = {["assembling-machine-1"] = assembler},
        recipes = {["iron-gear-wheel"] = gear},
      }

      local result = generator.generate("iron-gear-wheel", 100)

      -- 2 assemblers make 2 x 50.4 = 100.8 gears from 2 plates each
      assert.are.same(ready_message("iron-gear-wheel", "100.8", {{"iron-plate", "201.6"}}), result.message)
    end)

    it("allows the rate when both input lanes are exactly full", function()
      _G.prototypes = fake_prototypes{
        belt_speed = 0.03125,
        inserter_rotation_speed = 0.014,
        machines = {["assembling-machine-1"] = assembler},
        recipes = {["iron-gear-wheel"] = gear},
      }

      local result = generator.generate("iron-gear-wheel", 400)

      assert.are.equal(8, count_named(result.entities, "assembling-machine-1")) -- 400 / 50.4 = 7.94; 8 x 100.8 plates is under the 900 of two lanes
    end)

    it("refuses the rate when the input lanes cannot carry what the machines would eat", function()
      _G.prototypes = fake_prototypes{
        belt_speed = 0.03125,
        inserter_rotation_speed = 0.014,
        machines = {["assembling-machine-1"] = assembler},
        recipes = {["iron-gear-wheel"] = gear},
      }

      local result, error_message = generator.generate("iron-gear-wheel", 500)

      assert.is_nil(result)
      assert.are.same({"blueprint-generation.error-rate-too-high", "450"}, error_message) -- 900 / 100.8 = 8.93 machines' worth x 50.4
    end)

    it("refuses the machine when its size is one the layout cannot handle", function()
      _G.prototypes = fake_prototypes{
        machines = {["assembling-machine-1"] = a_machine{crafting_speed = 0.5, size = 4}},
        recipes = {["iron-gear-wheel"] = gear},
      }

      local result, error_message = generator.generate("iron-gear-wheel", 60)

      assert.is_nil(result)
      assert.are.same({"blueprint-generation.error-unsupported-machine"}, error_message)
    end)

    it("refuses the machine when it is not square", function()
      _G.prototypes = fake_prototypes{
        machines = {["assembling-machine-1"] = a_machine{crafting_speed = 0.5, size = 3, height = 2}},
        recipes = {["iron-gear-wheel"] = gear},
      }

      local result, error_message = generator.generate("iron-gear-wheel", 60)

      assert.is_nil(result)
      assert.are.same({"blueprint-generation.error-unsupported-machine"}, error_message)
    end)
  end)

  describe("a recipe that makes more per craft than one output inserter moves, in an electric machine", function()
    -- One plate makes two items in 0.5 s: at speed 0.5 a machine could make 120 a minute and eat 60.
    local doubling = a_recipe{energy = 0.5, ingredients = {amount_of(1, "iron-plate")}, products = {amount_of(2, "iron-gear-wheel")}}
    local assembler = a_machine{crafting_speed = 0.5, size = 3}

    it("gives each machine two output inserters when it makes more than one inserter moves", function()
      _G.prototypes = fake_prototypes{
        inserter_rotation_speed = 0.014, -- 50.4 items a minute
        machines = {["assembling-machine-1"] = assembler},
        recipes = {["iron-gear-wheel"] = doubling},
      }

      local result = generator.generate("iron-gear-wheel", 200)

      assert.are.equal(2, count_named(result.entities, "assembling-machine-1")) -- each makes 2 x 50.4 = 100.8; 200 / 100.8 = 1.98
      assert.are.equal(6, count_named(result.entities, "inserter")) -- 2 machines x (1 in: 50.4, 2 out: 100.8 / 50.4)
    end)

    it("winds the output belt when each machine has two output inserters", function()
      _G.prototypes = fake_prototypes{
        inserter_rotation_speed = 0.014,
        machines = {["assembling-machine-1"] = assembler},
        recipes = {["iron-gear-wheel"] = doubling},
      }

      local result = generator.generate("iron-gear-wheel", 200)

      assert.are.equal(17, count_named(result.entities, "transport-belt")) -- 6 input tiles (rows 0 to 5, the second assembler's inserter being in its bottom row) + the winding belt: the start, two seams of two inserters (4 tiles each) and the two rows between them (11)
    end)

    it("gives a small machine only one output inserter when the layout has room for no more", function()
      _G.prototypes = fake_prototypes{
        inserter_rotation_speed = 0.014, -- 50.4 items a minute
        machines = {["assembling-machine-1"] = a_machine{crafting_speed = 0.5, size = 2}},
        recipes = {["iron-gear-wheel"] = doubling},
      }

      local result = generator.generate("iron-gear-wheel", 100)

      assert.are.equal(2, count_named(result.entities, "assembling-machine-1")) -- one output inserter moves 50.4, so 100 / 50.4 = 1.98
      assert.are.equal(4, count_named(result.entities, "inserter")) -- 2 machines x (1 in + 1 out)
    end)

    it("allows the rate when it is within the limits of two output lanes", function()
      _G.prototypes = fake_prototypes{
        belt_speed = 0.03125,
        inserter_rotation_speed = 0.014,
        machines = {["assembling-machine-1"] = assembler},
        recipes = {["iron-gear-wheel"] = doubling},
      }

      local result = generator.generate("iron-gear-wheel", 800)

      assert.are.equal(8, count_named(result.entities, "assembling-machine-1")) -- 800 / 100.8 = 7.94
    end)

    it("refuses the rate when the two output lanes cannot carry it", function()
      _G.prototypes = fake_prototypes{
        belt_speed = 0.03125,
        inserter_rotation_speed = 0.014,
        machines = {["assembling-machine-1"] = assembler},
        recipes = {["iron-gear-wheel"] = doubling},
      }

      local result, error_message = generator.generate("iron-gear-wheel", 901)

      assert.is_nil(result)
      assert.are.same({"blueprint-generation.error-rate-too-high", "900"}, error_message) -- 450 / 50.4 = 8.93 machines' worth x 100.8: both lanes full
    end)
  end)

  describe("a recipe made in an electric machine, with two ingredients on one lane each", function()
    local two_ingredients = a_recipe{
      energy = 0.5,
      ingredients = {amount_of(1, "iron-plate"), amount_of(3, "copper-cable")},
      products = {amount_of(1, "iron-gear-wheel")},
    }
    local assembler = a_machine{crafting_speed = 0.5, size = 3}

    it("names each ingredient of a recipe with two, whatever the lane it rides", function()
      _G.prototypes = fake_prototypes{
        inserter_rotation_speed = 0.014, -- 50.4 items a minute
        machines = {["assembling-machine-1"] = assembler},
        recipes = {["iron-gear-wheel"] = two_ingredients},
      }

      local result = generator.generate("iron-gear-wheel", 50)

      -- 2 x 25.2 = 50.4 achieved: 240 items a minute at full speed, but two inserters move 100.8, so 60 x 100.8 / 240.
      -- 1 plate and 3 cables for each.
      assert.are.same(ready_message("iron-gear-wheel", "50.4", {{"iron-plate", "50.4"}, {"copper-cable", "151.2"}}), result.message)
    end)

    it("refuses the rate when one ingredient's lane fills before the other's", function()
      _G.prototypes = fake_prototypes{
        belt_speed = 0.03125,
        inserter_rotation_speed = 0.014,
        machines = {["assembling-machine-1"] = assembler},
        recipes = {["iron-gear-wheel"] = two_ingredients},
      }

      local result, error_message = generator.generate("iron-gear-wheel", 151)

      assert.is_nil(result)
      assert.are.same({"blueprint-generation.error-rate-too-high", "150"}, error_message) -- a machine eats 75.6 cables a minute: 450 / 75.6 = 5.95 machines' worth x 25.2
    end)
  end)

  describe("the machine's energy source", function()
    local plate = a_recipe{energy = 3.2, ingredients = {amount_of(1, "iron-ore")}, products = {amount_of(1, "iron-plate")}, category = "smelting"}
    local gear = a_recipe{energy = 0.5, ingredients = {amount_of(2, "iron-plate")}, products = {amount_of(1, "iron-gear-wheel")}}

    it("builds when a burner machine accepts the fuel's category after another category", function()
      _G.prototypes = fake_prototypes{
        machines = {["stone-furnace"] = a_machine{crafting_speed = 1, size = 2, burns = {"aaa-fuel", "chemical"}}},
        recipes = {["iron-plate"] = plate},
      }

      local result = generator.generate("iron-plate", 50)

      assert.are.equal(3, count_named(result.entities, "stone-furnace"))
    end)

    it("builds when a burner machine accepts the fuel's category before another category", function()
      _G.prototypes = fake_prototypes{
        machines = {["stone-furnace"] = a_machine{crafting_speed = 1, size = 2, burns = {"chemical", "zzz-fuel"}}},
        recipes = {["iron-plate"] = plate},
      }

      local result = generator.generate("iron-plate", 50)

      assert.are.equal(3, count_named(result.entities, "stone-furnace"))
    end)

    it("refuses the machine when it cannot burn the configured fuel", function()
      _G.prototypes = fake_prototypes{
        machines = {["stone-furnace"] = a_machine{crafting_speed = 1, size = 2, burns = {"nuclear"}}},
        recipes = {["iron-plate"] = plate},
      }

      local result, error_message = generator.generate("iron-plate", 50)

      assert.is_nil(result)
      assert.are.same({"blueprint-generation.error-fuel-mismatch", {"entity-name.stone-furnace"}}, error_message)
    end)

    it("refuses the machine when it accepts no fuel at all", function()
      _G.prototypes = fake_prototypes{
        machines = {["stone-furnace"] = a_machine{crafting_speed = 1, size = 2, burns = {}}},
        recipes = {["iron-plate"] = plate},
      }

      local result, error_message = generator.generate("iron-plate", 50)

      assert.is_nil(result)
      assert.are.same({"blueprint-generation.error-fuel-mismatch", {"entity-name.stone-furnace"}}, error_message)
    end)

    it("refuses the machine when it is electric but the config names a fuel", function()
      _G.prototypes = fake_prototypes{
        machines = {["stone-furnace"] = a_machine{crafting_speed = 1, size = 2}},
        recipes = {["iron-plate"] = plate},
      }

      local result, error_message = generator.generate("iron-plate", 50)

      assert.is_nil(result)
      assert.are.same({"blueprint-generation.error-fuel-mismatch", {"entity-name.stone-furnace"}}, error_message)
    end)

    it("refuses the machine when it burns fuel but the config names none", function()
      _G.prototypes = fake_prototypes{
        machines = {["assembling-machine-1"] = a_machine{crafting_speed = 0.5, size = 3, burns = {"chemical"}}},
        recipes = {["iron-gear-wheel"] = gear},
      }

      local result, error_message = generator.generate("iron-gear-wheel", 60)

      assert.is_nil(result)
      assert.are.same({"blueprint-generation.error-fuel-mismatch", {"entity-name.assembling-machine-1"}}, error_message)
    end)

    it("refuses the machine when its energy source is neither electric nor burner", function()
      _G.prototypes = fake_prototypes{
        machines = {["assembling-machine-1"] = a_machine{crafting_speed = 0.5, size = 3, heat = true}},
        recipes = {["iron-gear-wheel"] = gear},
      }

      local result, error_message = generator.generate("iron-gear-wheel", 60)

      assert.is_nil(result)
      assert.are.same({"blueprint-generation.error-unsupported-energy"}, error_message)
    end)
  end)

  describe("a recipe made from an item that is itself made, so the chain starts at the raw items", function()
    -- An assembler (speed 0.5, 3x3) crafts a gear in 0.5 s from 2 plates, so at full speed it makes
    -- 60 gears a minute and eats 120 plates. Its two input inserters move 100.8 plates a minute (50.4 each),
    -- so it really makes 50.4 gears from 100.8 plates. A furnace makes 18.75 plates a minute from 3.2 s.
    local plate = a_recipe{energy = 3.2, ingredients = {amount_of(1, "iron-ore")}, products = {amount_of(1, "iron-plate")}, category = "smelting"}
    local gear = a_recipe{energy = 0.5, ingredients = {amount_of(2, "iron-plate")}, products = {amount_of(1, "iron-gear-wheel")}}
    local assembler = a_machine{crafting_speed = 0.5, size = 3}

    local function gear_game(overrides)
      local options = {
        furnace_speed = 1,
        machines = {["assembling-machine-1"] = assembler},
        recipes = {["iron-plate"] = plate, ["iron-gear-wheel"] = gear},
      }
      for key, value in pairs(overrides or {}) do
        options[key] = value
      end
      return fake_prototypes(options)
    end

    it("builds the machines of every step, enough furnaces to feed the assemblers", function()
      _G.prototypes = gear_game()

      local result = generator.generate("iron-gear-wheel", 50)

      assert.are.equal(1, count_named(result.entities, "assembling-machine-1")) -- 50 / 50.4
      assert.are.equal(6, count_named(result.entities, "stone-furnace")) -- 100.8 plates / 18.75 = 5.4
    end)

    it("sets the recipe of the assembling machines in a chain", function()
      _G.prototypes = gear_game()

      local result = generator.generate("iron-gear-wheel", 50)

      local assembler
      for _, entity in ipairs(result.entities) do
        if entity.name == "assembling-machine-1" then
          assembler = entity
        end
      end
      assert.are.equal("iron-gear-wheel", assembler.recipe)
    end)

    it("sets the name of the recipe, which need not be the name of what it makes", function()
      local pipe_recipe = a_recipe{energy = 0.5, ingredients = {amount_of(1, "iron-plate")}, products = {amount_of(1, "pipe")}}
      _G.prototypes = gear_game{recipes = {["iron-plate"] = plate, ["pipe-from-plates"] = pipe_recipe}}

      local result = generator.generate("pipe", 10)

      local assembler
      for _, entity in ipairs(result.entities) do
        if entity.name == "assembling-machine-1" then
          assembler = entity
        end
      end
      assert.are.equal("pipe-from-plates", assembler.recipe)
    end)

    it("builds one furnace for one gear a minute, since two plates are all it takes", function()
      _G.prototypes = gear_game()

      local result = generator.generate("iron-gear-wheel", 1)

      assert.are.equal(1, count_named(result.entities, "stone-furnace"))
      assert.are.equal(1, count_named(result.entities, "assembling-machine-1"))
    end)

    it("puts the furnaces on the left of the assemblers", function()
      _G.prototypes = gear_game()

      local result = generator.generate("iron-gear-wheel", 100)

      local last_furnace_x, first_assembler_x = -math.huge, math.huge
      for _, entity in ipairs(result.entities) do
        if entity.name == "stone-furnace" then
          last_furnace_x = math.max(last_furnace_x, entity.position.x)
        elseif entity.name == "assembling-machine-1" then
          first_assembler_x = math.min(first_assembler_x, entity.position.x)
        end
      end
      assert.is_true(last_furnace_x < first_assembler_x)
    end)

    it("builds with the buildings of both machines and the shared ones", function()
      _G.prototypes = gear_game()

      local result = generator.generate("iron-gear-wheel", 50)

      assert.are.same(
        {"assembling-machine-1", "inserter", "small-electric-pole", "stone-furnace", "transport-belt"},
        distinct_names_of(result.entities))
    end)

    it("builds a blueprint that passes the validator, with every machine fed, emptied and powered", function()
      _G.prototypes = gear_game()
      local catalog = builders.a_catalog{machine_size = 2, machine_needs_power = false}
      catalog["assembling-machine-1"] = {kind = "machine", width = 3, height = 3, needs_power = true}

      local result = generator.generate("iron-gear-wheel", 100)

      assert.are.same({}, validator.validate(result.entities, catalog))
    end)

    it("describes the blueprint with the machines of each step, from the raw items to the product", function()
      _G.prototypes = gear_game()

      local result = generator.generate("iron-gear-wheel", 100)

      assert.are.equal("iron-gear-wheel: 100.8 per minute from 11 x stone-furnace, 2 x assembling-machine-1", result.description)
    end)

    it("counts what the gears need of the ore and not what the furnaces could use", function()
      _G.prototypes = gear_game()

      local result = generator.generate("iron-gear-wheel", 100)

      -- 100.8 gears need 201.6 plates and so 201.6 ore, although the 11 furnaces could make 206.25 plates. They work
      -- 201.6 x 3.2 / 60 = 10.752 furnaces' worth of the time, burning 1.35 coal a minute each: 14.5152.
      assert.are.same(ready_message("iron-gear-wheel", "100.8", {{"iron-ore", "201.6"}, {"coal", "14.52"}}), result.message)
    end)

    it("limits the rate by the one lane that carries the plates to the assemblers", function()
      _G.prototypes = gear_game()

      local result, error_message = generator.generate("iron-gear-wheel", 250)

      assert.is_nil(result)
      -- a lane carries 450 plates a minute, enough for 4.46 assemblers' worth of 100.8, which make 4.46 x 50.4 gears
      assert.are.same({"blueprint-generation.error-rate-too-high", "225"}, error_message)
    end)

    it("builds an assembler for the part of an assembler that the plate lane can still feed", function()
      _G.prototypes = gear_game()

      local result = generator.generate("iron-gear-wheel", 225)

      assert.are.equal(5, count_named(result.entities, "assembling-machine-1")) -- the lane holds 4.46 assemblers' worth of plates
      assert.are.equal(24, count_named(result.entities, "stone-furnace")) -- 450 plates / 18.75; five assemblers at full speed would eat 504
    end)

    it("limits the rate by the belt speed of the plate lane when the belt is slower", function()
      _G.prototypes = gear_game{belt_speed = 0.015625} -- half the speed: a lane carries 225 plates a minute

      local result, error_message = generator.generate("iron-gear-wheel", 120)

      assert.is_nil(result)
      assert.are.same({"blueprint-generation.error-rate-too-high", "112.5"}, error_message) -- 225 plates / 100.8 = 2.23 assemblers' worth x 50.4
    end)

    it("makes a recipe in the machine of a later category when the config names no machine for its first", function()
      local plate_in_two_categories = a_recipe{
        energy = 3.2, ingredients = {amount_of(1, "iron-ore")}, products = {amount_of(1, "iron-plate")},
        categories = {"crushing", "smelting"},
      }
      _G.prototypes = fake_prototypes{recipes = {["iron-plate"] = plate_in_two_categories}}

      local result = generator.generate("iron-plate", 50)

      assert.are.equal(3, count_named(result.entities, "stone-furnace")) -- 50 / 18.75 = 2.67, rounded up
    end)

    it("treats an ingredient as raw when only machines the config does not name make it", function()
      local crushing = a_recipe{energy = 1, ingredients = {amount_of(1, "asteroid-chunk")}, products = {amount_of(1, "iron-ore")}, category = "crushing"}
      _G.prototypes = gear_game{recipes = {["iron-plate"] = plate, ["ore-from-asteroids"] = crushing}}

      local result = generator.generate("iron-plate", 50)

      assert.are.equal(3, count_named(result.entities, "stone-furnace"))
    end)
  end)

  describe("a chain whose last step makes more than it eats, so its output belt winds", function()
    -- An assembler (speed 0.5, 3x3) crafts in 0.5 s from 1 plate to 2 cables, so at full speed it eats 60 plates and
    -- makes 120 cables a minute. Its one input inserter moves 50.4 plates, so it really makes 100.8 cables, which
    -- takes two output inserters (50.4 each). A furnace makes 18.75 plates a minute.
    local plate = a_recipe{energy = 3.2, ingredients = {amount_of(1, "copper-ore")}, products = {amount_of(1, "copper-plate")}, category = "smelting"}
    local cable = a_recipe{energy = 0.5, ingredients = {amount_of(1, "copper-plate")}, products = {amount_of(2, "copper-cable")}}
    local assembler = a_machine{crafting_speed = 0.5, size = 3}

    local function cable_game()
      return fake_prototypes{
        furnace_speed = 1,
        machines = {["assembling-machine-1"] = assembler},
        recipes = {["copper-plate"] = plate, ["copper-cable"] = cable},
      }
    end

    it("builds the machines of both steps, with enough furnaces for the plates the assemblers take", function()
      _G.prototypes = cable_game()

      local result = generator.generate("copper-cable", 100)

      assert.are.equal(1, count_named(result.entities, "assembling-machine-1")) -- 100 / 100.8
      assert.are.equal(3, count_named(result.entities, "stone-furnace")) -- 50.4 plates / 18.75 = 2.69
    end)

    it("gives each assembler two output inserters and one input inserter", function()
      _G.prototypes = cable_game()

      local result = generator.generate("copper-cable", 100)

      -- 3 furnaces with an input and an output inserter each, and the assembler's one input and two output inserters
      assert.are.equal(9, count_named(result.entities, "inserter"))
    end)

    it("gives a single assembler one output inserter when its share of the work needs no more, so the belt does not wind", function()
      _G.prototypes = cable_game()

      local result = generator.generate("copper-cable", 1)

      -- a furnace's input and output inserter, the assembler's one input and one output inserter
      assert.are.equal(4, count_named(result.entities, "inserter"))
    end)

    it("builds a blueprint that passes the validator, with every machine fed, emptied and powered", function()
      _G.prototypes = cable_game()
      local catalog = builders.a_catalog{machine_size = 2, machine_needs_power = false}
      catalog["assembling-machine-1"] = {kind = "machine", width = 3, height = 3, needs_power = true}

      local result = generator.generate("copper-cable", 300)

      assert.are.same({}, validator.validate(result.entities, catalog))
    end)

    it("allows the rate when the plate lane and the two cable lanes are exactly full", function()
      _G.prototypes = cable_game()

      local result = generator.generate("copper-cable", 900)

      assert.are.equal(24, count_named(result.entities, "stone-furnace")) -- 450 plates / 18.75
      assert.are.equal(9, count_named(result.entities, "assembling-machine-1")) -- 450 / 50.4 = 8.93 assemblers' worth
    end)

    it("refuses the rate when both lanes are full, naming the most", function()
      _G.prototypes = cable_game()

      local result, error_message = generator.generate("copper-cable", 901)

      assert.is_nil(result)
      assert.are.same({"blueprint-generation.error-rate-too-high", "900"}, error_message)
    end)
  end)

  describe("a recipe with two made ingredients, so the blueprint is a tree of blocks", function()
    -- A furnace makes 18.75 plates a minute (speed 1, 3.2 s). An assembler (speed 0.5, 3x3) crafts every 1 s:
    -- cables, 1 plate to 2 cables, with one input and two output inserters, make 100.8 cables a minute from
    -- 50.4 plates; circuits, 1 plate and 3 cables to 1 circuit, with two input inserters moving 100.8 items,
    -- make 25.2 circuits a minute. A lane carries 450 cables, so at most 150 circuits a minute.
    local iron_plate = a_recipe{energy = 3.2, ingredients = {amount_of(1, "iron-ore")}, products = {amount_of(1, "iron-plate")}, category = "smelting"}
    local copper_plate = a_recipe{energy = 3.2, ingredients = {amount_of(1, "copper-ore")}, products = {amount_of(1, "copper-plate")}, category = "smelting"}
    local cable = a_recipe{energy = 0.5, ingredients = {amount_of(1, "copper-plate")}, products = {amount_of(2, "copper-cable")}}
    local circuit = a_recipe{
      energy = 0.5, ingredients = {amount_of(1, "iron-plate"), amount_of(3, "copper-cable")},
      products = {amount_of(1, "electronic-circuit")},
    }

    local function circuit_game(recipes)
      return fake_prototypes{
        furnace_speed = 1,
        machines = {["assembling-machine-1"] = a_machine{crafting_speed = 0.5, size = 3}},
        recipes = recipes or {
          ["iron-plate"] = iron_plate, ["copper-plate"] = copper_plate,
          ["copper-cable"] = cable, ["electronic-circuit"] = circuit,
        },
      }
    end

    it("builds the machines of every step, furnaces for both plates and assemblers for the cables and the circuits", function()
      _G.prototypes = circuit_game()

      local result = generator.generate("electronic-circuit", 50)

      assert.are.equal(7, count_named(result.entities, "stone-furnace")) -- 50 plates / 18.75 = 2.67, and 75 plates for the cables / 18.75 = 4
      assert.are.equal(4, count_named(result.entities, "assembling-machine-1")) -- 150 cables / 100.8 = 1.49, and 50 circuits / 25.2 = 1.98
    end)

    it("describes the blueprint with the machines of every step, each after the steps that feed it", function()
      _G.prototypes = circuit_game()

      local result = generator.generate("electronic-circuit", 50)

      assert.are.equal(
        "electronic-circuit: 50 per minute from 3 x stone-furnace, 4 x stone-furnace, 2 x assembling-machine-1, 2 x assembling-machine-1",
        result.description)
    end)

    it("adds up what each branch needs, the ores in the order of the recipe and the fuel after them", function()
      _G.prototypes = circuit_game()

      local result = generator.generate("electronic-circuit", 50)

      -- 50 circuits: 50 plates (50 iron ore, 2.667 furnaces' worth of crafting: 3.6 coal), and 150 cables from 75 copper
      -- plates (75 copper ore, 4 furnaces' worth: 5.4 coal)
      assert.are.same(ready_message("electronic-circuit", "50", {{"iron-ore", "50"}, {"copper-ore", "75"}, {"coal", "9"}}), result.message)
    end)

    it("builds a blueprint that passes the validator, with every machine fed, emptied and powered", function()
      _G.prototypes = circuit_game()
      local catalog = builders.a_catalog{machine_size = 2, machine_needs_power = false}
      catalog["assembling-machine-1"] = {kind = "machine", width = 3, height = 3, needs_power = true}

      local result = generator.generate("electronic-circuit", 100)

      assert.are.same({}, validator.validate(result.entities, catalog))
    end)

    it("sets the recipe of every assembling machine and leaves the furnaces to pick their own", function()
      _G.prototypes = circuit_game()

      local result = generator.generate("electronic-circuit", 50)

      local recipes = {}
      for _, entity in ipairs(result.entities) do
        recipes[entity.name] = recipes[entity.name] or {}
        recipes[entity.name][#recipes[entity.name] + 1] = entity.recipe or "none"
      end
      table.sort(recipes["assembling-machine-1"])
      assert.are.same({"none", "none", "none", "none", "none", "none", "none"}, recipes["stone-furnace"]) -- 3 + 4 furnaces
      assert.are.same({"copper-cable", "copper-cable", "electronic-circuit", "electronic-circuit"}, recipes["assembling-machine-1"])
    end)

    it("allows the rate when the lane of cables is exactly full", function()
      _G.prototypes = circuit_game()

      local result = generator.generate("electronic-circuit", 150)

      assert.are.equal(20, count_named(result.entities, "stone-furnace")) -- 150 plates / 18.75 = 8, and 225 plates for the cables / 18.75 = 12
      assert.are.equal(11, count_named(result.entities, "assembling-machine-1")) -- 450 cables / 100.8 = 4.46, and 150 circuits / 25.2 = 5.95
    end)

    it("refuses the rate when the lane of cables cannot carry it, naming the most", function()
      _G.prototypes = circuit_game()

      local result, error_message = generator.generate("electronic-circuit", 151)

      assert.is_nil(result)
      assert.are.same({"blueprint-generation.error-rate-too-high", "150"}, error_message)
    end)

    it("names the most under the rate field", function()
      _G.prototypes = circuit_game()

      assert.are.same({"blueprint-generation.max-rate", "150"}, generator.max_rate_message("electronic-circuit"))
    end)

    it("refuses the request when a step with made ingredients burns fuel, naming the item", function()
      local circuit_in_a_furnace = a_recipe{
        energy = 0.5, ingredients = {amount_of(1, "iron-plate"), amount_of(3, "copper-cable")},
        products = {amount_of(1, "electronic-circuit")}, category = "smelting",
      }
      _G.prototypes = circuit_game{
        ["iron-plate"] = iron_plate, ["copper-plate"] = copper_plate,
        ["copper-cable"] = cable, ["electronic-circuit"] = circuit_in_a_furnace,
      }

      local result, error_message = generator.generate("electronic-circuit", 10)

      assert.is_nil(result)
      assert.are.same({"blueprint-generation.error-chain-fuel", {"item-name.electronic-circuit"}}, error_message)
    end)

    it("refuses the request when a step has one made ingredient that is itself made from two, naming the item", function()
      local gear_of_a_circuit = a_recipe{energy = 0.5, ingredients = {amount_of(1, "electronic-circuit")}, products = {amount_of(1, "iron-gear-wheel")}}
      _G.prototypes = circuit_game{
        ["iron-plate"] = iron_plate, ["copper-plate"] = copper_plate, ["copper-cable"] = cable,
        ["electronic-circuit"] = circuit, ["iron-gear-wheel"] = gear_of_a_circuit,
      }

      local result, error_message = generator.generate("iron-gear-wheel", 10)

      assert.is_nil(result)
      assert.are.same({"blueprint-generation.error-chain-too-complex", {"item-name.iron-gear-wheel"}}, error_message)
    end)
  end)

  describe("a recipe with one made ingredient and a raw one, so the raw item rides a belt of its own", function()
    -- A furnace makes 18.75 plates a minute (speed 1, 3.2 s). An assembler (speed 0.5, 3x3) crafts every 0.5 s:
    -- cables, 1 plate to 2 cables, make 100.8 cables a minute with two output inserters; poles, 1 wood and
    -- 2 cables to 2 poles, would eat 60 wood and 120 cables a minute, but two input inserters move only
    -- 100.8 items, so they make 67.2 poles a minute. A lane carries 450 cables, so at most 450 poles a minute.
    local copper_plate = a_recipe{energy = 3.2, ingredients = {amount_of(1, "copper-ore")}, products = {amount_of(1, "copper-plate")}, category = "smelting"}
    local cable = a_recipe{energy = 0.5, ingredients = {amount_of(1, "copper-plate")}, products = {amount_of(2, "copper-cable")}}
    local pole = a_recipe{
      energy = 0.5, ingredients = {amount_of(1, "wood"), amount_of(2, "copper-cable")},
      products = {amount_of(2, "small-electric-pole")},
    }

    local function pole_game()
      return fake_prototypes{
        furnace_speed = 1,
        machines = {["assembling-machine-1"] = a_machine{crafting_speed = 0.5, size = 3}},
        recipes = {["copper-plate"] = copper_plate, ["copper-cable"] = cable, ["small-electric-pole"] = pole},
      }
    end

    it("builds the machines of the made ingredient and of the final step, and none for the raw item", function()
      _G.prototypes = pole_game()

      local result = generator.generate("small-electric-pole", 100)

      assert.are.equal(3, count_named(result.entities, "stone-furnace")) -- 50 plates for 100 cables / 18.75 = 2.67
      assert.are.equal(3, count_named(result.entities, "assembling-machine-1")) -- 100 cables / 100.8 = 1 cable assembler, 100 poles / 67.2 = 1.49 pole assemblers
    end)

    it("describes the blueprint with the machines of every step and says nothing of the raw item", function()
      _G.prototypes = pole_game()

      local result = generator.generate("small-electric-pole", 100)

      assert.are.equal(
        "small-electric-pole: 100.8 per minute from 3 x stone-furnace, 1 x assembling-machine-1, 2 x assembling-machine-1",
        result.description)
    end)

    it("counts a raw item that goes with a made one like any other raw item", function()
      _G.prototypes = pole_game()

      local result = generator.generate("small-electric-pole", 60)

      -- 67.2 poles come from 33.6 crafts of 1 wood and 2 cables: 33.6 wood, 67.2 cables from 33.6 copper plates, so 33.6
      -- ore, and 33.6 x 3.2 / 60 = 1.792 furnaces' worth of crafting: 2.4192 coal
      assert.are.same(ready_message("small-electric-pole", "67.2", {{"copper-ore", "33.6"}, {"wood", "33.6"}, {"coal", "2.42"}}), result.message)
    end)

    it("sets the recipe of every assembling machine and leaves the furnaces to pick their own", function()
      _G.prototypes = pole_game()

      local result = generator.generate("small-electric-pole", 100)

      local recipes = {}
      for _, entity in ipairs(result.entities) do
        recipes[entity.name] = recipes[entity.name] or {}
        recipes[entity.name][#recipes[entity.name] + 1] = entity.recipe or "none"
      end
      table.sort(recipes["assembling-machine-1"])
      assert.are.same({"none", "none", "none"}, recipes["stone-furnace"])
      assert.are.same({"copper-cable", "small-electric-pole", "small-electric-pole"}, recipes["assembling-machine-1"])
    end)

    it("builds a blueprint that passes the validator, with every machine fed, emptied and powered", function()
      _G.prototypes = pole_game()
      local catalog = builders.a_catalog{machine_size = 2, machine_needs_power = false}
      catalog["assembling-machine-1"] = {kind = "machine", width = 3, height = 3, needs_power = true}

      local result = generator.generate("small-electric-pole", 100)

      assert.are.same({}, validator.validate(result.entities, catalog))
    end)

    it("allows the rate when the lane of cables is exactly full", function()
      _G.prototypes = pole_game()

      local result = generator.generate("small-electric-pole", 450)

      assert.is_not_nil(result)
    end)

    it("refuses the rate when the lane of cables is over full, naming the most", function()
      _G.prototypes = pole_game()

      local result, error_message = generator.generate("small-electric-pole", 451)

      assert.is_nil(result)
      assert.are.same({"blueprint-generation.error-rate-too-high", "450"}, error_message)
    end)

    it("refuses the recipe when the step with the raw item burns fuel", function()
      local pole_in_a_furnace = a_recipe{
        energy = 0.5, ingredients = {amount_of(1, "wood"), amount_of(2, "copper-cable")},
        products = {amount_of(2, "small-electric-pole")}, category = "smelting",
      }
      _G.prototypes = fake_prototypes{
        furnace_speed = 1,
        machines = {["assembling-machine-1"] = a_machine{crafting_speed = 0.5, size = 3}},
        recipes = {["copper-plate"] = copper_plate, ["copper-cable"] = cable, ["small-electric-pole"] = pole_in_a_furnace},
      }

      local result, error_message = generator.generate("small-electric-pole", 10)

      assert.is_nil(result)
      assert.are.same({"blueprint-generation.error-chain-fuel", {"item-name.small-electric-pole"}}, error_message)
    end)
  end)

  describe("a recipe with three made ingredients, so the final machines take from a second input belt", function()
    -- A furnace makes 18.75 plates a minute (speed 1, 3.2 s), or 18.75 bricks from 2 stone each. An assembler (speed 0.5,
    -- 3x3) crafts every 1 s. Gears, 2 plates each, would eat 120 plates a minute, but the two plain inserters of a gear
    -- assembler move 100.8: 50.4 gears a minute. "Inserters" (the recipe is a stand-in) take a gear, a brick and a plate each,
    -- 60 of each a minute at full speed; a plain inserter moves 50.4 items a minute, a long-handed one 72, and a machine has
    -- two input slots. The gear alone on belt a (50.4 / 60 = 0.84), the brick and the plate on belt b (72 / 120 = 0.6): 0.6,
    -- so 36 inserters a minute for each final assembler.
    local plate = a_recipe{energy = 3.2, ingredients = {amount_of(1, "iron-ore")}, products = {amount_of(1, "iron-plate")}, category = "smelting"}
    local brick = a_recipe{energy = 3.2, ingredients = {amount_of(2, "stone")}, products = {amount_of(1, "stone-brick")}, category = "smelting"}
    local gear = a_recipe{energy = 0.5, ingredients = {amount_of(2, "iron-plate")}, products = {amount_of(1, "iron-gear-wheel")}}
    local inserter = a_recipe{
      energy = 0.5, ingredients = {amount_of(1, "iron-gear-wheel"), amount_of(1, "stone-brick"), amount_of(1, "iron-plate")},
      products = {amount_of(1, "inserter")},
    }

    local function inserter_game(extra)
      extra = extra or {}
      return fake_prototypes{
        furnace_speed = 1,
        machines = {["assembling-machine-1"] = a_machine{crafting_speed = 0.5, size = 3}},
        recipes = {["iron-plate"] = plate, ["stone-brick"] = brick, ["iron-gear-wheel"] = gear, ["inserter"] = inserter},
        missing_entities = extra.missing_entities,
        long_inserter_rotation_speed = extra.long_inserter_rotation_speed,
      }
    end

    it("builds the machines of every step: furnaces for the plates of the gears, the bricks and the plates, assemblers for the gears and the inserters", function()
      _G.prototypes = inserter_game()

      local result = generator.generate("inserter", 36)

      assert.are.equal(8, count_named(result.entities, "stone-furnace")) -- 72 plates for 36 gears / 18.75 = 3.8, 36 bricks / 18.75 = 1.9, 36 plates / 18.75 = 1.9
      assert.are.equal(2, count_named(result.entities, "assembling-machine-1")) -- one for the gears, one for the inserters
    end)

    it("gives each final assembler a long-handed inserter, and builds one for each 36 a minute", function()
      _G.prototypes = inserter_game()

      local result = generator.generate("inserter", 100)

      assert.are.equal(3, count_named(result.entities, "long-handed-inserter")) -- 100 / 36 = 2.8 final assemblers
    end)

    it("describes the blueprint with the machines of every step, each after the steps that feed it", function()
      _G.prototypes = inserter_game()

      local result = generator.generate("inserter", 36)

      assert.are.equal(
        "inserter: 36 per minute from 4 x stone-furnace, 1 x assembling-machine-1, 2 x stone-furnace, 2 x stone-furnace, 1 x assembling-machine-1",
        result.description)
    end)

    it("adds up the same raw item used by two branches, and the fuel of every furnace", function()
      _G.prototypes = inserter_game()

      local result = generator.generate("inserter", 36)

      -- 36 inserters: 36 gears (72 plates), 36 bricks (72 stone) and 36 plates, so 72 + 36 iron ore and 72 stone.
      -- The furnaces craft 3.2 s for each: 72 + 36 plates and 36 bricks are 3.84 + 1.92 + 1.92 furnaces' worth: 10.368 coal.
      assert.are.same(ready_message("inserter", "36", {{"iron-ore", "108"}, {"stone", "72"}, {"coal", "10.37"}}), result.message)
    end)

    it("sets the recipe of every assembling machine and leaves the furnaces to pick their own", function()
      _G.prototypes = inserter_game()

      local result = generator.generate("inserter", 36)

      local recipes = {}
      for _, entity in ipairs(result.entities) do
        recipes[entity.name] = recipes[entity.name] or {}
        recipes[entity.name][#recipes[entity.name] + 1] = entity.recipe or "none"
      end
      table.sort(recipes["assembling-machine-1"])
      assert.are.same({"inserter", "iron-gear-wheel"}, recipes["assembling-machine-1"])
      assert.are.equal(8, #recipes["stone-furnace"])
      assert.are.equal("none", recipes["stone-furnace"][1])
    end)

    it("builds a blueprint that passes the validator, with every machine fed, emptied and powered", function()
      _G.prototypes = inserter_game()
      local catalog = builders.a_catalog{machine_size = 2, machine_needs_power = false}
      catalog["assembling-machine-1"] = {kind = "machine", width = 3, height = 3, needs_power = true}

      local result = generator.generate("inserter", 100)

      assert.are.same({}, validator.validate(result.entities, catalog))
    end)

    it("names the most a lane carries when the lane of plates for the gears fills first", function()
      _G.prototypes = inserter_game()

      assert.are.same({"blueprint-generation.max-rate", "225"}, generator.max_rate_message("inserter")) -- 450 plates, 2 for each gear
    end)

    it("refuses the rate when it is more than that", function()
      _G.prototypes = inserter_game()

      local result, error_message = generator.generate("inserter", 226)

      assert.is_nil(result)
      assert.are.same({"blueprint-generation.error-rate-too-high", "225"}, error_message)
    end)

    it("takes the long-handed inserter's speed from the game", function()
      -- At the plain inserter's speed (0.014) the belt b side is 50.4 / 120 = 0.42 too: 25.2 a minute, 100 / 25.2 = 3.97.
      _G.prototypes = inserter_game{long_inserter_rotation_speed = 0.014}

      local result = generator.generate("inserter", 100)

      assert.are.equal(4, count_named(result.entities, "long-handed-inserter"))
    end)

    it("plans with the plain inserter's speed when the game has no long-handed inserter, and refuses nothing", function()
      _G.prototypes = inserter_game{missing_entities = {"long-handed-inserter"}}

      local result = generator.generate("inserter", 100)

      assert.are.equal(4, count_named(result.entities, "long-handed-inserter")) -- the blueprint still has them, as 25.2 a minute machines
    end)

    it("builds a recipe with one input belt when the game has no long-handed inserter", function()
      _G.prototypes = inserter_game{missing_entities = {"long-handed-inserter"}}

      local result = generator.generate("iron-gear-wheel", 10)

      assert.is_not_nil(result)
      assert.are.equal(0, count_named(result.entities, "long-handed-inserter"))
    end)
  end)

  describe("the most one blueprint can make, shown under the rate field", function()
    local plate = a_recipe{energy = 3.2, ingredients = {amount_of(1, "iron-ore")}, products = {amount_of(1, "iron-plate")}, category = "smelting"}
    local gear = a_recipe{energy = 0.5, ingredients = {amount_of(2, "iron-plate")}, products = {amount_of(1, "iron-gear-wheel")}}

    it("names the most a lane carries when the item is made in one step", function()
      _G.prototypes = fake_prototypes{furnace_speed = 1, recipes = {["iron-plate"] = plate}}

      assert.are.same({"blueprint-generation.max-rate", "450"}, generator.max_rate_message("iron-plate"))
    end)

    it("names the number a refused rate names, for a chain", function()
      _G.prototypes = fake_prototypes{
        furnace_speed = 1,
        machines = {["assembling-machine-1"] = a_machine{crafting_speed = 0.5, size = 3}},
        recipes = {["iron-plate"] = plate, ["iron-gear-wheel"] = gear},
      }

      local _, refusal = generator.generate("iron-gear-wheel", 1000)

      assert.are.same({"blueprint-generation.max-rate", refusal[2]}, generator.max_rate_message("iron-gear-wheel"))
      assert.are.equal("225", refusal[2])
    end)

    it("follows the belt speed of the game", function()
      _G.prototypes = fake_prototypes{belt_speed = 0.03125, furnace_speed = 1, recipes = {["iron-plate"] = plate}}
      local slow = generator.max_rate_message("iron-plate")
      _G.prototypes = fake_prototypes{belt_speed = 0.0625, furnace_speed = 1, recipes = {["iron-plate"] = plate}}
      local fast = generator.max_rate_message("iron-plate")

      assert.are.same({"blueprint-generation.max-rate", "450"}, slow)
      assert.are.same({"blueprint-generation.max-rate", "900"}, fast)
    end)

    it("gives the message of the refusal when the item cannot be made", function()
      _G.prototypes = fake_prototypes{recipes = {}}

      assert.are.same({"blueprint-generation.error-unsupported-item"}, generator.max_rate_message("advanced-circuit"))
      assert.are.same({"blueprint-generation.error-no-recipe", "iron-plate"}, generator.max_rate_message("iron-plate"))
    end)

    it("gives the message of the refusal when a machine cannot be built", function()
      _G.prototypes = fake_prototypes{
        furnace_speed = 1,
        machines = {["assembling-machine-1"] = a_machine{crafting_speed = 0.5, size = 4}},
        recipes = {["iron-plate"] = plate, ["iron-gear-wheel"] = gear},
      }

      local _, refusal = generator.generate("iron-gear-wheel", 10)

      assert.are.same(refusal, generator.max_rate_message("iron-gear-wheel"))
    end)
  end)

  describe("the belt between two steps, whatever the rate", function()
    -- The furnaces' column is much longer than the assemblers' for the plates it makes (a furnace column takes
    -- 2 rows for 18.75 plates a minute, an assembler 3 rows for 50 to 100), so the belt of plates runs north
    -- whether 1 or 900 are asked. The direction comes from the work each column does, not from how many
    -- machines the rate happens to round up to.
    local function plate_belt_directions(entities)
      local directions, seen = {}, {}
      for _, entity in ipairs(entities) do
        if entity.name == "transport-belt" and entity.position.x == 5.5 then
          if not seen[entity.direction] then
            seen[entity.direction] = true
            directions[#directions + 1] = entity.direction
          end
        end
      end
      return directions
    end

    local function game_of(ore, plate, product, plates_in, products_out, energy)
      return fake_prototypes{
        furnace_speed = 1,
        machines = {["assembling-machine-1"] = a_machine{crafting_speed = 0.5, size = 3}},
        recipes = {
          [plate] = a_recipe{energy = 3.2, ingredients = {amount_of(1, ore)}, products = {amount_of(1, plate)}, category = "smelting"},
          [product] = a_recipe{energy = energy, ingredients = {amount_of(plates_in, plate)}, products = {amount_of(products_out, product)}},
        },
      }
    end

    for _, rate in ipairs({1, 10, 100, 225}) do
      it("runs the plates north for gear wheels when " .. rate .. " are asked", function()
        _G.prototypes = game_of("iron-ore", "iron-plate", "iron-gear-wheel", 2, 1, 0.5)

        local result = generator.generate("iron-gear-wheel", rate)

        assert.are.same({defines.direction.north}, plate_belt_directions(result.entities))
      end)
    end

    for _, rate in ipairs({1, 10, 100, 900}) do
      it("runs the plates north for copper cables when " .. rate .. " are asked", function()
        _G.prototypes = game_of("copper-ore", "copper-plate", "copper-cable", 1, 2, 0.5)

        local result = generator.generate("copper-cable", rate)

        assert.are.same({defines.direction.north}, plate_belt_directions(result.entities))
      end)
    end

    for _, rate in ipairs({1, 10, 100}) do
      it("runs the plates south when the assemblers take more rows than the furnaces for the same plates and " .. rate .. " are asked", function()
        _G.prototypes = game_of("iron-ore", "iron-plate", "iron-gear-wheel", 1, 1, 5) -- an assembler eats only 6 plates a minute

        local result = generator.generate("iron-gear-wheel", rate)

        assert.are.same({defines.direction.south}, plate_belt_directions(result.entities))
      end)
    end
  end)

  describe("recipes the player has not unlocked", function()
    -- The same stand-in game as for three made ingredients: plates and bricks from furnaces, gears and inserters
    -- from assemblers, "inserter" taking three ingredients. Only the recipe of the product is looked at; the
    -- ingredients, the machines and the buildings are not (the game unlocks them first, or a later feature does).
    local plate = a_recipe{energy = 3.2, ingredients = {amount_of(1, "iron-ore")}, products = {amount_of(1, "iron-plate")}, category = "smelting"}
    local brick = a_recipe{energy = 3.2, ingredients = {amount_of(2, "stone")}, products = {amount_of(1, "stone-brick")}, category = "smelting"}
    local gear = a_recipe{energy = 0.5, ingredients = {amount_of(2, "iron-plate")}, products = {amount_of(1, "iron-gear-wheel")}}
    local inserter = a_recipe{
      energy = 0.5, ingredients = {amount_of(1, "iron-gear-wheel"), amount_of(1, "stone-brick"), amount_of(1, "iron-plate")},
      products = {amount_of(1, "inserter")},
    }

    local function game()
      return fake_prototypes{
        furnace_speed = 1,
        machines = {["assembling-machine-1"] = a_machine{crafting_speed = 0.5, size = 3}},
        recipes = {["iron-plate"] = plate, ["stone-brick"] = brick, ["iron-gear-wheel"] = gear, ["inserter"] = inserter},
      }
    end

    local function locked_message(item)
      return {"blueprint-generation.error-locked", {"item-name." .. item}}
    end

    it("builds the blueprint when the recipe of the item is unlocked", function()
      _G.prototypes = game()

      local result = generator.generate("inserter", 36, fake_force{})

      assert.is_not_nil(result)
    end)

    it("refuses the item when its own recipe is locked, naming the item", function()
      _G.prototypes = game()

      local result, message = generator.generate("inserter", 36, fake_force{locked = {"inserter"}})

      assert.is_nil(result)
      assert.are.same(locked_message("inserter"), message)
    end)

    it("does not look at the recipes of the ingredients made on the way, which the game unlocks first", function()
      _G.prototypes = game()

      local result = generator.generate("inserter", 36, fake_force{locked = {"iron-gear-wheel", "stone-brick", "iron-plate"}})

      assert.is_not_nil(result)
    end)

    it("does not look at the recipes of the crafting machines, which the game unlocks first", function()
      _G.prototypes = game()

      local result = generator.generate("inserter", 36, fake_force{locked = {"assembling-machine-1", "stone-furnace"}})

      assert.is_not_nil(result)
    end)

    it("does not look at the long-handed inserter, even for an item with three ingredients", function()
      _G.prototypes = game()

      local result = generator.generate("inserter", 36, fake_force{locked = {"long-handed-inserter"}})

      assert.is_not_nil(result)
    end)

    it("does not look at the belt, the inserter and the pole every blueprint places", function()
      _G.prototypes = game()

      local result = generator.generate("iron-plate", 10, fake_force{locked = {"transport-belt", "inserter", "small-electric-pole"}})

      assert.is_not_nil(result)
    end)

    it("does not hold a recipe against the player that the force does not know at all", function()
      _G.prototypes = game()

      local result = generator.generate("inserter", 36, fake_force{absent = {"inserter"}})

      assert.is_not_nil(result)
    end)

    it("shows the same message under the rate field for a locked item, and the rate for one that is not", function()
      _G.prototypes = game()
      local force = fake_force{locked = {"iron-gear-wheel", "medium-electric-pole"}} -- without the medium pole no step is built wide

      assert.are.same(locked_message("iron-gear-wheel"), generator.max_rate_message("iron-gear-wheel", force))
      assert.are.same({"blueprint-generation.max-rate", "450"}, generator.max_rate_message("iron-plate", force))
    end)

    it("leaves the recipes unchecked when no force is given", function()
      _G.prototypes = game()

      assert.is_not_nil(generator.generate("inserter", 36))
      assert.are.same({"blueprint-generation.max-rate", "225"}, generator.max_rate_message("inserter"))
    end)

    describe("the products on offer", function()
      local function contains(list, name)
        for _, entry in ipairs(list) do
          if entry == name then
            return true
          end
        end
        return false
      end

      it("lists the products whose recipes are unlocked", function()
        _G.prototypes = game()

        local offered = generator.unlocked_products(fake_force{})

        assert.is_true(contains(offered, "inserter"))
        assert.is_true(contains(offered, "iron-gear-wheel"))
        assert.is_true(contains(offered, "iron-plate"))
      end)

      it("leaves out the product whose own recipe is locked, and not the products made from it", function()
        _G.prototypes = game()

        local offered = generator.unlocked_products(fake_force{locked = {"iron-gear-wheel"}})

        assert.is_false(contains(offered, "iron-gear-wheel"))
        assert.is_true(contains(offered, "inserter")) -- its gears are not looked at
        assert.is_true(contains(offered, "iron-plate"))
        assert.is_true(contains(offered, "stone-brick"))
      end)

      it("keeps a product that cannot be made for another reason, so choosing it says why", function()
        _G.prototypes = game()

        local offered = generator.unlocked_products(fake_force{})

        assert.is_true(contains(offered, "pipe")) -- the game here has no recipe for it
      end)

      it("lists the names in order", function()
        _G.prototypes = game()

        local offered = generator.unlocked_products(fake_force{})

        local sorted = {table.unpack(offered)}
        table.sort(sorted)
        assert.are.same(sorted, offered)
      end)

      it("counts the recipes of the force it is given", function()
        _G.prototypes = game()

        local with_everything = generator.unlocked_products(fake_force{})
        local without_inserter = generator.unlocked_products(fake_force{locked = {"inserter"}})

        assert.are.equal(#with_everything - 1, #without_inserter)
        assert.is_false(contains(without_inserter, "inserter"))
        assert.is_true(contains(without_inserter, "iron-plate"))
      end)
    end)
  end)

  describe("the assembling machine 2, once the force has unlocked it", function()
    -- A recipe that takes 3 s a craft, so the machine's speed decides how many there are: 10 a minute from an
    -- assembling machine 1 (speed 0.5), 15 from an assembling machine 2 (0.75). One plate in, one pipe out,
    -- which the inserters keep up with in either.
    local plate = a_recipe{energy = 3.2, ingredients = {amount_of(1, "iron-ore")}, products = {amount_of(1, "iron-plate")}, category = "smelting"}
    local slow_pipe = a_recipe{energy = 3, ingredients = {amount_of(1, "iron-plate")}, products = {amount_of(1, "pipe")}}

    local function pipe_game(with_assembler_2)
      local machines = {["assembling-machine-1"] = a_machine{crafting_speed = 0.5, size = 3}}
      if with_assembler_2 then
        machines["assembling-machine-2"] = a_machine{crafting_speed = 0.75, size = 3}
      end
      return fake_prototypes{furnace_speed = 1, machines = machines, recipes = {["iron-plate"] = plate, ["pipe"] = slow_pipe}}
    end

    -- How many assembling machines 1 and 2 the blueprint has.
    local function assemblers(result)
      return {count_named(result.entities, "assembling-machine-1"), count_named(result.entities, "assembling-machine-2")}
    end

    it("builds with it, and with fewer machines than the assembling machine 1 takes", function()
      _G.prototypes = pipe_game(true)

      local result = generator.generate("pipe", 30, fake_force{})

      assert.are.same({0, 2}, assemblers(result))
    end)

    it("sets the recipe on it", function()
      _G.prototypes = pipe_game(true)

      local result = generator.generate("pipe", 30, fake_force{})

      local recipes = {}
      for _, entity in ipairs(result.entities) do
        if entity.name == "assembling-machine-2" then
          recipes[#recipes + 1] = entity.recipe
        end
      end
      assert.are.same({"pipe", "pipe"}, recipes)
    end)

    it("builds with the assembling machine 1 when the force has not unlocked it", function()
      _G.prototypes = pipe_game(true)

      local result = generator.generate("pipe", 30, fake_force{locked = {"assembling-machine-2"}})

      assert.are.same({3, 0}, assemblers(result))
    end)

    it("builds with the assembling machine 1 when the game has no assembling machine 2", function()
      _G.prototypes = pipe_game(false)

      local result = generator.generate("pipe", 30, fake_force{})

      assert.are.same({3, 0}, assemblers(result))
    end)

    it("builds with the assembling machine 1 when no force is given", function()
      _G.prototypes = pipe_game(true)

      local result = generator.generate("pipe", 30)

      assert.are.same({3, 0}, assemblers(result))
    end)

    it("builds a blueprint that passes the validator, with every machine fed, emptied and powered", function()
      _G.prototypes = pipe_game(true)
      local catalog = builders.a_catalog{machine_size = 2, machine_needs_power = false}
      catalog["assembling-machine-2"] = {kind = "machine", width = 3, height = 3, needs_power = true}

      local result = generator.generate("pipe", 30, fake_force{})

      assert.are.same({}, validator.validate(result.entities, catalog))
    end)

    it("builds the machines of the other steps the same, so the furnaces of the plates do not change", function()
      _G.prototypes = pipe_game(true)

      local with, without = generator.generate("pipe", 30, fake_force{}), generator.generate("pipe", 30, fake_force{locked = {"assembling-machine-2"}})

      assert.are.equal(count_named(without.entities, "stone-furnace"), count_named(with.entities, "stone-furnace"))
    end)
  end)

  describe("the design that brings in one belt of each material", function()
    -- Iron plates and copper cables to circuits, as above: two ores and the coal for the furnaces, so three belts come in
    -- and the blueprint has one splitter (the coal feeds both trunks) and four underground belts (the two ore feeders
    -- go under the coal). The design needs a force that has researched the splitter and the underground belt, and an
    -- underground belt that spans at least 3 tiles; without them the blueprint takes the original design.
    local iron_plate = a_recipe{energy = 3.2, ingredients = {amount_of(1, "iron-ore")}, products = {amount_of(1, "iron-plate")}, category = "smelting"}
    local copper_plate = a_recipe{energy = 3.2, ingredients = {amount_of(1, "copper-ore")}, products = {amount_of(1, "copper-plate")}, category = "smelting"}
    local cable = a_recipe{energy = 0.5, ingredients = {amount_of(1, "copper-plate")}, products = {amount_of(2, "copper-cable")}}
    local circuit = a_recipe{
      energy = 0.5, ingredients = {amount_of(1, "iron-plate"), amount_of(3, "copper-cable")},
      products = {amount_of(1, "electronic-circuit")},
    }

    local function circuit_game(options)
      options = options or {}
      return fake_prototypes{
        furnace_speed = 1,
        machines = {["assembling-machine-1"] = a_machine{crafting_speed = 0.5, size = 3}},
        recipes = {
          ["iron-plate"] = iron_plate, ["copper-plate"] = copper_plate,
          ["copper-cable"] = cable, ["electronic-circuit"] = circuit,
        },
        underground_distance = options.underground_distance,
        missing_entities = options.missing_entities,
        fast_belts = options.fast_belts,
        fast_underground_distance = options.fast_underground_distance,
      }
    end

    describe("with the fast belts, once the force has unlocked the fast belt, the fast splitter and the fast underground belt", function()
      local FAST = {"fast-transport-belt", "fast-splitter", "fast-underground-belt"}
      local BASIC = {"transport-belt", "splitter", "underground-belt"}

      -- How many of each of the belts, the splitters and the underground belts of the blueprint, by name.
      local function belts_by_name(result)
        local counts = {}
        for _, name in ipairs({"transport-belt", "splitter", "underground-belt", "fast-transport-belt", "fast-splitter", "fast-underground-belt"}) do
          counts[name] = count_named(result.entities, name)
        end
        return counts
      end

      it("builds it with the fast belt, splitter and underground belt, and none of the basic ones", function()
        _G.prototypes = circuit_game{fast_belts = true}

        local counts = belts_by_name(generator.generate("electronic-circuit", 50, fake_force{}))

        assert.are.same({0, 0, 0, true, 1, 4}, {counts["transport-belt"], counts["splitter"], counts["underground-belt"],
          counts["fast-transport-belt"] > 0, counts["fast-splitter"], counts["fast-underground-belt"]})
      end)

      for _, locked in ipairs({{"fast-transport-belt"}, {"fast-splitter"}, {"fast-underground-belt"}}) do
        it("builds it with the basic ones when the force has not unlocked the " .. locked[1], function()
          _G.prototypes = circuit_game{fast_belts = true}

          local counts = belts_by_name(generator.generate("electronic-circuit", 50, fake_force{locked = locked}))

          assert.are.same({0, 0, 0}, {counts["fast-transport-belt"], counts["fast-splitter"], counts["fast-underground-belt"]})
        end)

        it("builds it with the basic ones when the game has no " .. locked[1], function()
          _G.prototypes = circuit_game{fast_belts = true, missing_entities = locked}

          local counts = belts_by_name(generator.generate("electronic-circuit", 50, fake_force{}))

          assert.are.same({0, 0, 0}, {counts["fast-transport-belt"], counts["fast-splitter"], counts["fast-underground-belt"]})
        end)
      end

      it("builds it with the basic ones when no force is given", function()
        _G.prototypes = circuit_game{fast_belts = true}

        local counts = belts_by_name(generator.generate("electronic-circuit", 50))

        assert.are.same({0, 0, 0}, {counts["fast-transport-belt"], counts["fast-splitter"], counts["fast-underground-belt"]})
      end)

      it("makes up to twice as many: the lanes of the fast belt carry 900 a minute, where the basic belt's carry 450", function()
        _G.prototypes = circuit_game{fast_belts = true}

        assert.are.same({{"blueprint-generation.max-rate", "300"}, {"blueprint-generation.max-rate", "150"}},
          {generator.max_rate_message("electronic-circuit", fake_force{}), generator.max_rate_message("electronic-circuit", fake_force{locked = {"fast-splitter"}})})
      end)

      it("builds a blueprint that passes the validator at the rate only the fast belts make", function()
        _G.prototypes = circuit_game{fast_belts = true}
        local catalog = builders.a_catalog{machine_size = 2, machine_needs_power = false}
        catalog["assembling-machine-1"] = {kind = "machine", width = 3, height = 3, needs_power = true}

        local result = generator.generate("electronic-circuit", 300, fake_force{})

        assert.are.same({}, validator.validate(result.entities, catalog))
      end)

      it("refuses a rate above that, naming the most", function()
        _G.prototypes = circuit_game{fast_belts = true}

        local result, message = generator.generate("electronic-circuit", 301, fake_force{})

        assert.are.same({nil, {"blueprint-generation.error-rate-too-high", "300"}}, {result, message})
      end)

      it("builds it when the fast underground belt spans exactly the 3 tiles the hops need", function()
        _G.prototypes = circuit_game{fast_belts = true, fast_underground_distance = 3}

        local counts = belts_by_name(generator.generate("electronic-circuit", 50, fake_force{}))

        assert.are.equal(4, counts["fast-underground-belt"])
      end)
    end)

    it("builds it for a force that has researched the splitter and the underground belt", function()
      _G.prototypes = circuit_game()

      local result = generator.generate("electronic-circuit", 50, fake_force{})

      assert.are.equal(1, count_named(result.entities, "splitter"))
      assert.are.equal(4, count_named(result.entities, "underground-belt"))
    end)

    it("tells the player the items of the belts that come in, from the top of the blueprint down", function()
      _G.prototypes = circuit_game()

      local result = generator.generate("electronic-circuit", 50, fake_force{})

      assert.are.same(
        ready_message_with_belts("electronic-circuit", "50", {{"iron-ore", "50"}, {"copper-ore", "75"}, {"coal", "9"}}, {"coal", "copper-ore", "iron-ore"}),
        result.message)
    end)

    it("builds a blueprint that passes the validator, with every machine fed, emptied and powered", function()
      _G.prototypes = circuit_game()
      local catalog = builders.a_catalog{machine_size = 2, machine_needs_power = false}
      catalog["assembling-machine-1"] = {kind = "machine", width = 3, height = 3, needs_power = true}

      local result = generator.generate("electronic-circuit", 100, fake_force{})

      assert.are.same({}, validator.validate(result.entities, catalog))
    end)

    it("builds it when the underground belt spans exactly the 3 tiles the hops need", function()
      _G.prototypes = circuit_game{underground_distance = 3}

      local result = generator.generate("electronic-circuit", 50, fake_force{})

      assert.are.equal("blueprint-generation.generated-with-belts", result.message[1])
    end)

    local original_design = {
      {label = "the force has not researched the splitter", force = fake_force{locked = {"splitter"}}},
      {label = "the force has not researched the underground belt", force = fake_force{locked = {"underground-belt"}}},
      {label = "the force does not know the recipe of the splitter", force = fake_force{absent = {"splitter"}}},
      {label = "the force does not know the recipe of the underground belt", force = fake_force{absent = {"underground-belt"}}},
      {label = "no force is given, so nothing is known to be researched", force = nil},
      {label = "the game has no splitter", force = fake_force{}, game = {missing_entities = {"splitter"}}},
      {label = "the game has no underground belt", force = fake_force{}, game = {missing_entities = {"underground-belt"}}},
      {label = "the underground belt spans fewer than 3 tiles", force = fake_force{}, game = {underground_distance = 2}},
      {label = "the game does not say how far the underground belt spans", force = fake_force{}, game = {underground_distance = false}},
    }

    for _, case in ipairs(original_design) do
      it("takes the original design, with a belt of raw items for every chain, when " .. case.label, function()
        _G.prototypes = circuit_game(case.game)

        local result = generator.generate("electronic-circuit", 50, case.force)

        assert.are.same(ready_message("electronic-circuit", "50", {{"iron-ore", "50"}, {"copper-ore", "75"}, {"coal", "9"}}), result.message)
        assert.are.equal(0, count_named(result.entities, "splitter") + count_named(result.entities, "underground-belt"))
      end)
    end

    it("takes the original design for the line under the rate field too, which does not depend on the layout", function()
      _G.prototypes = circuit_game()

      assert.are.same({"blueprint-generation.max-rate", "150"}, generator.max_rate_message("electronic-circuit", fake_force{}))
    end)

    it("brings in one belt for a machine that eats only one raw item, which rides both lanes", function()
      local chest = a_recipe{energy = 0.5, ingredients = {amount_of(2, "wood")}, products = {amount_of(1, "wooden-chest")}}
      _G.prototypes = fake_prototypes{
        machines = {["assembling-machine-1"] = a_machine{crafting_speed = 0.5, size = 3}},
        recipes = {["wooden-chest"] = chest},
      }

      local result = generator.generate("wooden-chest", 30, fake_force{})

      assert.are.same({"blueprint-generation.generated-with-belts", {"", {"item-name.wood"}}}, {result.message[1], result.message[5]})
    end)

    it("brings in a raw item that goes with made ones on a belt of its own", function()
      local pole = a_recipe{energy = 0.5, ingredients = {amount_of(1, "wood"), amount_of(2, "copper-cable")}, products = {amount_of(2, "small-electric-pole")}}
      _G.prototypes = fake_prototypes{
        furnace_speed = 1,
        machines = {["assembling-machine-1"] = a_machine{crafting_speed = 0.5, size = 3}},
        recipes = {["copper-plate"] = copper_plate, ["copper-cable"] = cable, ["small-electric-pole"] = pole},
      }

      local result = generator.generate("small-electric-pole", 20, fake_force{})

      assert.are.same({
        "blueprint-generation.generated-with-belts",
        {"", {"item-name.wood"}, ", ", {"item-name.copper-ore"}, ", ", {"item-name.coal"}},
      }, {result.message[1], result.message[5]})
    end)
  end)

  describe("fast inserters, used for a side that one plain inserter cannot serve once the force has researched them", function()
    -- An assembler (speed 0.5, 3x3) makes 60 gears a minute and eats 120 plates: two plain inserters (100.8) would hold it
    -- back to about 50 gears, one fast inserter (144) does not. A furnace eats 18.75 ore a minute and keeps plain inserters.
    local plate = a_recipe{energy = 3.2, ingredients = {amount_of(1, "iron-ore")}, products = {amount_of(1, "iron-plate")}, category = "smelting"}
    local gear = a_recipe{energy = 0.5, ingredients = {amount_of(2, "iron-plate")}, products = {amount_of(1, "iron-gear-wheel")}}

    local function gear_game(options)
      options = options or {}
      return fake_prototypes{
        furnace_speed = 1,
        machines = {["assembling-machine-1"] = a_machine{crafting_speed = 0.5, size = 3}},
        recipes = {["iron-plate"] = plate, ["iron-gear-wheel"] = gear},
        missing_entities = options.missing_entities,
        fast_inserter_rotation_speed = options.fast_inserter_rotation_speed,
      }
    end

    it("puts a fast inserter on each side of an assembler that moves more than a plain inserter does", function()
      _G.prototypes = gear_game()

      local result = generator.generate("iron-gear-wheel", 60, fake_force{})

      assert.are.equal(2, count_named(result.entities, "fast-inserter")) -- one on each side of the one assembler
    end)

    it("keeps plain inserters for the furnaces, whose flow one plain inserter moves", function()
      _G.prototypes = gear_game()

      local result = generator.generate("iron-gear-wheel", 60, fake_force{})

      assert.are.equal(14, count_named(result.entities, "inserter")) -- 7 furnaces, an inserter on each side
    end)

    it("gives a side at most two inserters, even when a machine eats more than two fast inserters move", function()
      local heavy_gear = a_recipe{energy = 0.5, ingredients = {amount_of(5, "iron-plate")}, products = {amount_of(1, "iron-gear-wheel")}} -- 300 plates a minute
      _G.prototypes = fake_prototypes{
        furnace_speed = 1,
        machines = {["assembling-machine-1"] = a_machine{crafting_speed = 0.5, size = 3}},
        recipes = {["iron-plate"] = plate, ["iron-gear-wheel"] = heavy_gear},
      }

      local result = generator.generate("iron-gear-wheel", 57, fake_force{}) -- one assembler at nearly full speed: 57.6 gears a minute

      -- two fast inserters on the input side (288 of the 300 a minute) and one on the output side
      assert.are.same({1, 3}, {count_named(result.entities, "assembling-machine-1"), count_named(result.entities, "fast-inserter")})
    end)

    it("needs fewer assemblers, since each runs at full speed", function()
      _G.prototypes = gear_game()

      local fast = generator.generate("iron-gear-wheel", 60, fake_force{})
      local plain = generator.generate("iron-gear-wheel", 60)

      assert.are.same({1, 2}, {count_named(fast.entities, "assembling-machine-1"), count_named(plain.entities, "assembling-machine-1")})
    end)

    it("builds a blueprint that passes the validator, with every machine fed, emptied and powered", function()
      _G.prototypes = gear_game()
      local catalog = builders.a_catalog{machine_size = 2, machine_needs_power = false}
      catalog["assembling-machine-1"] = {kind = "machine", width = 3, height = 3, needs_power = true}

      local result = generator.generate("iron-gear-wheel", 60, fake_force{})

      assert.are.same({}, validator.validate(result.entities, catalog))
    end)

    local plain_only = {
      {label = "no force is given, so nothing is known to be researched", force = nil},
      {label = "the force has not researched the fast inserter", force = fake_force{locked = {"fast-inserter"}}},
      {label = "the force does not know the recipe of the fast inserter", force = fake_force{absent = {"fast-inserter"}}},
      {label = "the game has no fast inserter", force = fake_force{}, game = {missing_entities = {"fast-inserter"}}},
      {label = "the game does not say how fast the fast inserter swings", force = fake_force{}, game = {fast_inserter_rotation_speed = false}},
    }

    for _, case in ipairs(plain_only) do
      it("uses plain inserters only when " .. case.label, function()
        _G.prototypes = gear_game(case.game)

        local result = generator.generate("iron-gear-wheel", 60, case.force)

        assert.are.equal(0, count_named(result.entities, "fast-inserter"))
      end)
    end

    describe("copper cables, which an assembler makes at 120 a minute from 60 plates", function()
      -- One fast inserter moves the 120 cables of a machine. The last column's belt winds so that machines side by side fill a
      -- lane each, so the product keeps both lanes and one more machine's worth than a lane carries is lost.
      local copper_plate = a_recipe{energy = 3.2, ingredients = {amount_of(1, "copper-ore")}, products = {amount_of(1, "copper-plate")}, category = "smelting"}
      local cable = a_recipe{energy = 0.5, ingredients = {amount_of(1, "copper-plate")}, products = {amount_of(2, "copper-cable")}}

      local function cable_game()
        return fake_prototypes{
          furnace_speed = 1,
          machines = {["assembling-machine-1"] = a_machine{crafting_speed = 0.5, size = 3}},
          recipes = {["copper-plate"] = copper_plate, ["copper-cable"] = cable},
        }
      end

      it("allows 810 a minute, 6.75 machines' worth of 120, with the paired winding belt", function()
        _G.prototypes = cable_game()

        assert.are.same({"blueprint-generation.max-rate", "810"}, generator.max_rate_message("copper-cable", fake_force{}))
      end)

      it("allows 900 a minute, as it always did, with plain inserters, which wind the belt with two inserters on a machine", function()
        _G.prototypes = cable_game()

        assert.are.same({"blueprint-generation.max-rate", "900"}, generator.max_rate_message("copper-cable"))
      end)

      it("builds a blueprint that passes the validator, with every machine fed, emptied and powered", function()
        _G.prototypes = cable_game()
        local catalog = builders.a_catalog{machine_size = 2, machine_needs_power = false}
        catalog["assembling-machine-1"] = {kind = "machine", width = 3, height = 3, needs_power = true}

        local result = generator.generate("copper-cable", 500, fake_force{})

        assert.are.same({}, validator.validate(result.entities, catalog))
      end)

      it("gives every assembler one fast inserter on each side", function()
        _G.prototypes = cable_game()

        local result = generator.generate("copper-cable", 500, fake_force{})

        assert.are.equal(2 * count_named(result.entities, "assembling-machine-1"), count_named(result.entities, "fast-inserter"))
      end)
    end)

    it("shows the maximum the same way when the fast inserter is not researched", function()
      _G.prototypes = gear_game()

      -- (the medium pole is locked as well: with it a step is built wide when the rate asks for more, which the
      -- message for no force, the original design, does not show)
      assert.are.same(generator.max_rate_message("iron-gear-wheel"), generator.max_rate_message("iron-gear-wheel", fake_force{locked = {"fast-inserter", "medium-electric-pole"}}))
    end)
  end)

  describe("refusals", function()
    it("refuses the request when the item is not supported", function()
      _G.prototypes = fake_prototypes{}

      local result, error_message = generator.generate("advanced-circuit", 10)

      assert.is_nil(result)
      assert.are.same({"blueprint-generation.error-unsupported-item"}, error_message)
    end)

    it("refuses the request when a building prototype is missing", function()
      _G.prototypes = fake_prototypes{
        missing_entities = {"inserter"},
        recipes = {["iron-plate"] = a_recipe{energy = 3.2, ingredients = {amount_of(1, "iron-ore")}, products = {amount_of(1, "iron-plate")}, category = "smelting"}},
      }

      local result, error_message = generator.generate("iron-plate", 10)

      assert.is_nil(result)
      assert.are.same({"blueprint-generation.error-missing-prototype"}, error_message)
    end)

    it("refuses the request when no recipe makes the item, naming the item", function()
      _G.prototypes = fake_prototypes{items = {"iron-plate"}, recipes = {}}

      local result, error_message = generator.generate("iron-plate", 10)

      assert.is_nil(result)
      assert.are.same({"blueprint-generation.error-no-recipe", {"item-name.iron-plate"}}, error_message)
    end)

    it("names the item by its plain name when the game has no such item", function()
      _G.prototypes = fake_prototypes{recipes = {}}

      local _, error_message = generator.generate("iron-plate", 10)

      assert.are.same({"blueprint-generation.error-no-recipe", "iron-plate"}, error_message)
    end)

    it("refuses the recipe when two ingredients and a fuel need three lanes", function()
      _G.prototypes = fake_prototypes{
        recipes = {["iron-plate"] = a_recipe{energy = 3.2, ingredients = {amount_of(1, "iron-ore"), amount_of(1, "coal")}, products = {amount_of(1, "iron-plate")}, category = "smelting"}},
      }

      local result, error_message = generator.generate("iron-plate", 10)

      assert.is_nil(result)
      assert.are.same({"blueprint-generation.error-unsupported-recipe"}, error_message)
    end)

    it("refuses the request when the machine cannot craft", function()
      _G.prototypes = fake_prototypes{
        furnace_speed = false,
        recipes = {["iron-plate"] = a_recipe{energy = 3.2, ingredients = {amount_of(1, "iron-ore")}, products = {amount_of(1, "iron-plate")}, category = "smelting"}},
      }

      local result, error_message = generator.generate("iron-plate", 10)

      assert.is_nil(result)
      assert.are.same({"blueprint-generation.error-missing-prototype"}, error_message)
    end)

    it("refuses the request when the inserter has no rotation speed", function()
      _G.prototypes = fake_prototypes{
        inserter_rotation_speed = false,
        recipes = {["iron-plate"] = a_recipe{energy = 3.2, ingredients = {amount_of(1, "iron-ore")}, products = {amount_of(1, "iron-plate")}, category = "smelting"}},
      }

      local result, error_message = generator.generate("iron-plate", 10)

      assert.is_nil(result)
      assert.are.same({"blueprint-generation.error-missing-prototype"}, error_message)
    end)

    describe("a furnace that eats what another step makes and burns fuel", function()
      local plate = a_recipe{energy = 3.2, ingredients = {amount_of(1, "iron-ore")}, products = {amount_of(1, "iron-plate")}, category = "smelting"}
      local gear_in_a_furnace = a_recipe{energy = 3.2, ingredients = {amount_of(2, "iron-plate")}, products = {amount_of(1, "iron-gear-wheel")}, category = "smelting"}

      it("is refused without the design that brings in one belt of each material, naming the item", function()
        _G.prototypes = fake_prototypes{recipes = {["iron-plate"] = plate, ["iron-gear-wheel"] = gear_in_a_furnace}}

        local result, error_message = generator.generate("iron-gear-wheel", 10)

        assert.is_nil(result)
        assert.are.same({"blueprint-generation.error-fuel-needs-inputs", {"item-name.iron-gear-wheel"}}, error_message)
      end)

      it("is built with it, the fuel brought to the furnace on the lane the plates leave free", function()
        _G.prototypes = fake_prototypes{recipes = {["iron-plate"] = plate, ["iron-gear-wheel"] = gear_in_a_furnace}}

        local result = generator.generate("iron-gear-wheel", 10, fake_force{})

        assert.are.equal("blueprint-generation.generated-with-belts", result.message[1])
        assert.are.same({"", {"item-name.coal"}, ", ", {"item-name.iron-ore"}}, result.message[5]) -- one coal belt feeds both furnaces
      end)
    end)

    it("refuses the request when two recipes make an item on the way, naming the item", function()
      local plate = a_recipe{energy = 3.2, ingredients = {amount_of(1, "iron-ore")}, products = {amount_of(1, "iron-plate")}, category = "smelting"}
      local other_plate = a_recipe{energy = 1, ingredients = {amount_of(1, "scrap")}, products = {amount_of(1, "iron-plate")}, category = "smelting"}
      local gear = a_recipe{energy = 0.5, ingredients = {amount_of(2, "iron-plate")}, products = {amount_of(1, "iron-gear-wheel")}}
      _G.prototypes = fake_prototypes{
        machines = {["assembling-machine-1"] = a_machine{crafting_speed = 0.5, size = 3}},
        recipes = {["iron-plate"] = plate, ["iron-plate-from-scrap"] = other_plate, ["iron-gear-wheel"] = gear},
      }

      local result, error_message = generator.generate("iron-gear-wheel", 10)

      assert.is_nil(result)
      assert.are.same({"blueprint-generation.error-ambiguous-recipe", {"item-name.iron-plate"}}, error_message)
    end)

    it("refuses the request when a step needs five made ingredients, naming the item", function()
      local plate = a_recipe{energy = 3.2, ingredients = {amount_of(1, "iron-ore")}, products = {amount_of(1, "iron-plate")}, category = "smelting"}
      local copper = a_recipe{energy = 3.2, ingredients = {amount_of(1, "copper-ore")}, products = {amount_of(1, "copper-plate")}, category = "smelting"}
      local brick = a_recipe{energy = 3.2, ingredients = {amount_of(2, "stone")}, products = {amount_of(1, "stone-brick")}, category = "smelting"}
      local cable = a_recipe{energy = 0.5, ingredients = {amount_of(1, "copper-plate")}, products = {amount_of(2, "copper-cable")}}
      local pipe = a_recipe{energy = 0.5, ingredients = {amount_of(1, "iron-plate")}, products = {amount_of(1, "pipe")}}
      local gear = a_recipe{
        energy = 0.5,
        ingredients = {amount_of(2, "iron-plate"), amount_of(1, "copper-plate"), amount_of(1, "stone-brick"), amount_of(1, "copper-cable"), amount_of(1, "pipe")},
        products = {amount_of(1, "iron-gear-wheel")},
      }
      _G.prototypes = fake_prototypes{
        machines = {["assembling-machine-1"] = a_machine{crafting_speed = 0.5, size = 3}},
        recipes = {
          ["iron-plate"] = plate, ["copper-plate"] = copper, ["stone-brick"] = brick, ["copper-cable"] = cable, ["pipe"] = pipe,
          ["iron-gear-wheel"] = gear,
        },
      }

      local result, error_message = generator.generate("iron-gear-wheel", 10)

      assert.is_nil(result)
      assert.are.same({"blueprint-generation.error-chain-too-complex", {"item-name.iron-gear-wheel"}}, error_message)
    end)

    it("refuses the request when a later step mixes the made ingredient with two raw ones, naming the item", function()
      local plate = a_recipe{energy = 3.2, ingredients = {amount_of(1, "iron-ore")}, products = {amount_of(1, "iron-plate")}, category = "smelting"}
      local gear = a_recipe{
        energy = 0.5, ingredients = {amount_of(2, "iron-plate"), amount_of(1, "stone"), amount_of(1, "flint")},
        products = {amount_of(1, "iron-gear-wheel")},
      }
      _G.prototypes = fake_prototypes{
        machines = {["assembling-machine-1"] = a_machine{crafting_speed = 0.5, size = 3}},
        recipes = {["iron-plate"] = plate, ["iron-gear-wheel"] = gear},
      }

      local result, error_message = generator.generate("iron-gear-wheel", 10)

      assert.is_nil(result)
      assert.are.same({"blueprint-generation.error-chain-too-complex", {"item-name.iron-gear-wheel"}}, error_message)
    end)

    it("refuses the request when only a machine the config does not name makes the item", function()
      local plate_in_a_chemical_plant = a_recipe{energy = 1, ingredients = {amount_of(1, "iron-ore")}, products = {amount_of(1, "iron-plate")}, category = "chemistry"}
      _G.prototypes = fake_prototypes{recipes = {["iron-plate"] = plate_in_a_chemical_plant}}

      local result, error_message = generator.generate("iron-plate", 10)

      assert.is_nil(result)
      assert.are.same({"blueprint-generation.error-no-recipe", {"item-name.iron-plate"}}, error_message)
    end)

    it("refuses the request when a recipe on the way has a fluid ingredient", function()
      -- two ingredients fit the two lanes of an electric machine, so only the fluid can make the recipe unsupported
      local wet_gear = a_recipe{energy = 0.5, ingredients = {amount_of(2, "iron-plate"), fluid_of(10, "water")}, products = {amount_of(1, "iron-gear-wheel")}}
      _G.prototypes = fake_prototypes{
        machines = {["assembling-machine-1"] = a_machine{crafting_speed = 0.5, size = 3}},
        recipes = {["iron-gear-wheel"] = wet_gear},
      }

      local result, error_message = generator.generate("iron-gear-wheel", 10)

      assert.is_nil(result)
      assert.are.same({"blueprint-generation.error-unsupported-recipe"}, error_message)
    end)

    it("refuses the request when the machine of a later step has a size the layout cannot build", function()
      local plate = a_recipe{energy = 3.2, ingredients = {amount_of(1, "iron-ore")}, products = {amount_of(1, "iron-plate")}, category = "smelting"}
      local gear = a_recipe{energy = 0.5, ingredients = {amount_of(2, "iron-plate")}, products = {amount_of(1, "iron-gear-wheel")}}
      _G.prototypes = fake_prototypes{
        machines = {["assembling-machine-1"] = a_machine{crafting_speed = 0.5, size = 4}},
        recipes = {["iron-plate"] = plate, ["iron-gear-wheel"] = gear},
      }

      local result, error_message = generator.generate("iron-gear-wheel", 10)

      assert.is_nil(result)
      assert.are.same({"blueprint-generation.error-unsupported-machine"}, error_message)
    end)

    it("refuses the request when the machine of an earlier step cannot craft", function()
      local plate = a_recipe{energy = 3.2, ingredients = {amount_of(1, "iron-ore")}, products = {amount_of(1, "iron-plate")}, category = "smelting"}
      local gear = a_recipe{energy = 0.5, ingredients = {amount_of(2, "iron-plate")}, products = {amount_of(1, "iron-gear-wheel")}}
      _G.prototypes = fake_prototypes{
        furnace_speed = false,
        machines = {["assembling-machine-1"] = a_machine{crafting_speed = 0.5, size = 3}},
        recipes = {["iron-plate"] = plate, ["iron-gear-wheel"] = gear},
      }

      local result, error_message = generator.generate("iron-gear-wheel", 10)

      assert.is_nil(result)
      assert.are.same({"blueprint-generation.error-missing-prototype"}, error_message)
    end)

    it("refuses the request when the machine of an earlier step has a size the layout cannot build", function()
      -- the iron plate is smelted from iron ore that an assembler of size 4 makes from scrap
      local ore = a_recipe{energy = 1, ingredients = {amount_of(1, "scrap")}, products = {amount_of(1, "iron-ore")}}
      local plate = a_recipe{energy = 3.2, ingredients = {amount_of(1, "iron-ore")}, products = {amount_of(1, "iron-plate")}, category = "smelting"}
      _G.prototypes = fake_prototypes{
        machines = {["assembling-machine-1"] = a_machine{crafting_speed = 0.5, size = 4}},
        recipes = {["iron-ore"] = ore, ["iron-plate"] = plate},
      }

      local result, error_message = generator.generate("iron-plate", 10)

      assert.is_nil(result)
      assert.are.same({"blueprint-generation.error-unsupported-machine"}, error_message)
    end)

    it("refuses the request when the machine of a later step is missing", function()
      local plate = a_recipe{energy = 3.2, ingredients = {amount_of(1, "iron-ore")}, products = {amount_of(1, "iron-plate")}, category = "smelting"}
      local gear = a_recipe{energy = 0.5, ingredients = {amount_of(2, "iron-plate")}, products = {amount_of(1, "iron-gear-wheel")}}
      _G.prototypes = fake_prototypes{recipes = {["iron-plate"] = plate, ["iron-gear-wheel"] = gear}}

      local result, error_message = generator.generate("iron-gear-wheel", 10)

      assert.is_nil(result)
      assert.are.same({"blueprint-generation.error-missing-prototype"}, error_message)
    end)

    it("refuses the request when the belt has no belt speed", function()
      _G.prototypes = fake_prototypes{
        belt_speed = false,
        recipes = {["iron-plate"] = a_recipe{energy = 3.2, ingredients = {amount_of(1, "iron-ore")}, products = {amount_of(1, "iron-plate")}, category = "smelting"}},
      }

      local result, error_message = generator.generate("iron-plate", 10)

      assert.is_nil(result)
      assert.are.same({"blueprint-generation.error-missing-prototype"}, error_message)
    end)
  end)

  describe("lamps, put on the blueprint once the force has unlocked the small lamp", function()
    local plate = a_recipe{energy = 3.2, ingredients = {amount_of(1, "iron-ore")}, products = {amount_of(1, "iron-plate")}, category = "smelting"}
    local gear = a_recipe{energy = 0.5, ingredients = {amount_of(2, "iron-plate")}, products = {amount_of(1, "iron-gear-wheel")}}

    local function gear_game(options)
      options = options or {}
      return fake_prototypes{
        furnace_speed = 1,
        machines = {["assembling-machine-1"] = a_machine{crafting_speed = 0.5, size = 3}},
        recipes = {["iron-plate"] = plate, ["iron-gear-wheel"] = gear},
        missing_entities = options.missing_entities,
      }
    end

    -- The tiles of the lamps of a blueprint.
    local function lamps_of(entities)
      local lamps = {}
      for _, entity in ipairs(entities) do
        if entity.name == "small-lamp" then
          lamps[#lamps + 1] = grid.top_left_tile(entity.position)
        end
      end
      return lamps
    end

    local function closest_pair(lamps)
      local closest = math.huge
      for i = 1, #lamps - 1 do
        for j = i + 1, #lamps do
          closest = math.min(closest, math.sqrt((lamps[i].x - lamps[j].x) ^ 2 + (lamps[i].y - lamps[j].y) ^ 2))
        end
      end
      return closest
    end

    it("puts lamps on a blueprint, more than one when it is long", function()
      _G.prototypes = gear_game()

      local result = generator.generate("iron-gear-wheel", 200, fake_force{})

      assert.is_true(#lamps_of(result.entities) > 1)
    end)

    it("puts no two lamps closer than 10 tiles", function()
      _G.prototypes = gear_game()

      local result = generator.generate("iron-gear-wheel", 200, fake_force{})

      assert.is_true(closest_pair(lamps_of(result.entities)) >= 10)
    end)

    it("builds a blueprint that passes the validator, every lamp powered and on a tile of its own", function()
      _G.prototypes = gear_game()
      local catalog = builders.a_catalog{machine_size = 2, machine_needs_power = false}
      catalog["assembling-machine-1"] = {kind = "machine", width = 3, height = 3, needs_power = true}

      local result = generator.generate("iron-gear-wheel", 200, fake_force{})

      assert.are.same({}, validator.validate(result.entities, catalog))
    end)

    local without_lamps = {
      {label = "no force is given, so nothing is known to be researched", force = nil},
      {label = "the force has not unlocked the small lamp", force = fake_force{locked = {"small-lamp"}}},
      {label = "the force does not know the recipe of the small lamp", force = fake_force{absent = {"small-lamp"}}},
      {label = "the game has no small lamp", force = fake_force{}, game = {missing_entities = {"small-lamp"}}},
    }

    for _, case in ipairs(without_lamps) do
      it("puts no lamp on the blueprint when " .. case.label, function()
        _G.prototypes = gear_game(case.game)

        local result = generator.generate("iron-gear-wheel", 200, case.force)

        assert.are.equal(0, count_named(result.entities, "small-lamp"))
      end)
    end
  end)

  describe("furnaces built wide, when the force has what they need and the rate asks for more than the plain design makes", function()
    -- A furnace makes 18.75 plates a minute and a lane carries 450, so 24 furnaces make the most a plain column does. Built
    -- wide (a second input belt woven with the first, poles beside the output side, the output belt winding in twos)
    -- 48 furnaces make 900. 500 plates a minute are 26.67 furnaces: 27.
    local plate = a_recipe{energy = 3.2, ingredients = {amount_of(1, "iron-ore")}, products = {amount_of(1, "iron-plate")}, category = "smelting"}
    local gear = a_recipe{energy = 0.5, ingredients = {amount_of(2, "iron-plate")}, products = {amount_of(1, "iron-gear-wheel")}}
    local steel = a_recipe{energy = 16, ingredients = {amount_of(5, "iron-plate")}, products = {amount_of(1, "steel-plate")}, category = "smelting"}

    local function game(options)
      options = options or {}
      return fake_prototypes{
        furnace_speed = 1,
        machines = {["assembling-machine-1"] = a_machine{crafting_speed = 0.5, size = 3}},
        recipes = {["iron-plate"] = plate, ["iron-gear-wheel"] = gear, ["steel-plate"] = steel},
        missing_entities = options.missing_entities,
        medium_pole_supply_distance = options.medium_pole_supply_distance,
      }
    end

    -- A furnace built wide has two input inserters and an output inserter; a plain one has an input and an output inserter.
    local function inserters_per_furnace(result)
      return count_named(result.entities, "inserter") / count_named(result.entities, "stone-furnace")
    end

    it("builds the furnaces plain at a rate the plain design makes", function()
      _G.prototypes = game()

      local result = generator.generate("iron-plate", 450, fake_force{})

      assert.are.equal(2, inserters_per_furnace(result))
    end)

    it("builds the furnaces wide above that, two input inserters and an output inserter on each", function()
      _G.prototypes = game()

      local result = generator.generate("iron-plate", 500, fake_force{})

      assert.are.same({27, 3}, {count_named(result.entities, "stone-furnace"), inserters_per_furnace(result)})
    end)

    it("builds a blueprint that passes the validator, the second belt and the poles beside the output side included", function()
      _G.prototypes = game()
      local catalog = builders.a_catalog{machine_size = 2, machine_needs_power = false}

      local result = generator.generate("iron-plate", 900, fake_force{})

      assert.are.same({}, validator.validate(result.entities, catalog))
    end)

    it("builds the furnaces of a chain wide too, and the assemblers that eat their plates", function()
      _G.prototypes = game()
      local catalog = builders.a_catalog{machine_size = 2, machine_needs_power = false}
      catalog["assembling-machine-1"] = {kind = "machine", width = 3, height = 3, needs_power = true}

      local result = generator.generate("iron-gear-wheel", 300, fake_force{})

      assert.are.same({}, validator.validate(result.entities, catalog))
      assert.is_true(count_named(result.entities, "stone-furnace") > 24) -- 300 gears need 600 plates: 32 furnaces, more than a plain column makes
    end)

    it("allows 900 plates a minute, 48 furnaces' worth", function()
      _G.prototypes = game()

      assert.are.same({"blueprint-generation.max-rate", "900"}, generator.max_rate_message("iron-plate", fake_force{}))
    end)

    it("refuses a rate above that", function()
      _G.prototypes = game()

      local result, message = generator.generate("iron-plate", 901, fake_force{})

      assert.are.same({nil, {"blueprint-generation.error-rate-too-high", "900"}}, {result, message})
    end)

    -- What the generator tells the layout about the furnaces: the stage layout `rows.build_pure` is given.
    local function layout_of(item, rate)
      local rows = require("scripts.rows")
      local build_pure, given = rows.build_pure, nil
      rows.build_pure = function(root, names, options)
        given = root
        return build_pure(root, names, options)
      end
      local ok, problem = pcall(generator.generate, item, rate, fake_force{})
      rows.build_pure = build_pure
      assert(ok, problem)
      return given
    end

    -- The items of a feed with their amounts to two decimals: "iron-ore 450.00".
    local function amounts(feed)
      local list = {}
      for _, item in ipairs(feed.items) do
        list[#list + 1] = string.format("%s %.2f", item.name, item.amount)
      end
      return list
    end

    it("takes a lane of ore and the fuel from the first belt of furnaces built wide", function()
      _G.prototypes = game()

      local root = layout_of("iron-plate", 600) -- 32 furnaces: 600 ore a minute, and 32 x 1.35 coal

      assert.are.same({"iron-ore 450.00", "coal 43.20"}, amounts(root.feed))
    end)

    it("takes the rest of the ore from the second belt of furnaces built wide, and no fuel", function()
      _G.prototypes = game()

      local root = layout_of("iron-plate", 600)

      assert.are.same({"iron-ore 150.00"}, amounts(root.second_feed))
    end)

    it("allows 180 steel plates a minute, 48 steel furnaces' worth, where the plain design allows 90", function()
      _G.prototypes = game()

      assert.are.same({{"blueprint-generation.max-rate", "180"}, {"blueprint-generation.max-rate", "90"}},
        {generator.max_rate_message("steel-plate", fake_force{}), generator.max_rate_message("steel-plate", fake_force{locked = {"medium-electric-pole"}})})
    end)

    it("tells the layout that the iron furnaces draw a second belt and the steel furnaces a belt of fuel", function()
      _G.prototypes = game()

      local steel_stage = layout_of("steel-plate", 100)
      local iron_stage = steel_stage.suppliers[1]

      assert.are.same({{false, true}, {true, false}}, {
        {iron_stage.shape.fuel_belt, iron_stage.shape.second_input_belt},
        {steel_stage.shape.fuel_belt, steel_stage.shape.second_input_belt},
      }) -- (each is {the belt of fuel, the second belt}: the iron furnaces draw the second, the steel furnaces the belt of fuel)
    end)

    it("builds the iron furnaces and the steel furnaces wide, three inserters on each, and a blueprint that passes the validator", function()
      _G.prototypes = game()
      local catalog = builders.a_catalog{machine_size = 2, machine_needs_power = true}

      local result = generator.generate("steel-plate", 100, fake_force{}) -- 27 steel furnaces, and 27 iron furnaces for their plates

      assert.are.same({54, 3, {}}, {count_named(result.entities, "stone-furnace"), inserters_per_furnace(result), validator.validate(result.entities, catalog)})
    end)

    local plain = {
      {label = "no force is given, which is the original design", force = nil},
      {label = "the force has not unlocked the splitter, which is the original design too", force = fake_force{locked = {"splitter"}}},
      {label = "the force has not unlocked the underground belt, which is the original design too", force = fake_force{locked = {"underground-belt"}}},
      {label = "the force has not unlocked the medium pole, whose small pole does not reach the input inserters from the output side", force = fake_force{locked = {"medium-electric-pole"}}},
      {label = "the medium pole of the game powers no more than 2.5 tiles", force = fake_force{}, game = {medium_pole_supply_distance = 2.5}},
    }

    for _, case in ipairs(plain) do
      it("allows 450 plates a minute, as the plain design does, when " .. case.label, function()
        _G.prototypes = game(case.game)

        assert.are.same({"blueprint-generation.max-rate", "450"}, generator.max_rate_message("iron-plate", case.force))
      end)
    end
  end)

  describe("the medium electric pole, built with once the force has unlocked it", function()
    -- 60 gears a minute are 7 furnaces and an assembler: the poles beside them are what changes.
    local plate = a_recipe{energy = 3.2, ingredients = {amount_of(1, "iron-ore")}, products = {amount_of(1, "iron-plate")}, category = "smelting"}
    local gear = a_recipe{energy = 0.5, ingredients = {amount_of(2, "iron-plate")}, products = {amount_of(1, "iron-gear-wheel")}}

    local function gear_game(options)
      options = options or {}
      return fake_prototypes{
        furnace_speed = 1,
        machines = {["assembling-machine-1"] = a_machine{crafting_speed = 0.5, size = 3}},
        recipes = {["iron-plate"] = plate, ["iron-gear-wheel"] = gear},
        missing_entities = options.missing_entities,
        medium_pole_supply_distance = options.medium_pole_supply_distance,
        medium_pole_wire_distance = options.medium_pole_wire_distance,
      }
    end

    it("builds with 8 medium poles, where small poles take 10, and no small pole", function()
      _G.prototypes = gear_game()

      local result = generator.generate("iron-gear-wheel", 60, fake_force{})

      assert.are.same({8, 0}, {count_named(result.entities, "medium-electric-pole"), count_named(result.entities, "small-electric-pole")})
    end)

    it("builds a blueprint that passes the validator, every inserter, machine and lamp powered and the poles wired", function()
      _G.prototypes = gear_game()
      local catalog = builders.a_catalog{machine_size = 2, machine_needs_power = false}
      catalog["assembling-machine-1"] = {kind = "machine", width = 3, height = 3, needs_power = true}

      local result = generator.generate("iron-gear-wheel", 200, fake_force{})

      assert.are.same({}, validator.validate(result.entities, catalog))
    end)

    it("takes how far the pole powers from the game: a medium pole that powers 2.5 tiles takes the 10 poles of a small one", function()
      _G.prototypes = gear_game({medium_pole_supply_distance = 2.5, medium_pole_wire_distance = 7.5})

      local result = generator.generate("iron-gear-wheel", 60, fake_force{})

      assert.are.equal(10, count_named(result.entities, "medium-electric-pole"))
    end)

    it("puts the lamps by the supply distance the game gives for the medium pole: a game that says 2.5 gets other lamps", function()
      local function lamp_tiles(entities)
        local tiles = {}
        for _, entity in ipairs(entities) do
          if entity.name == "small-lamp" then
            local tile = grid.top_left_tile(entity.position)
            tiles[#tiles + 1] = tile.x .. "," .. tile.y
          end
        end
        return tiles
      end
      _G.prototypes = gear_game()
      local powering_3_5 = generator.generate("iron-gear-wheel", 200, fake_force{})
      _G.prototypes = gear_game({medium_pole_supply_distance = 2.5, medium_pole_wire_distance = 9})

      local powering_2_5 = generator.generate("iron-gear-wheel", 200, fake_force{})

      assert.are_not.same(lamp_tiles(powering_3_5.entities), lamp_tiles(powering_2_5.entities))
    end)

    -- The poles of the blueprint of 60 gears when the medium pole is not used: 10 with the force's design (the band of the
    -- one-belt design is what a force that has the splitter and the underground belt gets), 12 in the original design.
    local small_only = {
      {label = "no force is given, so nothing is known to be unlocked", force = nil, poles = 12},
      {label = "the force has not unlocked the medium pole", force = fake_force{locked = {"medium-electric-pole"}}, poles = 10},
      {label = "the force does not know the recipe of the medium pole", force = fake_force{absent = {"medium-electric-pole"}}, poles = 10},
      {label = "the game has no medium pole", force = fake_force{}, game = {missing_entities = {"medium-electric-pole"}}, poles = 10},
    }

    for _, case in ipairs(small_only) do
      it("builds with the small pole when " .. case.label, function()
        _G.prototypes = gear_game(case.game)

        local result = generator.generate("iron-gear-wheel", 60, case.force)

        assert.are.same({0, case.poles}, {count_named(result.entities, "medium-electric-pole"), count_named(result.entities, "small-electric-pole")})
      end)
    end

    it("stops with a message when the game does not say how far the medium pole powers", function()
      _G.prototypes = gear_game({medium_pole_supply_distance = false})

      assert.has_error(function() generator.generate("iron-gear-wheel", 60, fake_force{}) end,
        "generator: the game does not give the supply area distance of medium-electric-pole")
    end)

    it("stops with a message when the game gives the medium pole no wire", function()
      _G.prototypes = gear_game({medium_pole_wire_distance = false})

      assert.has_error(function() generator.generate("iron-gear-wheel", 60, fake_force{}) end,
        "generator: the game does not give the wire distance of medium-electric-pole")
    end)
  end)
end)
