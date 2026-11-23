-- spec/plants_supplier_generator_spec.lua
-- A recipe on belts that takes an item made in plants: advanced circuit takes plastic bar (petroleum gas from refineries and coal, in plants), rocket
-- takes explosives (the chain of its sulfur plants and coal) and accumulator takes battery (furnaces of iron and copper plates and the chain of the
-- sulfuric acid). The part made in plants is a block that stands as a column among the columns of machines (see scripts/plants_block.lua and
-- scripts/rows.lua), planned for the share of the rate the recipe asks of it. The stand-ins of the game are those of the other chain specs: a
-- refinery of 5 x 5 and a chemical plant of 3 x 3, a furnace and an inserter that move 50.4 items a minute.
---@diagnostic disable: undefined-field  -- luassert's `assert` has fields (`assert.are`, `assert.is_nil`, ...) the editor cannot see
---@diagnostic disable: need-check-nil  -- the assertion before each use fails the test first if the result is nil
---@diagnostic disable: global-in-non-module  -- `_G.prototypes = ...` is how a spec fakes the game's global

local generator = require("scripts.generator")
local oil_game = require("spec.support.oil_game")
local validator = require("spec.support.blueprint_validator")
local builders = require("spec.support.builders")

local the_game, named, catalog, with_medium_pole = oil_game.the_game, oil_game.named, oil_game.catalog, oil_game.with_medium_pole
local taken, panels_of = oil_game.taken, oil_game.panels_of
local fake_force = builders.fake_force

-- The recipes, the part of each that is made in plants, and the most each makes a minute: where the steps of belts or the part in plants cannot go on.
local CASES = {
  {
    recipe = "advanced-circuit", what = "plastic bar", alone = "plastic-bar", needs = 2, rates = {1, 20, 75}, most = "75", panels = {"coal", "copper-ore", "crude-oil", "iron-ore"},
    -- 75 advanced circuits a minute take 450 cables a minute for each of their two circuits: a lane of the belt (the plastic would go to 806)
    described_at = 30, described = "advanced-circuit: 30 per minute from 4 x stone-furnace, 5 x stone-furnace, 2 x assembling-machine-1, 3 x assembling-machine-1, "
      .. "2 x oil-refinery, 1 x chemical-plant, 4 x stone-furnace, 2 x assembling-machine-1, 6 x assembling-machine-1",
  },
  {
    recipe = "rocket", what = "explosives", alone = "explosives", needs = 1, rates = {1, 30, 225}, most = "225", panels = {"coal", "crude-oil", "iron-ore", "water"},
    -- two iron plates for each rocket, on a lane of 450 a minute (the explosives would go to 900)
    described_at = 30, described = "rocket: 30 per minute from 3 x oil-refinery, 2 x chemical-plant, 4 x stone-furnace, 4 x assembling-machine-1",
  },
  {
    recipe = "accumulator", what = "battery", alone = "battery", needs = 5, rates = {1, 4, 42}, most = "42", panels = {"coal", "copper-ore", "crude-oil", "iron-ore", "water"},
    -- five batteries for each accumulator, and the part makes 210 a minute at the most
    described_at = 4, described = "accumulator: 6 per minute from 1 x stone-furnace, 5 x stone-furnace, 3 x oil-refinery, 5 x chemical-plant, 2 x assembling-machine-1",
  },
}

local DESIGNS = {{name = "the original design of the belts", new = false}, {name = "the design with one belt of each material", new = true}}

