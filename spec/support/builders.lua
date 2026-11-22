-- spec/support/builders.lua
-- Helpers that build the plain data the tests need, so a test body only has to
-- spell out the values its assertions depend on.
--
-- The rule for using them: a value a test's expectation depends on is passed in
-- by the test itself (`a_catalog{pole_wire_reach = 7}`), never left to a default
-- that the reader cannot see. Defaults are only for things the test does not care about.

local grid = require("scripts.grid")

local builders = {}

-- The two poles a blueprint may be built with, as the base game has them: the name, how far from its centre the pole
-- powers and how long a wire it holds, in tiles. The generator takes the medium pole instead of the small one when it is
-- unlocked.
---@type table<"small"|"medium", {name: string, supply_distance: number, wire_distance: number}>
builders.POLES = {
  small = {name = "small-electric-pole", supply_distance = 2.5, wire_distance = 7.5},
  medium = {name = "medium-electric-pole", supply_distance = 3.5, wire_distance = 9},
}

-- The prototype names the layout is given, with the small pole. They are labels here, nothing more.
---@type bpgen.Names
builders.NAMES = {
  machine = "stone-furnace",
  belt = "transport-belt",
  inserter = "inserter",
  long_inserter = "long-handed-inserter",
  fast_inserter = "fast-inserter",
  pole = builders.POLES.small.name,
  pole_supply_distance = builders.POLES.small.supply_distance,
  pole_wire_distance = builders.POLES.small.wire_distance,
  lamp = "small-lamp",
  panel = "display-panel",
  splitter = "splitter",
  underground = "underground-belt",
  pipe = "pipe",
  pipe_to_ground = "pipe-to-ground",
  pump = "pump",
}

-- `NAMES` with the medium electric pole in place of the small one.
---@return bpgen.Names
function builders.medium_pole_names()
  local names = {}
  for key, value in pairs(builders.NAMES) do
    names[key] = value
  end
  names.pole = builders.POLES.medium.name
  names.pole_supply_distance = builders.POLES.medium.supply_distance
  names.pole_wire_distance = builders.POLES.medium.wire_distance
  return names
end

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

-- A fast inserter: like `inserter`, with a name of its own.
---@param tile_x number
---@param tile_y number
---@param direction? defines.direction
---@return table  an entity without its number yet (see `blueprint_of`)
function builders.fast_inserter(tile_x, tile_y, direction)
  return {name = builders.NAMES.fast_inserter, position = grid.position(tile_x, tile_y), direction = direction}
end

-- A long-handed inserter: like `inserter`, but it picks up from and drops onto the tile two tiles away.
---@param tile_x number
---@param tile_y number
---@param direction? defines.direction
---@return table  an entity without its number yet (see `blueprint_of`)
function builders.long_inserter(tile_x, tile_y, direction)
  return {name = builders.NAMES.long_inserter, position = grid.position(tile_x, tile_y), direction = direction}
end

-- A splitter: two tiles side by side across the way it faces, so `splitter(2, 0, east)` covers tiles (2, 0) and (2, 1),
-- and `splitter(2, 0, south)` covers (2, 0) and (3, 0). `tile_x`, `tile_y` is its top-left tile.
---@param tile_x number
---@param tile_y number
---@param direction defines.direction  the way it moves items
---@return table  an entity without its number yet (see `blueprint_of`)
function builders.splitter(tile_x, tile_y, direction)
  local across_east_west = direction == defines.direction.east or direction == defines.direction.west
  local width, height = 2, 1
  if across_east_west then
    width, height = 1, 2
  end
  return {name = builders.NAMES.splitter, position = grid.position(tile_x, tile_y, width, height), direction = direction}
end

-- One end of an underground belt: `kind` is "input" for the entrance and "output" for the exit, `direction` the way
-- the belt moves items at both ends.
---@param tile_x number
---@param tile_y number
---@param direction defines.direction
---@param kind "input"|"output"
---@return table  an entity without its number yet (see `blueprint_of`)
function builders.underground(tile_x, tile_y, direction, kind)
  return {name = builders.NAMES.underground, position = grid.position(tile_x, tile_y), direction = direction, type = kind}
