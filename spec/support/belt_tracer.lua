-- spec/support/belt_tracer.lua
-- Follows the items through a blueprint, lane by lane, the way the game moves them, and
-- reports what would go wrong. Test tooling only: the game never loads this folder.
--
--     local problems = tracer.problems(entities, {machines = {...}, raw = {...}, product = "..."})
--
-- The validator checks the entities and deliberately not the flow of the items; this
-- checks the flow, from the rules the layout relies on:
--   * where an inserter puts what it takes from a machine depends on the belt (rules the
--     owner checked in game, 2026-11-07): on a belt across its line, the far lane; on a
--     curve, the inside lane of the curve, whatever side the inserter stands on; on a belt
--     in line with it (the belt runs away from the inserter or toward it), the right-hand
--     lane of the belt, looking along the way the belt runs;
--   * a belt with a belt behind it, or with belts feeding it from both sides, stays
--     straight, and a belt that feeds the side of it puts everything on the near lane
--     (side-loading);
--   * a belt with one belt feeding it from the side and none behind it is a curve, and
--     keeps each lane's identity;
--   * an inserter takes from both lanes of a belt.
-- The problems are text. They are: a lane that carries two items, an input inserter of a machine
-- whose inserters, all of them together, never see something it eats, an item nobody eats, a belt that carries the product together with something else, and a belt
-- of raw items that something we made is put on.
--
-- `options.machines` says, by entity name, what each machine is: {size, eats = items,
-- makes = item}. `options.raw` lists, by name, the machines fed by belts of raw items,
-- which the player supplies (those belts hold nothing of ours). `options.product` is the
-- item of the blueprint. The names of belts and inserters are "transport-belt" and
-- "inserter" unless `options.belt` and `options.inserter` say otherwise. A long-handed inserter
-- (`options.long_inserter`, "long-handed-inserter" by default) picks up from and drops onto the tile
-- two away, over whatever stands between. The tracer follows it only when it takes from a belt into a
-- machine; one that puts items on a belt is reported, since the lane rules above are for a belt next to
-- the inserter.
-- `options.supplies` (optional) lists the belts of raw items that run to an input inserter
-- or to the side of another belt without passing a machine, which the player fills: each is
-- {x = tile column, y = tile row, item = name} for the first tile of the belt, and the item
-- rides both of its lanes.
--
-- Lanes are "left" and "right" of the way a belt runs. Like the validator, this reads
-- the table `defines`, so a test must define it first.

local grid = require("scripts.grid")

local tracer = {}

local direction = defines.direction
local VECTOR = {
  [direction.north] = {x = 0, y = -1}, [direction.east] = {x = 1, y = 0},
  [direction.south] = {x = 0, y = 1}, [direction.west] = {x = -1, y = 0},
}
local LEFT_OF = {
  [direction.north] = direction.west, [direction.east] = direction.north,
  [direction.south] = direction.east, [direction.west] = direction.south,
}
local RIGHT_OF = {
  [direction.north] = direction.east, [direction.east] = direction.south,
  [direction.south] = direction.west, [direction.west] = direction.north,
}
local OPPOSITE = {
  [direction.north] = direction.south, [direction.south] = direction.north,
  [direction.east] = direction.west, [direction.west] = direction.east,
}

-- The items on the two lanes of a belt.
---@class bpgen.Lanes
---@field left table<string, true>
---@field right table<string, true>

-- What the tracer knows about a blueprint, found once.
---@class bpgen.TraceIndex
---@field options table
---@field problems string[]
---@field tile table<table, bpgen.Tile>  the top-left tile of each entity
---@field by_tile table<string, table>  the entity that covers each tile
---@field belts table<string, table>  the belt on each tile
---@field makers table[]  the inserters that take from a machine onto a belt: {inserter, machine, belt}
---@field takers table[]  the inserters that take from a belt into a machine: {inserter, machine, belt}
---@field drops table<table, bpgen.Lanes>  what inserters put on each belt
---@field supplied table<table, string>  the item the player puts on the first tile of a belt of raw items
---@field contents table<table, bpgen.Lanes>  the items on each belt, once worked out

local function tile_key(x, y)
  return string.format("%g,%g", x, y)
end

---@return bpgen.Lanes
local function new_lanes()
  return {left = {}, right = {}}
end