describe("a recipe on belts that takes an item made in plants", function()
  for _, case in ipairs(CASES) do
    for _, design in ipairs(DESIGNS) do
      local force = design.new and fake_force{} or nil

      it("builds " .. case.recipe .. ", with the " .. case.what .. " made in plants, in " .. design.name .. "", function()
        _G.prototypes = the_game()

        for _, rate in ipairs(case.rates) do
          local result, error_message = generator.generate(case.recipe, rate, force)

          assert.is_not_nil(result, error_message and error_message[1])
          local entries = design.new and with_medium_pole(catalog()) or catalog()
          assert.are.same({}, validator.validate(named(result.entities), entries))
          assert.has_consecutive_numbers(result.entities)
        end
      end)

      it("refuses " .. case.recipe .. " above the most it makes in " .. design.name, function()
        _G.prototypes = the_game()

        local result, error_message = generator.generate(case.recipe, tonumber(case.most) + 1, force)

        assert.is_nil(result)
        assert.are.same({"blueprint-generation.error-rate-too-high", case.most}, error_message)
      end)
    end

    it("lists the machines of the " .. case.what .. " in the description of " .. case.recipe .. ", where its step stands among the steps", function()
      _G.prototypes = the_game()

      local result = generator.generate(case.recipe, case.described_at)

      assert.are.equal(case.described, result.description)
    end)

    it("says the fluids of the " .. case.what .. " that the player brings, as the part takes them on its own, with the iron ore and the copper ore the belts take", function()
      _G.prototypes = the_game()
      local rate = case.rates[2]

      local together = taken(generator.generate(case.recipe, rate))
      local alone = taken(generator.generate(case.alone, case.needs * rate))

      assert.are.equal(alone["crude-oil"], together["crude-oil"])
      assert.are.equal(alone.water, together.water)
      assert.is_not_nil(together["iron-ore"])
    end)

    it("puts a panel on each of the fluids that come in by pipe, with those of the belts that come in", function()
      _G.prototypes = the_game()

      local result = generator.generate(case.recipe, case.rates[2], fake_force{})

      assert.are.same(case.panels, panels_of(result.entities))
    end)
  end

  describe("a part made in plants lower in the tree, or that takes two fluids", function()
    -- A box of circuits takes advanced circuits, which take the plastic bar: the plants are a grandchild of the last step, with a step on belts between. A pack
    -- of sulfur takes the sulfur, whose plants take water as well as the gas the refineries make: the second fluid comes in by a pipe of its own.
    local LOWER = {
      {recipe = "circuit-box", fluids = {"crude-oil"}, panels = {"coal", "copper-ore", "crude-oil", "iron-ore"}, machines = "2 x oil-refinery, 1 x chemical-plant"},
      {recipe = "sulfur-pack", fluids = {"crude-oil", "water"}, panels = {"coal", "crude-oil", "iron-ore", "water"}, machines = "oil-refinery"},
    }

    for _, case in ipairs(LOWER) do
      for _, design in ipairs(DESIGNS) do
        it("builds " .. case.recipe .. " in " .. design.name .. "", function()
          _G.prototypes = the_game()

          for _, rate in ipairs({1, 10}) do
            local result, error_message = generator.generate(case.recipe, rate, design.new and fake_force{} or nil)

            assert.is_not_nil(result, error_message and error_message[1])
            local entries = design.new and with_medium_pole(catalog()) or catalog()
            assert.are.same({}, validator.validate(named(result.entities), entries))
            assert.is_truthy(result.description:find(case.machines, 1, true))
          end
        end)
      end

      it("takes the fluids of the part of " .. case.recipe .. " as the part takes them, and puts a panel on each that comes in by a pipe", function()
        _G.prototypes = the_game()

        local result = generator.generate(case.recipe, 10, fake_force{})

        local amounts = taken(result)
        for _, fluid in ipairs(case.fluids) do
          assert.is_not_nil(amounts[fluid], fluid)
        end
        assert.are.same(case.panels, panels_of(result.entities))
      end)
    end

    it("lists the fluids of the part after the raw items and the fuel", function()
      _G.prototypes = the_game()

      local result = generator.generate("sulfur-pack", 10)

      assert.are.same({"iron-ore", "coal", "crude-oil", "water"}, oil_game.taken_in_order(result))
    end)
  end)

  it("takes the coal of the plastic plants and of the furnaces together", function()
    _G.prototypes = the_game()

    local amounts = taken(generator.generate("advanced-circuit", 30))

    -- 50.4 for the plants (a block makes 100.8 plastic bar a minute) and 15.12 for the 13 furnaces' worth of 4.32 + 6.48 + 4.32
    assert.are.same({["iron-ore"] = "60", ["copper-ore"] = "150", coal = "65.52", ["crude-oil"] = "2240"}, amounts)
  end)

  it("refuses when the game has no oil refinery or no chemical plant for the plants of the part", function()
    for _, missing in ipairs({"oil-refinery", "chemical-plant"}) do
      _G.prototypes = the_game{missing_entities = {missing}}

      local result, error_message = generator.generate("advanced-circuit", 10)

      assert.is_nil(result)
      assert.are.same({"blueprint-generation.error-missing-prototype"}, error_message)
    end
  end)

  it("refuses when the game has no recipe that makes the fluid the plants take, and says which fluid", function()
    _G.prototypes = oil_game.the_game_without_recipe("basic-oil-processing")

    local result, error_message = generator.generate("advanced-circuit", 10)

    assert.is_nil(result)
    assert.are.same({"blueprint-generation.error-no-recipe", {"fluid-name.petroleum-gas"}}, error_message)
  end)
end)
