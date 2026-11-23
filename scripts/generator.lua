-- scripts/generator.lua
-- The one place that reads the game's prototype data (recipes, machines) and
-- connects it to the pure planner and layout modules. Only call it from event
-- handlers: `prototypes` does not exist while control.lua is first loading.

local config = require("scripts.config")
local constants = require("scripts.constants")
local chain = require("scripts.chain")
local planner = require("scripts.planner")
local poles = require("scripts.poles")
local layout = require("scripts.layout")
local input_side = require("scripts.input_side")
local inputs = require("scripts.inputs")
local rows = require("scripts.rows")
local entity_list = require("scripts.entity_list")
local output_side = require("scripts.output_side")
local fluid_row = require("scripts.fluid_row")
local fluid_plant = require("scripts.fluid_plant")
local item_fluid_chain = require("scripts.item_fluid_chain")
local item_fluid_plants = require("scripts.item_fluid_plants")
local plants_block = require("scripts.plants_block")
local accounting = require("scripts.accounting")
local belts_blocks = require("scripts.belts_blocks")
local fluid_boxes = require("scripts.fluid_boxes")
local grid = require("scripts.grid")
local corner_entries = require("scripts.corner_entries")
local finishing = require("scripts.finishing")
local messages = require("scripts.messages")
local recipes = require("scripts.recipes")

local generator = {}

local in_order = accounting.in_order

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

-- Whether a recipe that makes an item takes back something that is made from that item: the recipe that empties a filled barrel takes the filled
-- barrel, which the recipe that fills a barrel makes from the barrel the first gives back. Such a recipe makes the item from what is made from it (a loop),
-- so it is not what makes the item. When the item is the final product of the recipe the player picked, this is the final product being one of the
-- ingredients of a step of its own tree.
---@param prototype LuaRecipePrototype
---@param item_name string  an item the recipe makes
---@return boolean
local function takes_back(prototype, item_name)
  for _, ingredient in ipairs(prototype.ingredients) do
    if ingredient.type == "item" then
      local makers = prototypes.get_recipe_filtered({{filter = "has-product-item", elem_filters = {{filter = "name", name = ingredient.name}}}})
      for _, maker in pairs(makers) do
        for _, taken in ipairs(maker.ingredients) do
          if taken.type == "item" and taken.name == item_name then
            return true
          end
        end
      end
    end
  end
  return false
end

-- The recipes that make `item_name` in a machine the config names, leaving out those that take back what is made from it (see `takes_back`).
---@param item_name string
---@return bpgen.Candidate[]
local function candidate_recipes(item_name)
  local filters = {{filter = "has-product-item", elem_filters = {{filter = "name", name = item_name}}}}
  local found = {}
  for _, prototype in pairs(prototypes.get_recipe_filtered(filters)) do
    local choice = machine_choice(prototype)
    if choice and not takes_back(prototype, item_name) then
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
---@field fluid_supplier? {job: bpgen.Job, fluid: string, amount: number, max_output: number|nil}  of the root of a recipe on belts that takes a fluid that machines make (petroleum gas): the part that makes it (a row of refineries, a chain), the fluid, how much one craft of the step takes of it, and the most the part makes a minute
---@field plants? {job: bpgen.Job, max_output: number|nil}  a step that is made in plants (plastic bar, explosives, battery) and stands as a block among the columns of machines (see scripts/plants_block.lua): the job of that part, with its own steps below it, and the most it makes a minute; the step has no steps below it in the tree of the recipe

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
---@field kind "belts"|"fluid_row"|"fluid_plant"|"item_fluid_chain"|"nested_chain"  how it is laid out (a nested chain is the blueprint of `item_fluid_chain.build_nested`: an item made from two items on belts and a fluid that a chain of its own makes; an item fluid chain is the blueprint of scripts/item_fluid_chain.lua, a fluid made from two items and a fluid, one item made in plants and the other on belts); the others: columns of machines with belts, a row of machines that make a fluid from a fluid (see scripts/fluid_row.lua), or plants that make an item from a fluid with the machines that make the fluid (see scripts/fluid_plant.lua)
---@field maker? bpgen.StageData  of a fluid plant: the step that makes the fluid the recipe takes
---@field made_fluid? string  of a fluid plant: the fluid of its recipe that the step makes (the other one, if it takes two, comes in by a pipe)
---@field parts? bpgen.ChainParts  of an item fluid chain: the step that makes the item made in plants (with `maker` and `made_fluid` for the machines that make its fluid) and the steps that make the other item on belts
---@field nested? bpgen.NestedParts  of a nested chain: the steps that make its two items and the recipe of the chain that makes its fluid
---@field chain_job? bpgen.Job  of a nested chain: the job of the chain that makes its fluid (see `nested`)
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

-- The parts of a recipe that takes two items and a fluid when both items are made on belts and a chain of its own makes the fluid (battery:
-- iron plate, copper plate and sulfuric acid), or nil.
---@param root bpgen.StageData
---@return bpgen.NestedParts|nil
local function nested_parts_of(root)
  if #root.recipe.ingredients ~= 2 or #root.recipe.fluids ~= 1 or #root.suppliers ~= 2 or root.recipe.products[1].type == "fluid" then
    return nil
  end
  local chain_recipe = config.fluid_chains[root.recipe.fluids[1].name]
  if chain_recipe and takes_no_fluid(root.suppliers[1]) and takes_no_fluid(root.suppliers[2]) then
    return {first = root.suppliers[1], second = root.suppliers[2], chain_recipe = chain_recipe}
  end
  return nil
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
---@field kind "belts"|"fluid_row"|"fluid_plant"|"item_fluid_chain"|"nested_chain"
---@field root bpgen.StageData  the step of the recipe the player picked, with the steps below it
---@field maker? bpgen.StageData  the step that makes the fluid the plants take
---@field nested? bpgen.NestedParts
---@field made_fluid? string
---@field parts? bpgen.ChainParts

-- The parts of an item fluid chain: the step made in plants and either the steps that make the other item on belts or the name of that item
-- when it is raw (it comes in by a belt and has no machines).
---@class bpgen.ChainParts
---@field plants bpgen.StageData
---@field belts? bpgen.StageData
---@field raw_item? string

-- The parts of a nested chain: the steps that make its two items on belts and the recipe of the chain that makes its fluid.
---@class bpgen.NestedParts
---@field first bpgen.StageData
---@field second bpgen.StageData
---@field chain_recipe string

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
  local nested = nested_parts_of(root)
  if nested then
    return {kind = "nested_chain", nested = nested}
  end
  if makes_fluid then
    return {kind = "fluid_row"}
  end
  if not takes_fluids_for_plants(root) then
    return {kind = "belts"}
  end
  return read_plants_layout(root, "fluid_plant", nil, force)
end

---@type fun(recipe_name: string, rate_per_minute: number, force: LuaForce|nil): bpgen.Job|nil, LocalisedString|nil
local read_job

---@type fun(job: bpgen.Job): number|nil, bpgen.PlanReason|nil
local max_rate_of

---@type fun(job: bpgen.Job): bpgen.PlannedBlock
local plan_block

