-- scripts/config.lua
-- Everything the generator hardcodes for now, kept in one place. Later
-- iterations will replace these constants with choices made from the
-- player's research and settings.
--
-- A file that ends with `return <value>` is a "module": `require` runs the file
-- once and hands that value to whoever asked for it.

---@class bpgen.Config
---@field entities {inserter: string, long_inserter: string, fast_inserter: string, lamp: string, panel: string, pipe: string, pipe_to_ground: string, pump: string, poles: string[], belts: bpgen.BeltTier[]}
---@field recipes table<string, true>  the recipes a player may ask for, by recipe name; the rate is of the product of the recipe
---@field fluid_flow_per_second number  how many units of a fluid the pipes of a blueprint are taken to carry in a second
---@field machines table<string, bpgen.MachineChoice|nil>  the machine for each recipe category, nil for a category with none
---@field default_recipe string  the recipe the window starts with; must be a key of `recipes`

---@type bpgen.Config
local config = {
  -- The building blocks used in every blueprint.
  entities = {
    inserter = "inserter",
    long_inserter = "long-handed-inserter", -- for a second input belt (recipes with three or four ingredients) when the belts cannot be woven
    fast_inserter = "fast-inserter", -- for a machine whose side needs more than one plain inserter moves, once researched
    lamp = "small-lamp", -- the lights of the blueprint, once researched (see scripts/lights.lua)
    panel = "display-panel", -- beside each belt the player brings in, once researched, showing its item (see scripts/labels.lua)
    pipe = "pipe", -- the trunk of pipes of a step that takes a fluid (see scripts/layout.lua)
    pipe_to_ground = "pipe-to-ground", -- under the belts of that step, from the trunk to its machines
    pump = "pump", -- at the water inlet in the corner where the belts come in: one pump serves up to 320 tiles of pipe

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

  -- The recipes a player can ask for, which the window offers (the rate is of the product of the recipe). The recipe is built in
  -- the machine of its category (see `machines`), and how the items it takes are made comes from the game's recipes: the generator
  -- follows them back through the intermediate products until it reaches raw items (see scripts/chain.lua). Each is named for the
  -- item it makes but one, basic oil processing, which makes a fluid.
  recipes = {
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
    -- Three ingredients: a second input belt, woven with the first (see scripts/weave.lua), or reached by long-handed
    -- inserters while the force has not got what the weave is made of.
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
    -- More products with the game's own recipes, each checked at every rate: most are made through steel or engine units, so they need the
    -- design with one belt of each material (the table of the README says which).
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
    -- Takes a fluid (water): its machines have a pipe in the middle row of their input side (see scripts/layout.lua).
    ["concrete"] = true,
    ["refined-concrete"] = true, -- concrete (a column of its own that takes water) with steel plate and iron sticks, and water
    -- A step with one ingredient on top of a step with several inputs: the column of machines stands beside the column that takes them.
    ["hazard-concrete"] = true,
    ["refined-hazard-concrete"] = true,
    -- Three made ingredients (piercing rounds, a grenade and walls), one belt of each material only (steel, and coal for the grenade).
    ["military-science-pack"] = true,
    -- Made through steel plate (and engine units for the turret), so one belt of each material only.
    ["chemical-plant"] = true,
    ["flamethrower"] = true,
    ["defender-capsule"] = true, -- piercing rounds magazines, electronic circuits and gear wheels
    ["flamethrower-turret"] = true,
    -- Five made ingredients (steel plate, gear wheels, bricks, circuits and pipes): the first step with a third woven belt, which needs the
    -- medium electric pole as well (see scripts/weave.lua).
    ["oil-refinery"] = true,
    -- A recipe that takes a fluid and makes a fluid is built as a row of machines with a pipe along one side that brings the fluid
    -- in and a pipe along the other that takes the product away, and no belts (see scripts/fluid_row.lua); the rate is units of the
    -- fluid a minute. Advanced oil processing and coal liquefaction make petroleum gas too, with other inputs and other products,
    -- which that row does not take.
    ["basic-oil-processing"] = true,
  },

  -- How much of a fluid a run of pipes is taken to carry, units a second (ASSUMED, not checked in game: the pipes of the row of a
  -- blueprint, a hundred and some tiles at most, carry well over this). The row has no more machines than the pipes feed.
  fluid_flow_per_second = 600,

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
    ["crafting-with-fluid"] = {tiers = {"assembling-machine-2"}}, -- concrete: the first assembling machine with a fluid input, which has a 3 x 3 body
    ["oil-processing"] = {tiers = {"oil-refinery"}}, -- basic oil processing: a machine of 5 x 5 that takes and gives fluids only
  },

  -- The recipe already picked when the window opens.
  default_recipe = "iron-plate",
}

return config
