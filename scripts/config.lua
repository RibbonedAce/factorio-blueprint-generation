-- scripts/config.lua
-- Everything the generator hardcodes for now, kept in one place. Later
-- iterations will replace these constants with choices made from the
-- player's research and settings.
--
-- A file that ends with `return <value>` is a "module": `require` runs the file
-- once and hands that value to whoever asked for it.

---@class bpgen.Config
---@field entities {belt: string, inserter: string, long_inserter: string, pole: string}
---@field products table<string, true>  the items a player may ask for, by name
---@field machines table<string, bpgen.MachineChoice|nil>  the machine for each recipe category, nil for a category with none
---@field default_product string  the item the window starts with; must be a key of `products`

---@type bpgen.Config
local config = {
  -- The first-tier building blocks used in every blueprint.
  entities = {
    belt = "transport-belt",
    inserter = "inserter",
    long_inserter = "long-handed-inserter", -- for a second input belt (recipes with three or four ingredients)
    pole = "small-electric-pole",
  },

  -- The items a player can ask for. How each is made comes from the game's recipes:
  -- the generator follows the recipe back through the intermediate products it
  -- needs, until it reaches raw items (see scripts/chain.lua).
  products = {
    ["iron-plate"] = true,
    ["copper-plate"] = true,
    ["stone-brick"] = true,
    ["iron-gear-wheel"] = true,
    ["copper-cable"] = true,
    ["wooden-chest"] = true,
    ["iron-chest"] = true,
    ["pipe"] = true,
    ["stone-furnace"] = true,
    ["firearm-magazine"] = true,
    ["light-armor"] = true,
    ["electronic-circuit"] = true,
    ["small-electric-pole"] = true,
    -- Three ingredients: a second input belt, reached by long-handed inserters.
    ["inserter"] = true,
    ["long-handed-inserter"] = true,
    ["fast-inserter"] = true,
    ["assembling-machine-1"] = true,
    ["electric-mining-drill"] = true,
    ["burner-mining-drill"] = true,
    ["radar"] = true,
    ["rocket-launcher"] = true,
    ["gun-turret"] = true,
    ["submachine-gun"] = true,
    ["steam-engine"] = true,
    ["steam-turbine"] = true,
    ["lab"] = true,
    ["splitter"] = true,
    ["fast-splitter"] = true,
    ["small-lamp"] = true,
    ["power-switch"] = true,
    -- Four ingredients.
    ["programmable-speaker"] = true,
    ["shotgun"] = true,
    ["transport-belt"] = true,
    ["burner-inserter"] = true,
    ["pipe-to-ground"] = true,
    ["boiler"] = true,
    ["offshore-pump"] = true,
    ["automation-science-pack"] = true,
  },

  -- The machine that makes the recipes of each category, and the item it burns
  -- (leave `fuel` out for an electric machine). A recipe whose categories are not
  -- listed here cannot be made. Only a step fed raw items can burn fuel, since the fuel
  -- rides on the belt that carries the raw items.
  machines = {
    smelting = {machine = "stone-furnace", fuel = "coal"},
    crafting = {machine = "assembling-machine-1"}, -- electric: no fuel
  },

  -- The item already picked when the window opens.
  default_product = "iron-plate",
}

return config