-- The step of the recipe the player picked, with the steps below it, and how the recipe is laid out (the arrangement has the step as its
-- `root`), or nil and the message for the player.
---@param prototype LuaRecipePrototype
---@param force LuaForce|nil
---@return bpgen.Arrangement|nil
---@return LocalisedString|nil error_message
local function read_arrangement(prototype, force)
  local root, problem = read_root(prototype, force)
  if not root then
    return nil, problem
  end
  local arrangement, layout_problem = read_layout(root, force)
  if arrangement then
    arrangement.root = root
  end
  return arrangement, layout_problem
end

-- The job with the arrangement of its recipe set on it: its product, its rate, its root and kind, the machines that make a fluid and, for a
-- nested chain, the job of the chain that makes its fluid. Nil and the message for the player when that chain cannot be read.
---@param job bpgen.Job
---@param rate_per_minute number
---@param arrangement bpgen.Arrangement
---@param force LuaForce|nil
---@return bpgen.Job|nil
---@return LocalisedString|nil error_message
local function arranged(job, rate_per_minute, arrangement, force)
  job.item_name, job.rate_per_minute, job.root, job.kind = arrangement.root.item, rate_per_minute, arrangement.root, arrangement.kind
  job.maker, job.made_fluid, job.parts, job.nested = arrangement.maker, arrangement.made_fluid, arrangement.parts, arrangement.nested
  if not arrangement.nested then
    return job
  end
  local problem
  job.chain_job, problem = read_job(arrangement.nested.chain_recipe, 1, force)
  return job.chain_job and job or nil, problem
end

-- The arrangements that make an item from fluids, which a step of a recipe can be made in as a block (see scripts/plants_block.lua).
local PLANTS_KINDS = {fluid_plant = true, item_fluid_chain = true, nested_chain = true}

-- The job of the part of a recipe that makes a step in plants, or in a row of machines that make a fluid: the step with the steps below it, laid out as
-- `read_layout` says, when that is one of `kinds`. Nil and no message when it is another, nil and the message for the player when the part cannot be read.
-- The rate of the job is a placeholder (1 a minute): the part is planned for the share of the rate that asks of it (`plan_blocks`, `plan_fluid_block`), and the
-- most it makes does not depend on the rate.
---@param job bpgen.Job  of the recipe picked, from which the part reads the buildings
---@param stage bpgen.StageData
---@param kinds table<string, true>
---@param force LuaForce|nil
---@return bpgen.Job|nil part
---@return LocalisedString|nil error_message
local function read_part(job, stage, kinds, force)
  local arrangement, problem = read_layout(stage, force)
  if not arrangement or not kinds[arrangement.kind] then
    return nil, problem
  end
  arrangement.root = stage
  return arranged(part_of(job, {}), 1, arrangement, force)
end

-- The leaf of the tree of a recipe for a step that is made in plants: the step with nothing below it, and the job of that part, with the steps
-- below the step. Nil when the step is not made in plants (nil too for the message), or nil and the message for the player when the part cannot
-- be read (the fluid its plants take has no recipe to make it).
---@param job bpgen.Job  of the recipe picked, from which the part reads the buildings
---@param stage bpgen.StageData
---@param force LuaForce|nil
---@return bpgen.StageData|nil leaf
---@return LocalisedString|nil error_message
local function plants_leaf_of(job, stage, force)
  local part, problem = read_part(job, stage, PLANTS_KINDS, force)
  if not part then
    return nil, problem
  end
  local leaf = {}
  for key, value in pairs(stage) do
    leaf[key] = value
  end
  leaf.suppliers, leaf.raw_item, leaf.plants = {}, nil, {job = part}
  return leaf, nil
end

-- Replaces the steps below `stage` that are made in plants by their leaves (see `plants_leaf_of`), going down the steps that are not. Gives the
-- message for the player when a part cannot be read.
---@param job bpgen.Job
---@param stage bpgen.StageData
---@param force LuaForce|nil
---@return LocalisedString|nil error_message
local function split_plants(job, stage, force)
  for index, supplier in ipairs(stage.suppliers) do
    local leaf, problem = plants_leaf_of(job, supplier, force)
    if not leaf and not problem then
      problem = split_plants(job, supplier, force)
    end
    if problem then
      return problem
    end
    stage.suppliers[index] = leaf or supplier
  end
  return nil
end

-- The arrangements that make a fluid, which a step of a recipe that takes it can take it from, as a block (see scripts/rows.lua).
local SUPPLIER_KINDS = {fluid_row = true, item_fluid_chain = true}

-- The first fluid a step takes that machines make (the config names a recipe for it), as the recipe has it, or nil.
---@param stage bpgen.StageData
---@return {name: string, amount: number}|nil
local function made_fluid_taken_by(stage)
  for _, fluid in ipairs(stage.recipe.fluids) do
    if config.fluid_makers[fluid.name] or config.fluid_chains[fluid.name] then
      return fluid
    end
  end
  return nil
end

-- The part that makes the fluid a step takes: the recipe the config names for the fluid (a row of machines, a chain), read like the recipe of any part.
-- Nil and the message for the player when the game has no such recipe or the recipe is not laid out as one that makes a fluid.
---@param job bpgen.Job
---@param stage bpgen.StageData  the step that takes the fluid
---@param fluid {name: string, amount: number}
---@param force LuaForce|nil
---@return {job: bpgen.Job, fluid: string, amount: number}|nil
---@return LocalisedString|nil error_message
local function fluid_supplier_of(job, stage, fluid, force)
  local prototype = prototypes.recipe[config.fluid_chains[fluid.name] or config.fluid_makers[fluid.name]]
  if not prototype then
    return nil, messages.chain_problem("no-recipe", fluid.name)
  end
  local root, problem = read_root(prototype, force)
  if not root then
    return nil, problem
  end
  local part
  part, problem = read_part(job, root, SUPPLIER_KINDS, force)
  if not part then
    return nil, problem or messages.made_fluid(stage.item, fluid.name)
  end
  return {job = part, fluid = fluid.name, amount = fluid.amount}, nil
end

-- Gives the root of a recipe on belts the part that makes the fluid it takes, when machines make that fluid, and refuses a step lower in the tree that
-- takes such a fluid (the machines that make it are built for the last step only). Gives the message for the player when it cannot.
---@param job bpgen.Job
---@param force LuaForce|nil
---@return LocalisedString|nil error_message
local function split_fluid(job, force)
  for _, stage in ipairs(in_order(job.root, {})) do
    local fluid = not stage.plants and made_fluid_taken_by(stage)
    if fluid and stage ~= job.root then
      return messages.made_fluid(stage.item, fluid.name)
    end
    if fluid then
      local supplier, problem = fluid_supplier_of(job, stage, fluid, force)
      if not supplier then
        return problem
      end
      stage.fluid_supplier = supplier
    end
  end
  return nil
end

-- The job with its arrangement set (see `arranged`) and, for a recipe on belts, the steps made in plants split off (see `split_plants`) and the part
-- that makes the fluid of its last step (see `split_fluid`).
---@param job bpgen.Job  with what the game says
---@param prototype LuaRecipePrototype
---@param rate_per_minute number
---@param force LuaForce|nil
---@return bpgen.Job|nil
---@return LocalisedString|nil error_message
local function arranged_job(job, prototype, rate_per_minute, force)
  local arrangement, problem = read_arrangement(prototype, force)
  if not arrangement then
    return nil, problem
  end
  local arranged_one
  arranged_one, problem = arranged(job, rate_per_minute, arrangement, force)
  if not arranged_one then
    return nil, problem
  end
  if arranged_one.kind ~= "belts" then
    return arranged_one, nil
  end
  problem = split_plants(arranged_one, arranged_one.root, force) or split_fluid(arranged_one, force)
  return not problem and arranged_one or nil, problem
