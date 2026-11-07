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

local function items_of(stages)
  local items = {}
  for index, stage in ipairs(stages) do
    items[index] = stage.item
  end
  return items
end

describe("chain", function()
  describe("resolve, for an item made from raw items", function()
    it("gives one step when the recipe has several raw ingredients", function()
      local lookup = lookup_in{["steel-thing"] = production{"iron-ore", "coal", "stone"}}

      local stages = chain.resolve("steel-thing", lookup)

      assert.are.same({"steel-thing"}, items_of(stages))
    end)

    it("keeps the recipe, the machine and the fuel of the step", function()
      local recipe_of_plate = production({"iron-ore"}, "stone-furnace")
      recipe_of_plate.fuel = "coal"
      local lookup = lookup_in{["iron-plate"] = recipe_of_plate}

      local stages = chain.resolve("iron-plate", lookup)

      assert.are.same({item = "iron-plate", recipe = recipe_of_plate.recipe, machine = "stone-furnace", fuel = "coal"}, stages[1])
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

      local stages = chain.resolve("pipe-thing", lookup)

      assert.are.same({"ore-chunk", "plate", "gear", "pipe-thing"}, items_of(stages))
    end)

  end)

  describe("resolve, for an item that cannot be chained", function()
    it("reports that nothing makes the item when it is raw", function()
      local stages, reason, item = chain.resolve("iron-ore", lookup_in{})

      assert.is_nil(stages)
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

    it("reports the item when two of its ingredients are made from others", function()
      local lookup = lookup_in{
        ["circuit"] = production{"iron-plate", "copper-plate"},
        ["iron-plate"] = production{"iron-ore"},
        ["copper-plate"] = production{"copper-ore"},
      }

      local stages, reason, item = chain.resolve("circuit", lookup)

      assert.is_nil(stages)
      assert.are.equal("several-crafted", reason)
      assert.are.equal("circuit", item)
    end)

    it("reports the item when it mixes a made ingredient with a raw one", function()
      local lookup = lookup_in{
        ["thing"] = production{"iron-plate", "stone"},
        ["iron-plate"] = production{"iron-ore"},
      }

      local _, reason, item = chain.resolve("thing", lookup)

      assert.are.equal("extra-ingredient", reason)
      assert.are.equal("thing", item)
    end)

    it("reports the step where the chain branches, when it is not the last one", function()
      local lookup = lookup_in{
        ["pipe-thing"] = production{"circuit"},
        ["circuit"] = production{"iron-plate", "copper-plate"},
        ["iron-plate"] = production{"iron-ore"},
        ["copper-plate"] = production{"copper-ore"},
      }

      local _, reason, item = chain.resolve("pipe-thing", lookup)

      assert.are.equal("several-crafted", reason)
      assert.are.equal("circuit", item)
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
  end)
end)
