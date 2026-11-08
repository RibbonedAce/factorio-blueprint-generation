-- scripts/blocks.lua
-- Recipes with two made ingredients, laid out as a tree of blocks. Pure, like
-- scripts/layout.lua, which builds the columns of a chain; this module puts them together.
--
-- A block is the blueprint of one item at one rate (see `bpgen.Block`): the raw items
-- enter from the west, and one product belt runs down its rightmost column. A block
-- never draws its product belt; whoever uses the block does, and picks the way it runs.
-- A straight chain of columns (furnaces, then assemblers) is a block. So are two blocks
-- with the column of machines that eats what they make, which is how a recipe with two
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

-- Where two blocks meet and feed the column that eats what they make.
---@class bpgen.Junction
---@field lower_column integer  tile column of the lower block's product belt, beside the input belt
---@field input_column integer  tile column of the upper block's product belt, which goes on as the input belt of the final column
---@field row integer  the first row of the lower block, where its product belt turns east into the input belt

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

---@param upper bpgen.Block
---@param lower bpgen.Block
---@return bpgen.Junction
local function junction_of(upper, lower)
  return {lower_column = upper.product_column - 1, input_column = upper.product_column, row = upper.height}
end

-- Moves the lower block into place, below the upper block, and returns the entities of both.
-- The upper block stays where it is, in the corner. The lower block is moved so that its
-- product belt is beside the upper block's: east when it is narrower, west when it is as wide
-- or wider, which puts it in negative columns, where its belt of raw items is its own trail.
-- It starts in the join row: its first output inserter then drops onto the belt tile that
-- turns east there, a curve, which side-loads everything it carries onto one lane anyway.
---@param upper bpgen.Block
---@param lower bpgen.Block
---@param junction bpgen.Junction
---@return bpgen.Entity[]
local function place_blocks(upper, lower, junction)
  shift(lower, junction.lower_column - lower.product_column, junction.row)
  local entities = {}
  absorb(entities, upper)
  absorb(entities, lower)
  return entities
end

-- The product belt of the lower block, running north up to the join row, and the belt
-- tile there that turns it east into the side of the input belt.
---@param entities bpgen.Entity[]
---@param belt_name string
---@param junction bpgen.Junction
---@param lower_height integer
local function add_lower_belt(entities, belt_name, junction, lower_height)
  for row = junction.row + 1, junction.row + lower_height - 1 do
    add_belt(entities, belt_name, junction.lower_column, row, defines.direction.north)
  end
  add_belt(entities, belt_name, junction.lower_column, junction.row, defines.direction.east)
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
---@param groups bpgen.Entity[][]  at least one
local function join_pole_groups(groups)
  local joined = append({}, groups[1])
  local waiting = {table.unpack(groups, 2)}
  while #waiting > 0 do
    local pair, index = closest_group(joined, waiting)
    if not pair or not index then
      return
    end
    layout.connect_poles(pair.from, pair.to)
    append(joined, table.remove(waiting, index))
  end
end

-- The final column goes to the right of the lower block, starting one row below the
-- join row, and its input belt comes down from the top of the blueprint.
-- Two blocks and the column that eats what they make, as one block.
---@param upper bpgen.Block
---@param lower bpgen.Block
---@param stage bpgen.StageLayout  the stage of the final column
---@param names bpgen.SharedNames
---@param is_root boolean  whether this is the last block of the blueprint, which draws its product belt
---@return bpgen.Block
local function composite_block(upper, lower, stage, names, is_root)
  local junction = junction_of(upper, lower)
  local entities = place_blocks(upper, lower, junction)
  local options = {product_belt = is_root, input_belt_rows_above = junction.row + 1}
  local final = layout.chain_block({stage}, names, options)
  shift(final, junction.input_column, junction.row + 1)
  absorb(entities, final)
  add_lower_belt(entities, names.belt, junction, lower.height)
  join_pole_groups({upper.poles, lower.poles, final.poles})
  return {
    entities = entities,
    poles = append(append(append({}, upper.poles), lower.poles), final.poles),
    product_column = final.product_column,
    height = math.max(junction.row + lower.height, junction.row + 1 + final.height),
    raw_belts = append(append({}, upper.raw_belts), lower.raw_belts),
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

local block_of

-- The two blocks that make a stage's ingredients, the taller one first, as the upper block.
-- Equally tall blocks stay in the recipe's order.
---@param suppliers (bpgen.StageLayout|bpgen.RawSupplier)[]
---@param names bpgen.SharedNames
---@return bpgen.Block upper
---@return bpgen.Block lower
local function ordered_blocks(suppliers, names)
  local first = block_of(suppliers[1], names, false)
  local second = block_of(suppliers[2], names, false)
  if first.height < second.height then
    return second, first
  end
  return first, second
end

-- The block of a raw item: the first tile of its belt, which the join gives its direction.
---@param supplier bpgen.RawSupplier
---@return bpgen.Block
local function raw_block(supplier)
  return {entities = {}, poles = {}, product_column = 0, height = 1, raw_belts = {{stage = supplier, column = 0, row = 0}}}
end

-- The block that makes what a stage makes, before it gets a line of poles.
---@param stage bpgen.StageLayout
---@param names bpgen.SharedNames
---@param is_root boolean
---@return bpgen.Block
local function built_block(stage, names, is_root)
  local suppliers = stage.suppliers or {}
  if #suppliers == 2 then
    local upper, lower = ordered_blocks(suppliers, names)
    return composite_block(upper, lower, stage, names, is_root)
  end
  local chain = straight_chain(stage)
  return layout.chain_block(chain, names, {product_belt = is_root, input_belt_rows_above = 0})
end

-- The block that makes what a stage makes. The last block of the blueprint has no
-- neighbours, so it needs no line of poles.
---@param stage bpgen.StageLayout|bpgen.RawSupplier
---@param names bpgen.SharedNames
---@param is_root boolean
---@return bpgen.Block
function block_of(stage, names, is_root)
  if stage.raw_item then
    return raw_block(stage)
  end
  local block = built_block(stage, names, is_root)
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
-- block in the corner, is in column 0.
---@param block bpgen.Block
---@param belt_name string
local function add_trails(block, belt_name)
  local top_row = block.raw_belts[1].row
  local entry_column = 0
  for _, belt in ipairs(block.raw_belts) do
    if belt.column ~= 0 or belt.row ~= top_row then
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