end

-- The job for this request, or nil and the message for the player when the recipe is
-- not supported or something it needs is missing from the game. The rate is of the
-- product of the recipe.
---@param recipe_name string  the recipe the player picked
---@param rate_per_minute number
---@param force LuaForce|nil  whose research decides the design of the inputs; nil takes the original
---@return bpgen.Job|nil
---@return LocalisedString|nil error_message
function read_job(recipe_name, rate_per_minute, force)
  local prototype, problem = picked_recipe(recipe_name)
  if not prototype then
    return nil, problem
  end
  local job
  job, problem = read_buildings(force)
  if not job then
    return nil, problem
  end
  job, problem = arranged_job(job --[[@as bpgen.Job]], prototype, rate_per_minute, force)
  if not job then
    return nil, problem
  end
  return add_unlocked(job, force) -- what the force has unlocked is added just below
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

-- The rows of the connections of what a machine takes, as it faces west (see `input_side.connection_rows`), or nil for a machine that takes
-- no fluid or has them where the layout draws no pipes.
---@param stage bpgen.StageData
---@return integer[]|nil
local function fluid_connections_of(stage)
  local size = stage.machine_size
  if not (stage.fluid_input and size) then
    return nil
  end
  return input_side.connection_rows(fluid_boxes.read(prototypes.entity[stage.machine], size), size)
end

-- How many input belts a step that takes a fluid has, at most, and how many inserters its machines get on them: the rows its pipe
-- connections leave, from one belt, or, with the weave, one on each of two belts (a machine with one free row has one belt). Nil for a
-- machine the pipes are not drawn for.
---@param stage bpgen.StageData
---@param weaves boolean  whether the blueprint weaves belts (see `can_weave`)
---@return integer|nil slots
---@return integer|nil most_woven
---@return integer|nil most_belts
local function fluid_slots(stage, weaves)
  local connections = fluid_connections_of(stage)
  local slots = connections and layout.max_fluid_inserters(stage.machine_size --[[@as integer]], connections)
  if not slots then
    return nil
  end
  local two_belts = weaves and slots >= FLUID_BELTS
  return slots, two_belts and slots or nil, two_belts and FLUID_BELTS or 1
end

-- Whether the machine and the recipe of a step that takes a fluid are what the layout draws pipes for: one fluid, a machine with a fluid
-- input of the size it draws them for, whose connections it can place, and no more items than its belts carry (four on two woven belts, two
-- on one: a machine whose connections leave one free row has one belt).
---@param stage bpgen.StageData
---@return boolean
local function is_built_with_fluid(stage)
  local slots, _, most_belts = fluid_slots(stage, true)
  return #stage.recipe.fluids == 1 and slots ~= nil and #stage.recipe.ingredients <= (most_belts --[[@as integer]]) * LANES_PER_BELT
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

-- The reason a step that takes a fluid cannot be built, as a message for the player, or nil. The pipes come to a column of their own (a
-- step that takes a fluid and something from another step starts a final column, with room for the pipes beside its belt; the column of a
-- step fed raw items only is the first of a chain, whose pipes have no pump to come from); the step needs a machine, and a recipe, that
-- the pipes are drawn for (see `is_built_with_fluid`).
---@param job bpgen.Job
---@param stage bpgen.StageData
---@return LocalisedString|nil
local function fluid_problem(job, stage)
  if #stage.recipe.fluids == 0 then
    return nil
  end
  if chain.input_count(stage) < 1 then
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

-- The rows of pipes of the machines of a step that makes a fluid (see `fluid_row.rows_of`), or nil when their pipe
-- connections are not in rows of the kind the layout draws.
---@param stage bpgen.StageData  its machine is square
---@return bpgen.FluidRows|nil
local function fluid_rows_of(stage)
  local size = stage.machine_size --[[@as integer]]
  return fluid_row.rows_of(fluid_boxes.read(prototypes.entity[stage.machine], size), size)
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

-- Whether a wire of the blueprint reaches from one pole beside the output inserters of the plants to the next, which stand where they do
-- beside the assembling machines (scripts/output_side.lua). That the pole reaches the inserters it stands beside is `poles_fit_row`'s
-- (two tiles: the plants come with a row of refineries, which needs the same), so it is not asked again. The final plants of a chain are
-- the same machine as the plants of its first part, which are asked, so they are not asked again either.
---@param names bpgen.SharedNames
---@param size integer  the machine's size
---@return boolean
local function poles_fit_plant(names, size)
  return names.pole_wire_distance >= output_side.longest_wire(size, layout.pole_reach(names.pole_supply_distance))
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
  local boxes = fluid_boxes.read(prototypes.entity[stage.machine], size)
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

-- How many output inserters the plants of a step may have: the two that the winding output belt serves for machines of 3 x 3, as for the
-- assembling machines (see scripts/output_side.lua); otherwise one.
---@param stage bpgen.StageData
---@return integer
local function output_inserters_max(stage)
  return stage.machine_size == constants.WINDING_MACHINE_SIZE and constants.WINDING_OUTPUT_INSERTERS or 1
end

-- The plants of a step as `fluid_plant` and `item_fluid_plants` take them: the machine, the recipe, the size, how many, and the pipe
-- connections as the game gives them. `rows` is nil for a machine whose connections are not in rows.
---@param stage bpgen.StageData
---@param count integer
---@return table
local function plants_of(stage, count, output_inserters, output_winds)
  local size = stage.machine_size --[[@as integer]]
  local boxes = fluid_boxes.read(prototypes.entity[stage.machine], size)
  return {
    machine = stage.machine, recipe = stage.recipe.name, size = size, count = count, boxes = boxes, rows = fluid_row.rows_of(boxes, size),
    item_output = stage.recipe.products[1].type ~= "fluid", output_inserters = output_inserters, output_winds = output_winds,
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

-- The reason a nested chain cannot be built, as a message for the player, or nil: the steps on belts that make its two items, the chain that
-- makes its fluid, and the plants of the recipe.
---@param job bpgen.Job
---@return LocalisedString|nil
local function nested_chain_problem(job)
  local nested = job.nested --[[@as bpgen.NestedParts]]
  for _, root in ipairs({nested.first, nested.second}) do
    for _, stage in ipairs(in_order(root, {})) do
      local problem = stage_problem(job, stage)
      if problem then
        return problem
      end
    end
  end
  return item_fluid_chain_problem(job.chain_job --[[@as bpgen.Job]]) or item_fluid_plants_problem(job, job.root)
end

-- The reason the machines of a recipe made in plants or in a row of machines (the ways to make an item or a fluid from fluids and items) cannot be built
-- with, as a message for the player, or nil. A part of a recipe on belts (plastic bar in advanced circuit, the petroleum gas of a barrel) is one of these.
---@param job bpgen.Job  of kind "fluid_row", "fluid_plant", "item_fluid_chain" or "nested_chain"
---@return LocalisedString|nil
local function part_problem(job)
  if job.kind == "fluid_row" then
    return fluid_row_problem(job, job.root)
  end
  if job.kind == "fluid_plant" then
    return fluid_plant_problem(job)
  end
  if job.kind == "item_fluid_chain" then
    return item_fluid_chain_problem(job)
  end
  return nested_chain_problem(job)
end

-- The reason a step of a recipe on belts cannot be built, as a message for the player, or nil: its own machines, the part that makes it in plants, or the part that
-- makes the fluid it takes.
---@param job bpgen.Job
---@param stage bpgen.StageData
---@return LocalisedString|nil
local function stage_part_problem(job, stage)
  if stage.plants then
    return part_problem(stage.plants.job)
  end
  return stage_problem(job, stage) or (stage.fluid_supplier and part_problem(stage.fluid_supplier.job)) or nil
end

-- The reason one of the machines cannot be built with, as a message for the player, or nil.
---@param job bpgen.Job
---@return LocalisedString|nil
local function machine_problem(job)
  if job.kind ~= "belts" then
    return part_problem(job)
  end
  for _, stage in ipairs(in_order(job.root, {})) do
    local problem = stage_part_problem(job, stage)
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
---@field fluid_block? bpgen.PlannedBlock  of the root, when machines make the fluid it takes: the part that makes it, planned for what the machines of the root take of it
---@field block? bpgen.PlannedBlock  of a step made in plants, the part planned for the share of the rate the recipe asks of it

-- A part made in plants of a recipe, planned for the rate it is asked for.
---@class bpgen.PlannedBlock
---@field raws bpgen.RawAmount[]  what it takes a minute
---@field fluids table<string, true>  the names of the fluids among `raws`; the others are raw items
---@field summaries bpgen.StageSummary[]  its machines, from the first step to the last
---@field build fun(): bpgen.PlantsBlock  draws it

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
    local slots, most_woven, belts = fluid_slots(stage, weaves)
    return assert(slots, "generator: no room for inserters beside the pipes of a machine of size " .. machine_size), most_woven, assert(belts)
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
    fluid = #stage.recipe.fluids > 0 or nil,
  }
