-- scripts/rows.lua
-- Recipes with several made ingredients, laid out as a row of columns. Pure, like
-- scripts/layout.lua, which builds the columns of a chain; this module puts them side by side.
--
-- The point of the layout is that the recipe and the rate stretch the blueprint in different
-- directions: the recipe fixes the width (one column per step of the recipe tree), and the rate
-- only makes the columns taller (more machines in a column, never another column).
--
-- Every step is a column, built by `layout.chain_block` (a chain of stages fed raw items, or the
-- column of machines that eats what other columns make, the "final" column). The columns stand
-- left to right in the order of a walk of the recipe tree that visits the columns that make the
-- ingredients of a step before the step itself, the ingredients of belt a before those of belt b.
-- Above them run the belts of raw items, one row each, from the west edge; the belt of the column
-- furthest east has the top row, so no belt crosses another. A product leaves its column at the
-- bottom, runs east along a row of its own (an "arc") and goes up into belt a or belt b of the
-- column that eats it, which run NORTH here. An arc runs under the columns it passes and deeper
-- than the arcs it would cross, which are the arcs of the columns east of its own. The circuit
-- (ii and cc are furnaces for iron and copper plates, O the cable assemblers, E the circuit
-- assemblers, } an inserter, + a pole, ^ v > belts), x from -1:
--
--      10123456789012345678901234
--   0 |>>>>>>>v...........^}EEE}v|     <- the belt of raw items for the copper furnaces, the top row
--   1 |>v.....v}cc}^}OOO}v^}EEE+v|     <- the one for the iron furnaces (the column furthest west)
--   2 |.v}ii}vv+cc+^+OOO}v^+EEE.v|
--   3 |.v+ii+vv}cc}^.OOO+v^}EEE}v|     <- belt a (column 18) runs north along the circuit assemblers
--   4 |.v}ii}vv.cc.^.....v^}EEE.v|
--   5 |...ii.vv}cc}^.....v^.EEE.v|
--   6 |......v.+cc+......>^......|     <- the cables turn east here and join belt a from the west
--   7 |......v>>>>>>>>>>>>^......|     <- the iron plates run along this row (the arc)
--   8 |......>>^.................|     <- and go through the lane gadget in rows 7 and 8
--
-- Two products on one belt need a lane each. The second joins from the west: a belt that feeds
-- the side of another puts everything on its near lane, the west one. The first would curve into
-- the belt and keep both lanes, so it goes through the lane gadget: its belt goes one row past
-- its arc, east for two tiles and north into the side of the arc, which has a stub belt behind it
-- so that it stays straight. The side-load puts everything on the south lane, and the turn of the
-- arc into belt a (east to north) makes that the east lane.
--
-- A column starts in the row under the belts of raw items that pass over it, and an arc may run
-- in the free space under a column shorter than the ones it passes. A final column starts one row
-- lower than that: its belts run north, and the end of a belt that points into the side of
-- another belt feeds it, which would put its ingredients on the belt of raw items above it.
--
-- A raw item that goes with a made one (wood next to cables) has no machines: its column is two
-- wide, the belt and a spare column for the gadget of the arc before it, and its belt is the arc.
-- See .agents/row-layout-plan.md for the reasons and the measurements.
--
-- Two ways to bring in the raw items. `rows.build` is the original: a belt for every chain, with the
-- ore on one lane and the fuel on the other, as described above. `rows.build_pure` is the design that
-- takes one belt of each material, one item on both lanes (.agents/inputs-plan.md): the chains start
-- lower, under a band along the top (scripts/inputs.lua) where scripts/feeds.lua's trunks are made from
-- the belts that come in, with splitters and underground belts. It needs both of those researched.

local feeds = require("scripts.feeds")
local grid = require("scripts.grid")
local inputs = require("scripts.inputs")
local layout = require("scripts.layout")
local poles = require("scripts.poles")

local rows = {}

local north, east, south = defines.direction.north, defines.direction.east, defines.direction.south

