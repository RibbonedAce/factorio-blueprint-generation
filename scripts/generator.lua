-- scripts/generator.lua
-- The one place that reads the game's prototype data (recipes, machines) and
-- connects it to the pure planner and layout modules. Only call it from event
-- handlers: `prototypes` does not exist while control.lua is first loading.

local config = require("scripts.config")
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

-- Copy a recipe prototype into a plain table for the planner.
---@param recipe_name string
---@return bpgen.Recipe|nil
local function read_recipe(recipe_name)
  local prototype = prototypes.recipe[recipe_name]
  if not prototype then
    return nil
  end

  local recipe = {energy = prototype.energy, ingredients = {}, products = {}}
  for _, ingredient in ipairs(prototype.ingredients) do
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

-- The prototype names the layout is given.
---@param product bpgen.Product
---@return bpgen.Names
local function names_for(product)
  return {
    machine = product.machine,
    belt = config.entities.belt,
    inserter = config.entities.inserter,
    pole = config.entities.pole,
  }
end

---@param names bpgen.Names
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

-- Everything about the game that generating needs, copied into plain values.
-- Returns nil if something is missing (another mod could have removed or renamed
-- it): a building, the recipe, the machine's speed, the belt's speed or the
-- inserter's rotation speed.
---@class bpgen.GameData  the game values generating needs, as plain data
---@field recipe bpgen.Recipe
---@field machine_speed number
---@field machine_size integer|nil  nil when the machine is not square
---@field energy_source bpgen.EnergySource|nil  nil when the machine runs on something unhandled
---@field fuels table<string, true>  the items the machine can burn, empty for an electric one
---@field belt_speed number
---@field inserter_rotation_speed number

---@param product bpgen.Product
---@param names bpgen.Names
---@return bpgen.GameData|nil
local function read_game_data(product, names)
  if not all_entities_exist(names) then
    return nil
  end
  local machine = prototypes.entity[names.machine]
  local recipe = read_recipe(product.recipe)
  local machine_speed = machine.get_crafting_speed()
  -- `belt_speed` is nil unless the entity really is a transport belt, and
  -- the rotation speed is nil unless it really is an inserter.
  local belt_speed = prototypes.entity[names.belt].belt_speed
  local rotation_speed = prototypes.entity[names.inserter].get_inserter_rotation_speed()
  if not (recipe and machine_speed and belt_speed and rotation_speed) then
    return nil
  end
  local energy_source = read_energy_source(machine)
  return {
    recipe = recipe,
    machine_speed = machine_speed,
    machine_size = square_size(machine),
    energy_source = energy_source,
    fuels = burnable_by(energy_source),
    belt_speed = belt_speed,
    inserter_rotation_speed = rotation_speed,
  }
end

-- What one call to `generate` works with, built once and not changed afterwards.
-- The steps below take it instead of the same five values each: what the player
-- asked for, how the config makes it, the prototype names, and the game's numbers.
---@class bpgen.Job
---@field item_name string  what the player wants
---@field rate_per_minute number  how much of it
---@field product bpgen.Product  how the config makes it
---@field names bpgen.Names  the prototype names the layout builds with
---@field game bpgen.GameData  what the game says about them

-- The job for this request, or nil and the message for the player when the item is
-- not supported or something it needs is missing from the game.
---@param item_name string
---@param rate_per_minute number
---@return bpgen.Job|nil
---@return LocalisedString|nil error_message
local function read_job(item_name, rate_per_minute)
  local product = config.products[item_name]
  if not product then
    return nil, error_message("error-unsupported-item")
  end
  local names = names_for(product)
  local game = read_game_data(product, names)
  if not game then
    return nil, error_message("error-missing-prototype")
  end
  return {item_name = item_name, rate_per_minute = rate_per_minute, product = product, names = names, game = game}
end

-- Whether the fuel the config sets for a product suits the machine: an electric
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

