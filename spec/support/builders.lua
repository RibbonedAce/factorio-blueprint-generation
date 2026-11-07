-- spec/support/builders.lua
-- Helpers that build the plain data the tests need, so a test body only has to
-- spell out the values its assertions depend on.
--
-- The rule for using them: a value a test's expectation depends on is passed in
-- by the test itself (`a_catalog{pole_wire_reach = 7}`), never left to a default
-- that the reader cannot see. Defaults are only for things the test does not care about.

local grid = require("scripts.grid")

local builders = {}

-- The prototype names the layout is given. They are labels here, nothing more.
---@type bpgen.Names
builders.NAMES = {
  machine = "stone-furnace",
  belt = "transport-belt",
  inserter = "inserter",
  pole = "small-electric-pole",
}

-- `{name = "iron-ore", amount = 1}` written as `amount_of(1, "iron-ore")`.
---@param amount number
---@param name string
---@return bpgen.RecipeItem
function builders.amount_of(amount, name)
  return {name = name, amount = amount}
end

--------------------------------------------------------------------------------
-- Blueprint entities. Positions are given as TILES: the top-left tile the entity
-- covers (see scripts/grid.lua), so `furnace(2, 0)` covers tiles x 2 to 3 and
-- y 0 to 1. The entity's centre position, which Factorio wants, is worked out
-- for you. Entity numbers are added by `blueprint_of`. Fractions are allowed to
-- build entities that are NOT lined up with the grid: `inserter(0.75, 0, ...)`.
--------------------------------------------------------------------------------

local MACHINE_SIZE = 2

-- Belts default to running south, like the generated ones; pass a direction to change that.
---@param tile_x number
---@param tile_y number
---@param direction? defines.direction  default south
---@return table  an entity without its number yet (see `blueprint_of`)
function builders.belt(tile_x, tile_y, direction)
  return {name = builders.NAMES.belt, position = grid.position(tile_x, tile_y), direction = direction or defines.direction.south}
end

---@param tile_x number
---@param tile_y number
---@return table  an entity without its number yet (see `blueprint_of`)
function builders.furnace(tile_x, tile_y)
  return {name = builders.NAMES.machine, position = grid.position(tile_x, tile_y, MACHINE_SIZE, MACHINE_SIZE)}
end

---@param tile_x number
---@param tile_y number
---@param direction? defines.direction
---@return table  an entity without its number yet (see `blueprint_of`)
function builders.inserter(tile_x, tile_y, direction)
  return {name = builders.NAMES.inserter, position = grid.position(tile_x, tile_y), direction = direction}
end

-- Poles can be given another prototype name, for tests that need a second kind of pole.
---@param tile_x number
---@param tile_y number
---@param name? string  another pole prototype name
---@return table  an entity without its number yet (see `blueprint_of`)
function builders.pole(tile_x, tile_y, name)
  return {name = name or builders.NAMES.pole, position = grid.position(tile_x, tile_y)}
end

-- Gives the entities their numbers (1, 2, 3, ... in the order passed) and
-- returns them as a list, the way a blueprint holds them.
---@param ... table  entities from the builders above
---@return bpgen.Entity[]
function builders.blueprint_of(...)
  local entities = {...}
  for index, entity in ipairs(entities) do
    entity.entity_number = index
  end
  return entities
end

