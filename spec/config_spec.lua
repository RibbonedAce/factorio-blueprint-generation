-- spec/config_spec.lua
-- Facts about the hardcoded choices that other code relies on. The values are
-- written out here on purpose, so changing one in config.lua is a deliberate act.
---@diagnostic disable: undefined-field  -- luassert's `assert` has fields (`assert.are`, `assert.is_nil`, ...) the editor cannot see

local config = require("scripts.config")

describe("config", function()
  describe("the machines", function()
    it("smelts in a stone furnace burning coal", function()
      local choice = config.machines.smelting

      assert.are.same({machine = "stone-furnace", fuel = "coal"}, choice)
    end)

    it("crafts in a basic assembling machine, which burns nothing", function()
      local choice = config.machines.crafting

      assert.are.same({machine = "assembling-machine-1"}, choice)
    end)
  end)

  describe("the default product", function()
    it("chooses iron plate by default when the window opens", function()
      local default = config.default_product

      assert.are.equal("iron-plate", default)
    end)

    it("chooses a default that can be generated when the window opens", function()
      local product = config.products[config.default_product]

      assert.is_not_nil(product)
    end)
  end)
end)
