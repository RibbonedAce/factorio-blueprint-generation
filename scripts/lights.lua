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

local grid = require("scripts.grid")

local lights = {}

local MIN_GAP = 10  -- tiles: no two lamps are closer than this
local COVER = 10  -- tiles: every powered tile has a lamp this close

-- The tile a belt runs on to, by the direction it faces, as a step in tiles.
---@return table<integer, {x: integer, y: integer}>
local function steps()
  local directions = defines.direction
  return {
    [directions.north] = {x = 0, y = -1}, [directions.south] = {x = 0, y = 1},
    [directions.east] = {x = 1, y = 0}, [directions.west] = {x = -1, y = 0},
  }
end

---@param x integer
---@param y integer
---@return string
local function key(x, y)
  return x .. "," .. y
end

-- The tiles that hold something, and the tiles ahead of the belts.
---@param entities bpgen.Entity[]
---@param options bpgen.LightOptions
---@return table<string, true>
local function taken_tiles(entities, options)
  local belts, taken, step = {}, {}, steps()
  for _, name in ipairs(options.belts or {}) do
    belts[name] = true
  end
  for _, entity in ipairs(entities) do
    local width, height = options.size_of(entity)
    local tile = grid.top_left_tile(entity.position, width, height)
    for dx = 0, width - 1 do
      for dy = 0, height - 1 do
        taken[key(tile.x + dx, tile.y + dy)] = true
      end
    end
    if belts[entity.name] and step[entity.direction] then
      taken[key(tile.x + step[entity.direction].x, tile.y + step[entity.direction].y)] = true
    end
  end
  return taken
end

-- The tiles inside the supply area of a pole, from the top row down and from the left in a row, once each.
---@param entities bpgen.Entity[]
---@param options bpgen.LightOptions
---@return {x: integer, y: integer}[] list
---@return table<string, true> set
local function powered_tiles(entities, options)
  local reach = math.floor(options.supply_distance + 0.5 - 1e-9) -- a tile is powered when the area covers part of it
  local set, list = {}, {}
  for _, entity in ipairs(entities) do
    if entity.name == options.pole then
      local centre = grid.top_left_tile(entity.position)
      for dx = -reach, reach do
        for dy = -reach, reach do
          local x, y = centre.x + dx, centre.y + dy
          if not set[key(x, y)] then
            set[key(x, y)] = true
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
  local taken = taken_tiles(entities, options)
  local list, powered = powered_tiles(entities, options)
  local function free(x, y)
    return powered[key(x, y)] and not taken[key(x, y)]
  end
  local lamps = {}
  for _, tile in ipairs(list) do
    local spot = not has_lamp_within_reach(lamps, tile) and spot_for(tile, lamps, free)
    if spot then
      lamps[#lamps + 1] = spot
      entities[#entities + 1] = {name = options.lamp, position = grid.position(spot.x, spot.y), entity_number = #entities + 1}
    end
  end
end

return lights