end

-- The most a step made in plants makes a minute: what its part makes at the most (the planner is asked once, and the answer is kept).
---@param stage bpgen.StageData  with `plants`
---@return number
local function plants_max(stage)
  local plants = stage.plants --[[@as {job: bpgen.Job, max_output: number|nil}]]
  plants.max_output = plants.max_output or assert(max_rate_of(plants.job), "generator: a part made in plants says no most that it makes")
  return plants.max_output
end

-- A step as the planner wants it, with the steps that make its ingredients.
---@param job bpgen.Job
---@param stage bpgen.StageData
---@return bpgen.StageTree
local function stage_tree(job, stage)
  if stage.plants then
    return {stage = {product = stage.item, recipe = stage.recipe, machine_speed = stage.machine_speed, block = {max_output = plants_max(stage)}}, suppliers = {}}
  end
  local suppliers = {}
  for index, supplier in ipairs(stage.suppliers) do
    suppliers[index] = stage_tree(job, supplier)
  end
  return {stage = stage_request(job, stage), suppliers = suppliers}
end

-- The most the root makes a minute that the part that makes the fluid it takes can supply: what the part makes at the most (the planner is asked once, and the
-- answer is kept) over the fluid one item of the root takes. Nil when no part makes the fluid of the root.
---@param job bpgen.Job
---@return number|nil
local function fluid_limit(job)
  local supplier = job.root.fluid_supplier
  if not supplier then
    return nil
  end
  supplier.max_output = supplier.max_output or assert(max_rate_of(supplier.job), "generator: a part that makes a fluid says no most that it makes")
  return supplier.max_output / (supplier.amount / planner.amount_made(job.root.recipe, job.root.item))
end

-- What the planner is asked for this job: the belt lane, and the inserters of each step.
---@param job bpgen.Job
---@return bpgen.TreeRequest
local function tree_request(job)
  return {
    rate_per_minute = job.rate_per_minute,
    lane_items_per_minute = planner.lane_items_per_minute(job.belt_speed),
    root = stage_tree(job, job.root),
    most_per_minute = fluid_limit(job),
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

-- Plans the part of every step made in plants for what the rate asks of it: its load is the share of what it makes at the most.
---@param planned bpgen.PlannedStage
local function plan_blocks(planned)
  for _, planned_stage in ipairs(in_order(planned, {})) do
    local plants = planned_stage.stage.plants
    if plants then
      planned_stage.block = plan_block(part_of(plants.job, {rate_per_minute = planned_stage.plan.load * plants_max(planned_stage.stage)}))
    end
  end
end

-- Plans the part that makes the fluid the root takes, for what the machines of the root take of it.
---@param planned bpgen.PlannedStage  the root
local function plan_fluid_block(planned)
  local supplier = planned.stage.fluid_supplier
  if supplier then
    local crafts = planned.plan.output_per_minute / planner.amount_made(planned.stage.recipe, planned.stage.item)
    planned.fluid_block = plan_block(part_of(supplier.job, {rate_per_minute = crafts * supplier.amount}))
  end
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
  local planned = planned_tree(job.root, plans)
  plan_blocks(planned)
  plan_fluid_block(planned)
  return planned, nil
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
    fluid_connections = fluid and fluid_connections_of(planned.stage) or nil,
  }
end

local layout_stage -- defined below: a step is laid out with the steps that make its ingredients

