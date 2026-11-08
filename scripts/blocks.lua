-- scripts/blocks.lua
-- Recipes with several made ingredients, laid out as a tree of blocks. Pure, like
-- scripts/layout.lua, which builds the columns of a chain; this module puts them together.
--
-- A block is the blueprint of one item at one rate (see `bpgen.Block`): the raw items
-- enter from the west, and one product belt runs down its rightmost column. A block
-- never draws its product belt; whoever uses the block does, and picks the way it runs.
-- A straight chain of columns (furnaces, then assemblers) is a block. So are several blocks
-- with the column of machines that eats what they make, which is how a recipe with two or more
-- made ingredients is built, over and over for as deep as the recipe goes.
--
-- The two blocks are stacked, and the column goes to the right of them, beside the lower
-- one. The upper block stays in the corner, and its product belt (v) goes straight on, down
-- the column to the right of the lower block's, and becomes the input belt of the final
-- column. The lower block is moved until its product belt is in the column beside the input
-- belt: east when the lower block is narrower, west when it is as wide or wider, which puts it
-- in negative columns (its belt of raw items then needs no turn: its trail is the belt). It
-- starts in the row where its product belt turns east (>) into the side of the input belt (the
-- join row): its first output inserter drops onto that turn, which is a curve, but the turn
-- puts everything on one lane anyway. Inserters put what they make on the far lane of a belt,
-- and a belt that feeds the side of another puts everything on its near lane, so the two
-- products ride different lanes of the input belt, and the final column's inserters take both.
-- Two equally wide blocks of one furnace each and an assembler (F furnace, A assembler, } an
-- inserter that moves things east, + a pole, v ^ > belts):
--
--       x: -1 0 1 2 3 4 5 6 7 8 9 10 11
--   row 0:    v v } F F } v
--   row 1:    v . + F F + v
--   row 2:    v } F F } > v          <- the join row: the lower block starts here
--   row 3:    . + F F + ^ v } A A A  }  v
--   row 4:    . . . . . . v } A A A  +  v
--   row 5:    . . . . . . . + A A A  .  v
--
-- The taller block goes on top, so that the final column, about as tall as a block, stands
-- beside the shorter one. Every belt of raw items is fed from the west, at its own row.
--
-- With three or four ingredients the final column takes from two belts, because a belt has
-- two lanes: belt a, next to its inserters, which is the product belt of the top block, and
-- belt b, one column west of it, which the long-handed inserters of the final column reach
-- over belt a. Belts cannot cross, so the order of the blocks is fixed (see `stack_of`): the
-- head of belt a, the block that turns east into the side of belt a, the block that turns east
-- into the head of belt b (a curve: its items keep the west lane), and the source, whose output
-- inserters drop on belt b as it runs south past them (the east lane). The final column
-- stands beside the source. The tiles beside the final column (M a block's machines, L a
-- long-handed inserter, the other letters as above):
--
--                  I-3  I-2  I-1   I   I+1     I = belt a
--   head             .    M    }    v    .
--   side (top row)   .    M    >    v    .
--   side             .    }    ^    v    .
--   join (top row)   .    >    v    v    .
--   join             }    ^    v    v    .
--   source (top row) .    }    v    v    }
--   source           .    .    v    v    L
--
-- Two blocks are never stacked with a belt of one right under a belt of the other: the belt
-- between two columns of a block can run north up to its first row, and would feed the belt
-- above. There is an empty row between them then.
--
-- A raw item that goes with a made one (wood next to copper cable) is a block with no
-- machines: one belt tile, one row tall, which is the first tile of its product belt. It
-- always goes below (every block with machines is taller), so its belt, a trail from the top
-- left like any other belt of raw items, runs along the join row, below the blocks above it,
-- and its first tile is the turn east into the side of the input belt. The raw item arrives on
-- the near lane, the made one on the far lane.
--
-- A block that has neighbours also keeps a line of poles beside its product belt, from its
-- top to its bottom, because the poles of a wide block can be too far from the join for a
-- wire: its tall column of furnaces is on the left, and the join is on the right.

local grid = require("scripts.grid")
local layout = require("scripts.layout")

local blocks = {}