---@param into table<string, true>
---@param from table<string, true>
local function add_items(into, from)
  for item in pairs(from) do
    into[item] = true
  end
end

-- Remembers where every entity is, and which tiles hold belts.
---@param entities table[]
---@param options table
---@return bpgen.TraceIndex
local function index_of(entities, options)
  local index = {options = options, problems = {}, tile = {}, by_tile = {}, belts = {}, makers = {}, takers = {}, drops = {}, contents = {}, supplied = {}}
  local belt_name = options.belt or "transport-belt"
  for _, entity in ipairs(entities) do
    local machine = options.machines[entity.name]
    local size = machine and machine.size or 1
    local tile = grid.top_left_tile(entity.position, size, size)
    index.tile[entity] = tile
    for dx = 0, size - 1 do
      for dy = 0, size - 1 do
        index.by_tile[tile_key(tile.x + dx, tile.y + dy)] = entity
      end
    end
    if entity.name == belt_name then
      index.belts[tile_key(tile.x, tile.y)] = entity
    end
  end
  return index
end

-- The entity on the tile `distance` steps (one by default) from `entity` the way `way` points.
---@param index bpgen.TraceIndex
---@param entity table
---@param way defines.direction
---@param distance? integer
---@return table|nil
local function entity_beside(index, entity, way, distance)
  local tile = index.tile[entity]
  distance = distance or 1
  return index.by_tile[tile_key(tile.x + VECTOR[way].x * distance, tile.y + VECTOR[way].y * distance)]
end

---@param index bpgen.TraceIndex
---@param belt table
---@param way defines.direction
---@return table|nil
local function belt_beside(index, belt, way)
  local tile = index.tile[belt]
  return index.belts[tile_key(tile.x + VECTOR[way].x, tile.y + VECTOR[way].y)]
end

-- The belt on the side `side` of a belt, if it points into it.
---@param index bpgen.TraceIndex
---@param belt table
---@param side defines.direction
---@return table|nil
local function feeder_from(index, belt, side)
  local neighbour = belt_beside(index, belt, side)
  if neighbour and belt_beside(index, neighbour, neighbour.direction) == belt then
    return neighbour
  end
  return nil
end

-- The belts that feed a belt from behind, from its left and from its right.
---@param index bpgen.TraceIndex
---@param belt table
---@return table|nil rear
---@return table|nil left
---@return table|nil right
local function feeders_of(index, belt)
  local way = belt.direction
  return feeder_from(index, belt, OPPOSITE[way]), feeder_from(index, belt, LEFT_OF[way]), feeder_from(index, belt, RIGHT_OF[way])
end

-- A belt with exactly one belt feeding it from a side and none behind it is a curve.
local function is_curve(rear, left, right)
  return rear == nil and ((left ~= nil) ~= (right ~= nil))
end

-- The lane on the inside of a curve: the side that the belt feeding it is on.
---@param left table|nil  the belt feeding the curve from its left, if that is where it comes from
---@return string
local function inside_lane(left)
  return left and "left" or "right"
end

-- The lane an inserter puts items on when it drops them on a belt next to it: the inside
-- lane of a curve; across the line of the inserter, the far lane; in line with it, the
-- right-hand lane of the belt.
---@param index bpgen.TraceIndex
---@param inserter table
---@param belt table
---@return string
local function drop_lane(index, inserter, belt)
  local rear, left, right = feeders_of(index, belt)
  if is_curve(rear, left, right) then
    return inside_lane(left)
  end
  local from_belt = {x = index.tile[inserter].x - index.tile[belt].x, y = index.tile[inserter].y - index.tile[belt].y}
  local on_left = VECTOR[LEFT_OF[belt.direction]]
  if from_belt.x == on_left.x and from_belt.y == on_left.y then
    return "right"
  end
  local on_right = VECTOR[RIGHT_OF[belt.direction]]
  if from_belt.x == on_right.x and from_belt.y == on_right.y then
    return "left"
  end
  return "right"
end

---@param index bpgen.TraceIndex
---@param entity table|nil
local function is_machine(index, entity)
  return entity ~= nil and index.options.machines[entity.name] ~= nil
end

---@param index bpgen.TraceIndex
---@param entity table|nil
local function is_belt(index, entity)
  return entity ~= nil and entity.name == (index.options.belt or "transport-belt")
