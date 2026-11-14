-- scripts/config.lua
-- Everything the generator hardcodes for now, kept in one place. Later
-- iterations will replace these constants with choices made from the
-- player's research and settings.
--
-- A file that ends with `return <value>` is a "module": `require` runs the file
-- once and hands that value to whoever asked for it.

---@class bpgen.Config
---@field entities {inserter: string, long_inserter: string, fast_inserter: string, lamp: string, poles: string[], belts: bpgen.BeltTier[]}
---@field products table<string, true>  the items a player may ask for, by name
---@field machines table<string, bpgen.MachineChoice|nil>  the machine for each recipe category, nil for a category with none
---@field default_product string  the item the window starts with; must be a key of `products`

---@type bpgen.Config
local config = {
  -- The building blocks used in every blueprint.
  entities = {
    inserter = "inserter",
    long_inserter = "long-handed-inserter", -- for a second input belt (recipes with three or four ingredients)
    fast_inserter = "fast-inserter", -- for a machine whose side needs more than one plain inserter moves, once researched
    lamp = "small-lamp", -- the lights of the blueprint, once researched (see scripts/lights.lua)

    -- The tiers of a building, from the one every blueprint can count on to the best: the blueprint is built with the
    -- last tier the force has unlocked (and the game has; nothing is known without a force, which gets the first tier;
    -- see `generator.best_tier`). A tier is not held to the size of the first.
    -- The poles: the medium pole powers a 7 x 7 area and reaches 9 tiles (see scripts/layout.lua).
    poles = {"small-electric-pole", "medium-electric-pole"},
    -- The belts: a tier is a belt, a splitter and an underground belt, all three or none (the game unlocks the fast
    -- ones together): a basic splitter or underground belt in the line of a fast belt would carry half of it, and the lanes
    -- the planner counts would not arrive. The splitter and the underground belt are for the input design that brings in one
    -- belt of each material, which divides and merges the belts itself (see scripts/inputs.lua). A lane of a fast belt carries
    -- twice what the basic one's does.
    belts = {
      {belt = "transport-belt", splitter = "splitter", underground = "underground-belt"},
      {belt = "fast-transport-belt", splitter = "fast-splitter", underground = "fast-underground-belt"},
    },
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
    ["logistic-science-pack"] = true, -- two made ingredients, an inserter and a transport belt
    ["underground-belt"] = true,
    ["repair-pack"] = true,
    ["shotgun-shell"] = true,
    -- Made through steel plate, a furnace that eats iron plates and burns fuel: only with one belt of each material (see scripts/inputs.lua).
    ["steel-plate"] = true,
    ["steel-chest"] = true,
    ["heavy-armor"] = true,
    -- Steel together with other made ingredients, one belt of each material only.
    ["stone-wall"] = true,
    ["gate"] = true,
    ["fluid-wagon"] = true,
    ["solar-panel"] = true,
    ["pumpjack"] = true,
    ["assembling-machine-2"] = true,
    ["iron-stick"] = true,
    ["barrel"] = true,
    ["engine-unit"] = true, -- the category `advanced-crafting`
    ["storage-tank"] = true,
    ["fast-transport-belt"] = true,
    ["fast-underground-belt"] = true,
    ["medium-electric-pole"] = true,
    ["big-electric-pole"] = true,
    ["pump"] = true,
    ["rail"] = true,
    ["train-stop"] = true,
    ["rail-signal"] = true,
    ["rail-chain-signal"] = true,
    ["locomotive"] = true,
    ["cargo-wagon"] = true,
    ["car"] = true,
    ["arithmetic-combinator"] = true,
    ["decider-combinator"] = true,
    ["constant-combinator"] = true,
    ["display-panel"] = true,
    ["landfill"] = true,
    ["steel-furnace"] = true,
    ["piercing-rounds-magazine"] = true,
    ["grenade"] = true,
  },

  -- The machine that makes the recipes of each category, and the item it burns
  -- (leave `fuel` out for an electric machine). A recipe whose categories are not
  -- listed here cannot be made. Only a step fed raw items can burn fuel, since the fuel
  -- rides on the belt that carries the raw items. `tiers` are the machines from the one every
  -- blueprint can count on to the best, built with the last the force has unlocked (see the tiers of
  -- `entities`): faster, in the same room.
  machines = {
    smelting = {tiers = {"stone-furnace", "steel-furnace"}, fuel = "coal"}, -- the steel furnace burns the same fuel, at twice the speed, in the same 2 x 2 tiles
    crafting = {tiers = {"assembling-machine-1", "assembling-machine-2"}}, -- electric: no fuel
    ["advanced-crafting"] = {tiers = {"assembling-machine-1", "assembling-machine-2"}}, -- engine units: the assembling machines make this category too
  },

  -- The item already picked when the window opens.
  default_product = "iron-plate",
}

return config