end

-- A pipe: it joins the pipes, the ends of underground pipes and the fluid connections of machines on its four sides.
---@param tile_x number
---@param tile_y number
---@return table  an entity without its number yet (see `blueprint_of`)
function builders.pipe(tile_x, tile_y)
  return {name = builders.NAMES.pipe, position = grid.position(tile_x, tile_y), direction = defines.direction.north}
end

-- One end of an underground pipe. `direction` is the side its opening faces, where it joins an ordinary pipe or a
-- machine; the underground pipe runs the other way, to the end that faces the opposite way.
---@param tile_x number
---@param tile_y number
---@param direction defines.direction  the side of the opening
---@return table  an entity without its number yet (see `blueprint_of`)
function builders.pipe_to_ground(tile_x, tile_y, direction)
  return {name = builders.NAMES.pipe_to_ground, position = grid.position(tile_x, tile_y), direction = direction}
end

-- Poles can be given another prototype name, for tests that need a second kind of pole.
---@param tile_x number
---@param tile_y number
---@param name? string  another pole prototype name
---@return table  an entity without its number yet (see `blueprint_of`)
function builders.pole(tile_x, tile_y, name)
  return {name = name or builders.NAMES.pole, position = grid.position(tile_x, tile_y)}
end

-- Gives the entities of a list their numbers (1, 2, 3, ... in the order of the list) and gives the list back.
---@param list table[]  entities from the builders above
---@return bpgen.Entity[]
function builders.numbered(list)
  for index, entity in ipairs(list) do
    entity.entity_number = index
  end
  return list
end

-- Gives the entities their numbers (1, 2, 3, ... in the order passed) and
-- returns them as a list, the way a blueprint holds them.
---@param ... table  entities from the builders above
---@return bpgen.Entity[]
function builders.blueprint_of(...)
  return builders.numbered({...})
end

