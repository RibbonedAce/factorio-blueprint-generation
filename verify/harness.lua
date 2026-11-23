-- verify/harness.lua
-- Generates a blueprint with the repo's own modules from the game's recipes (verify/recipes.lua) and checks it with the validator and
-- the belt tracer of spec/support/. Two environments: `a` has the basic belts, the stone furnace and the assembling machine 1;
-- `b` has the fast belts, the steel furnace and the assembling machine 2 too. Two designs: `new` is a force that has researched
-- everything (the design with one belt of each material), `old` is no force at all (the original design).

-- The game's constants, which the modules read when they load (spec/helper.lua does the same for busted).
rawset(_G, "defines", {
  direction = {north = "north", east = "east", south = "south", west = "west"},
  wire_connector_id = {pole_copper = "pole_copper"},
})

local builders = require("spec.support.builders")
local validator = require("spec.support.blueprint_validator")
local tracer = require("spec.support.belt_tracer")
local recipe_data = require("verify.recipes")

local harness = {}

local ENVIRONMENTS = {
  a = {fast = false, steel = false, assembler2 = false},
  b = {fast = true, steel = true, assembler2 = true},
}

-- The fake game's recipes, items and machines for an environment.
---@param environment table
---@return table prototypes
local function fake_game(environment)
  local recipes, items = {}, {}
  for name, recipe in pairs(require("verify.recipes")) do
    local ingredients, products = {}, {}
    for _, ingredient in ipairs(recipe.ingredients) do
      if ingredient[3] == "fluid" then
        ingredients[#ingredients + 1] = builders.fluid_of(ingredient[2], ingredient[1])
      else
        ingredients[#ingredients + 1] = builders.amount_of(ingredient[2], ingredient[1])
        items[#items + 1] = ingredient[1]
      end
    end
    for _, result in ipairs(recipe.results) do
      products[#products + 1] = builders.amount_of(result[2], result[1])
      items[#items + 1] = result[1]
    end
    recipes[name] = builders.a_recipe{energy = recipe.energy, ingredients = ingredients, products = products, categories = recipe.categories}
  end
  return builders.fake_prototypes{
    items = items, recipes = recipes, fast_belts = environment.fast,
    machines = {
      ["assembling-machine-1"] = {crafting_speed = 0.5, width = 3, height = 3},
      ["assembling-machine-2"] = {crafting_speed = 0.75, width = 3, height = 3, fluid_input = true},
      ["steel-furnace"] = environment.steel and {type = "furnace", crafting_speed = 2, width = 2, height = 2, burns = {"chemical"}, energy_usage = 1500} or nil,
    },
  }
end

-- Remembers what each machine of a blueprint eats and makes, under a name of its own, which the tracer needs.
---@param inst table
---@param root table  the first stage of the layout
---@param request table  the planner's request for it
local function note_machines(inst, root, request)
  local function walk(stage_layout, node)
    local id = stage_layout.machine .. "|" .. node.stage.product .. (stage_layout.shape.second_input_belt and "|wide" or "")
    stage_layout.machine = id
    local eats = {}
    for _, input in ipairs(node.stage.recipe.ingredients or {}) do eats[#eats + 1] = input.name end
    if node.stage.fuel and #stage_layout.suppliers > 0 then eats[#eats + 1] = node.stage.fuel end -- a furnace in a chain takes its fuel from the belt of its plates
    inst.info[id] = {
      size = stage_layout.shape.machine_size, product = node.stage.product, furnace = stage_layout.shape.machine_size == 2,
      eats = eats, raw = #stage_layout.suppliers == 0, wide = stage_layout.shape.second_input_belt == true, fluid = stage_layout.shape.fluid_input == true,
    }
    local made = 0
    for _, supplier in ipairs(stage_layout.suppliers) do
      if not supplier.raw_item then
        made = made + 1
        walk(supplier, node.suppliers[made])
      end
    end
  end
  walk(root, request)
end

-- The belts of raw items that no furnace smelts (wood) start at the west end of their row.
---@param grid table
---@param entities table[]
---@param raw_stages table[]
---@param belt string
---@return table[] supplies
local function raw_supplies(grid, entities, raw_stages, belt)
  local supplies = {}
  for index, stage in ipairs(raw_stages) do
    if stage.raw_item then
      local west
      for _, entity in ipairs(entities) do
        local tile = grid.top_left_tile(entity.position, 1, 1)
        if entity.name == belt and tile.y == index - 1 then
          west = math.min(west or tile.x, tile.x)
        end
      end
      supplies[#supplies + 1] = {x = west, y = index - 1, item = stage.raw_item}
    end
  end
  return supplies
end

-- A fresh set of the repo's modules, watched so that every blueprint says what its machines eat and make.
---@param environment table
---@param design "new"|"old"
---@return table inst  with `generate(recipe, rate)` and `check(result)`
local function instance(environment, design)
  for name in pairs(package.loaded) do
    if name:match("^scripts%.") then package.loaded[name] = nil end
  end
  local generator, planner, rows, grid = require("scripts.generator"), require("scripts.planner"), require("scripts.rows"), require("scripts.grid")
  local inst = {info = {}, inputs = {}}
  local request
  local plan_tree, build, build_pure = planner.plan_tree, rows.build, rows.build_pure
  planner.plan_tree = function(tree_request) request = tree_request.root; return plan_tree(tree_request) end
  rows.build = function(root, names)
    note_machines(inst, root, request)
    local entities, raw_stages, entries = build(root, names)
    inst.inputs = raw_supplies(grid, entities, raw_stages, names.belt)
    return entities, raw_stages, entries
  end
  rows.build_pure = function(root, names, options)
    note_machines(inst, root, request)
    local entities, supplies = build_pure(root, names, options)
    inst.inputs = supplies
    return entities, supplies
  end
  local locked = environment.assembler2 and {} or {"assembling-machine-2"}
  local force = builders.fake_force{locked = locked}
  function inst.generate(recipe, rate)
    inst.info, inst.inputs = {}, {}
    local result = generator.generate(recipe, rate, design == "new" and force or nil)
    return result and {entities = result.entities, info = inst.info, inputs = inst.inputs, product = recipe_data[recipe].results[1][1]}
  end
  function inst.check(result)
    return harness.problems(result, environment, design)
  end
  return inst
end

-- What the validator and the belt tracer find wrong with a blueprint (an empty list when it is sound).
---@param result table
---@param environment table
---@param design "new"|"old"
---@return string[]
function harness.problems(result, environment, design)
  local catalog = builders.a_catalog{pole_supply_radius = 2.5, pole_wire_reach = 7.5}
  local machines, raw, raw_lanes, raw_second_lanes = {}, {}, {}, {}
  for id, info in pairs(result.info) do
    catalog[id] = {kind = "machine", width = info.size, height = info.size, needs_power = info.size == 3, fluid_input = info.fluid or nil}
    machines[id] = {size = info.size, eats = info.eats, makes = info.product}
    if info.raw then
      raw[id] = true
      raw_lanes[id] = info.furnace and {info.eats[1], "coal"} or info.eats
      if info.wide then raw_second_lanes[id] = {info.eats[1]} end
    end
  end
  local problems = validator.validate(result.entities, catalog)
  local options = {machines = machines, raw = raw, product = result.product, supplies = result.inputs}
  if design == "new" then
    options.raw_lanes, options.raw_second_lanes, options.underground_reach = raw_lanes, raw_second_lanes, environment.fast and 7 or 5
    if environment.fast then
      options.belt, options.splitter, options.underground = "fast-transport-belt", "fast-splitter", "fast-underground-belt"
    end
  end
  for _, problem in ipairs(tracer.problems(result.entities, options)) do
    problems[#problems + 1] = problem
  end
  return problems
end

-- The generators of an environment, one for each design: sets the fake game too.
---@param letter "a"|"b"
---@return table  {new = inst, old = inst}
function harness.environment(letter)
  local environment = assert(ENVIRONMENTS[letter], "verify: no environment " .. tostring(letter))
  _G.prototypes = fake_game(environment)
  return {new = instance(environment, "new"), old = instance(environment, "old")}
end

return harness
