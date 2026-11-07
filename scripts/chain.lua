-- scripts/chain.lua
-- Works out the steps that turn raw items into the item the player wants: the item is
-- made from ingredients, each of which is raw or made from ingredients of its own, and so
-- on until everything is raw. Pure: it knows nothing of the game, only of a `lookup`
-- function that says how an item is made.
--
-- The result is a tree of steps, each with the steps that make its made ingredients. A
-- step whose ingredients are all raw has none (the first step of a chain). A step with one
-- made ingredient is fed by a straight chain of steps. A step with two made ingredients
-- is fed by two blocks, one on each lane of its input belt (see scripts/blocks.lua). The
-- following are refused:
--   * a step with more than two made ingredients (it needs more lanes than a belt has);
--   * a step that mixes made ingredients with raw ones (the raw items would need a lane);
--   * a step with one made ingredient that is itself made from two (a column of machines
--     on top of a block with two inputs is not laid out yet).

local chain = {}

-- The most made ingredients a step can have: one for each lane of its input belt.
local MOST_MADE_INGREDIENTS = 2

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
-- more than two, or when it mixes them with raw ingredients.
---@param production bpgen.Production
---@param crafted bpgen.MadeIngredient[]  its made ingredients
---@return bpgen.ChainReason|nil
local function branching_reason(production, crafted)
  if #crafted > MOST_MADE_INGREDIENTS then
    return "several-crafted"
  end
  if #crafted > 0 and #production.recipe.ingredients > #crafted then
    return "extra-ingredient"
  end
  return nil
end

-- The step for `item` once the steps that make its made ingredients are known, or nil
-- and why not: a step with one made ingredient cannot be fed by a step with two (a fork
-- further down was refused where it started).
---@param item string
---@param production bpgen.Production
---@param suppliers bpgen.ChainStage[]
---@return bpgen.ChainStage|nil
---@return bpgen.ChainReason|nil reason
---@return string|nil item  the item the reason is about
local function stage_of(item, production, suppliers)
  if #suppliers == 1 and #suppliers[1].suppliers > 1 then
    return nil, "fork-in-chain", item
  end
  return {item = item, recipe = production.recipe, machine = production.machine, fuel = production.fuel, suppliers = suppliers}
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
  return stage_of(item, production, suppliers)
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
