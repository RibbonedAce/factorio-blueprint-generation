-- scripts/generator.lua
-- The one place that reads the game's prototype data (recipes, machines) and
-- connects it to the pure planner and layout modules. Only call it from event
-- handlers: `prototypes` does not exist while control.lua is first loading.

local config = require("scripts.config")
local constants = require("scripts.constants")
local chain = require("scripts.chain")
local planner = require("scripts.planner")
local layout = require("scripts.layout")
local inputs = require("scripts.inputs")
local rows = require("scripts.rows")
local entity_list = require("scripts.entity_list")
local fluid_row = require("scripts.fluid_row")
local fluid_plant = require("scripts.fluid_plant")
local item_fluid_chain = require("scripts.item_fluid_chain")
local item_fluid_plants = require("scripts.item_fluid_plants")
local grid = require("scripts.grid")
local corner_entries = require("scripts.corner_entries")
local labels = require("scripts.labels")
local lights = require("scripts.lights")
local messages = require("scripts.messages")
local recipes = require("scripts.recipes")

local generator = {}

local north, east, south, west = defines.direction.north, defines.direction.east, defines.direction.south, defines.direction.west

-- How many ingredients one input belt carries: two, one on each lane. A step with more takes them from more belts: two
-- reached by long-handed inserters, or two or three woven.
local LANES_PER_BELT = constants.LANES_PER_BELT

-- How many belts a step whose machines take a fluid takes from, at most: the two woven belts that have room beside the pipe of its
-- machines (see scripts/layout.lua), so four items.
local FLUID_BELTS = 2
local MOST_FLUID_ITEMS = FLUID_BELTS * LANES_PER_BELT