-- The reason this machine cannot be built with, as a message for the player, or nil.
---@param job bpgen.Job
---@return LocalisedString|nil
local function machine_problem(job)
  local game = job.game
  local size = game.machine_size
  if not size or not layout.supports_machine_size(size) then
    return error_message("error-unsupported-machine")
  end
  local energy_source = game.energy_source
  if not energy_source then
    return error_message("error-unsupported-energy")
  end
  if not suits_machine(job.product.fuel, energy_source, game.fuels) then
    return error_message("error-fuel-mismatch", prototypes.entity[job.product.machine].localised_name)
  end
  return nil
end

-- Why the planner said no, as a message for the player.
---@param reason string  the planner's refusal reason
---@param max_rate number|nil
---@return LocalisedString
local function refusal_message(reason, max_rate)
  if reason == "rate-too-high" then
    ---@cast max_rate number -- the planner always gives it with this reason
    return error_message("error-rate-too-high", format_number(max_rate))
  end
  return error_message("error-unsupported-recipe")
end

---@param job bpgen.Job
---@param plan bpgen.Plan
---@return string
local function describe_blueprint(job, plan)
  return string.format("%s: %s per minute from %d x %s",
    job.item_name, format_number(plan.output_per_minute), plan.machines, job.product.machine)
end

-- The LocalisedString shown to the player when a blueprint is ready. The locale
-- entry fills __1__ to __5__ from the values below, in this order (machines,
-- machine, rate made, item, rate asked), then says what goes on the input belt:
-- the first lane's item is __6__ and the second lane's item, when it is a
-- different one (a fuel, or a second ingredient), is __7__. One item on both
-- lanes has an entry of its own, `generated-one-item`, which only has __6__.
---@param job bpgen.Job
---@param plan bpgen.Plan
---@return LocalisedString
local function success_message(job, plan)
  local first_lane, second_lane = plan.lanes[1], plan.lanes[2]
  local message = {
    first_lane == second_lane and "blueprint-generation.generated-one-item" or "blueprint-generation.generated",
    string.format("%d", plan.machines),
    prototypes.entity[job.product.machine].localised_name,
    format_number(plan.output_per_minute),
    prototypes.item[job.item_name].localised_name,
    format_number(job.rate_per_minute),
    prototypes.item[first_lane].localised_name,
  }
  if second_lane ~= first_lane then
    message[#message + 1] = prototypes.item[second_lane].localised_name
  end
  return message --[[@as LocalisedString]]
end

-- The machine's size in tiles. `machine_problem` has already refused a machine
-- that has none, so it is there by the time anything asks.
---@param job bpgen.Job
---@return integer
local function machine_size_of(job)
  return job.game.machine_size --[[@as integer]]
end

-- Ask the planner, with the limits the game data gives: the belt lane, and the
-- inserters that feed and empty each machine (as many as the layout leaves room
-- for). Returns the plan, or nil and the message for the player.
---@param job bpgen.Job
---@return bpgen.Plan|nil
---@return LocalisedString|nil error_message
local function make_plan(job)
  local game = job.game
  local machine_size = machine_size_of(job)
  local plan, reason, max_rate = planner.plan{
    product = job.item_name,
    rate_per_minute = job.rate_per_minute,
    recipe = game.recipe,
    machine_speed = game.machine_speed,
    lane_items_per_minute = planner.lane_items_per_minute(game.belt_speed),
    fuel = job.product.fuel,
    inserters = {
      items_per_minute = planner.inserter_items_per_minute(game.inserter_rotation_speed),
      max_input = layout.max_input_inserters(machine_size),
      max_output = layout.max_output_inserters(machine_size),
    },
  }
  if not plan then
    ---@cast reason string -- the planner always gives a reason when it gives no plan
    return nil, refusal_message(reason, max_rate)
  end
  return plan, nil
end

-- Lay out the planned machines and word the results for the player.
---@param job bpgen.Job
---@param plan bpgen.Plan
---@return bpgen.Generated
local function assemble(job, plan)
  local shape = {
    machine_size = machine_size_of(job),
    input_inserters = plan.input_inserters,
    output_inserters = plan.output_inserters,
  }
  return {
    entities = layout.build(plan.machines, job.names, shape),
    description = describe_blueprint(job, plan),
    message = success_message(job, plan),
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

  local plan, refusal = make_plan(job)
  if not plan then
    return nil, refusal
  end

  return assemble(job, plan)
end

return generator
