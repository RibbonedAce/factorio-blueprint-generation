-- scripts/poles.lua
-- Wires the poles of a blueprint's columns into one network. Pure, like scripts/layout.lua.
--
-- Each column is already wired inside. The nearest column is joined to the poles joined so far, by the
-- nearest pair of poles. The layout does not read the reach of a pole from the game: the specs check that
-- these wires are short enough for the shapes the generator makes.
--
-- The input design that brings in one belt of each material (.agents/inputs-plan.md) hangs the chains lower
-- than a short final column, which can leave the nearest pair further apart than a wire reaches. Given a
-- `bridge`, the module then puts poles on free tiles between them, each as far toward the other end as a
-- wire reaches.

local grid = require("scripts.grid")
local layout = require("scripts.layout")

local poles = {}

-- How far apart two small poles may be and still be wired: a little under the 7.5 tiles the game allows.
local WIRE_REACH = 7

-- Two poles and how far apart they are.
---@class bpgen.PolePair
---@field from bpgen.Entity
---@field to bpgen.Entity
---@field distance number

---@param x number
---@param y number
---@return string
local function tile_key(x, y)
  return string.format("%g,%g", x, y)
end

-- Appends the items of `more` to `list`, and gives back `list`.
---@generic T
---@param list T[]
---@param more T[]
---@return T[]
local function append(list, more)
  for _, item in ipairs(more) do
    list[#list + 1] = item
  end
  return list
end

---@param first bpgen.Position
---@param second bpgen.Position
---@return number
local function distance(first, second)
  local dx, dy = first.x - second.x, first.y - second.y
  return math.sqrt(dx * dx + dy * dy)
end

-- The closest pair of poles, one from each list, or nil when one list is empty.
---@param group bpgen.Entity[]
---@param others bpgen.Entity[]
---@return bpgen.PolePair|nil
local function closest_pair(group, others)
  local best
  for _, pole in ipairs(group) do
    for _, other in ipairs(others) do
      local apart = distance(pole.position, other.position)
      if not best or apart < best.distance then
        best = {from = pole, to = other, distance = apart}
      end
    end
  end
  return best
end

-- The group among `waiting` that is closest to the poles in `joined`, with the pair of
-- poles that are closest, or nil when no group has a pole.
---@param joined bpgen.Entity[]
---@param waiting bpgen.Entity[][]
---@return bpgen.PolePair|nil
---@return integer|nil index  of the group in `waiting`
local function closest_group(joined, waiting)
  local best, best_index
  for index, group in ipairs(waiting) do
    local pair = closest_pair(joined, group)
    if pair and (not best or pair.distance < best.distance) then
      best, best_index = pair, index
    end
  end
  return best, best_index
end

-- The free tile within wire reach of `from` that is closest to `to`, as a position, or nil when there is none.
---@param taken table<string, true>
---@param from bpgen.Position
---@param to bpgen.Position
---@return bpgen.Position|nil
local function free_tile_toward(taken, from, to)
  local best, best_apart
  local reach = math.floor(WIRE_REACH)
  for dx = -reach, reach do
    for dy = -reach, reach do
      local x, y = math.floor(from.x) + dx, math.floor(from.y) + dy
      local centre = grid.position(x, y)
      if not taken[tile_key(x, y)] and distance(centre, from) <= WIRE_REACH then
        local apart = distance(centre, to)
        if not best or apart < best_apart then
          best, best_apart = centre, apart
        end
      end
    end
  end
  return best
end

-- Puts a pole on the free tile within reach of `from` that is closest to `to`.
---@param bridge bpgen.PoleBridge
---@param from bpgen.Entity
---@param to bpgen.Entity
---@return bpgen.Entity
local function add_bridge_pole(bridge, from, to)
  local centre = free_tile_toward(bridge.taken, from.position, to.position)
  assert(centre and distance(centre, to.position) < distance(from.position, to.position), "poles: no room for a pole between two poles")
  bridge.taken[tile_key(centre.x - 0.5, centre.y - 0.5)] = true
  local pole = {name = bridge.pole, position = centre} --[[@as bpgen.Entity]]
  bridge.entities[#bridge.entities + 1] = pole
  pole.entity_number = #bridge.entities
  return pole
end

-- Wires `from` to `to`, with bridge poles between them when they are further apart than a wire reaches
-- (and there is a bridge to put them in).
---@param from bpgen.Entity
---@param to bpgen.Entity
---@param bridge bpgen.PoleBridge|nil
local function connect(from, to, bridge)
  local previous = from
  while bridge and distance(previous.position, to.position) > WIRE_REACH do
    local pole = add_bridge_pole(bridge, previous, to)
    layout.connect_poles(previous, pole)
    previous = pole
  end
  layout.connect_poles(previous, to)
end

-- The tiles that hold something, for the bridge poles to keep off. `size_of` says how many tiles
-- an entity covers across and along the map.
---@param entities bpgen.Entity[]
---@param size_of fun(entity: bpgen.Entity): integer, integer
---@return table<string, true>
function poles.taken_tiles(entities, size_of)
  local taken = {}
  for _, entity in ipairs(entities) do
    local width, height = size_of(entity)
    local tile = grid.top_left_tile(entity.position, width, height)
    for dx = 0, width - 1 do
      for dy = 0, height - 1 do
        taken[tile_key(tile.x + dx, tile.y + dy)] = true
      end
    end
  end
  return taken
end

-- Joins groups of poles into one network. Each group is already wired inside; the nearest group
-- is joined to the poles joined so far, by the nearest pair of poles. A group with no pole is left out.
---@param groups bpgen.Entity[][]  at least one group has a pole
---@param bridge? bpgen.PoleBridge  to put poles between two that are further apart than a wire reaches
function poles.join(groups, bridge)
  local waiting = {}
  for _, group in ipairs(groups) do
    if #group > 0 then
      waiting[#waiting + 1] = group
    end
  end
  local joined = append({}, table.remove(waiting, 1))
  local pair, index = closest_group(joined, waiting)
  while pair and index do
    connect(pair.from, pair.to, bridge)
    append(joined, table.remove(waiting, index))
    pair, index = closest_group(joined, waiting)
  end
end

return poles
