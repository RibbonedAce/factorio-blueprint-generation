-- scripts/generator.lua
-- The one place that reads the game's prototype data (recipes, machines) and
-- connects it to the pure planner and layout modules. Only call it from event
-- handlers: `prototypes` does not exist while control.lua is first loading.

local config = require("scripts.config")
local chain = require("scripts.chain")
local planner = require("scripts.planner")
local layout = require("scripts.layout")
local inputs = require("scripts.inputs")
local rows = require("scripts.rows")
local lights = require("scripts.lights")
local messages = require("scripts.messages")

local generator = {}

-- Copy a recipe prototype into a plain table for the planner. Returns nil for a
-- recipe with a fluid among its ingredients: it would need pipes, which the layout
-- does not build. (A product that is not an item comes with an item product, and
-- the planner refuses a recipe with more than one product.)
---@param prototype LuaRecipePrototype
---@return bpgen.Recipe|nil
local function read_recipe(prototype)
  local recipe = {name = prototype.name, energy = prototype.energy, ingredients = {}, products = {}}
  for _, ingredient in ipairs(prototype.ingredients) do
    if ingredient.type ~= "item" then
      return nil
    end
    recipe.ingredients[#recipe.ingredients + 1] = {name = ingredient.name, amount = ingredient.amount}
  end
  for index, product in ipairs(prototype.products) do
    -- get_product_amount gives the average amount per craft, which also covers
    -- products with a random or ranged amount.
    recipe.products[#recipe.products + 1] = {name = product.name, amount = prototype.get_product_amount(index)}
  end
  return recipe
end

-- Whether the force can build a building: it has unlocked the recipe, which the game names like the
-- building, and the building exists.
---@param force LuaForce
---@param name string
---@return boolean
local function can_build(force, name)
  local recipe = force.recipes[name]
  return recipe ~= nil and recipe.enabled and prototypes.entity[name] ~= nil
end

-- The pole the blueprint is built with: the medium electric pole once the force has unlocked it (nothing is known
-- without a force) and the game has it, else the small one, which every blueprint can count on.
---@param force LuaForce|nil
---@return string
local function pole_name(force)
  if force and can_build(force, config.entities.medium_pole) then
    return config.entities.medium_pole
  end
  return config.entities.pole
end

-- The belt, the splitter and the underground belt of the blueprint: the fast ones once the force has unlocked all three
-- (nothing is known without a force) and the game has them, else the basic ones. All three or none: a basic splitter or
-- underground belt in the line of a fast belt would carry half of what the belt does, and the lanes the planner counts
-- would not arrive. The game unlocks them together (logistics 2).
---@param force LuaForce|nil
---@return string belt
---@return string splitter
---@return string underground
local function belt_names(force)
  local entities = config.entities
  if force and can_build(force, entities.fast_belt) and can_build(force, entities.fast_splitter) and can_build(force, entities.fast_underground_belt) then
    return entities.fast_belt, entities.fast_splitter, entities.fast_underground_belt
  end
  return entities.belt, entities.splitter, entities.underground_belt
end

-- The building blocks every column of the blueprint shares, but for the numbers of the pole (see `add_pole_distances`).
---@param force LuaForce|nil  whose research decides the pole and the belts
---@return bpgen.SharedNames
local function shared_names(force)
  local belt, splitter, underground = belt_names(force)
  return {
    belt = belt, inserter = config.entities.inserter,
    long_inserter = config.entities.long_inserter, fast_inserter = config.entities.fast_inserter, pole = pole_name(force),
    lamp = config.entities.lamp,
    splitter = splitter, underground = underground,
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
-- without one is not refused (it gets the plain inserter's speed for it). Whether the
-- player has UNLOCKED these recipes is a separate question (see `locked_item`).
---@param names bpgen.SharedNames
---@return boolean
local function all_entities_exist(names)
  for _, entity_name in ipairs({names.belt, names.inserter, names.pole}) do
    if not prototypes.entity[entity_name] then
      return false
    end
  end
  return true
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
---@return bpgen.Production|nil
---@return "unsupported"|nil reason
local function production_of(candidate)
  local recipe = read_recipe(candidate.prototype)
  if recipe then
    return {recipe = recipe, machine = candidate.choice.machine, fuel = candidate.choice.fuel}
  end
  return nil, "unsupported"
end

-- How the game makes an item, in the shape `chain.resolve` asks for (see `bpgen.RecipeLookup`).
---@param item_name string
---@return bpgen.Production|nil
---@return bpgen.ChainReason|nil reason
local function lookup_production(item_name)
  local candidates = candidate_recipes(item_name)
  local only = candidates[1]
  if only and #candidates == 1 then
    return production_of(only)
  end
  if #candidates == 0 then
    return nil, "no-recipe"
  end
  return nil, "ambiguous"
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
    machine_speed = machine_speed, machine_size = square_size(machine),
    energy_source = energy_source, fuels = burnable_by(energy_source), suppliers = suppliers,
    raw_item = stage.raw_item,
  }
end

-- What one call to `generate` works with, built once and not changed afterwards.
-- The steps below take it instead of the same values each: what the player asked
-- for, the tree of steps that makes it with their machines, and the game's numbers.
---@class bpgen.Job
---@field item_name string  what the player wants
---@field rate_per_minute number  how much of it
---@field root bpgen.StageData  the step that makes `item_name`, with the steps below it
---@field names bpgen.SharedNames  the prototype names every column builds with
---@field belt_speed number
---@field inserter_rotation_speed number
---@field long_inserter_rotation_speed number  the long-handed inserter's, or the plain inserter's when the game has none
---@field fast_inserter_rotation_speed? number  the fast inserter's, when the force has researched it and the game gives its speed; nil: plain inserters only
---@field lamp_supply_distance? number  how far a pole powers, when the blueprint gets lamps (the force has unlocked the small lamp); nil: no lamps
---@field inputs? bpgen.InputOptions  asks for the design that brings in one belt of each material (see scripts/inputs.lua); nil for the original design, a belt of raw items for every chain

-- The rotation speed of the fast inserter when the blueprint may use it: the force has unlocked its recipe (nothing is
-- known without a force) and the game has the building and says how fast it swings. Nil otherwise: the blueprint then
-- takes plain inserters only, as it always did.
---@param names bpgen.SharedNames
---@param force LuaForce|nil
---@return number|nil
local function fast_rotation_speed(names, force)
  if not (force and names.fast_inserter and can_build(force, names.fast_inserter)) then
    return nil
  end
  return prototypes.entity[names.fast_inserter].get_inserter_rotation_speed()
end

-- How far the pole powers (2.5 tiles for a small pole) if the blueprint gets lamps: the force has unlocked the small
-- lamp (nothing is known without a force) and the game has it. Nil otherwise: the blueprint then has no lamps, as it
-- never had.
---@param names bpgen.SharedNames  with the numbers of its pole
---@param force LuaForce|nil
---@return number|nil
local function lamp_distance(names, force)
  if not (force and names.lamp and can_build(force, names.lamp)) then
    return nil
  end
  return names.pole_supply_distance
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
  if not (force and can_build(force, names.splitter) and can_build(force, names.underground)) then
    return nil
  end
  local reach = prototypes.entity[names.underground].max_underground_distance
  if not (reach and reach >= inputs.MIN_REACH) then
    return nil
  end
  return {lane_items_per_minute = planner.lane_items_per_minute(belt_speed), underground_reach = reach}
end

-- The steps for an item with the data of their machines, or nil and the message for
-- the player when the item cannot be made from steps we can build or the game lacks
-- a machine.
---@param item_name string
---@return bpgen.StageData|nil
---@return LocalisedString|nil error_message
local function read_root(item_name)
  local stage, reason, culprit = chain.resolve(item_name, lookup_production)
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

-- The speeds of the belt and of the inserters the layout uses, or nil when the belt or
-- the plain inserter is missing from the game. `belt_speed` is nil unless the entity
-- really is a transport belt, and the rotation speeds are nil unless they really are
-- inserters. A game without a long-handed inserter gets the plain inserter's speed for it.
---@param names bpgen.SharedNames
---@return number|nil belt_speed
---@return number|nil inserter_rotation_speed
---@return number|nil long_inserter_rotation_speed
local function read_speeds(names)
  if not all_entities_exist(names) then
    return nil
  end
  local inserter_speed = prototypes.entity[names.inserter].get_inserter_rotation_speed()
  local long = prototypes.entity[names.long_inserter]
  local long_speed = long and long.get_inserter_rotation_speed() or inserter_speed
  return prototypes.entity[names.belt].belt_speed, inserter_speed, long_speed
end

-- The job for this request, or nil and the message for the player when the item is
-- not supported or something it needs is missing from the game.
---@param item_name string
---@param rate_per_minute number
---@param force LuaForce|nil  whose research decides the design of the inputs; nil takes the original
---@return bpgen.Job|nil
---@return LocalisedString|nil error_message
local function read_job(item_name, rate_per_minute, force)
  if not config.products[item_name] then
    return nil, messages.unsupported_item()
  end
  local names = shared_names(force)
  local belt_speed, rotation_speed, long_rotation_speed = read_speeds(names)
  if not (belt_speed and rotation_speed and long_rotation_speed) then
    return nil, messages.missing_prototype()
  end
  add_pole_distances(names)
  local root, problem = read_root(item_name)
  if not root then
    return nil, problem
  end
  return {
    item_name = item_name,
    rate_per_minute = rate_per_minute,
    root = root,
    names = names,
    belt_speed = belt_speed,
    inserter_rotation_speed = rotation_speed,
    long_inserter_rotation_speed = long_rotation_speed,
    fast_inserter_rotation_speed = fast_rotation_speed(names, force),
    lamp_supply_distance = lamp_distance(names, force),
    inputs = input_options(names, belt_speed, force),
  }
end

-- The item whose recipe the force has not unlocked yet, or nil when the force has it. Only
-- the recipe of the product is looked at (owner, 2026-11-08): in the game a recipe is never
-- unlocked before those of its ingredients, nor before the crafting machine it needs, and
-- the buildings (long-handed inserter, belt, inserter, pole) are left to a later feature
-- that will unlock by the entities a blueprint places. A recipe the force does not know at
-- all is not held against it: there is nothing to unlock.
---@param job bpgen.Job
---@param force LuaForce
---@return string|nil item
local function locked_item(job, force)
  local recipe = force.recipes[job.root.recipe.name or job.root.item]
  if recipe and not recipe.enabled then
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
  if #stage.suppliers ~= 1 or #stage.recipe.ingredients ~= 1 then
    return messages.chain_fuel(stage.item)
  end
  if not has_inputs then
    return messages.fuel_needs_inputs(stage.item)
  end
  return nil
end

-- The reason this step's machine cannot be built with, as a message for the player, or nil.
---@param stage bpgen.StageData
---@param has_inputs boolean  whether the design that brings in one belt of each material is available
---@return LocalisedString|nil
local function stage_problem(stage, has_inputs)
  local size = stage.machine_size
  if not size or not layout.supports_machine_size(size) then
    return messages.unsupported_machine()
  end
  local energy_source = stage.energy_source
  if not energy_source then
    return messages.unsupported_energy()
  end
  local problem = fuel_problem(stage, has_inputs)
  if problem then
    return problem
  end
  if not suits_machine(stage.fuel, energy_source, stage.fuels) then
    return messages.fuel_mismatch(prototypes.entity[stage.machine].localised_name)
  end
  return nil
end

-- The reason one of the machines cannot be built with, as a message for the player, or nil.
---@param job bpgen.Job
---@return LocalisedString|nil
local function machine_problem(job)
  for _, stage in ipairs(in_order(job.root, {})) do
    local problem = stage_problem(stage, job.inputs ~= nil)
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
---@field demand? bpgen.Demand[]  what the step takes itself of raw items and fuel a minute, once `raw_amounts` has run

---@class bpgen.Demand  how much of one raw item or fuel a step takes a minute
---@field name string
---@field amount number
---@field is_fuel? boolean

-- The machines of every step, from the first to the last, for the blueprint's description.
---@param planned bpgen.PlannedStage
---@return bpgen.StepSummary[]
local function step_summaries(planned)
  local steps = {}
  for _, step in ipairs(in_order(planned, {})) do
    steps[#steps + 1] = {machines = step.plan.machines, machine = step.stage.machine}
  end
  return steps
end

-- What one step takes itself a minute when it makes `crafts` crafts a minute: the ingredients
-- no step makes, which are raw, then, in a machine that burns fuel, the fuel the machines burn
-- while crafting.
---@param step bpgen.PlannedStage
---@param crafts number
---@param made_by table<string, bpgen.PlannedStage>  the steps below it, by the item they make
---@return bpgen.Demand[]
local function own_demand(step, crafts, made_by)
  local stage, demand = step.stage, {}
  for _, ingredient in ipairs(stage.recipe.ingredients) do
    if not made_by[ingredient.name] then
      demand[#demand + 1] = {name = ingredient.name, amount = crafts * ingredient.amount}
    end
  end
  if stage.fuel and stage.fuel_use then
    local machines_working = crafts * stage.recipe.energy / (60 * stage.machine_speed)
    demand[#demand + 1] = {name = stage.fuel, amount = machines_working * stage.fuel_use, is_fuel = true}
  end
  return demand
end

-- Adds what a step takes to the totals, noting an item the first time it is seen.
---@param totals {order: string[], fuel_order: string[], amount: table<string, number>}
---@param entry bpgen.Demand
local function add_to_totals(totals, entry)
  if not totals.amount[entry.name] then
    totals.amount[entry.name] = 0
    local order = entry.is_fuel and totals.fuel_order or totals.order
    order[#order + 1] = entry.name
  end
  totals.amount[entry.name] = totals.amount[entry.name] + entry.amount
end

-- The raw items (and the fuel) the blueprint uses, a minute at the rate it really makes: the
-- step is asked to make `makes` items a minute, so it needs so many crafts, so many of each
-- ingredient (the steps that make an ingredient are asked for that much in turn; an
-- ingredient no step makes is raw) and, in a machine that burns fuel, the fuel the machines
-- burn while crafting (see `own_demand`). `totals.order` lists the raw items in the order the
-- steps need them, from the first step; `totals.fuel_order` the fuels, which go after them.
---@param step bpgen.PlannedStage  gets its `demand`
---@param makes number  how many of the step's item it is asked for
---@param totals {order: string[], fuel_order: string[], amount: table<string, number>}
local function add_demand(step, makes, totals)
  local crafts = makes / planner.amount_made(step.stage.recipe, step.stage.item)
  local made_by = {}
  for _, supplier in ipairs(step.suppliers) do
    made_by[supplier.stage.item] = supplier
  end
  for _, ingredient in ipairs(step.stage.recipe.ingredients) do
    if made_by[ingredient.name] then
      add_demand(made_by[ingredient.name], crafts * ingredient.amount, totals)
    end
  end
  step.demand = own_demand(step, crafts, made_by)
  for _, entry in ipairs(step.demand) do
    add_to_totals(totals, entry)
  end
end

-- How much of each raw item, then of each fuel, the blueprint uses a minute when its
-- machines make what they really make (which can be more than was asked).
---@param planned bpgen.PlannedStage
---@return bpgen.RawAmount[]
local function raw_amounts(planned)
  local totals = {order = {}, fuel_order = {}, amount = {}}
  add_demand(planned, planned.plan.output_per_minute, totals)
  local raws = {}
  for _, names in ipairs({totals.order, totals.fuel_order}) do
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
  return job.inputs ~= nil and stage.raw_item == nil
    and stage.fuel ~= nil and layout.pole_reach(job.names.pole_supply_distance) > machine_size
end

-- What the planner is told about one step: the inserters that feed and empty each
-- of its machines, as many as the layout leaves room for.
---@param job bpgen.Job
---@param stage bpgen.StageData
---@return bpgen.StageRequest
local function stage_request(job, stage)
  local machine_size = machine_size_of(stage)
  return {
    product = stage.item,
    recipe = stage.recipe,
    machine_speed = stage.machine_speed,
    fuel = stage.fuel,
    inserters = {
      items_per_minute = planner.inserter_items_per_minute(job.inserter_rotation_speed),
      long_items_per_minute = planner.inserter_items_per_minute(job.long_inserter_rotation_speed),
      fast_items_per_minute = job.fast_inserter_rotation_speed and planner.inserter_items_per_minute(job.fast_inserter_rotation_speed) or nil,
      max_input = layout.max_input_inserters(machine_size),
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

-- Whether the product of a step rides belt b of the stage that eats it, the belt that
-- long-handed inserters take from (see `bpgen.Belts`).
---@param plan bpgen.Plan  of the stage that eats it
---@param item string  what the step makes
---@return boolean
local function rides_belt_b(plan, item)
  for _, name in ipairs(plan.belts.b) do
    if name == item then
      return true
    end
  end
  return false
end

-- What a step takes from the belts that come in, for the design that brings in one belt of each
-- material: its raw ingredients, then the fuel. A step with made ingredients takes either one raw
-- item and no fuel (the feed of its raw column), or only fuel (`fuel_problem` allows nothing else).
---@param step bpgen.PlannedStage  with its `demand`
---@return bpgen.Feed
local function feed_of(step)
  local items = {}
  for _, entry in ipairs(step.demand) do
    items[#items + 1] = {name = entry.name, amount = entry.amount}
  end
  return {items = items}
end

-- What a step built wide takes from its two input belts: of its ingredient, as much as one lane carries on the first belt
-- (the fuel on the other lane) and the rest on both lanes of the second.
---@param step bpgen.PlannedStage  with its `demand`
---@param lane number  what one lane of a belt carries a minute
---@return bpgen.Feed first
---@return bpgen.Feed second
local function wide_feeds(step, lane)
  local first, second = {}, {}
  for _, entry in ipairs(step.demand) do
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
---@param step bpgen.PlannedStage  with its `demand`
---@param lane number  what one lane of a belt carries a minute
---@return bpgen.Feed|nil feed
---@return bpgen.Feed|nil second_feed
---@return bpgen.Feed|nil fuel_feed
local function feeds_of(step, lane)
  if #step.suppliers > 0 then
    return nil, nil, step.stage.fuel and feed_of(step) or nil
  end
  if step.plan.wide then
    local feed, second_feed = wide_feeds(step, lane)
    return feed, second_feed, nil
  end
  return feed_of(step), nil, nil
end

-- The size of a step's machines and how many inserters each has, as the layout wants it: a step built wide has its second
-- input belt, its poles beside the output side and its output belt winding for machines in twos. A step built wide that is
-- fed by another one (steel plate from iron plate) has a belt of fuel of its own, woven with the belt before it, instead.
---@param step bpgen.PlannedStage
---@return bpgen.Shape
local function shape_of(step)
  local wide = step.plan.wide
  local fuel_belt = wide and #step.suppliers > 0
  return {
    machine_size = machine_size_of(step.stage),
    input_inserters = step.plan.input_inserters,
    input_fast = step.plan.input_fast,
    long_inserters = step.plan.long_inserters,
    output_inserters = step.plan.output_inserters,
    output_fast = step.plan.output_fast,
    output_paired = wide,
    powered_from_output = wide,
    second_input_belt = wide and not fuel_belt,
    fuel_belt = fuel_belt,
  }
end

-- What the layout is told about a step and what it eats: the steps that make its
-- ingredients, each saying which belt of this step it rides, then the raw item that goes
-- with them, if any, which has no machines and only a belt (on belt a). A step that eats only
-- raw items also says what it takes of them (`feed`), which `rows.build_pure` uses.
---@param step bpgen.PlannedStage  with its `demand`
---@param lane number  what one lane of a belt carries a minute
---@return bpgen.StageLayout
local function layout_stage(step, lane)
  local suppliers = {}
  for index, supplier in ipairs(step.suppliers) do
    suppliers[index] = layout_stage(supplier, lane)
    suppliers[index].belt = rides_belt_b(step.plan, supplier.stage.item) and "b" or "a"
  end
  local raw_item = step.stage.raw_item
  if raw_item then
    suppliers[#suppliers + 1] = {raw_item = raw_item, feed = feed_of(step)}
  end
  local feed, second_feed, fuel_feed = feeds_of(step, lane)
  return {
    machine_count = step.plan.machines,
    load = step.plan.load,
    machine = step.stage.machine,
    recipe = recipe_to_set(step.stage),
    shape = shape_of(step),
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
local function build_entities(job, planned)
  local root = layout_stage(planned, planner.lane_items_per_minute(job.belt_speed))
  if not job.inputs then
    return (rows.build(root, job.names)), nil, root
  end
  local entities, supplies = rows.build_pure(root, job.names, job.inputs)
  local belts = {}
  for index, supply in ipairs(supplies) do
    belts[index] = supply.item
  end
  return entities, belts, root
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
    size_of = function(entity) return inputs.footprint(entity, job.names, sizes) end,
  })
end

-- Lay out the planned machines and word the results for the player.
---@param job bpgen.Job
---@param planned bpgen.PlannedStage
---@return bpgen.Generated
local function assemble(job, planned)
  local raws = raw_amounts(planned) -- also notes what each step takes, which the layout needs
  local entities, belts, root = build_entities(job, planned)
  add_lights(job, entities, root)
  return {
    entities = entities,
    description = messages.description(job.item_name, planned.plan.output_per_minute, step_summaries(planned)),
    message = messages.ready(planned.plan.output_per_minute, planned.stage.item, raws, belts),
  }
end

-- The job for this request, with every machine checked, or nil and the message for the
-- player. With a `force`, an item whose recipe the force has not unlocked is refused too.
---@param item_name string
---@param rate_per_minute number
---@param force LuaForce|nil
---@return bpgen.Job|nil
---@return LocalisedString|nil error_message
local function read_buildable_job(item_name, rate_per_minute, force)
  local job, problem = read_job(item_name, rate_per_minute, force)
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

-- The products the item picker offers a force: every product of the config except those
-- whose recipe the force has not unlocked (see `locked_item`). A product that cannot be
-- made for another reason stays in the list, so choosing it still shows the message that
-- says why.
---@param force LuaForce
---@return string[] names  sorted
function generator.unlocked_products(force)
  local names = {}
  for name in pairs(config.products) do
    local job = read_job(name, 1) -- the rate is not used
    if not (job and locked_item(job, force)) then
      names[#names + 1] = name
    end
  end
  table.sort(names)
  return names
end

-- The line the window shows under the rate field: the most one blueprint of
-- `item_name` can make per minute, or the message for why it cannot be made.
---@param item_name string
---@param force LuaForce|nil  whose unlocked recipes count; nil counts them all
---@return LocalisedString
function generator.max_rate_message(item_name, force)
  local job, problem = read_buildable_job(item_name, 1, force) -- the rate is not used
  if not job then
    ---@cast problem LocalisedString -- there is always a message when there is no job
    return problem
  end
  local max_rate, reason = planner.max_tree_rate(tree_request(job))
  if not max_rate then
    ---@cast reason bpgen.PlanReason
    return messages.plan_problem(reason)
  end
  return messages.max_rate(max_rate)
end

-- Make the blueprint for `rate_per_minute` of `item_name`.
-- On success returns a table {entities, description, message}:
--   entities     the blueprint entities, ready for set_blueprint_entities
--   description  text for the blueprint's description field
--   message      a LocalisedString to show the player
-- On failure returns nil and a LocalisedString explaining why.
---@param item_name string
---@param rate_per_minute number
---@param force LuaForce|nil  whose unlocked recipes count; nil counts them all
---@return bpgen.Generated|nil
---@return LocalisedString|nil error_message
function generator.generate(item_name, rate_per_minute, force)
  local job, problem = read_buildable_job(item_name, rate_per_minute, force)
  if not job then
    return nil, problem
  end

  local planned, refusal = make_plans(job)
  if not planned then
    return nil, refusal
  end

  return assemble(job, planned)
end

return generator
