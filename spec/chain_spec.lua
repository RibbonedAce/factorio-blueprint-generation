-- spec/chain_spec.lua
-- Which steps lead from raw items to the item the player wants? The module is told
-- how items are made by a `lookup` function, so these specs hand it a small table:
-- `lookup_in{...}` lists the recipes by item, and an item that is not in the table
-- is raw. The recipes are labels, with names as in the game, only their ingredients matter.
---@diagnostic disable: undefined-field  -- luassert's `assert` has fields (`assert.are`, `assert.is_nil`, ...) the editor cannot see
---@diagnostic disable: need-check-nil  -- the assertion before each use fails the test first if the result is nil

local chain = require("scripts.chain")
local builders = require("spec.support.builders")

local amount_of = builders.amount_of

-- A way to make something: `production{"iron-ore"}` eats one iron ore, in a machine named "machine".
---@param ingredient_names string[]
---@param machine? string
---@return bpgen.Production
local function production(ingredient_names, machine)
  local ingredients = {}
  for index, name in ipairs(ingredient_names) do
    ingredients[index] = amount_of(1, name)
  end
  return {
    recipe = {energy = 1, ingredients = ingredients, products = {amount_of(1, "anything")}},
    machine = machine or "machine",
  }
end

-- A lookup over a table of items to how each is made. A value of "ambiguous" or
-- "unsupported" is the reason the lookup gives; an item that is missing is raw.
---@param table_of_items table<string, bpgen.Production|bpgen.ChainReason>
---@return bpgen.RecipeLookup
local function lookup_in(table_of_items)
  return function(item)
    local entry = table_of_items[item]
    if entry == nil then
      return nil, "no-recipe"
    end
    if type(entry) == "string" then
      return nil, entry
    end
    return entry
  end
end