-- The entities of the list that have the name, in the order of the list.
---@param entities table[]
---@param name string
---@return table[]
function builders.entities_named(entities, name)
  local found = {}
  for _, entity in ipairs(entities) do
    if entity.name == name then
      found[#found + 1] = entity
    end
  end
  return found
end

-- The items of the belts that come in, from the top of the blueprint down, as the message of a blueprint in the design with one belt of each material
-- lists them (`message[5]` is a text that joins the names of the items).
---@param message table
---@return string[]
function builders.belts_named(message)
  local names = {}
  for _, item in ipairs(message[5]) do
    local name = type(item) == "table" and tostring(item[1]):match("^item%-name%.(.+)$")
    names[#names + 1] = name or nil
  end
  return names
end

-- How many entities of the list have the name.
---@param entities table[]
---@param name string
---@return integer
function builders.count_named(entities, name)
  return #builders.entities_named(entities, name)
end

-- The rows of the belts in one tile column, in order.
---@param entities table[]
---@param column integer
---@return integer[]
function builders.belt_rows(entities, column)
  local rows = {}
  for _, belt in ipairs(builders.entities_named(entities, builders.NAMES.belt)) do
    local tile = grid.top_left_tile(belt.position)
    if tile.x == column then
      rows[#rows + 1] = tile.y
    end
  end
  table.sort(rows)
  return rows
end

-- The columns of the entities of one name, one tile each, in one tile row, in order.
---@param entities table[]
---@param name string
---@param row integer
---@return integer[]
function builders.columns_in_row(entities, name, row)
  local columns = {}
  for _, entity in ipairs(builders.entities_named(entities, name)) do
    local tile = grid.top_left_tile(entity.position)
    if tile.y == row then
      columns[#columns + 1] = tile.x
    end
  end
  table.sort(columns)
  return columns
end

-- The rows of the entities of one name, one tile each, in one tile column, in order.
---@param entities table[]
---@param name string
---@param column integer
---@return integer[]
function builders.rows_in_column(entities, name, column)
  local rows = {}
  for _, entity in ipairs(builders.entities_named(entities, name)) do
    local tile = grid.top_left_tile(entity.position)
    if tile.x == column then
      rows[#rows + 1] = tile.y
    end
  end
  table.sort(rows)
  return rows
end

-- The rows from the top of the blueprint (the row 0) down of the entities with the name, in a column, in order: what is in the blueprint
-- and not the pipes that bring the start of a pipe to the corner above it (see scripts/pipe_entries.lua).
---@param entities bpgen.Entity[]
---@param name string
---@param column integer
---@return integer[]
function builders.body_rows_in_column(entities, name, column)
  local rows = {}
  for _, row in ipairs(builders.rows_in_column(entities, name, column)) do
    if row >= 0 then
      rows[#rows + 1] = row
    end
  end
  return rows
end

-- The whole numbers from `first` to `last`.
---@param first integer
---@param last integer
---@return integer[]
function builders.range(first, last)
  local numbers = {}
  for number = first, last do
    numbers[#numbers + 1] = number
  end
  return numbers
end

-- The directions the belts of one tile column face, each once, in the order they are first met.
---@param entities table[]
---@param column integer
---@return defines.direction[]
function builders.belt_directions(entities, column)
  local directions, seen = {}, {}
  for _, belt in ipairs(builders.entities_named(entities, builders.NAMES.belt)) do
    if grid.top_left_tile(belt.position).x == column and not seen[belt.direction] then
      seen[belt.direction] = true
      directions[#directions + 1] = belt.direction
    end
  end
  return directions
end

-- A copy of `base` with the fields of `changes` put in it (plain values; no field of either is looked into). Without `changes`,
-- a plain copy.
---@param base table
---@param changes? table
---@return table
function builders.merged(base, changes)
  local copy = {}
  for key, value in pairs(base) do
    copy[key] = value
  end
  for key, value in pairs(changes or {}) do
    copy[key] = value
  end
  return copy
end

-- The shortest distance between two of the tiles, or infinity when there are fewer than two.
---@param tiles {x: number, y: number}[]
---@return number
function builders.closest_pair(tiles)
  local closest = math.huge
  for i = 1, #tiles - 1 do
    for j = i + 1, #tiles do
      closest = math.min(closest, math.sqrt((tiles[i].x - tiles[j].x) ^ 2 + (tiles[i].y - tiles[j].y) ^ 2))
    end
  end
  return closest
end

-- Runs `run` with `module[name]` replaced by `replacement` and gives back what it gives. The original is back in its place
-- afterwards, also when `run` fails, which then fails with its own message.
---@generic R
---@param module table
---@param name string
---@param replacement function
---@param run fun(): R
---@return R
function builders.with_replaced(module, name, replacement, run)
  local original = module[name]
  module[name] = replacement
  local ok, result = pcall(run)
  module[name] = original
  if not ok then
    error(result, 0)
  end
  return result
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
--   pole_supply_radius   of the small pole, default 2.5
--   pole_wire_reach      of the small pole, default 7.5
--   medium_pole_supply_radius  of the medium pole, default 3.5
--   medium_pole_wire_reach     of the medium pole, default 9
--   machine_needs_power  default false
--   machine_size         tiles wide and tall, default 2
---@param options? {pole_supply_radius?: number, pole_wire_reach?: number, medium_pole_supply_radius?: number, medium_pole_wire_reach?: number, machine_needs_power?: boolean, machine_size?: integer}
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
    [names.splitter] = {kind = "belt", width = 2, height = 1, turns = true},
    [names.underground] = {kind = "belt", width = 1, height = 1},
    ["fast-transport-belt"] = {kind = "belt", width = 1, height = 1},
    ["fast-splitter"] = {kind = "belt", width = 2, height = 1, turns = true},
    ["fast-underground-belt"] = {kind = "belt", width = 1, height = 1},
    [names.inserter] = {kind = "inserter", width = 1, height = 1, needs_power = true},
    [names.fast_inserter] = {kind = "inserter", width = 1, height = 1, needs_power = true},
    [names.long_inserter] = {kind = "inserter", width = 1, height = 1, needs_power = true, reach = 2},
    [builders.POLES.small.name] = {
      kind = "pole", width = 1, height = 1,
      supply_radius = options.pole_supply_radius or builders.POLES.small.supply_distance,
      wire_reach = options.pole_wire_reach or builders.POLES.small.wire_distance,
    },
    [builders.POLES.medium.name] = {
      kind = "pole", width = 1, height = 1,
      supply_radius = options.medium_pole_supply_radius or builders.POLES.medium.supply_distance,
      wire_reach = options.medium_pole_wire_reach or builders.POLES.medium.wire_distance,
    },
    [names.lamp] = {kind = "lamp", width = 1, height = 1, needs_power = true},
    [names.panel] = {kind = "panel", width = 1, height = 1},
    [names.pipe] = {kind = "pipe", width = 1, height = 1},
    [names.pipe_to_ground] = {kind = "pipe_to_ground", width = 1, height = 1, reach = 10},
    [names.pump] = {kind = "pump", width = 2, height = 1, needs_power = true}, -- only facing east or west is used
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
      items[#items + 1] = {type = amount.type or "item", name = amount.name, amount = amount.amount, fluidbox_index = amount.fluidbox_index}
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
-- `energy_usage` is what the machine uses while it crafts, in joules per tick; the default is 1500 (90 kW).
-- `type` is the prototype type, "assembling-machine" unless given; a furnace is "furnace" (it picks its own recipe).
-- `fluid_input = true` gives the machine a fluid box that takes a fluid in and one that gives one out (an assembling machine 2 has
-- both); `fluid_boxes` says the production type of each box instead ("input", "output", "input-output").
-- `pipe_boxes` gives the machine fluid boxes with a pipe connection each, as the game describes them: the production type, the
-- position of the connection from the centre of the machine as it faces north, which is the position of the tile of the MACHINE at
-- its edge (not of the pipe outside it), and the direction the connection points in. A refinery of 5 x 5 has an input under it at
-- {x = 1, y = 2}, pointing south (the game's own example is the assembling machine 2: `position = {0, -1}`, `direction = north`).
-- A box may say `connection_type` too, "normal" unless it says "underground" or "linked", and `no_position = true` for a connection
-- the game gives no position for.
--     a_machine{crafting_speed = 1, size = 5, pipe_boxes = {{production_type = "input", position = {x = 1, y = 2}, direction = defines.direction.south}}}
---@param options {crafting_speed: number|false, size: integer, height?: integer, burns?: string[], heat?: boolean, energy_usage?: number, type?: string, fluid_input?: boolean, fluid_boxes?: string[], pipe_boxes?: {production_type: string, position: {x: number, y: number}, direction: defines.direction, connection_type?: string, no_position?: boolean}[]}  `height` defaults to `size`; give it for a machine that is not square; `fluid_input` gives it a fluid box that takes a fluid in; `fluid_boxes` the production types of its fluid boxes, which `fluid_input` leaves to {"input", "output"}; `pipe_boxes` its fluid boxes with their pipe connections
---@return table
function builders.a_machine(options)
  return {
    type = options.type,
    crafting_speed = options.crafting_speed,
    width = options.size,
    height = options.height or options.size,
    burns = options.burns,
    heat = options.heat,
    energy_usage = options.energy_usage or 1500,
    fluid_input = options.fluid_input,
    fluid_boxes = options.fluid_boxes,
    pipe_boxes = options.pipe_boxes,
  }
end

-- A stand-in for the game's `prototypes` table. What exists is what the test
-- says: no recipe is there unless the test lists it.
--
-- Options (all optional):
--   items                   names of items that exist without being in any recipe; default none
--   recipes                 recipes by name, each made with `a_recipe`; default none.
--                           `recipe[name]` gives one, and `get_recipe_filtered` finds them by the items they make
--   furnace_speed           the stone furnace's crafting speed, default 1;
--                           `false` makes it an entity that cannot craft
--   machines                other crafting machines by name, each made with `a_machine`
--                           (the stone furnace is always there, 2 x 2); default none
--   belt_speed              the transport belt's speed, default 0.03125;
--                           `false` makes it an entity without a belt speed
--   long_inserter_rotation_speed the long-handed inserter's, default 0.02 (72 items a minute)
--   fast_inserter_rotation_speed the fast inserter's, default 0.04 (144 items a minute);
--                           `false` makes it an entity that is not an inserter
--   inserter_rotation_speed the inserter's rotation speed, default 0.014 (the basic
--                           inserter, 50.4 items a minute); `false` makes it an
--                           entity that is not an inserter
--   inserter_stacks         by inserter name ("inserter", "long-handed-inserter", "fast-inserter"), how its stack size
--                           comes about, as {built_in = , takes_research = }: `built_in` is the bonus the prototype has of its
--                           own, default 0, `false` makes the game not say; `takes_research` is whether the force's inserter
--                           capacity bonus counts for it, default true, "unsaid" makes the game not say. An inserter left out
--                           has the defaults
--   underground_distance    the most tiles the underground belt spans, default 5 (the basic one);
--                           `false` makes it an entity without that field
--   fast_belts              true gives the game the fast transport belt, splitter and underground belt, which a
--                           force that has unlocked all three builds with; default false (the basic ones only)
--   fast_belt_speed         the fast transport belt's speed, default 0.0625 (twice the basic one's);
--                           `false` makes it an entity without a belt speed
--   fast_underground_distance the most tiles the fast underground belt spans, default 7
--   small_pole_supply_distance, medium_pole_supply_distance  how far the small and the medium electric pole
--                           power, default 2.5 and 3.5; `false` makes the game not say
--   small_pole_wire_distance, medium_pole_wire_distance  how long a wire they hold, default 7.5 and 9;
--                           `false` makes it an entity that holds none (0)
--   missing_entities        names of buildings the game does not have, default none
--   furnace_energy_usage    what the stone furnace uses while it crafts, in joules per tick; default 1500 (90 kW);
--                           `false` makes the game not say
--   furnace_effectivity     the share of the fuel's energy the stone furnace uses, default 1
--   coal_fuel_value         the energy of one coal in joules, default 4000000 (4 MJ)
-- The buildings the layout uses (furnace, belt, inserter, pole, the medium pole that a force that
-- has unlocked it gets instead, and the splitter and the underground belt of the input design that
-- brings in one belt of each material) exist unless listed as missing. Every item a recipe mentions exists, and so does coal, the
-- fuel, in the fuel category "chemical". The stone furnace burns "chemical".
-- `get_item_filtered` understands only what the generator needs, filters of the
-- form {filter = "fuel-category", ["fuel-category"] = name} combined with "or"
-- (anything else is an error), and an empty list of filters gives every item,
-- as the worst case of what the game might do.
---@param options? {items?: string[], recipes?: table<string, table>, furnace_speed?: number|false, machines?: table<string, table>, belt_speed?: number|false, fast_belts?: boolean, fast_belt_speed?: number|false, fast_underground_distance?: number, inserter_rotation_speed?: number|false, long_inserter_rotation_speed?: number, fast_inserter_rotation_speed?: number|false, inserter_stacks?: table<string, {built_in?: number|false, takes_research?: boolean|"unsaid"}>, underground_distance?: number|false, small_pole_supply_distance?: number|false, small_pole_wire_distance?: number|false, medium_pole_supply_distance?: number|false, medium_pole_wire_distance?: number|false, missing_entities?: string[]}
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
  local long_rotation_speed = option(options.long_inserter_rotation_speed, 0.02)
  local fast_rotation_speed = option(options.fast_inserter_rotation_speed, 0.04)
  local underground_distance = option(options.underground_distance, 5)
  local small_supply_distance = option(options.small_pole_supply_distance, builders.POLES.small.supply_distance)
  local small_wire_distance = option(options.small_pole_wire_distance, builders.POLES.small.wire_distance)
  local medium_supply_distance = option(options.medium_pole_supply_distance, builders.POLES.medium.supply_distance)
  local medium_wire_distance = option(options.medium_pole_wire_distance, builders.POLES.medium.wire_distance)
  local furnace_energy_usage = option(options.furnace_energy_usage, 1500)
  local furnace_effectivity = option(options.furnace_effectivity, 1)
  local coal_fuel_value = option(options.coal_fuel_value, 4000000)

  local function as_set(names)
    local set = {}
    for _, name in ipairs(names) do
      set[name] = true
    end
    return set
  end
  -- The four positions of a pipe connection, one for each way the machine faces (north, east, south, west), from the one it has facing
  -- north: turning the machine a quarter clockwise moves the connection from (x, y) to (-y, x). The `direction` of a connection is the
  -- one it has facing north only, as in the game.
  local function turned_positions(position)
    return {
      {x = position.x, y = position.y}, {x = -position.y, y = position.x},
      {x = -position.x, y = -position.y}, {x = position.y, y = -position.x},
    }
  end
  -- The fluid boxes of a machine: those `pipe_boxes` has, each with the one pipe connection it says, else those `fluid_boxes`
  -- names, else an input and an output when `fluid_input` is set, else none.
  local function fluid_boxes(fields)
    local boxes = {}
    for index, box in ipairs(fields.pipe_boxes or {}) do
      boxes[#boxes + 1] = {
        production_type = box.production_type, index = index,
        pipe_connections = {{
          connection_type = box.connection_type or "normal", positions = box.no_position and {} or turned_positions(box.position),
          direction = box.direction,
        }},
      }
    end
    for _, production_type in ipairs(fields.fluid_boxes or (fields.fluid_input and {"input", "output"} or {})) do
      boxes[#boxes + 1] = {production_type = production_type, index = #boxes + 1, pipe_connections = {}}
    end
    return boxes
  end
  -- Machines run on electricity unless they burn fuel or have a source the mod does not handle.
  local function entity(name, fields)
    fields = fields or {}
    local burner = fields.burns
    local electric = fields.is_machine and not burner and not fields.heat
    return {
      localised_name = {"entity-name." .. name},
      type = fields.type or (fields.is_machine and "assembling-machine" or nil),
      get_crafting_speed = function() return fields.crafting_speed or nil end,
      get_inserter_rotation_speed = function() return fields.rotation_speed or nil end,
      inserter_stack_size_bonus = fields.stack_size_bonus,
      uses_inserter_stack_size_bonus = fields.uses_stack_size_bonus,
      get_max_energy_usage = function() return fields.energy_usage or nil end,
      belt_speed = fields.belt_speed or nil,
      max_underground_distance = fields.underground_distance or nil,
      get_supply_area_distance = function() return fields.supply_area_distance or nil end,
      get_max_wire_distance = function() return fields.max_wire_distance or 0 end,
      tile_width = fields.width or 1,
      tile_height = fields.height or 1,
      burner_prototype = burner and {fuel_categories = as_set(burner), effectivity = fields.effectivity or 1} or nil,
      electric_energy_source_prototype = electric and {} or nil,
      fluidbox_prototypes = fluid_boxes(fields),
    }
  end
  local function item(name, fuel_categories, fuel_value)
    return {localised_name = {"item-name." .. name}, fuel_categories = as_set(fuel_categories or {}), fuel_value = fuel_value or 0}
  end
  -- An inserter: how fast it swings, and how its stack size comes about (the option `inserter_stacks`).
  local function inserter(name, speed)
    local stack = (options.inserter_stacks or {})[name] or {}
    local takes_research = option(stack.takes_research, true)
    if takes_research == "unsaid" then
      takes_research = nil -- a game that does not say; `false` is a game that says no
    end
    return entity(name, {
      rotation_speed = speed,
      stack_size_bonus = option(stack.built_in, 0) or nil,
      uses_stack_size_bonus = takes_research,
    })
  end

  local entities = {
    ["stone-furnace"] = entity("stone-furnace", {type = "furnace", crafting_speed = furnace_speed, width = 2, height = 2, burns = {"chemical"}, is_machine = true, energy_usage = furnace_energy_usage or nil, effectivity = furnace_effectivity}),
    ["transport-belt"] = entity("transport-belt", {belt_speed = belt_speed}),
    ["splitter"] = entity("splitter"),
    ["underground-belt"] = entity("underground-belt", {underground_distance = underground_distance or nil}),
    ["inserter"] = inserter("inserter", rotation_speed),
    ["long-handed-inserter"] = inserter("long-handed-inserter", long_rotation_speed),
    ["fast-inserter"] = inserter("fast-inserter", fast_rotation_speed or nil),
    [builders.POLES.small.name] = entity(builders.POLES.small.name, {
      supply_area_distance = small_supply_distance or nil, max_wire_distance = small_wire_distance or nil,
    }),
    [builders.POLES.medium.name] = entity(builders.POLES.medium.name, {
      supply_area_distance = medium_supply_distance or nil, max_wire_distance = medium_wire_distance or nil,
    }),
    ["small-lamp"] = entity("small-lamp"),
    ["display-panel"] = entity("display-panel"),
    ["pipe"] = entity("pipe"),
    ["pipe-to-ground"] = entity("pipe-to-ground"),
    ["pump"] = entity("pump"),
  }
  for name, machine in pairs(options.machines or {}) do
    machine.is_machine = true
    entities[name] = entity(name, machine)
  end
  if options.fast_belts then
    entities["fast-transport-belt"] = entity("fast-transport-belt", {belt_speed = option(options.fast_belt_speed, 0.0625) or nil})
    entities["fast-splitter"] = entity("fast-splitter")
    entities["fast-underground-belt"] = entity("fast-underground-belt", {underground_distance = option(options.fast_underground_distance, 7)})
  end
  for _, name in ipairs(options.missing_entities or {}) do
    entities[name] = nil
  end

  local recipes = options.recipes or {}
  for name, recipe in pairs(recipes) do
    recipe.name = name -- a recipe prototype knows its own name
  end
  local items = {["coal"] = item("coal", {"chemical"}, coal_fuel_value)}
  for _, name in ipairs(options.items or {}) do
    items[name] = items[name] or item(name)
  end
  local fluids = {}
  for _, recipe in pairs(recipes) do
    for _, amount in ipairs(recipe.ingredients) do
      if amount.type == "fluid" then
        fluids[amount.name] = {localised_name = {"fluid-name." .. amount.name}}
      else
        items[amount.name] = items[amount.name] or item(amount.name)
      end
    end
    for _, amount in ipairs(recipe.products) do
      if amount.type == "fluid" then
        fluids[amount.name] = {localised_name = {"fluid-name." .. amount.name}}
      else
        items[amount.name] = items[amount.name] or item(amount.name)
      end
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

  -- The recipes that make an item, by recipe name. Understands only the filter the generator uses,
  -- {filter = "has-product-item", elem_filters = {{filter = "name", name = item}}}.
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

  return {
    entity = entities, item = items, fluid = fluids, recipe = recipes,
    get_item_filtered = get_item_filtered, get_recipe_filtered = get_recipe_filtered,
  }
end

-- A stand-in for a force, which tells the generator which recipes the player can use:
-- `force.recipes[name]` is a recipe with `enabled`, or nil for a recipe the game does not
-- have. Every recipe is enabled unless the test lists it.
--
-- Options (all optional):
--   locked   names of recipes that are not unlocked yet
--   absent   names of recipes the force does not know at all
--   inserter_stack_size_bonus  what the force's research adds to the items an inserter moves in a swing, default 0;
--            `false` makes the force not say
---@param options? {locked?: string[], absent?: string[], inserter_stack_size_bonus?: number|false}
---@return table  a stand-in for a LuaForce
function builders.fake_force(options)
  options = options or {}
  local bonus = options.inserter_stack_size_bonus
  if bonus == nil then
    bonus = 0
  end
  local locked, absent = {}, {}
  for _, name in ipairs(options.locked or {}) do
    locked[name] = true
  end
  for _, name in ipairs(options.absent or {}) do
    absent[name] = true
  end
  local recipes = setmetatable({}, {__index = function(_, name)
    if absent[name] then
      return nil
    end
    return {enabled = not locked[name]}
  end})
  return {recipes = recipes, inserter_stack_size_bonus = bonus or nil}
end

return builders