-- How a product reaches the belt of the column that eats it.
---@class bpgen.Arc
---@field head boolean  whether it is the first product of its belt, which the belt starts with
---@field gadget boolean  whether it goes through the lane gadget: a head that shares its belt with another product
---@field rows integer  how many rows it takes: 2 with the gadget, else 1
---@field row integer  its first row, once assigned

-- One column of the blueprint, with the product it sends to its parent.
---@class bpgen.Column
---@field kind "raw"|"chain"|"final"  a belt of a raw item, a chain fed raw items, or the column that eats other columns' products
---@field belt "a"|"b"  the input belt of the parent that its product rides
---@field fed bpgen.StageLayout|bpgen.RawSupplier  the stage a belt of raw items feeds (a chain: its first); the stage of a final column
---@field stages? bpgen.StageLayout[]  the stages whose machines the column holds, nil for a raw item
---@field feed? bpgen.Feed  of a chain or a raw column, what it takes from the belts that come in (`build_pure` only)
---@field drop_x? integer  of a chain or a raw column, the tile column its belt of raw items comes down (`build_pure` only)
---@field children bpgen.Column[]  of a final column: the columns that make what it eats, belt a first
---@field parent? bpgen.Column
---@field block? bpgen.Block  not for a raw item
---@field arc? bpgen.Arc  not for the root
---@field has_belt_b? boolean  of a final column: whether a second input belt stands west of belt a
---@field index integer  place in the row of columns, from the west
---@field x_b? integer  tile column of belt b
---@field x0? integer  tile column of the input belt (belt a for a final column); nil for a raw item
---@field x_source integer  tile column of the product belt (for a raw item: of its belt)
---@field raw_row? integer  row of its belt of raw items
---@field top? integer  its first row
---@field bottom? integer  one past its last row

-- A belt of raw items: from the west edge along its row, then down a column.
---@class bpgen.RawRun
---@field column bpgen.Column
---@field x integer  tile column it comes down
---@field row integer

