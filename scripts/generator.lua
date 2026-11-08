-- scripts/generator.lua
-- The one place that reads the game's prototype data (recipes, machines) and
-- connects it to the pure planner and layout modules. Only call it from event
-- handlers: `prototypes` does not exist while control.lua is first loading.

local config = require("scripts.config")
local chain = require("scripts.chain")
local planner = require("scripts.planner")
local layout = require("scripts.layout")
local blocks = require("scripts.blocks")

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

-- Why the recipe tree could not be made, as a message for the player.
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
  if reason == "several-crafted" or reason == "extra-ingredient" or reason == "fork-in-chain" then
    return error_message("error-chain-too-complex", item_label(item_name))
  end
  return error_message("error-unsupported-recipe")
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
    return nil, chain_message(reason, culprit)
  end
  local root = read_stage(stage)
  if not root then
    return nil, error_message("error-missing-prototype")
  end
  return root, nil
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

-- The reason this step's machine cannot be built with, as a message for the player, or nil.
---@param stage bpgen.StageData
---@return LocalisedString|nil
local function stage_problem(stage)
  local size = stage.machine_size
  if not size or not layout.supports_machine_size(size) then
    return error_message("error-unsupported-machine")
  end
  local energy_source = stage.energy_source
  if not energy_source then
    return error_message("error-unsupported-energy")
  end
  if #stage.suppliers > 0 and stage.fuel then
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
  for _, stage in ipairs(in_order(job.root, {})) do
    local problem = stage_problem(stage)
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
---@param planned bpgen.PlannedStage
---@return string
local function describe_blueprint(job, planned)
  local machines = {}
  ---@type number
  local made_per_minute = 0
  for _, step in ipairs(in_order(planned, {})) do
    machines[#machines + 1] = string.format("%d x %s", step.plan.machines, step.stage.machine)
    made_per_minute = step.plan.output_per_minute -- the last step's, the root's, is what counts
  end
  return string.format("%s: %s per minute from %s", job.item_name, format_number(made_per_minute), table.concat(machines, ", "))
end

-- How a step's sentence goes on from the step before it in the list: the first step
-- starts the sentence, and a step fed by other steps says so (the step listed just before
-- it is the last of the steps that feed it). A step fed raw items that is not the first
-- is simply added.
---@param step bpgen.PlannedStage
---@param previous bpgen.PlannedStage|nil  the step listed before it
---@return string
local function stage_key(step, previous)
  if not previous then
    return "blueprint-generation.generated-first-stage"
  end
  if #step.suppliers > 0 then
    return "blueprint-generation.generated-next-stage"
  end
  return "blueprint-generation.generated-other-stage"
end

-- What one step of the tree makes and with what, as a LocalisedString.
---@param step bpgen.PlannedStage
---@param previous bpgen.PlannedStage|nil
---@return LocalisedString
local function stage_message(step, previous)
  return {
    stage_key(step, previous),
    string.format("%d", step.plan.machines),
    prototypes.entity[step.stage.machine].localised_name,
    format_number(step.plan.output_per_minute),
    item_label(step.stage.item),
  } --[[@as LocalisedString]]
end

-- What each step makes, one sentence part after the other, from the raw items to the product.
---@param planned bpgen.PlannedStage
---@return LocalisedString
local function steps_message(planned)
  ---@type LocalisedString
  local steps = {""}
  ---@type bpgen.PlannedStage|nil
  local previous
  for _, step in ipairs(in_order(planned, {})) do
    steps[#steps + 1] = stage_message(step, previous)
    previous = step
  end
  return steps
end

-- The message for a blueprint with one belt of raw items. The entry locale text fills
-- __1__ to __4__ from the values below, in this order: what each step makes (one
-- LocalisedString for all the steps, see `steps_message`), the rate asked, then what
-- goes on the input belt: the first lane's item is __3__ and the second lane's item,
-- when it is a different one (a fuel, or a second ingredient), is __4__. One item on
-- both lanes has an entry of its own, `generated-one-item`, which only has __3__.
---@param job bpgen.Job
---@param steps LocalisedString
---@param lanes string[]  the items on the two lanes of the belt of raw items
---@return LocalisedString
local function one_belt_message(job, steps, lanes)
  local first_lane, second_lane = lanes[1], lanes[2]
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

-- How one belt of raw items is loaded, for the player.
---@param lanes string[]  the items on its two lanes
---@return LocalisedString
local function raw_belt_text(lanes)
  if lanes[1] == lanes[2] then
    return {"blueprint-generation.raw-belt-one-item", item_label(lanes[1])}
  end
  return {"blueprint-generation.raw-belt", item_label(lanes[1]), item_label(lanes[2])}
end

-- The message for a blueprint with several belts of raw items, which come in on the
-- left, from the top down: __3__ lists them in that order.
---@param job bpgen.Job
---@param steps LocalisedString
---@param raw_belts string[][]  the items on the two lanes of each belt of raw items, from the top down
---@return LocalisedString
local function several_belts_message(job, steps, raw_belts)
  ---@type LocalisedString
  local belts = {""}
  for index, lanes in ipairs(raw_belts) do
    if index > 1 then
      belts[#belts + 1] = "; "
    end
    belts[#belts + 1] = raw_belt_text(lanes)
  end
  return {"blueprint-generation.generated-raw-belts", steps, format_number(job.rate_per_minute), belts} --[[@as LocalisedString]]
end

-- The LocalisedString shown to the player when a blueprint is ready.
---@param job bpgen.Job
---@param planned bpgen.PlannedStage
---@param raw_belts string[][]  the items on the two lanes of each belt of raw items, from the top down
---@return LocalisedString
local function success_message(job, planned, raw_belts)
  local steps = steps_message(planned)
  if #raw_belts == 1 then
    return one_belt_message(job, steps, raw_belts[1])
  end
  return several_belts_message(job, steps, raw_belts)
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
    return nil, refusal_message(reason, max_rate)
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

-- What the layout is told about a step and what it eats: the steps that make its
-- ingredients, then the raw item that goes with them, if any, which has no machines and
-- only a belt. A step fed raw items, and the belt of a raw item, are noted in `raw_lanes`,
-- with the items on the lanes of the belt.
---@param step bpgen.PlannedStage
---@param raw_lanes table<bpgen.StageLayout, string[]>
---@return bpgen.StageLayout
local function layout_stage(step, raw_lanes)
  local suppliers = {}
  for index, supplier in ipairs(step.suppliers) do
    suppliers[index] = layout_stage(supplier, raw_lanes)
  end
  local raw_item = step.stage.raw_item
  if raw_item then
    local raw_supplier = {raw_item = raw_item}
    suppliers[#suppliers + 1] = raw_supplier
    raw_lanes[raw_supplier] = {raw_item, raw_item}
  end
  local stage = {
    machine_count = step.plan.machines,
    load = step.plan.load,
    machine = step.stage.machine,
    recipe = recipe_to_set(step.stage),
    shape = {
      machine_size = machine_size_of(step.stage),
      input_inserters = step.plan.input_inserters,
      output_inserters = step.plan.output_inserters,
    },
    suppliers = suppliers,
  }
  if #suppliers == 0 then
    raw_lanes[stage] = step.plan.lanes
  end
  return stage
end

-- Lay out the planned machines and word the results for the player.
---@param job bpgen.Job
---@param planned bpgen.PlannedStage
---@return bpgen.Generated
local function assemble(job, planned)
  local raw_lanes = {}
  local entities, raw_stages = blocks.build(layout_stage(planned, raw_lanes), job.names)
  local raw_belts = {}
  for index, stage in ipairs(raw_stages) do
    raw_belts[index] = raw_lanes[stage]
  end
  return {
    entities = entities,
    description = describe_blueprint(job, planned),
    message = success_message(job, planned, raw_belts),
  }
end

-- The job for this request, with every machine checked, or nil and the message for the player.
---@param item_name string
---@param rate_per_minute number
---@return bpgen.Job|nil
---@return LocalisedString|nil error_message
local function read_buildable_job(item_name, rate_per_minute)
  local job, problem = read_job(item_name, rate_per_minute)
  if not job then
    return nil, problem
  end
  problem = machine_problem(job)
  if problem then
    return nil, problem
  end
  return job, nil
end

-- The line the window shows under the rate field: the most one blueprint of
-- `item_name` can make per minute, or the message for why it cannot be made.
---@param item_name string
---@return LocalisedString
function generator.max_rate_message(item_name)
  local job, problem = read_buildable_job(item_name, 1) -- the rate is not used
  if not job then
    ---@cast problem LocalisedString -- there is always a message when there is no job
    return problem
  end
  local max_rate, reason = planner.max_tree_rate(tree_request(job))
  if not max_rate then
    ---@cast reason bpgen.PlanReason
    return refusal_message(reason)
  end
  return error_message("max-rate", format_number(max_rate))
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
  local job, problem = read_buildable_job(item_name, rate_per_minute)
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
