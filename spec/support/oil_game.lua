-- spec/support/oil_game.lua
-- The stand-in game of the specs of recipes that take what plants or refineries make: a refinery of 5 x 5 and a chemical plant of 3 x 3, the recipes of
-- petroleum gas, plastic bar, sulfur, explosives, sulfuric acid and battery, and the recipes that take them on belts (advanced circuit, rocket, accumulator,
-- the barrels of petroleum gas and sulfuric acid). The validator's catalog for what the blueprints of these recipes are made of, and what the
-- message of a generated blueprint says. Test tooling only: the game never loads this folder.
--
-- Loading it puts the recipes in the config's list of recipes, as the specs of the chains do for theirs: the mod's own list does not have them yet.
---@diagnostic disable: global-in-non-module  -- `_G.prototypes = ...` is how a spec fakes the game's global

local builders = require("spec.support.builders")
local config = require("scripts.config")

local a_machine, a_recipe, amount_of, fluid_of = builders.a_machine, builders.a_recipe, builders.amount_of, builders.fluid_of
local north, south = defines.direction.north, defines.direction.south

local oil_game = {}

oil_game.REFINERY_BOXES = {
  {production_type = "input", position = {x = -1, y = 2}, direction = south}, {production_type = "input", position = {x = 1, y = 2}, direction = south},
  {production_type = "output", position = {x = -2, y = -2}, direction = north}, {production_type = "output", position = {x = 0, y = -2}, direction = north},
  {production_type = "output", position = {x = 2, y = -2}, direction = north},
}
oil_game.PLANT_BOXES = {
  {production_type = "input", position = {x = -1, y = -1}, direction = north}, {production_type = "input", position = {x = 1, y = -1}, direction = north},
  {production_type = "output", position = {x = -1, y = 1}, direction = south}, {production_type = "output", position = {x = 1, y = 1}, direction = south},
}

local function item(name, count) return amount_of(count, name) end
local function fluid(name, count) return fluid_of(count, name) end

