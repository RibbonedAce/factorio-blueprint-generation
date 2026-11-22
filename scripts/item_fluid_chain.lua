-- scripts/item_fluid_chain.lua
-- The blueprint of a recipe that takes items and a fluid, when other parts of the blueprint make the items: one is made by chemical plants
-- from fluids (the plants part, with the machines that make the fluids it takes) and one by furnaces or assemblers on belts from raw items
-- (the belts part). Sulfuric acid is the example of this file and of its specs: sulfur from petroleum gas and water (plants fed by
-- refineries), iron plates from iron ore and coal (furnaces), and the plants that make the acid from both and water. Pure, like
-- scripts/fluid_plant.lua. It puts three blueprints made apart into one, and joins them: the belts part (made by the generator from the
-- game's recipes, see `bpgen.BeltsBlock`), the plants part (`fluid_plant.build_block`), and the final plants, which take what the other two
-- make (scripts/item_fluid_plants.lua).
--
-- The blocks stand side by side from west to east, all starting at the top row, as the columns of every other blueprint do (see
-- scripts/rows.lua): the parts that make what the final plants eat come first and the final plants last, east of them. The belts part is the
-- westmost of the parts, so that the pipe of the fluid that comes in beside the plants part (the water of the sulfur) and the pipe of the
-- fluid the final plants take (the water of the acid) have no other entry between them (see scripts/corner_entries.lua): they come in as one.
--
-- The products leave their blocks at the bottom and join the belt b of the final plants, which runs north, in the way of scripts/rows.lua.
-- The belt of the belts part (the head) comes down the east side of its block to the row under everything (the row of the arc), goes through
-- the lane gadget (one row further down, east for two tiles and north into the side of the arc, which has a stub behind it) and runs east
-- along the arc to the belt b, which it turns into. The belt of the plants part (the second product) comes down the east side of its plants
-- and ends pointing into the side of the arc from the north, which has the belt of the head behind it. A belt that feeds the side of another
-- puts everything on its near lane, so the head rides the south lane of the arc and the other the north lane, and the turn of the arc into
-- the belt b (east to north) makes those the east lane and the west lane: each item has a lane, as the plants need.
-- Drawn as the generator makes it for sulfuric acid: 2 furnaces (F), 5 refineries (R), 3 plants of the sulfur (S) and 3 plants of the acid
-- (A), in the original design of the belts, with the rows in the middle left out; = a pipe, u the end of an underground pipe, i an inserter,
-- + a pole, the belts as arrows, and the row of each entry at the left (the rows above the blueprint are -1 and under):
--
--   -7 |========================        the entry of the water of both plants: the row of the furthest start, down at the two pipes
--   -6 |................=......=
--   -4 |=========.......=......=        the entry of the crude oil, west of both pipes of the water
--   -1 |v.......=....+..=...+..=        the entry of the belt of the furnaces, nearest the blueprint
--    0 |viFFiv..=RRRRR=.=SSS+v.=u^uAAA=
--    1 |v+FF+v..=RRRRR=.uSSSiv.=+^iAAA=+
--       ...
--    8 |.....v..=RRRRR===SSS.v.=u^uAAA=
--    9 |.....v..=RRRRR=......v...^
--       ...
--   24 |.....v...RRRRR=......v...^
--   25 |.....v>>>>>>>>>>>>>>>>>>>^      the arc: the belt of the sulfur ends pointing into it from above, and it turns north into the belt b
--   26 |.....>>^                        the lane gadget of the belt of the furnaces
--
-- Everything that comes in starts at the top left, as `scripts/corner_entries.lua` has it: the pipes of the plants part (the crude oil of
-- its refineries and the water beside its plants, with the water of the final plants joined to it when it is the same fluid), and the belts
-- of the belts part. The poles of the blocks are joined into one network.
--
-- `build_nested` makes the blueprint of a recipe whose two items are both made on belts and whose fluid another chain makes (battery: iron
-- plate and copper plate from furnaces, and the sulfuric acid of the chain above, which `build_block` gives as a block). From west to east:
-- the part of the first item, the part of the second, the chain, and the final plants. The belts of the two items reach the belt b of the
-- final plants as above (the first is the head, the second side-loads the arc from the north), and the pipe of the fluid the chain makes
-- runs along the first row where it can into the trunk of the final plants. The start of each entry has the name of its part before its key.

local item_fluid_plants = require("scripts.item_fluid_plants")
local corner_entries = require("scripts.corner_entries")
local entity_list = require("scripts.entity_list")
local fluid_plant = require("scripts.fluid_plant")
local grid = require("scripts.grid")
local poles = require("scripts.poles")

local item_fluid_chain = {}

local north, east, south = defines.direction.north, defines.direction.east, defines.direction.south

-- How many free columns there are between two blocks.
local BLOCK_GAP = 1

-- The last column and the last row that an entity of the list covers, as tiles of its frame.
---@param entities bpgen.Entity[]
---@param size_of fun(entity: bpgen.Entity): integer, integer
---@return integer right
---@return integer bottom
local function extent_of(entities, size_of)
  local right, bottom = -math.huge, -math.huge
  for _, entity in ipairs(entities) do
    local across, along = size_of(entity)
    local tile = grid.top_left_tile(entity.position, across, along)
    right, bottom = math.max(right, tile.x + across - 1), math.max(bottom, tile.y + along - 1)
  end
  return right, bottom
end

-- The copies in `added` (the result of `entity_list.merge`) of the poles of a group of the source it was made from.
---@param group bpgen.Entity[]  poles of the source
---@param added bpgen.Entity[]  the new entities, in the order of the source
---@return bpgen.Entity[]
local function copies_of(group, added)
  local copies = {}
  for index, pole in ipairs(group) do
    copies[index] = added[pole.entity_number]
  end
  return copies
end

-- The starts of the belts of raw items of the belts part (see `corner_entries.add`), for the block at the column `x_block`: a belt that runs
-- south at the first tile of the block comes down its own column; the belts that run east into the block, which stand one under the other
-- at its west edge, come down the columns before it, the upper one the column nearest the block, so that none crosses another.
---@param belts_part bpgen.BeltsBlock
---@param x_block integer
---@param belt string
---@return bpgen.EntryStart[]
local function belts_starts(belts_part, x_block, belt)
  local ordered = {table.unpack(belts_part.raw)}
  table.sort(ordered, function(first, second) return first.y < second.y end)
  local starts, rank = {}, 0
  for _, raw in ipairs(ordered) do
    if raw.direction == south then
      starts[#starts + 1] = {key = raw.key, x = x_block + raw.x, y = raw.y, name = belt, belt = true}
    else
      assert(raw.direction == east and raw.x == 0, "item_fluid_chain: a belt of raw items comes in at the west edge of the block of the belts part, running east, or at its top, running south")
      rank = rank + 1
      starts[#starts + 1] = {key = raw.key, x = x_block - rank, y = raw.y, name = belt, belt = true, until_x = x_block - 1}
    end
  end
  return starts
end

-- How many columns the belts of raw items take west of the block of the belts part: the ones that run east into it.
---@param belts_part bpgen.BeltsBlock
---@return integer
local function lead_of(belts_part)
  local lead = 0
  for _, raw in ipairs(belts_part.raw) do
    lead = lead + (raw.direction == east and 1 or 0)
  end
  return lead
end

-- A run of belt tiles down or up one column, all running the way given.
---@param entities bpgen.Entity[]
---@param belt string
---@param column integer
---@param first_row integer
---@param last_row integer  nothing is added when it is above `first_row`
---@param direction defines.direction
local function add_run(entities, belt, column, first_row, last_row, direction)
  for row = first_row, last_row do
    entity_list.append(entities, {name = belt, position = grid.position(column, row), direction = direction})
  end
end

-- A run of belt tiles east along one row.
---@param entities bpgen.Entity[]
---@param belt string
---@param first_column integer
---@param last_column integer
---@param row integer
local function add_across(entities, belt, first_column, last_column, row)
  for column = first_column, last_column do
    entity_list.append(entities, {name = belt, position = grid.position(column, row), direction = east})
  end
end

-- The belt of the belts part from the end of its block, down its column to the row of the arc, through the lane gadget and along the arc
-- to the tile before the belt b (see the head of this file and `add_gadget` in scripts/rows.lua).
---@param entities bpgen.Entity[]
---@param belt string
---@param places bpgen.ItemFluidChainPlaces
---@param first_row integer  the row under the last tile of the belt that the block made
local function add_head_belt(entities, belt, places, first_row)
  local x, row = places.belts_product, places.arc_row
  add_run(entities, belt, x, first_row, row, south)
  add_run(entities, belt, x, row + 1, row + 1, east)
  add_run(entities, belt, x + 1, row + 1, row + 1, east)
  add_run(entities, belt, x + 2, row + 1, row + 1, north)
  add_across(entities, belt, x + 1, places.belt_b - 1, row)
end

-- The belt of the plants part from the end of its plants, down its column to the row above the arc, where its last tile points into the
-- side of the arc.
---@param entities bpgen.Entity[]
---@param belt string
---@param places bpgen.ItemFluidChainPlaces
---@param first_row integer  the row under the last tile of the belt that the plants made
local function add_second_belt(entities, belt, places, first_row)
  add_run(entities, belt, places.plants_product, first_row, places.arc_row - 1, south)
end

-- The belt b from the row under the last final plant down to the arc row, running north: the arc turns into its last tile.
---@param entities bpgen.Entity[]
---@param belt string
---@param places bpgen.ItemFluidChainPlaces
---@param first_row integer
local function add_belt_b_tail(entities, belt, places, first_row)
  add_run(entities, belt, places.belt_b, first_row, places.arc_row, north)
end

-- Where the blocks stand, from their sizes (see the head of this file). The row of the arc is the one under everything the blocks hold.
---@param request bpgen.ItemFluidChainBuild
---@param plants_block table  what `fluid_plant.build_block` gave
---@param final_block bpgen.ItemFluidPlantsBlock
---@return bpgen.ItemFluidChainPlaces
local function places_of(request, plants_block, final_block)
  local belts_x = lead_of(request.belts_part)
  local belts_right, belts_bottom = extent_of(request.belts_part.entities, request.size_of)
  local plants_x = belts_x + belts_right + 1 + BLOCK_GAP
  local plants_product = plants_x + plants_block.product_belt.column
  local final_x = plants_product + 1 + BLOCK_GAP
  local _, plants_bottom = extent_of(plants_block.entities, request.size_of)
  return {
    belts_x = belts_x, belts_product = belts_x + request.belts_part.product.column, plants_x = plants_x, plants_product = plants_product, final_x = final_x,
    trunk = final_x + final_block.columns.trunk, belt_b = final_x + final_block.columns.belt,
    arc_row = math.max(plants_bottom, belts_bottom, final_block.last_row) + 1,
  }
end

-- Wires the poles of the blocks into one network, with poles between them where a wire does not reach, on free tiles.
---@param entities bpgen.Entity[]
---@param request bpgen.ItemFluidChainBuild
---@param groups bpgen.Entity[][]  the poles of each block, each group wired inside, in the entities
local function join_poles(entities, request, groups)
  local firsts = {}
  for _, group in ipairs(groups) do
    firsts[#firsts + 1] = {group[1]}
  end
  poles.join(firsts, {
    entities = entities, taken = grid.taken_tiles(entities, request.size_of), pole = request.final_plants.pole,
    wire_distance = request.final_plants.pole_wire_distance,
  })
end

-- A copy of an entry start moved `dx` columns east, with the column where its belt turns east into its block (`until_x`), if it has one.
---@param start bpgen.EntryStart
---@param dx integer
---@return bpgen.EntryStart
local function moved(start, dx)
  local copy = {}
  for key, value in pairs(start) do
    copy[key] = value
  end
  copy.x = start.x + dx
  copy.until_x = start.until_x and start.until_x + dx or nil
  return copy
end

-- Where everything that comes in starts: the pipes of the plants part (moved to where it stands), the trunk of the fluid of the final
-- plants, which joins the fluid that comes in beside the plants part when `shared_fluid` says it is the same, and the belts of raw items of
-- the belts part.
---@param request bpgen.ItemFluidChainBuild
---@param plants_block table  what `fluid_plant.build_block` gave
---@param places bpgen.ItemFluidChainPlaces
---@return bpgen.EntryStart[]
local function starts_of(request, plants_block, places)
  local starts = {}
  for _, start in ipairs(belts_starts(request.belts_part, places.belts_x, request.final_plants.belt)) do
    starts[#starts + 1] = start
  end
  for _, start in ipairs(plants_block.entries.starts) do
    starts[#starts + 1] = moved(start, places.plants_x)
  end
  starts[#starts + 1] = {key = "final_fluid", x = places.trunk, y = 0, name = request.final_plants.pipe, joins = request.shared_fluid and "supplied" or nil}
  return starts
end

-- The blocks and the belts that join them, numbered from 1, starting at its top-left tile (0, 0), without the entries of what comes in and
-- the joining of the poles: for a blueprint made of this one and more (see `item_fluid_chain.build_nested`), which does those. `starts` are
-- where what comes in starts (see `starts_of`), and `groups` the poles of each block, each group wired inside, in the entities.
---@param request bpgen.ItemFluidChainBuild
---@return bpgen.ItemFluidChainBlock
function item_fluid_chain.build_block(request)
  local plants_block = fluid_plant.build_block(request.plants_part)
  local final_block, belts_block = item_fluid_plants.build(request.final_plants), request.belts_part
  local places = places_of(request, plants_block, final_block)
  local entities = {}
  local belts_added = entity_list.merge(entities, belts_block.entities, places.belts_x, 0)
  local plants_added = entity_list.merge(entities, plants_block.entities, places.plants_x, 0)
  local final_added = entity_list.merge(entities, final_block.entities, places.final_x, 0)
  add_head_belt(entities, request.final_plants.belt, places, belts_block.product.last_row + 1)
  add_second_belt(entities, request.final_plants.belt, places, plants_block.product_belt.last_row + 1)
  add_belt_b_tail(entities, request.final_plants.belt, places, final_block.last_row + 1)
  return {
    entities = entities, starts = starts_of(request, plants_block, places), places = places, final = final_block,
    groups = {
      copies_of(belts_block.poles, belts_added), copies_of(plants_block.groups[1], plants_added), copies_of(plants_block.groups[2], plants_added),
      copies_of(final_block.groups[1], final_added), copies_of(final_block.groups[2], final_added),
    },
  }
end

-- The blueprint, numbered from 1, starting at its top-left tile (0, 0): the blocks, the belts that join them, the entries of what comes in
-- and the poles. `inlets` are the entries, at the west edge, with the keys of the starts they come from: "input" and "supplied" of the
-- plants part (see `fluid_plant.build_block`), which is also the entry of the fluid of the final plants when `shared_fluid` is set and else
-- has the key "final_fluid", and the keys of the belts of raw items of the belts part.
---@param request bpgen.ItemFluidChainBuild
---@return bpgen.ItemFluidChain
function item_fluid_chain.build(request)
  local block = item_fluid_chain.build_block(request)
  local inlets = corner_entries.add(block.entities, block.starts)
  join_poles(block.entities, request, block.groups)
  return {entities = block.entities, inlets = inlets, places = block.places, final = block.final}
end

-- A copy of an entry start with the name of its part before its key (and before the key it joins), so that the starts of several parts, each
-- with an "input" or a belt of coal of its own, are told apart.
---@param start bpgen.EntryStart
---@param part string
---@return bpgen.EntryStart
local function named(start, part)
  local copy = moved(start, 0)
  copy.key = part .. ":" .. start.key
  copy.joins = start.joins and (part .. ":" .. start.joins) or nil
  return copy
end

-- Where the parts of a nested chain stand, from their sizes, west to east: the two parts that make the items on belts, the chain that makes
-- the fluid, and the final plants. The belts of raw items that run east into a part come down the columns before it, so the part has them
-- before its own column (`lead_of`). The names of the columns of the head and of the second belt are those of `places_of`.
---@param request bpgen.NestedChainBuild
---@param final_block bpgen.ItemFluidPlantsBlock
---@return bpgen.NestedChainPlaces
local function nested_places_of(request, final_block)
  local first, second, chain = request.first_part, request.second_part, request.fluid_chain
  local first_x = lead_of(first)
  local first_right, first_bottom = extent_of(first.entities, request.size_of)
  local second_x = first_x + first_right + 1 + BLOCK_GAP + lead_of(second)
  local second_right, second_bottom = extent_of(second.entities, request.size_of)
  local chain_x = second_x + second_right + 1 + BLOCK_GAP
  local chain_right, chain_bottom = extent_of(chain.entities, request.size_of)
  local final_x = chain_x + chain_right + 1 + BLOCK_GAP
  return {
    first_x = first_x, second_x = second_x, chain_x = chain_x, final_x = final_x,
    belts_product = first_x + first.product.column, plants_product = second_x + second.product.column,
    trunk = final_x + final_block.columns.trunk, belt_b = final_x + final_block.columns.belt,
    arc_row = math.max(first_bottom, second_bottom, chain_bottom, final_block.last_row) + 1,
  }
end

-- The rows of the entities with the name in a column, as a set.
---@param entities bpgen.Entity[]
---@param name string
---@param column integer
---@return table<integer, true>
local function rows_in_column(entities, name, column)
  local rows = {}
  for _, entity in ipairs(entities) do
    local tile = grid.top_left_tile(entity.position)
    if entity.name == name and tile.x == column then
      rows[tile.y] = true
    end
  end
  return rows
end

-- The pipe that takes the fluid the chain makes from its pipe, beside its plants, to the trunk of the final plants, which stands two columns
-- east of the column of the poles of those plants: along the first row where both have a pipe and the column of the poles has none of them.
---@param entities bpgen.Entity[]  all of the blueprint
---@param request bpgen.NestedChainBuild
---@param places bpgen.NestedChainPlaces
local function add_fluid_link(entities, request, places)
  local chain = request.fluid_chain
  local pipe, pole = request.final_plants.pipe, request.final_plants.pole
  local from = places.chain_x + chain.places.final_x + chain.final.columns.output
  local made, poles_at, trunk = rows_in_column(entities, pipe, from), rows_in_column(entities, pole, from + 1), rows_in_column(entities, pipe, places.trunk)
  local row
  for candidate = 0, chain.final.output_exit_row do
    if made[candidate] and trunk[candidate] and not poles_at[candidate] and not row then
      row = candidate
    end
  end
  assert(row, "item_fluid_chain: no row where the pipe of the fluid the chain makes reaches the trunk of the final plants")
  for column = from + 1, places.trunk - 1 do
    entity_list.append(entities, {name = pipe, position = grid.position(column, row)})
  end
end

-- Where what comes in starts, for the parts of a nested chain: the belts of raw items of the two parts on belts and the starts of the chain
-- (moved to where it stands), each with the name of its part before its key ("first", "second" and "chain").
---@param request bpgen.NestedChainBuild
---@param places bpgen.NestedChainPlaces
---@return bpgen.EntryStart[]
local function nested_starts_of(request, places)
  local starts, belt = {}, request.final_plants.belt
  for _, start in ipairs(belts_starts(request.first_part, places.first_x, belt)) do
    starts[#starts + 1] = named(start, "first")
  end
  for _, start in ipairs(belts_starts(request.second_part, places.second_x, belt)) do
    starts[#starts + 1] = named(start, "second")
  end
  for _, start in ipairs(request.fluid_chain.starts) do
    starts[#starts + 1] = named(moved(start, places.chain_x), "chain")
  end
  return starts
end

-- The blueprint of a recipe whose items are both made on belts and whose fluid another chain makes (battery: iron plate and copper plate from
-- furnaces, and the sulfuric acid of the chain of `item_fluid_chain.build_block`), numbered from 1, starting at its top-left tile (0, 0). The
-- parts stand from west to east, all starting at the top row: the part of the first item (the head of the belt b), the part of the second, the
-- chain that makes the fluid, and the final plants. The belts of the two items reach the belt b in the way of `item_fluid_chain.build`: the
-- head goes through the lane gadget and along the arc, which the second side-loads from above. The pipe of the fluid that the chain makes
-- runs straight into the trunk of the final plants. `inlets` are the entries, with the key of the start of each and the name of its part
-- before it: "first:", "second:" and "chain:".
---@param request bpgen.NestedChainBuild
---@return bpgen.NestedChain
function item_fluid_chain.build_nested(request)
  local final_block = item_fluid_plants.build(request.final_plants)
  local places = nested_places_of(request, final_block)
  local entities = {}
  local first_added = entity_list.merge(entities, request.first_part.entities, places.first_x, 0)
  local second_added = entity_list.merge(entities, request.second_part.entities, places.second_x, 0)
  local chain_added = entity_list.merge(entities, request.fluid_chain.entities, places.chain_x, 0)
  local final_added = entity_list.merge(entities, final_block.entities, places.final_x, 0)
  add_head_belt(entities, request.final_plants.belt, places, request.first_part.product.last_row + 1)
  add_second_belt(entities, request.final_plants.belt, places, request.second_part.product.last_row + 1)
  add_belt_b_tail(entities, request.final_plants.belt, places, final_block.last_row + 1)
  add_fluid_link(entities, request, places)
  local inlets = corner_entries.add(entities, nested_starts_of(request, places))
  local groups = {copies_of(request.first_part.poles, first_added), copies_of(request.second_part.poles, second_added)}
  for _, group in ipairs(request.fluid_chain.groups) do
    groups[#groups + 1] = copies_of(group, chain_added)
  end
  groups[#groups + 1], groups[#groups + 2] = copies_of(final_block.groups[1], final_added), copies_of(final_block.groups[2], final_added)
  join_poles(entities, request, groups)
  return {entities = entities, inlets = inlets, places = places, final = final_block}
end

return item_fluid_chain
