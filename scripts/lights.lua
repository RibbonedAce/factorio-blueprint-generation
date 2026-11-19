-- scripts/lights.lua
-- Puts lamps on a finished blueprint, on free tiles that a pole powers. Pure, like scripts/layout.lua.
--
-- Two rules, the first one hard and the second one soft:
--   * no two lamps are closer than `MIN_GAP` tiles;
--   * every tile a pole powers has a lamp within `COVER` tiles.
--
-- The tiles a pole powers are the ones inside its supply area, which is where the lamps go too (a lamp has
-- to be powered). They are taken from the top row down, left to right. A tile with no lamp within reach gets
-- one on the closest free tile that is at least `MIN_GAP` from every lamp so far, which is the tile itself
-- when it is free: so the hard rule holds by construction, and the soft rule fails only where no free tile
-- is left to put a lamp on. A tile that something stands on, and the tile a belt runs on to, are not free
-- (the player goes on with the belts that leave the blueprint).

local constants = require("scripts.constants")
local entity_list = require("scripts.entity_list")
local grid = require("scripts.grid")

local lights = {}

local MIN_GAP = 10  -- tiles: no two lamps are closer than this
local COVER = 10  -- tiles: every powered tile has a lamp this close

local north, east, south, west = defines.direction.north, defines.direction.east, defines.direction.south, defines.direction.west

-- The tile a belt runs on to, by the direction it faces, as a step in tiles.
---@type table<integer, {x: integer, y: integer}>
local STEPS = {
  [north] = {x = 0, y = -1}, [south] = {x = 0, y = 1},
  [east] = {x = 1, y = 0}, [west] = {x = -1, y = 0},
}

-- The set of names in a list, or an empty one for no list.
---@param list string[]|nil
---@return table<string, true>
local function set_of(list)
  local set = {}
  for _, name in ipairs(list or {}) do
    set[name] = true
  end
  return set
end

-- Marks the tile next to each entity whose name is in `names`, on the way it faces: the tile ahead of it for a `sign` of 1,
-- the tile behind it for -1.
---@param taken table<string, true>
---@param entities bpgen.Entity[]
---@param names table<string, true>
---@param size_of fun(entity: bpgen.Entity): integer, integer
---@param sign integer
local function mark_next_to(taken, entities, names, size_of, sign)
  for _, entity in ipairs(entities) do
    local way = STEPS[entity.direction]
    if names[entity.name] and way then
      local tile = grid.top_left_tile(entity.position, size_of(entity))
      taken[grid.key(tile.x + sign * way.x, tile.y + sign * way.y)] = true
    end
  end
end

-- The tiles that hold something, the tiles ahead of the belts and the tiles behind the inlets.
---@param entities bpgen.Entity[]
---@param options bpgen.LightOptions
---@return table<string, true>
function lights.taken_tiles(entities, options)
  local taken = grid.taken_tiles(entities, options.size_of)
  mark_next_to(taken, entities, set_of(options.belts), options.size_of, 1)
  mark_next_to(taken, entities, set_of(options.inlets), options.size_of, -1) -- where its input is
  return taken
end

-- The tiles inside the supply area of a pole, from the top row down and from the left in a row, once each.
---@param entities bpgen.Entity[]
---@param options bpgen.LightOptions
---@return {x: integer, y: integer}[] list
---@return table<string, true> set
local function powered_tiles(entities, options)
  local reach = math.floor(options.supply_distance + 0.5 - constants.EPSILON) -- a tile is powered when the area covers part of it
  local set, list = {}, {}
  for _, entity in ipairs(entities) do
    if entity.name == options.pole then
      local centre = grid.top_left_tile(entity.position)
      for dx = -reach, reach do
        for dy = -reach, reach do
          local x, y = centre.x + dx, centre.y + dy
          if not set[grid.key(x, y)] then
            set[grid.key(x, y)] = true
            list[#list + 1] = {x = x, y = y}
          end
        end
      end
    end
  end
  table.sort(list, function(a, b) return a.y < b.y or (a.y == b.y and a.x < b.x) end)
  return list, set
end

-- The squared distance between two tiles, which is all the rules compare.
---@param a {x: integer, y: integer}
---@param b {x: integer, y: integer}
---@return integer
local function squared(a, b)
  return (a.x - b.x) ^ 2 + (a.y - b.y) ^ 2
end

---@param lamps {x: integer, y: integer}[]
---@param tile {x: integer, y: integer}
---@return boolean
local function has_lamp_within_reach(lamps, tile)
  for _, lamp in ipairs(lamps) do
    if squared(lamp, tile) <= COVER ^ 2 then
      return true
    end
  end
  return false
end

---@param lamps {x: integer, y: integer}[]
---@param tile {x: integer, y: integer}
---@return boolean
local function far_from_lamps(lamps, tile)
  for _, lamp in ipairs(lamps) do
    if squared(lamp, tile) < MIN_GAP ^ 2 then
      return false
    end
  end
  return true
end

-- Where a lamp goes to cover `tile`: the closest free powered tile within reach of it that is far enough from
-- every lamp, the earlier one of two that are as close; nil when there is none.
---@param tile {x: integer, y: integer}
---@param lamps {x: integer, y: integer}[]
---@param free fun(x: integer, y: integer): boolean  whether a lamp may stand on the tile
---@return {x: integer, y: integer}|nil
local function spot_for(tile, lamps, free)
  local best, best_apart
  for dy = -COVER, COVER do
    for dx = -COVER, COVER do
      local spot = {x = tile.x + dx, y = tile.y + dy}
      local apart = squared(spot, tile)
      if apart <= COVER ^ 2 and (not best or apart < best_apart) and free(spot.x, spot.y) and far_from_lamps(lamps, spot) then
        best, best_apart = spot, apart
      end
    end
  end
  return best
end

-- Adds the lamps to `entities`, numbered after the entities there are. Without a pole there are none.
---@param entities bpgen.Entity[]  the finished blueprint; the lamps are appended
---@param options bpgen.LightOptions
function lights.add(entities, options)
  local taken = lights.taken_tiles(entities, options)
  local list, powered = powered_tiles(entities, options)
  local function free(x, y)
    return powered[grid.key(x, y)] and not taken[grid.key(x, y)]
  end
  local lamps = {}
  for _, tile in ipairs(list) do
    local spot = not has_lamp_within_reach(lamps, tile) and spot_for(tile, lamps, free)
    if spot then
      lamps[#lamps + 1] = spot
      entity_list.append(entities, {name = options.lamp, position = grid.position(spot.x, spot.y)})
    end
  end
end

return lights