oil_game.RECIPES = {
  ["iron-plate"] = a_recipe{energy = 3.2, ingredients = {item("iron-ore", 1)}, products = {item("iron-plate", 1)}, category = "smelting"},
  ["copper-plate"] = a_recipe{energy = 3.2, ingredients = {item("copper-ore", 1)}, products = {item("copper-plate", 1)}, category = "smelting"},
  ["steel-plate"] = a_recipe{energy = 16, ingredients = {item("iron-plate", 5)}, products = {item("steel-plate", 1)}, category = "smelting"},
  ["copper-cable"] = a_recipe{energy = 0.5, ingredients = {item("copper-plate", 1)}, products = {item("copper-cable", 2)}},
  ["electronic-circuit"] = a_recipe{energy = 0.5, ingredients = {item("iron-plate", 1), item("copper-cable", 3)}, products = {item("electronic-circuit", 1)}},
  ["basic-oil-processing"] = a_recipe{energy = 5, ingredients = {fluid("crude-oil", 100)}, products = {fluid("petroleum-gas", 45)}, category = "oil-processing"},
  ["plastic-bar"] = a_recipe{energy = 1, ingredients = {item("coal", 1), fluid("petroleum-gas", 20)}, products = {item("plastic-bar", 2)}, category = "chemistry"},
  ["advanced-circuit"] = a_recipe{
    energy = 6, ingredients = {item("electronic-circuit", 2), item("plastic-bar", 2), item("copper-cable", 4)}, products = {item("advanced-circuit", 1)},
  },
  ["sulfur"] = a_recipe{energy = 1, ingredients = {fluid("water", 30), fluid("petroleum-gas", 30)}, products = {item("sulfur", 2)}, category = "chemistry"},
  ["explosives"] = a_recipe{
    energy = 4, ingredients = {item("sulfur", 1), item("coal", 1), fluid("water", 10)}, products = {item("explosives", 2)}, category = "chemistry",
  },
  ["rocket"] = a_recipe{energy = 4, ingredients = {item("explosives", 1), item("iron-plate", 2)}, products = {item("rocket", 1)}},
  ["sulfuric-acid"] = a_recipe{
    energy = 1, ingredients = {item("sulfur", 5), item("iron-plate", 1), fluid("water", 100)}, products = {fluid("sulfuric-acid", 50)}, category = "chemistry",
  },
  ["battery"] = a_recipe{
    energy = 4, ingredients = {item("iron-plate", 1), item("copper-plate", 1), fluid("sulfuric-acid", 20)}, products = {item("battery", 1)}, category = "chemistry",
  },
  ["accumulator"] = a_recipe{energy = 10, ingredients = {item("iron-plate", 2), item("battery", 5)}, products = {item("accumulator", 1)}},
  ["barrel"] = a_recipe{energy = 1, ingredients = {item("steel-plate", 1)}, products = {item("barrel", 1)}},
  ["water-barrel"] = a_recipe{
    energy = 0.2, ingredients = {fluid("water", 50), item("barrel", 1)}, products = {item("water-barrel", 1)}, category = "crafting-with-fluid",
  },
  ["petroleum-gas-barrel"] = a_recipe{
    energy = 0.2, ingredients = {fluid("petroleum-gas", 50), item("barrel", 1)}, products = {item("petroleum-gas-barrel", 1)}, category = "crafting-with-fluid",
  },
  ["sulfuric-acid-barrel"] = a_recipe{
    energy = 0.2, ingredients = {fluid("sulfuric-acid", 50), item("barrel", 1)}, products = {item("sulfuric-acid-barrel", 1)}, category = "crafting-with-fluid",
  },
  -- A flask is filled like a barrel and made of iron plates alone, which the original design of the belts can build: a barrel is made of steel, whose furnace
  -- takes its fuel from a belt that design has no room for.
  ["gas-flask"] = a_recipe{
    energy = 0.2, ingredients = {fluid("petroleum-gas", 50), item("iron-plate", 2)}, products = {item("gas-flask", 1)}, category = "crafting-with-fluid",
  },
  ["acid-flask"] = a_recipe{
    energy = 0.2, ingredients = {fluid("sulfuric-acid", 50), item("iron-plate", 2)}, products = {item("acid-flask", 1)}, category = "crafting-with-fluid",
  },
  -- A box of circuits takes advanced circuits (made on belts, from plastic bar made in plants), so the plants are two steps below the last one.
  ["circuit-box"] = a_recipe{energy = 2, ingredients = {item("advanced-circuit", 2), item("iron-plate", 1)}, products = {item("circuit-box", 1)}},
  -- A pack of sulfur takes the sulfur that plants make from two fluids (water and petroleum gas).
  ["sulfur-pack"] = a_recipe{energy = 2, ingredients = {item("sulfur", 2), item("iron-plate", 1)}, products = {item("sulfur-pack", 1)}},
  -- Two flasks a craft, so that what a flask takes of the fluid is not the fluid of a craft.
  ["twin-flask"] = a_recipe{
    energy = 0.2, ingredients = {fluid("petroleum-gas", 50), item("iron-plate", 2)}, products = {item("twin-flask", 2)}, category = "crafting-with-fluid",
  },
  -- A gadget takes the gas, plastic bars (made in plants) and iron plates: a blueprint with a block that makes an item and a block that makes a fluid.
  ["gas-gadget"] = a_recipe{
    energy = 2, ingredients = {fluid("petroleum-gas", 50), item("plastic-bar", 2), item("iron-plate", 1)}, products = {item("gas-gadget", 1)}, category = "crafting-with-fluid",
  },
  -- A crate of flasks: the step that makes the flasks is not the last one, so the gas it takes cannot come from a part of the blueprint.
  ["gas-crate"] = a_recipe{energy = 1, ingredients = {item("gas-flask", 3), item("iron-plate", 1)}, products = {item("gas-crate", 1)}},
}
for name in pairs(oil_game.RECIPES) do
  config.recipes[name] = true
