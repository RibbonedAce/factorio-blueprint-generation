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
local config = require("scripts.config")
local validator = require("spec.support.blueprint_validator")
local tracer = require("spec.support.belt_tracer")
local grid = require("scripts.grid")

local fake_prototypes = builders.fake_prototypes
local a_recipe = builders.a_recipe
local a_machine = builders.a_machine
local fake_force = builders.fake_force
local amount_of = builders.amount_of
local fluid_of = builders.fluid_of

-- The message for a blueprint that is ready: how much of the product it makes a minute, then the raw
-- items, the fuel and the fluids as {item, amount a minute} pairs, in the order the message lists them (a fluid has "fluid" as a
-- third entry).
local function ready_message(product, per_minute, raws)
  local list = {""}
  for index, raw in ipairs(raws) do
    if index > 1 then
      list[#list + 1] = ", "
    end
    list[#list + 1] = {"blueprint-generation.raw-amount", raw[2], {(raw[3] == "fluid" and "fluid-name." or "item-name.") .. raw[1]}}
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

local entities_named = builders.entities_named
local count_named = builders.count_named

-- What the generator tells the layout about the stages of a blueprint: the root stage `rows.build` or `rows.build_pure` is given.
---@param item string
---@param rate number
---@param force table
---@return table
local function layout_given(item, rate, force)
  local rows = require("scripts.rows")
  local given
  local function remembering(build)
    return function(root, ...)
      given = root
      return build(root, ...)
    end
  end
  builders.with_replaced(rows, "build", remembering(rows.build), function()
    builders.with_replaced(rows, "build_pure", remembering(rows.build_pure), function()
      generator.generate(item, rate, force)
    end)
  end)
  return given
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
        local column = grid.top_left_tile(entity.position).x
        if entity.name == "inserter" and column == 1 then
          input_column = input_column + 1
        elseif entity.name == "inserter" and column == 5 then
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

      local tiles = {}
      for _, entity in ipairs(result.entities) do
        if entity.name == "assembling-machine-1" then
          tiles[#tiles + 1] = grid.top_left_tile(entity.position, 3, 3)
        end
      end
      assert.are.same({{x = 2, y = 0}, {x = 2, y = 3}}, tiles) -- 3 wide from column 2; rows 0 to 2, then 3 to 5
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
      return fake_prototypes(builders.merged({
        furnace_speed = 1,
        machines = {["assembling-machine-1"] = assembler},
        recipes = {["iron-plate"] = plate, ["iron-gear-wheel"] = gear},
      }, overrides))
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

    describe("a recipe the config lists whose name is not the name of what it makes", function()
      before_each(function()
        config.recipes["pipe-from-plates"] = true
      end)

      after_each(function()
        config.recipes["pipe-from-plates"] = nil
      end)

      it("is set by its own name as the recipe of the machines", function()
        local pipe_recipe = a_recipe{energy = 0.5, ingredients = {amount_of(1, "iron-plate")}, products = {amount_of(1, "pipe")}}
        _G.prototypes = gear_game{recipes = {["iron-plate"] = plate, ["pipe-from-plates"] = pipe_recipe}}

        local result = generator.generate("pipe-from-plates", 10)

        local assembler
        for _, entity in ipairs(result.entities) do
          if entity.name == "assembling-machine-1" then
            assembler = entity
          end
        end
        assert.are.equal("pipe-from-plates", assembler.recipe)
      end)
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

    local function gear_recipe()
      return a_recipe{energy = 0.5, ingredients = {amount_of(2, "iron-plate")}, products = {amount_of(1, "iron-gear-wheel")}}
    end

    it("builds a step with one made ingredient that is itself made from two, its column beside the column of the two", function()
      local gear_of_a_circuit = a_recipe{energy = 0.5, ingredients = {amount_of(1, "electronic-circuit")}, products = {amount_of(1, "iron-gear-wheel")}}
      _G.prototypes = circuit_game{
        ["iron-plate"] = iron_plate, ["copper-plate"] = copper_plate, ["copper-cable"] = cable,
        ["electronic-circuit"] = circuit, ["iron-gear-wheel"] = gear_of_a_circuit,
      }
      local catalog = builders.a_catalog{machine_size = 2, machine_needs_power = false}
      catalog["assembling-machine-1"] = {kind = "machine", width = 3, height = 3, needs_power = true}

      local result = generator.generate("iron-gear-wheel", 10)

      assert.are.same({}, validator.validate(result.entities, catalog))
    end)

    it("refuses the request when a step has one made ingredient and a raw one and the made one is itself made from two, naming the item", function()
      local gear_of_a_circuit = a_recipe{energy = 0.5, ingredients = {amount_of(1, "electronic-circuit"), amount_of(1, "stone")}, products = {amount_of(1, "iron-gear-wheel")}}
      _G.prototypes = circuit_game{
        ["iron-plate"] = iron_plate, ["copper-plate"] = copper_plate, ["copper-cable"] = cable,
        ["electronic-circuit"] = circuit, ["iron-gear-wheel"] = gear_of_a_circuit,
      }

      local result, error_message = generator.generate("iron-gear-wheel", 10)

      assert.is_nil(result)
      assert.are.same({"blueprint-generation.error-chain-too-complex", {"item-name.iron-gear-wheel"}}, error_message)
    end)

    it("still builds a furnace that burns fuel on top of a step with one input, which is a chain", function()
      local brick_of_a_gear = a_recipe{energy = 3.2, ingredients = {amount_of(1, "iron-gear-wheel")}, products = {amount_of(1, "stone-brick")}, category = "smelting"}
      _G.prototypes = circuit_game{
        ["iron-plate"] = iron_plate, ["iron-gear-wheel"] = gear_recipe(), ["stone-brick"] = brick_of_a_gear,
      }
      local catalog = builders.a_catalog{machine_size = 2, machine_needs_power = false}
      catalog["assembling-machine-1"] = {kind = "machine", width = 3, height = 3, needs_power = true}

      local result = generator.generate("stone-brick", 10, fake_force{})

      assert.are.same({}, validator.validate(result.entities, catalog))
    end)

    it("refuses a furnace that burns fuel on top of a step with several inputs: its fuel would have no belt of its own to ride", function()
      local brick_of_a_circuit = a_recipe{energy = 3.2, ingredients = {amount_of(1, "electronic-circuit")}, products = {amount_of(1, "stone-brick")}, category = "smelting"}
      _G.prototypes = circuit_game{
        ["iron-plate"] = iron_plate, ["copper-plate"] = copper_plate, ["copper-cable"] = cable,
        ["electronic-circuit"] = circuit, ["stone-brick"] = brick_of_a_circuit,
      }

      local result, error_message = generator.generate("stone-brick", 10, fake_force{})

      assert.is_nil(result)
      assert.are.same({"blueprint-generation.error-chain-fuel", {"item-name.stone-brick"}}, error_message)
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

  describe("a recipe with three made ingredients, so the final machines take from woven belts", function()
    -- A furnace makes 18.75 plates a minute (speed 1, 3.2 s), or 18.75 bricks from 2 stone each. An assembler (speed 0.5,
    -- 3x3) crafts every 1 s. Gears, 2 plates each, would eat 120 plates a minute, but the two plain inserters of a gear
    -- assembler move 100.8: 50.4 gears a minute. "Inserters" (the recipe is a stand-in) take a gear, a brick and a plate each,
    -- 60 of each a minute at full speed; a plain inserter moves 50.4 items a minute, and a machine has three input slots
    -- for its woven belts. The gear and the brick on belt a with two inserters, the plate on belt b with one: 100.8 / 120 and
    -- 50.4 / 60 are 0.84 each, so 50.4 inserters a minute for each final assembler. The woven belts are made of splitters and
    -- underground belts, so the force has to have them, and `plain` has the plain inserter only.
    local plain = fake_force{locked = {"fast-inserter"}}
    local plate = a_recipe{energy = 3.2, ingredients = {amount_of(1, "iron-ore")}, products = {amount_of(1, "iron-plate")}, category = "smelting"}
    local brick = a_recipe{energy = 3.2, ingredients = {amount_of(2, "stone")}, products = {amount_of(1, "stone-brick")}, category = "smelting"}
    local gear = a_recipe{energy = 0.5, ingredients = {amount_of(2, "iron-plate")}, products = {amount_of(1, "iron-gear-wheel")}}
    local inserter = a_recipe{
      energy = 0.5, ingredients = {amount_of(1, "iron-gear-wheel"), amount_of(1, "stone-brick"), amount_of(1, "iron-plate")},
      products = {amount_of(1, "inserter")},
    }

    local function inserter_game(extra)
      return fake_prototypes(builders.merged({
        furnace_speed = 1,
        machines = {["assembling-machine-1"] = a_machine{crafting_speed = 0.5, size = 3}},
        recipes = {["iron-plate"] = plate, ["stone-brick"] = brick, ["iron-gear-wheel"] = gear, ["inserter"] = inserter},
      }, extra))
    end

    it("builds the machines of every step: furnaces for the plates of the gears, the bricks and the plates, assemblers for the gears and the inserters", function()
      _G.prototypes = inserter_game()

      local result = generator.generate("inserter", 36, plain)

      assert.are.equal(8, count_named(result.entities, "stone-furnace")) -- 72 plates for 36 gears / 18.75 = 3.8, 36 bricks / 18.75 = 1.9, 36 plates / 18.75 = 1.9
      assert.are.equal(2, count_named(result.entities, "assembling-machine-1")) -- one for the gears, one for the inserters
    end)

    it("builds a final assembler for what its plain inserters move, with no long-handed inserter", function()
      _G.prototypes = inserter_game()

      local result = generator.generate("inserter", 100, plain)

      local finals = 0
      for _, entity in ipairs(result.entities) do
        if entity.recipe == "inserter" then
          finals = finals + 1
        end
      end
      assert.are.same({2, 0}, {finals, count_named(result.entities, "long-handed-inserter")}) -- 100 / 50.4 = 1.98 final assemblers
    end)

    it("describes the blueprint with the machines of every step, each after the steps that feed it", function()
      _G.prototypes = inserter_game()

      local result = generator.generate("inserter", 36, plain)

      -- The final assembler makes 50.4 a minute, more than the 36: the two brick furnaces, 37.5, are what limits the tree.
      assert.are.equal(
        "inserter: 37.5 per minute from 4 x stone-furnace, 1 x assembling-machine-1, 2 x stone-furnace, 2 x stone-furnace, 1 x assembling-machine-1",
        result.description)
    end)

    it("adds up the same raw item used by two branches, and the fuel of every furnace", function()
      _G.prototypes = inserter_game()

      local result = generator.generate("inserter", 36, plain)

      -- 37.5 inserters (what the 2 brick furnaces make): 37.5 gears (75 plates), 37.5 bricks (75 stone) and 37.5 plates, so
      -- 75 + 37.5 iron ore and 75 stone. All 8 furnaces (4 for the plates of the gears, 2 for the bricks, 2 for the plates) work
      -- flat out and burn 1.35 coal a minute each: 10.8.
      assert.are.same(ready_message("inserter", "37.5", {{"iron-ore", "112.5"}, {"stone", "75"}, {"coal", "10.8"}})[4], result.message[4])
    end)

    it("sets the recipe of every assembling machine and leaves the furnaces to pick their own", function()
      _G.prototypes = inserter_game()

      local result = generator.generate("inserter", 36, plain)

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

      local result = generator.generate("inserter", 100, plain)

      assert.are.same({}, validator.validate(result.entities, catalog))
    end)

    it("names the most a lane carries when the lane of the bricks fills first", function()
      _G.prototypes = inserter_game()

      assert.are.same({"blueprint-generation.max-rate", "225"}, generator.max_rate_message("inserter", plain)) -- 450 stone, 2 for each brick
    end)

    it("refuses the rate when it is more than that", function()
      _G.prototypes = inserter_game()

      local result, error_message = generator.generate("inserter", 226, plain)

      assert.is_nil(result)
      assert.are.same({"blueprint-generation.error-rate-too-high", "225"}, error_message)
    end)

    it("builds the recipe when the game has no long-handed inserter: the blueprint has none", function()
      _G.prototypes = inserter_game{missing_entities = {"long-handed-inserter"}}

      local result = generator.generate("inserter", 100, plain)

      assert.is_not_nil(result)
    end)

    describe("when the blueprint cannot weave its belts: a long-handed inserter takes from the second belt", function()
      -- The woven belts are made of splitters and underground belts, so they need a force that has researched both, an
      -- underground belt that spans the longest hop of belt a, and a pole that powers two tiles away. Without them the
      -- final machines have a plain inserter for belt a and a long-handed one for belt b, one column further out, and two
      -- input slots, not three: the gear alone on belt a (50.4 / 60 = 0.84), the brick and the plate on belt b
      -- (72 / 120 = 0.6): 0.6, so 36 inserters a minute for each final assembler.
      local LONG = "long-handed-inserter"

      it("gives each final assembler a long-handed inserter, and sizes the machines by the speed of that inserter, when no force is given", function()
        _G.prototypes = inserter_game()

        local result = generator.generate("inserter", 100)

        assert.are.equal(3, count_named(result.entities, LONG)) -- 100 / 36 = 2.8 final assemblers
      end)

      it("builds them when the force has not researched the splitter", function()
        _G.prototypes = inserter_game()

        local result = generator.generate("inserter", 100, fake_force{locked = {"splitter", "fast-inserter"}})

        assert.are.equal(3, count_named(result.entities, LONG))
      end)

      it("builds them when the force has not researched the underground belt", function()
        _G.prototypes = inserter_game()

        local result = generator.generate("inserter", 100, fake_force{locked = {"underground-belt", "fast-inserter"}})

        assert.are.equal(3, count_named(result.entities, LONG))
      end)

      it("builds them when the underground belt spans one tile less than the longest hop of belt a", function()
        _G.prototypes = inserter_game{underground_distance = 4}

        local result = generator.generate("inserter", 100, plain)

        assert.are.equal(3, count_named(result.entities, LONG))
      end)

      it("weaves the belts instead when the underground belt spans exactly the longest hop of belt a", function()
        _G.prototypes = inserter_game{underground_distance = 5}

        local result = generator.generate("inserter", 100, plain)

        assert.are.equal(0, count_named(result.entities, LONG))
      end)

      it("builds them when the pole powers only one tile away, which leaves inserters beside woven belts without power", function()
        _G.prototypes = inserter_game{small_pole_supply_distance = 1.5}

        local result = generator.generate("inserter", 100, fake_force{locked = {"fast-inserter", "medium-electric-pole"}})

        assert.are.equal(3, count_named(result.entities, LONG))
      end)

      it("weaves the belts instead when the pole powers two tiles away, which two woven belts need", function()
        _G.prototypes = inserter_game{small_pole_supply_distance = 2}

        local result = generator.generate("inserter", 100, fake_force{locked = {"fast-inserter", "medium-electric-pole"}})

        assert.are.equal(0, count_named(result.entities, LONG))
      end)

      it("builds the machines of every step: furnaces for the plates of the gears, the bricks and the plates, assemblers for the gears and the inserters", function()
        _G.prototypes = inserter_game()

        local result = generator.generate("inserter", 36)

        assert.are.equal(8, count_named(result.entities, "stone-furnace")) -- 72 plates for 36 gears / 18.75 = 3.8, 36 bricks / 18.75 = 1.9, 36 plates / 18.75 = 1.9
        assert.are.equal(2, count_named(result.entities, "assembling-machine-1")) -- one for the gears, one for the inserters
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

        assert.are.equal(4, count_named(result.entities, LONG))
      end)

      it("plans with the plain inserter's speed when the game has no long-handed inserter, and refuses nothing", function()
        _G.prototypes = inserter_game{missing_entities = {LONG}}

        local result = generator.generate("inserter", 100)

        assert.are.equal(4, count_named(result.entities, LONG)) -- the blueprint still has them, as 25.2 a minute machines
      end)

      it("sizes the machines by the stack size of the long-handed inserter too, once the force has researched the inserter capacity bonus", function()
        _G.prototypes = inserter_game()

        local result = generator.generate("inserter", 100, fake_force{locked = {"splitter", "fast-inserter"}, inserter_stack_size_bonus = 1})

        -- belt a has the gear, 60 a minute, which one plain inserter moves (90.6); belt b the brick and the plate, 120, which one
        -- long-handed inserter moves (2 items in 50 + 8 ticks, 124.1): each final assembler runs at full speed, 100 / 60 = 1.67
        assert.are.equal(2, count_named(result.entities, LONG))
      end)

      it("takes the stack size bonus built into the long-handed inserter from the game", function()
        _G.prototypes = inserter_game{inserter_stacks = {[LONG] = {built_in = 1}}}

        local result = generator.generate("inserter", 100)

        -- the long-handed inserter moves 124.1 a minute, enough for belt b's 120, but the plain one 50.4 of the gear's 60: 84%, 50.4 a minute, 100 / 50.4 = 1.98
        assert.are.equal(2, count_named(result.entities, LONG))
      end)

      it("plans with the plain inserter's stack size when the game has no long-handed inserter", function()
        _G.prototypes = inserter_game{missing_entities = {LONG}}

        local result = generator.generate("inserter", 100, fake_force{locked = {"splitter", "fast-inserter"}, inserter_stack_size_bonus = 1})

        -- belt b's 120 a minute is more than the plain inserter moves with the bonus (90.6): 75.5%, 45.3 a minute, 100 / 45.3 = 2.2
        assert.are.equal(3, count_named(result.entities, LONG))
      end)

      it("builds a recipe with one input belt when the game has no long-handed inserter", function()
        _G.prototypes = inserter_game{missing_entities = {LONG}}

        local result = generator.generate("iron-gear-wheel", 10)

        assert.is_not_nil(result)
        assert.are.equal(0, count_named(result.entities, LONG))
      end)

      it("builds a recipe with one input belt all the same, for a force with no splitter", function()
        _G.prototypes = inserter_game()

        local result = generator.generate("iron-gear-wheel", 10, fake_force{locked = {"splitter"}})

        assert.is_not_nil(result)
      end)

      it("refuses a step that eats three raw items as a recipe it cannot build: it has no made ingredient to put on a second belt", function()
        local gear = a_recipe{
          energy = 0.5, ingredients = {amount_of(1, "iron-ore"), amount_of(1, "copper-ore"), amount_of(1, "stone")},
          products = {amount_of(1, "iron-gear-wheel")},
        }
        _G.prototypes = fake_prototypes{
          machines = {["assembling-machine-1"] = a_machine{crafting_speed = 0.5, size = 3}},
          recipes = {["iron-gear-wheel"] = gear},
        }

        local result, error_message = generator.generate("iron-gear-wheel", 10)

        assert.are.same({nil, {"blueprint-generation.error-unsupported-recipe"}}, {result, error_message})
      end)

      it("refuses a step that eats five raw items as a recipe it cannot build too, not as one that needs three woven belts", function()
        local gear = a_recipe{
          energy = 0.5,
          ingredients = {amount_of(1, "iron-ore"), amount_of(1, "copper-ore"), amount_of(1, "stone"), amount_of(1, "wood"), amount_of(1, "sand")},
          products = {amount_of(1, "iron-gear-wheel")},
        }
        _G.prototypes = fake_prototypes{
          machines = {["assembling-machine-1"] = a_machine{crafting_speed = 0.5, size = 3}},
          recipes = {["iron-gear-wheel"] = gear},
        }

        local result, error_message = generator.generate("iron-gear-wheel", 10)

        assert.are.same({nil, {"blueprint-generation.error-unsupported-recipe"}}, {result, error_message})
      end)
    end)
  end)

  describe("a recipe that takes a fluid, so the machines of the last step have a pipe in the middle row of their input side", function()
    -- Concrete: 1 iron stick, 5 stone bricks and 100 water make 10 concrete in 10 s. An assembling machine 2 (speed 0.75, 3x3)
    -- crafts every 13.33 s, so it makes 45 concrete a minute from 27 items, which one plain inserter (50.4 a minute) moves. A
    -- furnace makes 18.75 bricks a minute from 37.5 stone; an assembling machine 1 (speed 0.5) makes 2 sticks every second.
    -- 90 concrete a minute is 2 machines, 9 crafts: 9 sticks and 45 bricks, so 4.5 plates, 90 stone and 900 water a minute.
    local plate = a_recipe{energy = 3.2, ingredients = {amount_of(1, "iron-ore")}, products = {amount_of(1, "iron-plate")}, category = "smelting"}
    local brick = a_recipe{energy = 3.2, ingredients = {amount_of(2, "stone")}, products = {amount_of(1, "stone-brick")}, category = "smelting"}
    local stick = a_recipe{energy = 0.5, ingredients = {amount_of(1, "iron-plate")}, products = {amount_of(2, "iron-stick")}}
    local gear = a_recipe{energy = 0.5, ingredients = {amount_of(2, "iron-plate")}, products = {amount_of(1, "iron-gear-wheel")}}
    local copper_plate = a_recipe{energy = 3.2, ingredients = {amount_of(1, "copper-ore")}, products = {amount_of(1, "copper-plate")}, category = "smelting"}
    local cable = a_recipe{energy = 0.5, ingredients = {amount_of(1, "copper-plate")}, products = {amount_of(2, "copper-cable")}}

    -- A recipe for concrete, in the category of the machines that take a fluid.
    local function concrete_of(ingredients, energy)
      return a_recipe{energy = energy or 10, ingredients = ingredients, products = {amount_of(10, "concrete")}, category = "crafting-with-fluid"}
    end

    local concrete = concrete_of{amount_of(1, "iron-stick"), amount_of(5, "stone-brick"), fluid_of(100, "water")}
    local base_recipes = {["iron-plate"] = plate, ["stone-brick"] = brick, ["iron-stick"] = stick, ["concrete"] = concrete}

    -- The game with an assembling machine 1 and an assembling machine 2, which has a fluid input unless `options.fluid_input` is false
    -- (or the fluid boxes of `options.fluid_boxes`).
    local function concrete_game(options)
      options = options or {}
      return fake_prototypes{
        furnace_speed = 1,
        machines = {
          ["assembling-machine-1"] = a_machine{crafting_speed = 0.5, size = 3},
          ["assembling-machine-2"] = a_machine{crafting_speed = 0.75, size = 3, fluid_input = options.fluid_input ~= false, fluid_boxes = options.fluid_boxes},
        },
        recipes = options.recipes or base_recipes,
        missing_entities = options.missing_entities,
      }
    end

    local function catalog()
      local entries = builders.a_catalog{machine_size = 2, machine_needs_power = false}
      entries["assembling-machine-1"] = {kind = "machine", width = 3, height = 3, needs_power = true}
      entries["assembling-machine-2"] = {kind = "machine", width = 3, height = 3, needs_power = true, fluid_input = {concrete = true, ["refined-concrete"] = true}} -- it takes no fluid for the sticks
      return entries
    end

    local function machines_taking_fluid(entities)
      local found = {}
      for _, entity in ipairs(entities) do
        if entity.recipe == "concrete" then
          found[#found + 1] = entity
        end
      end
      return found
    end

    it("builds an assembling machine 2 for each machine's worth of concrete, and the machines of the steps before it", function()
      _G.prototypes = concrete_game()

      local result = generator.generate("concrete", 90)

      assert.are.same({2, 1, 4}, {
        count_named(result.entities, "assembling-machine-2"), count_named(result.entities, "assembling-machine-1"), count_named(result.entities, "stone-furnace"),
      })
    end)

    it("describes the blueprint with the machines of every step, each after the steps that feed it", function()
      _G.prototypes = concrete_game()

      local result = generator.generate("concrete", 90)

      assert.are.equal("concrete: 90 per minute from 1 x stone-furnace, 1 x assembling-machine-1, 3 x stone-furnace, 2 x assembling-machine-2", result.description)
    end)

    it("takes a fluid box that is for input and output at once as a fluid input", function()
      _G.prototypes = concrete_game{fluid_boxes = {"input-output"}}

      local result = generator.generate("concrete", 90)

      assert.are.equal(2, #machines_taking_fluid(result.entities))
    end)

    it("faces the machines that take the fluid west, where their fluid connection is", function()
      _G.prototypes = concrete_game()

      local result = generator.generate("concrete", 90)

      local west = defines.direction.west
      assert.are.same({west, west}, {machines_taking_fluid(result.entities)[1].direction, machines_taking_fluid(result.entities)[2].direction})
    end)

    it("builds an underground pipe at each end of the pipe of every machine, and a trunk of pipes along the machines", function()
      _G.prototypes = concrete_game()

      local result = generator.generate("concrete", 90)

      assert.are.same({4, 23}, {count_named(result.entities, "pipe-to-ground"), count_named(result.entities, "pipe")}) -- 5 in the trunk, the rest up and west to the pump
    end)

    it("adds the fluid to what the blueprint takes a minute, after the raw items and the fuel", function()
      _G.prototypes = concrete_game()

      local result = generator.generate("concrete", 90)

      assert.are.same(ready_message("concrete", "90", {{"iron-ore", "4.5"}, {"stone", "90"}, {"coal", "3.56"}, {"water", "900", "fluid"}}), result.message)
    end)

    it("builds a blueprint that passes the validator, with the pipes joined to the machines", function()
      _G.prototypes = concrete_game()

      local result = generator.generate("concrete", 90)

      assert.are.same({}, validator.validate(result.entities, catalog()))
    end)

    for _, rate in ipairs({1, 10, 45, 46, 100, 225, 300}) do
      it("builds a blueprint that passes the validator for " .. rate .. " concrete a minute", function()
        _G.prototypes = concrete_game()

        local result = generator.generate("concrete", rate)

        assert.are.same({}, validator.validate(result.entities, catalog()))
      end)
    end

    it("takes the fluid by pipes in the design that brings in one belt of each material, and names the items of its belts without it", function()
      _G.prototypes = concrete_game()

      local result = generator.generate("concrete", 90, fake_force{})

      assert.are.same(
        ready_message_with_belts("concrete", "90", {{"iron-ore", "4.5"}, {"stone", "90"}, {"coal", "3.56"}, {"water", "900", "fluid"}}, {"coal", "stone", "iron-ore"}),
        result.message)
    end)

    it("builds a blueprint that passes the validator in the design that brings in one belt of each material", function()
      _G.prototypes = concrete_game()
      local entries = catalog()
      entries[builders.POLES.medium.name] = {kind = "pole", width = 1, height = 1, supply_radius = builders.POLES.medium.supply_distance, wire_reach = builders.POLES.medium.wire_distance}

      local result = generator.generate("concrete", 90, fake_force{})

      assert.are.same({}, validator.validate(result.entities, entries))
    end)

    it("puts one pump, with a pole, in the corner where the belts come in: the west end of the pipe along the top", function()
      _G.prototypes = concrete_game()

      local result = generator.generate("concrete", 90)

      local belt_left = math.huge
      for _, belt in ipairs(entities_named(result.entities, "transport-belt")) do
        belt_left = math.min(belt_left, grid.top_left_tile(belt.position).x)
      end
      local pump = entities_named(result.entities, "pump")[1]
      assert.are.same({1, 1, belt_left}, {count_named(result.entities, "pump"), count_named(result.entities, "small-electric-pole") > 0 and 1 or 0, grid.top_left_tile(pump.position, 2, 1).x})
    end)

    it("tells the lamps to keep the tile behind the pump free, which is where the water comes in", function()
      _G.prototypes = concrete_game()
      local lights = require("scripts.lights")
      local original, told = lights.add, nil
      local function spying(entities, options)
        told = options
        return original(entities, options)
      end

      builders.with_replaced(lights, "add", spying, function() generator.generate("concrete", 90, fake_force{}) end)

      assert.are.same({{"transport-belt", "underground-belt"}, {"pump"}}, {told.belts, told.inlets})
    end)

    describe("an iron ore next to the bricks, as the game's concrete takes them: the raw item rides the lane the bricks leave free", function()
      local ore_concrete = concrete_of{amount_of(1, "iron-ore"), amount_of(5, "stone-brick"), fluid_of(100, "water")}
      local ore_recipes = {["stone-brick"] = brick, ["concrete"] = ore_concrete}

      it("builds the machines of both steps: furnaces for the bricks, assembling machines 2 for the concrete", function()
        _G.prototypes = concrete_game{recipes = ore_recipes}

        local result = generator.generate("concrete", 90)

        assert.are.same({2, 0, 3}, {
          count_named(result.entities, "assembling-machine-2"), count_named(result.entities, "assembling-machine-1"), count_named(result.entities, "stone-furnace"),
        }) -- 9 crafts a minute of 45 bricks: 2.4 furnaces
      end)

      it("adds up the stone for the bricks, the ore of the recipe, the coal of the furnaces and the water", function()
        _G.prototypes = concrete_game{recipes = ore_recipes}

        local result = generator.generate("concrete", 90)

        assert.are.same(ready_message("concrete", "90", {{"stone", "90"}, {"iron-ore", "9"}, {"coal", "3.24"}, {"water", "900", "fluid"}}), result.message)
      end)

      it("builds a blueprint that passes the validator, with the pipes joined to the machines", function()
        _G.prototypes = concrete_game{recipes = ore_recipes}

        local result = generator.generate("concrete", 90)

        assert.are.same({}, validator.validate(result.entities, catalog()))
      end)

      it("builds a blueprint that passes the validator in the design that brings in one belt of each material, which names its belts", function()
        _G.prototypes = concrete_game{recipes = ore_recipes}
        local entries = catalog()
        entries[builders.POLES.medium.name] = {kind = "pole", width = 1, height = 1, supply_radius = builders.POLES.medium.supply_distance, wire_reach = builders.POLES.medium.wire_distance}

        local result = generator.generate("concrete", 90, fake_force{})

        assert.are.same({{}, ready_message_with_belts("concrete", "90", {{"stone", "90"}, {"iron-ore", "9"}, {"coal", "3.24"}, {"water", "900", "fluid"}}, {"iron-ore", "stone", "coal"})},
          {validator.validate(result.entities, entries), result.message})
      end)
    end)

    describe("a step that takes a fluid inside another that takes one: refined concrete, whose concrete is made in machines with a pipe too", function()
      -- 20 concrete and 8 iron sticks with 100 water make 10 refined concrete in 15 s. The one machine for 20 a minute takes 28 items
      -- for a craft through two inserters (100.8 a minute) and so makes 2.25 crafts, 22.5 a minute: 225 water, and 45 concrete,
      -- 4.5 crafts and 450 water, which is 675 in all.
      local refined = a_recipe{
        energy = 15, ingredients = {amount_of(20, "concrete"), amount_of(8, "iron-stick"), fluid_of(100, "water")},
        products = {amount_of(10, "refined-concrete")}, category = "crafting-with-fluid",
      }
      local refined_recipes = {["iron-plate"] = plate, ["stone-brick"] = brick, ["iron-stick"] = stick, ["concrete"] = concrete, ["refined-concrete"] = refined}

      it("builds the machines of both steps that take the fluid, one pump for the pipes of both, and a blueprint that passes the validator", function()
        _G.prototypes = concrete_game{recipes = refined_recipes}

        local result = generator.generate("refined-concrete", 20)

        assert.are.same({1, {}}, {count_named(result.entities, "pump"), validator.validate(result.entities, catalog())})
      end)

      it("builds the same in the design that brings in one belt of each material", function()
        _G.prototypes = concrete_game{recipes = refined_recipes}
        local entries = catalog()
        entries[builders.POLES.medium.name] = {kind = "pole", width = 1, height = 1, supply_radius = builders.POLES.medium.supply_distance, wire_reach = builders.POLES.medium.wire_distance}

        local result = generator.generate("refined-concrete", 20, fake_force{})

        assert.are.same({1, {}}, {count_named(result.entities, "pump"), validator.validate(result.entities, entries)})
      end)

      it("adds the water of both steps up, after the raw items and the fuel", function()
        _G.prototypes = concrete_game{recipes = refined_recipes}

        local result = generator.generate("refined-concrete", 20)

        local message = result.message
        local water = message[4][#message[4]]
        assert.are.same({"blueprint-generation.raw-amount", "675", {"fluid-name.water"}}, water)
      end)
    end)

    describe("hazard concrete: one ingredient, the concrete, made in a column beside the column of the concrete", function()
      -- 10 concrete a craft make 10 hazard concrete in 0.25 s: an assembling machine 1 (speed 0.5) crafts every 0.5 s, and its two
      -- plain input inserters (100.8 a minute) feed it about 10 crafts a minute, which is 100 hazard concrete from 100 concrete.
      local hazard = a_recipe{energy = 0.25, ingredients = {amount_of(10, "concrete")}, products = {amount_of(10, "hazard-concrete")}}
      local hazard_recipes = {["iron-plate"] = plate, ["stone-brick"] = brick, ["iron-stick"] = stick, ["concrete"] = concrete, ["hazard-concrete"] = hazard}

      it("builds the machines of the concrete and of the hazard concrete, with one pump for the pipes of the concrete", function()
        _G.prototypes = concrete_game{recipes = hazard_recipes}

        local result = generator.generate("hazard-concrete", 90)

        -- two assembling machines 2 for the concrete, one assembling machine 1 for the iron sticks and one for the hazard concrete
        assert.are.same({2, 2, 1}, {count_named(result.entities, "assembling-machine-2"), count_named(result.entities, "assembling-machine-1"), count_named(result.entities, "pump")})
      end)

      it("builds a blueprint that passes the validator", function()
        _G.prototypes = concrete_game{recipes = hazard_recipes}

        local result = generator.generate("hazard-concrete", 90)

        assert.are.same({}, validator.validate(result.entities, catalog()))
      end)

      it("builds a blueprint that passes the validator in the design that brings in one belt of each material", function()
        _G.prototypes = concrete_game{recipes = hazard_recipes}
        local entries = catalog()
        entries[builders.POLES.medium.name] = {kind = "pole", width = 1, height = 1, supply_radius = builders.POLES.medium.supply_distance, wire_reach = builders.POLES.medium.wire_distance}

        local result = generator.generate("hazard-concrete", 90, fake_force{})

        assert.are.same({}, validator.validate(result.entities, entries))
      end)

      it("adds up the water of the concrete, which is all the hazard concrete takes", function()
        _G.prototypes = concrete_game{recipes = hazard_recipes}

        local result = generator.generate("hazard-concrete", 90)

        assert.are.same({"blueprint-generation.raw-amount", "900", {"fluid-name.water"}}, result.message[4][#result.message[4]])
      end)

      it("builds refined hazard concrete the same way, on top of the refined concrete of two columns that take a fluid", function()
        local refined = a_recipe{
          energy = 15, ingredients = {amount_of(20, "concrete"), amount_of(8, "iron-stick"), fluid_of(100, "water")},
          products = {amount_of(10, "refined-concrete")}, category = "crafting-with-fluid",
        }
        local refined_hazard = a_recipe{energy = 0.25, ingredients = {amount_of(10, "refined-concrete")}, products = {amount_of(10, "refined-hazard-concrete")}}
        _G.prototypes = concrete_game{recipes = {
          ["iron-plate"] = plate, ["stone-brick"] = brick, ["iron-stick"] = stick, ["concrete"] = concrete, ["refined-concrete"] = refined,
          ["refined-hazard-concrete"] = refined_hazard,
        }}

        local result = generator.generate("refined-hazard-concrete", 20)

        assert.are.same({1, {}}, {count_named(result.entities, "pump"), validator.validate(result.entities, catalog())})
      end)
    end)

    describe("more than two items: two woven belts, one inserter on each", function()
      -- A heavy concrete that takes a gear too: the stick and the brick ride belt a, the gear belt b (three lanes in all).
      local heavy = concrete_of{amount_of(1, "iron-stick"), amount_of(5, "stone-brick"), amount_of(1, "iron-gear-wheel"), fluid_of(100, "water")}
      local heavy_recipes = {["iron-plate"] = plate, ["stone-brick"] = brick, ["iron-stick"] = stick, ["iron-gear-wheel"] = gear, ["concrete"] = heavy}

      it("builds it when the force has the splitter and the underground belt, a blueprint that passes the validator", function()
        _G.prototypes = concrete_game{recipes = heavy_recipes}

        local result = generator.generate("concrete", 90, fake_force{})

        assert.are.same({}, validator.validate(result.entities, catalog()))
      end)

      it("builds it with a pipe at every machine", function()
        _G.prototypes = concrete_game{recipes = heavy_recipes}

        local result = generator.generate("concrete", 90, fake_force{})

        assert.are.equal(2 * #machines_taking_fluid(result.entities), count_named(result.entities, "pipe-to-ground"))
      end)

      it("refuses it when the blueprint cannot weave belts, naming the item", function()
        _G.prototypes = concrete_game{recipes = heavy_recipes}

        local result, error_message = generator.generate("concrete", 90)

        assert.is_nil(result)
        assert.are.same({"blueprint-generation.error-fluid-needs-weave", {"item-name.concrete"}}, error_message)
      end)

      it("builds it for four items, two on each belt, a blueprint that passes the validator", function()
        local four = concrete_of{amount_of(1, "iron-stick"), amount_of(5, "stone-brick"), amount_of(1, "iron-gear-wheel"), amount_of(1, "copper-cable"), fluid_of(100, "water")}
        _G.prototypes = concrete_game{recipes = {
          ["iron-plate"] = plate, ["copper-plate"] = copper_plate, ["stone-brick"] = brick, ["iron-stick"] = stick, ["iron-gear-wheel"] = gear,
          ["copper-cable"] = cable, ["concrete"] = four,
        }}

        local result = generator.generate("concrete", 90, fake_force{})

        assert.are.same({}, validator.validate(result.entities, catalog()))
      end)

      it("builds it with one inserter on each belt, however much the machines could eat: they run slower instead", function()
        -- 1 s a craft: a machine would eat 270 items a minute from belt a, which one plain inserter (50.4) is far from, so the
        -- machines are slower and 400 concrete a minute takes two of them (a planner that gave belt a a second inserter would need one)
        local quick = concrete_of({amount_of(1, "iron-stick"), amount_of(5, "stone-brick"), amount_of(1, "iron-gear-wheel"), fluid_of(100, "water")}, 1)
        _G.prototypes = concrete_game{recipes = {["iron-plate"] = plate, ["stone-brick"] = brick, ["iron-stick"] = stick, ["iron-gear-wheel"] = gear, ["concrete"] = quick}}

        local result = generator.generate("concrete", 400, fake_force{})

        assert.are.same({}, validator.validate(result.entities, catalog()))
      end)
    end)

    describe("one made ingredient and a fluid: the step takes a column of its own, with room for its pipes", function()
      -- 5 stone bricks and 100 water make 10 concrete in 10 s: one belt, with the bricks on it, goes to the machines that take the water.
      local bricks_only = concrete_of{amount_of(5, "stone-brick"), fluid_of(100, "water")}
      local bricks_recipes = {["stone-brick"] = brick, ["concrete"] = bricks_only}

      -- What the belt tracer finds wrong with the lanes of the concrete made from bricks and water: the furnaces make the bricks from stone, which the
      -- player supplies, and the machines that take the water eat them.
      local function lane_problems(entities, belts)
        local options = {
          machines = {["stone-furnace"] = {size = 2, eats = {"stone"}, makes = "stone-brick"}, ["assembling-machine-2"] = {size = 3, eats = {"stone-brick"}, makes = "concrete"}},
          raw = {["stone-furnace"] = true}, product = "concrete",
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
          options.underground_reach, options.raw_lanes, options.supplies = 5, {["stone-furnace"] = {"stone", "coal"}}, {}
          for index, item in ipairs(belts) do
            options.supplies[index] = {x = 0, y = rows[index], item = item}
          end
        end
        return tracer.problems(entities, options)
      end

      it("builds the machines of the concrete, one pump for their pipes, and a blueprint that passes the validator", function()
        _G.prototypes = concrete_game{recipes = bricks_recipes}

        local result = generator.generate("concrete", 90)

        assert.are.same({1, {}}, {count_named(result.entities, "pump"), validator.validate(result.entities, catalog())})
      end)

      it("builds the same in the design that brings in one belt of each material", function()
        _G.prototypes = concrete_game{recipes = bricks_recipes}
        local entries = catalog()
        entries[builders.POLES.medium.name] = {kind = "pole", width = 1, height = 1, supply_radius = builders.POLES.medium.supply_distance, wire_reach = builders.POLES.medium.wire_distance}

        local result = generator.generate("concrete", 90, fake_force{})

        assert.are.same({1, {}}, {count_named(result.entities, "pump"), validator.validate(result.entities, entries)})
      end)

      it("carries the bricks to the machines that take the water, in both designs of the belts: the belt tracer finds nothing wrong", function()
        _G.prototypes = concrete_game{recipes = bricks_recipes}

        local original = generator.generate("concrete", 90)
        local new = generator.generate("concrete", 90, fake_force{})

        assert.are.same({}, lane_problems(original.entities))
        assert.are.same({}, lane_problems(new.entities, builders.belts_named(new.message)))
      end)

      it("builds the step inside another step too, where it is a column that the column of that step eats from", function()
        local wrapped = a_recipe{energy = 0.5, ingredients = {amount_of(1, "concrete"), amount_of(1, "iron-plate")}, products = {amount_of(1, "iron-gear-wheel")}}
        _G.prototypes = concrete_game{recipes = {["iron-plate"] = plate, ["stone-brick"] = brick, ["concrete"] = bricks_only, ["iron-gear-wheel"] = wrapped}}

        local result = generator.generate("iron-gear-wheel", 10)

        assert.are.same({1, {}}, {count_named(result.entities, "pump"), validator.validate(result.entities, catalog())})
      end)
    end)

    describe("refused", function()
      local function refusal_for(game_options, rate, force)
        _G.prototypes = concrete_game(game_options)
        local result, error_message = generator.generate("concrete", rate or 90, force)
        assert.is_nil(result)
        return error_message
      end

      it("refuses a recipe that takes two fluids", function()
        local two_fluids = concrete_of{amount_of(1, "iron-stick"), amount_of(5, "stone-brick"), fluid_of(100, "water"), fluid_of(10, "steam")}

        local error_message = refusal_for{recipes = {["iron-plate"] = plate, ["stone-brick"] = brick, ["iron-stick"] = stick, ["concrete"] = two_fluids}}

        assert.are.same({"blueprint-generation.error-fluid-unsupported", {"item-name.concrete"}}, error_message)
      end)

      it("refuses a machine that has no fluid input", function()
        local error_message = refusal_for{fluid_input = false}

        assert.are.same({"blueprint-generation.error-fluid-unsupported", {"item-name.concrete"}}, error_message)
      end)

      it("refuses a machine whose only fluid box is for output: it gives a fluid and takes none", function()
        local error_message = refusal_for{fluid_boxes = {"output"}}

        assert.are.same({"blueprint-generation.error-fluid-unsupported", {"item-name.concrete"}}, error_message)
      end)

      it("refuses a recipe with five items, which two belts do not carry", function()
        local five = concrete_of{
          amount_of(1, "iron-stick"), amount_of(5, "stone-brick"), amount_of(1, "iron-gear-wheel"), amount_of(1, "copper-cable"), amount_of(1, "iron-plate"),
          fluid_of(100, "water"),
        }
        local recipes = {
          ["iron-plate"] = plate, ["copper-plate"] = copper_plate, ["stone-brick"] = brick, ["iron-stick"] = stick, ["iron-gear-wheel"] = gear,
          ["copper-cable"] = cable, ["concrete"] = five,
        }

        local error_message = refusal_for({recipes = recipes}, 90, fake_force{})

        assert.are.same({"blueprint-generation.error-fluid-unsupported", {"item-name.concrete"}}, error_message)
      end)

      it("refuses a game that has no pipe", function()
        local error_message = refusal_for{missing_entities = {"pipe"}}

        assert.are.same({"blueprint-generation.error-missing-prototype"}, error_message)
      end)

      it("refuses a game that has no underground pipe", function()
        local error_message = refusal_for{missing_entities = {"pipe-to-ground"}}

        assert.are.same({"blueprint-generation.error-missing-prototype"}, error_message)
      end)

      it("refuses a game that has no pump", function()
        local error_message = refusal_for{missing_entities = {"pump"}}

        assert.are.same({"blueprint-generation.error-missing-prototype"}, error_message)
      end)
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

      assert.are.same({"blueprint-generation.error-unsupported-pick"}, generator.max_rate_message("advanced-circuit"))
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
      return builders.belt_directions(entities, 5)
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

    it("does not look at the long-handed inserter when the blueprint takes its second belt with them, without the splitter", function()
      _G.prototypes = game()

      local result = generator.generate("inserter", 36, fake_force{locked = {"long-handed-inserter", "splitter"}})

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

      assert.is_not_nil(generator.generate("iron-gear-wheel", 36))
      assert.are.same({"blueprint-generation.max-rate", "225"}, generator.max_rate_message("iron-gear-wheel"))
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

  describe("the tiers of a building: the last that the force has unlocked builds", function()
    local plate = a_recipe{energy = 3.2, ingredients = {amount_of(1, "iron-ore")}, products = {amount_of(1, "iron-plate")}, category = "smelting"}
    local slow_pipe = a_recipe{energy = 3, ingredients = {amount_of(1, "iron-plate")}, products = {amount_of(1, "pipe")}}

    -- The game has the assembling machines 1, 2 and a 3, which the config gets as a third tier for the test.
    local function three_assemblers(size_of_3)
      local machines = {
        ["assembling-machine-1"] = a_machine{crafting_speed = 0.5, size = 3},
        ["assembling-machine-2"] = a_machine{crafting_speed = 0.75, size = 3},
        ["assembling-machine-3"] = a_machine{crafting_speed = 1.25, size = size_of_3 or 3},
      }
      return fake_prototypes{furnace_speed = 1, machines = machines, recipes = {["iron-plate"] = plate, ["pipe"] = slow_pipe}}
    end

    -- Which of the assembling machines the blueprint is built with.
    local function assemblers(result)
      return {count_named(result.entities, "assembling-machine-1") > 0, count_named(result.entities, "assembling-machine-2") > 0,
        count_named(result.entities, "assembling-machine-3") > 0}
    end

    before_each(function()
      table.insert(config.machines.crafting.tiers, "assembling-machine-3")
    end)

    after_each(function()
      table.remove(config.machines.crafting.tiers)
    end)

    it("builds with the third tier when the force has unlocked all of them", function()
      _G.prototypes = three_assemblers()

      local result = generator.generate("pipe", 30, fake_force{})

      assert.are.same({false, false, true}, assemblers(result))
    end)

    it("builds with the second tier when the third is locked", function()
      _G.prototypes = three_assemblers()

      local result = generator.generate("pipe", 30, fake_force{locked = {"assembling-machine-3"}})

      assert.are.same({false, true, false}, assemblers(result))
    end)

    it("builds with the first tier when the second and the third are locked", function()
      _G.prototypes = three_assemblers()

      local result = generator.generate("pipe", 30, fake_force{locked = {"assembling-machine-2", "assembling-machine-3"}})

      assert.are.same({true, false, false}, assemblers(result))
    end)

    it("builds with the third tier when only the second is locked: the best the force has unlocked", function()
      _G.prototypes = three_assemblers()

      local result = generator.generate("pipe", 30, fake_force{locked = {"assembling-machine-2"}})

      assert.are.same({false, false, true}, assemblers(result))
    end)

    it("builds with a machine tier of another size than the first: the size is the game's to say", function()
      _G.prototypes = three_assemblers(2)

      local result = generator.generate("pipe", 30, fake_force{})

      assert.are.same({false, false, true}, assemblers(result))
    end)

    it("builds with a pole tier of another size than the first", function()
      _G.prototypes = three_assemblers()
      _G.prototypes.entity["medium-electric-pole"].tile_width = 3

      local result = generator.generate("pipe", 30, fake_force{})

      assert.is_true(count_named(result.entities, "medium-electric-pole") > 0)
    end)

    it("builds with a belt tier whose pieces are of another size than the first's", function()
      _G.prototypes = fake_prototypes{
        furnace_speed = 1, fast_belts = true, machines = {["assembling-machine-1"] = a_machine{crafting_speed = 0.5, size = 3}},
        recipes = {["iron-plate"] = plate, ["pipe"] = slow_pipe},
      }
      _G.prototypes.entity["fast-splitter"].tile_width = 2

      local result = generator.generate("pipe", 30, fake_force{})

      assert.is_true(count_named(result.entities, "fast-transport-belt") > 0)
    end)
  end)

  describe("the steel furnace, once the force has unlocked it", function()
    -- A stone furnace makes 18.75 plates a minute from 3.2 s; the steel furnace, at twice the speed, 37.5.
    local plate = a_recipe{energy = 3.2, ingredients = {amount_of(1, "iron-ore")}, products = {amount_of(1, "iron-plate")}, category = "smelting"}

    local function plate_game(steel_furnace)
      local machines = {}
      if steel_furnace then
        machines["steel-furnace"] = steel_furnace
      end
      return fake_prototypes{furnace_speed = 1, machines = machines, recipes = {["iron-plate"] = plate}}
    end

    local function a_steel_furnace()
      return a_machine{type = "furnace", crafting_speed = 2, size = 2, burns = {"chemical"}}
    end

    -- How many stone furnaces and steel furnaces the blueprint has.
    local function furnaces(result)
      return {count_named(result.entities, "stone-furnace"), count_named(result.entities, "steel-furnace")}
    end

    it("builds with it, and with half as many furnaces as the stone furnace takes", function()
      _G.prototypes = plate_game(a_steel_furnace())

      local result = generator.generate("iron-plate", 75, fake_force{})

      assert.are.same({0, 2}, furnaces(result)) -- 75 / 37.5; the stone furnaces would be 4
    end)

    it("leaves the recipe to the furnace, which picks its own", function()
      _G.prototypes = plate_game(a_steel_furnace())

      local result = generator.generate("iron-plate", 75, fake_force{})

      local recipes = {}
      for _, entity in ipairs(result.entities) do
        if entity.name == "steel-furnace" then
          recipes[#recipes + 1] = entity.recipe or "none"
        end
      end
      assert.are.same({"none", "none"}, recipes)
    end)

    it("builds with the stone furnace when the force has not unlocked it", function()
      _G.prototypes = plate_game(a_steel_furnace())

      local result = generator.generate("iron-plate", 75, fake_force{locked = {"steel-furnace"}})

      assert.are.same({4, 0}, furnaces(result))
    end)

    it("builds with the stone furnace when the game has no steel furnace", function()
      _G.prototypes = plate_game(nil)

      local result = generator.generate("iron-plate", 75, fake_force{})

      assert.are.same({4, 0}, furnaces(result))
    end)

    it("builds with the stone furnace when no force is given", function()
      _G.prototypes = plate_game(a_steel_furnace())

      local result = generator.generate("iron-plate", 75)

      assert.are.same({4, 0}, furnaces(result))
    end)

    it("builds a blueprint that passes the validator, with every furnace fed, emptied and powered", function()
      _G.prototypes = plate_game(a_steel_furnace())
      local catalog = builders.a_catalog{machine_size = 2, machine_needs_power = false}
      catalog["steel-furnace"] = {kind = "machine", width = 2, height = 2, needs_power = false}

      local result = generator.generate("iron-plate", 75, fake_force{})

      assert.are.same({}, validator.validate(result.entities, catalog))
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
      return fake_prototypes(builders.merged({
        furnace_speed = 1,
        machines = {["assembling-machine-1"] = a_machine{crafting_speed = 0.5, size = 3}},
        recipes = {
          ["iron-plate"] = iron_plate, ["copper-plate"] = copper_plate,
          ["copper-cable"] = cable, ["electronic-circuit"] = circuit,
        },
      }, options))
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

      it("makes up to twice as many: the lanes of the fast belt carry twice what the basic belt's carry", function()
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

      it("builds it when the fast underground belt spans exactly the fewest tiles the hops need", function()
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

    describe("display panels, put beside the belts that come in once the force has unlocked the display panel", function()
      -- The items the display panels show, from the top of the blueprint down.
      local function icons_of(entities)
        local icons = {}
        for _, entity in ipairs(entities) do
          if entity.name == "display-panel" then
            icons[#icons + 1] = entity.icon.name
          end
        end
        return icons
      end

      it("puts a panel with the item of each belt that comes in, from the top down", function()
        _G.prototypes = circuit_game()

        local result = generator.generate("electronic-circuit", 50, fake_force{})

        assert.are.same({"coal", "copper-ore", "iron-ore"}, icons_of(result.entities))
      end)

      it("builds a blueprint with the panels that passes the validator", function()
        _G.prototypes = circuit_game()
        local catalog = builders.a_catalog{machine_size = 2, machine_needs_power = false}
        catalog["assembling-machine-1"] = {kind = "machine", width = 3, height = 3, needs_power = true}

        local result = generator.generate("electronic-circuit", 100, fake_force{})

        assert.are.same({}, validator.validate(result.entities, catalog))
      end)

      local without_panels = {
        {label = "the force has not unlocked the display panel", force = fake_force{locked = {"display-panel"}}},
        {label = "the force does not know the recipe of the display panel", force = fake_force{absent = {"display-panel"}}},
        {label = "the game has no display panel", force = fake_force{}, game = {missing_entities = {"display-panel"}}},
        {label = "the blueprint takes the original design, which has no entries to label", force = fake_force{locked = {"splitter"}}},
        {label = "no force is given, so nothing is known to be researched", force = nil},
      }

      for _, case in ipairs(without_panels) do
        it("puts no panel on the blueprint when " .. case.label, function()
          _G.prototypes = circuit_game(case.game)

          local result = generator.generate("electronic-circuit", 50, case.force)

          assert.are.same({}, icons_of(result.entities))
        end)
      end
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

    it("builds it when the underground belt spans exactly the fewest tiles the hops need", function()
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
      return fake_prototypes(builders.merged({
        furnace_speed = 1,
        machines = {["assembling-machine-1"] = a_machine{crafting_speed = 0.5, size = 3}},
        recipes = {["iron-plate"] = plate, ["iron-gear-wheel"] = gear},
      }, options))
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

      it("allows the most the paired winding belt carries with fast inserters, which is less than two full lanes", function()
        _G.prototypes = cable_game()

        assert.are.same({"blueprint-generation.max-rate", "810"}, generator.max_rate_message("copper-cable", fake_force{}))
      end)

      it("allows two full lanes with plain inserters, which wind the belt with two inserters on a machine", function()
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

  describe("the inserter capacity bonus, once the force has researched it: an inserter then moves more than one item in a swing", function()
    -- A plain inserter swings in 1 / 0.014 = 71.4 ticks. With a hand of two items it also holds still for the second one: at a
    -- basic belt an item takes 8 ticks to come along (or to be carried clear), so it moves 2 items in 79.4 ticks, 90.6 a minute
    -- where a hand of one moves 50.4. An assembler (speed 0.5, 3x3) makes 60 gears a minute and eats 120 plates: two plain
    -- inserters (100.8) hold it back to 50.4 gears, two with the bonus (181.3) do not. `plain` has no fast inserter.
    local plate = a_recipe{energy = 3.2, ingredients = {amount_of(1, "iron-ore")}, products = {amount_of(1, "iron-plate")}, category = "smelting"}
    local gear = a_recipe{energy = 0.5, ingredients = {amount_of(2, "iron-plate")}, products = {amount_of(1, "iron-gear-wheel")}}

    local function gear_game(options)
      return fake_prototypes(builders.merged({
        furnace_speed = 1,
        machines = {["assembling-machine-1"] = a_machine{crafting_speed = 0.5, size = 3}},
        recipes = {["iron-plate"] = plate, ["iron-gear-wheel"] = gear},
      }, options))
    end

    local function plain(bonus)
      return fake_force{absent = {"fast-inserter"}, inserter_stack_size_bonus = bonus}
    end

    it("needs fewer assemblers, since plain inserters then run each machine at full speed", function()
      _G.prototypes = gear_game()

      local researched = generator.generate("iron-gear-wheel", 60, plain(1))
      local not_yet = generator.generate("iron-gear-wheel", 60, plain(0))

      -- one assembler at full speed: 2 x 90.6 plates moved of the 120 it eats; otherwise two that make 50.4 each
      assert.are.same({1, 2}, {count_named(researched.entities, "assembling-machine-1"), count_named(not_yet.entities, "assembling-machine-1")})
    end)

    it("counts whole items only: a bonus of less than one item changes nothing", function()
      _G.prototypes = gear_game()

      local result = generator.generate("iron-gear-wheel", 60, plain(0.9))

      assert.are.equal(2, count_named(result.entities, "assembling-machine-1")) -- as without the research: 50.4 gears each
    end)

    it("counts the bonus built into the inserter even when no force is given", function()
      _G.prototypes = gear_game{inserter_stacks = {["inserter"] = {built_in = 1}}}

      local result = generator.generate("iron-gear-wheel", 60)

      assert.are.equal(1, count_named(result.entities, "assembling-machine-1")) -- the hand holds 2 items with nothing researched
    end)

    it("leaves the research out for an inserter whose prototype does not take it", function()
      _G.prototypes = gear_game{inserter_stacks = {["inserter"] = {takes_research = false}}}

      local result = generator.generate("iron-gear-wheel", 60, plain(1))

      assert.are.equal(2, count_named(result.entities, "assembling-machine-1")) -- 50.4 gears each, as if nothing were researched
    end)

    it("counts it for the belt's speed: a faster belt makes an inserter wait less, so it moves more", function()
      -- 186 plates make 1 gear a minute: a machine eats 186 plates, which two plain inserters move at 181.3 on a basic belt
      -- (a machine at 97.5%) and at 190.9 on a belt of twice the speed (4 ticks of waiting), which feeds it fully.
      local heavy = a_recipe{energy = 30, ingredients = {amount_of(186, "iron-plate")}, products = {amount_of(1, "iron-gear-wheel")}}
      local function assemblers_at(belt_speed)
        _G.prototypes = gear_game{recipes = {["iron-plate"] = plate, ["iron-gear-wheel"] = heavy}, belt_speed = belt_speed}
        return count_named(generator.generate("iron-gear-wheel", 2, plain(1)).entities, "assembling-machine-1")
      end

      local assemblers = {basic = assemblers_at(0.03125), twice_as_fast = assemblers_at(0.0625)}

      assert.are.same({basic = 3, twice_as_fast = 2}, assemblers) -- 2 / 0.975 = 2.05 machines; 2 / 1
    end)

    describe("with the fast inserter researched too", function()
      it("puts a plain inserter on a side that one plain inserter then moves", function()
        _G.prototypes = gear_game()

        local result = generator.generate("iron-gear-wheel", 60, fake_force{inserter_stack_size_bonus = 1})

        -- the input side takes 120 plates, more than a plain inserter moves (90.6): one fast inserter (218.2); the output side's 60 gears
        -- need no fast one. Without the bonus both sides have one (50.4 is less than either).
        assert.are.equal(1, count_named(result.entities, "fast-inserter"))
      end)

      it("needs fewer fast inserters, since one moves what two did", function()
        local heavy_gear = a_recipe{energy = 0.5, ingredients = {amount_of(3, "iron-plate")}, products = {amount_of(1, "iron-gear-wheel")}} -- 180 plates a minute
        _G.prototypes = gear_game{recipes = {["iron-plate"] = plate, ["iron-gear-wheel"] = heavy_gear}}

        local researched = generator.generate("iron-gear-wheel", 60, fake_force{inserter_stack_size_bonus = 1})
        local not_yet = generator.generate("iron-gear-wheel", 60, fake_force{})

        -- With the bonus one fast inserter (218.2) moves the 180 plates and a plain one (90.6) the 60 gears; without it two fast
        -- ones (144 each) move the plates and a fast one the gears, which a plain one (50.4) would not
        assert.are.same({1, 3}, {count_named(researched.entities, "fast-inserter"), count_named(not_yet.entities, "fast-inserter")})
      end)

      it("takes the stack size of the fast inserter from the game: one then moves what two did", function()
        local heavy_gear = a_recipe{energy = 0.5, ingredients = {amount_of(3, "iron-plate")}, products = {amount_of(1, "iron-gear-wheel")}}
        _G.prototypes = gear_game{recipes = {["iron-plate"] = plate, ["iron-gear-wheel"] = heavy_gear}, inserter_stacks = {["fast-inserter"] = {built_in = 1}}}

        local result = generator.generate("iron-gear-wheel", 60, fake_force{})

        -- the plates, 180 a minute, take one fast inserter (218.2); the gears, 60, one too, since the plain inserter, with a hand of one, moves 50.4
        assert.are.equal(2, count_named(result.entities, "fast-inserter"))
      end)
    end)

    it("stops with a message when the game does not say the stack size bonus of an inserter", function()
      _G.prototypes = gear_game{inserter_stacks = {["inserter"] = {built_in = false}}}

      assert.has_error(function() generator.generate("iron-gear-wheel", 60, plain(1)) end,
        "generator: the game does not give the stack size bonus of inserter")
    end)

    it("stops with a message when the game does not say whether an inserter takes the research", function()
      _G.prototypes = gear_game{inserter_stacks = {["inserter"] = {takes_research = "unsaid"}}}

      assert.has_error(function() generator.generate("iron-gear-wheel", 60, plain(1)) end,
        "generator: the game does not say whether inserter takes the inserter capacity bonus")
    end)

    it("stops with a message when the force does not give its inserter capacity bonus", function()
      _G.prototypes = gear_game()

      assert.has_error(function() generator.generate("iron-gear-wheel", 60, plain(false)) end,
        "generator: the game does not give the inserter capacity bonus of the force")
    end)
  end)

  describe("the recipe the player picks", function()
    -- Two recipes make the same iron plates: from an ore in 3.2 s, and from two scraps in 6.4 s, which makes half as many plates in a
    -- furnace (18.75 a minute and 9.375). The config lists the second for these tests.
    local plate = a_recipe{energy = 3.2, ingredients = {amount_of(1, "iron-ore")}, products = {amount_of(1, "iron-plate")}, category = "smelting"}
    local from_scrap = a_recipe{energy = 6.4, ingredients = {amount_of(2, "scrap")}, products = {amount_of(1, "iron-plate")}, category = "smelting"}

    before_each(function()
      config.recipes["iron-plate-from-scrap"] = true
    end)

    after_each(function()
      config.recipes["iron-plate-from-scrap"] = nil
    end)

    local function plate_game()
      return fake_prototypes{recipes = {["iron-plate"] = plate, ["iron-plate-from-scrap"] = from_scrap}}
    end

    it("builds with the recipe picked, though another recipe makes the same product", function()
      _G.prototypes = plate_game()

      local by_ore = generator.generate("iron-plate", 75)
      local by_scrap = generator.generate("iron-plate-from-scrap", 75)

      -- 75 plates a minute: 4 furnaces at 18.75 a minute from ore, 8 at 9.375 from scrap
      assert.are.same({4, 8}, {count_named(by_ore.entities, "stone-furnace"), count_named(by_scrap.entities, "stone-furnace")})
    end)

    it("takes the raw items of the recipe picked", function()
      _G.prototypes = plate_game()

      local by_scrap = generator.generate("iron-plate-from-scrap", 75)

      assert.are.same({"item-name.scrap"}, by_scrap.message[4][2][3]) -- the first raw item in the message
    end)

    it("names the product, not the recipe, in the message and the description", function()
      _G.prototypes = plate_game()

      local by_scrap = generator.generate("iron-plate-from-scrap", 75)

      assert.are.same({{"item-name.iron-plate"}, "iron-plate: 75 per minute from 8 x stone-furnace"}, {by_scrap.message[3], by_scrap.description})
    end)

    it("shows the maximum of the recipe picked under the rate field", function()
      _G.prototypes = plate_game()

      -- one lane of the input belt carries 450 a minute: 450 ore make 450 plates, and 450 scraps make 225
      assert.are.same({"blueprint-generation.max-rate", "450"}, generator.max_rate_message("iron-plate"))
      assert.are.same({"blueprint-generation.max-rate", "225"}, generator.max_rate_message("iron-plate-from-scrap"))
    end)

    it("refuses a recipe the config does not list", function()
      _G.prototypes = plate_game()
      config.recipes["iron-plate-from-scrap"] = nil

      local result, error_message = generator.generate("iron-plate-from-scrap", 75)

      assert.are.same({nil, {"blueprint-generation.error-unsupported-pick"}}, {result, error_message})
    end)

    it("refuses a recipe the game does not have, naming it", function()
      _G.prototypes = fake_prototypes{recipes = {["iron-plate"] = plate}}

      local result, error_message = generator.generate("iron-plate-from-scrap", 75)

      assert.are.same({nil, {"blueprint-generation.error-no-recipe", "iron-plate-from-scrap"}}, {result, error_message})
    end)

    it("refuses a recipe of a category that no machine of the config makes, naming its product", function()
      local melting = a_recipe{energy = 1, ingredients = {amount_of(1, "scrap")}, products = {amount_of(1, "iron-plate")}, category = "metallurgy"}
      _G.prototypes = fake_prototypes{recipes = {["iron-plate-from-scrap"] = melting}}

      local result, error_message = generator.generate("iron-plate-from-scrap", 75)

      assert.are.same({nil, {"blueprint-generation.error-no-recipe", {"item-name.iron-plate"}}}, {result, error_message})
    end)

    it("refuses a recipe that makes nothing", function()
      local nothing = a_recipe{energy = 1, ingredients = {amount_of(1, "scrap")}, products = {}, category = "smelting"}
      _G.prototypes = fake_prototypes{recipes = {["iron-plate-from-scrap"] = nothing}}

      local result, error_message = generator.generate("iron-plate-from-scrap", 75)

      assert.are.same({nil, {"blueprint-generation.error-unsupported-recipe"}}, {result, error_message})
    end)

    it("refuses the recipe picked when its ingredient is made by two recipes, which the player did not pick", function()
      local gear = a_recipe{energy = 0.5, ingredients = {amount_of(2, "iron-plate")}, products = {amount_of(1, "iron-gear-wheel")}}
      _G.prototypes = fake_prototypes{
        machines = {["assembling-machine-1"] = a_machine{crafting_speed = 0.5, size = 3}},
        recipes = {["iron-plate"] = plate, ["iron-plate-from-scrap"] = from_scrap, ["iron-gear-wheel"] = gear},
      }

      local result, error_message = generator.generate("iron-gear-wheel", 10)

      assert.are.same({nil, {"blueprint-generation.error-ambiguous-recipe", {"item-name.iron-plate"}}}, {result, error_message})
    end)

    it("checks that the force has unlocked the recipe picked, not the recipes of the other products", function()
      _G.prototypes = plate_game()

      local locked = generator.generate("iron-plate-from-scrap", 75, fake_force{locked = {"iron-plate-from-scrap"}})
      local other = generator.generate("iron-plate-from-scrap", 75, fake_force{locked = {"iron-plate"}})

      assert.is_nil(locked)
      assert.is_not_nil(other)
    end)

    it("says which product the force has not unlocked the recipe of", function()
      _G.prototypes = plate_game()

      local _, error_message = generator.generate("iron-plate-from-scrap", 75, fake_force{locked = {"iron-plate-from-scrap"}})

      assert.are.same({"blueprint-generation.error-locked", {"item-name.iron-plate"}}, error_message)
    end)
  end)

  describe("refusals", function()
    it("refuses the request when the item is not supported", function()
      _G.prototypes = fake_prototypes{}

      local result, error_message = generator.generate("advanced-circuit", 10)

      assert.is_nil(result)
      assert.are.same({"blueprint-generation.error-unsupported-pick"}, error_message)
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

      it("refuses the request without the design that brings in one belt of each material, naming the item", function()
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

    describe("a step that eats many made ingredients", function()
      local plate = a_recipe{energy = 3.2, ingredients = {amount_of(1, "iron-ore")}, products = {amount_of(1, "iron-plate")}, category = "smelting"}
      local copper = a_recipe{energy = 3.2, ingredients = {amount_of(1, "copper-ore")}, products = {amount_of(1, "copper-plate")}, category = "smelting"}
      local brick = a_recipe{energy = 3.2, ingredients = {amount_of(2, "stone")}, products = {amount_of(1, "stone-brick")}, category = "smelting"}
      local cable = a_recipe{energy = 0.5, ingredients = {amount_of(1, "copper-plate")}, products = {amount_of(2, "copper-cable")}}
      local pipe = a_recipe{energy = 0.5, ingredients = {amount_of(1, "iron-plate")}, products = {amount_of(1, "pipe")}}
      local rod = a_recipe{energy = 0.5, ingredients = {amount_of(1, "iron-plate")}, products = {amount_of(2, "iron-stick")}}
      local wire = a_recipe{energy = 0.5, ingredients = {amount_of(1, "copper-plate")}, products = {amount_of(1, "wire")}}

      -- A stand-in "gear" that eats `ingredients`, each made by a recipe above.
      local function game_with(ingredients)
        local gear = a_recipe{energy = 0.5, ingredients = ingredients, products = {amount_of(1, "iron-gear-wheel")}}
        return fake_prototypes{
          furnace_speed = 1,
          machines = {["assembling-machine-1"] = a_machine{crafting_speed = 0.5, size = 3}},
          recipes = {
            ["iron-plate"] = plate, ["copper-plate"] = copper, ["stone-brick"] = brick, ["copper-cable"] = cable, ["pipe"] = pipe,
            ["iron-stick"] = rod, ["wire"] = wire, ["iron-gear-wheel"] = gear,
          },
        }
      end

      local five = {amount_of(2, "iron-plate"), amount_of(1, "copper-plate"), amount_of(1, "stone-brick"), amount_of(1, "copper-cable"), amount_of(1, "pipe")}

      it("refuses the request when a step needs seven made ingredients, naming the item", function()
        _G.prototypes = game_with({
          amount_of(2, "iron-plate"), amount_of(1, "copper-plate"), amount_of(1, "stone-brick"), amount_of(1, "copper-cable"),
          amount_of(1, "pipe"), amount_of(1, "iron-stick"), amount_of(1, "wire"),
        })

        local result, error_message = generator.generate("iron-gear-wheel", 10, fake_force{})

        assert.is_nil(result)
        assert.are.same({"blueprint-generation.error-chain-too-complex", {"item-name.iron-gear-wheel"}}, error_message)
      end)

      it("builds a step that needs five made ingredients, on three woven belts, with the medium pole", function()
        _G.prototypes = game_with(five)
        local catalog = builders.a_catalog{machine_size = 2, machine_needs_power = false}
        catalog["assembling-machine-1"] = {kind = "machine", width = 3, height = 3, needs_power = true}

        local result = generator.generate("iron-gear-wheel", 10, fake_force{})

        assert.are.same({}, validator.validate(result.entities, catalog))
      end)

      -- Three woven belts need the splitter, the underground belt and the medium pole: without one of them the step is refused,
      -- and the message says what to research.
      local refusal = {"blueprint-generation.error-belts-need-weave", {"item-name.iron-gear-wheel"}}

      it("refuses it when the force has only the small pole, whose poles do not reach the inserters beside three belts", function()
        _G.prototypes = game_with(five)

        local result, error_message = generator.generate("iron-gear-wheel", 10, fake_force{locked = {"medium-electric-pole"}})

        assert.are.same({nil, refusal}, {result, error_message})
      end)

      it("refuses it when no force is given: long-handed inserters reach a second belt only", function()
        _G.prototypes = game_with(five)

        local result, error_message = generator.generate("iron-gear-wheel", 10)

        assert.are.same({nil, refusal}, {result, error_message})
      end)

      it("refuses it when the force has not researched the splitter", function()
        _G.prototypes = game_with(five)

        local result, error_message = generator.generate("iron-gear-wheel", 10, fake_force{locked = {"splitter"}})

        assert.are.same({nil, refusal}, {result, error_message})
      end)

      it("refuses it when the force has not researched the underground belt", function()
        _G.prototypes = game_with(five)

        local result, error_message = generator.generate("iron-gear-wheel", 10, fake_force{locked = {"underground-belt"}})

        assert.are.same({nil, refusal}, {result, error_message})
      end)

      it("shows the same refusal under the rate field", function()
        _G.prototypes = game_with(five)

        assert.are.same(refusal, generator.max_rate_message("iron-gear-wheel"))
      end)

      it("builds a step that needs four made ingredients with the small pole: two woven belts need poles that reach two rows", function()
        _G.prototypes = game_with({amount_of(2, "iron-plate"), amount_of(1, "copper-plate"), amount_of(1, "stone-brick"), amount_of(1, "copper-cable")})

        local result = generator.generate("iron-gear-wheel", 10, fake_force{locked = {"medium-electric-pole"}})

        assert.is_not_nil(result)
      end)

      it("builds a step that needs four made ingredients with long-handed inserters when no force is given: two belts carry them", function()
        _G.prototypes = game_with({amount_of(2, "iron-plate"), amount_of(1, "copper-plate"), amount_of(1, "stone-brick"), amount_of(1, "copper-cable")})

        local result = generator.generate("iron-gear-wheel", 10)

        assert.are.equal(1, count_named(result.entities, "long-handed-inserter"))
      end)
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
      local plate_in_a_centrifuge = a_recipe{energy = 1, ingredients = {amount_of(1, "iron-ore")}, products = {amount_of(1, "iron-plate")}, category = "centrifuging"}
      _G.prototypes = fake_prototypes{recipes = {["iron-plate"] = plate_in_a_centrifuge}}

      local result, error_message = generator.generate("iron-plate", 10)

      assert.is_nil(result)
      assert.are.same({"blueprint-generation.error-no-recipe", {"item-name.iron-plate"}}, error_message)
    end)

    it("refuses the request when a step that takes a fluid is fed raw items only, naming the item", function()
      local wet_gear = a_recipe{energy = 0.5, ingredients = {amount_of(2, "iron-plate"), fluid_of(10, "water")}, products = {amount_of(1, "iron-gear-wheel")}}
      _G.prototypes = fake_prototypes{
        machines = {["assembling-machine-1"] = a_machine{crafting_speed = 0.5, size = 3}},
        recipes = {["iron-gear-wheel"] = wet_gear},
      }

      local result, error_message = generator.generate("iron-gear-wheel", 10)

      assert.is_nil(result)
      assert.are.same({"blueprint-generation.error-fluid-single-input", {"item-name.iron-gear-wheel"}}, error_message)
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
      return fake_prototypes(builders.merged({
        furnace_speed = 1,
        machines = {["assembling-machine-1"] = a_machine{crafting_speed = 0.5, size = 3}},
        recipes = {["iron-plate"] = plate, ["iron-gear-wheel"] = gear},
      }, options))
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

    it("puts lamps on a blueprint, more than one when it is long", function()
      _G.prototypes = gear_game()

      local result = generator.generate("iron-gear-wheel", 200, fake_force{})

      assert.is_true(#lamps_of(result.entities) > 1)
    end)

    it("puts no two lamps closer than 10 tiles", function()
      _G.prototypes = gear_game()

      local result = generator.generate("iron-gear-wheel", 200, fake_force{})

      assert.is_true(builders.closest_pair(lamps_of(result.entities)) >= 10)
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
      return fake_prototypes(builders.merged({
        furnace_speed = 1,
        machines = {["assembling-machine-1"] = a_machine{crafting_speed = 0.5, size = 3}},
        recipes = {["iron-plate"] = plate, ["iron-gear-wheel"] = gear, ["steel-plate"] = steel},
      }, options))
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

    it("allows two full lanes of plates, which furnaces built wide make", function()
      _G.prototypes = game()

      assert.are.same({"blueprint-generation.max-rate", "900"}, generator.max_rate_message("iron-plate", fake_force{}))
    end)

    it("refuses a rate above that", function()
      _G.prototypes = game()

      local result, message = generator.generate("iron-plate", 901, fake_force{})

      assert.are.same({nil, {"blueprint-generation.error-rate-too-high", "900"}}, {result, message})
    end)

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

      local root = layout_given("iron-plate", 600, fake_force{}) -- 32 furnaces: 600 ore a minute, and 32 x 1.35 coal

      assert.are.same({"iron-ore 450.00", "coal 43.20"}, amounts(root.feed))
    end)

    it("takes the rest of the ore from the second belt of furnaces built wide, and no fuel", function()
      _G.prototypes = game()

      local root = layout_given("iron-plate", 600, fake_force{})

      assert.are.same({"iron-ore 150.00"}, amounts(root.second_feed))
    end)

    it("allows twice the steel plates of the plain design, with the furnaces built wide", function()
      _G.prototypes = game()

      assert.are.same({{"blueprint-generation.max-rate", "180"}, {"blueprint-generation.max-rate", "90"}},
        {generator.max_rate_message("steel-plate", fake_force{}), generator.max_rate_message("steel-plate", fake_force{locked = {"medium-electric-pole"}})})
    end)

    it("tells the layout that the iron furnaces draw a second belt and the steel furnaces a belt of fuel", function()
      _G.prototypes = game()

      local steel_stage = layout_given("steel-plate", 100, fake_force{})
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
      return fake_prototypes(builders.merged({
        furnace_speed = 1,
        machines = {["assembling-machine-1"] = a_machine{crafting_speed = 0.5, size = 3}},
        recipes = {["iron-plate"] = plate, ["iron-gear-wheel"] = gear},
      }, options))
    end

    it("has the poles of the furnaces beside their output side alone, where the pole reaches their input inserters", function()
      _G.prototypes = gear_game()

      local assembler = layout_given("iron-gear-wheel", 60, fake_force{})
      local furnaces = assembler.suppliers[1]

      assert.are.same({true, false}, {furnaces.shape.powered_from_output, assembler.shape.powered_from_output}) -- 3 tiles reach a 2 x 2 machine's input side, not a 3 x 3 one's
    end)

    it("has the poles of the furnaces beside both sides when the small pole is all there is", function()
      _G.prototypes = gear_game()

      local assembler = layout_given("iron-gear-wheel", 60, fake_force{locked = {"medium-electric-pole"}})

      assert.is_false(assembler.suppliers[1].shape.powered_from_output)
    end)

    it("has the poles of the furnaces beside both sides when the medium pole of the game powers only 2.5 tiles", function()
      _G.prototypes = gear_game({medium_pole_supply_distance = 2.5, medium_pole_wire_distance = 7.5})

      local assembler = layout_given("iron-gear-wheel", 60, fake_force{})

      assert.is_false(assembler.suppliers[1].shape.powered_from_output)
    end)

    it("has the poles of the furnaces beside their output side alone in the original design too, once the medium pole is unlocked", function()
      _G.prototypes = gear_game()

      local assembler = layout_given("iron-gear-wheel", 60, fake_force{locked = {"splitter"}})

      assert.is_true(assembler.suppliers[1].shape.powered_from_output)
    end)

    it("builds with fewer medium poles than small poles take, and no small pole", function()
      _G.prototypes = gear_game()

      local result = generator.generate("iron-gear-wheel", 60, fake_force{})

      -- 4 beside the output side of the 7 furnaces, which reach the input inserters too (3 tiles away), and 1 for the assembler: the
      -- pole of its input side is left out, since the furnaces' poles reach its input inserters across the belt (2 tiles away)
      assert.are.same({5, 0}, {count_named(result.entities, "medium-electric-pole"), count_named(result.entities, "small-electric-pole")})
    end)

    it("builds a blueprint that passes the validator, every inserter, machine and lamp powered and the poles wired", function()
      _G.prototypes = gear_game()
      local catalog = builders.a_catalog{machine_size = 2, machine_needs_power = false}
      catalog["assembling-machine-1"] = {kind = "machine", width = 3, height = 3, needs_power = true}

      local result = generator.generate("iron-gear-wheel", 200, fake_force{})

      assert.are.same({}, validator.validate(result.entities, catalog))
    end)

    it("takes how far the pole powers from the game: a medium pole that powers no further than a small one takes as many poles", function()
      _G.prototypes = gear_game({medium_pole_supply_distance = 2.5, medium_pole_wire_distance = 7.5})

      local result = generator.generate("iron-gear-wheel", 60, fake_force{})

      assert.are.equal(9, count_named(result.entities, "medium-electric-pole"))
    end)

    it("puts the lamps by the supply distance the game gives for the medium pole: a game that gives a shorter distance gets other lamps", function()
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

    -- The poles of the blueprint of 60 gears when the medium pole is not used: 9 with the force's design (the band of the
    -- one-belt design is what a force that has the splitter and the underground belt gets), 10 in the original design.
    local small_only = {
      {label = "no force is given, so nothing is known to be unlocked", force = nil, poles = 10},
      {label = "the force has not unlocked the medium pole", force = fake_force{locked = {"medium-electric-pole"}}, poles = 9},
      {label = "the force does not know the recipe of the medium pole", force = fake_force{absent = {"medium-electric-pole"}}, poles = 9},
      {label = "the game has no medium pole", force = fake_force{}, game = {missing_entities = {"medium-electric-pole"}}, poles = 9},
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

  describe("a fluid made from a fluid, in a row of oil refineries", function()
    -- 100 crude oil make 45 petroleum gas in 5 s: a refinery of speed 1 makes 540 a minute and takes 1,200 crude oil. The refinery is
    -- 5 x 5. The game gives each pipe connection as the tile of the machine it is on, at its edge, and the way it points: the two
    -- that take a fluid are on the bottom row (one tile either side of the middle) and point south, the three that give one are on
    -- the top row and point north. The pipes stand on the tiles outside, under it and above it.
    local north, south, west = defines.direction.north, defines.direction.south, defines.direction.west
    local east = defines.direction.east
    local basic = a_recipe{energy = 5, ingredients = {fluid_of(100, "crude-oil")}, products = {fluid_of(45, "petroleum-gas")}, category = "oil-processing"}
    local advanced = a_recipe{
      energy = 5, ingredients = {fluid_of(100, "crude-oil"), fluid_of(50, "water")},
      products = {fluid_of(25, "heavy-oil"), fluid_of(45, "light-oil"), fluid_of(55, "petroleum-gas")}, category = "oil-processing",
    }
    local two_fluids = a_recipe{
      energy = 5, ingredients = {fluid_of(100, "crude-oil"), fluid_of(50, "water")}, products = {fluid_of(45, "petroleum-gas")}, category = "oil-processing",
    }
    local PIPES = {
      {production_type = "input", position = {x = -1, y = 2}, direction = south}, {production_type = "input", position = {x = 1, y = 2}, direction = south},
      {production_type = "output", position = {x = -2, y = -2}, direction = north}, {production_type = "output", position = {x = 0, y = -2}, direction = north},
      {production_type = "output", position = {x = 2, y = -2}, direction = north},
    }

    local function refinery(changes)
      return a_machine(builders.merged({crafting_speed = 1, size = 5, pipe_boxes = PIPES}, changes))
    end

    local function oil_game(changes)
      return fake_prototypes(builders.merged({
        machines = {["oil-refinery"] = refinery()},
        recipes = {["basic-oil-processing"] = basic},
      }, changes))
    end

    local function catalog()
      local entries = builders.a_catalog{}
      entries["oil-refinery"] = {
        kind = "machine", width = 5, height = 5, needs_power = true,
        fluid_connections = {input = {{x = 1, y = 5}, {x = 3, y = 5}}, output = {{x = 0, y = -1}, {x = 2, y = -1}, {x = 4, y = -1}}},
      }
      return entries
    end

    it("builds as many refineries as the rate needs, which make a little more than asked", function()
      _G.prototypes = oil_game()

      local result = generator.generate("basic-oil-processing", 1000)

      assert.are.equal(2, count_named(result.entities, "oil-refinery")) -- 1000 / 540 = 1.85
    end)

    it("sets the recipe on every refinery", function()
      _G.prototypes = oil_game()

      local result = generator.generate("basic-oil-processing", 1000)

      local recipes = {}
      for _, refinery_entity in ipairs(builders.entities_named(result.entities, "oil-refinery")) do
        recipes[#recipes + 1] = refinery_entity.recipe
      end
      assert.are.same({"basic-oil-processing", "basic-oil-processing"}, recipes)
    end)

    it("says what the refineries make and what they take a minute", function()
      _G.prototypes = oil_game()

      local result = generator.generate("basic-oil-processing", 1000)

      -- 2 refineries make 1,080, in 24 crafts a minute of 100 crude oil
      assert.are.same({"blueprint-generation.generated", "1080", {"fluid-name.petroleum-gas"},
        {"", {"blueprint-generation.raw-amount", "2400", {"fluid-name.crude-oil"}}}}, result.message)
    end)

    it("describes the blueprint with its refineries", function()
      _G.prototypes = oil_game()

      local result = generator.generate("basic-oil-processing", 1000)

      assert.are.equal("petroleum-gas: 1080 per minute from 2 x oil-refinery", result.description)
    end)

    it("builds a blueprint that passes the validator: powered, wired, and two networks of pipes, each with an open end", function()
      _G.prototypes = oil_game()

      local result = generator.generate("basic-oil-processing", 1000)

      assert.are.same({}, validator.validate(result.entities, catalog()))
    end)

    it("builds from the recipe the config names when another recipe makes the fluid too", function()
      _G.prototypes = oil_game{recipes = {["basic-oil-processing"] = basic, ["advanced-oil-processing"] = advanced}}

      local result = generator.generate("basic-oil-processing", 1000)

      assert.are.equal(2, count_named(result.entities, "oil-refinery"))
    end)

    it("names the most a row makes, which is as many refineries as stand in 320 tiles, the length a run of pipes may have", function()
      _G.prototypes = oil_game()

      -- 64 refineries of 5 tiles, and 64 x 540 petroleum gas
      assert.are.same({"blueprint-generation.max-rate", "34560"}, generator.max_rate_message("basic-oil-processing"))
    end)

    it("names fewer for a larger refinery", function()
      -- a refinery of 21 tiles: 15 in 320, and its connections as the game gives them for that size
      local big = {
        {production_type = "input", position = {x = -1, y = 10}, direction = south}, {production_type = "input", position = {x = 1, y = 10}, direction = south},
        {production_type = "output", position = {x = -2, y = -10}, direction = north}, {production_type = "output", position = {x = 0, y = -10}, direction = north},
        {production_type = "output", position = {x = 2, y = -10}, direction = north},
      }
      _G.prototypes = oil_game{small_pole_wire_distance = 21, machines = {["oil-refinery"] = refinery{size = 21, pipe_boxes = big}}}

      assert.are.same({"blueprint-generation.max-rate", "8100"}, generator.max_rate_message("basic-oil-processing")) -- 15 x 540
    end)

    it("allows the most a row makes", function()
      _G.prototypes = oil_game()

      local result = generator.generate("basic-oil-processing", 34560)

      assert.are.equal(64, count_named(result.entities, "oil-refinery"))
    end)

    it("reads where the pipes connect from the game, as tiles from the top-left of the machine", function()
      -- a refinery that takes its fluid at the west end of its bottom side and gives its own at the east of its top side. The game
      -- gives the positions from the centre: -2 and 1 across are the tiles 0 and 3 (floor(2.5 - 2), floor(2.5 + 1)), 2 and -2 down
      -- the rows 4 and 0, the bottom and the top row of the machine, so that the pipes are on the rows 5 and -1 beside them
      local lopsided = {
        {production_type = "input", position = {x = -2, y = 2}, direction = south}, {production_type = "output", position = {x = 1, y = -2}, direction = north},
      }
      _G.prototypes = oil_game{machines = {["oil-refinery"] = refinery{pipe_boxes = lopsided}}}
      local entries = catalog()
      entries["oil-refinery"].fluid_connections = {input = {{x = 0, y = 5}}, output = {{x = 3, y = -1}}}

      local result = generator.generate("basic-oil-processing", 1000)

      -- two refineries, 5 tiles apart, in a row that is turned: the pipe that takes the fluid out is in the column 7, from the tile of
      -- the first connection to that of the last refinery (3 to 8); the pipe that brings it in is in the column 1, from the north end
      -- to the tile of the connection of the last refinery (0 to 5)
      local out_column, in_column = builders.body_rows_in_column(result.entities, "pipe", 7), builders.body_rows_in_column(result.entities, "pipe", 1)
      assert.are.same({builders.range(3, 8), builders.range(0, 5)}, {out_column, in_column})
      assert.are.same({}, validator.validate(result.entities, entries))
    end)

    it("stacks the refineries from north to south, turned to face east, the fluid coming in at the north end", function()
      _G.prototypes = oil_game()

      local result = generator.generate("basic-oil-processing", 1000)

      local refineries = builders.entities_named(result.entities, "oil-refinery")
      local tiles = {}
      for _, refinery_entity in ipairs(refineries) do
        local tile = grid.top_left_tile(refinery_entity.position, 5, 5)
        tiles[#tiles + 1] = {tile.x, tile.y, refinery_entity.direction}
      end
      table.sort(tiles, function(a, b) return a[2] < b[2] end)
      -- the crude oil pipe is the column 1 on their west, from the north end of the blueprint, and the petroleum gas pipe the column 7
      assert.are.same({{2, 0, east}, {2, 5, east}}, tiles)
      assert.are.same({builders.range(0, 8), builders.range(0, 9)}, {builders.body_rows_in_column(result.entities, "pipe", 1), builders.body_rows_in_column(result.entities, "pipe", 7)})
    end)

    it("takes the start of the crude oil pipe to the top left corner, up above the blueprint and west to the edge, as the belts start there", function()
      _G.prototypes = oil_game()

      local result = generator.generate("basic-oil-processing", 1000)

      -- the pipe goes up from the tile (1, 0) to the row -1 and west along it: the tiles (0, -1) and (1, -1), the end open to the west
      local above = {}
      for _, pipe in ipairs(builders.entities_named(result.entities, "pipe")) do
        local tile = grid.top_left_tile(pipe.position)
        if tile.y < 0 then
          above[#above + 1] = {tile.x, tile.y}
        end
      end
      table.sort(above, function(a, b) return a[1] < b[1] end)
      assert.are.same({{0, -1}, {1, -1}}, above)
    end)

    it("keeps the tile west of the entry of the crude oil pipe free of lamps, where the player joins it", function()
      _G.prototypes = oil_game()
      local lights = require("scripts.lights")
      local add, told = lights.add, nil
      lights.add = function(entities, options) told = options return add(entities, options) end

      generator.generate("basic-oil-processing", 1000, fake_force{})
      lights.add = add

      assert.are.same({{x = -1, y = -1}}, told.free_tiles)
    end)

    it("puts a display panel with the crude oil beside the entry at the top left corner, above it, once the force has unlocked it", function()
      _G.prototypes = oil_game()

      local result = generator.generate("basic-oil-processing", 1000, fake_force{})

      local panels = {}
      for _, panel in ipairs(builders.entities_named(result.entities, "display-panel")) do
        local tile = grid.top_left_tile(panel.position)
        panels[#panels + 1] = {tile.x, tile.y, panel.icon.type, panel.icon.name}
      end
      table.sort(panels, function(a, b) return a[1] < b[1] end)
      assert.are.same({{0, -2, "fluid", "crude-oil"}}, panels)
    end)

    it("has no panels without the force's display panel, nor without a force", function()
      _G.prototypes = oil_game()

      local locked = generator.generate("basic-oil-processing", 1000, fake_force{locked = {"display-panel"}})
      local none = generator.generate("basic-oil-processing", 1000)

      assert.are.same({0, 0}, {count_named(locked.entities, "display-panel"), count_named(none.entities, "display-panel")})
    end)

    it("builds with a wire exactly as long as a machine is wide, which reaches from the pole of one machine to the next", function()
      _G.prototypes = oil_game{small_pole_wire_distance = 5}

      local result = generator.generate("basic-oil-processing", 1000)

      assert.are.equal(2, count_named(result.entities, "oil-refinery"))
    end)

    it("gives the planner the crafting speed of the refinery from the game", function()
      -- a refinery of speed 2 makes 1,080 gas a minute: 64 of them in 320 tiles
      _G.prototypes = oil_game{machines = {["oil-refinery"] = refinery{crafting_speed = 2}}}

      local result = generator.generate("basic-oil-processing", 1000)

      assert.are.same({"petroleum-gas: 1080 per minute from 1 x oil-refinery", {"blueprint-generation.max-rate", "69120"}},
        {result.description, generator.max_rate_message("basic-oil-processing")})
    end)

    it("keeps the lamps off the machines and the pipes", function()
      _G.prototypes = oil_game()
      local lit = generator.generate("basic-oil-processing", 1000, fake_force{})

      local problems = validator.validate(lit.entities, catalog())

      assert.is_true(count_named(lit.entities, "small-lamp") > 0)
      assert.are.same({}, problems)
    end)

    it("refuses a rate that needs more refineries than stand in the length of a run of pipes, naming the most", function()
      _G.prototypes = oil_game()

      local result, error_message = generator.generate("basic-oil-processing", 34561)

      assert.are.same({nil, {"blueprint-generation.error-rate-too-high", "34560"}}, {result, error_message})
    end)

    it("refuses a fluid whose recipe the force has not unlocked, naming the fluid", function()
      _G.prototypes = oil_game()

      local result, error_message = generator.generate("basic-oil-processing", 1000, fake_force{locked = {"basic-oil-processing"}})

      assert.are.same({nil, {"blueprint-generation.error-locked", {"fluid-name.petroleum-gas"}}}, {result, error_message})
    end)

    it("builds with the medium pole, one for each refinery, once the force has unlocked it", function()
      _G.prototypes = oil_game()

      local result = generator.generate("basic-oil-processing", 1000, fake_force{})

      assert.are.same({2, 0}, {count_named(result.entities, "medium-electric-pole"), count_named(result.entities, "small-electric-pole")})
    end)

    it("puts lamps on the blueprint once the force has unlocked the small lamp", function()
      _G.prototypes = oil_game()

      local lit = generator.generate("basic-oil-processing", 1000, fake_force{})
      local dark = generator.generate("basic-oil-processing", 1000, fake_force{locked = {"small-lamp"}})

      assert.is_true(count_named(lit.entities, "small-lamp") > 0)
      assert.are.equal(0, count_named(dark.entities, "small-lamp"))
    end)

    -- The game with the refinery's fluid boxes as given.
    local function with_boxes(boxes)
      return {machines = {["oil-refinery"] = refinery{pipe_boxes = boxes}}}
    end

    local refused = {
      {label = "the pipe connections of what it takes and of what it gives are on the same side of the machine", message = "error-fluid-row-pipes",
        game = with_boxes{{production_type = "input", position = {x = 1, y = 2}, direction = south},
          {production_type = "output", position = {x = -1, y = 2}, direction = south}}},
      {label = "the pipe connections of what it takes are in two rows, one on each side of the machine", message = "error-fluid-row-pipes",
        game = with_boxes{{production_type = "input", position = {x = 1, y = 2}, direction = south},
          {production_type = "input", position = {x = 1, y = -2}, direction = north}, {production_type = "output", position = {x = 0, y = -2}, direction = north}}},
      {label = "a pipe connection is at a side of the machine", message = "error-fluid-row-pipes",
        game = with_boxes{{production_type = "input", position = {x = -2, y = 0}, direction = west},
          {production_type = "output", position = {x = 0, y = -2}, direction = north}}},
      {label = "the machine gives no fluid", message = "error-fluid-row-pipes",
        game = with_boxes{{production_type = "input", position = {x = 1, y = 2}, direction = south}}},
      {label = "its recipe takes two fluids", message = "error-fluid-row-recipe", game = {recipes = {["basic-oil-processing"] = two_fluids}}},
      {label = "its recipe takes an item as well", message = "error-fluid-row-recipe", game = {recipes = {["basic-oil-processing"] = a_recipe{
        energy = 5, ingredients = {fluid_of(100, "crude-oil"), amount_of(1, "iron-plate")}, products = {fluid_of(45, "petroleum-gas")}, category = "oil-processing"}}}},
      {label = "its recipe makes two products", message = "error-fluid-row-recipe", game = {recipes = {["basic-oil-processing"] = a_recipe{
        energy = 5, ingredients = {fluid_of(100, "crude-oil")}, products = {fluid_of(45, "petroleum-gas"), fluid_of(5, "light-oil")}, category = "oil-processing"}}}},
      {label = "the pole of the blueprint reaches one tile only, which does not power a machine from beyond its pipes", message = "error-fluid-row-poles",
        game = {small_pole_supply_distance = 1.5}},
      {label = "the wire of the pole is shorter than a machine is wide", message = "error-fluid-row-poles", game = {small_pole_wire_distance = 4}},
    }

    for _, case in ipairs(refused) do
      it("refuses the fluid, saying which part cannot be laid out, when " .. case.label, function()
        _G.prototypes = oil_game(case.game)

        local result, error_message = generator.generate("basic-oil-processing", 1000)

        assert.are.same({nil, {"blueprint-generation." .. case.message, {"fluid-name.petroleum-gas"}}}, {result, error_message})
      end)
    end

    it("leaves out a pipe connection that is not an ordinary one, which an underground pipe's is not", function()
      local boxes = {table.unpack(PIPES)}
      boxes[#boxes + 1] = {production_type = "input", position = {x = -2, y = 0}, direction = west, connection_type = "underground"}
      _G.prototypes = oil_game(with_boxes(boxes))

      local result = generator.generate("basic-oil-processing", 1000)

      assert.are.equal(2, count_named(result.entities, "oil-refinery"))
    end)

    describe("a pipe connection the game gives in a way that is not understood stops the generator with a message", function()
      local function generate_with(box)
        _G.prototypes = oil_game(with_boxes{box})
        return function() generator.generate("basic-oil-processing", 1000) end
      end

      it("when it gives no position", function()
        local generate = generate_with{production_type = "input", direction = south, no_position = true}

        assert.has_error(generate, "generator: the game does not give the position of a pipe connection of the machine")
      end)

      it("when it points in a direction that is not north, east, south or west", function()
        local generate = generate_with{production_type = "input", position = {x = 1, y = 2}, direction = "northeast"}

        assert.has_error(generate, "generator: the game gives a pipe connection of the machine a direction other than north, east, south or west")
      end)

      it("when its position is the tile of the pipe outside the machine, not the tile of the machine at its edge", function()
        -- {x = 1, y = 3} is the tile 3,5, under the machine, and south of it 3,6: neither is a tile at the edge of the machine
        local generate = generate_with{production_type = "input", position = {x = 1, y = 3}, direction = south}

        assert.has_error(generate, "generator: a pipe connection of the machine is on the tile 3,5 and points to the tile 3,6, which is not from a tile at the edge of the machine to one outside it (5 tiles on a side)")
      end)

      it("when its position is the tile past the east edge of the machine", function()
        -- {x = 3, y = 2} is the tile 5,4, one column past the machine of 5 tiles, and south of it 5,5: not a tile of the machine
        local generate = generate_with{production_type = "input", position = {x = 3, y = 2}, direction = south}

        assert.has_error(generate, "generator: a pipe connection of the machine is on the tile 5,4 and points to the tile 5,5, which is not from a tile at the edge of the machine to one outside it (5 tiles on a side)")
      end)

      it("when it points into the machine", function()
        -- {x = 1, y = -2} is the tile 3,0, on the top row, and pointing south it goes to the tile 3,1, inside the machine
        local generate = generate_with{production_type = "input", position = {x = 1, y = -2}, direction = south}

        assert.has_error(generate, "generator: a pipe connection of the machine is on the tile 3,0 and points to the tile 3,1, which is not from a tile at the edge of the machine to one outside it (5 tiles on a side)")
      end)
    end)

    it("refuses a refinery that is not square", function()
      _G.prototypes = oil_game{machines = {["oil-refinery"] = refinery{height = 4}}}

      local result, error_message = generator.generate("basic-oil-processing", 1000)

      assert.are.same({nil, {"blueprint-generation.error-unsupported-machine"}}, {result, error_message})
    end)

    it("refuses a refinery that burns fuel, which a row of poles does not power", function()
      _G.prototypes = oil_game{machines = {["oil-refinery"] = refinery{burns = {"chemical"}}}}

      local result, error_message = generator.generate("basic-oil-processing", 1000)

      assert.are.same({nil, {"blueprint-generation.error-unsupported-energy"}}, {result, error_message})
    end)

    it("refuses the fluid when the game has no pipe", function()
      _G.prototypes = oil_game{missing_entities = {"pipe"}}

      local result, error_message = generator.generate("basic-oil-processing", 1000)

      assert.are.same({nil, {"blueprint-generation.error-missing-prototype"}}, {result, error_message})
    end)

    it("refuses a fluid that is not on offer", function()
      _G.prototypes = oil_game()

      local result, error_message = generator.generate("crude-oil", 1000)

      assert.are.same({nil, {"blueprint-generation.error-unsupported-pick"}}, {result, error_message})
    end)
  end)

  describe("an item made from a fluid, in chemical plants fed by the refineries that make the fluid", function()
    -- 20 petroleum gas make 1 solid fuel in 2 s: a plant of speed 1 makes 30 a minute and takes 600 gas; a refinery makes 540 gas a
    -- minute from 1,200 crude oil. The plant is 3 x 3 and takes its fluid at its two connections above it as it faces north (the
    -- tiles of the machine at its edge and the way they point, as the game gives them); the refinery is as in the row of refineries.
    local north, south = defines.direction.north, defines.direction.south
    local gas = a_recipe{energy = 5, ingredients = {fluid_of(100, "crude-oil")}, products = {fluid_of(45, "petroleum-gas")}, category = "oil-processing"}
    local fuel = a_recipe{energy = 2, ingredients = {fluid_of(20, "petroleum-gas")}, products = {amount_of(1, "solid-fuel")}, category = "chemistry"}
    local REFINERY_BOXES = {
      {production_type = "input", position = {x = -1, y = 2}, direction = south}, {production_type = "input", position = {x = 1, y = 2}, direction = south},
      {production_type = "output", position = {x = -2, y = -2}, direction = north}, {production_type = "output", position = {x = 0, y = -2}, direction = north},
      {production_type = "output", position = {x = 2, y = -2}, direction = north},
    }
    local PLANT_BOXES = {
      {production_type = "input", position = {x = -1, y = -1}, direction = north}, {production_type = "input", position = {x = 1, y = -1}, direction = north},
      {production_type = "output", position = {x = -1, y = 1}, direction = south}, {production_type = "output", position = {x = 1, y = 1}, direction = south},
    }

    local function fuel_game(changes)
      return fake_prototypes(builders.merged({
        machines = {
          ["oil-refinery"] = a_machine{crafting_speed = 1, size = 5, pipe_boxes = REFINERY_BOXES},
          ["chemical-plant"] = a_machine{crafting_speed = 1, size = 3, pipe_boxes = PLANT_BOXES},
        },
        recipes = {["basic-oil-processing"] = gas, ["solid-fuel-from-petroleum-gas"] = fuel},
      }, changes))
    end

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

    it("builds as many plants as the rate needs and as many refineries as they take gas from", function()
      _G.prototypes = fuel_game()

      local result = generator.generate("solid-fuel-from-petroleum-gas", 100)

      -- 100 / 30 = 3.3, 4 plants, which take 2,400 gas: 4.4 refineries, 5
      assert.are.same({5, 4}, {count_named(result.entities, "oil-refinery"), count_named(result.entities, "chemical-plant")})
    end)

    it("sets the recipe of the plants and turns them to face west, the refineries east", function()
      _G.prototypes = fuel_game()

      local result = generator.generate("solid-fuel-from-petroleum-gas", 100)

      local plant = builders.entities_named(result.entities, "chemical-plant")[1]
      local refinery = builders.entities_named(result.entities, "oil-refinery")[1]
      assert.are.same({"solid-fuel-from-petroleum-gas", defines.direction.west, "basic-oil-processing", defines.direction.east},
        {plant.recipe, plant.direction, refinery.recipe, refinery.direction})
    end)

    it("says what the blueprint makes and the crude oil it takes in a minute, and describes it with its machines", function()
      _G.prototypes = fuel_game()

      local result = generator.generate("solid-fuel-from-petroleum-gas", 100)

      -- 4 plants make 120, from 2,400 gas, which comes from 5,333.3 crude oil
      assert.are.same({"blueprint-generation.generated", "120", {"item-name.solid-fuel"}}, {result.message[1], result.message[2], result.message[3]})
      assert.are.same({"fluid-name.crude-oil"}, result.message[4][2][3])
      assert.are.equal("solid-fuel: 120 per minute from 5 x oil-refinery, 4 x chemical-plant", result.description)
    end)

    it("builds a blueprint that passes the validator: powered, wired, an inserter and a belt for each plant, two networks of pipes", function()
      _G.prototypes = fuel_game()

      local result = generator.generate("solid-fuel-from-petroleum-gas", 100)

      assert.are.same({}, validator.validate(result.entities, catalog()))
    end)

    it("builds one that passes it with everything researched: the medium pole, the lamps and the panel", function()
      _G.prototypes = fuel_game()

      local result = generator.generate("solid-fuel-from-petroleum-gas", 100, fake_force{})

      assert.are.same({}, validator.validate(result.entities, catalog()))
      assert.are.same({2, true}, {count_named(result.entities, "display-panel") + 1, count_named(result.entities, "small-lamp") > 0})
    end)

    it("puts a display panel with the crude oil beside the start of the pipe, once the force has unlocked it, and none for the item", function()
      _G.prototypes = fuel_game()

      local result = generator.generate("solid-fuel-from-petroleum-gas", 100, fake_force{})

      local panels = builders.entities_named(result.entities, "display-panel")
      assert.are.same({1, "fluid", "crude-oil"}, {#panels, panels[1].icon.type, panels[1].icon.name})
    end)

    it("names the most one blueprint makes: what the two lanes of the belt carry, which the plants fill in turn", function()
      _G.prototypes = fuel_game()

      assert.are.same({"blueprint-generation.max-rate", "900"}, generator.max_rate_message("solid-fuel-from-petroleum-gas")) -- 30 plants of 30
    end)

    it("names the most with fast belts: two lanes of 900, which the refineries of the test game make gas for 57 plants of", function()
      _G.prototypes = fuel_game{fast_belts = true}

      assert.are.same({"blueprint-generation.max-rate", "1710"}, generator.max_rate_message("solid-fuel-from-petroleum-gas", fake_force{}))
    end)

    it("names fewer when the refineries are so large that the gas of those that fit feeds fewer plants than a lane carries", function()
      -- 15 refineries of 21 tiles in 320 make 8,100 gas, which 13 plants take (390 a minute), where a lane would carry 15 plants
      local big = {
        {production_type = "input", position = {x = -1, y = 10}, direction = south}, {production_type = "input", position = {x = 1, y = 10}, direction = south},
        {production_type = "output", position = {x = -2, y = -10}, direction = north}, {production_type = "output", position = {x = 0, y = -10}, direction = north},
        {production_type = "output", position = {x = 2, y = -10}, direction = north},
      }
      _G.prototypes = fuel_game{small_pole_wire_distance = 21, machines = {
        ["oil-refinery"] = a_machine{crafting_speed = 1, size = 21, pipe_boxes = big},
        ["chemical-plant"] = a_machine{crafting_speed = 1, size = 3, pipe_boxes = PLANT_BOXES},
      }}

      assert.are.same({"blueprint-generation.max-rate", "390"}, generator.max_rate_message("solid-fuel-from-petroleum-gas"))
    end)

    it("names fewer when the plants are so large that fewer of them stand in 320 tiles than a lane carries", function()
      -- plants of 23 tiles: 13 in 320, where a lane would carry 15 (a pole reaches 11 tiles and a wire the 46 rows between two poles)
      local wide = {
        {production_type = "input", position = {x = -1, y = -11}, direction = north}, {production_type = "input", position = {x = 1, y = -11}, direction = north},
        {production_type = "output", position = {x = -1, y = 11}, direction = south}, {production_type = "output", position = {x = 1, y = 11}, direction = south},
      }
      _G.prototypes = fuel_game{small_pole_wire_distance = 47, small_pole_supply_distance = 11.5, machines = {
        ["oil-refinery"] = a_machine{crafting_speed = 1, size = 5, pipe_boxes = REFINERY_BOXES},
        ["chemical-plant"] = a_machine{crafting_speed = 1, size = 23, pipe_boxes = wide},
      }}

      assert.are.same({"blueprint-generation.max-rate", "390"}, generator.max_rate_message("solid-fuel-from-petroleum-gas"))
    end)

    describe("plastic bar, which takes coal, an item that comes in by a belt like an ore", function()
      -- 1 coal and 20 petroleum gas make 2 plastic bars in 1 s.
      local plastic = a_recipe{
        energy = 1, ingredients = {amount_of(1, "coal"), fluid_of(20, "petroleum-gas")}, products = {amount_of(2, "plastic-bar")}, category = "chemistry",
      }

      local function plastic_game(changes)
        return fuel_game(builders.merged({recipes = {["basic-oil-processing"] = gas, ["plastic-bar"] = plastic}}, changes))
      end

      local function plastic_catalog()
        return catalog()
      end

      it("builds the refineries and the plants, with an inserter on each side of each plant", function()
        _G.prototypes = plastic_game()

        local result = generator.generate("plastic-bar", 100)

        -- 100.8 a minute from each plant (the machine makes 120, which one inserter moves 50.4 of: two output inserters wind the belt): 1 plant,
        -- from 1,008 gas, which takes 2 refineries
        local plants = builders.entities_named(result.entities, "chemical-plant")
        assert.are.same({"plastic-bar", 1, 2}, {plants[1].recipe, #plants, count_named(result.entities, "oil-refinery")})
        assert.are.same({3, 0}, {count_named(result.entities, "inserter"), count_named(result.entities, "long-handed-inserter")}) -- the coal in and the plastic out, two of them
        assert.are.equal(4, count_named(result.entities, "pipe-to-ground")) -- two ends at each of two connections of the plant
      end)

      it("builds a blueprint that passes the validator: the inserters between the belts and the plants, powered", function()
        _G.prototypes = plastic_game()

        local result = generator.generate("plastic-bar", 300)

        assert.are.same({}, validator.validate(result.entities, plastic_catalog()))
      end)

      it("says what it makes, the crude oil and the coal it takes in a minute, and names the belt of coal that comes in", function()
        _G.prototypes = plastic_game()

        local result = generator.generate("plastic-bar", 100)

        -- 2 plants make 100.8 a minute, from 50.4 coal and 1,008 gas, which takes 2,240 crude oil
        assert.are.same({"blueprint-generation.generated-with-belts", "100.8", {"item-name.plastic-bar"}}, {result.message[1], result.message[2], result.message[3]})
        assert.are.same({"blueprint-generation.raw-amount", "2240", {"fluid-name.crude-oil"}}, result.message[4][2])
        assert.are.same({"blueprint-generation.raw-amount", "50.4", {"item-name.coal"}}, result.message[4][4])
        assert.are.same({"", {"item-name.coal"}}, result.message[5])
      end)

      it("puts a display panel with the crude oil and one with the coal at the top left corner, once the force has unlocked the panel", function()
        _G.prototypes = plastic_game()

        local result = generator.generate("plastic-bar", 100, fake_force{})

        local icons = {}
        for _, panel in ipairs(builders.entities_named(result.entities, "display-panel")) do
          icons[#icons + 1] = panel.icon.type .. " " .. panel.icon.name
        end
        table.sort(icons)
        assert.are.same({"fluid crude-oil", "item coal"}, icons)
      end)

      it("keeps the tile west of the entry of each free of lamps, the belt of coal on the top row", function()
        _G.prototypes = plastic_game()
        local lights = require("scripts.lights")
        local add, told = lights.add, nil
        lights.add = function(entities, options) told = options return add(entities, options) end

        generator.generate("plastic-bar", 100, fake_force{})
        lights.add = add

        assert.are.same({{x = -1, y = -1}, {x = -1, y = -4}}, told.free_tiles)
      end)

      describe("with plants of 3 x 3 or 7 x 7 and the poles of the game", function()
        -- plants of 7 x 7 take their fluid at the columns 1 and 5 above them, from the tiles of the machine at its top edge
        local seven = {
          {production_type = "input", position = {x = -2, y = -3}, direction = north}, {production_type = "input", position = {x = 2, y = -3}, direction = north},
          {production_type = "output", position = {x = -2, y = 3}, direction = south}, {production_type = "output", position = {x = 2, y = 3}, direction = south},
        }

        local function with_poles(size, supply, wire)
          return plastic_game{
            small_pole_supply_distance = supply, small_pole_wire_distance = wire,
            machines = {
              ["oil-refinery"] = a_machine{crafting_speed = 1, size = 5, pipe_boxes = REFINERY_BOXES},
              ["chemical-plant"] = a_machine{crafting_speed = 1, size = size, pipe_boxes = size == 7 and seven or PLANT_BOXES},
            },
          }
        end

        local function outcome(size, supply, wire)
          _G.prototypes = with_poles(size, supply, wire)
          local result, error_message = generator.generate("plastic-bar", 100)
          return result and "built" or error_message[1]
        end

        it("builds plants of 3 x 3 with the small pole", function()
          assert.are.equal("built", outcome(3, 2.5, 7.5))
        end)

        it("refuses plants of 3 x 3 whose pole reaches less than the two tiles a row of machines needs", function()
          assert.are.equal("blueprint-generation.error-fluid-row-poles", outcome(3, 0.5, 7.5))
        end)

        it("refuses plants of 3 x 3 when the wire is shorter than a plant is wide", function()
          assert.are.equal("blueprint-generation.error-fluid-row-poles", outcome(3, 2.5, 2.5))
        end)

        it("builds plants of 7 x 7 whose pole reaches 3 tiles and whose wire reaches the 14 rows between the poles beside the inserters (the poles of the second and of the fourth plant)", function()
          assert.are.equal("built", outcome(7, 3.5, 14))
        end)

        it("refuses plants of 7 x 7 whose wire is a row short of that", function()
          assert.are.equal("blueprint-generation.error-fluid-row-poles", outcome(7, 3.5, 13))
        end)

        it("gives plants of 7 x 7 one output inserter each and a plain belt, which the winding belt is not drawn for", function()
          _G.prototypes = with_poles(7, 3.5, 14)

          local result = generator.generate("plastic-bar", 100)

          -- a plant makes 50.4 a minute from its one inserter (two would make 100.8): 2 plants for 100, each with an inserter that brings the coal
          -- and one that takes the plastic away
          assert.are.same({2, 4}, {count_named(result.entities, "chemical-plant"), count_named(result.entities, "inserter")})
        end)

        it("builds plants of 7 x 7 that take no item with a wire of 14 and a pole that reaches 3 tiles or 2, which stand beside the inserters, and refuses a shorter wire", function()
          local function fuel_outcome(supply, wire)
            _G.prototypes = fuel_game{
              small_pole_supply_distance = supply, small_pole_wire_distance = wire,
              machines = {
                ["oil-refinery"] = a_machine{crafting_speed = 1, size = 5, pipe_boxes = REFINERY_BOXES},
                ["chemical-plant"] = a_machine{crafting_speed = 1, size = 7, pipe_boxes = seven},
              },
            }
            local result, error_message = generator.generate("solid-fuel-from-petroleum-gas", 100)
            return result and "built" or error_message[1]
          end

          assert.are.same({"built", "built", "blueprint-generation.error-fluid-row-poles"}, {fuel_outcome(3.5, 14), fuel_outcome(2.5, 14), fuel_outcome(2.5, 13)})
        end)
      end)

      it("limits the plants by the coal the belt carries, both lanes of it, when each takes a lot", function()
        -- 40 coal and 2 plastic a craft: the input inserter that moves X coal a minute makes X / 20 plastic, so the belt of 900 coal a minute
        -- feeds 900 / X plants and the lane of the output belt a great many
        local hungry = a_recipe{
          energy = 1, ingredients = {amount_of(40, "coal"), fluid_of(20, "petroleum-gas")}, products = {amount_of(2, "plastic-bar")}, category = "chemistry",
        }
        _G.prototypes = plastic_game{recipes = {["basic-oil-processing"] = gas, ["plastic-bar"] = hungry}}

        local result = generator.generate("plastic-bar", 1)
        local per_plant_coal = tonumber(result.message[4][4][2])
        local max = generator.max_rate_message("plastic-bar")

        -- plants of the same coal each: 900 / coal, whole, and what they make
        local plants = math.floor(900 / per_plant_coal + 1e-9)
        assert.are.same("blueprint-generation.max-rate", max[1])
        assert.are.equal(tostring(plants * per_plant_coal / 20), max[2])
      end)

      it("names the most one blueprint makes", function()
        _G.prototypes = plastic_game()

        local max = generator.max_rate_message("plastic-bar")

        -- two inserters of the test game move 100.8 a minute and wind the belt, whose two lanes carry 900: 8 plants, whose coal the belt carries easily
        assert.are.same({"blueprint-generation.max-rate", "806.4"}, max)
      end)

      it("stops with a message when the game has no pipe to ground, which takes the gas under the belt of coal", function()
        _G.prototypes = plastic_game{missing_entities = {"pipe-to-ground"}}

        local result, error_message = generator.generate("plastic-bar", 100)

        assert.are.same({nil, {"blueprint-generation.error-missing-prototype"}}, {result, error_message})
      end)

      it("does not need the long-handed inserter", function()
        _G.prototypes = plastic_game{missing_entities = {"long-handed-inserter"}}

        local result = generator.generate("plastic-bar", 100)

        assert.is_not_nil(result)
      end)

      it("goes on belts, as before, when the item is made and not raw", function()
        local made = a_recipe{energy = 1, ingredients = {amount_of(1, "iron-plate"), fluid_of(20, "petroleum-gas")}, products = {amount_of(1, "widget")}, category = "chemistry"}
        _G.prototypes = plastic_game{recipes = {["basic-oil-processing"] = gas, ["widget"] = made, ["iron-plate"] = a_recipe{energy = 3.2, ingredients = {amount_of(1, "iron-ore")}, products = {amount_of(1, "iron-plate")}, category = "smelting"}}}

        local result = generator.generate("widget", 10)

        assert.is_nil(result)
      end)
    end)

    describe("sulfur, which takes a second fluid that nothing makes: water, which comes in by a pipe", function()
      -- 30 water and 30 petroleum gas make 2 sulfur in 1 s, listed water first. The boxes of the plant are as above: the first takes
      -- the first fluid of the recipe (the second when `fluidbox_index` says so).
      local function sulfur(changes)
        return a_recipe(builders.merged({
          energy = 1, ingredients = {fluid_of(30, "water"), fluid_of(30, "petroleum-gas")}, products = {amount_of(2, "sulfur")}, category = "chemistry",
        }, changes))
      end

      -- The game with the recipe of sulfur given (the one above by default) and the other changes.
      local function sulfur_game(recipe, changes)
        return fuel_game(builders.merged({recipes = {["basic-oil-processing"] = gas, ["sulfur"] = recipe or sulfur{}}}, changes))
      end

      local function chemical_plants(result)
        return builders.entities_named(result.entities, "chemical-plant")
      end

      local function sulfur_catalog()
        local entries = catalog()
        entries["chemical-plant"] = {
          kind = "machine", width = 3, height = 3, needs_power = true,
          fluid_connections = {water = {{x = 0, y = -1}}, gas = {{x = 2, y = -1}}},
        }
        return entries
      end

      it("builds the refineries and the plants with the recipe set, and the pipes of both fluids", function()
        _G.prototypes = sulfur_game()

        local result = generator.generate("sulfur", 200)

        -- 100.8 a minute from each plant (two output inserters, which wind the belt): 2 plants for 200, from 3,024 gas, which takes 6 refineries
        assert.are.same({2, 6, "sulfur"}, {#chemical_plants(result), count_named(result.entities, "oil-refinery"), chemical_plants(result)[1].recipe})
        assert.are.equal(2, count_named(result.entities, "pipe-to-ground")) -- under the pipes of the gas between the first plant and the second
      end)

      it("mirrors the first plant, whose box that takes the gas is the second, which is at the top row of a plant facing west", function()
        _G.prototypes = sulfur_game()

        local plants = chemical_plants(generator.generate("sulfur", 200))

        assert.are.same({true, nil}, {plants[1].mirror, plants[2].mirror})
      end)

      it("mirrors the other when the recipe puts the gas in the first box (a fluidbox_index)", function()
        local swapped = sulfur{ingredients = {fluid_of(30, "water"), fluid_of(30, "petroleum-gas")}}
        swapped.ingredients[1].fluidbox_index, swapped.ingredients[2].fluidbox_index = 2, 1
        _G.prototypes = sulfur_game(swapped)

        local plants = chemical_plants(generator.generate("sulfur", 200))

        assert.are.same({nil, true}, {plants[1].mirror, plants[2].mirror})
      end)

      it("builds a blueprint that passes the validator: the water and the gas are two networks of pipes", function()
        _G.prototypes = sulfur_game()

        local result = generator.generate("sulfur", 300)

        assert.are.same({}, validator.validate(result.entities, sulfur_catalog()))
      end)

      it("says what it makes and the crude oil and the water it takes in a minute", function()
        _G.prototypes = sulfur_game()

        local result = generator.generate("sulfur", 100)

        assert.are.same({"blueprint-generation.generated", "100.8", {"item-name.sulfur"}}, {result.message[1], result.message[2], result.message[3]})
        assert.are.same({"fluid-name.crude-oil"}, result.message[4][2][3])
        assert.are.same({"fluid-name.water"}, result.message[4][4][3])
      end)

      it("takes both pipes that come in to the top left corner, the water on the top row, and leaves the tile west of each free of lamps", function()
        _G.prototypes = sulfur_game()

        local result = generator.generate("sulfur", 100, fake_force{})

        local ends, west_lamps = {}, 0
        for _, pipe in ipairs(builders.entities_named(result.entities, "pipe")) do
          local tile = grid.top_left_tile(pipe.position)
          if tile.x == 0 and tile.y < 0 then
            ends[#ends + 1] = tile.y
          end
        end
        for _, lamp in ipairs(builders.entities_named(result.entities, "small-lamp")) do
          local tile = grid.top_left_tile(lamp.position)
          west_lamps = west_lamps + ((tile.x == -1 and (tile.y == -1 or tile.y == -4)) and 1 or 0)
        end
        table.sort(ends)
        assert.are.same({{-4, -1}, 0}, {ends, west_lamps})
      end)

      it("keeps the tile west of each entry free of lamps, where the player joins the pipe", function()
        _G.prototypes = sulfur_game()
        local lights = require("scripts.lights")
        local add, told = lights.add, nil
        lights.add = function(entities, options) told = options return add(entities, options) end

        generator.generate("sulfur", 100, fake_force{})
        lights.add = add

        assert.are.same({{x = -1, y = -1}, {x = -1, y = -4}}, told.free_tiles)
      end)

      it("puts a display panel with each fluid that comes in at the north end, once the force has unlocked the panel", function()
        _G.prototypes = sulfur_game()

        local result = generator.generate("sulfur", 100, fake_force{})

        local icons = {}
        for _, panel in ipairs(builders.entities_named(result.entities, "display-panel")) do
          icons[#icons + 1] = panel.icon.type .. " " .. panel.icon.name
        end
        table.sort(icons)
        assert.are.same({"fluid crude-oil", "fluid water"}, icons)
      end)

      it("names the most one blueprint makes: as many plants as the two lanes of the belt carry, 8 of 100.8", function()
        _G.prototypes = sulfur_game()

        assert.are.same({"blueprint-generation.max-rate", "806.4"}, generator.max_rate_message("sulfur"))
      end)

      it("refuses a plant whose connections that take a fluid are not at its top and bottom rows", function()
        local middle = {
          {production_type = "input", position = {x = -1, y = -1}, direction = north}, {production_type = "input", position = {x = 0, y = -1}, direction = north},
          {production_type = "output", position = {x = -1, y = 1}, direction = south}, {production_type = "output", position = {x = 1, y = 1}, direction = south},
        }
        _G.prototypes = sulfur_game(nil, {machines = {
          ["oil-refinery"] = a_machine{crafting_speed = 1, size = 5, pipe_boxes = REFINERY_BOXES},
          ["chemical-plant"] = a_machine{crafting_speed = 1, size = 3, pipe_boxes = middle},
        }})

        local result, error_message = generator.generate("sulfur", 100)

        assert.are.same({nil, {"blueprint-generation.error-fluid-row-pipes", {"item-name.sulfur"}}}, {result, error_message})
      end)

      it("refuses a recipe that puts both fluids in the same box", function()
        local clash = sulfur{ingredients = {fluid_of(30, "water"), fluid_of(30, "petroleum-gas")}}
        clash.ingredients[1].fluidbox_index, clash.ingredients[2].fluidbox_index = 1, 1
        _G.prototypes = sulfur_game(clash)

        local result, error_message = generator.generate("sulfur", 100)

        assert.are.same({nil, {"blueprint-generation.error-fluid-row-pipes", {"item-name.sulfur"}}}, {result, error_message})
      end)

      it("stops with a message when the game has no pipe to ground", function()
        _G.prototypes = sulfur_game(nil, {missing_entities = {"pipe-to-ground"}})

        local result, error_message = generator.generate("sulfur", 100)

        assert.are.same({nil, {"blueprint-generation.error-missing-prototype"}}, {result, error_message})
      end)

      it("refuses a recipe whose two fluids the config has a recipe for each, which the layout does not take", function()
        _G.prototypes = sulfur_game()
        config.fluid_makers["water"] = "basic-oil-processing"

        local result, error_message = generator.generate("sulfur", 100)
        config.fluid_makers["water"] = nil

        assert.are.same({nil, {"blueprint-generation.error-fluid-row-recipe", {"item-name.sulfur"}}}, {result, error_message})
      end)

      it("names the first fluid when no recipe makes either, which have to come from somewhere", function()
        local raw = sulfur{ingredients = {fluid_of(30, "water"), fluid_of(30, "crude-oil")}}
        _G.prototypes = sulfur_game(raw)

        local result, error_message = generator.generate("sulfur", 100)

        assert.are.same({nil, {"blueprint-generation.error-no-recipe", {"fluid-name.water"}}}, {result, error_message})
      end)

      it("refuses a plant that burns fuel, whose poles beside the inserters do not reach it", function()
        _G.prototypes = sulfur_game(nil, {machines = {
          ["oil-refinery"] = a_machine{crafting_speed = 1, size = 5, pipe_boxes = REFINERY_BOXES},
          ["chemical-plant"] = a_machine{crafting_speed = 1, size = 3, pipe_boxes = PLANT_BOXES, burns = {"chemical"}},
        }})

        local result, error_message = generator.generate("sulfur", 100)

        assert.are.same({nil, {"blueprint-generation.error-unsupported-energy"}}, {result, error_message})
      end)

      it("does not take a recipe with no ingredients at all for a plant", function()
        local free = sulfur{ingredients = {}}
        _G.prototypes = sulfur_game(free)

        local ok = pcall(generator.generate, "sulfur", 100)

        assert.is_true(ok)
      end)

      it("refuses a recipe that takes three fluids", function()
        local three = sulfur{ingredients = {fluid_of(30, "water"), fluid_of(30, "petroleum-gas"), fluid_of(1, "crude-oil")}}
        _G.prototypes = sulfur_game(three)

        local result, error_message = generator.generate("sulfur", 100)

        assert.are.same({nil, {"blueprint-generation.error-fluid-single-input", {"item-name.sulfur"}}}, {result, error_message})
      end)
    end)

    it("stops with a message when the game gives a connection of the plant that is not at the edge of the machine", function()
      local wrong = {{production_type = "input", position = {x = 0, y = 0}, direction = north}}
      _G.prototypes = fuel_game{machines = {
        ["oil-refinery"] = a_machine{crafting_speed = 1, size = 5, pipe_boxes = REFINERY_BOXES},
        ["chemical-plant"] = a_machine{crafting_speed = 1, size = 3, pipe_boxes = wrong},
      }}

      local generate = function() generator.generate("solid-fuel-from-petroleum-gas", 100) end

      assert.has_error(generate)
    end)
  end)
end)
