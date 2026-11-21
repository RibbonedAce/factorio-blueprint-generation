-- scripts/recipes.lua
-- Which recipes the player can pick: the ones of the config that the force has unlocked, and the filters of the window's picker
-- of recipes that ask for them. The generator asks it whether a recipe is locked, and the window (scripts/gui.lua) what to offer.
-- Reads the game's `prototypes` and the force's recipes, like scripts/generator.lua.

local config = require("scripts.config")

local recipes = {}

-- Whether the force has not unlocked a recipe yet (`LuaForce.recipes`). A recipe the force does not know at all is not held
-- against it: there is nothing to unlock.
---@param recipe_name string
---@param force LuaForce
---@return boolean
function recipes.is_locked(recipe_name, force)
  local recipe = force.recipes[recipe_name]
  return recipe ~= nil and not recipe.enabled
end

-- The recipes of the config except those the force has not unlocked: the picker offers them, and the window
-- starts with one. A recipe that cannot be made for another reason stays in the list, so choosing it still
-- shows the message that says why.
---@param force LuaForce
---@return string[] names  sorted
function recipes.unlocked(force)
  local names = {}
  for name in pairs(config.recipes) do
    if not recipes.is_locked(name, force) then
      names[#names + 1] = name
    end
  end
  table.sort(names)
  return names
end

-- The names in a set, sorted.
---@param set table<string, true>
---@return string[]
local function sorted_names(set)
  local names = {}
  for name in pairs(set) do
    names[#names + 1] = name
  end
  table.sort(names)
  return names
end

-- The filters of the picker of recipes in the window. A filter of recipes cannot ask for a recipe by its name (the game has no
-- such filter, and the unlocked recipes of a force are not a prototype property a filter can use), so these ask for what the
-- unlocked recipes make: the recipes that make one of their items and no fluid, or one of their fluids, and that are not hidden
-- (the game does not leave them out of a picker: the recycling of an item makes the items it is made of). A product that another
-- recipe makes too has that recipe in the picker as well; choosing it is answered with a message under the rate field.
---@param force LuaForce
---@return RecipePrototypeFilter[]
function recipes.picker_filters(force)
  local items, fluids = {}, {}
  for _, name in ipairs(recipes.unlocked(force)) do
    local prototype = prototypes.recipe[name]
    local product = prototype and prototype.products[1]
    if product then
      local made = product.type == "fluid" and fluids or items
      made[product.name] = true
    end
  end
  local filters = {
    {filter = "has-product-item", elem_filters = {{filter = "name", name = sorted_names(items)}}},
    {filter = "has-product-fluid", invert = true, mode = "and"},
    {filter = "hidden", invert = true, mode = "and"},
  }
  if next(fluids) then
    filters[#filters + 1] = {filter = "has-product-fluid", elem_filters = {{filter = "name", name = sorted_names(fluids)}}, mode = "or"}
    filters[#filters + 1] = {filter = "hidden", invert = true, mode = "and"}
  end
  return filters
end

return recipes
