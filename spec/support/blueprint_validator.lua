-- spec/support/blueprint_validator.lua
-- Checks that a list of blueprint entities is physically sensible, whatever
-- layout produced it. Test tooling only: the game never loads this folder.
--
--     local problems = validator.validate(entities, catalog)
--
-- `problems` is a list of readable strings; an empty list means the blueprint
-- passed. The checks, run in this order, are:
--   1. every entity is known to the catalog, and entity numbers are unique
--   2. every entity sits on the tile grid (odd sizes on half tiles, even on whole)
--   3. no two entities cover the same tile
--   4. every inserter picks up from, and drops onto, a belt or a machine, and at
--      least one of the two is a machine
--   5. every entity that needs power is inside a pole's supply area
--   6. every wire joins two poles within reach, and all poles form one network
--
-- Deliberately NOT checked (the owner's decision): belt paths, because later
-- layouts may bend belts to save space, and item flow, because that is a
-- game-specific quirk. Sizes and ranges come from the catalog the caller passes
-- in, so the numbers in it can be made up: nothing here depends on their values.
--
-- The catalog maps an entity name to its description:
--   {kind = "belt" | "machine" | "inserter" | "pole" | "lamp",
--    width = tiles, height = tiles,
--    turns = true,                -- optional: covers height x width tiles facing east or west (a splitter)
--    needs_power = true,          -- optional, for things a pole must reach
--    reach = tiles,               -- inserters only: how far away it picks up and drops, default 1
--    supply_radius = tiles,       -- poles only: how far from its centre it powers
--    wire_reach = tiles}          -- poles only: the longest wire it can hold
--
-- Like `layout.lua`, this reads the table `defines` (here the direction names
-- and the copper wire connector); a test must define it before calling.
--
-- Every check is its own small private function below. They share one "index"
-- of the blueprint, built first by `index_entities`:
--   index.catalog    the catalog passed in
--   index.usable     entities that passed checks 1 and 2, in blueprint order
--   index.by_number  every known entity with a valid, unique number, by number
--   index.by_tile    which usable entity covers each tile (filled by check 3)
--   index.poles      the usable poles

local validator = {}

--------------------------------------------------------------------------------
-- Small helpers
--------------------------------------------------------------------------------

-- The tile an inserter picks up from, relative to its own position, for each
-- direction name. It drops on the opposite side. (Assumption: an inserter's
-- direction is the side it picks up from. See .agents/project-status.md.)
local function pickup_offsets()
  local directions = defines.direction
  return {
    [directions.north] = {x = 0, y = -1},
    [directions.south] = {x = 0, y = 1},
    [directions.east] = {x = 1, y = 0},
    [directions.west] = {x = -1, y = 0},
  }
end

-- A tile is named by its top-left corner, written as text so it can be a table key.
local function tile_key(x, y)
  return string.format("%g,%g", x, y)
end

-- The width and the height an entity covers as it stands. An entity that `turns` (a splitter) is
-- `width` x `height` facing north or south, and the other way round facing east or west.
local function size_of(entity, description)
  local directions = defines.direction
  if description.turns and (entity.direction == directions.east or entity.direction == directions.west) then
    return description.height, description.width
  end
  return description.width, description.height
end

local function tiles_of(entity, description)
  local keys = {}
  local width, height = size_of(entity, description)
  local left = entity.position.x - width / 2
  local top = entity.position.y - height / 2
  for dx = 0, width - 1 do
    for dy = 0, height - 1 do
      keys[#keys + 1] = tile_key(left + dx, top + dy)
    end
  end
  return keys
end

-- Is `value` a whole number (for an even size) or a whole number plus a half (odd size)?
local function on_grid(value, size)
  local expected_fraction = (size % 2 == 1) and 0.5 or 0
  return (value - expected_fraction) % 1 == 0
end

local function is_aligned(entity, description)
  local width, height = size_of(entity, description)
  return on_grid(entity.position.x, width) and on_grid(entity.position.y, height)
end

-- Adds "<name> #<number>: <text>" to `problems`; with no entity, just the text.
local function add_problem(problems, entity, text)
  local who = entity and string.format("%s #%s: ", tostring(entity.name), tostring(entity.entity_number)) or ""
  problems[#problems + 1] = who .. text
end

--------------------------------------------------------------------------------
-- Checks 1 and 2: known entities, unique numbers, aligned positions
--------------------------------------------------------------------------------

-- Why this entity cannot be used at all, as text, or nil if it is fine.
-- `description` is its catalog entry (nil when the name is unknown).
local function identity_fault(entity, description, by_number)
  if not description then
    return "is not in the catalog"
  end
  if by_number[entity.entity_number] then
    return "reuses an entity number"
  end
  if type(entity.entity_number) ~= "number" then
    return "has no entity number"
  end
end

local function kind_of(index, entity)
  return entity and index.catalog[entity.name].kind
end

local function usable_of_kind(index, kind)
  local found = {}
  for _, entity in ipairs(index.usable) do
    if kind_of(index, entity) == kind then
      found[#found + 1] = entity
    end
  end
  return found
end

-- Entities that fail here are left out of `usable`, so later checks can rely on
-- every usable entity having a catalog entry, a number and an aligned position.
local function index_entities(entities, catalog, problems)
  local index = {catalog = catalog, usable = {}, by_number = {}, by_tile = {}}
  for _, entity in ipairs(entities) do
    local description = catalog[entity.name]
    local fault = identity_fault(entity, description, index.by_number)
    if fault then
      add_problem(problems, entity, fault)
    else
      index.by_number[entity.entity_number] = entity
      if is_aligned(entity, description) then
        index.usable[#index.usable + 1] = entity
      else
        add_problem(problems, entity, "is not aligned to the tile grid")
      end
    end
  end
  index.poles = usable_of_kind(index, "pole")
  return index
end

--------------------------------------------------------------------------------
-- Check 3: overlaps
--------------------------------------------------------------------------------

-- Also fills `index.by_tile`, which the inserter check reads.
local function find_overlaps(index, problems)
  for _, entity in ipairs(index.usable) do
    for _, key in ipairs(tiles_of(entity, index.catalog[entity.name])) do
      local other = index.by_tile[key]
      if other then
        add_problem(problems, entity,
          string.format("overlaps %s #%d on tile %s", other.name, other.entity_number, key))
      else
        index.by_tile[key] = entity
      end
    end
  end
end

--------------------------------------------------------------------------------
-- Check 4: inserters
--------------------------------------------------------------------------------

-- The usable entity on the tile `dx`, `dy` tiles from a 1x1 entity, or nil.
-- (A 1x1 entity is centred on a half tile, so its tile's corner is 0.5 back.)
local function entity_beside(index, entity, dx, dy)
  return index.by_tile[tile_key(entity.position.x + dx - 0.5, entity.position.y + dy - 0.5)]
end

local function holds_items(kind)
  return kind == "belt" or kind == "machine"
end

local function check_inserter_ends(inserter, from, to, index, problems)
  local from_kind, to_kind = kind_of(index, from), kind_of(index, to)
  local picks_up, drops = holds_items(from_kind), holds_items(to_kind)
  if not picks_up then
    add_problem(problems, inserter, "has nothing to pick up from")
  end
  if not drops then
    add_problem(problems, inserter, "has nothing to drop onto")
  end
  if picks_up and drops and from_kind ~= "machine" and to_kind ~= "machine" then
    add_problem(problems, inserter, "does not touch a machine")
  end
end

local function check_inserter(inserter, offsets, index, problems)
  local offset = offsets[inserter.direction]
  if not offset then
    add_problem(problems, inserter, "has no usable direction")
    return
  end
  local reach = index.catalog[inserter.name].reach or 1
  local from = entity_beside(index, inserter, offset.x * reach, offset.y * reach)
  local to = entity_beside(index, inserter, -offset.x * reach, -offset.y * reach)
  check_inserter_ends(inserter, from, to, index, problems)
end

local function check_inserters(index, problems)
  local offsets = pickup_offsets()
  for _, inserter in ipairs(usable_of_kind(index, "inserter")) do
    check_inserter(inserter, offsets, index, problems)
  end
end

--------------------------------------------------------------------------------
-- Check 5: power
--------------------------------------------------------------------------------

-- A pole's supply area is a square of `supply_radius` around its centre; an
-- entity is powered if its footprint overlaps that square.
local function is_powered(entity, description, index)
  local width, height = size_of(entity, description)
  for _, pole in ipairs(index.poles) do
    local radius = index.catalog[pole.name].supply_radius
    if math.abs(pole.position.x - entity.position.x) < radius + width / 2
        and math.abs(pole.position.y - entity.position.y) < radius + height / 2 then
      return true
    end
  end
  return false
end

local function check_power(index, problems)
  for _, entity in ipairs(index.usable) do
    local description = index.catalog[entity.name]
    if description.needs_power and not is_powered(entity, description, index) then
      add_problem(problems, entity, "is outside every pole's supply area")
    end
  end
end

--------------------------------------------------------------------------------
-- Check 6: wires and networks
--------------------------------------------------------------------------------

-- Groups poles that wires connect (a union-find over entity numbers).
-- `join` ignores numbers that are not poles in the network, such as a pole that
-- was already reported as misaligned.
local function new_network(poles)
  local parent = {}
  for _, pole in ipairs(poles) do
    parent[pole.entity_number] = pole.entity_number
  end

  local function find(number)
    while parent[number] ~= number do
      number = parent[number]
    end
    return number
  end

  local network = {}

  function network.join(first, second)
    if parent[first] and parent[second] then
      parent[find(first)] = find(second)
    end
  end

  ---@return integer
  function network.count()
    local roots, count = {}, 0
    for number in pairs(parent) do
      local root = find(number)
      if not roots[root] then
        roots[root] = true
        count = count + 1
      end
    end
    return count
  end

  return network
end

-- Each wire is {source number, source connector, target number, target
-- connector}, listed on its source entity. Returns what is wrong with it, or nil.
local function wire_fault(owner, wire, from, to, index)
  local copper = defines.wire_connector_id.pole_copper
  if wire[1] ~= owner.entity_number then
    return "lists a wire that starts on another entity"
  end
  if kind_of(index, from) ~= "pole" or kind_of(index, to) ~= "pole" then
    return "has a wire that does not join two poles"
  end
  if wire[2] ~= copper or wire[4] ~= copper then
    return "has a wire that does not use the copper connector"
  end
end

local function is_longer_than_reach(from, to, catalog)
  local dx, dy = from.position.x - to.position.x, from.position.y - to.position.y
  local reach = math.min(catalog[from.name].wire_reach, catalog[to.name].wire_reach)
  return math.sqrt(dx * dx + dy * dy) > reach
end

local function check_wire(owner, wire, index, network, problems)
  local from, to = index.by_number[wire[1]], index.by_number[wire[3]]
  local fault = wire_fault(owner, wire, from, to, index)
  if fault then
    add_problem(problems, owner, fault)
    return
  end
  if is_longer_than_reach(from, to, index.catalog) then
    add_problem(problems, owner,
      string.format("has a wire to #%d that is longer than its reach", to.entity_number))
  end
  network.join(from.entity_number, to.entity_number)
end

local function check_wires(index, problems)
  local network = new_network(index.poles)
  for _, owner in ipairs(index.usable) do
    for _, wire in ipairs(owner.wires or {}) do
      check_wire(owner, wire, index, network, problems)
    end
  end
  if network.count() > 1 then
    add_problem(problems, nil, string.format("the poles form %d separate networks", network.count()))
  end
end

--------------------------------------------------------------------------------

---@class bpgen.CatalogEntry  what the validator knows about one entity name
---@field kind "belt"|"machine"|"inserter"|"pole"|"lamp"
---@field width number  tiles
---@field height number  tiles
---@field turns? boolean  the entity covers `height` x `width` tiles when it faces east or west (a splitter)
---@field needs_power? boolean
---@field reach? number  inserters only: tiles away that it picks up and drops, 1 by default (2 for a long-handed inserter)
---@field supply_radius? number  poles only
---@field wire_reach? number  poles only

---@param entities table[]  normally bpgen.Entity, but damaged ones (no number, no position) are what it exists to report
---@param catalog table<string, bpgen.CatalogEntry>  keyed by entity name
---@return string[] problems  empty when the blueprint passed
function validator.validate(entities, catalog)
  local problems = {}
  local index = index_entities(entities, catalog, problems)
  find_overlaps(index, problems)
  check_inserters(index, problems)
  check_power(index, problems)
  check_wires(index, problems)
  return problems
end

return validator
