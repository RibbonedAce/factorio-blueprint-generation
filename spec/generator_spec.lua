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

local fake_prototypes = builders.fake_prototypes
local a_recipe = builders.a_recipe
local a_machine = builders.a_machine
local amount_of = builders.amount_of
local fluid_of = builders.fluid_of

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

    it("tells the player what was built, the rate achieved and what goes on the belt when a blueprint is ready", function()
      _G.prototypes = fake_prototypes{
        furnace_speed = 1,
        recipes = {["iron-plate"] = a_recipe{energy = 3.2, ingredients = {amount_of(1, "iron-ore")}, products = {amount_of(1, "iron-plate")}, category = "smelting"}},
      }

      local result = generator.generate("iron-plate", 50)

      assert.are.same({
        "blueprint-generation.generated",
        {"",
          {
            "blueprint-generation.generated-first-stage",
            "3",                           -- furnaces
            {"entity-name.stone-furnace"},
            "56.25",                       -- 3 x 18.75 achieved
            {"item-name.iron-plate"},
          },
        },
        "50",                          -- what was asked for
        {"item-name.iron-ore"},
        {"item-name.coal"},
      }, result.message)
    end)

    it("prints whole numbers without decimals when the rate is whole", function()
      _G.prototypes = fake_prototypes{
        furnace_speed = 1,
        recipes = {["iron-plate"] = a_recipe{energy = 3.2, ingredients = {amount_of(1, "iron-ore")}, products = {amount_of(1, "iron-plate")}, category = "smelting"}},
      }

      local result = generator.generate("iron-plate", 60)

      local first_step = result.message[2][2]
      assert.are.equal("75", first_step[4]) -- 4 furnaces x 18.75, not "75.00"
      assert.are.equal("60", result.message[3])
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

    it("tells the player to use both lanes for the ingredient when the machine burns nothing", function()
      _G.prototypes = fake_prototypes{
        inserter_rotation_speed = 0.014,
        machines = {["assembling-machine-1"] = assembler},
        recipes = {["iron-gear-wheel"] = gear},
      }

      local result = generator.generate("iron-gear-wheel", 100)

      assert.are.same({
        "blueprint-generation.generated-one-item",
        {"",
          {
            "blueprint-generation.generated-first-stage",
            "2",                                    -- machines
            {"entity-name.assembling-machine-1"},
            "100.8",                                -- 2 x 50.4 achieved
            {"item-name.iron-gear-wheel"},
          },
        },
        "100",                                  -- what was asked for
        {"item-name.iron-plate"},
      }, result.message)
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

    it("refuses the rate when another machine would eat more than the input lanes carry", function()
      _G.prototypes = fake_prototypes{
        belt_speed = 0.03125,
        inserter_rotation_speed = 0.014,
        machines = {["assembling-machine-1"] = assembler},
        recipes = {["iron-gear-wheel"] = gear},
      }

      local result, error_message = generator.generate("iron-gear-wheel", 500)

      assert.is_nil(result)
      assert.are.same({"blueprint-generation.error-rate-too-high", "403.2"}, error_message) -- 900 / 100.8 = 8.9, so 8 machines x 50.4
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

      assert.are.equal(16, count_named(result.entities, "transport-belt")) -- 4 input tiles (rows 0 to 3) + 2 machines x 6
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

    it("refuses the rate when another machine would overfill an output lane", function()
      _G.prototypes = fake_prototypes{
        belt_speed = 0.03125,
        inserter_rotation_speed = 0.014,
        machines = {["assembling-machine-1"] = assembler},
        recipes = {["iron-gear-wheel"] = doubling},
      }

      local result, error_message = generator.generate("iron-gear-wheel", 810)

      assert.is_nil(result)
      assert.are.same({"blueprint-generation.error-rate-too-high", "806.4"}, error_message) -- 450 / 50.4 = 8.9, so 8 machines x 100.8
    end)
  end)

  describe("a recipe made in an electric machine, with two ingredients on one lane each", function()
    local two_ingredients = a_recipe{
      energy = 0.5,
      ingredients = {amount_of(1, "iron-plate"), amount_of(3, "copper-cable")},
      products = {amount_of(1, "iron-gear-wheel")},
    }
    local assembler = a_machine{crafting_speed = 0.5, size = 3}

    it("tells the player which ingredient goes on which lane when the recipe has two", function()
      _G.prototypes = fake_prototypes{
        inserter_rotation_speed = 0.014, -- 50.4 items a minute
        machines = {["assembling-machine-1"] = assembler},
        recipes = {["iron-gear-wheel"] = two_ingredients},
      }

      local result = generator.generate("iron-gear-wheel", 50)

      assert.are.same({
        "blueprint-generation.generated",
        {"",
          {
            "blueprint-generation.generated-first-stage",
            "2",                                    -- machines
            {"entity-name.assembling-machine-1"},
            "50.4",                                 -- 2 x 25.2 achieved: 240 items a minute at full speed, but two inserters move 100.8, so 60 x 100.8 / 240
            {"item-name.iron-gear-wheel"},
          },
        },
        "50",                                   -- what was asked for
        {"item-name.iron-plate"},
        {"item-name.copper-cable"},
      }, result.message)
    end)

    it("refuses the rate when one ingredient's lane fills before the other's", function()
      _G.prototypes = fake_prototypes{
        belt_speed = 0.03125,
        inserter_rotation_speed = 0.014,
        machines = {["assembling-machine-1"] = assembler},
        recipes = {["iron-gear-wheel"] = two_ingredients},
      }

      local result, error_message = generator.generate("iron-gear-wheel", 130)

      assert.is_nil(result)
      assert.are.same({"blueprint-generation.error-rate-too-high", "126"}, error_message) -- a machine eats 75.6 cables a minute: 450 / 75.6 = 5.9, so 5 machines x 25.2
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

    it("tells the player what each step makes, and puts only the raw items and the fuel on the input belt", function()
      _G.prototypes = gear_game()

      local result = generator.generate("iron-gear-wheel", 100)

      assert.are.same({
        "blueprint-generation.generated",
        {"",
          {
            "blueprint-generation.generated-first-stage",
            "11",                                    -- furnaces
            {"entity-name.stone-furnace"},
            "206.25",                                -- 11 x 18.75 plates
            {"item-name.iron-plate"},
          },
          {
            "blueprint-generation.generated-next-stage",
            "2",                                     -- assemblers
            {"entity-name.assembling-machine-1"},
            "100.8",                                 -- 2 x 50.4 gears
            {"item-name.iron-gear-wheel"},
          },
        },
        "100",                                       -- what was asked for
        {"item-name.iron-ore"},
        {"item-name.coal"},
      }, result.message)
    end)

    it("limits the rate by the one lane that carries the plates to the assemblers", function()
      _G.prototypes = gear_game()

      local result, error_message = generator.generate("iron-gear-wheel", 250)

      assert.is_nil(result)
      -- a lane carries 450 plates a minute, enough for 4 assemblers of 100.8 (4.46), which make 4 x 50.4 gears
      assert.are.same({"blueprint-generation.error-rate-too-high", "201.6"}, error_message)
    end)

    it("allows the rate when the plates fill the lane up to the last assembler that fits", function()
      _G.prototypes = gear_game()

      local result = generator.generate("iron-gear-wheel", 201.6)

      assert.are.equal(4, count_named(result.entities, "assembling-machine-1"))
    end)

    it("limits the rate by the belt speed of the plate lane when the belt is slower", function()
      _G.prototypes = gear_game{belt_speed = 0.015625} -- half the speed: a lane carries 225 plates a minute

      local result, error_message = generator.generate("iron-gear-wheel", 120)

      assert.is_nil(result)
      assert.are.same({"blueprint-generation.error-rate-too-high", "100.8"}, error_message) -- 2 assemblers: 201.6 plates <= 225
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

  describe("refusals", function()
    it("refuses the request when the item is not supported", function()
      _G.prototypes = fake_prototypes{}

      local result, error_message = generator.generate("copper-cable", 10)

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

    it("refuses the request when the machine of a later step burns fuel, naming the item", function()
      local plate = a_recipe{energy = 3.2, ingredients = {amount_of(1, "iron-ore")}, products = {amount_of(1, "iron-plate")}, category = "smelting"}
      local gear_in_a_furnace = a_recipe{energy = 3.2, ingredients = {amount_of(2, "iron-plate")}, products = {amount_of(1, "iron-gear-wheel")}, category = "smelting"}
      _G.prototypes = fake_prototypes{recipes = {["iron-plate"] = plate, ["iron-gear-wheel"] = gear_in_a_furnace}}

      local result, error_message = generator.generate("iron-gear-wheel", 10)

      assert.is_nil(result)
      assert.are.same({"blueprint-generation.error-chain-fuel", {"item-name.iron-gear-wheel"}}, error_message)
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

    it("refuses the request when a step needs two made ingredients, naming the item", function()
      local plate = a_recipe{energy = 3.2, ingredients = {amount_of(1, "iron-ore")}, products = {amount_of(1, "iron-plate")}, category = "smelting"}
      local copper = a_recipe{energy = 3.2, ingredients = {amount_of(1, "copper-ore")}, products = {amount_of(1, "copper-plate")}, category = "smelting"}
      local gear = a_recipe{energy = 0.5, ingredients = {amount_of(2, "iron-plate"), amount_of(1, "copper-plate")}, products = {amount_of(1, "iron-gear-wheel")}}
      _G.prototypes = fake_prototypes{
        machines = {["assembling-machine-1"] = a_machine{crafting_speed = 0.5, size = 3}},
        recipes = {["iron-plate"] = plate, ["copper-plate"] = copper, ["iron-gear-wheel"] = gear},
      }

      local result, error_message = generator.generate("iron-gear-wheel", 10)

      assert.is_nil(result)
      assert.are.same({"blueprint-generation.error-chain-too-complex", {"item-name.iron-gear-wheel"}}, error_message)
    end)

    it("refuses the request when a later step mixes the made ingredient with a raw one, naming the item", function()
      local plate = a_recipe{energy = 3.2, ingredients = {amount_of(1, "iron-ore")}, products = {amount_of(1, "iron-plate")}, category = "smelting"}
      local gear = a_recipe{energy = 0.5, ingredients = {amount_of(2, "iron-plate"), amount_of(1, "stone")}, products = {amount_of(1, "iron-gear-wheel")}}
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
end)
