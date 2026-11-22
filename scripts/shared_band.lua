-- scripts/shared_band.lua
-- The belts of raw items of a blueprint made of several blocks that stand side by side (the chains of scripts/item_fluid_chain.lua), brought in
-- through one band along the top, as scripts/rows.lua does for the columns of a recipe: the player brings one belt of each material (coal too),
-- and the blueprint divides it with splitters and makes the belts its furnaces need, ore on one lane and fuel on the other, from the pure
-- ones. Which belt feeds what is scripts/feeds.lua's, and the band is drawn by scripts/inputs.lua; this module only says where each belt that
-- comes down to a block is, and puts the blocks under the band. Pure, like scripts/corner_entries.lua.
--
-- Every block has a belt of raw items that comes down its column from the top row (a START with a `feed`, what it takes a minute). The band
-- needs the columns east of its own (`inputs.start_column`), and the rows above the blocks, so the blocks move east and down together, by the
-- same amounts, which keeps everything of the blueprint where it is in relation to the rest. The belt of each block goes on down from the last
-- tile of the belt that comes down from the band to the first tile of its own, where the blocks stand lower than the band's belts end:
--
--     0 |>>v..........       the coal comes in and goes down its bus
--     1 |..v..........
--     2 |..SS.>>>>>>>>v      the band: a trunk, and the belts that come down from it
--     3 |..v>>^.......v
--       |..v..........v      the belts that the band does not draw, down to the block (here: a tile of each)
--     6 |..>>>^.......v}FF}   the first rows of the block
--
-- A start without a `feed` is a pipe or a belt that does not come down from the band: the caller brings those in (scripts/corner_entries.lua).

local entity_list = require("scripts.entity_list")
local feeds = require("scripts.feeds")
local inputs = require("scripts.inputs")

local shared_band = {}

-- A belt of raw items that comes down to a block, as a leaf of the band (see `feeds.plan`).
---@class bpgen.BandLeaf : bpgen.FeedLeaf
---@field start bpgen.EntryStart  where its belt comes down: the column, and the row of the first tile of the block's own belt

-- The result of `shared_band.add`.
---@class bpgen.SharedBand
---@field starts bpgen.EntryStart[]  the starts that have no `feed`, moved with the blocks
---@field supplies bpgen.Supply[]  the belts the player brings in, from the top down
---@field dx integer  how many columns the blocks moved east
---@field dy integer  how many rows the blocks moved down

-- The leaves of the starts that have a `feed`, numbered from the west.
---@param starts bpgen.EntryStart[]
---@return bpgen.BandLeaf[]
local function leaves_of(starts)
  local belts = {}
  for _, start in ipairs(starts) do
    if start.feed then
      belts[#belts + 1] = start
    end
  end
  table.sort(belts, function(first, second) return first.x < second.x end)
  local leaves = {}
  for index, start in ipairs(belts) do
    leaves[index] = {index = index, feed = start.feed, start = start}
  end
  return leaves
end

-- How many rows the blocks move down: the first row of every block is under the lowest trunk, which passes over the blocks west of its last
-- leaf. That is also under the last tile of the belt that comes down to every block (the lowest trunk's belts end one row above it, and the
-- others end higher), so each block's own belt starts at or under it.
---@param plan bpgen.FeedPlan
---@return integer
local function drop_of(plan)
  return inputs.first_row_under(plan, 0)
end

-- The starts without a `feed`, moved.
---@param starts bpgen.EntryStart[]
---@param dx integer
---@param dy integer
---@return bpgen.EntryStart[]
local function others_of(starts, dx, dy)
  local others = {}
  for _, start in ipairs(starts) do
    if not start.feed then
      local copy = {}
      for key, value in pairs(start) do
        copy[key] = value
      end
      copy.x, copy.y = start.x + dx, start.y + dy
      others[#others + 1] = copy
    end
  end
  return others
end

-- The belt from the last tile of the belt that comes down from the band to the tile before the first tile of the block's own belt.
---@param entities bpgen.Entity[]
---@param names bpgen.SharedNames
---@param leaves bpgen.BandLeaf[]  with `drop_x`
---@param ends table<bpgen.FeedLeaf, integer>
---@param dy integer
local function add_descents(entities, names, leaves, ends, dy)
  for _, leaf in ipairs(leaves) do
    for _, belt in ipairs(inputs.belts_down(names, leaf.drop_x, ends[leaf] + 1, leaf.start.y + dy - 1)) do
      entity_list.append(entities, belt)
    end
  end
end

-- Brings in the belts of raw items of the blocks in `entities` (the blueprint with its first tile at (0, 0)) through one band, moving the
-- blocks east and down in place and appending the band and the belts under it. The starts with a `feed` are those belts; the others are
-- returned, moved. Stops when `names` has no splitter or underground belt, or the underground belt does not span enough tiles for the band.
---@param entities bpgen.Entity[]
---@param starts bpgen.EntryStart[]
---@param names bpgen.SharedNames
---@param options bpgen.InputOptions
---@return bpgen.SharedBand
function shared_band.add(entities, starts, names, options)
  local leaves = leaves_of(starts)
  assert(#leaves > 0, "shared_band: no belt of raw items comes down to the blocks")
  local plan = feeds.plan(leaves, options.lane_items_per_minute)
  local dx = inputs.start_column(plan)
  for _, leaf in ipairs(leaves) do
    leaf.drop_x = leaf.start.x + dx
  end
  local band, supplies, ends = inputs.lay(plan, names, options.underground_reach)
  local dy = drop_of(plan)
  for _, entity in ipairs(entities) do
    entity.position.x, entity.position.y = entity.position.x + dx, entity.position.y + dy
  end
  for _, entity in ipairs(band) do
    entity_list.append(entities, entity)
  end
  add_descents(entities, names, leaves, ends, dy)
  return {starts = others_of(starts, dx, dy), supplies = supplies, dx = dx, dy = dy}
end

return shared_band