-- A block that has neighbours keeps a line of poles in the column beside its product belt
-- (where its last column's output inserters are), from the top of the block to the bottom,
-- so that the block above or below it, and the column beside it, always find a pole close
-- to the join. Without it a wide block, whose tall column is on its left, can have no pole
-- within a small pole's wire reach of the join. A pole every POLE_HOP rows fits that reach,
-- and the line comes within LINE_END_GAP rows of both ends of the block.
local POLE_HOP = 6
local LINE_END_GAP = 2

-- Two poles and how far apart they are.
---@class bpgen.PolePair
---@field from bpgen.Entity
---@field to bpgen.Entity
---@field distance number

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

-- Moves a block `dx` tiles east and `dy` tiles south.
---@param block bpgen.Block
---@param dx integer
---@param dy integer
local function shift(block, dx, dy)
  for _, entity in ipairs(block.entities) do
    entity.position.x = entity.position.x + dx
    entity.position.y = entity.position.y + dy
  end
  block.product_column = block.product_column + dx
  block.output_rows = {first = block.output_rows.first + dy, last = block.output_rows.last + dy}
  if block.long_rows then
    block.long_rows = {first = block.long_rows.first + dy, last = block.long_rows.last + dy}
  end
  for _, belt in ipairs(block.raw_belts) do
    belt.column = belt.column + dx
    belt.row = belt.row + dy
  end
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

---@param first bpgen.Entity
---@param second bpgen.Entity
---@return number
local function distance(first, second)
  local dx, dy = first.position.x - second.position.x, first.position.y - second.position.y
  return math.sqrt(dx * dx + dy * dy)
end

-- The closest pair of poles, one from each list, or nil when one list is empty.
---@param poles bpgen.Entity[]
---@param others bpgen.Entity[]
---@return bpgen.PolePair|nil
local function closest_pair(poles, others)
  local best
  for _, pole in ipairs(poles) do
    for _, other in ipairs(others) do
      local apart = distance(pole, other)
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

-- Wires groups of poles into one network. Each group is already wired inside; the
-- nearest group is joined to the poles joined so far, by the nearest pair of poles.
-- The layout does not read the reach of a pole from the game: the specs check that
-- these wires are short enough for the shapes the generator makes.
---@param groups bpgen.Entity[][]  at least one; a group with no pole (a block of a raw item) is left out
local function join_pole_groups(groups)
  local waiting = {}
  for _, group in ipairs(groups) do
    if #group > 0 then
      waiting[#waiting + 1] = group
    end
  end
  local joined = append({}, table.remove(waiting, 1))
  while #waiting > 0 do
    local pair, index = closest_group(joined, waiting)
    if not pair or not index then
      return
    end
    layout.connect_poles(pair.from, pair.to)
    append(joined, table.remove(waiting, index))
  end
end

-- One block of a composite, where it stands, and how its product belt joins the belts.
---@class bpgen.Slot
---@field block bpgen.Block
---@field kind "head"|"side"|"join"|"source"
---@field offset integer  how many columns west of belt a its product belt stands
---@field top integer  its first row, once placed

-- The blocks of one belt, tallest first; equally tall ones in the recipe's order.
---@param entries {block: bpgen.Block, index: integer}[]
local function tallest_first(entries)
  table.sort(entries, function(first, second)
    if first.block.height ~= second.block.height then
      return first.block.height > second.block.height
    end
    return first.index < second.index
  end)
end

-- The blocks of a composite from the top of the blueprint down. Belts cannot cross, so
-- the belts fix the order. The blocks of belt a come first: the head, whose output
-- inserters drop on belt a (which goes on as the input belt of the final column), then the
-- block whose belt turns east into the side of belt a. Then the blocks of belt b, which
-- stands one column west of belt a: the block whose belt turns east into the head of belt b
-- (a curve, so its items keep the west lane), then the source, whose output inserters
-- drop on belt b as it passes (the east lane). The final column stands beside the last
-- block. Without a belt b, the block that turns into the side of belt a is the last.
---@param blocks bpgen.Block[]
---@param suppliers (bpgen.StageLayout|bpgen.RawSupplier)[]  the stages that the blocks are of, same order
---@return bpgen.Slot[]
local function stack_of(blocks, suppliers)
  local on_a, on_b = {}, {}
  for index, block in ipairs(blocks) do
    local belt = suppliers[index].belt == "b" and on_b or on_a
    belt[#belt + 1] = {block = block, index = index}
  end
  tallest_first(on_a)
  tallest_first(on_b)
  local stack = {{block = on_a[1].block, kind = "head", offset = 0}}
  if on_a[2] then
    stack[#stack + 1] = {block = on_a[2].block, kind = "side", offset = -1}
  end
  if #on_b == 2 then
    stack[#stack + 1] = {block = on_b[1].block, kind = "join", offset = -2}
  end
  if #on_b > 0 then
    stack[#stack + 1] = {block = on_b[#on_b].block, kind = "source", offset = -1}
  end
  return stack
end

-- Whether a belt in the first row of `block` (at row `top`) has a belt right above it, in the
-- block above. The belt between two columns of a block runs north when the first column is the
-- longer, and its last tile is in the block's first row: right under a belt of the block above
-- it would feed it from behind. (The belts of a block end at least a row above its last row,
-- so no belt above runs south into the block below.)
---@param placed bpgen.Entity[]  the blocks above, in place
---@param block bpgen.Block  at row `top`
---@param belt_name string
---@param top integer
---@return boolean
local function belt_under_belt(placed, block, belt_name, top)
  local above = {}
  for _, entity in ipairs(placed) do
    if entity.name == belt_name and entity.position.y - 0.5 == top - 1 then
      above[entity.position.x] = true
    end
  end
  for _, entity in ipairs(block.entities) do
    if entity.name == belt_name and entity.position.y - 0.5 == top and above[entity.position.x] then
      return true
    end
  end
  return false
end

-- Moves the blocks into place, one under the other from the top row, each with its product
-- belt in its column, and a row apart where a belt of one block is right under a belt of the block above. Belt
-- a is the product belt of the top block, which stays where it is, in the corner. A block that
-- is wider than its column allows moves west, past column 0, where its belt of raw items is
-- its own trail. Gives the entities of all the blocks.
---@param stack bpgen.Slot[]
---@param belt_name string
---@return bpgen.Entity[] entities
---@return integer belt_a  tile column of belt a
---@return integer end_row  one past the last row of the last block
local function place_stack(stack, belt_name)
  local entities = {}
  local belt_a = stack[1].block.product_column
  local row = 0
  for _, slot in ipairs(stack) do
    shift(slot.block, belt_a + slot.offset - slot.block.product_column, row)
    if belt_under_belt(entities, slot.block, belt_name, row) then
      shift(slot.block, 0, 1)
      row = row + 1
    end
    slot.top = row
    absorb(entities, slot.block)
    row = row + slot.block.height
  end
  return entities, belt_a, row
end

-- A run of belt tiles down one column, all running the same way.
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

-- The product belt of a block that joins another belt from the west: north up the rows of
-- the block, then east in its top row. The block starts in that row, so its first output
-- inserter may drop on the turn, a curve; what the turn feeds puts it on one lane anyway.
---@param entities bpgen.Entity[]
---@param belt_name string
---@param slot bpgen.Slot
---@param belt_a integer
local function add_joining_belt(entities, belt_name, slot, belt_a)
  local column = belt_a + slot.offset
  add_run(entities, belt_name, column, slot.top + 1, slot.top + slot.block.height - 1, defines.direction.north)
  add_belt(entities, belt_name, column, slot.top, defines.direction.east)
end

-- The row where belt b starts: the top row of the block that joins it, or of the source.
---@param stack bpgen.Slot[]
---@return integer|nil row  nil without a belt b
local function belt_b_start(stack)
  for _, slot in ipairs(stack) do
    if slot.kind == "join" or slot.kind == "source" then
      return slot.top
    end
  end
  return nil
end

-- The row the final column starts on: beside the last block. Below the turn of the
-- last block's belt into belt a, if that is how it joins. Beside a source, far enough
-- down for the long-handed inserters to see what it drops: belt b runs south, so an inserter
-- sees only what was dropped north of it. The last one must see every drop, or what is
-- dropped below it is never picked up. The first one must see at least its machine's share
-- of the drops (`machines` machines share them, spread evenly over the rows of the source's
-- output inserters), or the first machines would starve. The pickers are evenly spaced
-- between the two, so the two checks are enough. (The rows of the last block are in place;
-- the final column's are not yet.)
---@param last bpgen.Slot
---@param final bpgen.Block  before it is moved
---@param machines integer  how many machines the final column has
---@return integer
local function final_first_row(last, final, machines)
  if last.kind == "side" then
    return last.top + 1
  end
  local first_drop, last_drop = last.block.output_rows.first, last.block.output_rows.last
  local share = math.ceil((last_drop - first_drop + 1) / machines)
  return math.max(last.top, first_drop - 1 + share - final.long_rows.first, last_drop - final.long_rows.last)
end

-- The belts that the blocks do not draw: belt a above the final column (the final column
-- draws the rest), the belt of every block that turns into another belt, and belt b.
---@param entities bpgen.Entity[]
---@param belt_name string
---@param stack bpgen.Slot[]
---@param belt_a integer
---@param final bpgen.Block  in place
local function add_belts(entities, belt_name, stack, belt_a, final)
  add_run(entities, belt_name, belt_a, 0, final.raw_belts[1].row - 1, defines.direction.south)
  for _, slot in ipairs(stack) do
    if slot.kind == "side" or slot.kind == "join" then
      add_joining_belt(entities, belt_name, slot, belt_a)
    end
  end
  local start = belt_b_start(stack)
  if start then
    add_run(entities, belt_name, belt_a - 1, start, final.long_rows.last, defines.direction.south)
  end
end

-- Several blocks and the column that eats what they make, as one block (see `stack_of` for
-- how they stand). The column goes to the right of them, beside the last block, and its
-- input belt, belt a, comes down from the top of the blueprint.
---@param blocks bpgen.Block[]  the blocks that make the ingredients
---@param suppliers (bpgen.StageLayout|bpgen.RawSupplier)[]  their stages, same order
---@param stage bpgen.StageLayout  the stage of the final column
---@param names bpgen.SharedNames
---@param is_root boolean  whether this is the last block of the blueprint, which draws its product belt
---@return bpgen.Block
local function composite_block(blocks, suppliers, stage, names, is_root)
  local stack = stack_of(blocks, suppliers)
  local entities, belt_a, end_row = place_stack(stack, names.belt)
  local final = layout.chain_block({stage}, names, {product_belt = is_root})
  local first_row = final_first_row(stack[#stack], final, stage.machine_count)
  shift(final, belt_a, first_row)
  absorb(entities, final)
  add_belts(entities, names.belt, stack, belt_a, final)
  local poles, groups, raw_belts = {}, {}, {}
  for _, slot in ipairs(stack) do
    groups[#groups + 1] = slot.block.poles
    append(poles, slot.block.poles)
    append(raw_belts, slot.block.raw_belts)
  end
  groups[#groups + 1] = final.poles
  join_pole_groups(groups)
  return {
    entities = entities,
    poles = append(poles, final.poles),
    product_column = final.product_column,
    output_rows = final.output_rows,
    height = math.max(end_row, first_row + final.height),
    raw_belts = raw_belts,
  }
end

-- The tile row of a pole.
---@param pole bpgen.Entity
---@return number
local function row_of(pole)
  return pole.position.y - 0.5
end

-- The poles of a block in the column beside its product belt, from the top.
---@param block bpgen.Block
---@return bpgen.Entity[]
local function pole_line(block)
  local line = {}
  for _, pole in ipairs(block.poles) do
    if pole.position.x - 0.5 == block.product_column - 1 then
      line[#line + 1] = pole
    end
  end
  table.sort(line, function(first, second) return first.position.y < second.position.y end)
  return line
end

-- Adds a pole at tile row `row` of the line, wired to the pole before it.
---@param block bpgen.Block
---@param pole_name string
---@param row number
---@param neighbour bpgen.Entity
---@return bpgen.Entity
local function add_line_pole(block, pole_name, row, neighbour)
  local pole = {name = pole_name, position = grid.position(block.product_column - 1, row)}
  block.entities[#block.entities + 1] = pole
  pole.entity_number = #block.entities
  block.poles[#block.poles + 1] = pole
  layout.connect_poles(neighbour, pole)
  return pole
end

-- Lengthens the line of poles of a block up and down, until it is within LINE_END_GAP
-- rows of the top and of the bottom. The tiles are free: the last column ends at or
-- above the new poles, or has no machine in the tile at the bottom of its last row.
---@param block bpgen.Block
---@param pole_name string
local function extend_pole_line(block, pole_name)
  local line = pole_line(block)
  local last, first = line[#line], line[1]
  while last and block.height - 1 - row_of(last) > LINE_END_GAP do
    last = add_line_pole(block, pole_name, math.min(row_of(last) + POLE_HOP, block.height - 1), last)
  end
  while first and row_of(first) > LINE_END_GAP do
    first = add_line_pole(block, pole_name, math.max(row_of(first) - POLE_HOP, 0), first)
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
      error("blocks: a chain of stages cannot start from a stage with several made ingredients")
    end
    current = suppliers[1]
  end
  return chain
end

-- The block of a raw item: the first tile of its belt, which the join gives its direction.
---@param supplier bpgen.RawSupplier
---@return bpgen.Block
local function raw_block(supplier)
  return {
    entities = {}, poles = {}, product_column = 0, height = 1, output_rows = {first = 0, last = 0},
    raw_belts = {{stage = supplier, column = 0, row = 0}},
  }
end

-- The block that makes what a stage makes: the columns of a chain, or the blocks of the
-- stages that make its ingredients with the column that eats them. The last block of the
-- blueprint has no neighbours, so it needs no line of poles.
---@param stage bpgen.StageLayout|bpgen.RawSupplier
---@param names bpgen.SharedNames
---@param is_root boolean
---@return bpgen.Block
local function block_of(stage, names, is_root)
  if stage.raw_item then
    return raw_block(stage)
  end
  local suppliers = stage.suppliers or {}
  local block
  if #suppliers >= 2 then
    local blocks = {}
    for index, supplier in ipairs(suppliers) do
      blocks[index] = block_of(supplier, names, false)
    end
    block = composite_block(blocks, suppliers, stage, names, is_root)
  else
    block = layout.chain_block(straight_chain(stage), names, {product_belt = is_root})
  end
  if not is_root then
    extend_pole_line(block, names.pole)
  end
  return block
end

-- The tiles of a trail that brings a belt of raw items to the top left of the blueprint:
-- from the top row of the blueprint, level with the top of the first belt, down
-- `entry_column` (west of the blueprint, or the column of the belt itself when that is
-- west of the others), then east along the row of the belt, into its first tile. A belt
-- in the entry column has no tiles to the east: the trail only makes it longer.
---@param belt bpgen.RawBelt
---@param entry_column integer
---@param top_row integer  the row of the first belt of raw items of the blueprint
---@return {column: integer, row: integer, direction: defines.direction}[]
local function trail_tiles(belt, entry_column, top_row)
  local tiles = {}
  for row = top_row, belt.row - 1 do
    tiles[#tiles + 1] = {column = entry_column, row = row, direction = defines.direction.south}
  end
  for column = entry_column, belt.column - 1 do
    tiles[#tiles + 1] = {column = column, row = belt.row, direction = defines.direction.east}
  end
  return tiles
end

-- Brings every belt of raw items to the top left, so that the player can lay them all
-- in from one corner: a belt that does not start in the top left corner gets a trail
-- along the west side of the blueprint. The trails run down columns west of the blueprint
-- (or west of the others, for a lower block that sticks out to the west: its belt of raw
-- items is the trail), the lower the belt the further west, so that a trail turns east
-- below the trails of the belts above it and none crosses another. The first belt, of the
-- block in the corner (which is never moved), is the only one in the top row, in column 0.
---@param block bpgen.Block
---@param belt_name string
local function add_trails(block, belt_name)
  local top_row = block.raw_belts[1].row
  local entry_column = 0
  for _, belt in ipairs(block.raw_belts) do
    if belt.row ~= top_row then
      entry_column = math.min(entry_column - 1, belt.column)
      for _, tile in ipairs(trail_tiles(belt, entry_column, top_row)) do
        add_belt(block.entities, belt_name, tile.column, tile.row, tile.direction)
      end
    end
  end
end

-- The blueprint for `root`, the stage that makes the final product, with the stages that
-- make its ingredients in `suppliers`: none or one for a stage fed raw items or by a
-- chain, two for a stage with two made ingredients.
-- Returns the entities (numbered from 1) and the stages fed raw items, from the top of
-- the blueprint down, which is the order their belts of raw items come in. For a stage
-- with no more than one supplier at each step this is the same as `layout.build_chain`.
---@param root bpgen.StageLayout
---@param names bpgen.SharedNames
---@return bpgen.Entity[] entities
---@return bpgen.StageLayout[] raw_stages
function blocks.build(root, names)
  local block = block_of(root, names, true)
  add_trails(block, names.belt)
  local raw_stages = {}
  for index, belt in ipairs(block.raw_belts) do
    raw_stages[index] = belt.stage
  end
  return block.entities, raw_stages
end

return blocks
