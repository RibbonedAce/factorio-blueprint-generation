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

local fake_prototypes = builders.fake_prototypes
local a_recipe = builders.a_recipe
local a_machine = builders.a_machine
local amount_of = builders.amount_of

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
    it("needs three stone furnaces for 50 items a minute", function()
      _G.prototypes = fake_prototypes{
        furnace_speed = 1,
        recipes = {["iron-plate"] = a_recipe{energy = 3.2, ingredients = {amount_of(1, "iron-ore")}, products = {amount_of(1, "iron-plate")}}},
      }

      local result = generator.generate("iron-plate", 50)

      assert.are.equal(3, count_named(result.entities, "stone-furnace")) -- 50 / 18.75 = 2.67, rounded up
    end)

    it("brings four small electric poles with three furnaces", function()
      _G.prototypes = fake_prototypes{
        furnace_speed = 1,
        recipes = {["iron-plate"] = a_recipe{energy = 3.2, ingredients = {amount_of(1, "iron-ore")}, products = {amount_of(1, "iron-plate")}}},
      }

      local result = generator.generate("iron-plate", 50)

      assert.are.equal(4, count_named(result.entities, "small-electric-pole"))
    end)

    it("uses only the four buildings the game provides, each under its own name", function()
      _G.prototypes = fake_prototypes{
        recipes = {["iron-plate"] = a_recipe{energy = 3.2, ingredients = {amount_of(1, "iron-ore")}, products = {amount_of(1, "iron-plate")}}},
      }

      local result = generator.generate("iron-plate", 50)

      assert.are.same(
        {"inserter", "small-electric-pole", "stone-furnace", "transport-belt"},
        distinct_names_of(result.entities))
    end)

    it("names the furnaces, the real rate achieved, the ingredient and the fuel in the message", function()
      _G.prototypes = fake_prototypes{
        furnace_speed = 1,
        recipes = {["iron-plate"] = a_recipe{energy = 3.2, ingredients = {amount_of(1, "iron-ore")}, products = {amount_of(1, "iron-plate")}}},
      }

      local result = generator.generate("iron-plate", 50)

      assert.are.same({
        "blueprint-generation.generated",
        "3",                           -- furnaces
        {"entity-name.stone-furnace"},
        "56.25",                       -- 3 x 18.75 achieved
        {"item-name.iron-plate"},
        "50",                          -- what was asked for
        {"item-name.iron-ore"},
        {"item-name.coal"},
      }, result.message)
    end)

    it("prints whole numbers without decimals", function()
      _G.prototypes = fake_prototypes{
        furnace_speed = 1,
        recipes = {["iron-plate"] = a_recipe{energy = 3.2, ingredients = {amount_of(1, "iron-ore")}, products = {amount_of(1, "iron-plate")}}},
      }

      local result = generator.generate("iron-plate", 60)

      assert.are.equal("75", result.message[4]) -- 4 furnaces x 18.75, not "75.00"
      assert.are.equal("60", result.message[6])
    end)

    it("gives the blueprint a description with the rate achieved and the furnaces used", function()
      _G.prototypes = fake_prototypes{
        furnace_speed = 1,
        recipes = {["iron-plate"] = a_recipe{energy = 3.2, ingredients = {amount_of(1, "iron-ore")}, products = {amount_of(1, "iron-plate")}}},
      }

      local result = generator.generate("iron-plate", 50)

      assert.are.equal("iron-plate: 56.25 per minute from 3 x stone-furnace", result.description)
    end)

    it("refuses a rate above one belt lane, naming the standard belt's 450 a minute", function()
      _G.prototypes = fake_prototypes{
        belt_speed = 0.03125,
        furnace_speed = 1,
        recipes = {["iron-plate"] = a_recipe{energy = 3.2, ingredients = {amount_of(1, "iron-ore")}, products = {amount_of(1, "iron-plate")}}},
      }

      local result, error_message = generator.generate("iron-plate", 1000)

      assert.is_nil(result)
      assert.are.same({"blueprint-generation.error-rate-too-high", "450"}, error_message)
    end)
  end)

  describe("a recipe of two of one ingredient to one product", function()
    it("allows exactly 225 items a minute with 12 furnaces, which fill the ingredient lane", function()
      _G.prototypes = fake_prototypes{
        belt_speed = 0.03125,
        furnace_speed = 1,
        recipes = {["stone-brick"] = a_recipe{energy = 3.2, ingredients = {amount_of(2, "stone")}, products = {amount_of(1, "stone-brick")}}},
      }

      local result = generator.generate("stone-brick", 225)

      assert.are.equal(12, count_named(result.entities, "stone-furnace")) -- 12 x 37.5 ingredients = 450, one lane
    end)

    it("refuses 300 items a minute, naming 225 as the most, because the ingredient lane fills before the product lane", function()
      _G.prototypes = fake_prototypes{
        belt_speed = 0.03125,
        furnace_speed = 1,
        recipes = {["stone-brick"] = a_recipe{energy = 3.2, ingredients = {amount_of(2, "stone")}, products = {amount_of(1, "stone-brick")}}},
      }

      local result, error_message = generator.generate("stone-brick", 300)

      assert.is_nil(result)
      assert.are.same({"blueprint-generation.error-rate-too-high", "225"}, error_message) -- 12 furnaces x 18.75
    end)
  end)

  describe("a recipe of one ingredient to two products", function()
    it("reads how many items a craft makes from the recipe, so 75 a minute needs two furnaces", function()
      _G.prototypes = fake_prototypes{
        furnace_speed = 1,
        recipes = {["iron-plate"] = a_recipe{energy = 3.2, ingredients = {amount_of(1, "iron-ore")}, products = {amount_of(2, "iron-plate")}}},
      }

      local result = generator.generate("iron-plate", 75)

      assert.are.equal(2, count_named(result.entities, "stone-furnace")) -- 75 / (18.75 crafts x 2 items)
    end)
  end)

  describe("the belt's speed sets the limit, not a constant", function()
    it("allows 800 items a minute on a belt twice as fast, with 43 furnaces", function()
      _G.prototypes = fake_prototypes{
        belt_speed = 0.0625, -- a lane holds 900 a minute
        furnace_speed = 1,
        recipes = {["iron-plate"] = a_recipe{energy = 3.2, ingredients = {amount_of(1, "iron-ore")}, products = {amount_of(1, "iron-plate")}}},
      }

      local result = generator.generate("iron-plate", 800)

      assert.are.equal(43, count_named(result.entities, "stone-furnace")) -- 800 / 18.75 = 42.7, rounded up
    end)

    it("refuses 1000 items a minute on a belt twice as fast, naming 900 as the most", function()
      _G.prototypes = fake_prototypes{
        belt_speed = 0.0625,
        furnace_speed = 1,
        recipes = {["iron-plate"] = a_recipe{energy = 3.2, ingredients = {amount_of(1, "iron-ore")}, products = {amount_of(1, "iron-plate")}}},
      }

      local result, error_message = generator.generate("iron-plate", 1000)

      assert.is_nil(result)
      assert.are.same({"blueprint-generation.error-rate-too-high", "900"}, error_message) -- 48 furnaces x 18.75
    end)
  end)

  describe("a recipe made in an electric machine, with its one ingredient on both input lanes", function()
    local gear = a_recipe{energy = 0.5, ingredients = {amount_of(2, "iron-plate")}, products = {amount_of(1, "iron-gear-wheel")}}
    local assembler = a_machine{crafting_speed = 0.5, size = 3}

    it("needs two assembling machines for 100 items a minute, because two inserters feed each at 100.8 of the 120 plates it could eat", function()
      _G.prototypes = fake_prototypes{
        inserter_rotation_speed = 0.014, -- 50.4 items a minute
        machines = {["assembling-machine-1"] = assembler},
        recipes = {["iron-gear-wheel"] = gear},
      }

      local result = generator.generate("iron-gear-wheel", 100)

      assert.are.equal(2, count_named(result.entities, "assembling-machine-1")) -- a machine makes 60 x 100.8 / 120 = 50.4 gears; 100 / 50.4 = 1.98
    end)

    it("places two input inserters and one output inserter beside each machine", function()
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

    it("places the machines in tile column 2, three rows apart, with no pole row between them", function()
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

    it("needs fewer machines when the inserter is fast enough to run each at full speed", function()
      _G.prototypes = fake_prototypes{
        inserter_rotation_speed = 0.04, -- 144 items a minute, so two of them move more than the 120 a machine eats
        machines = {["assembling-machine-1"] = assembler},
        recipes = {["iron-gear-wheel"] = gear},
      }

      local result = generator.generate("iron-gear-wheel", 120)

      assert.are.equal(2, count_named(result.entities, "assembling-machine-1")) -- 120 / 60 gears a minute each
    end)

    it("says to put the plates on both lanes, and leaves out any fuel, because the machine burns nothing", function()
      _G.prototypes = fake_prototypes{
        inserter_rotation_speed = 0.014,
        machines = {["assembling-machine-1"] = assembler},
        recipes = {["iron-gear-wheel"] = gear},
      }

      local result = generator.generate("iron-gear-wheel", 100)

      assert.are.same({
        "blueprint-generation.generated-one-item",
        "2",                                    -- machines
        {"entity-name.assembling-machine-1"},
        "100.8",                                -- 2 x 50.4 achieved
        {"item-name.iron-gear-wheel"},
        "100",                                  -- what was asked for
        {"item-name.iron-plate"},
      }, result.message)
    end)

    it("allows 400 items a minute with 8 machines, which fill both input lanes", function()
      _G.prototypes = fake_prototypes{
        belt_speed = 0.03125,
        inserter_rotation_speed = 0.014,
        machines = {["assembling-machine-1"] = assembler},
        recipes = {["iron-gear-wheel"] = gear},
      }

      local result = generator.generate("iron-gear-wheel", 400)

      assert.are.equal(8, count_named(result.entities, "assembling-machine-1")) -- 400 / 50.4 = 7.94; 8 x 100.8 plates is under the 900 of two lanes
    end)

    it("refuses 500 items a minute, naming 403.2 as the most, because 9 machines would eat more than the two lanes carry", function()
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

    it("refuses a machine of a size the layout cannot handle", function()
      _G.prototypes = fake_prototypes{
        machines = {["assembling-machine-1"] = a_machine{crafting_speed = 0.5, size = 4}},
        recipes = {["iron-gear-wheel"] = gear},
      }

      local result, error_message = generator.generate("iron-gear-wheel", 60)

      assert.is_nil(result)
      assert.are.same({"blueprint-generation.error-unsupported-machine"}, error_message)
    end)

    it("refuses a machine that is not square", function()
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

    it("gives each machine one input and two output inserters, and runs it at what two inserters move", function()
      _G.prototypes = fake_prototypes{
        inserter_rotation_speed = 0.014, -- 50.4 items a minute
        machines = {["assembling-machine-1"] = assembler},
        recipes = {["iron-gear-wheel"] = doubling},
      }

      local result = generator.generate("iron-gear-wheel", 200)

      assert.are.equal(2, count_named(result.entities, "assembling-machine-1")) -- each makes 2 x 50.4 = 100.8; 200 / 100.8 = 1.98
      assert.are.equal(6, count_named(result.entities, "inserter")) -- 2 machines x (1 in: 50.4, 2 out: 100.8 / 50.4)
    end)

    it("winds the output belt, with six tiles per machine on top of the straight input belt", function()
      _G.prototypes = fake_prototypes{
        inserter_rotation_speed = 0.014,
        machines = {["assembling-machine-1"] = assembler},
        recipes = {["iron-gear-wheel"] = doubling},
      }

      local result = generator.generate("iron-gear-wheel", 200)

      assert.are.equal(16, count_named(result.entities, "transport-belt")) -- 4 input tiles (rows 0 to 3) + 2 machines x 6
    end)

    it("gives a 2 x 2 machine only one output inserter, because the layout has room for size - 1", function()
      _G.prototypes = fake_prototypes{
        inserter_rotation_speed = 0.014, -- 50.4 items a minute
        machines = {["assembling-machine-1"] = a_machine{crafting_speed = 0.5, size = 2}},
        recipes = {["iron-gear-wheel"] = doubling},
      }

      local result = generator.generate("iron-gear-wheel", 100)

      assert.are.equal(2, count_named(result.entities, "assembling-machine-1")) -- one output inserter moves 50.4, so 100 / 50.4 = 1.98
      assert.are.equal(4, count_named(result.entities, "inserter")) -- 2 machines x (1 in + 1 out)
    end)

    it("allows 800 items a minute with 8 machines, because the two output lanes each carry 8 x 50.4", function()
      _G.prototypes = fake_prototypes{
        belt_speed = 0.03125,
        inserter_rotation_speed = 0.014,
        machines = {["assembling-machine-1"] = assembler},
        recipes = {["iron-gear-wheel"] = doubling},
      }

      local result = generator.generate("iron-gear-wheel", 800)

      assert.are.equal(8, count_named(result.entities, "assembling-machine-1")) -- 800 / 100.8 = 7.94
    end)

    it("refuses 810 items a minute, naming 806.4 as the most, because a ninth machine would overfill a lane", function()
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

    it("says to put one ingredient on each lane, in the recipe's order", function()
      _G.prototypes = fake_prototypes{
        inserter_rotation_speed = 0.014, -- 50.4 items a minute
        machines = {["assembling-machine-1"] = assembler},
        recipes = {["iron-gear-wheel"] = two_ingredients},
      }

      local result = generator.generate("iron-gear-wheel", 50)

      assert.are.same({
        "blueprint-generation.generated",
        "2",                                    -- machines
        {"entity-name.assembling-machine-1"},
        "50.4",                                 -- 2 x 25.2 achieved: 240 items a minute at full speed, but two inserters move 100.8, so 60 x 100.8 / 240
        {"item-name.iron-gear-wheel"},
        "50",                                   -- what was asked for
        {"item-name.iron-plate"},
        {"item-name.copper-cable"},
      }, result.message)
    end)

    it("refuses 130 items a minute, naming 126 as the most, because the cable lane fills with 5 machines", function()
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

  describe("refusals", function()
    it("refuses an item that is not supported", function()
      _G.prototypes = fake_prototypes{}

      local result, error_message = generator.generate("copper-cable", 10)

      assert.is_nil(result)
      assert.are.same({"blueprint-generation.error-unsupported-item"}, error_message)
    end)

    it("refuses when a building prototype is missing", function()
      _G.prototypes = fake_prototypes{
        missing_entities = {"inserter"},
        recipes = {["iron-plate"] = a_recipe{energy = 3.2, ingredients = {amount_of(1, "iron-ore")}, products = {amount_of(1, "iron-plate")}}},
      }

      local result, error_message = generator.generate("iron-plate", 10)

      assert.is_nil(result)
      assert.are.same({"blueprint-generation.error-missing-prototype"}, error_message)
    end)

    it("refuses when the recipe is missing", function()
      _G.prototypes = fake_prototypes{recipes = {}}

      local result, error_message = generator.generate("iron-plate", 10)

      assert.is_nil(result)
      assert.are.same({"blueprint-generation.error-missing-prototype"}, error_message)
    end)

    it("refuses two ingredients on top of the fuel, because three items do not fit on two lanes", function()
      _G.prototypes = fake_prototypes{
        recipes = {["iron-plate"] = a_recipe{energy = 3.2, ingredients = {amount_of(1, "iron-ore"), amount_of(1, "coal")}, products = {amount_of(1, "iron-plate")}}},
      }

      local result, error_message = generator.generate("iron-plate", 10)

      assert.is_nil(result)
      assert.are.same({"blueprint-generation.error-unsupported-recipe"}, error_message)
    end)

    it("refuses a machine that cannot craft", function()
      _G.prototypes = fake_prototypes{
        furnace_speed = false,
        recipes = {["iron-plate"] = a_recipe{energy = 3.2, ingredients = {amount_of(1, "iron-ore")}, products = {amount_of(1, "iron-plate")}}},
      }

      local result, error_message = generator.generate("iron-plate", 10)

      assert.is_nil(result)
      assert.are.same({"blueprint-generation.error-missing-prototype"}, error_message)
    end)

    it("refuses an inserter entity without a rotation speed", function()
      _G.prototypes = fake_prototypes{
        inserter_rotation_speed = false,
        recipes = {["iron-plate"] = a_recipe{energy = 3.2, ingredients = {amount_of(1, "iron-ore")}, products = {amount_of(1, "iron-plate")}}},
      }

      local result, error_message = generator.generate("iron-plate", 10)

      assert.is_nil(result)
      assert.are.same({"blueprint-generation.error-missing-prototype"}, error_message)
    end)

    it("refuses a belt entity without a belt speed", function()
      _G.prototypes = fake_prototypes{
        belt_speed = false,
        recipes = {["iron-plate"] = a_recipe{energy = 3.2, ingredients = {amount_of(1, "iron-ore")}, products = {amount_of(1, "iron-plate")}}},
      }

      local result, error_message = generator.generate("iron-plate", 10)

      assert.is_nil(result)
      assert.are.same({"blueprint-generation.error-missing-prototype"}, error_message)
    end)
  end)
end)