-- What the layout is told about what a step eats: the steps that make its ingredients, each saying which belt of this step it rides, then the raw
-- item that goes with them, if any, which has no machines and only a belt (on belt a).
---@param planned bpgen.PlannedStage  with its `demand`
---@param lane number  what one lane of a belt carries a minute
---@param pole_reach integer
---@return (bpgen.StageLayout|bpgen.RawSupplier)[]
local function layout_suppliers(planned, lane, pole_reach)
  local suppliers = {}
  for index, supplier in ipairs(planned.suppliers) do
    suppliers[index] = layout_stage(supplier, lane, pole_reach)
    suppliers[index].belt = planner.belt_of(planned.plan.belts, supplier.stage.item)
  end
  local raw_item = planned.stage.raw_item
  if raw_item then
    suppliers[#suppliers + 1] = {raw_item = raw_item, feed = feed_of(planned)}
  end
  return suppliers
end

-- What the layout is told about a step and what it eats: the steps that make its
-- ingredients, each saying which belt of this step it rides, then the raw item that goes
-- with them, if any, which has no machines and only a belt (on belt a). A step that eats only
-- raw items also says what it takes of them (`feed`), which `rows.build_pure` uses.
---@param planned bpgen.PlannedStage  with its `demand`
---@param lane number  what one lane of a belt carries a minute
---@param pole_reach integer  how many tiles away from its own a pole of the blueprint powers (`layout.pole_reach`)
---@return bpgen.StageLayout
function layout_stage(planned, lane, pole_reach)
  if planned.block then
    return {plants = planned.block.build()}
  end
  local suppliers = layout_suppliers(planned, lane, pole_reach)
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
    fluid_supplier = planned.fluid_block and planned.fluid_block.build() or nil,
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
    local entities, _, entries = rows.build(root, job.names)
    return entities, nil, root, entries
  end
  local entities, supplies = rows.build_pure(root, job.names, job.input_options)
  local belts = {}
  for _, supply in ipairs(supplies) do
    if supply.type ~= "fluid" then
      belts[#belts + 1] = supply.item
    end
  end
  return entities, belts, root, supplies
end

-- Lay out the planned machines and word the results for the player.
---@param job bpgen.Job
---@param planned bpgen.PlannedStage
---@return bpgen.Generated
local function assemble(job, planned)
  local raws = accounting.raw_amounts(planned) -- also notes what each step takes, which the layout needs
  local entities, belts, root, supplies = build_entities(job, planned)
  finishing.add_labels(job, entities, root, supplies)
  finishing.add_lights(job, entities, root, supplies)
  return {
    entities = entities,
    description = messages.description(job.item_name, planned.plan.output_per_minute, accounting.stage_summaries(planned)),
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
  local boxes = fluid_boxes.read(prototypes.entity[stage.machine], size)
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

-- Wires the poles of the pumps of the entries to the poles of the row, with poles between them where a wire does not reach.
---@param entities bpgen.Entity[]
---@param inlets {pole?: bpgen.Entity}[]
---@param names bpgen.SharedNames
---@param sizes table<string, integer>
local function join_row_poles(entities, inlets, names, sizes)
  local row_poles, groups = {}, {}
  for _, entity in ipairs(entities) do
    if entity.name == names.pole and not (inlets[1] and inlets[1].pole == entity) then
      row_poles[#row_poles + 1] = entity
    end
  end
  groups[1] = {row_poles[1]}
  for _, pole in ipairs(corner_entries.poles_of(inlets)) do
    groups[#groups + 1] = {pole}
  end
  poles.join(groups, {
    entities = entities, taken = grid.taken_tiles(entities, function(entity) return inputs.footprint(entity, names, sizes) end),
    pole = names.pole, wire_distance = names.pole_wire_distance,
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
  local inlets = corner_entries.add(entities, {{key = "input", x = entries.input.x, y = entries.input.y, name = job.names.pipe}}, {pump = job.names.pump, pole = job.names.pole})
  join_row_poles(entities, inlets, job.names, row_sizes(job))
  finishing.add_inlet_labels(job, entities, inlets, {input = {name = stage.recipe.fluids[1].name, type = "fluid"}}, row_sizes(job))
  finishing.add_row_lights(job, entities, inlets, row_sizes(job))
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
  local plain = job.inserter
  local with_item = #stage.recipe.ingredients == 1
  local lane = planner.lane_items_per_minute(job.belt_speed)
  return {
    product = stage.item, recipe = stage.recipe, machine_speed = stage.machine_speed,
    maker_recipe = maker.recipe, maker_speed = maker.machine_speed, rate_per_minute = job.rate_per_minute,
    makers_that_fit = machines_that_fit(maker), plants_that_fit = machines_that_fit(stage),
    lane_items_per_minute = lane, output_inserters_max = output_inserters_max(stage),
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
  local boxes = fluid_boxes.read(prototypes.entity[stage.machine], size)
  return {
    makers = fluid_row_build(job, job.maker, plan.makers),
    plants = {
      machine = stage.machine, recipe = stage.recipe.name, size = size, count = plan.plants, boxes = boxes,
      rows = assert(fluid_row.rows_of(boxes, size), "generator: the pipe connections of the machine are not in rows"),
      fluid_boxes = #stage.recipe.fluids == 2 and plant_fluid_boxes(stage.recipe, job.made_fluid --[[@as string]]) or nil,
    },
    inserter = job.names.inserter, belt = job.names.belt, output_inserters = plan.output_inserters, output_winds = plan.output_winds,
    item_input = #stage.recipe.ingredients == 1 or nil,
    pipe_to_ground = job.names.pipe_to_ground, underground_reach = config.pipe_to_ground_reach, pump = job.names.pump,
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
  finishing.add_inlet_labels(job, entities, entries.inlets, {
    input = {name = job.maker.recipe.fluids[1].name, type = "fluid"}, supplied = supplied and {name = supplied.name, type = "fluid"},
    items = item and {name = item.name, type = "item"},
  }, row_sizes(job))
  finishing.add_row_lights(job, entities, entries.inlets, row_sizes(job))
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
    plants_that_fit = fit, lane_items_per_minute = planner.lane_items_per_minute(job.belt_speed), output_inserters_max = output_inserters_max(stage),
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
  -- both items side-load one lane of the belt b, whatever the lanes of their own belts carry
  local lane = planner.lane_items_per_minute(job.belt_speed)
  made_in_plants, made_on_belts = math.min(made_in_plants, lane), math.min(made_on_belts, lane)
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

-- How much of a fluid the plants of a plan take a minute.
---@param plan bpgen.ItemFluidPlantsPlan
---@param name string
---@return number
local function fluid_amount(plan, name)
  for _, fluid in ipairs(plan.fluids) do
    if fluid.name == name then
      return fluid.amount
    end
  end
  error("generator: the plants take no " .. name)
end

-- The jobs of the parts of a nested chain for the rates they are given: the steps on belts that make each item, and the chain that makes the
-- fluid (a job of its own, read with the recipe of the nested chain).
---@param job bpgen.Job
---@param rates {first: number, second: number, fluid: number}
---@return bpgen.Job first_job
---@return bpgen.Job second_job
---@return bpgen.Job chain_job
local function nested_jobs(job, rates)
  local nested = job.nested --[[@as bpgen.NestedParts]]
  local first = part_of(job, {root = nested.first, kind = "belts", item_name = nested.first.item, rate_per_minute = rates.first})
  local second = part_of(job, {root = nested.second, kind = "belts", item_name = nested.second.item, rate_per_minute = rates.second})
  return first, second, part_of(job.chain_job --[[@as bpgen.Job]], {rate_per_minute = rates.fluid})
end

-- What the parts of a nested chain can make a minute at most, as the plants would take it: the two items (each side-loads one lane of the belt
-- b, whatever the lanes of its own belt carry) and the fluid, from the chain that makes it. Nil when a part has steps the planner cannot handle.
---@param job bpgen.Job
---@return {first: number, second: number, fluid: number}|nil
local function nested_most(job)
  local first_job, second_job, chain_job = nested_jobs(job, {first = 1, second = 1, fluid = 1})
  local first, second = planner.max_tree_rate(tree_request(first_job)), planner.max_tree_rate(tree_request(second_job))
  local fluid = item_fluid_chain_max_rate(chain_job)
  if not (first and second and fluid) then
    return nil
  end
  local lane = planner.lane_items_per_minute(job.belt_speed)
  return {first = math.min(first, lane), second = math.min(second, lane), fluid = fluid}
end

-- How many plants a nested chain can feed with what its parts make, at most, and what one of them makes a minute: as many as each part can
-- feed, and as stand in the length a run of pipes may have. Nil and the reason when a part has a recipe the planner cannot handle.
---@param job bpgen.Job
---@return {plants: integer, per_plant: number}|nil
---@return bpgen.PlanReason|nil reason
local function most_nested_plants(job)
  local request = item_fluid_request(job, 1)
  request.rate_per_minute = 0
  local one, reason = planner.plan_item_fluid_plants(request)
  local most = one and nested_most(job)
  if not (one and most) then
    return nil, reason or "unsupported-recipe"
  end
  local nested = job.nested --[[@as bpgen.NestedParts]]
  local by_first = math.floor(most.first / item_amount(one, nested.first.item) + constants.EPSILON)
  local by_second = math.floor(most.second / item_amount(one, nested.second.item) + constants.EPSILON)
  local by_fluid = math.floor(most.fluid / fluid_amount(one, job.root.recipe.fluids[1].name) + constants.EPSILON)
  return {plants = math.max(1, math.min(machines_that_fit(job.root), by_first, by_second, by_fluid)), per_plant = one.per_plant}, nil
end

---@class bpgen.NestedChainPlans
---@field final bpgen.ItemFluidPlantsPlan  the plants of the recipe
---@field first bpgen.PlannedStage  the steps that make the first item
---@field second bpgen.PlannedStage
---@field chain bpgen.ItemFluidChainPlans  the chain that makes the fluid
---@field first_job bpgen.Job
---@field second_job bpgen.Job
---@field chain_job bpgen.Job

-- The plans of the parts of a nested chain for the rate asked for, or nil, the reason and the most it can make.
---@param job bpgen.Job
---@return bpgen.NestedChainPlans|nil
---@return bpgen.PlanReason|nil reason
---@return number|nil max_rate  given with "rate-too-high"
local function plan_nested_chain(job)
  local limit, reason = most_nested_plants(job)
  if not limit then
    return nil, reason
  end
  local final, why, max_rate = planner.plan_item_fluid_plants(item_fluid_request(job, limit.plants))
  if not final then
    return nil, why, max_rate
  end
  local nested = job.nested --[[@as bpgen.NestedParts]]
  local first_job, second_job, chain_job = nested_jobs(job, {
    first = item_amount(final, nested.first.item), second = item_amount(final, nested.second.item), fluid = fluid_amount(final, job.root.recipe.fluids[1].name),
  })
  local first, second, chain = make_plans(first_job), make_plans(second_job), plan_item_fluid_chain(chain_job)
  assert(first and second and chain, "generator: the parts of a nested chain cannot make what its plants take, though the most they make said they can")
  return {final = final, first = first, second = second, chain = chain, first_job = first_job, second_job = second_job, chain_job = chain_job}
end

-- The most a nested chain makes a minute (see `most_nested_plants`), or nil and why not.
---@param job bpgen.Job
---@return number|nil max_rate
---@return bpgen.PlanReason|nil reason
local function nested_chain_max_rate(job)
  local limit, reason = most_nested_plants(job)
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
    plants = plants_of(job.root, plan.plants, plan.output_inserters, plan.output_winds), inserter = names.inserter, belt = names.belt, pipe = names.pipe, pipe_to_ground = names.pipe_to_ground,
    pole = names.pole, pole_supply_distance = names.pole_supply_distance, pole_wire_distance = names.pole_wire_distance,
    underground_reach = config.pipe_to_ground_reach,
  }
end

-- The block of the steps that make the second item of a chain, made apart (see `bpgen.BeltsBlock`): its entities, its poles, the tile of the end
-- of its product belt and where its belt of raw items comes in, with what the belt takes in the design that brings in one belt of each material
-- (the band that does that is the whole blueprint's, see scripts/shared_band.lua, so the block is the one the original design draws). Also gives
-- the layout it was made from.
---@param job bpgen.Job  the job of the steps on belts
---@param planned bpgen.PlannedStage  with its `demand`
---@return bpgen.BeltsBlock
---@return bpgen.StageLayout root
local function belts_block(job, planned)
  local root = layout_stage(planned, planner.lane_items_per_minute(job.belt_speed), layout.pole_reach(job.names.pole_supply_distance))
  local entities, raw_stages = rows.build(root, job.names)
  assert(#raw_stages == 1, "generator: the steps that make the second item of a chain take raw items on more than one belt")
  local poles = {}
  for _, entity in ipairs(entities) do
    if entity.name == job.names.pole then
      poles[#poles + 1] = entity
    end
  end
  local start = belts_blocks.raw_start(entities, job.names.belt)
  local feed = job.input_options and assert(raw_stages[1].feed, "generator: the step fed raw items has no feed") or nil
  return {entities = entities, poles = poles, product = belts_blocks.product_end(entities, job.names.belt), raw = {{key = "belt", x = start.x, y = start.y, feed = feed}}}, root
end

-- The block of the part of a chain that makes the second item, with what it takes a minute (as `raw_amounts` gives it) and the layout of its
-- steps (nil when the item is raw).
---@param job bpgen.Job
---@param plans bpgen.ItemFluidChainPlans
---@return bpgen.BeltsBlock block
---@return bpgen.StageLayout|nil belts_root
---@return bpgen.RawAmount[] belts_raws
local function second_item_block(job, plans)
  if plans.belts then
    local belts_raws = accounting.raw_amounts(plans.belts) -- also notes what each step takes, which the layout needs
    local block, belts_root = belts_block(plans.belts_job, plans.belts)
    return block, belts_root, belts_raws
  end
  local raw_item = belts_item_of(job.parts --[[@as bpgen.ChainParts]])
  local amount = item_amount(plans.final, raw_item)
  local feed = job.input_options and {items = {{name = raw_item, amount = amount}}} or nil
  return belts_blocks.of_raw_item(raw_item, job.names.belt, feed), nil, {{name = raw_item, amount = amount}}
end

-- The tiles on a side of each machine of a chain, by name.
---@param job bpgen.Job
---@param belts_root bpgen.StageLayout|nil  the layout of the steps on belts, nil when the second item is raw
---@return table<string, integer>
local function chain_sizes(job, belts_root)
  local parts = job.parts --[[@as bpgen.ChainParts]]
  local sizes = belts_root and finishing.machine_sizes_of(belts_root, {}) or {}
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

-- What comes in at each entry of a chain that is a pipe, by its key (see `item_fluid_chain.build`): the crude oil, the water of the plants part
-- (which is the water of the final plants too, when they take the same fluid). The fluid the final plants take has an entry of its own,
-- "final_fluid", when it is not the same.
---@param job bpgen.Job
---@param plans bpgen.ItemFluidChainPlans
---@return table<string, {name: string, type: "item"|"fluid"}>
local function chain_things(job, plans)
  local supplied = plans.plants.supplied[1]
  return {
    input = {name = job.maker.recipe.fluids[1].name, type = "fluid"},
    supplied = supplied and {name = supplied.name, type = "fluid"},
    final_fluid = {name = job.root.recipe.fluids[1].name, type = "fluid"},
  }
end

-- What comes in at each entry of a blueprint made of parts: the pipes `things` knows, and, in the design that brings in one belt of each material,
-- a belt of the item whose name is the key of each of the other entries (the band names its belts by their item). The original design has a
-- belt of raw items for each part, which no panel names.
---@param job bpgen.Job
---@param inlets {key: string}[]
---@param things table<string, {name: string, type: "item"|"fluid"}>  the pipes, by the key of their entry
---@return table<string, {name: string, type: "item"|"fluid"}>
local function entry_things(job, inlets, things)
  if not job.input_options then
    return things
  end
  local all = {}
  for key, thing in pairs(things) do
    all[key] = thing
  end
  for _, inlet in ipairs(inlets) do
    all[inlet.key] = all[inlet.key] or {name = inlet.key, type = "item"}
  end
  return all
end

---@param job bpgen.Job
---@param plans bpgen.ItemFluidChainPlans
---@param belts_raws bpgen.RawAmount[]
---@return bpgen.RawAmount[]
local function chain_raws(job, plans, belts_raws)
  return accounting.merged_raws({belts_raws, plans.final.fluids, plans.plants.supplied, {{name = job.maker.recipe.fluids[1].name, amount = plans.plants.source_per_minute}}})
end

-- The machines of a chain by name, in the order of the steps: those that make the fluid of the first item, those of the first item, the
-- steps on belts and the plants of the fluid; a machine that two steps share (the chemical plant) once, with the sum.
---@param job bpgen.Job
---@param plans bpgen.ItemFluidChainPlans
---@return bpgen.StageSummary[]
local function chain_summaries(job, plans)
  return accounting.merged_summaries({
    {{machines = plans.plants.makers, machine = job.maker.machine}, {machines = plans.plants.plants, machine = job.parts.plants.machine}},
    plans.belts and accounting.stage_summaries(plans.belts) or {}, {{machines = plans.final.plants, machine = job.root.machine}},
  })
end

-- What the band that brings in one belt of each material is built with: nil for the original design.
---@param job bpgen.Job
---@return bpgen.BandRequest|nil
local function band_of(job)
  return job.input_options and {names = job.names, options = job.input_options} or nil
end

-- What `item_fluid_chain.build` and `item_fluid_chain.build_block` are asked for the plans of a chain, with the block of its second item.
---@param job bpgen.Job
---@param plans bpgen.ItemFluidChainPlans
---@param block bpgen.BeltsBlock
---@param sizes table<string, integer>
---@return bpgen.ItemFluidChainBuild
local function chain_request(job, plans, block, sizes)
  return {
    plants_part = fluid_plant_build(plans.plants_job, plans.plants), belts_part = block, final_plants = item_fluid_plants_request(job, plans.final),
    shared_fluid = shares_fluid(job, plans), band = band_of(job), pump = job.names.pump, size_of = function(entity) return inputs.footprint(entity, job.names, sizes) end,
  }
end

-- The names of the belts that come in, from the top of the blueprint down, for the design that brings in one belt of each material; nil for
-- the original design.
---@param job bpgen.Job
---@param inlets {key: string, x: integer, y: integer}[]
---@param things table<string, {name: string, type: "item"|"fluid"}>
---@return string[]|nil
local function belts_from_the_top(job, inlets, things)
  if not job.input_options then
    return nil
  end
  local ordered, names = {table.unpack(inlets)}, {}
  table.sort(ordered, function(first, second) return first.y < second.y end)
  for _, inlet in ipairs(ordered) do
    local thing = things[inlet.key]
    names[#names + 1] = thing and thing.type == "item" and thing.name or nil
  end
  return names
end

-- The names of the belts that come in, for the message of a chain: in the design that brings in one belt of each material, those of the band, from
-- the top down; in the original design nothing, unless its second item is raw, which comes in on a belt of its own (the one belt the player
-- brings, which the message names).
---@param job bpgen.Job
---@param plans bpgen.ItemFluidChainPlans
---@param inlets {key: string, x: integer, y: integer}[]
---@param things table<string, {name: string, type: "item"|"fluid"}>
---@return string[]|nil
local function chain_belts(job, plans, inlets, things)
  if job.input_options then
    return belts_from_the_top(job, inlets, things)
  end
  return not plans.belts and {belts_item_of(job.parts --[[@as bpgen.ChainParts]])} or nil
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
  local block, belts_root, belts_raws = second_item_block(job, plans)
  local sizes = chain_sizes(job, belts_root)
  local built = item_fluid_chain.build(chain_request(job, plans, block, sizes))
  local things = entry_things(job, built.inlets, chain_things(job, plans))
  finishing.add_inlet_labels(job, built.entities, built.inlets, things, sizes)
  finishing.add_row_lights(job, built.entities, built.inlets, sizes)
  return {
    entities = built.entities,
    description = messages.description(job.item_name, plans.final.output_per_minute, chain_summaries(job, plans)),
    message = messages.ready(plans.final.output_per_minute, job.root.item, chain_raws(job, plans, belts_raws), chain_belts(job, plans, built.inlets, things)),
  }
end

-- One part of a nested chain, made apart, with what it takes a minute, what its entries bring, the tiles on a side of its machines and what
-- its machines are.
---@class bpgen.NestedPart
---@field block bpgen.BeltsBlock|bpgen.ItemFluidChainBlock
---@field raws bpgen.RawAmount[]
---@field things table<string, {name: string, type: "item"|"fluid"}>  by the key of the entry (see `item_fluid_chain.build_nested`)
---@field sizes table<string, integer>
---@field summaries bpgen.StageSummary[]

-- The part of a nested chain that makes an item on belts.
---@param job bpgen.Job  the job of its steps
---@param planned bpgen.PlannedStage
---@return bpgen.NestedPart
local function belts_part(job, planned)
  local raws = accounting.raw_amounts(planned) -- also notes what each step takes, which the layout needs
  local block, root = belts_block(job, planned)
  return {block = block, raws = raws, things = {}, sizes = finishing.machine_sizes_of(root, {}), summaries = accounting.stage_summaries(planned)}
end

-- The part of a nested chain that makes the fluid: a chain, made apart (see `item_fluid_chain.build_block`).
---@param job bpgen.Job  the job of the chain
---@param plans bpgen.ItemFluidChainPlans
---@return bpgen.NestedPart
local function chain_part(job, plans)
  local block, belts_root, belts_raws = second_item_block(job, plans)
  local sizes = chain_sizes(job, belts_root)
  return {
    block = item_fluid_chain.build_block(chain_request(job, plans, block, sizes)), raws = chain_raws(job, plans, belts_raws),
    things = chain_things(job, plans), sizes = sizes, summaries = chain_summaries(job, plans),
  }
end

-- What the entries of a nested chain bring, by the key of the entry: the key of its part's entry with the name of the part before it.
---@param parts table<string, bpgen.NestedPart>
---@return table<string, {name: string, type: "item"|"fluid"}>
local function nested_things(parts)
  local things = {}
  for name, part in pairs(parts) do
    for key, thing in pairs(part.things) do
      things[name .. ":" .. key] = thing
    end
  end
  return things
end

-- The tiles on a side of each machine of a nested chain: those of its parts and of its plants.
---@param job bpgen.Job
---@param parts table<string, bpgen.NestedPart>
---@return table<string, integer>
local function nested_sizes(job, parts)
  local sizes = {[job.root.machine] = machine_size_of(job.root)}
  for _, part in pairs(parts) do
    for machine, size in pairs(part.sizes) do
      sizes[machine] = size
    end
  end
  return sizes
end

-- What `item_fluid_chain.build_nested` and `item_fluid_chain.build_nested_block` are asked for the plans of a nested chain.
---@param job bpgen.Job
---@param plans bpgen.NestedChainPlans
---@param parts table<string, bpgen.NestedPart>
---@param sizes table<string, integer>
---@return bpgen.NestedChainBuild
local function nested_request(job, plans, parts, sizes)
  return {
    first_part = parts.first.block --[[@as bpgen.BeltsBlock]], second_part = parts.second.block --[[@as bpgen.BeltsBlock]],
    fluid_chain = parts.chain.block --[[@as bpgen.ItemFluidChainBlock]], final_plants = item_fluid_plants_request(job, plans.final), band = band_of(job),
    pump = job.names.pump, size_of = function(entity) return inputs.footprint(entity, job.names, sizes) end,
  }
end

-- The item asked for, made in plants from two items made on belts and a fluid that a chain makes (see `item_fluid_chain.build_nested`): the
-- blueprint of the steps that make each item, of the chain that makes the fluid, and of the plants, and the words for the player.
---@param job bpgen.Job
---@return bpgen.Generated|nil
---@return LocalisedString|nil error_message
local function generate_nested_chain(job)
  local plans, reason, max_rate = plan_nested_chain(job)
  if not plans then
    ---@cast reason bpgen.PlanReason -- the planner always gives a reason when it gives no plan
    return nil, messages.plan_problem(reason, max_rate)
  end
  local parts = {first = belts_part(plans.first_job, plans.first), second = belts_part(plans.second_job, plans.second), chain = chain_part(plans.chain_job, plans.chain)}
  local sizes = nested_sizes(job, parts)
  local built = item_fluid_chain.build_nested(nested_request(job, plans, parts, sizes))
  local things = entry_things(job, built.inlets, nested_things(parts))
  finishing.add_inlet_labels(job, built.entities, built.inlets, things, sizes)
  finishing.add_row_lights(job, built.entities, built.inlets, sizes)
  local made, raws = plans.final.output_per_minute, accounting.merged_raws({parts.first.raws, parts.second.raws, parts.chain.raws})
  local summaries = accounting.merged_summaries({parts.first.summaries, parts.second.summaries, parts.chain.summaries, {{machines = plans.final.plants, machine = job.root.machine}}})
  return {
    entities = built.entities, description = messages.description(job.item_name, made, summaries),
    message = messages.ready(made, job.root.item, raws, belts_from_the_top(job, built.inlets, things)),
  }
end

-- The names of the fluids of a part made in plants that come in by a pipe, as a set, and the same by the key of the start of each pipe.
---@param things table<string, {name: string, type: "item"|"fluid"}>  what comes in at each entry, by key
---@return table<string, string> by_key
---@return table<string, true> names
local function fluids_of(things)
  local by_key, names = {}, {}
  for key, thing in pairs(things) do
    if thing.type == "fluid" then
      by_key[key], names[thing.name] = thing.name, true
    end
  end
  return by_key, names
end

-- Plants that make an item from a fluid and an item (plastic bar), with the machines that make the fluid, planned for the rate of the job.
---@param job bpgen.Job
---@return bpgen.PlannedBlock
local function plan_fluid_plant_block(job)
  local plan = assert(planner.plan_fluid_plant(fluid_plant_request(job)), "generator: the plants cannot make what the recipe asks of them, though the most they make said they can")
  local item = plan.items[1]
  local by_key, names = fluids_of({
    input = {name = job.maker.recipe.fluids[1].name, type = "fluid"}, supplied = plan.supplied[1] and {name = plan.supplied[1].name, type = "fluid"},
  })
  local sizes = {[job.maker.machine] = machine_size_of(job.maker), [job.root.machine] = machine_size_of(job.root)}
  local feeds = {items = item and {items = {{name = item.name, amount = item.amount}}} or nil}
  return {
    raws = plant_raws(job, plan), fluids = names, summaries = {{machines = plan.makers, machine = job.maker.machine}, {machines = plan.plants, machine = job.root.machine}},
    build = function() return plants_block.of_fluid_plant(fluid_plant.build_block(fluid_plant_build(job, plan)), by_key, feeds, sizes) end,
  }
end

-- A chain that makes an item (explosives), planned for the rate of the job.
---@param job bpgen.Job
---@return bpgen.PlannedBlock
local function plan_chain_block(job)
  local plans = assert(plan_item_fluid_chain(job), "generator: the parts of a chain cannot make what the recipe asks of it, though the most they make said they can")
  local block, belts_root, belts_raws = second_item_block(job, plans)
  local sizes = chain_sizes(job, belts_root)
  local by_key, names = fluids_of(chain_things(job, plans))
  return {
    raws = chain_raws(job, plans, belts_raws), fluids = names, summaries = chain_summaries(job, plans),
    build = function() return plants_block.of_chain(item_fluid_chain.build_block(chain_request(job, plans, block, sizes)), by_key, {}, sizes) end,
  }
end

-- A nested chain that makes an item (battery), planned for the rate of the job.
---@param job bpgen.Job
---@return bpgen.PlannedBlock
local function plan_nested_block(job)
  local plans = assert(plan_nested_chain(job), "generator: the parts of a nested chain cannot make what the recipe asks of it, though the most they make said they can")
  local parts = {first = belts_part(plans.first_job, plans.first), second = belts_part(plans.second_job, plans.second), chain = chain_part(plans.chain_job, plans.chain)}
  local sizes = nested_sizes(job, parts)
  local by_key, names = fluids_of(nested_things(parts))
  local summaries = accounting.merged_summaries({parts.first.summaries, parts.second.summaries, parts.chain.summaries, {{machines = plans.final.plants, machine = job.root.machine}}})
  return {
    raws = accounting.merged_raws({parts.first.raws, parts.second.raws, parts.chain.raws}), fluids = names, summaries = summaries,
    build = function() return plants_block.of_nested(item_fluid_chain.build_nested_block(nested_request(job, plans, parts, sizes)), by_key, {}, sizes) end,
  }
end

-- A row of machines that make a fluid (the refineries of petroleum gas), planned for the rate of the job, as the part that makes the fluid of a step.
---@param job bpgen.Job
---@return bpgen.PlannedBlock
local function plan_fluid_row_block(job)
  local stage = job.root
  local plan = assert(planner.plan_fluid_row(fluid_row_request(job)), "generator: the row cannot make what the recipe asks of it, though the most it makes said it can")
  local taken = stage.recipe.fluids[1]
  local crafts = plan.output_per_minute / planner.amount_made(stage.recipe, stage.item)
  local sizes = {[stage.machine] = machine_size_of(stage)}
  return {
    raws = {{name = taken.name, amount = crafts * taken.amount}}, fluids = {[taken.name] = true},
    summaries = {{machines = plan.machines, machine = stage.machine}},
    build = function()
      local entities, entries = fluid_row.build(fluid_row_build(job, stage, plan.machines))
      fluid_row.turn(entities, entries, stage.machine, sizes[stage.machine])
      return plants_block.of_fluid_row({entities = entities, entries = entries}, taken.name, sizes, job.names)
    end,
  }
end

-- A part of a recipe on belts, planned for the rate of the job: the part made in plants (whichever of the three ways to make an item in plants it is) or
-- the part that makes the fluid of the last step (a row of machines or a chain).
---@param job bpgen.Job
---@return bpgen.PlannedBlock
function plan_block(job)
  if job.kind == "fluid_row" then
    return plan_fluid_row_block(job)
  end
  if job.kind == "fluid_plant" then
    return plan_fluid_plant_block(job)
  end
  if job.kind == "item_fluid_chain" then
    return plan_chain_block(job)
  end
  assert(job.kind == "nested_chain", "generator: a part of a recipe is neither a row, plants, a chain nor a nested chain")
  return plan_nested_block(job)
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
function max_rate_of(job)
  if job.kind == "fluid_row" then
    return planner.max_fluid_row_rate(fluid_row_request(job))
  end
  if job.kind == "fluid_plant" then
    return planner.max_fluid_plant_rate(fluid_plant_request(job))
  end
  if job.kind == "item_fluid_chain" then
    return item_fluid_chain_max_rate(job)
  end
  if job.kind == "nested_chain" then
    return nested_chain_max_rate(job)
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
  if job.kind == "nested_chain" then
    return generate_nested_chain(job)
  end

  local planned, refusal = make_plans(job)
  if not planned then
    return nil, refusal
  end

  return assemble(job, planned)
end

return generator
