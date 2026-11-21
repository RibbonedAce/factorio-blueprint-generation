-- spec/recipes_spec.lua
-- Which recipes the window offers: the ones of the config the force has unlocked, and the filters of the picker (see
-- scripts/recipes.lua).
---@diagnostic disable: undefined-field  -- luassert's `assert` has fields (`assert.are`, `assert.is_nil`, ...) the editor cannot see
---@diagnostic disable: global-in-non-module  -- `_G.prototypes = ...` is how a spec fakes the game's global

local builders = require("spec.support.builders")
local config = require("scripts.config")
local recipes = require("scripts.recipes")

local fake_prototypes, a_recipe, fake_force = builders.fake_prototypes, builders.a_recipe, builders.fake_force
local amount_of, fluid_of = builders.amount_of, builders.fluid_of

describe("recipes", function()
  local plate = a_recipe{energy = 3.2, ingredients = {amount_of(1, "iron-ore")}, products = {amount_of(1, "iron-plate")}, category = "smelting"}
  local brick = a_recipe{energy = 3.2, ingredients = {amount_of(2, "stone")}, products = {amount_of(1, "stone-brick")}, category = "smelting"}
  local gear = a_recipe{energy = 0.5, ingredients = {amount_of(2, "iron-plate")}, products = {amount_of(1, "iron-gear-wheel")}}
  local inserter = a_recipe{energy = 0.5, ingredients = {amount_of(1, "iron-plate")}, products = {amount_of(1, "inserter")}}

  local function game()
    return fake_prototypes{recipes = {["iron-plate"] = plate, ["stone-brick"] = brick, ["iron-gear-wheel"] = gear, ["inserter"] = inserter}}
  end

  describe("the recipes on offer", function()
    local function contains(list, name)
      for _, entry in ipairs(list) do
        if entry == name then
          return true
        end
      end
      return false
    end

    it("lists the recipes that are unlocked", function()
      _G.prototypes = game()

      local offered = recipes.unlocked(fake_force{})

      assert.is_true(contains(offered, "inserter"))
      assert.is_true(contains(offered, "iron-gear-wheel"))
      assert.is_true(contains(offered, "iron-plate"))
    end)

    it("leaves out the recipe that is locked, and not the recipes of what is made from it", function()
      _G.prototypes = game()

      local offered = recipes.unlocked(fake_force{locked = {"iron-gear-wheel"}})

      assert.is_false(contains(offered, "iron-gear-wheel"))
      assert.is_true(contains(offered, "inserter")) -- its gears are not looked at
      assert.is_true(contains(offered, "iron-plate"))
      assert.is_true(contains(offered, "stone-brick"))
    end)

    it("keeps a recipe that cannot be made for another reason, so choosing it says why", function()
      _G.prototypes = game()

      local offered = recipes.unlocked(fake_force{})

      assert.is_true(contains(offered, "pipe")) -- the game here has no recipe for it
    end)

    it("lists the names in order", function()
      _G.prototypes = game()

      local offered = recipes.unlocked(fake_force{})

      local sorted = {table.unpack(offered)}
      table.sort(sorted)
      assert.are.same(sorted, offered)
    end)

    it("counts the recipes of the force it is given", function()
      _G.prototypes = game()

      local with_everything = recipes.unlocked(fake_force{})
      local without_inserter = recipes.unlocked(fake_force{locked = {"inserter"}})

      assert.are.equal(#with_everything - 1, #without_inserter)
      assert.is_false(contains(without_inserter, "inserter"))
      assert.is_true(contains(without_inserter, "iron-plate"))
    end)
  end)

  describe("the filters of the picker of recipes, which cannot name a recipe", function()
    -- The picker is a list of the game's recipes, and a filter of recipes cannot ask for a recipe by its name. So the filters
    -- ask for what the recipes on offer make: the ones that make one of their items and no fluid, or one of their fluids, and
    -- that are not hidden (a hidden recipe, such as the recycling of an item, can make them too).
    local oil = a_recipe{energy = 5, ingredients = {fluid_of(100, "crude-oil")}, products = {fluid_of(45, "petroleum-gas")}, category = "oil-processing"}

    it("ask for the recipes that make an item of the recipes on offer, make no fluid and are not hidden", function()
      _G.prototypes = game()

      local filters = recipes.picker_filters(fake_force{})

      assert.are.same({
        {filter = "has-product-item", elem_filters = {{filter = "name", name = {"inserter", "iron-gear-wheel", "iron-plate", "stone-brick"}}}},
        {filter = "has-product-fluid", invert = true, mode = "and"},
        {filter = "hidden", invert = true, mode = "and"},
      }, filters)
    end)

    it("leave out the items of the recipes that are locked", function()
      _G.prototypes = game()

      local filters = recipes.picker_filters(fake_force{locked = {"inserter", "stone-brick"}})

      assert.are.same({"iron-gear-wheel", "iron-plate"}, filters[1].elem_filters[1].name)
    end)

    it("also ask for the recipes that make a fluid of the recipes on offer, which take the place of the recipes that make no fluid", function()
      _G.prototypes = fake_prototypes{recipes = {["iron-plate"] = a_recipe{energy = 3.2, ingredients = {amount_of(1, "iron-ore")}, products = {amount_of(1, "iron-plate")}, category = "smelting"},
        ["basic-oil-processing"] = oil}}

      local filters = recipes.picker_filters(fake_force{})

      assert.are.same({
        {filter = "has-product-item", elem_filters = {{filter = "name", name = {"iron-plate"}}}},
        {filter = "has-product-fluid", invert = true, mode = "and"},
        {filter = "hidden", invert = true, mode = "and"},
        {filter = "has-product-fluid", elem_filters = {{filter = "name", name = {"petroleum-gas"}}}, mode = "or"},
        {filter = "hidden", invert = true, mode = "and"},
      }, filters)
    end)

    it("name a product once, though two recipes on offer make it", function()
      config.recipes["iron-plate-from-scrap"] = true
      _G.prototypes = fake_prototypes{recipes = {["iron-plate"] = a_recipe{energy = 3.2, ingredients = {amount_of(1, "iron-ore")}, products = {amount_of(1, "iron-plate")}, category = "smelting"},
        ["iron-plate-from-scrap"] = a_recipe{energy = 1.6, ingredients = {amount_of(1, "scrap")}, products = {amount_of(1, "iron-plate")}, category = "smelting"}}}

      local filters = recipes.picker_filters(fake_force{})

      config.recipes["iron-plate-from-scrap"] = nil
      assert.are.same({"iron-plate"}, filters[1].elem_filters[1].name)
    end)

    it("leave out a recipe the game does not have", function()
      _G.prototypes = fake_prototypes{recipes = {["iron-plate"] = a_recipe{energy = 3.2, ingredients = {amount_of(1, "iron-ore")}, products = {amount_of(1, "iron-plate")}, category = "smelting"}}}

      local filters = recipes.picker_filters(fake_force{})

      assert.are.same({"iron-plate"}, filters[1].elem_filters[1].name)
    end)
  end)
end)