-- Adds a copper wire from pole `from` to pole `to`. Both must already be numbered
-- (see `blueprint_of`). The wire is stored on `from`, as the layout stores it.
---@param from bpgen.Entity  already numbered
---@param to bpgen.Entity  already numbered
function builders.wire_between(from, to)
  local connector = defines.wire_connector_id.pole_copper
  from.wires = from.wires or {}
  ---@diagnostic disable-next-line: assign-type-mismatch  -- the fake `defines` uses strings, not Factorio's numbers
  from.wires[#from.wires + 1] = {from.entity_number, connector, to.entity_number, connector}
end

--------------------------------------------------------------------------------
-- The validator's catalog (see spec/support/blueprint_validator.lua).
--------------------------------------------------------------------------------

-- Options (all optional):
--   pole_supply_radius   default 2.5
--   pole_wire_reach      default 7.5
--   machine_needs_power  default false
--   machine_size         tiles wide and tall, default 2
---@param options? {pole_supply_radius?: number, pole_wire_reach?: number, machine_needs_power?: boolean, machine_size?: integer}
---@return table<string, bpgen.CatalogEntry>
function builders.a_catalog(options)
  options = options or {}
  local names = builders.NAMES
  return {
    [names.machine] = {
      kind = "machine",
      width = options.machine_size or 2, height = options.machine_size or 2,
      needs_power = options.machine_needs_power or false,
    },
    [names.belt] = {kind = "belt", width = 1, height = 1},
    [names.inserter] = {kind = "inserter", width = 1, height = 1, needs_power = true},
    [names.pole] = {
      kind = "pole", width = 1, height = 1,
      supply_radius = options.pole_supply_radius or 2.5,
      wire_reach = options.pole_wire_reach or 7.5,
    },
  }
end

--------------------------------------------------------------------------------
-- Stand-ins for the game's prototypes, for generator tests.
--------------------------------------------------------------------------------

-- A fluid in a recipe, for an ingredient or product that is not an item:
--     a_recipe{energy = 1, ingredients = {fluid_of(10, "water")}, products = {amount_of(1, "stone-brick")}}
---@param amount number
---@param name string
---@return bpgen.RecipeItem
function builders.fluid_of(amount, name)
  return {name = name, amount = amount, type = "fluid"} --[[@as bpgen.RecipeItem]]
end

-- A recipe prototype. The time, the amounts and the category are exactly what a
-- test's expectation depends on, so a test says them, except the category of a
-- recipe made by hand or in an assembler ("crafting"), which is the default; a
-- furnace's recipe says `category = "smelting"`. A recipe with several categories
-- (the game lists them all) says `categories = {"crushing", "smelting"}` instead.
--     a_recipe{energy = 3.2, ingredients = {amount_of(2, "stone")}, products = {amount_of(1, "stone-brick")}, category = "smelting"}
---@param options {energy: number, ingredients: bpgen.RecipeItem[], products: bpgen.RecipeItem[], category?: string, categories?: string[]}
---@return table
function builders.a_recipe(options)
  local function as_prototype_items(amounts)
    local items = {}
    for _, amount in ipairs(amounts) do
      items[#items + 1] = {type = amount.type or "item", name = amount.name, amount = amount.amount}
    end
    return items
  end

  local products = as_prototype_items(options.products)
  return {
    energy = options.energy,
    categories = options.categories or {options.category or "crafting"},
    ingredients = as_prototype_items(options.ingredients),
    products = products,
    get_product_amount = function(index) return products[index].amount end,
  }
end

-- A crafting machine prototype, for `fake_prototypes{machines = ...}`.
-- `crafting_speed = false` makes an entity that cannot craft.
-- The machine runs on electricity unless the options say otherwise: `burns` lists
-- the fuel categories a burner machine accepts, and `heat = true` makes a machine
-- with neither an electric nor a burner energy source (the game has others).
--     a_machine{crafting_speed = 0.5, size = 3}
--     a_machine{crafting_speed = 1, size = 2, burns = {"chemical"}}
---@param options {crafting_speed: number|false, size: integer, height?: integer, burns?: string[], heat?: boolean}  `height` defaults to `size`; give it for a machine that is not square
---@return table
function builders.a_machine(options)
  return {
    crafting_speed = options.crafting_speed,
    width = options.size,
    height = options.height or options.size,
    burns = options.burns,
    heat = options.heat,
  }
end

-- A stand-in for the game's `prototypes` table. What exists is what the test
-- says: no recipe is there unless the test lists it.
--
-- Options (all optional):
--   items                   names of items that exist without being in any recipe; default none
--   recipes                 recipes by name, each made with `a_recipe`; default none.
--                           `get_recipe_filtered` finds them by the items they make
--   furnace_speed           the stone furnace's crafting speed, default 1;
--                           `false` makes it an entity that cannot craft
--   machines                other crafting machines by name, each made with `a_machine`
--                           (the stone furnace is always there, 2 x 2); default none
--   belt_speed              the transport belt's speed, default 0.03125;
--                           `false` makes it an entity without a belt speed
--   inserter_rotation_speed the inserter's rotation speed, default 0.014 (the basic
--                           inserter, 50.4 items a minute); `false` makes it an
--                           entity that is not an inserter
--   missing_entities        names of buildings the game does not have, default none
-- The buildings the layout uses (furnace, belt, inserter, pole) exist unless
-- listed as missing. Every item a recipe mentions exists, and so does coal, the
-- fuel, in the fuel category "chemical". The stone furnace burns "chemical".
-- `get_item_filtered` understands only what the generator needs, filters of the
-- form {filter = "fuel-category", ["fuel-category"] = name} combined with "or"
-- (anything else is an error), and an empty list of filters gives every item,
-- as the worst case of what the game might do.
---@param options? {items?: string[], recipes?: table<string, table>, furnace_speed?: number|false, machines?: table<string, table>, belt_speed?: number|false, inserter_rotation_speed?: number|false, missing_entities?: string[]}
---@return table  a stand-in for the game's `prototypes`
function builders.fake_prototypes(options)
  options = options or {}
  local function option(value, default)
    if value == nil then
      return default
    end
    return value
  end
  local furnace_speed = option(options.furnace_speed, 1)
  local belt_speed = option(options.belt_speed, 0.03125)
  local rotation_speed = option(options.inserter_rotation_speed, 0.014)

  local function as_set(names)
    local set = {}
    for _, name in ipairs(names) do
      set[name] = true
    end
    return set
  end
  -- Machines run on electricity unless they burn fuel or have a source the mod does not handle.
  local function entity(name, fields)
    fields = fields or {}
    local burner = fields.burns
    local electric = fields.is_machine and not burner and not fields.heat
    return {
      localised_name = {"entity-name." .. name},
      get_crafting_speed = function() return fields.crafting_speed or nil end,
      get_inserter_rotation_speed = function() return fields.rotation_speed or nil end,
      belt_speed = fields.belt_speed or nil,
      tile_width = fields.width or 1,
      tile_height = fields.height or 1,
      burner_prototype = burner and {fuel_categories = as_set(burner)} or nil,
      electric_energy_source_prototype = electric and {} or nil,
    }
  end
  local function item(name, fuel_categories)
    return {localised_name = {"item-name." .. name}, fuel_categories = as_set(fuel_categories or {})}
  end

  local entities = {
    ["stone-furnace"] = entity("stone-furnace", {crafting_speed = furnace_speed, width = 2, height = 2, burns = {"chemical"}, is_machine = true}),
    ["transport-belt"] = entity("transport-belt", {belt_speed = belt_speed}),
    ["inserter"] = entity("inserter", {rotation_speed = rotation_speed}),
    ["small-electric-pole"] = entity("small-electric-pole"),
  }
  for name, machine in pairs(options.machines or {}) do
    machine.is_machine = true
    entities[name] = entity(name, machine)
  end
  for _, name in ipairs(options.missing_entities or {}) do
    entities[name] = nil
  end

  local recipes = options.recipes or {}
  local items = {["coal"] = item("coal", {"chemical"})}
  for _, name in ipairs(options.items or {}) do
    items[name] = items[name] or item(name)
  end
  for _, recipe in pairs(recipes) do
    for _, amount in ipairs(recipe.ingredients) do
      items[amount.name] = items[amount.name] or item(amount.name)
    end
    for _, amount in ipairs(recipe.products) do
      items[amount.name] = items[amount.name] or item(amount.name)
    end
  end

  local function get_item_filtered(filters)
    local found = {}
    for name, prototype in pairs(items) do
      if #filters == 0 then
        found[name] = prototype
      end
      for _, filter in ipairs(filters) do
        assert(filter.filter == "fuel-category" and type(filter["fuel-category"]) == "string" and filter.mode == nil,
          "the fake item filter only knows {filter = \"fuel-category\", [\"fuel-category\"] = name}")
        if prototype.fuel_categories[filter["fuel-category"]] then
          found[name] = prototype
        end
      end
    end
    return found
  end

  -- The recipes that make an item, by recipe name. Understands only the filter the
  -- generator uses, {filter = "has-product-item", elem_filters = {{filter = "name", name = item}}}.
  local function get_recipe_filtered(filters)
    assert(#filters == 1 and filters[1].filter == "has-product-item" and filters[1].mode == nil
      and #filters[1].elem_filters == 1 and filters[1].elem_filters[1].filter == "name"
      and type(filters[1].elem_filters[1].name) == "string",
      "the fake recipe filter only knows {filter = \"has-product-item\", elem_filters = {{filter = \"name\", name = item}}}")
    local wanted = filters[1].elem_filters[1].name
    local found = {}
    for recipe_name, recipe in pairs(recipes) do
      for _, product in ipairs(recipe.products) do
        if product.type == "item" and product.name == wanted then
          found[recipe_name] = recipe
        end
      end
    end
    return found
  end

  return {entity = entities, item = items, get_item_filtered = get_item_filtered, get_recipe_filtered = get_recipe_filtered}
end

return builders
