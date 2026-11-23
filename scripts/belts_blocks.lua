-- scripts/belts_blocks.lua
-- Blocks of steps on belts, as the chains of scripts/item_fluid_chain.lua take them (see `bpgen.BeltsBlock`): where the block made by the original
-- design of the belts sends its product out and takes its raw items in, which are the belts that run south at its two ends, and the block of a
-- raw item that has no machines, only the belt that comes in. Pure, like scripts/accounting.lua.

local entity_list = require("scripts.entity_list")
local grid = require("scripts.grid")

local belts_blocks = {}

local north, east, south, west = defines.direction.north, defines.direction.east, defines.direction.south, defines.direction.west

-- The tiles of the belts of the entities, as a set of `grid.key`s, and the tiles of those that run south, as a list.
---@param entities bpgen.Entity[]
---@param belt string  the prototype name of the belt
---@return table<string, true> all
---@return {x: number, y: number}[] runs_south
local function belt_tiles(entities, belt)
  local all, runs_south = {}, {}
  for _, entity in ipairs(entities) do
    if entity.name == belt then
      local tile = grid.top_left_tile(entity.position)
      all[grid.key(tile.x, tile.y)] = true
      if entity.direction == south then
        runs_south[#runs_south + 1] = tile
      end
    end
  end
  return all, runs_south
end

-- The last tile of the belt of product of a block of the belts layout: the tile of a belt that runs south with no belt in front of it, furthest
-- east (the belts of raw items end further west) and, in that column, the lowest.
---@param entities bpgen.Entity[]
---@param belt string  the prototype name of the belt
---@return {column: integer, last_row: integer}
function belts_blocks.product_end(entities, belt)
  local all, runs_south = belt_tiles(entities, belt)
  local ends = {}
  for _, tile in ipairs(runs_south) do
    if not all[grid.key(tile.x, tile.y + 1)] then
      ends[#ends + 1] = tile
    end
  end
  table.sort(ends, function(first, second)
    if first.x ~= second.x then
      return first.x > second.x
    end
    return first.y > second.y
  end)
  local last = assert(ends[1], "generator: the block of furnaces has no belt of product")
  return {column = last.x, last_row = last.y}
end

-- The first tile of the belt of raw items of the original design, which comes in at the top of the block, running south: the tile of a
-- belt that runs south with no belt behind it, furthest west and, in that column, the highest.
---@param entities bpgen.Entity[]
---@param belt string  the prototype name of the belt
---@return {x: integer, y: integer}
function belts_blocks.raw_start(entities, belt)
  local all, runs_south = belt_tiles(entities, belt)
  local starts = {}
  for _, tile in ipairs(runs_south) do
    if not all[grid.key(tile.x, tile.y - 1)] then
      starts[#starts + 1] = tile
    end
  end
  table.sort(starts, function(first, second)
    if first.x ~= second.x then
      return first.x < second.x
    end
    return first.y < second.y
  end)
  return assert(starts[1], "generator: the block of furnaces has no belt of raw items")
end

-- The block of the part of a chain whose second item is raw: no machines, only the belt that comes in at the top left, which is the belt of
-- its product too (a single tile, from which the chain takes it on), and what it takes a minute in the design that brings in one belt of each
-- material.
---@param item string
---@param belt string  the prototype name of the belt
---@param feed? bpgen.Feed  what the belt takes a minute, in the design that brings in one belt of each material
---@return bpgen.BeltsBlock
function belts_blocks.of_raw_item(item, belt, feed)
  local entities = {}
  entity_list.append(entities, {name = belt, position = grid.position(0, 0), direction = south})
  return {entities = entities, poles = {}, product = {column = 0, last_row = 0}, raw = {{key = item, x = 0, y = 0, feed = feed}}}
end

return belts_blocks
