-- scripts/chain.lua
-- Works out the steps that turn raw items into the item the player wants: the item is
-- made from ingredients, each of which is raw or made from ingredients of its own, and so
-- on until everything is raw. Pure: it knows nothing of the game, only of a `lookup`
-- function that says how an item is made.
--
-- The result is a tree of steps, each with the steps that make its made ingredients. A
-- step whose ingredients are all raw has none (the first step of a chain). A step with one
-- made ingredient is fed by a straight chain of steps. A step with two to four made
-- ingredients is fed by that many blocks, one on each lane of its input belts (two lanes
-- a belt, and a second belt for the third and fourth, see scripts/blocks.lua). A step
-- with made ingredients and one raw ingredient is fed by the blocks that make the first
-- and by a belt of the second, which takes a lane too (`ChainStage.raw_item`). The
-- following are refused:
--   * a step with more than four made ingredients (it needs more lanes than two belts have);
--   * a step with made ingredients and more than four ingredients in all, or more than one
--     raw ingredient (a belt of raw items fills both lanes, so it is side-loaded onto a
--     lane of its own, and only one is laid out);
--   * a step with one made ingredient that is itself made from two or more, or from one
--     and a raw one (a column of machines on top of a block with several inputs is not laid
--     out yet).

local chain = {}

-- The most made ingredients a step can have, and the most ingredients in all of a step that
-- has any: one for each lane of its two input belts. And the most raw ones that go with them.
local MOST_MADE_INGREDIENTS = 4
local MOST_INGREDIENTS = 4
local MOST_RAW_INGREDIENTS = 1

-- An ingredient that something makes, with how it is made.
---@class bpgen.MadeIngredient
---@field name string
---@field production bpgen.Production

-- The ingredients of a recipe that something makes, with how each is made.
-- Raw ingredients are left out. Returns nil, reason and the item when the way an
-- ingredient is made cannot be used.
---@param production bpgen.Production
---@param lookup bpgen.RecipeLookup
---@return bpgen.MadeIngredient[]|nil crafted
---@return bpgen.ChainReason|nil reason
---@return string|nil item  the ingredient with the problem
local function crafted_ingredients(production, lookup)
  local crafted = {}
  for _, ingredient in ipairs(production.recipe.ingredients) do
    local made, reason = lookup(ingredient.name)
    if made then
      crafted[#crafted + 1] = {name = ingredient.name, production = made}
    elseif reason ~= "no-recipe" then
      ---@cast reason bpgen.ChainReason -- an item the lookup could not give is always given with a reason
      return nil, reason, ingredient.name
    end
  end
  return crafted
end

-- Why a step cannot be built from its made ingredients, or nil when it can: when it has
-- more than four, or more than four ingredients in all, or more than one raw one.
---@param production bpgen.Production
---@param crafted bpgen.MadeIngredient[]  its made ingredients
---@return bpgen.ChainReason|nil
local function branching_reason(production, crafted)
  if #crafted > MOST_MADE_INGREDIENTS then
    return "several-crafted"
  end
  local ingredients = #production.recipe.ingredients
  if #crafted > 0 and (ingredients > MOST_INGREDIENTS or ingredients - #crafted > MOST_RAW_INGREDIENTS) then
    return "extra-ingredient"
  end
  return nil
end

-- The raw ingredient that goes with the made ones, or nil when every ingredient is made (or
-- none is). `branching_reason` has left room for one at most.
---@param production bpgen.Production
---@param crafted bpgen.MadeIngredient[]  its made ingredients
---@return string|nil
local function raw_ingredient(production, crafted)
  if #crafted == 0 then
    return nil
  end
  for _, ingredient in ipairs(production.recipe.ingredients) do
    local is_made = false
    for _, made in ipairs(crafted) do
      is_made = is_made or made.name == ingredient.name
    end
    if not is_made then
      return ingredient.name
    end
  end
  return nil
end

-- How many belts of items feed a step: one for each step that makes an ingredient, and one
-- for a raw ingredient that goes with them.
---@param stage bpgen.ChainStage
---@return integer
local function input_count(stage)
  return #stage.suppliers + (stage.raw_item and 1 or 0)
end

-- The step for `item` once the steps that make its made ingredients are known, or nil
-- and why not: a step with one made ingredient cannot be fed by a step with two inputs (a
-- fork further down was refused where it started).
---@param item string
---@param production bpgen.Production
---@param suppliers bpgen.ChainStage[]
---@param raw_item string|nil  the raw ingredient that goes with the made ones
---@return bpgen.ChainStage|nil
---@return bpgen.ChainReason|nil reason
---@return string|nil item  the item the reason is about
local function stage_of(item, production, suppliers, raw_item)
  if #suppliers == 1 and input_count(suppliers[1]) > 1 then
    return nil, "fork-in-chain", item
  end
  return {
    item = item, recipe = production.recipe, machine = production.machine, fuel = production.fuel,
    suppliers = suppliers, raw_item = raw_item,
  }
end

-- The step that makes `item`, with the steps that make its ingredients, in the recipe's
-- order. `seen` holds the items on the way down from the item asked for, to catch a
-- recipe that loops (two ingredients may share an item below them: that is no loop).
---@param item string
---@param production bpgen.Production
---@param lookup bpgen.RecipeLookup
---@param seen table<string, true>
---@return bpgen.ChainStage|nil
---@return bpgen.ChainReason|nil reason
---@return string|nil item  the item the reason is about
local function stage_for(item, production, lookup, seen)
  local crafted, reason, culprit = crafted_ingredients(production, lookup)
  if not crafted then
    return nil, reason, culprit
  end
  local branching = branching_reason(production, crafted)
  if branching then
    return nil, branching, item
  end
  local suppliers = {}
  for index, ingredient in ipairs(crafted) do
    if seen[ingredient.name] == true then
      return nil, "cycle", ingredient.name
    end
    seen[ingredient.name] = true
    local supplier, supplier_reason, supplier_item = stage_for(ingredient.name, ingredient.production, lookup, seen)
    seen[ingredient.name] = nil
    if not supplier then
      return nil, supplier_reason, supplier_item
    end
    suppliers[index] = supplier
  end
  return stage_of(item, production, suppliers, raw_ingredient(production, crafted))
end

-- The step that makes `item`, with the steps that make what it needs. On failure
-- returns nil, a reason (see `bpgen.ChainReason`) and the item the reason is about.
---@param item string
---@param lookup bpgen.RecipeLookup
---@return bpgen.ChainStage|nil stage
---@return bpgen.ChainReason|nil reason
---@return string|nil item
function chain.resolve(item, lookup)
  local production, reason = lookup(item)
  if production then
    return stage_for(item, production, lookup, {[item] = true})
  end
  return nil, reason, item
end

return chain
