-- scripts/config.lua
-- Everything the generator hardcodes for now, kept in one place. Later
-- iterations will replace these constants with choices made from the
-- player's research and settings.
--
-- A file that ends with `return <value>` is a "module": `require` runs the file
-- once and hands that value to whoever asked for it.

---@class bpgen.Config
---@field entities {belt: string, inserter: string, pole: string}
---@field products table<string, bpgen.Product>  keyed by the product item's name
---@field default_product string  the item the window starts with; must be a key of `products`

---@type bpgen.Config
local config = {
  -- The first-tier building blocks used in every blueprint.
  entities = {
    belt = "transport-belt",
    inserter = "inserter",
    pole = "small-electric-pole",
  },

  -- What can be generated: the product item, and how it is made.
  -- `recipe` and `machine` are prototype names; `fuel` is the item the machine burns
  -- (leave it out for an electric machine).
  products = {
    ["iron-plate"] = {recipe = "iron-plate", machine = "stone-furnace", fuel = "coal"},
    ["copper-plate"] = {recipe = "copper-plate", machine = "stone-furnace", fuel = "coal"},
    ["stone-brick"] = {recipe = "stone-brick", machine = "stone-furnace", fuel = "coal"},
    ["iron-gear-wheel"] = {recipe = "iron-gear-wheel", machine = "assembling-machine-1"}, -- electric: no fuel
  },

  -- The item already picked when the window opens.
  default_product = "iron-plate",
}

return config
