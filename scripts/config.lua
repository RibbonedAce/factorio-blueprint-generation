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
---@field fluid_chains table<string, string>  the recipe of the chain that makes a fluid that another recipe takes besides items, by the name of the fluid, built as a block beside the plants of that recipe
---@field fluid_makers table<string, string>  the recipe that makes a fluid that another recipe takes, by the name of the fluid, built as a row of machines ahead of it
---@field pipe_to_ground_reach integer  the most tiles an underground pipe spans, from one end to the other
---@field fluid_pipeline_tiles integer  how many tiles a run of pipes may span along a side, the machines that are fed from it with it
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
    -- A recipe that takes one fluid and nothing else and makes an item: chemical plants with the machines that make the fluid ahead
    -- of them (see `fluid_makers`), a pipe that is the one the fluid goes out of the one and comes in to the other, and the item on a
    -- belt (see scripts/fluid_plant.lua). The rate is of the item. The other recipes of solid fuel take light oil and heavy oil.
    ["solid-fuel-from-petroleum-gas"] = true,
    -- The same with a second fluid that nothing makes (water: raw, like an ore, it comes in by a pipe with a display panel): the plants
    -- are mirrored in turn, with two columns of pipes beside them (see scripts/fluid_plant.lua).
    ["sulfur"] = true,
    -- A recipe that takes one fluid and one raw item (coal): the item comes in by a belt at the top left corner, like an ore, to an
    -- inserter at each plant, which drops what it makes with a long-handed inserter over that belt.
    ["plastic-bar"] = true,
    -- A fluid made from two items and a fluid, in plants, from an item made in plants (sulfur, with the machines that make its fluid) and an
    -- item made on belts (iron plate): the blueprint is the chain of everything, from the raw ores and fluids (see scripts/item_fluid_chain.lua).
    ["sulfuric-acid"] = true,
    -- The same chain for an item: made from an item made in plants (sulfur) and a raw item (coal) that comes in by a belt, and a fluid.
    ["explosives"] = true,
    -- An item made in plants from two items that are made on belts (iron plate, copper plate) and a fluid that a chain of its own makes (the
    -- sulfuric acid, see `fluid_chains`): the blueprint is all of it, from the raw ores and fluids (see scripts/item_fluid_chain.lua).
    ["battery"] = true,
  },

  -- The recipe of the chain that makes a fluid that a recipe takes besides items (battery takes sulfuric acid): the blueprint of that chain
  -- stands beside the plants of the recipe, with its pipe running into their trunk. A fluid that a row of machines makes is in `fluid_makers`.
  fluid_chains = {
    ["sulfuric-acid"] = "sulfuric-acid",
  },

  -- The recipe that makes a fluid that a recipe takes, for a recipe that takes one fluid and nothing else: a row of the machines of
  -- that recipe makes it, so the blueprint starts from the fluid's own raw material. A fluid that is not named has no recipe the
  -- mod builds (water and crude oil are raw: they come in by a pipe). Petroleum gas comes from advanced oil processing and coal
  -- liquefaction too, with other inputs and other products, so the recipe that takes crude oil only is named.
  fluid_makers = {
    ["petroleum-gas"] = "basic-oil-processing",
  },

  -- How far apart the two ends of an underground pipe may be: the wiki (Pipe to ground) says "the maximum distance at which an
  -- underground pipe can connect is 10 tiles, resulting in a gap of 9 tiles in between".
  pipe_to_ground_reach = 10,

  -- How far a run of pipes without a pump may spread: the wiki (Fluid system) says a pipeline "has no limit on its flow" and carries
  -- fluid instantly "as long as the pipeline is not too long", which it takes as outside an area of 320 x 320 tiles. A row of machines
  -- has no more of them than stand in that many tiles one under the other.
  fluid_pipeline_tiles = 320,

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
    chemistry = {tiers = {"chemical-plant"}}, -- solid fuel: a machine of 3 x 3 with two connections to take a fluid and two to give one
  },

  -- The recipe already picked when the window opens.
  default_recipe = "iron-plate",
}

return config
