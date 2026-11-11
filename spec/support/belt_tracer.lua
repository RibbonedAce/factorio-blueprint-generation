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
--   * a belt with one belt feeding it from a side and none behind it is a curve, and
--     keeps each lane's identity;
--   * an inserter takes from both lanes of a belt;
--   * a splitter (two tiles side by side across its way) gives each of its two output tiles,
--     lane for lane, what its two input tiles bring: it keeps the lanes (not yet seen in game);
--   * an underground belt entrance gives its exit, which stands in line with it, facing the
--     same way, within `options.underground_reach` tiles (5 by default), what comes into it
--     from behind, lane for lane; between them anything may stand (not yet seen in game).
-- The problems are text. They are: a lane that carries two items, an input inserter of a machine
-- whose inserters, all of them together, never see something it eats, an item nobody eats, a belt that carries the product together with something else, and a belt
-- of raw items that something we made is put on; an underground belt entrance with no exit within
-- reach and an exit with no entrance; a belt that feeds the side of a splitter or of an underground
-- belt (the layout never does, and the game fills only one lane of an underground belt that way); and a
-- belt of a machine of `options.raw_lanes` that does not hold what the machine needs on the lanes it needs.
--
-- `options.machines` says, by entity name, what each machine is: {size, eats = items,
-- makes = item}. `options.raw` lists, by name, the machines fed by belts of raw items,
-- which the player supplies (those belts hold nothing of ours). `options.product` is the
-- item of the blueprint. The names of belts and inserters are "transport-belt" and
-- "inserter" unless `options.belt` and `options.inserter` say otherwise; those of the splitter and
-- the underground belt are "splitter" and "underground-belt" unless `options.splitter` and
-- `options.underground` say otherwise (an underground belt entity has `type` "input" for its
-- entrance and "output" for its exit). A fast inserter (`options.fast_inserter`, "fast-inserter" by default) is
-- an inserter like any other for the tracer. A long-handed inserter
-- (`options.long_inserter`, "long-handed-inserter" by default) picks up from and drops onto the tile
-- two away, over whatever stands between. The tracer follows it only when it takes from a belt into a
-- machine; one that puts items on a belt is reported, since the lane rules above are for a belt next to
-- the inserter.
-- `options.supplies` (optional) lists the belts of raw items that run to an input inserter
-- or to the side of another belt without passing a machine, which the player fills: each is
-- {x = tile column, y = tile row, item = name} for the first tile of the belt, and the item
-- rides both of its lanes. What the player supplies is not reported as something we made when it
-- is on a belt next to the inserter of a machine of `options.raw`.
-- `options.raw_lanes` (optional) says, by name of a machine of `options.raw`, what the belt that
-- its input inserters take from must hold: {item} is that item on both lanes, {first, second} is one
-- item on each lane, either way round.
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
local UNDERGROUND_REACH = 5

-- The items on the two lanes of a belt.
---@class bpgen.Lanes
---@field left table<string, true>
---@field right table<string, true>

-- One half of a splitter: a tile that moves items, with the way it faces. (A belt or a piece of an
-- underground belt is its own entity and has these fields too.)
---@class bpgen.SplitterHalf
---@field direction defines.direction
---@field splitter table  the entity

-- What the tracer knows about a blueprint, found once.
---@class bpgen.TraceIndex
---@field options table
---@field problems string[]
---@field tile table<table, bpgen.Tile>  the top-left tile of each entity (of a splitter half: its tile)
---@field by_tile table<string, table>  the entity that covers each tile
---@field belts table<string, table>  the belt on each tile
---@field flow table<string, table>  what moves items on each tile: a belt, a piece of an underground belt, or a splitter half
---@field kind table<table, "belt"|"entrance"|"exit"|"splitter">  of everything in `flow`
---@field twin table<table, table>  of a splitter half, the other half
---@field partner table<table, table>  of an underground belt exit, its entrance
---@field makers table[]  the inserters that take from a machine onto a belt: {inserter, machine, belt}
---@field takers table[]  the inserters that take from a belt into a machine: {inserter, machine, belt}
---@field drops table<table, bpgen.Lanes>  what inserters put on each belt
---@field supplied table<table, string>  the item the player puts on the first tile of a belt of raw items
---@field raw_items table<string, true>  every item the player supplies
---@field contents table<table, bpgen.Lanes>  the items on each tile that moves items, once worked out

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

