-- spec/fluid_supplier_generator_spec.lua
-- A recipe on belts whose last step takes a fluid that machines make: a barrel of petroleum gas (the gas from refineries) or of sulfuric acid (the acid
-- from the chain of its sulfur plants), and a flask, which is filled the same way and made of iron plates alone, so that the original design of the belts can
-- build it (a barrel is made of steel, whose furnace takes its fuel from a belt that design has no room for). The part that makes the fluid is a block that
-- stands right west of the column of the last step, its pipe joined to the trunk of that column's pipes, with no pump (see scripts/rows.lua), planned for
-- what the machines of the step take of the fluid. The stand-ins of the game are those of spec/support/oil_game.lua.
---@diagnostic disable: undefined-field  -- luassert's `assert` has fields (`assert.are`, `assert.is_nil`, ...) the editor cannot see
---@diagnostic disable: need-check-nil  -- the assertion before each use fails the test first if the result is nil
---@diagnostic disable: global-in-non-module  -- `_G.prototypes = ...` is how a spec fakes the game's global

local builders = require("spec.support.builders")
local config = require("scripts.config")
local generator = require("scripts.generator")
local oil_game = require("spec.support.oil_game")
local validator = require("spec.support.blueprint_validator")

local the_game, named, catalog, with_medium_pole = oil_game.the_game, oil_game.named, oil_game.catalog, oil_game.with_medium_pole
local taken, taken_in_order, panels_of = oil_game.taken, oil_game.taken_in_order, oil_game.panels_of
local fake_force = builders.fake_force

