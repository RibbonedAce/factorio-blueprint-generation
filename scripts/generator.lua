-- scripts/generator.lua
-- The one place that reads the game's prototype data (recipes, machines) and
-- connects it to the pure planner and layout modules. Only call it from event
-- handlers: `prototypes` does not exist while control.lua is first loading.

local config = require("scripts.config")
local chain = require("scripts.chain")
local planner = require("scripts.planner")
local layout = require("scripts.layout")

local generator = {}

-- Turn a number into short text for messages: 56.25 -> "56.25", 60 -> "60".
-- (`string.format` rounds to 2 decimals; the gsub then trims trailing zeros.
-- The extra parentheses keep only gsub's first result, the text.)
---@param value number
---@return string
local function format_number(value)
  return (string.format("%.2f", value):gsub("%.?0+$", ""))
end

-- Copy a recipe prototype into a plain table for the planner. Returns nil for a
-- recipe with a fluid among its ingredients: it would need pipes, which the layout
-- does not build. (A product that is not an item comes with an item product, and
-- the planner refuses a recipe with more than one product.)
---@param prototype LuaRecipePrototype
---@return bpgen.Recipe|nil
local function read_recipe(prototype)
  local recipe = {energy = prototype.energy, ingredients = {}, products = {}}
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

-- A LocalisedString for an error: the key is looked up in the locale file.
---@param key string  a key of the [blueprint-generation] section of the locale file
---@param ... LocalisedString|number|string  values for __1__, __2__ ... in the text
---@return LocalisedString
local function error_message(key, ...)
  return {"blueprint-generation." .. key, ...} --[[@as LocalisedString]]
end

-- The localised name of an item, for messages. An item the game does not have (another
-- mod could have removed one the config names) is shown by its plain name.
---@param item_name string
---@return LocalisedString
local function item_label(item_name)
  local item = prototypes.item[item_name]
  return item and item.localised_name or item_name
end

-- The building blocks every column of the blueprint shares.
---@return bpgen.SharedNames
local function shared_names()
  return {belt = config.entities.belt, inserter = config.entities.inserter, pole = config.entities.pole}
end

---@param names bpgen.SharedNames
---@return boolean
local function all_entities_exist(names)
  for _, entity_name in pairs(names) do
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

-- One step of the chain with what the game says about its machine, copied into plain
-- values. Returns nil if something is missing (another mod could have removed or
-- renamed it): the machine, or its crafting speed.
---@class bpgen.StageData  one step of the chain and the machine that makes it
---@field item string  the item the step makes
---@field recipe bpgen.Recipe
---@field machine string  machine prototype name
---@field fuel string|nil  item the machine burns, set by the config
---@field machine_speed number
---@field machine_size integer|nil  nil when the machine is not square
---@field energy_source bpgen.EnergySource|nil  nil when the machine runs on something unhandled
---@field fuels table<string, true>  the items the machine can burn, empty for an electric one

---@param stage bpgen.ChainStage
---@return bpgen.StageData|nil
local function read_stage(stage)
  local machine = prototypes.entity[stage.machine]
  local machine_speed = machine and machine.get_crafting_speed()
  if not (machine and machine_speed) then
    return nil
  end
  local energy_source = read_energy_source(machine)
  return {
    item = stage.item,
    recipe = stage.recipe,
    machine = stage.machine,
    fuel = stage.fuel,
    machine_speed = machine_speed,
    machine_size = square_size(machine),
    energy_source = energy_source,
    fuels = burnable_by(energy_source),
  }
end

-- What one call to `generate` works with, built once and not changed afterwards.
-- The steps below take it instead of the same values each: what the player asked
-- for, the chain of steps that makes it with their machines, and the game's numbers.
---@class bpgen.Job
---@field item_name string  what the player wants
---@field rate_per_minute number  how much of it
---@field stages bpgen.StageData[]  from the step fed raw items to the one that makes `item_name`
---@field names bpgen.SharedNames  the prototype names every column builds with
---@field belt_speed number
---@field inserter_rotation_speed number

-- Why the chain could not be made, as a message for the player.
---@param reason bpgen.ChainReason
---@param item_name string  the item the reason is about
---@return LocalisedString
local function chain_message(reason, item_name)
  if reason == "no-recipe" then
    return error_message("error-no-recipe", item_label(item_name))
  end
  if reason == "ambiguous" then
    return error_message("error-ambiguous-recipe", item_label(item_name))
  end
  if reason == "several-crafted" or reason == "extra-ingredient" then
    return error_message("error-chain-too-complex", item_label(item_name))
  end
  return error_message("error-unsupported-recipe")
end

-- The steps for an item, each with its machine's data, or nil and the message for the
-- player when the item cannot be made in a chain of machines or the game lacks one.
---@param item_name string
---@return bpgen.StageData[]|nil
---@return LocalisedString|nil error_message
local function read_stages(item_name)
  local steps, reason, culprit = chain.resolve(item_name, lookup_production)
  if not steps then
    ---@cast reason bpgen.ChainReason -- there is always a reason when there are no steps
    ---@cast culprit string
    return nil, chain_message(reason, culprit)
  end
  local stages = {}
  for index, step in ipairs(steps) do
    stages[index] = read_stage(step)
    if not stages[index] then
      return nil, error_message("error-missing-prototype")
    end
  end
  return stages, nil
end

-- The speeds of the belt and of the inserter the layout uses, or nil when one of them
-- is missing from the game. `belt_speed` is nil unless the entity really is a
-- transport belt, and the rotation speed is nil unless it really is an inserter.
---@param names bpgen.SharedNames
---@return number|nil belt_speed
---@return number|nil inserter_rotation_speed
local function read_speeds(names)
  if not all_entities_exist(names) then
    return nil
  end
  return prototypes.entity[names.belt].belt_speed, prototypes.entity[names.inserter].get_inserter_rotation_speed()
end

-- The job for this request, or nil and the message for the player when the item is
-- not supported or something it needs is missing from the game.
---@param item_name string
---@param rate_per_minute number
---@return bpgen.Job|nil
---@return LocalisedString|nil error_message
local function read_job(item_name, rate_per_minute)
  if not config.products[item_name] then
    return nil, error_message("error-unsupported-item")
  end
  local names = shared_names()
  local belt_speed, rotation_speed = read_speeds(names)
  if not (belt_speed and rotation_speed) then
    return nil, error_message("error-missing-prototype")
  end
  local stages, problem = read_stages(item_name)
  if not stages then
    return nil, problem
  end
  return {
    item_name = item_name,
    rate_per_minute = rate_per_minute,
    stages = stages,
    names = names,
    belt_speed = belt_speed,
    inserter_rotation_speed = rotation_speed,
  }
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

-- The reason this step's machine cannot be built with, as a message for the player, or nil.
-- `index` counts the steps from 1, the one fed raw items.
---@param stage bpgen.StageData
---@param index integer
---@return LocalisedString|nil
local function stage_problem(stage, index)
  local size = stage.machine_size
  if not size or not layout.supports_machine_size(size) then
    return error_message("error-unsupported-machine")
  end
  local energy_source = stage.energy_source
  if not energy_source then
    return error_message("error-unsupported-energy")
  end
  if index > 1 and stage.fuel then
    return error_message("error-chain-fuel", item_label(stage.item))
  end
  if not suits_machine(stage.fuel, energy_source, stage.fuels) then
    return error_message("error-fuel-mismatch", prototypes.entity[stage.machine].localised_name)
  end
  return nil
end

-- The reason one of the machines cannot be built with, as a message for the player, or nil.
---@param job bpgen.Job
---@return LocalisedString|nil
local function machine_problem(job)
  for index, stage in ipairs(job.stages) do
    local problem = stage_problem(stage, index)
    if problem then
      return problem
    end
  end
  return nil
end

-- One step of the chain with the plan the planner made for it: the two always
-- travel together.
---@class bpgen.PlannedStage
---@field stage bpgen.StageData
---@field plan bpgen.Plan

-- Why the planner said no, as a message for the player.
---@param reason bpgen.PlanReason
---@param max_rate number|nil
---@return LocalisedString
local function refusal_message(reason, max_rate)
  if reason == "rate-too-high" then
    ---@cast max_rate number -- the planner always gives it with this reason
    return error_message("error-rate-too-high", format_number(max_rate))
  end
  return error_message("error-unsupported-recipe")
end

-- The text for the blueprint's description field: the machines, step by step.
---@param job bpgen.Job
---@param planned bpgen.PlannedStage[]
---@return string
local function describe_blueprint(job, planned)
  local machines = {}
  ---@type number
  local made_per_minute = 0
  for _, step in ipairs(planned) do
    machines[#machines + 1] = string.format("%d x %s", step.plan.machines, step.stage.machine)
    made_per_minute = step.plan.output_per_minute -- the last step's is what counts
  end
  return string.format("%s: %s per minute from %s", job.item_name, format_number(made_per_minute), table.concat(machines, ", "))
end

-- What one step of the chain makes and with what, as a LocalisedString: the first
-- step starts the sentence and each next one carries on from the step before it.
---@param step bpgen.PlannedStage
---@param is_first boolean
---@return LocalisedString
local function stage_message(step, is_first)
  local key = is_first and "blueprint-generation.generated-first-stage" or "blueprint-generation.generated-next-stage"
  return {
    key,
    string.format("%d", step.plan.machines),
    prototypes.entity[step.stage.machine].localised_name,
    format_number(step.plan.output_per_minute),
    item_label(step.stage.item),
  } --[[@as LocalisedString]]
end

-- The items on the two lanes of the belt that brings in the raw items, which is the
-- input belt of the first step.
---@param planned bpgen.PlannedStage[]
---@return string first_lane
---@return string second_lane
local function raw_belt_lanes(planned)
  local first = planned[1]
  ---@cast first bpgen.PlannedStage -- a chain always has a first step
  local first_lane, second_lane = first.plan.lanes[1], first.plan.lanes[2]
  ---@cast first_lane string -- the first step always has an item on each of its two lanes
  ---@cast second_lane string
  return first_lane, second_lane
end

-- The LocalisedString shown to the player when a blueprint is ready. The locale
-- entry fills __1__ to __4__ from the values below, in this order: what each step
-- makes (one LocalisedString for all the steps, see `stage_message`), the rate
-- asked, then what goes on the input belt: the first lane's item is __3__ and the
-- second lane's item, when it is a different one (a fuel, or a second ingredient),
-- is __4__. One item on both lanes has an entry of its own, `generated-one-item`,
-- which only has __3__.
---@param job bpgen.Job
---@param planned bpgen.PlannedStage[]
---@return LocalisedString
local function success_message(job, planned)
  ---@type LocalisedString
  local steps = {""}
  for index, step in ipairs(planned) do
    steps[#steps + 1] = stage_message(step, index == 1)
  end
  local first_lane, second_lane = raw_belt_lanes(planned)
  local message = {
    first_lane == second_lane and "blueprint-generation.generated-one-item" or "blueprint-generation.generated",
    steps,
    format_number(job.rate_per_minute),
    item_label(first_lane),
  }
  if second_lane ~= first_lane then
    message[#message + 1] = item_label(second_lane)
  end
  return message --[[@as LocalisedString]]
end

-- The machine's size in tiles. `machine_problem` has already refused a machine
-- that has none, so it is there by the time anything asks.
---@param stage bpgen.StageData
---@return integer
local function machine_size_of(stage)
  return stage.machine_size --[[@as integer]]
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
      max_input = layout.max_input_inserters(machine_size),
      max_output = layout.max_output_inserters(machine_size),
    },
  }
end

-- Ask the planner, with the limits the game data gives: the belt lane, and the
-- inserters of each step. Returns each step with its plan, or nil and the message
-- for the player.
---@param job bpgen.Job
---@return bpgen.PlannedStage[]|nil
---@return LocalisedString|nil error_message
local function make_plans(job)
  local requests = {}
  for index, stage in ipairs(job.stages) do
    requests[index] = stage_request(job, stage)
  end
  local plans, reason, max_rate = planner.plan_chain{
    rate_per_minute = job.rate_per_minute,
    lane_items_per_minute = planner.lane_items_per_minute(job.belt_speed),
    stages = requests,
  }
  if not plans then
    ---@cast reason bpgen.PlanReason -- the planner always gives a reason when it gives no plans
    return nil, refusal_message(reason, max_rate)
  end
  local planned = {}
  for index, stage in ipairs(job.stages) do
    planned[index] = {stage = stage, plan = plans[index] --[[@as bpgen.Plan]]} -- one plan per step, in the same order
  end
  return planned, nil
end

-- Lay out the planned machines and word the results for the player.
---@param job bpgen.Job
---@param planned bpgen.PlannedStage[]
---@return bpgen.Generated
local function assemble(job, planned)
  local columns = {}
  for index, step in ipairs(planned) do
    columns[index] = {
      machine_count = step.plan.machines,
      machine = step.stage.machine,
      shape = {
        machine_size = machine_size_of(step.stage),
        input_inserters = step.plan.input_inserters,
        output_inserters = step.plan.output_inserters,
      },
    }
  end
  return {
    entities = layout.build_chain(columns, job.names),
    description = describe_blueprint(job, planned),
    message = success_message(job, planned),
  }
end

-- Make the blueprint for `rate_per_minute` of `item_name`.
-- On success returns a table {entities, description, message}:
--   entities     the blueprint entities, ready for set_blueprint_entities
--   description  text for the blueprint's description field
--   message      a LocalisedString to show the player
-- On failure returns nil and a LocalisedString explaining why.
---@param item_name string
---@param rate_per_minute number
---@return bpgen.Generated|nil
---@return LocalisedString|nil error_message
function generator.generate(item_name, rate_per_minute)
  local job, problem = read_job(item_name, rate_per_minute)
  if not job then
    return nil, problem
  end

  problem = machine_problem(job)
  if problem then
    return nil, problem
  end

  local planned, refusal = make_plans(job)
  if not planned then
    return nil, refusal
  end

  return assemble(job, planned)
end

return generator