-- Copy a recipe prototype into a plain table for the planner: the items it takes in `ingredients`, the fluids in `fluids` (the
-- layout brings them in through pipes, which only a step with two or more inputs can have: see `fluid_problem`). Each product
-- says whether it is an item or a fluid (the planner refuses a recipe with more than one product).
---@param prototype LuaRecipePrototype
---@return bpgen.Recipe
local function read_recipe(prototype)
  local recipe = {name = prototype.name, energy = prototype.energy, ingredients = {}, fluids = {}, products = {}}
  for _, ingredient in ipairs(prototype.ingredients) do
    local list = ({item = recipe.ingredients, fluid = recipe.fluids})[ingredient.type]
    assert(list, "generator: the game gives an ingredient of the type " .. tostring(ingredient.type) .. " in the recipe " .. prototype.name)
    list[#list + 1] = {name = ingredient.name, amount = ingredient.amount, fluidbox_index = ingredient.fluidbox_index}
  end
  for index, product in ipairs(prototype.products) do
    -- get_product_amount gives the average amount per craft, which also covers
    -- products with a random or ranged amount.
    recipe.products[#recipe.products + 1] = {name = product.name, amount = prototype.get_product_amount(index), type = product.type}
  end
  return recipe
end

-- Whether the force can build a building: it has unlocked the recipe, which the game names like the
-- building, and the building exists. Without a force (nothing is known to be researched) or without a name, nothing can be built.
---@param force LuaForce|nil
---@param name string|nil
---@return boolean
local function can_build(force, name)
  if not (force and name) then
    return false
  end
  local recipe = force.recipes[name]
  return recipe ~= nil and recipe.enabled and prototypes.entity[name] ~= nil
end

-- The prototype names of a tier of a building: the name itself for a building of one piece (a pole, a machine), the
-- names of its pieces for one of several (a belt, a splitter and an underground belt).
---@param tier string|table<string, string>
---@return string[]
local function names_of(tier)
  if type(tier) == "string" then
    return {tier}
  end
  local names = {}
  for _, name in pairs(tier) do
    names[#names + 1] = name
  end
  return names
end

-- Whether the force can build every piece of a tier.
---@param force LuaForce
---@param tier string|table<string, string>
---@return boolean
local function can_build_tier(force, tier)
  for _, name in ipairs(names_of(tier)) do
    if not can_build(force, name) then
      return false
    end
  end
  return true
end

-- The tier a blueprint is built with: the last of `tiers`, which go from the one every blueprint can count on to the
-- best, that the force has unlocked and the game has (every piece of it). Nothing is known without a force, which gets the
-- first. A tier is not held to the size or the fuel of the first: what a better building needs of the layout is for the
-- planner and the layouts to read from the game.
---@generic T: string|table<string, string>
---@param force LuaForce|nil
---@param tiers T[]
---@return T
local function best_tier(force, tiers)
  if force then
    for index = #tiers, 2, -1 do
      if can_build_tier(force, tiers[index]) then
        return tiers[index]
      end
    end
  end
  return tiers[1]
end

-- The building blocks every column of the blueprint shares, but for the numbers of the pole (see `add_pole_distances`).
---@param force LuaForce|nil  whose research decides the pole and the belts
---@return bpgen.SharedNames
local function shared_names(force)
  local belts = best_tier(force, config.entities.belts)
  return {
    belt = belts.belt, inserter = config.entities.inserter,
    long_inserter = config.entities.long_inserter, fast_inserter = config.entities.fast_inserter,
    pole = best_tier(force, config.entities.poles),
    lamp = config.entities.lamp, panel = config.entities.panel,
    pipe = config.entities.pipe, pipe_to_ground = config.entities.pipe_to_ground, pump = config.entities.pump,
    splitter = belts.splitter, underground = belts.underground,
  }
end

-- Tells the names how far their pole powers and how long a wire it holds, as the game says. A game that does not say is
-- a bug, not a case to fall back from: it stops with a message.
---@param names bpgen.SharedNames  whose pole exists
local function add_pole_distances(names)
  local prototype = prototypes.entity[names.pole]
  names.pole_supply_distance = assert(prototype.get_supply_area_distance(), "generator: the game does not give the supply area distance of " .. names.pole)
  local wire_distance = prototype.get_max_wire_distance()
  assert(wire_distance and wire_distance > 0, "generator: the game does not give the wire distance of " .. names.pole) -- 0 for an entity that holds no wire
  names.pole_wire_distance = wire_distance
end

-- Whether the buildings that every blueprint needs exist. The long-handed inserter is
-- not one of them: only recipes with three or more ingredients use it, and a game
-- without one is not refused (it gets the plain inserter for it, speed and stack size). Nor are the fast inserter, the splitter and the
-- underground belt: a blueprint takes them only when the force has them. Whether the
-- player has UNLOCKED these recipes is a separate question (see `locked_item`).
---@param entity_names string[]
---@return boolean
local function all_exist(entity_names)
  for _, entity_name in ipairs(entity_names) do
    if not prototypes.entity[entity_name] then
      return false
    end
  end
  return true
end

---@param names bpgen.SharedNames
---@return boolean
local function all_entities_exist(names)
  return all_exist({names.belt, names.inserter, names.pole})
end

-- The machine's size in tiles, when it is square (the layout only handles square machines).
---@param machine LuaEntityPrototype
---@return integer|nil
local function square_size(machine)
  if machine.tile_width == machine.tile_height then
    return machine.tile_width
  end
  return nil
end

-- Whether the machine takes a fluid in: one of its fluid boxes is for input. (The layout assumes the connection is in the middle of
-- the side the machine faces, as the assembling machine 2's is.)
---@param machine LuaEntityPrototype
---@return boolean
local function takes_fluid(machine)
  for _, box in ipairs(machine.fluidbox_prototypes) do
    if box.production_type == "input" or box.production_type == "input-output" then
      return true
    end
  end
  return false
end

---@class bpgen.EnergySource  what a machine runs on
---@field kind "electric"|"burner"
---@field fuel_categories string[]  the fuel categories a burner machine accepts, sorted; empty for an electric one

-- What the machine runs on, as plain data, or nil for a source this mod does not
-- handle yet (heat, fluid). A machine has at most one of the two sources the
-- game's prototype exposes here.
---@param machine LuaEntityPrototype
---@return bpgen.EnergySource|nil
local function read_energy_source(machine)
  if machine.electric_energy_source_prototype then
    return {kind = "electric", fuel_categories = {}}
  end
  local burner = machine.burner_prototype
  if burner then
    local categories = {}
    for category in pairs(burner.fuel_categories) do
      categories[#categories + 1] = category
    end
    table.sort(categories)
    return {kind = "burner", fuel_categories = categories}
  end
  return nil
end

-- The names of the items a machine can burn, as a set: the items in any of the
-- fuel categories it accepts. An electric machine, or one with an energy source
-- this mod does not handle, burns nothing. No categories also means no fuel (an
-- empty list of filters would match every item).
---@param energy_source bpgen.EnergySource|nil
---@return table<string, true>
local function burnable_by(energy_source)
  local fuels = {}
  if not energy_source or #energy_source.fuel_categories == 0 then
    return fuels
  end
  local filters = {}
  for _, category in ipairs(energy_source.fuel_categories) do
    filters[#filters + 1] = {filter = "fuel-category", ["fuel-category"] = category}
  end
  for name in pairs(prototypes.get_item_filtered(filters)) do
    fuels[name] = true
  end
  return fuels
end

-- The machine the config picks for a recipe: the one for the first of the recipe's
-- categories that has one, or nil when none has.
---@param prototype LuaRecipePrototype
---@return bpgen.MachineChoice|nil
local function machine_choice(prototype)
  for _, category in ipairs(prototype.categories) do
    local choice = config.machines[category]
    if choice then
      return choice
    end
  end
  return nil
end

-- A recipe that makes an item, with the machine the config picks for it.
---@class bpgen.Candidate
---@field prototype LuaRecipePrototype
---@field choice bpgen.MachineChoice

-- The recipes that make `item_name` in a machine the config names.
---@param item_name string
---@return bpgen.Candidate[]
local function candidate_recipes(item_name)
  local filters = {{filter = "has-product-item", elem_filters = {{filter = "name", name = item_name}}}}
  local found = {}
  for _, prototype in pairs(prototypes.get_recipe_filtered(filters)) do
    local choice = machine_choice(prototype)
    if choice then
      found[#found + 1] = {prototype = prototype, choice = choice}
    end
  end
  return found
end

---@param candidate bpgen.Candidate
---@param force LuaForce|nil  whose research decides the machine
---@return bpgen.Production
local function production_of(candidate, force)
  return {recipe = read_recipe(candidate.prototype), machine = best_tier(force, candidate.choice.tiers), fuel = candidate.choice.fuel}
end

-- How the game makes an item for a force, in the shape `chain.resolve` asks for (see `bpgen.RecipeLookup`). The recipe the player
-- picked makes its product as it is, whatever other recipes make it too (`picked`, with the product and how it is made); every
-- other item is made by the one recipe that makes it.
---@param force LuaForce|nil
---@param picked {item: string, production: bpgen.Production}
---@return bpgen.RecipeLookup
local function production_lookup(force, picked)
  return function(item_name)
    if item_name == picked.item then
      return picked.production
    end
    local candidates = candidate_recipes(item_name)
    local only = candidates[1]
    if only and #candidates == 1 then
      return production_of(only, force)
    end
    if #candidates == 0 then
      return nil, "no-recipe"
    end
    return nil, "ambiguous"
  end
end

-- How many of `fuel` a machine burns in a minute of crafting: its energy use divided by what
-- the fuel gives (the burner's effectivity counts too). nil for a machine that burns nothing or
-- when the game does not say. The game gives the energy use in joules per tick (ASSUMED, not
-- checked in game: a stone furnace, 90 kW, burns 1.35 coal a minute).
---@param machine LuaEntityPrototype
---@param fuel string|nil
---@return number|nil
local function read_fuel_use(machine, fuel)
  local burner = machine.burner_prototype
  local item = fuel and prototypes.item[fuel]
  local usage = machine.get_max_energy_usage()
  if not (burner and item and usage and item.fuel_value > 0 and burner.effectivity > 0) then
    return nil
  end
  return 60 * 60 * usage / (item.fuel_value * burner.effectivity)
end

-- One step of the recipe tree with what the game says about its machine, copied into
-- plain values, and the steps that make its ingredients. Returns nil if something is
-- missing (another mod could have removed or renamed it): the machine, or its crafting
-- speed, for this step or one of the steps below it.
---@class bpgen.StageData  one step and the machine that makes it
---@field item string  the item the step makes
---@field recipe bpgen.Recipe
---@field machine string  machine prototype name
---@field machine_type string  the type of the machine prototype: "furnace" or "assembling-machine", say
---@field fuel string|nil  item the machine burns, set by the config
---@field fuel_use number|nil  how many of `fuel` one machine burns a minute while it crafts; nil when the game does not say
---@field machine_speed number
---@field machine_size integer|nil  nil when the machine is not square
---@field fluid_input boolean  whether the machine has a fluid box that takes a fluid in
---@field energy_source bpgen.EnergySource|nil  nil when the machine runs on something unhandled
---@field fuels table<string, true>  the items the machine can burn, empty for an electric one
---@field suppliers bpgen.StageData[]  the steps that make its made ingredients, in the recipe's order
---@field raw_item string|nil  the raw ingredient that goes with the made ones, if any

---@param stage bpgen.ChainStage
---@return bpgen.StageData|nil
local function read_stage(stage)
  local machine = prototypes.entity[stage.machine]
  local machine_speed = machine and machine.get_crafting_speed()
  if not (machine and machine_speed) then
    return nil
  end
  local suppliers = {}
  for index, supplier in ipairs(stage.suppliers) do
    suppliers[index] = read_stage(supplier)
    if not suppliers[index] then
      return nil
    end
  end
  local energy_source = read_energy_source(machine)
  return {
    item = stage.item, recipe = stage.recipe, machine = stage.machine, machine_type = machine.type, fuel = stage.fuel,
    fuel_use = read_fuel_use(machine, stage.fuel),
    machine_speed = machine_speed, machine_size = square_size(machine), fluid_input = takes_fluid(machine),
    energy_source = energy_source, fuels = burnable_by(energy_source), suppliers = suppliers,
    raw_item = stage.raw_item,
  }
end

-- What the planner counts of one kind of inserter: how fast it swings and how many items one swing moves.
---@class bpgen.InserterData
---@field rotation_speed number  in turns a tick
---@field stack_size integer  the items its hand holds: one, the bonus built into the inserter and the force's inserter capacity bonus

-- What one call to `generate` works with, built once and not changed afterwards.
-- The steps below take it instead of the same values each: what the player asked
-- for, the tree of steps that makes it with their machines, and the game's numbers.
---@class bpgen.Job
---@field item_name string  the product of the recipe the player picked (the first, when it makes several, which the planner refuses)
---@field kind "belts"|"fluid_row"|"fluid_plant"|"item_fluid_chain"  how it is laid out (an item fluid chain is the blueprint of scripts/item_fluid_chain.lua, a fluid made from two items and a fluid, one item made in plants and the other on belts); the others: columns of machines with belts, a row of machines that make a fluid from a fluid (see scripts/fluid_row.lua), or plants that make an item from a fluid with the machines that make the fluid (see scripts/fluid_plant.lua)
---@field maker? bpgen.StageData  of a fluid plant: the step that makes the fluid the recipe takes
---@field made_fluid? string  of a fluid plant: the fluid of its recipe that the step makes (the other one, if it takes two, comes in by a pipe)
---@field parts? bpgen.ChainParts  of an item fluid chain: the step that makes the item made in plants (with `maker` and `made_fluid` for the machines that make its fluid) and the steps that make the other item on belts
---@field rate_per_minute number  how much of it
---@field root bpgen.StageData  the step of the recipe the player picked, with the steps below it that make what it takes
---@field names bpgen.SharedNames  the prototype names every column builds with
---@field belt_speed number
---@field inserter bpgen.InserterData
---@field long_inserter bpgen.InserterData  the long-handed inserter's, or the plain inserter's when the game has none
---@field fast_inserter? bpgen.InserterData  the fast inserter's, when the force has researched it and the game gives its speed; nil: plain inserters only
---@field lamp_supply_distance? number  how far a pole powers, when the blueprint gets lamps (the force has unlocked the small lamp); nil: no lamps
---@field labels boolean  whether the belts the player brings in get display panels (see scripts/labels.lua)
---@field row_labels boolean  whether the start of the pipe that brings the fluid into a row of machines that make a fluid gets a display panel (the force has unlocked the display panel)
---@field inputs? bpgen.InputOptions  asks for the design that brings in one belt of each material (see scripts/inputs.lua); nil for the original design, a belt of raw items for every chain

-- A job for one part of a blueprint that is made of several (see scripts/item_fluid_chain.lua): this job with the fields given instead, such as another
-- step as its root and a rate of its own. It reads everything else from this job.
---@param job bpgen.Job
---@param fields table
---@return bpgen.Job
local function part_of(job, fields)
  return setmetatable(fields, {__index = job}) --[[@as bpgen.Job]]
end

-- How many items the force's research adds to what one swing of an inserter moves: its inserter capacity bonus, which the inserter
-- takes unless its prototype leaves it out. Nothing is researched without a force. The game gives the bonus as a number that may
-- have a fraction, and a swing moves whole items. (The force keeps another number for bulk inserters, which no blueprint has.)
---@param name string  the inserter's prototype name
---@param prototype LuaEntityPrototype
---@param force LuaForce|nil
---@return integer
local function researched_stack_bonus(name, prototype, force)
  local takes_research = prototype.uses_inserter_stack_size_bonus
  assert(takes_research ~= nil, "generator: the game does not say whether " .. name .. " takes the inserter capacity bonus")
  if not (force and takes_research) then
    return 0
  end
  return math.floor(assert(force.inserter_stack_size_bonus, "generator: the game does not give the inserter capacity bonus of the force"))
end

-- What the planner counts of an inserter, or nil when the game does not say how fast it swings (it is no inserter). One swing
-- moves one item, the bonus built into the prototype, and the research of the force (see `researched_stack_bonus`).
---@param name string  the inserter's prototype name
---@param force LuaForce|nil
---@return bpgen.InserterData|nil
local function read_inserter(name, force)
  local prototype = prototypes.entity[name]
  local rotation_speed = prototype.get_inserter_rotation_speed()
  if not rotation_speed then
    return nil
  end
  local built_in = assert(prototype.inserter_stack_size_bonus, "generator: the game does not give the stack size bonus of " .. name)
  return {rotation_speed = rotation_speed, stack_size = 1 + built_in + researched_stack_bonus(name, prototype, force)}
end

-- The fast inserter when the blueprint may use it: the force has unlocked its recipe (nothing is known without a force) and the
-- game has the building and says how fast it swings. Nil otherwise: the blueprint then takes plain inserters only, as it always did.
---@param names bpgen.SharedNames
---@param force LuaForce|nil
---@return bpgen.InserterData|nil
local function read_fast_inserter(names, force)
  if not can_build(force, names.fast_inserter) then
    return nil
  end
  return read_inserter(names.fast_inserter, force)
end

-- How far the pole powers (2.5 tiles for a small pole) if the blueprint gets lamps: the force has unlocked the small
-- lamp (nothing is known without a force) and the game has it. Nil otherwise: the blueprint then has no lamps, as it
-- never had.
---@param names bpgen.SharedNames  with the numbers of its pole
---@param force LuaForce|nil
---@return number|nil
local function lamp_distance(names, force)
  if not can_build(force, names.lamp) then
    return nil
  end
  return names.pole_supply_distance
end

-- Whether the belts the player brings in get a display panel with their item: the blueprint has such belts (the design that
-- brings in one belt of each material), the force has unlocked the display panel (nothing is known without a force) and the
-- game has it. Otherwise the blueprint has no panels, as it never had.
---@param names bpgen.SharedNames
---@param force LuaForce|nil
---@param input_design boolean  the blueprint takes the design that brings in one belt of each material
---@return boolean
local function wants_labels(names, force, input_design)
  return input_design and can_build(force, names.panel)
end

-- What the design that brings in one belt of each material is asked for, or nil when the blueprint is
-- to take the original design, which needs neither building: the force has to have researched the splitter
-- and the underground belt (nothing is known without a force), and the underground belt has to span
-- enough tiles for the hops under the belts of the design.
---@param names bpgen.SharedNames
---@param belt_speed number
---@param force LuaForce|nil
---@return bpgen.InputOptions|nil
local function input_options(names, belt_speed, force)
  if not (can_build(force, names.splitter) and can_build(force, names.underground)) then
    return nil
  end
  local reach = prototypes.entity[names.underground].max_underground_distance
  if not (reach and reach >= inputs.MIN_REACH) then
    return nil
  end
  return {lane_items_per_minute = planner.lane_items_per_minute(belt_speed), underground_reach = reach}
end

-- The steps for the recipe the player picked with the data of their machines: the step that makes its product, with the steps that
-- make what it takes. Nil and the message for the player when it cannot be made from steps we can build or the game lacks a
-- machine.
---@param prototype LuaRecipePrototype  the recipe picked
---@param force LuaForce|nil  whose research decides the machines
---@return bpgen.StageData|nil
---@return LocalisedString|nil error_message
local function read_root(prototype, force)
  local product = prototype.products[1]
  if not product then
    return nil, messages.unsupported_recipe()
  end
  local choice = machine_choice(prototype)
  if not choice then
    return nil, messages.chain_problem("no-recipe", product.name)
  end
  local picked = {item = product.name, production = production_of({prototype = prototype, choice = choice}, force)}
  local stage, reason, culprit = chain.resolve(product.name, production_lookup(force, picked))
  if not stage then
    ---@cast reason bpgen.ChainReason -- there is always a reason when there is no step
    ---@cast culprit string
    return nil, messages.chain_problem(reason, culprit)
  end
  local root = read_stage(stage)
  if not root then
    return nil, messages.missing_prototype()
  end
  return root, nil
end

-- The speed of the belt and the inserters the layout uses, or nil when the belt or the plain
-- inserter is missing from the game. `belt_speed` is nil unless the entity really is a transport
-- belt, and the inserters are nil unless they really are inserters. A game without a long-handed
-- inserter gets the plain inserter for it.
---@param names bpgen.SharedNames
---@param force LuaForce|nil  whose research decides how many items an inserter moves in a swing
---@return number|nil belt_speed
---@return bpgen.InserterData|nil inserter
---@return bpgen.InserterData|nil long_inserter
local function read_speeds(names, force)
  if not all_entities_exist(names) then
    return nil
  end
  local inserter = read_inserter(names.inserter, force)
  local long = prototypes.entity[names.long_inserter] and read_inserter(names.long_inserter, force)
  return prototypes.entity[names.belt].belt_speed, inserter, long or inserter
end

-- Adds to a job what the force has unlocked: the fast inserter, the lamp, the design with one belt of each material and the
-- display panel for its belts.
---@param job bpgen.Job  with what the game says
---@param force LuaForce|nil
---@return bpgen.Job
local function add_unlocked(job, force)
  local names = job.names
  job.fast_inserter = read_fast_inserter(names, force)
  job.lamp_supply_distance = lamp_distance(names, force)
  job.input_options = input_options(names, job.belt_speed, force)
  job.labels = wants_labels(names, force, job.input_options ~= nil)
  job.row_labels = wants_labels(names, force, true)
  return job
end

-- The prototype of the recipe the player picked, or nil and the message for the player when the config does not list it or
-- the game does not have it (another mod could have removed a recipe the config names).
---@param recipe_name string
---@return LuaRecipePrototype|nil
---@return LocalisedString|nil error_message
local function picked_recipe(recipe_name)
  if not config.recipes[recipe_name] then
    return nil, messages.unsupported_pick()
  end
  local prototype = prototypes.recipe[recipe_name]
  if not prototype then
    return nil, messages.chain_problem("no-recipe", recipe_name)
  end
  return prototype, nil
end

-- The names of the buildings and the speeds of the belt and the inserters that every blueprint uses (the start of a job), or nil and
-- the message for the player when the game lacks one.
---@param force LuaForce|nil
---@return table|nil job_part
---@return LocalisedString|nil error_message
local function read_buildings(force)
  local names = shared_names(force)
  local belt_speed, inserter, long_inserter = read_speeds(names, force)
  if not (belt_speed and inserter and long_inserter) then
    return nil, messages.missing_prototype()
  end
  add_pole_distances(names)
  return {names = names, belt_speed = belt_speed, inserter = inserter, long_inserter = long_inserter}
end

-- The step that makes a fluid that a recipe takes: the recipe the config names for it (`config.fluid_makers`) with its machines.
-- Nil and the message for the player when the config names none, or the game does not have it.
---@param fluid_name string
---@param force LuaForce|nil
---@return bpgen.StageData|nil
---@return LocalisedString|nil error_message
local function read_maker(fluid_name, force)
  local recipe_name = config.fluid_makers[fluid_name]
  local prototype = recipe_name and prototypes.recipe[recipe_name]
  if not prototype then
    return nil, messages.chain_problem("no-recipe", fluid_name)
  end
  return read_root(prototype, force)
end

-- The fluid of a plant's recipe that a row of machines makes: the one the config names a recipe for (the first one, which then has no
-- recipe to make it, when it names none). Nil when it names a recipe for more than one.
---@param recipe bpgen.Recipe
---@return string|nil
local function made_fluid_of(recipe)
  local made = {}
  for _, fluid in ipairs(recipe.fluids) do
    if config.fluid_makers[fluid.name] then
      made[#made + 1] = fluid.name
    end
  end
  if #made > 1 then
    return nil
  end
  return made[1] or recipe.fluids[1].name
end

-- Whether the recipe of a step is one for plants: one fluid or two and nothing else, or one raw item and one fluid that the config has
-- a recipe for (a recipe that takes a fluid that is raw and an item goes on belts, to a machine with a fluid input).
---@param stage bpgen.StageData
---@return boolean
local function takes_fluids_for_plants(stage)
  local items, fluids = #stage.recipe.ingredients, #stage.recipe.fluids
  if items == 0 then
    return fluids == 1 or fluids == 2
  end
  return items == 1 and fluids == 1 and #stage.suppliers == 0 and config.fluid_makers[stage.recipe.fluids[1].name] ~= nil
end

-- Whether a step is made in plants from fluids alone (sulfur: petroleum gas and water), which a blueprint of an item fluid chain builds with the
-- machines that make its fluid.
---@param stage bpgen.StageData
---@return boolean
local function is_plants_step(stage)
  return #stage.suppliers == 0 and #stage.recipe.ingredients == 0 and planner.is_plant_recipe(stage.recipe, stage.item)
end

-- Whether no step of the tree takes a fluid, which the layout of belts builds from raw items.
---@param stage bpgen.StageData
---@return boolean
local function takes_no_fluid(stage)
  if #stage.recipe.fluids > 0 then
    return false
  end
  for _, supplier in ipairs(stage.suppliers) do
    if not takes_no_fluid(supplier) then
      return false
    end
  end
  return true
end

-- The parts of a recipe with one made item, made in plants, and one raw item (explosives: sulfur made in plants, and coal): the raw one has
-- no machines, only a belt that comes in. Nil for any other recipe with one made item.
---@param root bpgen.StageData
---@return bpgen.ChainParts|nil
local function raw_item_parts_of(root)
  if root.raw_item and is_plants_step(root.suppliers[1]) then
    return {plants = root.suppliers[1], raw_item = root.raw_item}
  end
  return nil
end

-- The parts of a recipe with two made items, when one is made in plants and the other on belts, in either order; nil for any other two.
---@param first bpgen.StageData
---@param second bpgen.StageData
---@return bpgen.ChainParts|nil
local function two_made_parts_of(first, second)
  if is_plants_step(first) and takes_no_fluid(second) then
    return {plants = first, belts = second}
  end
  if is_plants_step(second) and takes_no_fluid(first) then
    return {plants = second, belts = first}
  end
  return nil
end

-- The steps that make the two items of a recipe that takes two items and a fluid, when one is made in plants and the other on belts (iron
-- plate), or is raw, or nil.
---@param root bpgen.StageData
---@return bpgen.ChainParts|nil
local function chain_parts_of(root)
  if #root.recipe.ingredients ~= 2 or #root.recipe.fluids ~= 1 then
    return nil
  end
  if #root.suppliers == 1 then
    return raw_item_parts_of(root)
  end
  return #root.suppliers == 2 and two_made_parts_of(root.suppliers[1], root.suppliers[2]) or nil
end

-- The step that makes the fluid a step that is made in plants takes from a row of machines, and the name of that fluid. Nil and the message
-- for the player when the config names no recipe for it, or more than one of its fluids has one.
---@param stage bpgen.StageData  made in plants
---@param force LuaForce|nil
---@return bpgen.StageData|nil maker
---@return string|nil fluid
---@return LocalisedString|nil error_message
local function read_made_fluid(stage, force)
  local fluid = made_fluid_of(stage.recipe)
  if not fluid then
    return nil, nil, messages.fluid_row_recipe(stage.item)
  end
  local maker, problem = read_maker(fluid, force)
  if not maker then
    return nil, nil, problem
  end
  return maker, fluid
end

-- How a recipe is laid out, and what its layout needs of the game.
---@class bpgen.Arrangement
---@field kind "belts"|"fluid_row"|"fluid_plant"|"item_fluid_chain"
---@field maker? bpgen.StageData  the step that makes the fluid the plants take
---@field made_fluid? string
---@field parts? bpgen.ChainParts

-- The parts of an item fluid chain: the step made in plants and either the steps that make the other item on belts or the name of that item
-- when it is raw (it comes in by a belt and has no machines).
---@class bpgen.ChainParts
---@field plants bpgen.StageData
---@field belts? bpgen.StageData
---@field raw_item? string

-- The layout of a recipe with plants made of a step: the step that makes the fluid they take, and what the layout is called. Nil and the
-- message for the player when the fluid has no recipe to make it.
---@param plants bpgen.StageData  the step made in plants
---@param kind "fluid_plant"|"item_fluid_chain"
---@param parts bpgen.ChainParts|nil
---@param force LuaForce|nil
---@return bpgen.Arrangement|nil
---@return LocalisedString|nil error_message
local function read_plants_layout(plants, kind, parts, force)
  local maker, fluid, problem = read_made_fluid(plants, force)
  if not maker then
    return nil, problem
  end
  return {kind = kind, maker = maker, made_fluid = fluid, parts = parts}
end

-- How the recipe is laid out: "fluid_row" for one that makes a fluid, "item_fluid_chain" for one that makes a fluid from two items and a fluid,
-- one of the items made in plants and the other on belts, "fluid_plant" for one that makes an item from one fluid or two, or one fluid and
-- one raw item, and nothing else, with the step that makes the fluid and the name of the fluid it makes, and "belts" for the others. Nil
-- and the message for the player when the fluid of a plant has no recipe to make it.
---@param root bpgen.StageData  the step of the recipe the player picked
---@param force LuaForce|nil
---@return bpgen.Arrangement|nil
---@return LocalisedString|nil error_message
local function read_layout(root, force)
  local makes_fluid = root.recipe.products[1].type == "fluid"
  local parts = #root.recipe.ingredients > 0 and chain_parts_of(root) or nil
  if parts then
    return read_plants_layout(parts.plants, "item_fluid_chain", parts, force)
  end
  if makes_fluid then
    return {kind = "fluid_row"}
  end
  if not takes_fluids_for_plants(root) then
    return {kind = "belts"}
  end
  return read_plants_layout(root, "fluid_plant", nil, force)
end

-- The job for this request, or nil and the message for the player when the recipe is
-- not supported or something it needs is missing from the game. The rate is of the
-- product of the recipe.
---@param recipe_name string  the recipe the player picked
---@param rate_per_minute number
---@param force LuaForce|nil  whose research decides the design of the inputs; nil takes the original
---@return bpgen.Job|nil
---@return LocalisedString|nil error_message
local function read_job(recipe_name, rate_per_minute, force)
  local prototype, problem = picked_recipe(recipe_name)
  if not prototype then
    return nil, problem
  end
  local job
  job, problem = read_buildings(force)
  if not job then
    return nil, problem
  end
  local root
  root, problem = read_root(prototype, force)
  if not root then
    return nil, problem
  end
  local arrangement, layout_problem = read_layout(root, force)
  if not arrangement then
    return nil, layout_problem
  end
  job.item_name, job.rate_per_minute, job.root, job.kind = root.item, rate_per_minute, root, arrangement.kind
  job.maker, job.made_fluid, job.parts = arrangement.maker, arrangement.made_fluid, arrangement.parts
  return add_unlocked(job --[[@as bpgen.Job]], force) -- what the force has unlocked is added just below
end

-- The item whose recipe the force has not unlocked yet, or nil when the force has it. Only
-- the recipe the player picked is looked at (owner, 2026-11-08): in the game a recipe is never
-- unlocked before those of its ingredients, nor before the crafting machine it needs, and
-- the buildings (long-handed inserter, belt, splitter, underground belt, inserter, pole) are left to a later feature
-- that will unlock by the entities a blueprint places.
---@param job bpgen.Job
---@param force LuaForce
---@return string|nil item  the product of the recipe
local function locked_item(job, force)
  if recipes.is_locked(job.root.recipe.name, force) then
    return job.root.item
  end
  return nil
end

-- Whether the fuel the config sets for a machine suits it: an electric
-- machine takes none, and a burner machine needs one it can burn.
---@param fuel string|nil
---@param energy_source bpgen.EnergySource
---@param burnable table<string, true>  the items the machine can burn
---@return boolean
local function suits_machine(fuel, energy_source, burnable)
  if energy_source.kind == "electric" then
    return fuel == nil
  end
  return fuel ~= nil and burnable[fuel] == true
end

-- The steps of a tree, each after the steps that make its ingredients, so that a chain
-- goes from the raw items to the product. Works for steps and for planned steps.
---@param stage {suppliers: table[]}
---@param list table[]
---@return table[]
local function in_order(stage, list)
  for _, supplier in ipairs(stage.suppliers) do
    in_order(supplier, list)
  end
  list[#list + 1] = stage
  return list
end

-- The reason a step that is fed by other steps cannot burn fuel, as a message for the player, or nil. Its fuel rides the
-- lane the product of the step before it leaves free, so it can eat only that one product; and only the design that
-- brings in one belt of each material brings the fuel.
---@param stage bpgen.StageData
---@param has_inputs boolean  whether that design is available
---@return LocalisedString|nil
local function fuel_problem(stage, has_inputs)
  if #stage.suppliers == 0 or not stage.fuel then
    return nil
  end
  if #stage.suppliers ~= 1 or #stage.recipe.ingredients ~= 1 or chain.input_count(stage.suppliers[1]) > 1 then
    return messages.chain_fuel(stage.item)
  end
  if not has_inputs then
    return messages.fuel_needs_inputs(stage.item)
  end
  return nil
end

-- Whether the blueprint can weave input belts for a step that takes from more than one belt (see scripts/weave.lua): it is
-- of the design that brings in one belt of each material, whose splitters and underground belts the weave is made of, the
-- underground belt spans the longest hop of the weave, and the pole of the blueprint reaches the inserters beside two belts.
-- Without that a step takes its second belt with long-handed inserters, which every game has from the start.
---@param job bpgen.Job
---@return boolean
local function can_weave(job)
  return job.input_options ~= nil and job.input_options.underground_reach >= layout.WEAVE_REACH
    and layout.most_woven_belts(layout.pole_reach(job.names.pole_supply_distance)) >= 2
end

-- How many input belts a step of the blueprint takes from, at most: woven belts where the blueprint can weave them, as many
-- as its pole serves (see `layout.most_woven_belts`: three need the medium pole), else two, the second reached by long-handed
-- inserters over the first.
---@param job bpgen.Job
---@return integer
local function most_input_belts(job)
  if can_weave(job) then
    return layout.most_woven_belts(layout.pole_reach(job.names.pole_supply_distance))
  end
  return layout.LONG_HANDED_BELTS
end

-- The reason a step with more ingredients than `belts` belts carry (two each, one on each lane) cannot be built, as a message
-- for the player, or nil: it needs three woven belts, which the blueprint has to be able to weave.
---@param stage bpgen.StageData
---@param belts integer  the most belts the blueprint takes from (see `most_input_belts`)
---@return LocalisedString|nil
local function belts_problem(stage, belts)
  if #stage.suppliers == 0 or #stage.recipe.ingredients <= belts * LANES_PER_BELT then
    return nil
  end
  return messages.belts_need_weave(stage.item)
end

-- Whether the machine and the recipe of a step that takes a fluid are what the layout draws pipes for: one fluid, no more than
-- four items, and a machine with a fluid input of the size it draws them for.
---@param stage bpgen.StageData
---@return boolean
local function is_built_with_fluid(stage)
  return #stage.recipe.fluids == 1 and #stage.recipe.ingredients <= MOST_FLUID_ITEMS
    and stage.fluid_input and layout.max_fluid_inserters(stage.machine_size) ~= nil
end

-- The reason the belts and the pipes of a step that takes a fluid cannot be built, as a message for the player, or nil: more
-- than two items need woven belts, which the blueprint has to be able to weave, and the pipes need the game's pipes and pump.
---@param job bpgen.Job
---@param stage bpgen.StageData
---@return LocalisedString|nil
local function fluid_buildings_problem(job, stage)
  if #stage.recipe.ingredients > LANES_PER_BELT and not can_weave(job) then
    return messages.fluid_needs_weave(stage.item)
  end
  if not all_exist({job.names.pipe, job.names.pipe_to_ground, job.names.pump}) then
    return messages.missing_prototype()
  end
  return nil
end

-- The reason a step that takes a fluid cannot be built, as a message for the player, or nil. The pipes come to a column that takes
-- at least two things from other steps and belts (the column of a step in a chain has no room for the pipes beside its belt);
-- the step needs a machine, and a recipe, that the pipes are drawn for (see `is_built_with_fluid`).
---@param job bpgen.Job
---@param stage bpgen.StageData
---@return LocalisedString|nil
local function fluid_problem(job, stage)
  if #stage.recipe.fluids == 0 then
    return nil
  end
  if chain.input_count(stage) < 2 then
    return messages.fluid_single_input(stage.item)
  end
  if not is_built_with_fluid(stage) then
    return messages.fluid_unsupported(stage.item)
  end
  return fluid_buildings_problem(job, stage)
end

-- The reason the recipe of a step cannot be built with what the blueprint has, as a message for the player, or nil: the fuel it
-- burns, the fluid it takes and the belts that carry its ingredients.
---@param job bpgen.Job
---@param stage bpgen.StageData
---@return LocalisedString|nil
local function recipe_problem(job, stage)
  return fuel_problem(stage, job.input_options ~= nil) or fluid_problem(job, stage) or belts_problem(stage, most_input_belts(job))
end

-- The reason this step's machine cannot be built with, as a message for the player, or nil.
---@param job bpgen.Job
---@param stage bpgen.StageData
---@return LocalisedString|nil
local function stage_problem(job, stage)
  local size = stage.machine_size
  if not size or not layout.supports_machine_size(size) then
    return messages.unsupported_machine()
  end
  local energy_source = stage.energy_source
  if not energy_source then
    return messages.unsupported_energy()
  end
  local problem = recipe_problem(job, stage)
  if problem then
    return problem
  end
  if not suits_machine(stage.fuel, energy_source, stage.fuels) then
    return messages.fuel_mismatch(prototypes.entity[stage.machine].localised_name)
  end
  return nil
end

-- The tile beyond a tile of a machine, as a step in tiles, by the way a pipe connection points.
---@type table<defines.direction, {x: integer, y: integer}>
local CONNECTION_STEPS = {
  [north] = {x = 0, y = -1}, [east] = {x = 1, y = 0}, [south] = {x = 0, y = 1}, [west] = {x = -1, y = 0},
}

-- Whether a tile is one of the tiles of a machine of `size` tiles on a side, counted from its top-left tile.
---@param tile {x: integer, y: integer}
---@param size integer
---@return boolean
local function on_machine(tile, size)
  return tile.x >= 0 and tile.x < size and tile.y >= 0 and tile.y < size
end

-- The tile of the pipe at a pipe connection of a machine of `size` tiles, from its top-left tile, as it faces north. The game gives
-- a connection as the position, from the centre of the machine, of the tile OF THE MACHINE it is on, at its edge, and the way it
-- points (its own example is the assembling machine 2: `position = {0, -1}`, `direction = north`, so the connection is on the top
-- row, in the middle). The pipe stands on the tile beyond, outside the machine. `positions` has the position for each of the four
-- ways the machine can face, the one for north first. Nil for a connection that is not an ordinary one (an underground one, a
-- linked one).
---@param connection PipeConnectionDefinition
---@param size integer
---@return {x: integer, y: integer}|nil
local function connection_tile(connection, size)
  if connection.connection_type ~= "normal" then
    return nil
  end
  local position = assert(connection.positions[1], "generator: the game does not give the position of a pipe connection of the machine")
  local step = assert(CONNECTION_STEPS[connection.direction], "generator: the game gives a pipe connection of the machine a direction other than north, east, south or west")
  local on = {x = math.floor(size / 2 + position.x), y = math.floor(size / 2 + position.y)}
  local beyond = {x = on.x + step.x, y = on.y + step.y}
  assert(on_machine(on, size) and not on_machine(beyond, size), string.format(
    "generator: a pipe connection of the machine is on the tile %d,%d and points to the tile %d,%d, which is not from a tile at the edge of the machine to one outside it (%d tiles on a side)",
    on.x, on.y, beyond.x, beyond.y, size))
  return beyond
end

-- The fluid boxes of a machine as plain data: where the pipes of each connect, for the machine facing north.
---@param machine LuaEntityPrototype
---@param size integer
---@return bpgen.FluidBox[]
local function read_fluid_boxes(machine, size)
  local boxes = {}
  for _, box in ipairs(machine.fluidbox_prototypes) do
    local tiles = {}
    for _, connection in ipairs(box.pipe_connections) do
      tiles[#tiles + 1] = connection_tile(connection, size)
    end
    boxes[#boxes + 1] = {production_type = box.production_type, tiles = tiles}
  end
  return boxes
end

-- The rows of pipes of the machines of a step that makes a fluid (see `fluid_row.rows_of`), or nil when their pipe
-- connections are not in rows of the kind the layout draws.
---@param stage bpgen.StageData  its machine is square
---@return bpgen.FluidRows|nil
local function fluid_rows_of(stage)
  local size = stage.machine_size --[[@as integer]]
  return fluid_row.rows_of(read_fluid_boxes(prototypes.entity[stage.machine], size), size)
end

-- Whether the pole of the blueprint can power a machine from beyond the pipes beside it (two tiles away) and reach the pole of the
-- next machine.
---@param names bpgen.SharedNames
---@param size integer  the machine's size
---@return boolean
local function poles_fit_row(names, size)
  return layout.pole_reach(names.pole_supply_distance) >= 2 and size <= names.pole_wire_distance
end

-- The reason the machine of a step that makes a fluid cannot be built with, as a message for the player, or nil: it is square,
-- electric, and the pipe exists.
---@param job bpgen.Job
---@param stage bpgen.StageData
---@return LocalisedString|nil
local function fluid_row_machine_problem(job, stage)
  if not stage.machine_size then
    return messages.unsupported_machine()
  end
  if not (stage.energy_source and stage.energy_source.kind == "electric") then
    return messages.unsupported_energy()
  end
  if not prototypes.entity[job.names.pipe] then
    return messages.missing_prototype()
  end
  return nil
end

-- The reason a fluid cannot be made as a row of machines, as a message for the player, or nil.
---@param job bpgen.Job
---@param stage bpgen.StageData  the step that makes the fluid, whose machines are the row
---@return LocalisedString|nil
local function fluid_row_problem(job, stage)
  local problem = fluid_row_machine_problem(job, stage)
  if problem then
    return problem
  end
  if not planner.is_fluid_recipe(stage.recipe, stage.item) then
    return messages.fluid_row_recipe(stage.item)
  end
  if not fluid_rows_of(stage) then
    return messages.fluid_row_pipes(stage.item)
  end
  if not poles_fit_row(job.names, stage.machine_size --[[@as integer]]) then
    return messages.fluid_row_poles(stage.item)
  end
  return nil
end

-- Whether the pole of the blueprint can power the inserter beside the middle of a plant and reach the pole of the next plant.
---@param names bpgen.SharedNames
---@param size integer  the machine's size
---@return boolean
local function poles_fit_plant(names, size)
  return layout.pole_reach(names.pole_supply_distance) >= math.floor(size / 2) and size <= names.pole_wire_distance
end

-- Whether the index is one of the two input fluid boxes of a plant that takes two fluids.
---@param index integer|nil
---@return boolean
local function is_input_box(index)
  return index == 1 or index == 2
end

-- Which input fluid box of a plant takes each fluid of a recipe that takes two: the one the recipe says (`fluidbox_index`) or else the
-- order of the fluid. Gives the box of the fluid the machines of the row make (`made`) and of the other one, or nil when they are
-- not the two boxes. For a recipe of one fluid, nil.
---@param recipe bpgen.Recipe
---@param made string  the name of the fluid the machines of the row make
---@return {source: integer, supplied: integer}|nil
local function plant_fluid_boxes(recipe, made)
  local boxes = {}
  for order, fluid in ipairs(recipe.fluids) do
    boxes[fluid.name == made and "source" or "supplied"] = fluid.fluidbox_index or order
  end
  local source, supplied = boxes.source, boxes.supplied
  if is_input_box(source) and is_input_box(supplied) and source ~= supplied then
    return boxes
  end
  return nil
end

-- The reason a plant that takes two fluids cannot be built, as a message for the player, or nil: the recipe puts the fluids in the
-- two input boxes of the machine, whose connections are at its top and bottom rows, and the game has the pipe that goes under.
---@param job bpgen.Job
---@param stage bpgen.StageData  the step of the recipe picked
---@param rows bpgen.FluidRows
---@return LocalisedString|nil
local function two_fluids_problem(job, stage, rows)
  local size = stage.machine_size --[[@as integer]]
  local boxes = read_fluid_boxes(prototypes.entity[stage.machine], size)
  if not (plant_fluid_boxes(stage.recipe, job.made_fluid --[[@as string]]) and fluid_plant.two_input_rows(boxes, size, rows)) then
    return messages.fluid_row_pipes(stage.item)
  end
  if not all_exist({job.names.pipe_to_ground}) then
    return messages.missing_prototype()
  end
  return nil
end

-- The reason the plant itself (not the machines that make its fluid) cannot be built, as a message for the player, or nil: its
-- recipe, the rows of its pipe connections, and the pole.
---@param job bpgen.Job
---@param stage bpgen.StageData  the step of the recipe picked
---@return LocalisedString|nil
local function plant_problem(job, stage)
  if not planner.is_plant_recipe(stage.recipe, stage.item) then
    return messages.fluid_row_recipe(stage.item)
  end
  local rows = fluid_rows_of(stage)
  if not rows then
    return messages.fluid_row_pipes(stage.item)
  end
  local problem = #stage.recipe.fluids == 2 and two_fluids_problem(job, stage, rows)
  if problem then
    return problem
  end
  if #stage.recipe.ingredients == 1 and not all_exist({job.names.pipe_to_ground}) then
    return messages.missing_prototype()
  end
  if not poles_fit_plant(job.names, stage.machine_size --[[@as integer]]) then
    return messages.fluid_row_poles(stage.item)
  end
  return nil
end

-- The reason an item cannot be made from a fluid in plants, with the machines that make the fluid, as a message for the player, or
-- nil: the row of machines that make the fluid, and the machines and the pipe of the plants, fit.
---@param job bpgen.Job
---@return LocalisedString|nil
local function fluid_plant_problem(job)
  if job.maker.item ~= job.made_fluid then
    return messages.fluid_row_recipe(job.made_fluid --[[@as string]])
  end
  return fluid_row_problem(job, job.maker) or fluid_row_machine_problem(job, job.root) or plant_problem(job, job.root)
end

-- The plants of a step as `fluid_plant` and `item_fluid_plants` take them: the machine, the recipe, the size, how many, and the pipe
-- connections as the game gives them. `rows` is nil for a machine whose connections are not in rows.
---@param stage bpgen.StageData
---@param count integer
---@return table
local function plants_of(stage, count)
  local size = stage.machine_size --[[@as integer]]
  local boxes = read_fluid_boxes(prototypes.entity[stage.machine], size)
  return {
    machine = stage.machine, recipe = stage.recipe.name, size = size, count = count, boxes = boxes, rows = fluid_row.rows_of(boxes, size),
    item_output = stage.recipe.products[1].type ~= "fluid",
  }
end

-- The reason plants that make a fluid from two items and a fluid cannot be built, as a message for the player, or nil: the recipe, the
-- machine, the rows of its pipe connections (the layout needs a row with none, for the inserter), the underground pipe and the pole.
---@param job bpgen.Job
---@param stage bpgen.StageData
---@return LocalisedString|nil
local function item_fluid_plants_problem(job, stage)
  if not planner.is_item_fluid_recipe(stage.recipe, stage.item) or config.fluid_makers[stage.recipe.fluids[1].name] then
    return messages.fluid_row_recipe(stage.item)
  end
  local problem = fluid_row_machine_problem(job, stage)
  if problem then
    return problem
  end
  local plants = plants_of(stage, 1)
  if not (plants.rows and item_fluid_plants.fits(plants)) then
    return messages.fluid_row_pipes(stage.item)
  end
  if not all_exist({job.names.pipe_to_ground}) then
    return messages.missing_prototype()
  end
  if not poles_fit_row(job.names, plants.size) then
    return messages.fluid_row_poles(stage.item)
  end
  return nil
end

-- The reason a fluid cannot be made from two items and a fluid with the item made in plants and the other on belts, as a message for the
-- player, or nil: the plants of the first item with the machines that make their fluid, the plants of the fluid, and the steps of the belts.
---@param job bpgen.Job
---@return LocalisedString|nil
local function item_fluid_chain_problem(job)
  local parts = job.parts --[[@as bpgen.ChainParts]]
  local problem = fluid_plant_problem(part_of(job, {root = parts.plants, kind = "fluid_plant"})) or item_fluid_plants_problem(job, job.root)
  if problem then
    return problem
  end
  for _, stage in ipairs(parts.belts and in_order(parts.belts, {}) or {}) do
    problem = stage_problem(job, stage)
    if problem then
      return problem
    end
  end
  return nil
end

-- The reason one of the machines cannot be built with, as a message for the player, or nil.
---@param job bpgen.Job
---@return LocalisedString|nil
local function machine_problem(job)
  if job.kind == "fluid_row" then
    return fluid_row_problem(job, job.root)
  end
  if job.kind == "fluid_plant" then
    return fluid_plant_problem(job)
  end
  if job.kind == "item_fluid_chain" then
    return item_fluid_chain_problem(job)
  end
  for _, stage in ipairs(in_order(job.root, {})) do
    local problem = stage_problem(job, stage)
    if problem then
      return problem
    end
  end
  return nil
end

-- One step of the tree with the plan the planner made for it: the two always travel
-- together, with the steps that make its ingredients planned in the same way.
---@class bpgen.PlannedStage
---@field stage bpgen.StageData
---@field plan bpgen.Plan
---@field suppliers bpgen.PlannedStage[]  in the order of `stage.suppliers`
---@field demand? bpgen.Demand[]  what the step takes itself of raw items, fuel and fluids a minute, once `raw_amounts` has run

---@class bpgen.Demand  how much of one raw item, one fuel or one fluid a step takes a minute
---@field name string
---@field amount number
---@field is_fuel? boolean
---@field is_fluid? boolean  a fluid, which no belt brings in: the pipes do

-- What the steps of a blueprint take in all, by the order each is listed in: the raw items first, then the fuel, then the fluids.
---@class bpgen.DemandTotals
---@field order string[]  the raw items, from the first step
---@field fuel_order string[]
---@field fluid_order string[]
---@field amount table<string, number>

-- The machines of every step, from the first to the last, for the blueprint's description.
---@param planned bpgen.PlannedStage
---@return bpgen.StageSummary[]
local function stage_summaries(planned)
  local summaries = {}
  for _, planned_stage in ipairs(in_order(planned, {})) do
    summaries[#summaries + 1] = {machines = planned_stage.plan.machines, machine = planned_stage.stage.machine}
  end
  return summaries
end

-- What one step takes itself a minute when it makes `crafts` crafts a minute: the ingredients
-- no step makes, which are raw, then, in a machine that burns fuel, the fuel the machines burn
-- while crafting, then the fluids the recipe takes.
---@param planned bpgen.PlannedStage
---@param crafts number
---@param made_by table<string, bpgen.PlannedStage>  the steps below it, by the item they make
---@return bpgen.Demand[]
local function own_demand(planned, crafts, made_by)
  local stage, demand = planned.stage, {}
  for _, ingredient in ipairs(stage.recipe.ingredients) do
    if not made_by[ingredient.name] then
      demand[#demand + 1] = {name = ingredient.name, amount = crafts * ingredient.amount}
    end
  end
  if stage.fuel and stage.fuel_use then
    local machines_working = crafts * stage.recipe.energy / (60 * stage.machine_speed)
    demand[#demand + 1] = {name = stage.fuel, amount = machines_working * stage.fuel_use, is_fuel = true}
  end
  for _, fluid in ipairs(stage.recipe.fluids) do
    demand[#demand + 1] = {name = fluid.name, amount = crafts * fluid.amount, is_fluid = true}
  end
  return demand
end

-- The list of the totals that an entry is noted in.
---@param totals bpgen.DemandTotals
---@param entry bpgen.Demand
---@return string[]
local function order_of(totals, entry)
  if entry.is_fuel then
    return totals.fuel_order
  end
  return entry.is_fluid and totals.fluid_order or totals.order
end

-- Adds what a step takes to the totals, noting an item the first time it is seen.
---@param totals bpgen.DemandTotals
---@param entry bpgen.Demand
local function add_to_totals(totals, entry)
  if not totals.amount[entry.name] then
    totals.amount[entry.name] = 0
    local order = order_of(totals, entry)
    order[#order + 1] = entry.name
  end
  totals.amount[entry.name] = totals.amount[entry.name] + entry.amount
end

-- The raw items (and the fuel) the blueprint uses, a minute at the rate it really makes: the
-- step is asked to make `makes` items a minute, so it needs so many crafts, so many of each
-- ingredient (the steps that make an ingredient are asked for that much in turn; an
-- ingredient no step makes is raw) and, in a machine that burns fuel, the fuel the machines
-- burn while crafting (see `own_demand`). `totals.order` lists the raw items in the order the
-- steps need them, from the first step; `totals.fuel_order` the fuels, which go after them, and `totals.fluid_order` the fluids.
---@param planned bpgen.PlannedStage  gets its `demand`
---@param makes number  how many of the step's item it is asked for
---@param totals bpgen.DemandTotals
local function add_demand(planned, makes, totals)
  local crafts = makes / planner.amount_made(planned.stage.recipe, planned.stage.item)
  local made_by = {}
  for _, supplier in ipairs(planned.suppliers) do
    made_by[supplier.stage.item] = supplier
  end
  for _, ingredient in ipairs(planned.stage.recipe.ingredients) do
    if made_by[ingredient.name] then
      add_demand(made_by[ingredient.name], crafts * ingredient.amount, totals)
    end
  end
  planned.demand = own_demand(planned, crafts, made_by)
  for _, entry in ipairs(planned.demand) do
    add_to_totals(totals, entry)
  end
end

-- How much of each raw item, then of each fuel, then of each fluid, the blueprint uses a minute when its
-- machines make what they really make (which can be more than was asked).
---@param planned bpgen.PlannedStage
---@return bpgen.RawAmount[]
local function raw_amounts(planned)
  local totals = {order = {}, fuel_order = {}, fluid_order = {}, amount = {}}
  add_demand(planned, planned.plan.output_per_minute, totals)
  local raws = {}
  for _, names in ipairs({totals.order, totals.fuel_order, totals.fluid_order}) do
    for _, name in ipairs(names) do
      raws[#raws + 1] = {name = name, amount = totals.amount[name]}
    end
  end
  return raws
end

-- The machine's size in tiles. `machine_problem` has already refused a machine
-- that has none, so it is there by the time anything asks.
---@param stage bpgen.StageData
---@return integer
local function machine_size_of(stage)
  return stage.machine_size --[[@as integer]]
end

-- Whether the planner may build a step wide (see `bpgen.StageRequest.wide`): the blueprint is of the design with one belt of
-- each material (which has the underground belts the woven input belts need), the step burns fuel and has no raw item next
-- to a made one, and the pole of the blueprint reaches the inserters of the input side of its machine from the output side.
-- The planner decides the rest: a step fed raw items, or by one that it builds wide (steel plate from iron plate).
---@param job bpgen.Job
---@param stage bpgen.StageData
---@param machine_size integer
---@return boolean
local function may_be_wide(job, stage, machine_size)
  return job.input_options ~= nil and stage.raw_item == nil
    and stage.fuel ~= nil and layout.pole_reach(job.names.pole_supply_distance) > machine_size
end

-- How many inserters the input side of a step's machines gets, with one belt and with woven ones, and how many belts the step
-- takes from, at most. The pipe of a machine that takes a fluid leaves the top and the bottom row of its input side: from one belt,
-- or one inserter on each of two woven belts (none without the weave).
---@param job bpgen.Job
---@param stage bpgen.StageData
---@param machine_size integer
---@return integer max_input
---@return integer|nil max_woven_input
---@return integer most_belts
local function input_slots(job, stage, machine_size)
  local weaves = can_weave(job)
  if #stage.recipe.fluids > 0 then
    local slots = assert(layout.max_fluid_inserters(machine_size), "generator: no room for inserters beside the pipe of a machine of size " .. machine_size)
    return slots, weaves and slots or nil, weaves and FLUID_BELTS or 1
  end
  return layout.max_input_inserters(machine_size), weaves and layout.max_woven_inserters(machine_size) or nil, most_input_belts(job)
end

-- How many items a minute one inserter moves, with the belts of the blueprint (see `planner.inserter_items_per_minute`).
---@param job bpgen.Job
---@param inserter bpgen.InserterData
---@return number
local function items_per_minute(job, inserter)
  return planner.inserter_items_per_minute(inserter.rotation_speed, inserter.stack_size, job.belt_speed)
end

-- What the planner is told about one step: the inserters that feed and empty each
-- of its machines, as many as the layout leaves room for.
---@param job bpgen.Job
---@param stage bpgen.StageData
---@return bpgen.StageRequest
local function stage_request(job, stage)
  local machine_size = machine_size_of(stage)
  local max_input, max_woven_input, belts = input_slots(job, stage, machine_size)
  return {
    product = stage.item,
    recipe = stage.recipe,
    machine_speed = stage.machine_speed,
    fuel = stage.fuel,
    inserters = {
      items_per_minute = items_per_minute(job, job.inserter),
      long_items_per_minute = items_per_minute(job, job.long_inserter),
      fast_items_per_minute = job.fast_inserter and items_per_minute(job, job.fast_inserter) or nil,
      max_input = max_input,
      max_woven_input = max_woven_input,
      most_belts = belts,
      max_output = layout.max_output_inserters(machine_size),
      machine_size = machine_size,
    },
    wide = may_be_wide(job, stage, machine_size),
  }
end

-- A step as the planner wants it, with the steps that make its ingredients.
---@param job bpgen.Job
---@param stage bpgen.StageData
---@return bpgen.StageTree
local function stage_tree(job, stage)
  local suppliers = {}
  for index, supplier in ipairs(stage.suppliers) do
    suppliers[index] = stage_tree(job, supplier)
  end
  return {stage = stage_request(job, stage), suppliers = suppliers}
end

-- What the planner is asked for this job: the belt lane, and the inserters of each step.
---@param job bpgen.Job
---@return bpgen.TreeRequest
local function tree_request(job)
  return {
    rate_per_minute = job.rate_per_minute,
    lane_items_per_minute = planner.lane_items_per_minute(job.belt_speed),
    root = stage_tree(job, job.root),
  }
end

-- Each step of the tree with its plan.
---@param stage bpgen.StageData
---@param plans bpgen.PlanTree  the plans in the shape of `stage`'s tree
---@return bpgen.PlannedStage
local function planned_tree(stage, plans)
  local suppliers = {}
  for index, supplier in ipairs(stage.suppliers) do
    suppliers[index] = planned_tree(supplier, plans.suppliers[index])
  end
  return {stage = stage, plan = plans.plan, suppliers = suppliers}
end

-- Ask the planner, with the limits the game data gives: the belt lane, and the
-- inserters of each step. Returns each step with its plan, or nil and the message
-- for the player.
---@param job bpgen.Job
---@return bpgen.PlannedStage|nil
---@return LocalisedString|nil error_message
local function make_plans(job)
  local plans, reason, max_rate = planner.plan_tree(tree_request(job))
  if not plans then
    ---@cast reason bpgen.PlanReason -- the planner always gives a reason when it gives no plans
    return nil, messages.plan_problem(reason, max_rate)
  end
  return planned_tree(job.root, plans), nil
end

-- The recipe to set on the machines of a step: an assembling machine is blank until it is
-- told, a furnace picks its recipe from what it is given and has no recipe to set.
---@param stage bpgen.StageData
---@return string|nil
local function recipe_to_set(stage)
  if stage.machine_type == "furnace" then
    return nil
  end
  return stage.recipe.name
end

-- What a step takes from the belts that come in, for the design that brings in one belt of each
-- material: its raw ingredients, then the fuel. A step with made ingredients takes either one raw
-- item and no fuel (the feed of its raw column), or only fuel (`fuel_problem` allows nothing else). A fluid does not
-- come in on a belt: the pipes bring it.
---@param planned bpgen.PlannedStage  with its `demand`
---@return bpgen.Feed
local function feed_of(planned)
  local items = {}
  for _, entry in ipairs(planned.demand) do
    if not entry.is_fluid then
      items[#items + 1] = {name = entry.name, amount = entry.amount}
    end
  end
  return {items = items}
end

-- What a step built wide takes from its two input belts: of its ingredient, as much as one lane carries on the first belt
-- (the fuel on the other lane) and the rest on both lanes of the second.
---@param planned bpgen.PlannedStage  with its `demand`
---@param lane number  what one lane of a belt carries a minute
---@return bpgen.Feed first
---@return bpgen.Feed second
local function wide_feeds(planned, lane)
  local first, second = {}, {}
  for _, entry in ipairs(planned.demand) do
    local on_first = entry.is_fuel and entry.amount or math.min(entry.amount, lane)
    first[#first + 1] = {name = entry.name, amount = on_first}
    if not entry.is_fuel then
      second[#second + 1] = {name = entry.name, amount = entry.amount - on_first}
    end
  end
  return {items = first}, {items = second}
end

-- What a step takes from the belts that come in, by where it rides: a step that eats only raw items takes it on the
-- belt of raw items that ends in it (the first result; for a step built wide, on two belts: the second result is what
-- the second one carries), a step that eats what another step makes and burns fuel takes the fuel on the free lane of
-- the belt between them (the third).
---@param planned bpgen.PlannedStage  with its `demand`
---@param lane number  what one lane of a belt carries a minute
---@return bpgen.Feed|nil feed
---@return bpgen.Feed|nil second_feed
---@return bpgen.Feed|nil fuel_feed
local function feeds_of(planned, lane)
  if #planned.suppliers > 0 then
    return nil, nil, planned.stage.fuel and feed_of(planned) or nil
  end
  if planned.plan.wide then
    local feed, second_feed = wide_feeds(planned, lane)
    return feed, second_feed, nil
  end
  return feed_of(planned), nil, nil
end

-- The size of a step's machines and how many inserters each has, as the layout wants it: a step built wide has its second
-- input belt, its poles beside the output side and its output belt winding for machines in twos. A step built wide that is
-- fed by another one (steel plate from iron plate) has a belt of fuel of its own, woven with the belt before it, instead.
-- The poles of a column stand beside the output side alone when one there reaches the input inserters (a medium pole
-- does for a 2 x 2 machine: they are 3 tiles away) and so also powers the machine and the output inserters, which
-- takes half the poles; a column built wide needs it, as its input side is full (it is only built wide when the pole
-- reaches, see `may_be_wide`). A column that takes a fluid keeps poles of its own beside its pipes, whatever the pole reaches.
---@param planned bpgen.PlannedStage
---@param pole_reach integer  how many tiles away from its own a pole of the blueprint powers (`layout.pole_reach`)
---@return bpgen.Shape
local function shape_of(planned, pole_reach)
  local wide = planned.plan.wide
  local fuel_belt = wide and #planned.suppliers > 0
  local machine_size = machine_size_of(planned.stage)
  local fluid = #planned.stage.recipe.fluids > 0
  return {
    machine_size = machine_size,
    input_inserters = planned.plan.input_inserters,
    input_fast = planned.plan.input_fast,
    long_inserters = planned.plan.long_inserters,
    input_belts = planned.plan.belt_inserters,
    output_inserters = planned.plan.output_inserters,
    output_fast = planned.plan.output_fast,
    output_paired = wide,
    powered_from_output = pole_reach > machine_size and not fluid,
    second_input_belt = wide and not fuel_belt,
    fuel_belt = fuel_belt,
    fluid_input = fluid or nil,
  }
end

-- What the layout is told about a step and what it eats: the steps that make its
-- ingredients, each saying which belt of this step it rides, then the raw item that goes
-- with them, if any, which has no machines and only a belt (on belt a). A step that eats only
-- raw items also says what it takes of them (`feed`), which `rows.build_pure` uses.
---@param planned bpgen.PlannedStage  with its `demand`
---@param lane number  what one lane of a belt carries a minute
---@param pole_reach integer  how many tiles away from its own a pole of the blueprint powers (`layout.pole_reach`)
---@return bpgen.StageLayout
local function layout_stage(planned, lane, pole_reach)
  local suppliers = {}
  for index, supplier in ipairs(planned.suppliers) do
    suppliers[index] = layout_stage(supplier, lane, pole_reach)
    suppliers[index].belt = planner.belt_of(planned.plan.belts, supplier.stage.item)
  end
  local raw_item = planned.stage.raw_item
  if raw_item then
    suppliers[#suppliers + 1] = {raw_item = raw_item, feed = feed_of(planned)}
  end
  local feed, second_feed, fuel_feed = feeds_of(planned, lane)
  return {
    machine_count = planned.plan.machines,
    load = planned.plan.load,
    machine = planned.stage.machine,
    recipe = recipe_to_set(planned.stage),
    shape = shape_of(planned, pole_reach),
    suppliers = suppliers,
    feed = feed,
    second_feed = second_feed,
    fuel_feed = fuel_feed,
  }
end

-- The entities of the blueprint, and the names of the items of the belts the player brings in from
-- the top down (nothing for the original design: there the player brings a belt for each chain, and
-- the message names the raw items).
---@param job bpgen.Job
---@param planned bpgen.PlannedStage  with its `demand`
---@return bpgen.Entity[] entities
---@return string[]|nil belts
---@return bpgen.StageLayout root  what the blueprint was laid out from
---@return bpgen.Supply[] supplies  the belts the player brings in (none for the original design)
local function build_entities(job, planned)
  local root = layout_stage(planned, planner.lane_items_per_minute(job.belt_speed), layout.pole_reach(job.names.pole_supply_distance))
  if not job.input_options then
    return (rows.build(root, job.names)), nil, root, {}
  end
  local entities, supplies = rows.build_pure(root, job.names, job.input_options)
  local belts = {}
  for index, supply in ipairs(supplies) do
    belts[index] = supply.item
  end
  return entities, belts, root, supplies
end

-- The tiles on a side of the machine of each column of the layout, by machine name: the names the entities carry.
---@param stage bpgen.StageLayout
---@param sizes table<string, integer>
---@return table<string, integer>
local function machine_sizes_of(stage, sizes)
  sizes[stage.machine] = stage.shape.machine_size
  for _, supplier in ipairs(stage.suppliers or {}) do
    if supplier.machine then -- a raw item has no machines
      machine_sizes_of(supplier, sizes)
    end
  end
  return sizes
end

-- Puts the display panels on the blueprint when the job asks for them (see scripts/labels.lua).
---@param job bpgen.Job
---@param entities bpgen.Entity[]
---@param root bpgen.StageLayout  what the blueprint was laid out from
---@param supplies bpgen.Supply[]  the belts the player brings in
local function add_labels(job, entities, root, supplies)
  if not job.labels then
    return
  end
  local sizes = machine_sizes_of(root, {})
  labels.add(entities, supplies, {
    panel = job.names.panel,
    belts = {job.names.belt, job.names.underground},
    inlets = {job.names.pump},
    size_of = function(entity) return inputs.footprint(entity, job.names, sizes) end,
  })
end

-- Puts the lamps on the blueprint when the job asks for them (see scripts/lights.lua).
---@param job bpgen.Job
---@param entities bpgen.Entity[]
---@param root bpgen.StageLayout  what the blueprint was laid out from
local function add_lights(job, entities, root)
  if not job.lamp_supply_distance then
    return
  end
  local sizes = machine_sizes_of(root, {})
  lights.add(entities, {
    lamp = job.names.lamp, pole = job.names.pole, supply_distance = job.lamp_supply_distance,
    belts = {job.names.belt, job.names.underground},
    inlets = {job.names.pump}, -- the tile behind the pump is where the water comes in
    size_of = function(entity) return inputs.footprint(entity, job.names, sizes) end,
  })
end

-- Lay out the planned machines and word the results for the player.
---@param job bpgen.Job
---@param planned bpgen.PlannedStage
---@return bpgen.Generated
local function assemble(job, planned)
  local raws = raw_amounts(planned) -- also notes what each step takes, which the layout needs
  local entities, belts, root, supplies = build_entities(job, planned)
  add_labels(job, entities, root, supplies)
  add_lights(job, entities, root)
  return {
    entities = entities,
    description = messages.description(job.item_name, planned.plan.output_per_minute, stage_summaries(planned)),
    message = messages.ready(planned.plan.output_per_minute, planned.stage.item, raws, belts),
  }
end

-- How many machines of `stage` stand one under the other in the length a run of pipes may have.
---@param stage bpgen.StageData
---@return integer
local function machines_that_fit(stage)
  return math.floor(config.fluid_pipeline_tiles / stage.machine_size)
end

-- What the planner is asked for a row of machines that make a fluid.
---@param job bpgen.Job
---@return bpgen.FluidRowRequest
local function fluid_row_request(job)
  local stage = job.root
  return {
    product = stage.item, recipe = stage.recipe, machine_speed = stage.machine_speed,
    rate_per_minute = job.rate_per_minute, machines_that_fit = machines_that_fit(stage),
  }
end

-- What `fluid_row.build` is asked for `count` machines of the step: `fluid_row_problem` has already checked the machine.
---@param job bpgen.Job
---@param stage bpgen.StageData  the step that makes the fluid
---@param count integer
---@return bpgen.FluidRowBuild
local function fluid_row_build(job, stage, count)
  local size = machine_size_of(stage)
  local boxes = read_fluid_boxes(prototypes.entity[stage.machine], size)
  return {
    machine = stage.machine, recipe = stage.recipe.name, size = size, count = count, boxes = boxes,
    rows = assert(fluid_row.rows_of(boxes, size), "generator: the pipe connections of the machine are not in rows"),
    pipe = job.names.pipe, pole = job.names.pole,
    pole_supply_distance = job.names.pole_supply_distance, pole_wire_distance = job.names.pole_wire_distance,
  }
end

-- The sizes of the machines of a row, or of the plants and the machines that make their fluid, by name.
---@param job bpgen.Job
---@return table<string, integer>
local function row_sizes(job)
  local sizes = {[job.root.machine] = machine_size_of(job.root)}
  if job.maker then
    sizes[job.maker.machine] = machine_size_of(job.maker)
  end
  return sizes
end

-- Puts the lamps on a row of machines, or on plants with the machines that make their fluid, or on a chain of blocks, when the job asks for
-- them (see scripts/lights.lua). The tile a belt runs on to stays free, and so does the tile west of each entry of a pipe or a belt, where the
-- player joins it.
---@param job bpgen.Job
---@param entities bpgen.Entity[]
---@param inlets {key: string, x: integer, y: integer}[]  the entries of what comes in
---@param sizes? table<string, integer>  the tiles on a side of each machine, by name: those of the row or the plants by default
local function add_row_lights(job, entities, inlets, sizes)
  if not job.lamp_supply_distance then
    return
  end
  sizes = sizes or row_sizes(job)
  local free = {}
  for _, inlet in ipairs(inlets) do
    free[#free + 1] = {x = inlet.x - 1, y = inlet.y}
  end
  lights.add(entities, {
    lamp = job.names.lamp, pole = job.names.pole, supply_distance = job.lamp_supply_distance, belts = {job.names.belt, job.names.underground},
    free_tiles = free, size_of = function(entity) return inputs.footprint(entity, job.names, sizes) end,
  })
end

-- Puts a display panel beside each entry of a pipe or a belt that comes in at the top left corner, showing the fluid or the item, once
-- the force has unlocked the display panel (see scripts/labels.lua). An entry that `things` has nothing for goes without.
---@param job bpgen.Job
---@param entities bpgen.Entity[]
---@param inlets {key: string, x: integer, y: integer}[]  the entries; the one with the key "items" is a belt, the others are pipes
---@param things table<string, {name: string, type: "item"|"fluid"}>  what each entry brings, by its key
---@param sizes? table<string, integer>  the tiles on a side of each machine, by name: those of the row or the plants by default
local function add_inlet_labels(job, entities, inlets, things, sizes)
  if not job.row_labels then
    return
  end
  sizes = sizes or row_sizes(job)
  local supplies = {}
  for _, inlet in ipairs(inlets) do
    local thing = things[inlet.key]
    if thing then
      supplies[#supplies + 1] = {x = inlet.x, y = inlet.y, item = thing.name, type = thing.type}
    end
  end
  labels.add(entities, supplies, {
    panel = job.names.panel, belts = {job.names.belt, job.names.underground},
    size_of = function(entity) return inputs.footprint(entity, job.names, sizes) end,
  })
end

-- A row of machines for the fluid asked for, and the words for the player: what the row makes and takes a minute.
---@param job bpgen.Job
---@return bpgen.Generated|nil
---@return LocalisedString|nil error_message
local function generate_fluid_row(job)
  local stage = job.root
  local plan, reason, max_rate = planner.plan_fluid_row(fluid_row_request(job))
  if not plan then
    ---@cast reason bpgen.PlanReason -- the planner always gives a reason when it gives no plan
    return nil, messages.plan_problem(reason, max_rate)
  end
  local entities, entries = fluid_row.build(fluid_row_build(job, stage, plan.machines))
  fluid_row.turn(entities, entries, stage.machine, machine_size_of(stage))
  local inlets = corner_entries.add(entities, {{key = "input", x = entries.input.x, y = entries.input.y, name = job.names.pipe}})
  add_inlet_labels(job, entities, inlets, {input = {name = stage.recipe.fluids[1].name, type = "fluid"}})
  add_row_lights(job, entities, inlets)
  local crafts = plan.output_per_minute / planner.amount_made(stage.recipe, stage.item)
  local taken = {name = stage.recipe.fluids[1].name, amount = crafts * stage.recipe.fluids[1].amount}
  return {
    entities = entities,
    description = messages.description(job.item_name, plan.output_per_minute, {{machines = plan.machines, machine = stage.machine}}),
    message = messages.ready(plan.output_per_minute, stage.item, {taken}, nil),
  }
end

-- What the planner is asked for plants that make an item from a fluid, and the machines that make the fluid.
---@param job bpgen.Job
---@return bpgen.FluidPlantRequest
local function fluid_plant_request(job)
  local stage, maker = job.root, job.maker
  local with_item = #stage.recipe.ingredients == 1
  local plain = job.inserter
  local lane = planner.lane_items_per_minute(job.belt_speed)
  return {
    product = stage.item, recipe = stage.recipe, machine_speed = stage.machine_speed,
    maker_recipe = maker.recipe, maker_speed = maker.machine_speed, rate_per_minute = job.rate_per_minute,
    makers_that_fit = machines_that_fit(maker), plants_that_fit = machines_that_fit(stage),
    lane_items_per_minute = lane,
    inserter_items_per_minute = planner.inserter_items_per_minute(plain.rotation_speed, plain.stack_size, job.belt_speed),
    input_inserter_items_per_minute = with_item and planner.inserter_items_per_minute(plain.rotation_speed, plain.stack_size, job.belt_speed) or nil,
    item_belt_items_per_minute = with_item and 2 * lane or nil,
  }
end

-- What `fluid_plant.build` is asked for: `fluid_plant_problem` has already checked the machines.
---@param job bpgen.Job
---@param plan bpgen.FluidPlantPlan
---@return bpgen.FluidPlantBuild
local function fluid_plant_build(job, plan)
  local stage = job.root
  local size = machine_size_of(stage)
  local boxes = read_fluid_boxes(prototypes.entity[stage.machine], size)
  return {
    makers = fluid_row_build(job, job.maker, plan.makers),
    plants = {
      machine = stage.machine, recipe = stage.recipe.name, size = size, count = plan.plants, boxes = boxes,
      rows = assert(fluid_row.rows_of(boxes, size), "generator: the pipe connections of the machine are not in rows"),
      fluid_boxes = #stage.recipe.fluids == 2 and plant_fluid_boxes(stage.recipe, job.made_fluid --[[@as string]]) or nil,
    },
    inserter = job.names.inserter, belt = job.names.belt,
    item_input = #stage.recipe.ingredients == 1 or nil,
    pipe_to_ground = job.names.pipe_to_ground, underground_reach = config.pipe_to_ground_reach,
  }
end

-- What the blueprint takes a minute of what comes in: the fluid the machines of the row take, then the fluid that comes in beside the
-- plants and the item, when they take them.
---@param job bpgen.Job
---@param plan bpgen.FluidPlantPlan
---@return bpgen.RawAmount[]
local function plant_raws(job, plan)
  local taken = {{name = job.maker.recipe.fluids[1].name, amount = plan.source_per_minute}}
  for _, list in ipairs({plan.supplied, plan.items}) do
    for _, brought in ipairs(list) do
      taken[#taken + 1] = brought
    end
  end
  return taken
end

-- Plants for the item asked for, with the machines that make the fluid they take, and the words for the player: what the blueprint
-- makes and the fluid it takes in a minute.
---@param job bpgen.Job
---@return bpgen.Generated|nil
---@return LocalisedString|nil error_message
local function generate_fluid_plant(job)
  local plan, reason, max_rate = planner.plan_fluid_plant(fluid_plant_request(job))
  if not plan then
    ---@cast reason bpgen.PlanReason -- the planner always gives a reason when it gives no plan
    return nil, messages.plan_problem(reason, max_rate)
  end
  local entities, entries = fluid_plant.build(fluid_plant_build(job, plan))
  local supplied, item = plan.supplied[1], plan.items[1]
  add_inlet_labels(job, entities, entries.inlets, {
    input = {name = job.maker.recipe.fluids[1].name, type = "fluid"}, supplied = supplied and {name = supplied.name, type = "fluid"},
    items = item and {name = item.name, type = "item"},
  })
  add_row_lights(job, entities, entries.inlets)
  local taken = plant_raws(job, plan)
  local summaries = {{machines = plan.makers, machine = job.maker.machine}, {machines = plan.plants, machine = job.root.machine}}
  return {
    entities = entities,
    description = messages.description(job.item_name, plan.output_per_minute, summaries),
    message = messages.ready(plan.output_per_minute, job.root.item, taken, item and {item.name} or nil),
  }
end

-- What the planner is asked for the final plants of a chain, the ones that make the fluid: as many as `fit`, at most.
---@param job bpgen.Job
---@param fit integer
---@return bpgen.ItemFluidPlantsRequest
local function item_fluid_request(job, fit)
  local stage, inserter = job.root, job.inserter
  return {
    product = stage.item, recipe = stage.recipe, machine_speed = stage.machine_speed, rate_per_minute = job.rate_per_minute,
    inserter_rotation_speed = inserter.rotation_speed, inserter_stack_size = inserter.stack_size, belt_speed = job.belt_speed,
    plants_that_fit = fit, lane_items_per_minute = planner.lane_items_per_minute(job.belt_speed),
  }
end

-- How much of an item the plants of a plan take a minute.
---@param plan bpgen.ItemFluidPlantsPlan
---@param name string
---@return number
local function item_amount(plan, name)
  for _, item in ipairs(plan.items) do
    if item.name == name then
      return item.amount
    end
  end
  error("generator: the plants of the fluid take no " .. name)
end

-- The jobs of the two parts that make the items of a chain: the plants (with the machines that make their fluid) and the steps on belts,
-- each asked for the rate it is given.
---@param job bpgen.Job
---@param plants_rate number
---@param belts_rate number
---@return bpgen.Job plants_job
---@return bpgen.Job|nil belts_job  nil when the other item is raw
local function parts_jobs(job, plants_rate, belts_rate)
  local parts = job.parts --[[@as bpgen.ChainParts]]
  local plants_job = part_of(job, {root = parts.plants, kind = "fluid_plant", item_name = parts.plants.item, rate_per_minute = plants_rate})
  if not parts.belts then
    return plants_job, nil
  end
  return plants_job, part_of(job, {root = parts.belts, kind = "belts", item_name = parts.belts.item, rate_per_minute = belts_rate})
end

-- The item of the part that is not made in plants: what the steps on belts make, or the raw item that comes in.
---@param parts bpgen.ChainParts
---@return string
local function belts_item_of(parts)
  return parts.belts and parts.belts.item or assert(parts.raw_item, "generator: a chain has no second item")
end

-- What the part of the second item can make a minute at most: what the steps on belts make, or one lane of the belt the raw item comes in
-- on (it is side-loaded onto one lane). Nil when the steps are ones the planner cannot handle.
---@param job bpgen.Job
---@param belts_job bpgen.Job|nil
---@return number|nil
local function most_second_item(job, belts_job)
  if belts_job then
    return planner.max_tree_rate(tree_request(belts_job))
  end
  return planner.lane_items_per_minute(job.belt_speed)
end

-- How many plants that make the fluid the parts of a chain can feed with their items, at most, and what one of them makes a minute: as many as
-- the plants that make the first item can make it for, as the steps on belts make the second, and as stand in the length a run of pipes
-- may have. Nil and the reason when a part has a recipe the planner cannot handle.
---@param job bpgen.Job
---@return {plants: integer, per_plant: number}|nil
---@return bpgen.PlanReason|nil reason
local function most_item_fluid_plants(job)
  local request = item_fluid_request(job, 1)
  request.rate_per_minute = 0
  local one, reason = planner.plan_item_fluid_plants(request)
  if not one then
    return nil, reason
  end
  local plants_job, belts_job = parts_jobs(job, 1, 1)
  local made_in_plants, made_on_belts = planner.max_fluid_plant_rate(fluid_plant_request(plants_job)), most_second_item(job, belts_job)
  if not (made_in_plants and made_on_belts) then
    return nil, "unsupported-recipe"
  end
  local parts = job.parts --[[@as bpgen.ChainParts]]
  local by_plants = math.floor(made_in_plants / item_amount(one, parts.plants.item) + constants.EPSILON)
  local by_belts = math.floor(made_on_belts / item_amount(one, belts_item_of(parts)) + constants.EPSILON)
  return {plants = math.max(1, math.min(machines_that_fit(job.root), by_plants, by_belts)), per_plant = one.per_plant}, nil
end

---@class bpgen.ItemFluidChainPlans
---@field final bpgen.ItemFluidPlantsPlan  the final plants, which make the fluid
---@field plants bpgen.FluidPlantPlan  the plants that make the item made in plants, with the machines that make their fluid
---@field plants_job bpgen.Job
---@field belts? bpgen.PlannedStage  the steps that make the item made on belts; nil when that item is raw
---@field belts_job? bpgen.Job

-- The plans of the parts of a chain for the rate asked for, or nil, the reason and the most a chain can make.
---@param job bpgen.Job
---@return bpgen.ItemFluidChainPlans|nil
---@return bpgen.PlanReason|nil reason
---@return number|nil max_rate  given with "rate-too-high"
local function plan_item_fluid_chain(job)
  local limit, reason = most_item_fluid_plants(job)
  if not limit then
    return nil, reason
  end
  local final, why, max_rate = planner.plan_item_fluid_plants(item_fluid_request(job, limit.plants))
  if not final then
    return nil, why, max_rate
  end
  local parts = job.parts --[[@as bpgen.ChainParts]]
  local plants_job, belts_job = parts_jobs(job, item_amount(final, parts.plants.item), item_amount(final, belts_item_of(parts)))
  local plants, belts = planner.plan_fluid_plant(fluid_plant_request(plants_job)), belts_job and make_plans(belts_job)
  assert(plants and (belts or not belts_job), "generator: the parts of a chain cannot make what the plants of the fluid take, though the most they make said they can")
  return {final = final, plants = plants, plants_job = plants_job, belts = belts, belts_job = belts_job}
end

-- The most a chain makes a minute (see `most_item_fluid_plants`), or nil and why not.
---@param job bpgen.Job
---@return number|nil max_rate
---@return bpgen.PlanReason|nil reason
local function item_fluid_chain_max_rate(job)
  local limit, reason = most_item_fluid_plants(job)
  if not limit then
    return nil, reason
  end
  return planner.max_item_fluid_plants_rate(item_fluid_request(job, limit.plants)), nil
end

-- What `item_fluid_plants.build` is asked for the plans' plants of the fluid.
---@param job bpgen.Job
---@param plan bpgen.ItemFluidPlantsPlan
---@return bpgen.ItemFluidPlantsBuild
local function item_fluid_plants_request(job, plan)
  local names = job.names
  return {
    plants = plants_of(job.root, plan.plants), inserter = names.inserter, belt = names.belt, pipe = names.pipe, pipe_to_ground = names.pipe_to_ground,
    pole = names.pole, pole_supply_distance = names.pole_supply_distance, pole_wire_distance = names.pole_wire_distance,
    underground_reach = config.pipe_to_ground_reach,
  }
end

-- The tiles of the belts of the entities, as a set of `grid.key`s, and the tiles of those that run south, as a list.
---@param entities bpgen.Entity[]
---@param belt string  the prototype name of the belt
---@return table<string, true> all
---@return {x: number, y: number}[] runs_south
local function belt_tiles(entities, belt)
  local all, runs_south = {}, {}
  for _, entity in ipairs(entities) do
    if entity.name == belt then
      local tile = grid.top_left_tile(entity.position)
      all[grid.key(tile.x, tile.y)] = true
      if entity.direction == south then
        runs_south[#runs_south + 1] = tile
      end
    end
  end
  return all, runs_south
end

-- The last tile of the belt of product of a block of the belts layout: the tile of a belt that runs south with no belt in front of it, furthest
-- east (the belts of raw items end further west) and, in that column, the lowest.
---@param entities bpgen.Entity[]
---@param belt string  the prototype name of the belt
---@return {column: integer, last_row: integer}
local function product_end(entities, belt)
  local all, runs_south = belt_tiles(entities, belt)
  local ends = {}
  for _, tile in ipairs(runs_south) do
    if not all[grid.key(tile.x, tile.y + 1)] then
      ends[#ends + 1] = tile
    end
  end
  table.sort(ends, function(first, second)
    if first.x ~= second.x then
      return first.x > second.x
    end
    return first.y > second.y
  end)
  local last = assert(ends[1], "generator: the block of furnaces has no belt of product")
  return {column = last.x, last_row = last.y}
end

-- The first tile of the belt of raw items of the original design, which comes in at the top of the block, running south: the tile of a
-- belt that runs south with no belt behind it, furthest west and, in that column, the highest.
---@param entities bpgen.Entity[]
---@param belt string  the prototype name of the belt
---@return {x: integer, y: integer}
local function raw_start(entities, belt)
  local all, runs_south = belt_tiles(entities, belt)
  local starts = {}
  for _, tile in ipairs(runs_south) do
    if not all[grid.key(tile.x, tile.y - 1)] then
      starts[#starts + 1] = tile
    end
  end
  table.sort(starts, function(first, second)
    if first.x ~= second.x then
      return first.x < second.x
    end
    return first.y < second.y
  end)
  return assert(starts[1], "generator: the block of furnaces has no belt of raw items")
end

-- The block of the steps that make the second item of a chain, made apart (see `bpgen.BeltsBlock`): its entities, its poles, the tile of the end
-- of its product belt and where its belts of raw items come in. Also gives the names of the items of the belts that come in, from the top down
-- (nothing for the original design) and the layout it was made from.
---@param job bpgen.Job  the job of the steps on belts
---@param planned bpgen.PlannedStage  with its `demand`
---@return bpgen.BeltsBlock
---@return bpgen.StageLayout root
---@return string[]|nil belts
local function belts_block(job, planned)
  local entities, belts, root, supplies = build_entities(job, planned)
  local poles, raw = {}, {}
  for _, entity in ipairs(entities) do
    if entity.name == job.names.pole then
      poles[#poles + 1] = entity
    end
  end
  for _, supply in ipairs(supplies) do
    raw[#raw + 1] = {key = supply.item, x = supply.x, y = supply.y, direction = east}
  end
  if #raw == 0 then
    local start = raw_start(entities, job.names.belt)
    raw[1] = {key = "belt", x = start.x, y = start.y, direction = south}
  end
  return {entities = entities, poles = poles, product = product_end(entities, job.names.belt), raw = raw}, root, belts
end

-- The block of the part of a chain whose second item is raw: no machines, only the belt that comes in at the top left, which is the belt of
-- its product too (a single tile, from which the chain takes it on). Also the name of the item of the belt, for the entry.
---@param item string
---@param belt string  the prototype name of the belt
---@return bpgen.BeltsBlock
local function raw_item_block(item, belt)
  local entities = {}
  entity_list.append(entities, {name = belt, position = grid.position(0, 0), direction = south})
  return {entities = entities, poles = {}, product = {column = 0, last_row = 0}, raw = {{key = item, x = 0, y = 0, direction = south}}}
end

-- The block of the part of a chain that makes the second item, with what it takes a minute (as `raw_amounts` gives it), the layout of its
-- steps (nil when the item is raw) and the names of the belts that come in (nil for the original design).
---@param job bpgen.Job
---@param plans bpgen.ItemFluidChainPlans
---@return bpgen.BeltsBlock block
---@return bpgen.StageLayout|nil belts_root
---@return string[]|nil belts
---@return bpgen.RawAmount[] belts_raws
local function second_item_block(job, plans)
  if plans.belts then
    local belts_raws = raw_amounts(plans.belts) -- also notes what each step takes, which the layout needs
    local block, belts_root, belts = belts_block(plans.belts_job, plans.belts)
    return block, belts_root, belts, belts_raws
  end
  local raw_item = belts_item_of(job.parts --[[@as bpgen.ChainParts]])
  return raw_item_block(raw_item, job.names.belt), nil, {raw_item}, {{name = raw_item, amount = item_amount(plans.final, raw_item)}}
end

-- The tiles on a side of each machine of a chain, by name.
---@param job bpgen.Job
---@param belts_root bpgen.StageLayout|nil  the layout of the steps on belts, nil when the second item is raw
---@return table<string, integer>
local function chain_sizes(job, belts_root)
  local parts = job.parts --[[@as bpgen.ChainParts]]
  local sizes = belts_root and machine_sizes_of(belts_root, {}) or {}
  for _, stage in ipairs({job.root, parts.plants, job.maker}) do
    sizes[stage.machine] = machine_size_of(stage)
  end
  return sizes
end

-- Whether the fluid that comes in beside the plants part of a chain (the water of the sulfur) is the fluid the final plants take (the water of
-- the acid): then one entry brings it to both (see `item_fluid_chain.build`).
---@param job bpgen.Job
---@param plans bpgen.ItemFluidChainPlans
---@return boolean
local function shares_fluid(job, plans)
  local supplied = plans.plants.supplied[1]
  return supplied ~= nil and supplied.name == job.root.recipe.fluids[1].name
end

-- What comes in at each entry of a chain, by its key (see `item_fluid_chain.build`): the crude oil, the water of the plants part (which is the
-- water of the final plants too, when they take the same fluid) and, for the design that brings in one belt of each material, the item of
-- each belt. The fluid the final plants take has an entry of its own, "final_fluid", when it is not the same.
---@param job bpgen.Job
---@param plans bpgen.ItemFluidChainPlans
---@param belts string[]|nil  the items of the belts that come in
---@return table<string, {name: string, type: "item"|"fluid"}>
local function chain_things(job, plans, belts)
  local supplied = plans.plants.supplied[1]
  local things = {
    input = {name = job.maker.recipe.fluids[1].name, type = "fluid"},
    supplied = supplied and {name = supplied.name, type = "fluid"},
    final_fluid = {name = job.root.recipe.fluids[1].name, type = "fluid"},
  }
  for _, item in ipairs(belts or {}) do
    things[item] = {name = item, type = "item"}
  end
  return things
end

-- What a chain takes in a minute, from the top of the blueprint down: what the steps on belts take (the raw items, then the fuel), the water
-- (of both plants, together, with any other fluid they take that comes in by a pipe) and the crude oil of the machines that make the fluid.
---@param job bpgen.Job
---@param plans bpgen.ItemFluidChainPlans
---@param belts_raws bpgen.RawAmount[]
---@return bpgen.RawAmount[]
local function chain_raws(job, plans, belts_raws)
  local raws, place = {}, {}
  local function add(name, amount)
    if place[name] then
      raws[place[name]].amount = raws[place[name]].amount + amount
    else
      raws[#raws + 1], place[name] = {name = name, amount = amount}, #raws + 1
    end
  end
  for _, list in ipairs({belts_raws, plans.final.fluids, plans.plants.supplied}) do
    for _, raw in ipairs(list) do
      add(raw.name, raw.amount)
    end
  end
  add(job.maker.recipe.fluids[1].name, plans.plants.source_per_minute)
  return raws
end

-- The machines of a chain by name, in the order of the steps: those that make the fluid of the first item, those of the first item, the
-- steps on belts and the plants of the fluid; a machine that two steps share (the chemical plant) once, with the sum.
---@param job bpgen.Job
---@param plans bpgen.ItemFluidChainPlans
---@return bpgen.StageSummary[]
local function chain_summaries(job, plans)
  local list = {{machines = plans.plants.makers, machine = job.maker.machine}, {machines = plans.plants.plants, machine = job.parts.plants.machine}}
  for _, summary in ipairs(plans.belts and stage_summaries(plans.belts) or {}) do
    list[#list + 1] = summary
  end
  list[#list + 1] = {machines = plans.final.plants, machine = job.root.machine}
  local order, counts = {}, {}
  for _, summary in ipairs(list) do
    counts[summary.machine] = counts[summary.machine] or (function() order[#order + 1] = summary.machine return 0 end)()
    counts[summary.machine] = counts[summary.machine] + summary.machines
  end
  local merged = {}
  for _, machine in ipairs(order) do
    merged[#merged + 1] = {machines = counts[machine], machine = machine}
  end
  return merged
end

-- The fluid asked for, made from two items and a fluid: the blueprint of the plants that make the first item (with the machines that make
-- the fluid they take), the steps that make the second on belts, and the plants of the fluid (see scripts/item_fluid_chain.lua), and the words
-- for the player.
---@param job bpgen.Job
---@return bpgen.Generated|nil
---@return LocalisedString|nil error_message
local function generate_item_fluid_chain(job)
  local plans, reason, max_rate = plan_item_fluid_chain(job)
  if not plans then
    ---@cast reason bpgen.PlanReason -- the planner always gives a reason when it gives no plan
    return nil, messages.plan_problem(reason, max_rate)
  end
  local block, belts_root, belts, belts_raws = second_item_block(job, plans)
  local sizes = chain_sizes(job, belts_root)
  local built = item_fluid_chain.build({
    plants_part = fluid_plant_build(plans.plants_job, plans.plants), belts_part = block, final_plants = item_fluid_plants_request(job, plans.final),
    shared_fluid = shares_fluid(job, plans), size_of = function(entity) return inputs.footprint(entity, job.names, sizes) end,
  })
  add_inlet_labels(job, built.entities, built.inlets, chain_things(job, plans, belts), sizes)
  add_row_lights(job, built.entities, built.inlets, sizes)
  return {
    entities = built.entities,
    description = messages.description(job.item_name, plans.final.output_per_minute, chain_summaries(job, plans)),
    message = messages.ready(plans.final.output_per_minute, job.root.item, chain_raws(job, plans, belts_raws), belts),
  }
end

-- The job for this request, with every machine checked, or nil and the message for the
-- player. With a `force`, a recipe the force has not unlocked is refused too.
---@param recipe_name string
---@param rate_per_minute number
---@param force LuaForce|nil
---@return bpgen.Job|nil
---@return LocalisedString|nil error_message
local function read_buildable_job(recipe_name, rate_per_minute, force)
  local job, problem = read_job(recipe_name, rate_per_minute, force)
  if not job then
    return nil, problem
  end
  local locked = force and locked_item(job, force)
  if locked then
    return nil, messages.locked(locked)
  end
  problem = machine_problem(job)
  if problem then
    return nil, problem
  end
  return job, nil
end

-- The most a blueprint of the job can make a minute, or nil and why not.
---@param job bpgen.Job
---@return number|nil max_rate
---@return bpgen.PlanReason|nil reason
local function max_rate_of(job)
  if job.kind == "fluid_row" then
    return planner.max_fluid_row_rate(fluid_row_request(job))
  end
  if job.kind == "fluid_plant" then
    return planner.max_fluid_plant_rate(fluid_plant_request(job))
  end
  if job.kind == "item_fluid_chain" then
    return item_fluid_chain_max_rate(job)
  end
  return planner.max_tree_rate(tree_request(job))
end

-- The line the window shows under the rate field: the most one blueprint of
-- `recipe_name` can make per minute, or the message for why it cannot be made.
---@param recipe_name string
---@param force LuaForce|nil  whose unlocked recipes count; nil counts them all
---@return LocalisedString
function generator.max_rate_message(recipe_name, force)
  local job, problem = read_buildable_job(recipe_name, 1, force) -- the rate is not used
  if not job then
    ---@cast problem LocalisedString -- there is always a message when there is no job
    return problem
  end
  local max_rate, reason = max_rate_of(job)
  if not max_rate then
    ---@cast reason bpgen.PlanReason
    return messages.plan_problem(reason)
  end
  return messages.max_rate(max_rate)
end

-- Make the blueprint for `rate_per_minute` of what the recipe `recipe_name` makes.
-- On success returns a table {entities, description, message}:
--   entities     the blueprint entities, ready for set_blueprint_entities
--   description  text for the blueprint's description field
--   message      a LocalisedString to show the player
-- On failure returns nil and a LocalisedString explaining why.
---@param recipe_name string
---@param rate_per_minute number  of the product of the recipe
---@param force LuaForce|nil  whose unlocked recipes count; nil counts them all
---@return bpgen.Generated|nil
---@return LocalisedString|nil error_message
function generator.generate(recipe_name, rate_per_minute, force)
  local job, problem = read_buildable_job(recipe_name, rate_per_minute, force)
  if not job then
    return nil, problem
  end
  if job.kind == "fluid_row" then
    return generate_fluid_row(job)
  end
  if job.kind == "fluid_plant" then
    return generate_fluid_plant(job)
  end
  if job.kind == "item_fluid_chain" then
    return generate_item_fluid_chain(job)
  end

  local planned, refusal = make_plans(job)
  if not planned then
    return nil, refusal
  end

  return assemble(job, planned)
end

return generator