---@param index bpgen.TraceIndex
---@param text string
local function report(index, text)
  index.problems[#index.problems + 1] = text
end

-- How many tiles an entity covers across and along the map: a machine is square, a splitter is two
-- tiles wide across its way, so two wide facing north or south and two tall facing east or west.
---@param options table
---@param entity table
---@return integer width
---@return integer height
local function dimensions(options, entity)
  if entity.name == (options.splitter or "splitter") then
    if entity.direction == direction.north or entity.direction == direction.south then
      return 2, 1
    end
    return 1, 2
  end
  local machine = options.machines[entity.name]
  local size = machine and machine.size or 1
  return size, size
end

-- Puts the two halves of a splitter in `flow`.
---@param index bpgen.TraceIndex
---@param entity table
---@param tile bpgen.Tile  its top-left tile
---@param width integer
---@param height integer
local function index_splitter(index, entity, tile, width, height)
  local halves = {}
  for dx = 0, width - 1 do
    for dy = 0, height - 1 do
      local half = {direction = entity.direction, splitter = entity}
      index.tile[half] = {x = tile.x + dx, y = tile.y + dy}
      index.flow[tile_key(tile.x + dx, tile.y + dy)] = half
      index.kind[half] = "splitter"
      halves[#halves + 1] = half
    end
  end
  index.twin[halves[1]], index.twin[halves[2]] = halves[2], halves[1]
end

-- Remembers where every entity is, and which tiles hold belts and the other pieces that move items.
---@param entities table[]
---@param options table
---@return bpgen.TraceIndex
local function index_of(entities, options)
  local index = {
    options = options, problems = {}, tile = {}, by_tile = {}, belts = {}, flow = {}, kind = {}, twin = {}, partner = {},
    makers = {}, takers = {}, drops = {}, contents = {}, supplied = {}, raw_items = {},
  }
  local belt_name = options.belt or "transport-belt"
  for _, entity in ipairs(entities) do
    local width, height = dimensions(options, entity)
    local tile = grid.top_left_tile(entity.position, width, height)
    index.tile[entity] = tile
    for dx = 0, width - 1 do
      for dy = 0, height - 1 do
        index.by_tile[tile_key(tile.x + dx, tile.y + dy)] = entity
      end
    end
    local key = tile_key(tile.x, tile.y)
    if entity.name == belt_name then
      index.belts[key], index.flow[key], index.kind[entity] = entity, entity, "belt"
    elseif entity.name == (options.underground or "underground-belt") then
      index.flow[key] = entity
      index.kind[entity] = entity.type == "input" and "entrance" or "exit"
    elseif entity.name == (options.splitter or "splitter") then
      index_splitter(index, entity, tile, width, height)
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

-- What moves items on the tile next to `node` the way `way` points.
---@param index bpgen.TraceIndex
---@param node table
---@param way defines.direction
---@return table|nil
local function flow_beside(index, node, way)
  local tile = index.tile[node]
  return index.flow[tile_key(tile.x + VECTOR[way].x, tile.y + VECTOR[way].y)]
end

-- Whether `source` puts what it carries on the tile of `target`. (The entrance of an underground
-- belt takes its items underground: it feeds only its exit.)
---@param index bpgen.TraceIndex
---@param source table
---@param target table
---@return boolean
local function outputs_into(index, source, target)
  return index.kind[source] ~= "entrance" and flow_beside(index, source, source.direction) == target
end

-- What feeds a tile from the side `side`, if it points into it.
---@param index bpgen.TraceIndex
---@param node table
---@param side defines.direction
---@return table|nil
local function feeder_from(index, node, side)
  local neighbour = flow_beside(index, node, side)
  if neighbour and outputs_into(index, neighbour, node) then
    return neighbour
  end
  return nil
end

-- What feeds a tile from behind, from its left and from its right.
---@param index bpgen.TraceIndex
---@param node table
---@return table|nil rear
---@return table|nil left
---@return table|nil right
local function feeders_of(index, node)
  local way = node.direction
  return feeder_from(index, node, OPPOSITE[way]), feeder_from(index, node, LEFT_OF[way]), feeder_from(index, node, RIGHT_OF[way])
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
    report(index, string.format("the long-handed inserter at %g,%g puts items on a belt, which the tracer does not follow", tile.x, tile.y))
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

-- The items on each lane of a belt: what inserters drop on it, what the player supplies on it,
-- and what the belts that feed it bring.
---@param index bpgen.TraceIndex
---@param belt table
---@param lanes bpgen.Lanes
---@param visiting table<table, true>
local function fill_belt(index, belt, lanes, visiting)
  if index.drops[belt] then
    add_along(lanes, index.drops[belt])
  end
  if index.supplied[belt] then
    lanes.left[index.supplied[belt]] = true
    lanes.right[index.supplied[belt]] = true
  end
  bring_in(index, belt, lanes, visiting)
end

-- What comes through a tile that moves items. An underground belt entrance holds what is behind it,
-- its exit holds what its entrance does, and a splitter half holds what both input tiles bring.
---@param index bpgen.TraceIndex
---@param node table
---@param lanes bpgen.Lanes
---@param visiting table<table, true>
local function fill_node(index, node, lanes, visiting)
  local kind = index.kind[node]
  if kind == "belt" then
    fill_belt(index, node, lanes, visiting)
  elseif kind == "exit" then
    local entrance = index.partner[node]
    if entrance then
      add_along(lanes, contents_of(index, entrance, visiting))
    end
  else
    local tiles = kind == "splitter" and {node, index.twin[node]} or {node}
    for _, tile in ipairs(tiles) do
      local rear = feeder_from(index, tile, OPPOSITE[tile.direction])
      if rear then
        add_along(lanes, contents_of(index, rear, visiting))
      end
    end
  end
end

-- The items on each lane of a tile that moves items. `visiting` holds the tiles being worked
-- out, to stop at a loop.
---@param index bpgen.TraceIndex
---@param node table
---@param visiting table<table, true>
---@return bpgen.Lanes
function contents_of(index, node, visiting)
  if index.contents[node] then
    return index.contents[node]
  end
  local lanes = new_lanes()
  if visiting[node] then
    return lanes
  end
  visiting[node] = true
  fill_node(index, node, lanes, visiting)
  visiting[node] = nil
  index.contents[node] = lanes
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
  for _, node in pairs(index.flow) do
    local lanes = contents_of(index, node, {})
    for _, side in ipairs({"left", "right"}) do
      local items = sorted_items(lanes[side])
      if #items > 1 then
        local tile = index.tile[node]
        report(index, string.format("the %s lane at %g,%g carries %s", side, tile.x, tile.y, table.concat(items, " and ")))
      end
    end
  end
end

-- The items on either lane of a tile that moves items.
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
-- belt must hold nothing that we made (what the player supplies is fine).
---@param index bpgen.TraceIndex
---@param taker table
local function check_raw_taker(index, taker)
  local tile = index.tile[taker.inserter]
  for item in pairs(items_on(index, taker.belt)) do
    if not index.raw_items[item] then
      report(index, string.format("the belt of raw items next to the inserter at %g,%g carries %s", tile.x, tile.y, item))
    end
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
      report(index, string.format("the input inserter at %g,%g never sees %s", tile.x, tile.y, item))
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
      report(index, "nothing eats " .. item)
    end
  end
end

-- A belt that carries the product carries nothing else.
---@param index bpgen.TraceIndex
local function check_product(index)
  for _, node in pairs(index.flow) do
    local items = items_on(index, node)
    if items[index.options.product] and #sorted_items(items) > 1 then
      local tile = index.tile[node]
      report(index, string.format("the belt at %g,%g carries the product together with something else", tile.x, tile.y))
    end
  end
end

-- Notes the belts the player fills with raw items.
---@param index bpgen.TraceIndex
local function note_supplies(index)
  for _, supply in ipairs(index.options.supplies or {}) do
    index.supplied[index.belts[tile_key(supply.x, supply.y)]] = supply.item -- a supply that is not on a belt is a mistake in the test: this fails
    index.raw_items[supply.item] = true
  end
end

-- The first piece of an underground belt in line with an entrance, within reach, or nil.
---@param index bpgen.TraceIndex
---@param entrance table
---@return table|nil
local function first_piece_ahead(index, entrance)
  local reach = index.options.underground_reach or UNDERGROUND_REACH
  for distance = 1, reach do
    local piece = entity_beside(index, entrance, entrance.direction, distance)
    if piece and piece.name == (index.options.underground or "underground-belt") then
      return piece
    end
  end
  return nil
end

-- Every entrance meets an exit that faces the same way, within reach, with no other piece of an
-- underground belt between them; every exit is met by an entrance.
---@param index bpgen.TraceIndex
local function pair_undergrounds(index)
  for node, kind in pairs(index.kind) do
    if kind == "entrance" then
      local piece = first_piece_ahead(index, node)
      if piece and piece.type == "output" and piece.direction == node.direction then
        index.partner[piece] = node
      else
        local tile = index.tile[node]
        report(index, string.format("the underground belt entrance at %g,%g meets no exit within reach", tile.x, tile.y))
      end
    end
  end
  for node, kind in pairs(index.kind) do
    if kind == "exit" and not index.partner[node] then
      local tile = index.tile[node]
      report(index, string.format("the underground belt exit at %g,%g has no entrance", tile.x, tile.y))
    end
  end
end

-- Nothing feeds the side of a splitter or of a piece of an underground belt.
---@param index bpgen.TraceIndex
local function check_sides(index)
  for node, kind in pairs(index.kind) do
    if kind ~= "belt" then
      local _, left, right = feeders_of(index, node)
      if left or right then
        local tile = index.tile[node]
        report(index, string.format("a belt feeds the side of the %s at %g,%g", kind, tile.x, tile.y))
      end
    end
  end
end

-- Whether the lanes hold `expected`: one item on both lanes, or two items one on each lane.
---@param lanes bpgen.Lanes
---@param expected string[]
---@return boolean
local function lanes_match(lanes, expected)
  local left, right = sorted_items(lanes.left), sorted_items(lanes.right)
  local function only(list, item)
    return #list == 1 and list[1] == item
  end
  if #expected == 1 then
    return only(left, expected[1]) and only(right, expected[1])
  end
  return (only(left, expected[1]) and only(right, expected[2])) or (only(left, expected[2]) and only(right, expected[1]))
end

-- The belt that the input inserters of a machine of `raw_lanes` take from holds what the machine needs, on the lanes it needs.
---@param index bpgen.TraceIndex
local function check_raw_lanes(index)
  local expectations = index.options.raw_lanes
  for _, taker in ipairs(index.takers) do
    local expected = expectations and expectations[taker.machine.name]
    local lanes = expected and contents_of(index, taker.belt, {})
    if lanes and not lanes_match(lanes, expected) then
      local tile = index.tile[taker.inserter]
      report(index, string.format("the belt next to the inserter at %g,%g carries [%s] on its left lane and [%s] on its right lane, not %s",
        tile.x, tile.y, table.concat(sorted_items(lanes.left), ","), table.concat(sorted_items(lanes.right), ","), table.concat(expected, " and ")))
    end
  end
end

---@param entities table[]  blueprint entities with positions and directions
---@param options table  see the top of the file
---@return string[] problems  empty when the flow is sound
function tracer.problems(entities, options)
  local index = index_of(entities, options)
  note_supplies(index)
  pair_undergrounds(index)
  for _, entity in ipairs(entities) do
    if entity.name == (options.inserter or "inserter") or entity.name == (options.fast_inserter or "fast-inserter") then
      classify(index, entity, 1)
    elseif entity.name == (options.long_inserter or "long-handed-inserter") then
      classify(index, entity, 2)
    end
  end
  note_drops(index)
  check_sides(index)
  check_lanes(index)
  check_raw_lanes(index)
  check_outputs(index, check_inputs(index))
  check_product(index)
  table.sort(index.problems)
  return index.problems
end

return tracer
