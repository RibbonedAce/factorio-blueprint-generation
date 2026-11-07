-- scripts/chain.lua
-- Works out the chain of steps that turns raw items into the item the player wants:
-- the item is made from an ingredient that is itself made from an ingredient, and so
-- on until the ingredients are raw. Pure: it knows nothing of the game, only of a
-- `lookup` function that says how an item is made.
--
-- The blueprint is one column of machines per step, each feeding the next, so only
-- a straight line of steps can be built: every step has one ingredient that is made
-- by the step before it. A step with two such ingredients (a tree), or one that
-- mixes the earlier step's product with other ingredients, is refused.

local chain = {}

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

-- Why a step cannot be followed back along one line of steps, or nil when it can:
-- when its one made ingredient is also its only ingredient.
---@param production bpgen.Production
---@param crafted bpgen.MadeIngredient[]  its made ingredients
---@return bpgen.ChainReason|nil
local function branching_reason(production, crafted)
  if #crafted > 1 then
    return "several-crafted"
  end
  if #production.recipe.ingredients > 1 then
    return "extra-ingredient"
  end
  return nil
end

---@param item string
---@param production bpgen.Production
---@return bpgen.ChainStage
local function stage_of(item, production)
  return {item = item, recipe = production.recipe, machine = production.machine, fuel = production.fuel}
end

-- The steps that lead to `item`, first step first, ending with `item`'s own.
-- `seen` holds the items already on the way, to catch a recipe that loops.
---@param item string
---@param production bpgen.Production
---@param lookup bpgen.RecipeLookup
---@param seen table<string, true>
---@return bpgen.ChainStage[]|nil
---@return bpgen.ChainReason|nil reason
---@return string|nil item  the item the reason is about
local function steps_to(item, production, lookup, seen)
  local crafted, reason, culprit = crafted_ingredients(production, lookup)
  if not crafted then
    return nil, reason, culprit
  end
  local ingredient = crafted[1]
  if not ingredient then
    return {stage_of(item, production)} -- every ingredient is raw, so this step is fed raw items
  end
  local branching = branching_reason(production, crafted)
  if branching then
    return nil, branching, item
  end
  if seen[ingredient.name] == true then
    return nil, "cycle", ingredient.name
  end
  seen[ingredient.name] = true
  local steps, step_reason, step_item = steps_to(ingredient.name, ingredient.production, lookup, seen)
  if not steps then
    return nil, step_reason, step_item
  end
  steps[#steps + 1] = stage_of(item, production)
  return steps
end

-- The chain for `item`: a list of steps from the one fed raw items to the one that
-- makes `item`. On failure returns nil, a reason (see `bpgen.ChainReason`) and the
-- item the reason is about.
---@param item string
---@param lookup bpgen.RecipeLookup
---@return bpgen.ChainStage[]|nil stages
---@return bpgen.ChainReason|nil reason
---@return string|nil item
function chain.resolve(item, lookup)
  local production, reason = lookup(item)
  if production then
    return steps_to(item, production, lookup, {[item] = true})
  end
  return nil, reason, item
end

return chain