end

oil_game.ITEMS = {
  "iron-ore", "iron-plate", "copper-ore", "copper-plate", "steel-plate", "copper-cable", "electronic-circuit", "coal", "plastic-bar", "advanced-circuit", "sulfur",
  "explosives", "rocket", "battery", "accumulator", "barrel", "water-barrel", "petroleum-gas-barrel", "sulfuric-acid-barrel", "gas-flask", "acid-flask", "gas-crate", "gas-gadget", "twin-flask", "circuit-box", "sulfur-pack",
}

-- The machines of the game: the assembling machines, the refinery (with the fluid boxes given) and the chemical plant.
---@param refinery_boxes table[]
---@return table
local function machines(refinery_boxes)
  return {
    ["assembling-machine-1"] = a_machine{crafting_speed = 0.5, size = 3},
    ["assembling-machine-2"] = a_machine{crafting_speed = 0.75, size = 3, fluid_input = true},
    ["oil-refinery"] = a_machine{crafting_speed = 1, size = 5, pipe_boxes = refinery_boxes},
    ["chemical-plant"] = a_machine{crafting_speed = 1, size = 3, pipe_boxes = oil_game.PLANT_BOXES},
  }
end

-- The fake game: what `builders.fake_prototypes` takes, with `changes` merged in.
---@param changes? table
---@return table
function oil_game.the_game(changes)
  return builders.fake_prototypes(builders.merged(
    {furnace_speed = 1, items = oil_game.ITEMS, recipes = oil_game.RECIPES, machines = machines(oil_game.REFINERY_BOXES)}, changes))
end

-- The same game with the fluid boxes of the refinery that `boxes` says.
---@param boxes table[]
---@return table
function oil_game.the_game_with_refinery(boxes)
  return builders.fake_prototypes{furnace_speed = 1, items = oil_game.ITEMS, recipes = oil_game.RECIPES, machines = machines(boxes)}
end

-- The same game with the recipe of `name` missing.
---@param name string
---@return table
function oil_game.the_game_without_recipe(name)
  local recipes = {}
  for key, recipe in pairs(oil_game.RECIPES) do
    recipes[key] = key ~= name and recipe or nil
  end
  return builders.fake_prototypes{furnace_speed = 1, items = oil_game.ITEMS, recipes = recipes, machines = machines(oil_game.REFINERY_BOXES)}
end

-- The names the machines of a blueprint are told apart by, for the validator: the chemical plants by the recipe they make, and the assembling machines
-- that fill a barrel with a fluid that machines of the blueprint make by the fluid (the one that fills a barrel with water takes it from a pump).
local PLANT_NAMES = {
  ["plastic-bar"] = "plastic-plant", sulfur = "sulfur-plant", explosives = "explosives-plant", ["sulfuric-acid"] = "acid-plant", battery = "battery-plant",
}
local FILLER_NAMES = {
  ["petroleum-gas-barrel"] = "gas-barrel-filler", ["sulfuric-acid-barrel"] = "acid-barrel-filler", ["gas-flask"] = "gas-barrel-filler", ["acid-flask"] = "acid-barrel-filler",
  ["twin-flask"] = "gas-barrel-filler",
}

---@param entities table[]
---@return table[]
function oil_game.named(entities)
  local copies = {}
  for index, entity in ipairs(entities) do
    copies[index] = {}
    for key, value in pairs(entity) do
      copies[index][key] = value
    end
    if entity.name == "chemical-plant" then
      copies[index].name = PLANT_NAMES[entity.recipe]
    elseif entity.name == "assembling-machine-2" and FILLER_NAMES[entity.recipe] then
      copies[index].name = FILLER_NAMES[entity.recipe]
    end
  end
  return copies
end

