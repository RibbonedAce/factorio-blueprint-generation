-- spec/config_spec.lua
-- Facts about the hardcoded choices that other code relies on. The values are
-- written out here on purpose, so changing one in config.lua is a deliberate act.
---@diagnostic disable: undefined-field  -- luassert's `assert` has fields (`assert.are`, `assert.is_nil`, ...) the editor cannot see

local config = require("scripts.config")

describe("config", function()
  describe("the machines", function()
    it("smelts in a stone furnace burning coal, and in a steel furnace once it is unlocked", function()
      local choice = config.machines.smelting

      assert.are.same({tiers = {"stone-furnace", "steel-furnace"}, fuel = "coal"}, choice)
    end)

    it("crafts in a basic assembling machine, which burns nothing, and in assembling machine 2 once it is unlocked", function()
      local choice = config.machines.crafting

      assert.are.same({tiers = {"assembling-machine-1", "assembling-machine-2"}}, choice)
    end)

    it("crafts the advanced category in the same machines", function()
      local choice = config.machines["advanced-crafting"]

      assert.are.same({tiers = {"assembling-machine-1", "assembling-machine-2"}}, choice)
    end)
  end)

  describe("the tiers of the poles and the belts", function()
    it("has the small pole for every blueprint and the medium pole once it is unlocked", function()
      local poles = config.entities.poles

      assert.are.same({"small-electric-pole", "medium-electric-pole"}, poles)
    end)

    it("has the basic belt, splitter and underground belt, and the fast ones as a whole", function()
      local belts = config.entities.belts

      assert.are.same({
        {belt = "transport-belt", splitter = "splitter", underground = "underground-belt"},
        {belt = "fast-transport-belt", splitter = "fast-splitter", underground = "fast-underground-belt"},
      }, belts)
    end)
  end)

  describe("the recipes a player can ask for", function()
    it("has the recipe of an item that is made from raw items", function()
      assert.is_true(config.recipes["iron-plate"])
    end)

    it("has the recipe of an item that is made through other recipes", function()
      assert.is_true(config.recipes["iron-gear-wheel"])
    end)

    it("has basic oil processing, whose product is a fluid", function()
      assert.is_true(config.recipes["basic-oil-processing"])
    end)

    it("has no recipe that makes petroleum gas from other inputs and makes other products too", function()
      assert.are.same({nil, nil}, {config.recipes["advanced-oil-processing"], config.recipes["coal-liquefaction"]})
    end)
  end)

  describe("the default recipe", function()
    it("chooses the recipe of iron plate by default when the window opens", function()
      local default = config.default_recipe

      assert.are.equal("iron-plate", default)
    end)

    it("chooses a default that can be generated when the window opens", function()
      local recipe = config.recipes[config.default_recipe]

      assert.is_not_nil(recipe)
    end)
  end)
end)