-- The items of a step and of the steps that make its ingredients, a step after the steps
-- that feed it: for a chain, from the first step to the last.
---@param stage bpgen.ChainStage
---@param items? string[]
---@return string[]
local function items_of(stage, items)
  items = items or {}
  for _, supplier in ipairs(stage.suppliers) do
    items_of(supplier, items)
  end
  items[#items + 1] = stage.item
  return items
end

describe("chain", function()
  describe("resolve, for an item made from raw items", function()
    it("gives one step when the recipe has several raw ingredients", function()
      local lookup = lookup_in{["steel-thing"] = production{"iron-ore", "coal", "stone"}}

      local stage = chain.resolve("steel-thing", lookup)

      assert.are.same({"steel-thing"}, items_of(stage))
    end)

    it("keeps the recipe, the machine and the fuel of the step", function()
      local recipe_of_plate = production({"iron-ore"}, "stone-furnace")
      recipe_of_plate.fuel = "coal"
      local lookup = lookup_in{["iron-plate"] = recipe_of_plate}

      local stage = chain.resolve("iron-plate", lookup)

      assert.are.same({item = "iron-plate", recipe = recipe_of_plate.recipe, machine = "stone-furnace", fuel = "coal", suppliers = {}}, stage)
    end)
  end)

  describe("resolve, for an item made from another made item", function()
    it("follows the chain as deep as it goes", function()
      local lookup = lookup_in{
        ["pipe-thing"] = production{"gear"},
        ["gear"] = production{"plate"},
        ["plate"] = production{"ore-chunk"},
        ["ore-chunk"] = production{"rock"},
      }

      local stage = chain.resolve("pipe-thing", lookup)

      assert.are.same({"ore-chunk", "plate", "gear", "pipe-thing"}, items_of(stage))
    end)

    it("gives a step the one step that makes its ingredient", function()
      local lookup = lookup_in{["gear"] = production{"plate"}, ["plate"] = production{"ore"}}

      local stage = chain.resolve("gear", lookup)

      assert.are.equal(1, #stage.suppliers)
      assert.are.equal("plate", stage.suppliers[1].item)
    end)
  end)

  describe("resolve, for an item made from two made items", function()
    local circuit_lookup = lookup_in{
      ["circuit"] = production{"iron-plate", "copper-cable"},
      ["iron-plate"] = production{"iron-ore"},
      ["copper-cable"] = production{"copper-plate"},
      ["copper-plate"] = production{"copper-ore"},
    }

    it("gives the step a supplier for each of the ingredients, in the recipe's order", function()
      local stage = chain.resolve("circuit", circuit_lookup)

      assert.are.equal(2, #stage.suppliers)
      assert.are.same({"iron-plate"}, items_of(stage.suppliers[1]))
      assert.are.same({"copper-plate", "copper-cable"}, items_of(stage.suppliers[2]))
    end)

    it("makes an item that two ingredients share once for each of them, which is no loop", function()
      local lookup = lookup_in{
        ["pump"] = production{"pipe", "gear"},
        ["pipe"] = production{"plate"},
        ["gear"] = production{"plate"},
        ["plate"] = production{"ore"},
      }

      local stage = chain.resolve("pump", lookup)

      assert.are.same({"plate", "pipe", "plate", "gear", "pump"}, items_of(stage))
    end)

    it("gives the steps of a tree inside a tree", function()
      local lookup = lookup_in{
        ["underground"] = production{"plate", "belt"},
        ["belt"] = production{"plate", "gear"},
        ["gear"] = production{"plate"},
        ["plate"] = production{"ore"},
      }

      local stage = chain.resolve("underground", lookup)

      assert.are.equal("belt", stage.suppliers[2].item)
      assert.are.equal("gear", stage.suppliers[2].suppliers[2].item)
    end)
  end)

  describe("resolve, for an item made from one made item and one raw one", function()
    local pole_lookup = lookup_in{
      ["pole"] = production{"wood", "copper-cable"},
      ["copper-cable"] = production{"copper-plate"},
      ["copper-plate"] = production{"copper-ore"},
    }

    it("gives the step a supplier for the made ingredient and names the raw one", function()
      local stage = chain.resolve("pole", pole_lookup)

      assert.are.same({"copper-plate", "copper-cable"}, items_of(stage.suppliers[1]))
      assert.are.equal(1, #stage.suppliers)
      assert.are.equal("wood", stage.raw_item)
    end)

    it("names the raw ingredient whichever place it has in the recipe", function()
      local lookup = lookup_in{
        ["pole"] = production{"copper-cable", "wood"},
        ["copper-cable"] = production{"copper-plate"},
      }

      local stage = chain.resolve("pole", lookup)

      assert.are.equal("wood", stage.raw_item)
    end)

    it("names no raw ingredient when every ingredient is made", function()
      local stage = chain.resolve("gear", lookup_in{["gear"] = production{"plate"}, ["plate"] = production{"ore"}})

      assert.is_nil(stage.raw_item)
    end)

    it("names no raw ingredient when the step is fed raw items", function()
      local stage = chain.resolve("steel-thing", lookup_in{["steel-thing"] = production{"iron-ore", "coal"}})

      assert.is_nil(stage.raw_item)
    end)

    it("reports the step that is the only ingredient of another when it has a raw ingredient too", function()
      local lookup = lookup_in{
        ["box"] = production{"pole"},
        ["pole"] = production{"wood", "copper-cable"},
        ["copper-cable"] = production{"copper-plate"},
      }

      local stage, reason, item = chain.resolve("box", lookup)

      assert.is_nil(stage)
      assert.are.equal("fork-in-chain", reason)
      assert.are.equal("box", item)
    end)

    it("allows the step as one of two made ingredients of another", function()
      local lookup = lookup_in{
        ["panel"] = production{"plate", "pole"},
        ["pole"] = production{"wood", "copper-cable"},
        ["copper-cable"] = production{"copper-plate"},
        ["plate"] = production{"ore"},
      }

      local stage = chain.resolve("panel", lookup)

      assert.are.equal("wood", stage.suppliers[2].raw_item)
    end)
  end)

  describe("resolve, for an item that cannot be chained", function()
    it("reports that nothing makes the item when it is raw", function()
      local stage, reason, item = chain.resolve("iron-ore", lookup_in{})

      assert.is_nil(stage)
      assert.are.equal("no-recipe", reason)
      assert.are.equal("iron-ore", item)
    end)

    it("reports the item when several recipes make it", function()
      local _, reason, item = chain.resolve("iron-plate", lookup_in{["iron-plate"] = "ambiguous"})

      assert.are.equal("ambiguous", reason)
      assert.are.equal("iron-plate", item)
    end)

    it("reports the ingredient when several recipes make an ingredient", function()
      local lookup = lookup_in{["gear"] = production{"plate"}, ["plate"] = "ambiguous"}

      local _, reason, item = chain.resolve("gear", lookup)

      assert.are.equal("ambiguous", reason)
      assert.are.equal("plate", item)
    end)

    it("reports the ingredient when the recipe of an ingredient cannot be built", function()
      local lookup = lookup_in{["gear"] = production{"plate"}, ["plate"] = "unsupported"}

      local _, reason, item = chain.resolve("gear", lookup)

      assert.are.equal("unsupported", reason)
      assert.are.equal("plate", item)
    end)

    it("reports the item when its own recipe cannot be built", function()
      local _, reason, item = chain.resolve("gear", lookup_in{["gear"] = "unsupported"})

      assert.are.equal("unsupported", reason)
      assert.are.equal("gear", item)
    end)

    it("reports the ingredient that cannot be built even when it is the second of two made ones", function()
      local lookup = lookup_in{
        ["circuit"] = production{"iron-plate", "copper-plate"},
        ["iron-plate"] = production{"iron-ore"},
        ["copper-plate"] = "unsupported",
      }

      local _, reason, item = chain.resolve("circuit", lookup)

      assert.are.equal("unsupported", reason)
      assert.are.equal("copper-plate", item)
    end)

    it("reports the item when three of its ingredients are made from others", function()
      local lookup = lookup_in{
        ["thing"] = production{"iron-plate", "copper-plate", "stone-brick"},
        ["iron-plate"] = production{"iron-ore"},
        ["copper-plate"] = production{"copper-ore"},
        ["stone-brick"] = production{"stone"},
      }

      local stage, reason, item = chain.resolve("thing", lookup)

      assert.is_nil(stage)
      assert.are.equal("several-crafted", reason)
      assert.are.equal("thing", item)
    end)

    it("reports the item when it mixes a made ingredient with two raw ones", function()
      local lookup = lookup_in{
        ["thing"] = production{"iron-plate", "stone", "wood"},
        ["iron-plate"] = production{"iron-ore"},
      }

      local _, reason, item = chain.resolve("thing", lookup)

      assert.are.equal("extra-ingredient", reason)
      assert.are.equal("thing", item)
    end)

    it("reports the item when it mixes two made ingredients with a raw one", function()
      local lookup = lookup_in{
        ["thing"] = production{"iron-plate", "copper-plate", "stone"},
        ["iron-plate"] = production{"iron-ore"},
        ["copper-plate"] = production{"copper-ore"},
      }

      local _, reason, item = chain.resolve("thing", lookup)

      assert.are.equal("extra-ingredient", reason)
      assert.are.equal("thing", item)
    end)

    it("reports the step with one made ingredient that is itself made from two", function()
      local lookup = lookup_in{
        ["pipe-thing"] = production{"circuit"},
        ["circuit"] = production{"iron-plate", "copper-plate"},
        ["iron-plate"] = production{"iron-ore"},
        ["copper-plate"] = production{"copper-ore"},
      }

      local stage, reason, item = chain.resolve("pipe-thing", lookup)

      assert.is_nil(stage)
      assert.are.equal("fork-in-chain", reason)
      assert.are.equal("pipe-thing", item)
    end)

    it("reports the first step of a chain on top of two made ingredients, however long the chain", function()
      local lookup = lookup_in{
        ["box"] = production{"pipe-thing"},
        ["pipe-thing"] = production{"circuit"},
        ["circuit"] = production{"iron-plate", "copper-plate"},
        ["iron-plate"] = production{"iron-ore"},
        ["copper-plate"] = production{"copper-ore"},
      }

      local _, reason, item = chain.resolve("box", lookup)

      assert.are.equal("fork-in-chain", reason)
      assert.are.equal("pipe-thing", item)
    end)

    it("reports the item where the chain starts to loop, when the item asked for is not part of the loop", function()
      local lookup = lookup_in{["root"] = production{"x"}, ["x"] = production{"y"}, ["y"] = production{"x"}}

      local _, reason, item = chain.resolve("root", lookup)

      assert.are.equal("cycle", reason)
      assert.are.equal("x", item)
    end)

    it("reports the item that is made from itself in the end", function()
      local lookup = lookup_in{["a"] = production{"b"}, ["b"] = production{"a"}}

      local _, reason, item = chain.resolve("a", lookup)

      assert.are.equal("cycle", reason)
      assert.are.equal("a", item)
    end)

    it("reports a loop through the second of two made ingredients", function()
      local lookup = lookup_in{
        ["a"] = production{"b", "c"},
        ["b"] = production{"ore"},
        ["c"] = production{"a"},
      }

      local _, reason, item = chain.resolve("a", lookup)

      assert.are.equal("cycle", reason)
      assert.are.equal("a", item)
    end)
  end)
end)