-- The catalog of the validator: what the machines of the stand-in game take and give through their pipes. The plants of the plastic take the gas at
-- one of their two connections and the plants that take two fluids name them (the sulfur, the acid), each fluid a network of its own. The machine that
-- fills a barrel with water takes it in the middle of its input side (`fluid_input`); the ones that fill it with the gas or the acid that machines of the
-- blueprint make are told apart by `named`, with that fluid's network at the same place.
---@return table
function oil_game.catalog()
  local entries = builders.a_catalog{}
  local plant = {kind = "machine", width = 3, height = 3, needs_power = true}
  local function plant_with(connections)
    local entry = {}
    for key, value in pairs(plant) do
      entry[key] = value
    end
    entry.fluid_connections = connections
    return entry
  end
  entries["assembling-machine-1"] = plant
  entries["assembling-machine-2"] = {kind = "machine", width = 3, height = 3, needs_power = true, fluid_input = {["water-barrel"] = true}}
  entries["gas-barrel-filler"] = plant_with({gas = {{x = 1, y = -1}}})
  entries["acid-barrel-filler"] = plant_with({acid = {{x = 1, y = -1}}})
  entries["oil-refinery"] = {
    kind = "machine", width = 5, height = 5, needs_power = true, networks = {input = "crude", output = "gas"},
    fluid_connections = {input = {{x = 1, y = 5}, {x = 3, y = 5}}, output = {{x = 0, y = -1}, {x = 2, y = -1}, {x = 4, y = -1}}},
  }
  entries["plastic-plant"] = {
    kind = "machine", width = 3, height = 3, needs_power = true, networks = {input = "gas"}, fluid_connections = {input = {{x = 0, y = -1}, {x = 2, y = -1}}},
  }
  entries["sulfur-plant"] = plant_with({water = {{x = 0, y = -1}}, gas = {{x = 2, y = -1}}})
  entries["explosives-plant"] = plant_with({water = {{x = 0, y = -1}, {x = 2, y = -1}}})
  entries["acid-plant"] = plant_with({water = {{x = 0, y = -1}, {x = 2, y = -1}}, acid = {{x = 0, y = 3}, {x = 2, y = 3}}})
  entries["battery-plant"] = plant_with({acid = {{x = 0, y = -1}, {x = 2, y = -1}}})
  return entries
end

-- The catalog with the medium electric pole, which the design with one belt of each material uses.
---@param entries table
---@return table
function oil_game.with_medium_pole(entries)
  entries[builders.POLES.medium.name] = {
    kind = "pole", width = 1, height = 1, supply_radius = builders.POLES.medium.supply_distance, wire_reach = builders.POLES.medium.wire_distance,
  }
  return entries
end

-- What the message says the blueprint takes a minute, by the name of the item or the fluid, as the message words the amount.
---@param result {message: table}
---@return table<string, string>
function oil_game.taken(result)
  local amounts = {}
  for _, part in ipairs(result.message[4]) do
    if type(part) == "table" and part[1] == "blueprint-generation.raw-amount" then
      local name = part[3][1]:gsub("^%a+%-name%.", "")
      amounts[name] = part[2]
    end
  end
  return amounts
end

-- The names of what the message says the blueprint takes, in the order it lists them (the raw items, then the fuel, then the fluids).
---@param result {message: table}
---@return string[]
function oil_game.taken_in_order(result)
  local names = {}
  for _, part in ipairs(result.message[4]) do
    if type(part) == "table" and part[1] == "blueprint-generation.raw-amount" then
      local name = part[3][1]:gsub("^%a+%-name%.", "")
      names[#names + 1] = name
    end
  end
  return names
end

-- The names of the items shown on the display panels of the blueprint, sorted.
---@param entities bpgen.Entity[]
---@return string[]
function oil_game.panels_of(entities)
  local icons = {}
  for _, entity in ipairs(entities) do
    if entity.name == "display-panel" then
      icons[#icons + 1] = entity.icon.name
    end
  end
  table.sort(icons)
  return icons
end

return oil_game