---@param entities bpgen.Entity[]
---@param belt_name string
---@param column integer
---@param row integer
---@param direction defines.direction
local function add_belt(entities, belt_name, column, row, direction)
  local belt = {name = belt_name, position = grid.position(column, row), direction = direction}
  entities[#entities + 1] = belt
  belt.entity_number = #entities
end

-- A run of belt tiles down one column, all running the same way (nothing when `last_row` is above `first_row`).
---@param entities bpgen.Entity[]
---@param belt_name string
---@param column integer
---@param first_row integer
---@param last_row integer
---@param direction defines.direction
local function add_run(entities, belt_name, column, first_row, last_row, direction)
  for row = first_row, last_row do
    add_belt(entities, belt_name, column, row, direction)
  end
end

-- A run of belt tiles east along one row.
---@param entities bpgen.Entity[]
---@param belt_name string
---@param first_column integer
---@param last_column integer
---@param row integer
local function add_across(entities, belt_name, first_column, last_column, row)
  for column = first_column, last_column do
    add_belt(entities, belt_name, column, row, east)
  end
end

-- The stages of a straight chain, from the one fed raw items to `stage`. A stage with
-- several made ingredients in the middle of a chain is a mistake of the caller: the
-- generator refuses such recipes before it lays anything out.
---@param stage bpgen.StageLayout
---@return bpgen.StageLayout[]
local function straight_chain(stage)
  local chain = {}
  local current = stage
  while current do
    table.insert(chain, 1, current)
    local suppliers = current.suppliers or {}
    if #suppliers > 1 then
      error("rows: a chain of stages cannot start from a stage with several made ingredients")
    end
    current = suppliers[1]
  end
  return chain
end

-- The columns of a final column's suppliers: those of belt a first, then those of belt b, each in
-- the recipe's order.
---@param children bpgen.Column[]
---@return bpgen.Column[]
local function belt_a_first(children)
  local ordered = {}
  for _, belt in ipairs({"a", "b"}) do
    for _, child in ipairs(children) do
      if child.belt == belt then
        ordered[#ordered + 1] = child
      end
    end
  end
  return ordered
end

-- Says how each child of a final column reaches it: the first product of a belt is its head, and
-- a head that has company on its belt goes through the lane gadget.
---@param final bpgen.Column
local function mark_arcs(final)
  local counts, seen = {a = 0, b = 0}, {}
  for _, child in ipairs(final.children) do
    counts[child.belt] = counts[child.belt] + 1
  end
  for _, child in ipairs(final.children) do
    local head = not seen[child.belt]
    local gadget = head and counts[child.belt] >= 2
    child.arc = {head = head, gadget = gadget, rows = gadget and 2 or 1, row = 0}
    child.parent = final
    seen[child.belt] = true
  end
  final.has_belt_b = counts.b > 0
end

local column_of -- defined below: a final column is made of the columns of its suppliers

---@param stage bpgen.StageLayout
---@param belt "a"|"b"
---@param names bpgen.SharedNames
---@param is_root boolean
---@return bpgen.Column
local function final_column(stage, belt, names, is_root)
  local children = {}
  for _, supplier in ipairs(stage.suppliers or {}) do
    children[#children + 1] = column_of(supplier, names, false)
  end
  local final = {
    kind = "final", belt = belt, fed = stage, children = belt_a_first(children), stages = {stage},
    block = layout.chain_block({stage}, names, {product_belt = is_root}),
  }
  mark_arcs(final)
  return final
end

-- The column of a stage, with the columns of the stages that make its ingredients.
---@param stage bpgen.StageLayout|bpgen.RawSupplier
---@param names bpgen.SharedNames
---@param is_root boolean  whether this makes the final product of the blueprint, which draws its product belt
---@return bpgen.Column
function column_of(stage, names, is_root)
  local belt = stage.belt == "b" and "b" or "a"
  if stage.raw_item then
    return {kind = "raw", belt = belt, fed = stage, children = {}}
  end
  if #(stage.suppliers or {}) >= 2 then
    return final_column(stage, belt, names, is_root)
  end
  local stages = straight_chain(stage)
  return {
    kind = "chain", belt = belt, fed = stages[1], children = {}, stages = stages,
    block = layout.chain_block(stages, names, {product_belt = is_root}),
  }
end

-- Lists the columns from the west: the columns of a stage's ingredients, then the stage.
---@param column bpgen.Column
---@param columns bpgen.Column[]  the list so far
local function flatten(column, columns)
  for _, child in ipairs(column.children) do
    flatten(child, columns)
  end
  columns[#columns + 1] = column
  column.index = #columns
end

-- Gives every column its tile columns, side by side from column `start` (0 by default). A final column
-- with a belt b has a column of its own for it, west of belt a.
---@param columns bpgen.Column[]
---@param start? integer
local function place_across(columns, start)
  local cursor = start or 0
  for _, column in ipairs(columns) do
    if column.kind == "raw" then
      column.x_source = cursor + 1
      cursor = cursor + 2
    else
      if column.has_belt_b then
        column.x_b = cursor
        cursor = cursor + 1
      end
      column.x0 = cursor
      column.x_source = cursor + column.block.product_column
      cursor = column.x_source + 1
    end
  end
end

-- The belts of raw items, in the order of their rows: the one that comes down furthest east has the top row.
---@param columns bpgen.Column[]
---@return bpgen.RawRun[]
local function raw_runs_of(columns)
  local runs = {}
  for _, column in ipairs(columns) do
    if column.kind ~= "final" then
      runs[#runs + 1] = {column = column, x = column.x0 or column.x_source}
    end
  end
  table.sort(runs, function(first, second) return first.x > second.x end)
  for index, run in ipairs(runs) do
    run.row = index - 1
    run.column.raw_row = run.row
  end
  return runs
end

-- The first row of a column: under the belts of raw items that pass over it, which are those that come
-- down east of it. A chain starts right under its own belt. A final column leaves a row free under them.
---@param column bpgen.Column
---@param runs bpgen.RawRun[]
---@return integer
local function first_row_of(column, runs)
  if column.kind == "chain" then
    return column.raw_row + 1
  end
  local over = 0
  for _, run in ipairs(runs) do
    if run.x > column.x_source then
      over = over + 1
    end
  end
  return over > 0 and over + 1 or 0
end

---@param columns bpgen.Column[]
---@param runs bpgen.RawRun[]
local function set_rows(columns, runs)
  for _, column in ipairs(columns) do
    if column.block then
      column.top = first_row_of(column, runs)
      column.bottom = column.top + column.block.height
    end
  end
end

-- The row where the product belt of a column starts, and the row of its last output.
---@param column bpgen.Column
---@return integer
local function output_start(column)
  return column.block and column.top + column.block.output_rows.first or column.raw_row + 1
end

---@param column bpgen.Column
---@return integer
local function output_end(column)
  return column.block and column.top + column.block.output_rows.last or column.raw_row + 1
end

-- The first row the arc of `child` can take: under its last output, under the final column that eats it
-- (the belt that takes the product up passes all its inserters), and under the columns it passes.
---@param child bpgen.Column
---@param final bpgen.Column
---@param columns bpgen.Column[]
---@return integer
local function lowest_arc_row(child, final, columns)
  local lowest = math.max(final.bottom, output_end(child) + 1)
  for index = child.index + 1, final.index - 1 do
    lowest = math.max(lowest, columns[index].bottom or 0)
  end
  return lowest
end

-- Gives the arcs of the columns that a final column eats their rows, from the east: an arc runs
-- deeper than the arcs of the columns east of it and than everything inside them. Returns the
-- first row below all the arcs of this final column and of the final columns inside it.
---@param final bpgen.Column
---@param columns bpgen.Column[]
---@return integer
local function assign_arcs(final, columns)
  local depths = {}
  for index, child in ipairs(final.children) do
    depths[index] = child.kind == "final" and assign_arcs(child, columns) or 0
  end
  local deepest = 0
  for index = #final.children, 1, -1 do
    local child = final.children[index]
    local arc = child.arc
    arc.row = math.max(deepest, lowest_arc_row(child, final, columns))
    deepest = math.max(arc.row + arc.rows, depths[index], deepest)
  end
  return deepest
end

-- Adds the entities of a block to `entities`, numbered after the ones already there.
-- The wires of the block name its own numbers, which move along with them.
---@param entities bpgen.Entity[]
---@param block bpgen.Block
local function absorb(entities, block)
  local offset = #entities
  for _, entity in ipairs(block.entities) do
    entity.entity_number = entity.entity_number + offset
    for _, wire in ipairs(entity.wires or {}) do
      wire[1] = wire[1] + offset
      wire[3] = wire[3] + offset
    end
    entities[#entities + 1] = entity
  end
end

-- The belt of a final column that feeds its machines runs north, towards the top of the blueprint,
-- where the products arrive from the bottom.
---@param final bpgen.Column
---@param belt_name string
local function face_north(final, belt_name)
  for _, entity in ipairs(final.block.entities) do
    if entity.name == belt_name and entity.position.x - 0.5 == final.x0 then
      entity.direction = north
    end
  end
end

-- Moves the block of every column to its place and adds its entities.
---@param entities bpgen.Entity[]
---@param columns bpgen.Column[]
---@param belt_name string
local function place_blocks(entities, columns, belt_name)
  for _, column in ipairs(columns) do
    if column.block then
      for _, entity in ipairs(column.block.entities) do
        entity.position.x = entity.position.x + column.x0
        entity.position.y = entity.position.y + column.top
      end
      if column.kind == "final" then
        face_north(column, belt_name)
      end
      absorb(entities, column.block)
    end
  end
end

-- The belts of raw items: from the west edge east along their row, then down their column into
-- the first row of the chain (a belt of a raw item that goes with a made one is its arc).
---@param entities bpgen.Entity[]
---@param belt_name string
---@param runs bpgen.RawRun[]
local function add_raw_belts(entities, belt_name, runs)
  local west = runs[#runs].x - 1
  for _, run in ipairs(runs) do
    add_across(entities, belt_name, west, run.x - 1, run.row)
    add_belt(entities, belt_name, run.x, run.row, south)
    local column = run.column
    if column.kind == "chain" then
      local last = column.top + column.block.raw_belts[1].row - 1
      add_run(entities, belt_name, run.x, run.row + 1, last, south)
    end
  end
end

-- The tile row of the last tile of the input belt that a final column draws itself.
---@param final bpgen.Column
---@param belt_name string
---@return integer
local function input_belt_end(final, belt_name)
  local last = -1
  for _, entity in ipairs(final.block.entities) do
    if entity.name == belt_name and entity.position.x - 0.5 == final.x0 then
      last = math.max(last, entity.position.y - 0.5)
    end
  end
  return last
end

-- The lane gadget: the belt of the head goes one row past the row of its arc, east for two tiles and
-- north into the side of the arc, whose first two tiles are a stub and the tile it feeds.
---@param entities bpgen.Entity[]
---@param belt_name string
---@param x integer  tile column of the belt coming down
---@param row integer  the row of the arc
local function add_gadget(entities, belt_name, x, row)
  add_belt(entities, belt_name, x, row + 1, east)
  add_belt(entities, belt_name, x + 1, row + 1, east)
  add_belt(entities, belt_name, x + 2, row + 1, north)
  add_belt(entities, belt_name, x + 1, row, east)
  add_belt(entities, belt_name, x + 2, row, east)
end

-- The belt of a column from its last output down and east to the tile before `target`, the column of the belt that eats it.
---@param entities bpgen.Entity[]
---@param belt_name string
---@param child bpgen.Column
---@param target integer
local function add_arc(entities, belt_name, child, target)
  local arc, x = child.arc, child.x_source
  if arc.gadget then
    add_run(entities, belt_name, x, output_start(child), arc.row, south)
    add_gadget(entities, belt_name, x, arc.row)
    add_across(entities, belt_name, x + 3, target - 1, arc.row)
  else
    add_run(entities, belt_name, x, output_start(child), arc.row - 1, south)
    add_across(entities, belt_name, x, target - 1, arc.row)
  end
end

-- The belts that carry the products north to the machines, from the arc of their head up to
-- where the final column's own belt begins (belt a) or to its first long-handed inserter (belt b).
---@param entities bpgen.Entity[]
---@param belt_name string
---@param final bpgen.Column
local function add_risers(entities, belt_name, final)
  local heads = {}
  for _, child in ipairs(final.children) do
    if child.arc.head then
      heads[child.belt] = child.arc.row
    end
  end
  if heads.a then
    add_run(entities, belt_name, final.x0, input_belt_end(final, belt_name) + 1, heads.a, north)
  end
  if heads.b then
    add_run(entities, belt_name, final.x_b, final.top + final.block.long_rows.first, heads.b, north)
  end
end

-- The arcs and the belts that take the products up, of a final column and of the final columns inside it.
---@param entities bpgen.Entity[]
---@param belt_name string
---@param final bpgen.Column
local function add_arcs(entities, belt_name, final)
  for _, child in ipairs(final.children) do
    if child.kind == "final" then
      add_arcs(entities, belt_name, child)
    end
    add_arc(entities, belt_name, child, child.belt == "b" and final.x_b or final.x0)
  end
  add_risers(entities, belt_name, final)
end

-- Wires the poles of the columns into one network (see scripts/poles.lua).
---@param columns bpgen.Column[]  at least one has a pole
---@param bridge? bpgen.PoleBridge  to put poles between two that are further apart than a wire reaches
local function join_poles(columns, bridge)
  local groups = {}
  for _, column in ipairs(columns) do
    if column.block then
      groups[#groups + 1] = column.block.poles
    end
  end
  poles.join(groups, bridge)
end

-- The stages fed raw items by the belts of raw items, from the top row down.
---@param runs bpgen.RawRun[]
---@return (bpgen.StageLayout|bpgen.RawSupplier)[]
local function raw_stages_of(runs)
  local stages = {}
  for index, run in ipairs(runs) do
    stages[index] = run.column.fed
  end
  return stages
end

-- The blueprint for `root`, the stage that makes the final product, with the stages that
-- make its ingredients in `suppliers`: none or one for a stage fed raw items or by a
-- chain, two or more for a stage with several made ingredients.
-- Returns the entities (numbered from 1) and the stages fed raw items, from the top of
-- the blueprint down, which is the order their belts of raw items come in. For a stage
-- with no more than one supplier at each step this is the same as `layout.build_chain`.
---@param root bpgen.StageLayout
---@param names bpgen.SharedNames
---@return bpgen.Entity[] entities
---@return (bpgen.StageLayout|bpgen.RawSupplier)[] raw_stages
function rows.build(root, names)
  local top = column_of(root, names, true)
  if top.kind == "chain" then
    return top.block.entities, {top.fed}
  end
  local columns = {}
  flatten(top, columns)
  place_across(columns)
  local runs = raw_runs_of(columns)
  set_rows(columns, runs)
  assign_arcs(top, columns)
  local entities = {}
  place_blocks(entities, columns, names.belt)
  add_raw_belts(entities, names.belt, runs)
  add_arcs(entities, names.belt, top)
  join_poles(columns)
  return entities, raw_stages_of(runs)
end

-- The fuel that the stages of a chain burn, which comes down to the belt before the stage: a leaf for each, standing
-- in the list just after its chain (its place is a fraction past the chain's).
---@param column bpgen.Column  a chain
---@return bpgen.FeedLeaf[]
local function fuel_leaves_of(column)
  local feeds, leaves = column.block.fuel_feeds, {}
  for position, fuel in ipairs(feeds) do
    leaves[position] = {index = column.index + position / (#feeds + 1), feed = fuel.stage.fuel_feed, owner = column, fuel = fuel}
  end
  return leaves
end

-- The chains and the raw columns among the columns, and the fuel their stages burn: the leaves, which take what they
-- need from belts that come in. A chain keeps its fuel leaves in `fuel_leaves`.
---@param columns bpgen.Column[]
---@return bpgen.FeedLeaf[]
local function leaves_of(columns)
  local leaves = {}
  for _, column in ipairs(columns) do
    if column.kind ~= "final" then
      column.feed = assert(column.fed.feed, "rows: a stage fed raw items has no feed")
      column.drop_x = nil
      column.fuel_leaves = column.block and fuel_leaves_of(column) or {}
      leaves[#leaves + 1] = column
      for _, leaf in ipairs(column.fuel_leaves) do
        leaves[#leaves + 1] = leaf
      end
    end
  end
  return leaves
end

-- Tells every leaf the tile column its belt comes down, once the columns are placed: the fuel of a stage comes
-- down beside the output inserters of the stage before it, one column west of the belt between them.
---@param leaves bpgen.FeedLeaf[]
local function set_drops(leaves)
  for _, leaf in ipairs(leaves) do
    if leaf.owner then
      leaf.drop_x = leaf.owner.x0 + leaf.fuel.belt_column - 1
    else
      leaf.drop_x = leaf.x0 or leaf.x_source
    end
  end
end

-- The first row of a chain: right under the last tile of the belt that comes down to it, and low enough for the
-- fuel of its stages to turn into the heads of their belts (see `inputs.fuel_tail`).
---@param column bpgen.Column  a chain
---@param ends table<bpgen.FeedLeaf, integer>
---@return integer
local function chain_top(column, ends)
  local first_belt_row = ends[column] + 1
  for _, leaf in ipairs(column.fuel_leaves) do
    first_belt_row = math.max(first_belt_row, ends[leaf] + 2)
  end
  return first_belt_row - column.block.raw_belts[1].row
end

-- Gives every column its first row: a chain right under the last tile of the belt that comes down to it (see
-- `chain_top`), a final column under the trunks that pass over it; a raw column learns the row its belt comes down to.
---@param plan bpgen.FeedPlan
---@param columns bpgen.Column[]
---@param ends table<bpgen.FeedLeaf, integer>  of every leaf, the row of the last tile of its belt
local function set_pure_rows(plan, columns, ends)
  for _, column in ipairs(columns) do
    if column.kind == "final" then
      column.top = inputs.first_row_under(plan, column.x_source)
    elseif column.block then
      column.top = chain_top(column, ends)
    else
      column.raw_row = ends[column]
    end
    if column.block then
      column.bottom = column.top + column.block.height
    end
  end
end

-- The belt between the last tile of the descent of a chain and the first tile of its own belt, when `chain_top` put the
-- chain lower than right under the descent (a stage that burns fuel needs room for its fuel to turn in).
---@param entities bpgen.Entity[]
---@param columns bpgen.Column[]
---@param belt_name string
---@param ends table<bpgen.FeedLeaf, integer>
local function add_chain_descents(entities, columns, belt_name, ends)
  for _, column in ipairs(columns) do
    if column.block and column.kind ~= "final" then
      local first_belt_row = column.top + column.block.raw_belts[1].row
      add_run(entities, belt_name, column.drop_x, ends[column] + 1, first_belt_row - 1, south)
    end
  end
end

-- Adds the entities of the top band to the blueprint's, numbered after the ones there.
---@param entities bpgen.Entity[]
---@param band bpgen.NewEntity[]
local function add_band(entities, band)
  for _, entity in ipairs(band) do
    local numbered = entity --[[@as bpgen.Entity]] -- it gets its number just below
    entities[#entities + 1] = numbered
    numbered.entity_number = #entities
  end
end

-- The belts that bring the fuel from the end of its descent to the head of the belt before its stage, for every chain.
---@param columns bpgen.Column[]  with their rows
---@param names bpgen.SharedNames
---@param ends table<bpgen.FeedLeaf, integer>
---@return bpgen.NewEntity[]
local function fuel_tails(columns, names, ends)
  local tails = {}
  for _, column in ipairs(columns) do
    for _, leaf in ipairs(column.fuel_leaves or {}) do
      for _, entity in ipairs(inputs.fuel_tail(names, leaf.drop_x, ends[leaf], column.top + leaf.fuel.row)) do
        tails[#tails + 1] = entity
      end
    end
  end
  return tails
end

-- The tiles a machine covers on a side, by the machine's name.
---@param columns bpgen.Column[]
---@return table<string, integer>
local function machine_sizes(columns)
  local sizes = {}
  for _, column in ipairs(columns) do
    for _, stage in ipairs(column.stages or {}) do
      sizes[stage.machine] = stage.shape.machine_size
    end
  end
  return sizes
end

-- What the bridge poles need to know of the blueprint: where they go (after its entities) and which tiles those cover.
---@param entities bpgen.Entity[]
---@param columns bpgen.Column[]
---@param names bpgen.SharedNames
---@return bpgen.PoleBridge
local function pole_bridge(entities, columns, names)
  local sizes = machine_sizes(columns)
  local function size_of(entity)
    return inputs.footprint(entity, names, sizes)
  end
  return {entities = entities, taken = poles.taken_tiles(entities, size_of), pole = names.pole}
end

-- The blueprint for `root` in the design that takes one belt of each material (see the top of the file and
-- .agents/inputs-plan.md); `root` is as for `rows.build`, every stage fed raw items has its `feed`, and `names`
-- has the splitter and the underground belt. Works for a single chain too.
-- Returns the entities (numbered from 1) and the belts the player brings in, from the top down: where each
-- starts, at the west edge, and its item on both lanes.
---@param root bpgen.StageLayout
---@param names bpgen.SharedNames
---@param options bpgen.InputOptions
---@return bpgen.Entity[] entities
---@return bpgen.Input[] inputs
function rows.build_pure(root, names, options)
  local top = column_of(root, names, true)
  local columns = {}
  flatten(top, columns)
  local leaves = leaves_of(columns)
  local plan = feeds.plan(leaves, options.lane_items_per_minute)
  place_across(columns, inputs.start_column(plan))
  set_drops(leaves)
  local band, supplies, ends = inputs.lay(plan, names, options.underground_reach)
  set_pure_rows(plan, columns, ends)
  if top.kind == "final" then
    assign_arcs(top, columns)
  end
  local entities = {}
  place_blocks(entities, columns, names.belt)
  add_band(entities, band)
  add_chain_descents(entities, columns, names.belt, ends)
  add_band(entities, fuel_tails(columns, names, ends))
  if top.kind == "final" then
    add_arcs(entities, names.belt, top)
  end
  join_poles(columns, pole_bridge(entities, columns, names))
  return entities, supplies
end

return rows