end

-- Notes which kind of inserter this is, if it moves between a machine and a belt. `reach` is
-- how many tiles away it picks up and drops.
---@param index bpgen.TraceIndex
---@param inserter table
---@param reach integer
local function classify(index, inserter, reach)
  local from = entity_beside(index, inserter, inserter.direction, reach)
  local to = entity_beside(index, inserter, OPPOSITE[inserter.direction], reach)
  if is_machine(index, from) and is_belt(index, to) and reach > 1 then
    local tile = index.tile[inserter]
    index.problems[#index.problems + 1] = string.format("the long-handed inserter at %g,%g puts items on a belt, which the tracer does not follow", tile.x, tile.y)
  elseif is_machine(index, from) and is_belt(index, to) then
    index.makers[#index.makers + 1] = {inserter = inserter, machine = from, belt = to}
  elseif is_belt(index, from) and is_machine(index, to) then
    index.takers[#index.takers + 1] = {inserter = inserter, machine = to, belt = from}
  end
end

-- What the inserters that fill belts put on which lane.
---@param index bpgen.TraceIndex
local function note_drops(index)
  for _, maker in ipairs(index.makers) do
    local lanes = index.drops[maker.belt] or new_lanes()
    index.drops[maker.belt] = lanes
    lanes[drop_lane(index, maker.inserter, maker.belt)][index.options.machines[maker.machine.name].makes] = true
  end
end

-- Adds what `from` carries to `into`, each lane to the same lane.
---@param into bpgen.Lanes
---@param from bpgen.Lanes
local function add_along(into, from)
  add_items(into.left, from.left)
  add_items(into.right, from.right)
end

-- Adds everything `from` carries to one lane.
---@param lane table<string, true>
---@param from bpgen.Lanes
local function add_sideways(lane, from)
  add_items(lane, from.left)
  add_items(lane, from.right)
end

local contents_of

-- Adds what the belts that feed `belt` bring.
---@param index bpgen.TraceIndex
---@param belt table
---@param lanes bpgen.Lanes
---@param visiting table<table, true>
local function bring_in(index, belt, lanes, visiting)
  local rear, left, right = feeders_of(index, belt)
  if rear then
    add_along(lanes, contents_of(index, rear, visiting))
  end
  if is_curve(rear, left, right) then
    add_along(lanes, contents_of(index, left or right, visiting))
    return
  end
  if left then
    add_sideways(lanes.left, contents_of(index, left, visiting))
  end
  if right then
    add_sideways(lanes.right, contents_of(index, right, visiting))
  end
end

-- The items on each lane of a belt: what inserters drop on it, and what the belts that
-- feed it bring. `visiting` holds the belts being worked out, to stop at a loop.
---@param index bpgen.TraceIndex
---@param belt table
---@param visiting table<table, true>
---@return bpgen.Lanes
function contents_of(index, belt, visiting)
  if index.contents[belt] then
    return index.contents[belt]
  end
  local lanes = new_lanes()
  if visiting[belt] then
    return lanes
  end
  visiting[belt] = true
  if index.drops[belt] then
    add_along(lanes, index.drops[belt])
  end
  if index.supplied[belt] then
    lanes.left[index.supplied[belt]] = true
    lanes.right[index.supplied[belt]] = true
  end
  bring_in(index, belt, lanes, visiting)
  visiting[belt] = nil
  index.contents[belt] = lanes
  return lanes
end

---@param lane table<string, true>
---@return string[]  the items, sorted
local function sorted_items(lane)
  local items = {}
  for item in pairs(lane) do
    items[#items + 1] = item
  end
  table.sort(items)
  return items
end

-- No lane carries two kinds of item.
---@param index bpgen.TraceIndex
local function check_lanes(index)
  for _, belt in pairs(index.belts) do
    local lanes = contents_of(index, belt, {})
    for _, side in ipairs({"left", "right"}) do
      local items = sorted_items(lanes[side])
      if #items > 1 then
        local tile = index.tile[belt]
        index.problems[#index.problems + 1] = string.format("the %s lane at %g,%g carries %s", side, tile.x, tile.y, table.concat(items, " and "))
      end
    end
  end
end

-- The items on either lane of a belt.
---@param index bpgen.TraceIndex
---@param belt table
---@return table<string, true>
local function items_on(index, belt)
  local lanes = contents_of(index, belt, {})
  local items = {}
  add_items(items, lanes.left)
  add_items(items, lanes.right)
  return items
end

-- The problem texts for an input inserter that takes from a belt of raw items: the
-- belt must hold nothing that we made.
---@param index bpgen.TraceIndex
---@param taker table
local function check_raw_taker(index, taker)
  local tile = index.tile[taker.inserter]
  for item in pairs(items_on(index, taker.belt)) do
    index.problems[#index.problems + 1] = string.format("the belt of raw items next to the inserter at %g,%g carries %s", tile.x, tile.y, item)
  end
end

-- The items that the input inserters of each machine see between them, each on the belt it
-- takes from (a machine with a plain and a long-handed inserter sees two belts). The
-- machines fed by belts of raw items are left out.
---@param index bpgen.TraceIndex
---@return table<table, table<string, true>>  by machine
local function seen_by_machine(index)
  local seen = {}
  for _, taker in ipairs(index.takers) do
    if not index.options.raw[taker.machine.name] then
      seen[taker.machine] = seen[taker.machine] or {}
      add_items(seen[taker.machine], items_on(index, taker.belt))
    end
  end
  return seen
end

-- Between them, the input inserters of a machine see every item it eats; an inserter of a
-- machine that none of them sees the item for is reported. Adds the items that the machine
-- eats to `eaten`.
---@param index bpgen.TraceIndex
---@param taker table
---@param seen table<string, true>  what all the input inserters of its machine see
---@param eaten table<string, true>  the items some machine eats, to add to
local function check_taker(index, taker, seen, eaten)
  local tile = index.tile[taker.inserter]
  for _, item in ipairs(index.options.machines[taker.machine.name].eats) do
    eaten[item] = true
    if not seen[item] then
      index.problems[#index.problems + 1] = string.format("the input inserter at %g,%g never sees %s", tile.x, tile.y, item)
    end
  end
end

-- Every machine sees what it eats. Returns the items that some machine eats.
---@param index bpgen.TraceIndex
---@return table<string, true>
local function check_inputs(index)
  local eaten = {}
  local seen = seen_by_machine(index)
  for _, taker in ipairs(index.takers) do
    if index.options.raw[taker.machine.name] then
      check_raw_taker(index, taker)
    else
      check_taker(index, taker, seen[taker.machine], eaten)
    end
  end
  return eaten
end

-- Everything a machine makes is eaten by some machine, except the product.
---@param index bpgen.TraceIndex
---@param eaten table<string, true>
local function check_outputs(index, eaten)
  local reported = {}
  for _, maker in ipairs(index.makers) do
    local item = index.options.machines[maker.machine.name].makes
    if item ~= index.options.product and not eaten[item] and not reported[item] then
      reported[item] = true
      index.problems[#index.problems + 1] = "nothing eats " .. item
    end
  end
end

-- A belt that carries the product carries nothing else.
---@param index bpgen.TraceIndex
local function check_product(index)
  for _, belt in pairs(index.belts) do
    local items = items_on(index, belt)
    if items[index.options.product] and #sorted_items(items) > 1 then
      local tile = index.tile[belt]
      index.problems[#index.problems + 1] = string.format("the belt at %g,%g carries the product together with something else", tile.x, tile.y)
    end
  end
end

-- Notes the belts the player fills with raw items.
---@param index bpgen.TraceIndex
local function note_supplies(index)
  for _, supply in ipairs(index.options.supplies or {}) do
    index.supplied[index.belts[tile_key(supply.x, supply.y)]] = supply.item -- a supply that is not on a belt is a mistake in the test: this fails
  end
end

---@param entities table[]  blueprint entities with positions and directions
---@param options table  see the top of the file
---@return string[] problems  empty when the flow is sound
function tracer.problems(entities, options)
  local index = index_of(entities, options)
  note_supplies(index)
  for _, entity in ipairs(entities) do
    if entity.name == (options.inserter or "inserter") then
      classify(index, entity, 1)
    elseif entity.name == (options.long_inserter or "long-handed-inserter") then
      classify(index, entity, 2)
    end
  end
  note_drops(index)
  check_lanes(index)
  check_outputs(index, check_inputs(index))
  check_product(index)
  table.sort(index.problems)
  return index.problems
end

return tracer