-- What each recipe makes at the most, and what limits it: where the steps of belts or the part that makes the fluid cannot go on.
local CASES = {
  {
    recipe = "gas-flask", fluid = "petroleum-gas", alone = "basic-oil-processing", designs = {"original", "new"}, rates = {1, 10, 225}, most = "225", pumps = 1,
    -- two iron plates for each flask, on a lane of 450 a minute (the refineries could make flasks' worth of gas up to 691)
    panels = {"coal", "crude-oil", "iron-ore"},
    described = "gas-flask: 18.75 per minute from 2 x stone-furnace, 2 x oil-refinery, 1 x assembling-machine-2",
    taken = {coal = "2.7", ["crude-oil"] = "2400", ["iron-ore"] = "37.5"}, order = {"iron-ore", "coal", "crude-oil"},
  },
  {
    recipe = "acid-flask", fluid = "sulfuric-acid", alone = "sulfuric-acid", designs = {"original", "new"}, rates = {1, 10, 84}, most = "84", pumps = 2,
    -- the chain that makes the acid makes 4,200 a minute at the most, which is 84 flasks of 50 units
    panels = {"coal", "crude-oil", "iron-ore", "water"},
    described = "acid-flask: 18.75 per minute from 2 x stone-furnace, 6 x oil-refinery, 5 x chemical-plant, 2 x stone-furnace, 1 x assembling-machine-2",
    taken = {coal = "5.4", ["crude-oil"] = "6720", ["iron-ore"] = "75", water = "5544"}, order = {"iron-ore", "coal", "water", "crude-oil"},
  },
  {
    recipe = "petroleum-gas-barrel", fluid = "petroleum-gas", alone = "basic-oil-processing", designs = {"new"}, rates = {1, 10, 180}, most = "180", pumps = 1,
    panels = {"coal", "crude-oil", "iron-ore"},
    described = "petroleum-gas-barrel: 11.25 per minute from 3 x stone-furnace, 3 x stone-furnace, 1 x assembling-machine-2, 2 x oil-refinery, 1 x assembling-machine-2",
    taken = {coal = "8.1", ["crude-oil"] = "2400", ["iron-ore"] = "56.25"}, order = {"iron-ore", "coal", "crude-oil"},
  },
  {
    recipe = "sulfuric-acid-barrel", fluid = "sulfuric-acid", alone = "sulfuric-acid", designs = {"new"}, rates = {1, 10, 84}, most = "84", pumps = 2,
    panels = {"coal", "crude-oil", "iron-ore", "water"},
    described = "sulfuric-acid-barrel: 11.25 per minute from 3 x stone-furnace, 3 x stone-furnace, 1 x assembling-machine-2, 3 x oil-refinery, 3 x chemical-plant, "
      .. "1 x stone-furnace, 1 x assembling-machine-2",
    taken = {coal = "9.45", ["crude-oil"] = "3360", ["iron-ore"] = "75", water = "3192"}, order = {"iron-ore", "coal", "water", "crude-oil"},
  },
}

local function count_named(entities, name)
  local count = 0
  for _, entity in ipairs(entities) do
    count = count + (entity.name == name and 1 or 0)
  end
  return count
end

local function entries_for(design)
  return design == "new" and with_medium_pole(catalog()) or catalog()
end

local function force_for(design)
  return design == "new" and fake_force{} or nil
end

describe("a recipe on belts whose last step takes a fluid that machines make", function()
  for _, case in ipairs(CASES) do
    for _, design in ipairs(case.designs) do
      local force = force_for(design)

      it("builds " .. case.recipe .. " in the " .. design .. " design, up to the most it makes", function()
        _G.prototypes = the_game()

        for _, rate in ipairs(case.rates) do
          local result, error_message = generator.generate(case.recipe, rate, force)

          assert.is_not_nil(result, error_message and error_message[1])
          assert.are.same({}, validator.validate(named(result.entities), entries_for(design)))
          assert.has_consecutive_numbers(result.entities)
        end
      end)

      it("puts a pump on each pipe that comes in for " .. case.recipe .. " in the " .. design .. " design, and none for the " .. case.fluid, function()
        _G.prototypes = the_game()

        local result = generator.generate(case.recipe, case.rates[2], force)

        assert.are.equal(case.pumps, count_named(result.entities, "pump"))
      end)

      it("refuses " .. case.recipe .. " above the most it makes in the " .. design .. " design", function()
        _G.prototypes = the_game()

        local result, error_message = generator.generate(case.recipe, tonumber(case.most) + 1, force)

        assert.is_nil(result)
        assert.are.same({"blueprint-generation.error-rate-too-high", case.most}, error_message)
        assert.are.same({"blueprint-generation.max-rate", case.most}, generator.max_rate_message(case.recipe, force))
      end)
    end

    local last = case.designs[#case.designs]

    it("lists the machines that make the fluid of " .. case.recipe .. " right before the machines of its last step", function()
      _G.prototypes = the_game()

      local result = generator.generate(case.recipe, 10, force_for(last))

      assert.are.equal(case.described, result.description)
    end)

    it("takes what the machines that make the fluid take, not the fluid itself: no " .. case.fluid .. " comes in, and the raws are those of the part on its own", function()
      _G.prototypes = the_game()
      local together = generator.generate(case.recipe, 10, force_for(last))
      local amounts = taken(together)

      assert.are.same(case.taken, amounts)
      assert.is_nil(amounts[case.fluid])
    end)

    it("lists the fluids of " .. case.recipe .. " last, after the raw items and the fuel, as the message does for any recipe", function()
      _G.prototypes = the_game()

      local result = generator.generate(case.recipe, 10, force_for(last))

      assert.are.same(case.order, taken_in_order(result))
    end)

    it("makes the part that makes the fluid of " .. case.recipe .. " for the gas or the acid that the machines of its last step take, as the part makes it on its own", function()
      _G.prototypes = the_game()
      local result = generator.generate(case.recipe, 10, force_for(last))
      local per_minute = tonumber(result.description:match(": ([%d%.]+) per minute")) * 50 -- a flask or a barrel takes 50 units of the fluid

      local alone = taken(generator.generate(case.alone, per_minute))

      assert.are.equal(alone["crude-oil"], taken(result)["crude-oil"])
      assert.are.equal(alone.water, taken(result).water)
    end)

    it("puts a panel on the crude oil that comes in, above the belts, in the design with one belt of each material", function()
      _G.prototypes = the_game()

      local result = generator.generate(case.recipe, 10, fake_force{})

      assert.are.same(case.panels, panels_of(result.entities))
    end)
  end

  it("still brings in the water of a barrel of water by a pump", function()
    _G.prototypes = the_game()

    local result = generator.generate("water-barrel", 10, fake_force{})

    assert.are.same({1, {}, true}, {count_named(result.entities, "pump"), validator.validate(named(result.entities), with_medium_pole(catalog())), taken(result).water ~= nil})
  end)

  describe("with an item made in plants in the same blueprint", function()
    -- The gadget takes the gas, plastic bars and iron plates, so the blueprint has the refineries and plants of the plastic as a column of the row and, right
    -- west of the pipes of the gadget's machines, the refineries of the gas they take: two sets of refineries, each with its own network of gas, which the
    -- validator tells apart here by the east one being the supplier's (the plastic's block stands west of it).
    local function named_apart(entities)
      local copies, last_x = named(entities), -1
      for _, entity in ipairs(copies) do
        last_x = entity.name == "oil-refinery" and math.max(last_x, entity.position.x) or last_x
      end
      for _, entity in ipairs(copies) do
        if entity.name == "oil-refinery" and entity.position.x == last_x then
          entity.name = "supplier-refinery"
        elseif entity.name == "assembling-machine-2" and entity.recipe == "gas-gadget" then
          entity.name = "gadget-filler"
        end
      end
      return copies
    end

    local function catalog_apart(design)
      local entries, refinery = entries_for(design), catalog()["oil-refinery"]
      entries["supplier-refinery"] = {
        kind = "machine", width = refinery.width, height = refinery.height, needs_power = true, networks = {input = "crude", output = "supplier-gas"},
        fluid_connections = refinery.fluid_connections,
      }
      entries["gadget-filler"] = {kind = "machine", width = 3, height = 3, needs_power = true, fluid_connections = {["supplier-gas"] = {{x = 1, y = -1}}}}
      return entries
    end

    for _, design in ipairs({"original", "new"}) do
      it("builds it in the " .. design .. " design, the two sets of refineries two networks of gas and one of crude oil", function()
        _G.prototypes = the_game()

        for _, rate in ipairs({1, 10, 30}) do
          local result, error_message = generator.generate("gas-gadget", rate, force_for(design))

          assert.is_not_nil(result, error_message and error_message[1])
          assert.are.same({}, validator.validate(named_apart(result.entities), catalog_apart(design)))
        end
      end)
    end

    it("lists the machines of the plastic, then those that make the gas of the gadget right before the machines of the gadget", function()
      _G.prototypes = the_game()

      local result = generator.generate("gas-gadget", 10)

      assert.are.equal("gas-gadget: 16.8 per minute from 2 x oil-refinery, 1 x chemical-plant, 1 x stone-furnace, 2 x oil-refinery, 1 x assembling-machine-2", result.description)
    end)
  end)

  describe("a pipeline of only so many tiles", function()
    local tiles

    before_each(function()
      tiles = config.fluid_pipeline_tiles
      config.fluid_pipeline_tiles = 10 -- two refineries one under the other
    end)

    after_each(function()
      config.fluid_pipeline_tiles = tiles
    end)

    it("limits the flasks by the gas the refineries that fit make", function()
      _G.prototypes = the_game()

      local result, error_message = generator.generate("gas-flask", 22, fake_force{})

      assert.is_nil(result)
      assert.are.same({"blueprint-generation.error-rate-too-high", "21.6"}, error_message)
    end)

    it("takes what a craft takes of the fluid over what a craft makes", function()
      _G.prototypes = the_game()

      local refused, error_message = generator.generate("twin-flask", 44, fake_force{})
      local result = generator.generate("twin-flask", 43.2, fake_force{})

      assert.is_nil(refused)
      assert.are.same({"blueprint-generation.error-rate-too-high", "43.2"}, error_message)
      assert.are.equal("twin-flask: 43.2 per minute from 3 x stone-furnace, 2 x oil-refinery, 1 x assembling-machine-2", result.description)
      assert.are.same({coal = "3.11", ["crude-oil"] = "2400", ["iron-ore"] = "43.2"}, taken(result))
      assert.are.same({}, validator.validate(named(result.entities), with_medium_pole(catalog())))
    end)

    it("makes what the gas allows and no more", function()
      _G.prototypes = the_game()

      local result = generator.generate("gas-flask", 21.6, fake_force{})

      assert.are.equal("gas-flask: 21.6 per minute from 3 x stone-furnace, 2 x oil-refinery, 1 x assembling-machine-2", result.description)
      assert.are.same({}, validator.validate(named(result.entities), with_medium_pole(catalog())))
    end)
  end)

  describe("what it refuses", function()
    it("stops when a step that is not the last takes a fluid that machines make, in both designs, and says which", function()
      for _, force in ipairs({false, fake_force{}}) do
        _G.prototypes = the_game()

        local result, error_message = generator.generate("gas-crate", 1, force or nil)

        assert.is_nil(result)
        assert.are.same({"blueprint-generation.error-made-fluid", {"item-name.gas-flask"}, {"fluid-name.petroleum-gas"}}, error_message)
      end
    end)

    it("refuses when the game has no recipe that makes the fluid, and says which fluid", function()
      _G.prototypes = oil_game.the_game_without_recipe("basic-oil-processing")

      local result, error_message = generator.generate("gas-flask", 10)

      assert.is_nil(result)
      assert.are.same({"blueprint-generation.error-no-recipe", {"fluid-name.petroleum-gas"}}, error_message)
    end)

    it("refuses when the recipe the config names for the fluid is not laid out as a part that makes a fluid, with the message of a fluid that machines make", function()
      _G.prototypes = the_game()
      local named_recipe = config.fluid_makers["petroleum-gas"]
      config.fluid_makers["petroleum-gas"] = "plastic-bar" -- a recipe that makes an item
      local ok, result, error_message = pcall(generator.generate, "gas-flask", 10)
      config.fluid_makers["petroleum-gas"] = named_recipe

      assert.is_true(ok)
      assert.is_nil(result)
      assert.are.same({"blueprint-generation.error-made-fluid", {"item-name.gas-flask"}, {"fluid-name.petroleum-gas"}}, error_message)
    end)

    it("refuses when the refineries that make the fluid have a pipe connection that the row cannot lay out, with the message of the row", function()
      local boxes = {}
      for index, box in ipairs(oil_game.REFINERY_BOXES) do
        boxes[index] = box
      end
      boxes[1] = {production_type = "input", position = {x = -2, y = 0}, direction = defines.direction.west} -- at the side of the machine
      _G.prototypes = oil_game.the_game_with_refinery(boxes)

      local result, error_message = generator.generate("gas-flask", 10)

      assert.is_nil(result)
      assert.are.same({"blueprint-generation.error-fluid-row-pipes", {"fluid-name.petroleum-gas"}}, error_message)
    end)

    it("refuses when the game has no oil refinery for the part that makes the fluid", function()
      _G.prototypes = the_game{missing_entities = {"oil-refinery"}}

      local result, error_message = generator.generate("gas-flask", 10)

      assert.is_nil(result)
      assert.are.same({"blueprint-generation.error-missing-prototype"}, error_message)
    end)
  end)
end)
