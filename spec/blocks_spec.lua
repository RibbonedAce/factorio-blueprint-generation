-- spec/blocks_spec.lua
-- Recipes with two made ingredients, built as blocks (see the top of scripts/blocks.lua).
-- Positions are TILES read off the diagram in the small tree below (the top-left tile an
-- entity covers, y growing down; see scripts/grid.lua).
---@diagnostic disable: undefined-field  -- luassert's `assert` has fields (`assert.are`, `assert.is_nil`, ...) the editor cannot see

local blocks = require("scripts.blocks")
local builders = require("spec.support.builders")
local grid = require("scripts.grid")
local layout = require("scripts.layout")
local tracer = require("spec.support.belt_tracer")
local validator = require("spec.support.blueprint_validator")

local NAMES = builders.NAMES
local north, east, south = defines.direction.north, defines.direction.east, defines.direction.south

-- A column of 2 x 2 furnaces, one inserter on each side, or of 3 x 3 assemblers.
local function furnaces(machine, count)
  return {machine_count = count, machine = machine, shape = {machine_size = 2, input_inserters = 1, output_inserters = 1}, suppliers = {}}
end

local function assemblers(machine, count, input_inserters, output_inserters, suppliers)
  return {
    machine_count = count, machine = machine,
    shape = {machine_size = 3, input_inserters = input_inserters, output_inserters = output_inserters},
    suppliers = suppliers or {},
  }
end

local function entities_named(entities, name)
  local found = {}
  for _, entity in ipairs(entities) do
    if entity.name == name then
      found[#found + 1] = entity
    end
  end
  return found
end

-- An assembler whose machines each have a plain inserter and a long-handed one (in the row under it). The plain
-- inserter takes from belt a, the input belt next to the inserters; the long-handed one from belt b, one column further
-- west. `machine` says which assembler it is, for the tracer.
local function gadget_assembler(count, suppliers, machine)
  return {
    machine_count = count, machine = machine or "gadget-assembler",
    shape = {machine_size = 3, input_inserters = 1, long_inserters = 1, output_inserters = 1},
    suppliers = suppliers,
  }
end

-- The same block, said to ride belt b.
local function on_belt_b(block)
  block.belt = "b"
  return block
end

local function tile_of(entity, size)
  return grid.top_left_tile(entity.position, size, size)
end

local function entity_at(entities, name, x, y, size)
  for _, entity in ipairs(entities) do
    local tile = tile_of(entity, size)
    if entity.name == name and tile.x == x and tile.y == y then
      return entity
    end
  end
end

-- The rows of the belts in one tile column, in order.
local function belt_rows(entities, column)
  local rows = {}
  for _, entity in ipairs(entities) do
    local tile = tile_of(entity, 1)
    if entity.name == NAMES.belt and tile.x == column then
      rows[#rows + 1] = tile.y
    end
  end
  table.sort(rows)
  return rows
end

local function belt_directions(entities, column)
  local directions, seen = {}, {}
  for _, entity in ipairs(entities) do
    if entity.name == NAMES.belt and tile_of(entity, 1).x == column and not seen[entity.direction] then
      seen[entity.direction] = true
      directions[#directions + 1] = entity.direction
    end
  end
  return directions
end

describe("blocks", function()
  describe("two blocks of one furnace each and an assembler that eats what they make", function()
    -- The upper block is in the corner, in columns 0 to 5: 0 (raw belt), 1 (inserters), 2-3 (furnace),
    -- 4 (inserters), 5 (product belt, which goes on as the input belt of the final column). The lower block is as
    -- wide, so it is moved one column west to put its product belt in column 4, beside it: columns -1 (raw belt),
    -- 0, 1-2, 3 and 4. Rows 0 and 1 are the upper block; the lower block starts in row 2, the join row, where its
    -- product belt turns east into the side of the input belt. The assembler's input inserters are in column 6,
    -- the machine in 7-9, its output inserters in 10 and its output belt in 11.
    --
    --      x: -1 0 1 2 3 4 5 6 7 8 9 10 11
    --  row 0:    . v } I I } v
    --  row 1:    . . + I I + v
    --  row 2:    v } K K } > v
    --  row 3:    . + K K + ^ v } A A A  }  v
    --  row 4:    . . . . . . v } A A A  +  v
    local iron, copper = furnaces("iron-furnace", 1), furnaces("copper-furnace", 1)
    local root = assemblers("circuit-assembler", 1, 2, 1, {iron, copper})
    local entities, raw_stages = blocks.build(root, NAMES)

    it("lets the upper block's product belt go on south as the input belt of the final column", function()
      assert.are.same({0, 1, 2, 3, 4}, belt_rows(entities, 5)) -- down to the last input inserter, in row 4
      assert.are.same({south}, belt_directions(entities, 5))
    end)

    it("runs the lower block's product belt north, from its last row up to the join row", function()
      assert.are.equal(north, entity_at(entities, NAMES.belt, 4, 3, 1).direction)
    end)

    it("turns the lower block's product belt east into the side of the input belt in the join row", function()
      local turn = assert(entity_at(entities, NAMES.belt, 4, 2, 1))

      assert.are.equal(east, turn.direction)
    end)

    it("puts the final column to the right of the lower block, starting below the join row", function()
      assert.is_not_nil(entity_at(entities, "circuit-assembler", 7, 3, 3))
    end)

    it("draws the final product belt along the final column", function()
      assert.are.same({3, 4, 5}, belt_rows(entities, 11))
    end)

    it("starts the lower block in the join row, so its first output inserter drops onto the turn", function()
      assert.is_not_nil(entity_at(entities, "copper-furnace", 1, 2, 2))
      assert.is_not_nil(entity_at(entities, NAMES.inserter, 3, 2, 1))
    end)

    it("keeps the upper block in the corner and moves the lower block, which is as wide, one column west", function()
      assert.is_not_nil(entity_at(entities, "iron-furnace", 2, 0, 2))
      assert.is_not_nil(entity_at(entities, "copper-furnace", 1, 2, 2))
    end)

    it("lists the stages fed raw items from the top of the blueprint down", function()
      assert.are.equal(iron, raw_stages[1])
      assert.are.equal(copper, raw_stages[2])
    end)

    it("numbers every entity once", function()
      for index, entity in ipairs(entities) do
        assert.are.equal(index, entity.entity_number)
      end
    end)
  end)

  describe("two blocks of which the upper is wider", function()
    -- The upper block is 4 furnaces (8 rows) and a cable assembler, 12 columns wide, so its product belt is in
    -- column 11 and goes straight on south as the input belt of the final column. The lower block is one furnace
    -- column, 6 columns wide: it is moved east until its product belt is in column 10, beside the input belt, and
    -- starts in row 8, the join row. Its belt of raw items comes in at column 5. (A lower block that is as wide or
    -- wider is moved west instead, see the blocks above and below.)
    local cables = assemblers("cable-assembler", 1, 1, 2, {furnaces("copper-furnace", 4)})
    local root = assemblers("circuit-assembler", 1, 2, 1, {cables, furnaces("iron-furnace", 1)})
    local entities = blocks.build(root, NAMES)

    it("lets the upper block's product belt go on south as the input belt of the final column", function()
      assert.are.same({south}, belt_directions(entities, 11))
      assert.are.equal(east, entity_at(entities, NAMES.belt, 10, 8, 1).direction) -- the lower block's turn, beside it
    end)

    it("puts the lower block against the input belt, starting in the join row", function()
      assert.is_not_nil(entity_at(entities, "iron-furnace", 7, 8, 2))
    end)

    it("keeps the upper block in the corner", function()
      assert.is_not_nil(entity_at(entities, "copper-furnace", 2, 0, 2))
    end)
  end)

  describe("the line of poles beside the product belt of a block that has neighbours", function()
    local function poles_at(entities, x, y)
      return entity_at(entities, NAMES.pole, x, y, 1)
    end

    local function wired(from, to)
      for _, wire in ipairs(from.wires or {}) do
        if wire[3] == to.entity_number then
          return true
        end
      end
      return false
    end

    it("adds no pole when the line of poles already reaches both ends of the block", function()
      local root = assemblers("circuit-assembler", 1, 2, 1, {furnaces("iron-furnace", 1), furnaces("copper-furnace", 1)})

      local entities = blocks.build(root, NAMES)

      local poles = 0
      for _, entity in ipairs(entities) do
        poles = poles + (entity.name == NAMES.pole and 1 or 0)
      end
      assert.are.equal(6, poles) -- two for each of the two furnaces and for the assembler
    end)

    it("adds a pole at the bottom of the block, wired to the one above it, when the last column is shorter", function()
      -- The upper block is 4 furnaces (8 rows) and one cable assembler (3 rows); its last pole is in column 10, row 2.
      local cables = assemblers("cable-assembler", 1, 1, 2, {furnaces("copper-furnace", 4)})
      local root = assemblers("circuit-assembler", 1, 2, 1, {cables, furnaces("iron-furnace", 1)})

      local entities = blocks.build(root, NAMES)

      local tail = assert(poles_at(entities, 10, 7)) -- the last row of the block, within one hop (6 rows) of row 2
      assert.is_true(wired(assert(poles_at(entities, 10, 2)), tail))
    end)

    it("adds a pole at the top of a block whose last column starts further down", function()
      -- The lower block is a tree 6 rows tall whose final column covers rows 3 to 5 of it; the upper block is
      -- 4 furnaces (8 rows), so the tree starts in row 8 and its first pole would be in row 12 without the line.
      -- The tree is 7 columns wider than the furnaces' block, so it is moved 7 columns west: its output inserters
      -- are in column 3.
      local tree = assemblers("belt-assembler", 1, 2, 1, {furnaces("iron-furnace", 1), furnaces("copper-furnace", 1)})
      local root = assemblers("circuit-assembler", 1, 2, 1, {tree, furnaces("iron-furnace", 4)})

      local entities = blocks.build(root, NAMES)

      local head = assert(poles_at(entities, 3, 8)) -- the top row of the tree, in the column of the tree's output inserters
      assert.is_true(wired(assert(poles_at(entities, 3, 12)), head))
    end)

    it("adds no poles to the last block of the blueprint, which has no neighbours", function()
      -- The final column is 3 rows tall beside a lower block of 8 rows, which would leave a gap at the bottom of
      -- the column beside the product belt if the last block had a line.
      local cables = assemblers("cable-assembler", 1, 1, 2, {furnaces("copper-furnace", 4)})
      local root = assemblers("circuit-assembler", 1, 2, 1, {furnaces("iron-furnace", 1), cables})

      local entities = blocks.build(root, NAMES)

      assert.is_nil(poles_at(entities, 16, 4)) -- the line of a block with neighbours would go up from the pole in row 10
    end)
  end)

  describe("the belts of raw items, which all start at the top left", function()
    -- The small tree again: the upper block's belt of raw items starts at (0, 0), in the corner, and the lower
    -- block's, moved one column west, at (-1, 2).
    local function small_tree()
      local root = assemblers("circuit-assembler", 1, 2, 1, {furnaces("iron-furnace", 1), furnaces("copper-furnace", 1)})
      return (blocks.build(root, NAMES))
    end

    it("gives the upper block's belt no trail, since it starts in the corner", function()
      local entities = small_tree()

      assert.are.equal(south, entity_at(entities, NAMES.belt, 0, 0, 1).direction)
      assert.are.same({}, belt_rows(entities, -2))
    end)

    it("makes the belt of a lower block that sticks out to the west longer, with no turn", function()
      local entities = small_tree()

      assert.are.same({0, 1, 2}, belt_rows(entities, -1)) -- from the top row down to the first row of the block
      assert.are.same({south}, belt_directions(entities, -1))
    end)

    it("lets each belt of a tree that sticks out far to the west run straight down its own column", function()
      -- The lower block is a tree of two furnaces, 12 columns wide, below a block of 4 furnaces 6 columns wide:
      -- moved 7 columns west, its two belts of raw items are in columns -7 and -8.
      local tree = assemblers("belt-assembler", 1, 2, 1, {furnaces("iron-furnace", 1), furnaces("iron-furnace", 1)})
      local root = assemblers("circuit-assembler", 1, 2, 1, {furnaces("copper-furnace", 4), tree})

      local entities = blocks.build(root, NAMES)

      assert.are.same({0, 1, 2, 3, 4, 5, 6, 7, 8}, belt_rows(entities, -7)) -- down to the first row of the tree
      assert.are.same({0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10}, belt_rows(entities, -8)) -- down to the first row of the tree's lower block
      assert.are.same({}, belt_rows(entities, -9))
    end)

    it("gives the lower belt a longer trail when the upper block is wider, so the belt starts further east", function()
      -- The upper block is 4 furnaces and a cable assembler (8 rows), 12 columns wide; the lower block is a
      -- furnace column 6 columns wide, moved 5 columns east, so its belt starts at (5, 8).
      local cables = assemblers("cable-assembler", 1, 1, 2, {furnaces("copper-furnace", 4)})
      local root = assemblers("circuit-assembler", 1, 2, 1, {cables, furnaces("iron-furnace", 1)})

      local entities = blocks.build(root, NAMES)

      assert.are.same({0, 1, 2, 3, 4, 5, 6, 7, 8}, belt_rows(entities, -1)) -- only the lower belt's trail
      assert.are.same({}, belt_rows(entities, -2))
      assert.are.equal(east, entity_at(entities, NAMES.belt, 4, 8, 1).direction) -- next to the belt in column 5
    end)

    it("gives a trail to a belt in column 0 below the top row, where a lower block that is one column narrower leaves it", function()
      -- The upper block is one assembler fed raw items: columns 0 (raw belt), 1, 2-4, 5, and its product belt in column 6,
      -- 3 rows. The lower block is one furnace column with its product belt in column 5, right beside the input belt in
      -- column 6, so it is not moved: its belt of raw items is at (0, 3).
      local assembler = assemblers("chest-assembler", 1, 1, 1, {})
      local root = assemblers("circuit-assembler", 1, 2, 1, {assembler, furnaces("iron-furnace", 1)})

      local entities = blocks.build(root, NAMES)

      assert.are.same({0, 1, 2, 3}, belt_rows(entities, -1))
      assert.are.equal(east, entity_at(entities, NAMES.belt, -1, 3, 1).direction)
    end)

    it("gives a chain no trail, since its belt starts in the corner", function()
      local entities = blocks.build(assemblers("gear-assembler", 2, 2, 1, {furnaces("iron-furnace", 3)}), NAMES)

      assert.are.same({}, belt_rows(entities, -1))
    end)
  end)

  describe("a block that is a tree itself, above another block", function()
    it("starts the block below it in the row under the tree, when the tree ends with its lower block", function()
      -- The tree is two blocks of 3 furnaces, 6 rows each, one above the other, and a final column of 3 rows beside
      -- the lower one: 12 rows. It is taller than the furnace block below it, so it goes on top, and the block
      -- below starts in row 12.
      local tree = assemblers("belt-assembler", 1, 2, 1, {furnaces("iron-furnace", 3), furnaces("copper-furnace", 3)})
      local root = assemblers("underground-assembler", 1, 2, 1, {tree, furnaces("iron-furnace", 1)})

      local entities = blocks.build(root, NAMES)

      assert.are.equal(east, entity_at(entities, NAMES.belt, -1, 12, 1).direction) -- the trail of the lower block's belt, in its first row
      assert.is_nil(entity_at(entities, NAMES.belt, -1, 13, 1))
    end)
  end)

  describe("three or four suppliers, some of them on a second input belt", function()
    -- The final column is a "gadget" assembler (see `gadget_assembler`). Furnace blocks are 6 columns wide (the
    -- product belt in column 5), 2 rows a furnace.
    --
    -- Belt a is the product belt of the top block (3 furnaces, rows 0-5, column 5). Belt b starts at the top row of
    -- the second block (2 furnaces, moved two columns west, product belt in column 3, rows 6-9), whose belt turns
    -- east into it. The last block (1 furnace, moved one column west, rows 10-11) drops on belt b, in column 4.
    describe("two on belt b and one on belt a", function()
      local top, joiner, source = furnaces("iron-furnace", 3), on_belt_b(furnaces("copper-furnace", 2)), on_belt_b(furnaces("brick-furnace", 1))
      local entities, raw_stages = blocks.build(gadget_assembler(1, {top, joiner, source}), NAMES)

      it("runs belt a down from the top row to the row of the final column's plain inserter", function()
        assert.are.same({0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10}, belt_rows(entities, 5))
        assert.are.same({south}, belt_directions(entities, 5))
      end)

      it("turns the belt of the second block east at its top row into the head of belt b", function()
        assert.are.same({6, 7, 8, 9}, belt_rows(entities, 3))
        assert.are.equal(east, entity_at(entities, NAMES.belt, 3, 6, 1).direction)
        assert.are.equal(north, entity_at(entities, NAMES.belt, 3, 7, 1).direction)
      end)

      it("runs belt b south from the top row of the second block to the final column's long-handed inserter", function()
        assert.are.same({6, 7, 8, 9, 10, 11}, belt_rows(entities, 4))
        assert.are.same({south}, belt_directions(entities, 4))
      end)

      it("puts the final column beside the last block, with its plain inserter in the first row", function()
        assert.is_not_nil(entity_at(entities, "gadget-assembler", 7, 10, 3))
        assert.are.equal(NAMES.inserter, entity_at(entities, NAMES.inserter, 6, 10, 1).name)
      end)

      it("puts the long-handed inserter under the plain one, taking from belt b over belt a", function()
        assert.are.equal(NAMES.long_inserter, entity_at(entities, NAMES.long_inserter, 6, 11, 1).name)
      end)

      it("lists the stages fed raw items from the top of the blueprint down", function()
        assert.are.same({top, joiner, source}, raw_stages)
      end)
    end)

    -- Belt a is the product belt of the top block (3 furnaces, rows 0-5, column 5) with the second block's belt
    -- turning east into its side (2 furnaces, column 4, rows 6-9). The last block (1 furnace, rows 10-11) drops on belt b,
    -- which starts at its top row in the same column 4 as the tail of the second block's belt, pointing away from it.
    describe("one on belt b and two on belt a", function()
      local top, side, source = furnaces("iron-furnace", 3), furnaces("copper-furnace", 2), on_belt_b(furnaces("brick-furnace", 1))
      local entities = blocks.build(gadget_assembler(1, {top, side, source}), NAMES)

      it("turns the belt of the second block east into the side of belt a", function()
        assert.are.equal(east, entity_at(entities, NAMES.belt, 4, 6, 1).direction)
        assert.are.equal(north, entity_at(entities, NAMES.belt, 4, 9, 1).direction)
      end)

      it("starts belt b at the top row of the last block, pointing away from the tail of the belt above", function()
        assert.are.equal(south, entity_at(entities, NAMES.belt, 4, 10, 1).direction)
        assert.are.equal(south, entity_at(entities, NAMES.belt, 4, 11, 1).direction)
      end)

      it("runs belt a down to the row of the final column's plain inserter", function()
        assert.are.same({0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10}, belt_rows(entities, 5))
      end)
    end)

    describe("two on each belt", function()
      -- Rows: top block 0-5, second 6-9 (belt a side-load, column 4), third 10-13 (column 3, turning east at row 10
      -- into the head of belt b), last 14-15 (drops on belt b in column 4). The final column starts in row 14.
      local top, side = furnaces("iron-furnace", 3), furnaces("copper-furnace", 2)
      local joiner, source = on_belt_b(furnaces("brick-furnace", 2)), on_belt_b(furnaces("stick-furnace", 1))
      local entities = blocks.build(gadget_assembler(1, {top, side, joiner, source}), NAMES)

      it("runs belt b from the head of the third block to the long-handed inserter of the final column", function()
        assert.are.equal(south, entity_at(entities, NAMES.belt, 4, 10, 1).direction)
        assert.are.equal(south, entity_at(entities, NAMES.belt, 4, 15, 1).direction)
        assert.is_nil(entity_at(entities, NAMES.belt, 4, 16, 1))
      end)

      it("turns the belt of the third block east into the head of belt b", function()
        assert.are.equal(east, entity_at(entities, NAMES.belt, 3, 10, 1).direction)
      end)

      it("puts the final column beside the last block", function()
        assert.is_not_nil(entity_at(entities, "gadget-assembler", 7, 14, 3))
      end)
    end)

    it("puts the taller block of belt a on top when the recipe lists the shorter one first", function()
      local short, tall = furnaces("iron-furnace", 1), furnaces("copper-furnace", 3)
      local source = on_belt_b(furnaces("brick-furnace", 1))

      local _, raw_stages = blocks.build(gadget_assembler(1, {short, tall, source}), NAMES)

      assert.are.same({tall, short, source}, raw_stages)
    end)

    it("leaves an empty row between two blocks when a belt running north in the first row of the lower block would feed the tail of a belt above it", function()
      -- The circuit block above is rows 0-7 (2 iron furnaces, a cable block of 2 copper furnaces and a cable assembler,
      -- and the circuit assembler): its cable belt, column 4, ends in row 7. The gear block below (3 furnaces) has the
      -- belt from its furnaces to its assembler in column 4 too, running north up to its first row. Right under the
      -- circuit block it would run its plates into the cable belt, so the gear block starts in row 9, not 8.
      local circuit = assemblers("circuit-assembler", 1, 2, 1, {
        furnaces("iron-furnace", 2),
        assemblers("cable-assembler", 1, 1, 2, {furnaces("copper-furnace", 2)}),
      })
      local gear = assemblers("gear-assembler", 1, 2, 1, {furnaces("iron-furnace", 3)})

      local entities = blocks.build(gadget_assembler(1, {circuit, gear, on_belt_b(furnaces("brick-furnace", 1))}), NAMES)

      assert.is_not_nil(entity_at(entities, "iron-furnace", 1, 9, 2)) -- the first furnace of the gear block
      assert.is_nil(entity_at(entities, NAMES.belt, 4, 8, 1)) -- the row between is empty
    end)

    it("pushes the final column down until its first long-handed inserter sees what the last block drops, when that block drops it in one row", function()
      -- The last block is itself a gadget block: its final column is its lowest part, with one output inserter, in row 11
      -- of the whole blueprint. Belt b runs south, so a long-handed inserter above that row would never see a gadget.
      -- The outer final column has two machines with long-handed inserters in the second row of each, so it starts in row 10.
      local inner = on_belt_b(gadget_assembler(1, {
        furnaces("iron-furnace", 1),
        assemblers("cable-assembler", 1, 1, 2, {furnaces("copper-furnace", 1)}),
        on_belt_b(furnaces("brick-furnace", 1)),
      }, "inner-assembler"))
      local outer = gadget_assembler(2, {furnaces("iron-furnace", 1), inner, furnaces("brick-furnace", 2)}, "outer-assembler")

      local entities = blocks.build(outer, NAMES)

      assert.is_not_nil(entity_at(entities, "outer-assembler", 7, 10, 3))
      assert.are.equal(NAMES.long_inserter, entity_at(entities, NAMES.long_inserter, 6, 11, 1).name)
    end)

    it("pushes the final column down until the last of its machines sees every drop of a much taller last block", function()
      -- The last block is 5 furnaces under a block of 3 (rows 6-15), its output inserters in rows 6, 8, 10, 12 and 14.
      -- Two machines, long-handed inserters in the second row of each: the first sees its half of the drops from row 9,
      -- but the second, 3 rows lower, must reach row 14, so the final column starts in row 10 (long-handed inserters in
      -- rows 11 and 14).
      local top, source = furnaces("iron-furnace", 3), on_belt_b(furnaces("brick-furnace", 5))

      local entities = blocks.build(gadget_assembler(2, {top, source}), NAMES)

      assert.is_not_nil(entity_at(entities, "gadget-assembler", 7, 10, 3))
      assert.are.equal(NAMES.long_inserter, entity_at(entities, NAMES.long_inserter, 6, 14, 1).name)
    end)

    it("pushes the final column down until its last long-handed inserter is level with the last output inserter of the last block", function()
      -- The last block is 4 furnaces (8 rows, rows 6-13 under a top block of 3 furnaces); its output inserters are in
      -- rows 6, 8, 10 and 12. The final column is one machine whose long-handed inserter is its second row, so it starts
      -- in row 11 and the long-handed inserter, in row 12, is level with the last output inserter.
      local top, source = furnaces("iron-furnace", 3), on_belt_b(furnaces("brick-furnace", 4))

      local entities = blocks.build(gadget_assembler(1, {top, source}), NAMES)

      assert.is_not_nil(entity_at(entities, "gadget-assembler", 7, 11, 3))
      assert.are.equal(NAMES.long_inserter, entity_at(entities, NAMES.long_inserter, 6, 12, 1).name)
    end)
  end)

  describe("a raw item that goes with a made one, on a belt of its own", function()
    -- A pole assembler eats wood and cables. The cables' block is one copper furnace and one cable assembler, with
    -- a belt of raw items at (0, 0); it is the upper block, 12 columns wide, rows 0 to 2. The wood is a block of its
    -- own with no machines, below: one belt tile in the join row (row 3), in column 10, beside the input belt in
    -- column 11. The wood tile is the turn: the trail brings the wood east along the join row into it.
    local function poles(first_raw)
      local cables = assemblers("cable-assembler", 1, 1, 2, {furnaces("copper-furnace", 1)})
      local wood = {raw_item = "wood"}
      return assemblers("pole-assembler", 1, 2, 1, first_raw and {wood, cables} or {cables, wood})
    end

    it("runs the raw item east along the join row, below the block above, into the side of the input belt", function()
      local entities = blocks.build(poles(false), NAMES)

      assert.are.same({3}, belt_rows(entities, 10))
      assert.are.equal(east, entity_at(entities, NAMES.belt, 10, 3, 1).direction) -- the first tile of the raw item's belt is the turn
    end)

    it("brings the trail of the raw item down the west side and east along the join row", function()
      local entities = blocks.build(poles(false), NAMES)

      assert.are.same({0, 1, 2, 3}, belt_rows(entities, -1))
      assert.are.equal(south, entity_at(entities, NAMES.belt, -1, 2, 1).direction)
      assert.are.equal(east, entity_at(entities, NAMES.belt, -1, 3, 1).direction)
      assert.are.equal(east, entity_at(entities, NAMES.belt, 9, 3, 1).direction) -- the tile before the first tile of the raw item's belt
    end)

    it("lists the belt of the cables' ore first and the belt of the raw item last", function()
      local _, raw_stages = blocks.build(poles(false), NAMES)

      assert.are.equal("copper-furnace", raw_stages[1].machine)
      assert.are.equal("wood", raw_stages[2].raw_item)
    end)

    it("puts the raw item below the made one when the recipe lists it first", function()
      local listed_second = blocks.build(poles(false), NAMES)

      local listed_first, raw_stages = blocks.build(poles(true), NAMES)

      assert.are.same(listed_second, listed_first)
      assert.are.equal("wood", raw_stages[2].raw_item)
    end)

    it("builds no machine for the raw item", function()
      local entities = blocks.build(poles(false), NAMES)

      assert.are.equal(1, #entities_named(entities, "pole-assembler"))
      assert.are.equal(1, #entities_named(entities, "cable-assembler"))
      assert.are.equal(1, #entities_named(entities, "copper-furnace"))
    end)
  end)

  describe("the recipe of the machines", function()
    it("sets the recipe of the machines of every block and of the final column, and none on the furnaces", function()
      local cables = assemblers("cable-assembler", 1, 1, 2, {furnaces("copper-furnace", 1)})
      cables.recipe = "copper-cable"
      local root = assemblers("circuit-assembler", 1, 2, 1, {furnaces("iron-furnace", 1), cables})
      root.recipe = "electronic-circuit"

      local entities = blocks.build(root, NAMES)

      local recipes = {}
      for _, entity in ipairs(entities) do
        if entity.recipe then
          recipes[#recipes + 1] = entity.name .. " " .. entity.recipe
        end
      end
      table.sort(recipes)
      assert.are.same({"cable-assembler copper-cable", "circuit-assembler electronic-circuit"}, recipes)
    end)
  end)

  describe("which block goes on top", function()
    it("puts the taller block on top and lists its stage first", function()
      local short, tall = furnaces("iron-furnace", 1), furnaces("copper-furnace", 3)
      local root = assemblers("circuit-assembler", 1, 2, 1, {short, tall})

      local entities, raw_stages = blocks.build(root, NAMES)

      assert.are.equal(tall, raw_stages[1]) -- three furnaces are six rows, one is two
      assert.are.equal(short, raw_stages[2])
      assert.is_not_nil(entity_at(entities, "copper-furnace", 2, 0, 2))
    end)

    it("keeps the recipe's order when the blocks are equally tall", function()
      local first, second = furnaces("iron-furnace", 2), furnaces("copper-furnace", 2)
      local root = assemblers("circuit-assembler", 1, 2, 1, {first, second})

      local _, raw_stages = blocks.build(root, NAMES)

      assert.are.equal(first, raw_stages[1])
    end)

    it("compares the rows of the blocks, not the number of machines", function()
      local cables = assemblers("cable-assembler", 2, 1, 1, {furnaces("copper-furnace", 1)}) -- 2 x 3 rows
      local plates = furnaces("iron-furnace", 4) -- 4 x 2 rows
      local root = assemblers("circuit-assembler", 1, 2, 1, {cables, plates})

      local _, raw_stages = blocks.build(root, NAMES)

      assert.are.equal(plates.machine, raw_stages[1].machine) -- 8 rows against 6
    end)
  end)

  describe("a stage with no more than one made ingredient at each step", function()
    it("builds the same entities as a chain of columns", function()
      local furnace_column = furnaces("stone-furnace", 7)
      local assembler_column = assemblers("assembling-machine-1", 2, 2, 2, {furnace_column})

      local entities, raw_stages = blocks.build(assembler_column, NAMES)

      local expected = layout.build_chain({furnace_column, assembler_column}, NAMES)
      assert.are.same(expected, entities)
      assert.are.same({furnace_column}, raw_stages)
    end)

    it("builds a stage fed raw items on its own", function()
      local column = furnaces("stone-furnace", 3)

      local entities, raw_stages = blocks.build(column, NAMES)

      assert.are.same(layout.build_chain({column}, NAMES), entities)
      assert.are.same({column}, raw_stages)
    end)

    it("refuses a chain that starts from a stage with two made ingredients", function()
      local fork = assemblers("circuit-assembler", 1, 2, 1, {furnaces("iron-furnace", 1), furnaces("copper-furnace", 1)})
      local above_the_fork = assemblers("box-assembler", 1, 1, 1, {fork})

      assert.has_error(function() blocks.build(above_the_fork, NAMES) end)
    end)
  end)

  describe("the whole blueprint, checked by the generic validator and the belt tracer", function()
    local machines = {
      ["iron-furnace"] = {size = 2, eats = {"iron-ore"}, makes = "iron-plate"},
      ["copper-furnace"] = {size = 2, eats = {"copper-ore"}, makes = "copper-plate"},
      ["cable-assembler"] = {size = 3, eats = {"copper-plate"}, makes = "copper-cable"},
      ["circuit-assembler"] = {size = 3, eats = {"iron-plate", "copper-cable"}, makes = "electronic-circuit"},
      ["gear-assembler"] = {size = 3, eats = {"iron-plate"}, makes = "iron-gear-wheel"},
      ["belt-assembler"] = {size = 3, eats = {"iron-plate", "iron-gear-wheel"}, makes = "transport-belt"},
      ["underground-assembler"] = {size = 3, eats = {"iron-plate", "transport-belt"}, makes = "underground-belt"},
      ["other-belt-assembler"] = {size = 3, eats = {"iron-plate", "iron-gear-wheel"}, makes = "other-belt"},
      ["double-assembler"] = {size = 3, eats = {"transport-belt", "other-belt"}, makes = "double-belt"},
      ["pole-assembler"] = {size = 3, eats = {"wood", "copper-cable"}, makes = "small-electric-pole"},
      ["brick-furnace"] = {size = 2, eats = {"stone"}, makes = "stone-brick"},
      ["gadget-assembler"] = {size = 3, eats = {"iron-plate", "copper-cable", "stone-brick"}, makes = "gadget"},
      ["outer-assembler"] = {size = 3, eats = {"iron-plate", "gadget", "stone-brick"}, makes = "outer-gadget"},
    }
    local raw = {["iron-furnace"] = true, ["copper-furnace"] = true, ["brick-furnace"] = true}

    local function catalog()
      local entries = builders.a_catalog{pole_supply_radius = 2.5, pole_wire_reach = 7.5}
      for name, machine in pairs(machines) do
        entries[name] = {kind = "machine", width = machine.size, height = machine.size, needs_power = machine.size == 3}
      end
      return entries
    end

    -- Iron plates and copper cables to circuits, with the stages listed in either order.
    local function circuits(iron_count, copper_count, cable_count, circuit_count, iron_first)
      local cables = assemblers("cable-assembler", cable_count, 1, 2, {furnaces("copper-furnace", copper_count)})
      local iron = furnaces("iron-furnace", iron_count)
      local suppliers = iron_first and {iron, cables} or {cables, iron}
      return assemblers("circuit-assembler", circuit_count, 2, 1, suppliers)
    end

    for _, iron_count in ipairs({1, 4}) do
      for _, copper_count in ipairs({1, 5}) do
        for _, cable_count in ipairs({1, 3}) do
          for _, circuit_count in ipairs({1, 4}) do
            for _, iron_first in ipairs({true, false}) do
              local label = string.format("%d iron and %d copper furnaces, %d cable and %d circuit assemblers, %s first", iron_count, copper_count, cable_count, circuit_count, iron_first and "iron" or "cables")

              it("passes the validator when building " .. label, function()
                local entities = blocks.build(circuits(iron_count, copper_count, cable_count, circuit_count, iron_first), NAMES)

                assert.are.same({}, validator.validate(entities, catalog()))
              end)

              it("puts every item on a lane of its own where it is eaten when building " .. label, function()
                local entities = blocks.build(circuits(iron_count, copper_count, cable_count, circuit_count, iron_first), NAMES)

                local problems = tracer.problems(entities, {machines = machines, raw = raw, product = "electronic-circuit"})

                assert.are.same({}, problems)
              end)
            end
          end
        end
      end
    end

    -- An underground belt is iron plates and transport belts; a transport belt is an iron plate and a gear,
    -- and a gear is made from iron plates: the circuit shape twice over.
    local function underground_belts(plate_count, gear_count, belt_count, underground_count, belts_first)
      local gears = assemblers("gear-assembler", gear_count, 2, 1, {furnaces("iron-furnace", plate_count)})
      local belts = assemblers("belt-assembler", belt_count, 2, 2, {furnaces("iron-furnace", plate_count), gears})
      local plates = furnaces("iron-furnace", plate_count)
      local suppliers = belts_first and {belts, plates} or {plates, belts}
      return assemblers("underground-assembler", underground_count, 2, 1, suppliers)
    end

    for _, plate_count in ipairs({1, 3}) do
      for _, gear_count in ipairs({1, 2}) do
        for _, belt_count in ipairs({1, 2}) do
          for _, underground_count in ipairs({1, 3}) do
            for _, belts_first in ipairs({true, false}) do
              local label = string.format("%d furnaces per plate column, %d gear, %d belt and %d underground assemblers, %s first", plate_count, gear_count, belt_count, underground_count, belts_first and "belts" or "plates")

              it("passes the validator when building a block inside a block with " .. label, function()
                local entities = blocks.build(underground_belts(plate_count, gear_count, belt_count, underground_count, belts_first), NAMES)

                assert.are.same({}, validator.validate(entities, catalog()))
              end)

              it("puts every item on a lane of its own where it is eaten when building a block inside a block with " .. label, function()
                local entities = blocks.build(underground_belts(plate_count, gear_count, belt_count, underground_count, belts_first), NAMES)

                local problems = tracer.problems(entities, {machines = machines, raw = raw, product = "underground-belt"})

                assert.are.same({}, problems)
              end)
            end
          end
        end
      end
    end

    -- Wood and cables to poles, with the stages listed in either order. The wood's belt is the last of the raw
    -- belts, so it starts at (-1, 0): the cables' block is upper and its belt starts at (0, 0).
    local function poles(copper_count, cable_count, pole_count, wood_first)
      local cables = assemblers("cable-assembler", cable_count, 1, 2, {furnaces("copper-furnace", copper_count)})
      local wood = {raw_item = "wood"}
      return assemblers("pole-assembler", pole_count, 2, 1, wood_first and {wood, cables} or {cables, wood})
    end

    for _, copper_count in ipairs({1, 5}) do
      for _, cable_count in ipairs({1, 3}) do
        for _, pole_count in ipairs({1, 4}) do
          for _, wood_first in ipairs({true, false}) do
            local label = string.format("%d copper furnaces, %d cable and %d pole assemblers, wood %s", copper_count, cable_count, pole_count, wood_first and "first" or "second")

            it("passes the validator when building " .. label, function()
              local entities = blocks.build(poles(copper_count, cable_count, pole_count, wood_first), NAMES)

              assert.are.same({}, validator.validate(entities, catalog()))
            end)

            it("puts the wood and the cables on a lane of their own where they are eaten when building " .. label, function()
              local entities = blocks.build(poles(copper_count, cable_count, pole_count, wood_first), NAMES)

              local problems = tracer.problems(entities, {
                machines = machines, raw = raw, product = "small-electric-pole",
                supplies = {{x = -1, y = 0, item = "wood"}},
              })

              assert.are.same({}, problems)
            end)
          end
        end
      end
    end

    -- Gadgets from iron plates, cables, stone bricks and (in the third shape) gears, in three shapes: the recipe's
    -- ingredients split as 1 on belt a and 2 on belt b, as 2 and 1, and as 2 and 2; the suppliers listed in either order.
    local gadget_shapes = {
      {label = "1 on belt a and 2 on belt b", on_b = {cables = true, bricks = true}, eats = {"iron-plate", "copper-cable", "stone-brick"}},
      {label = "2 on belt a and 1 on belt b", on_b = {bricks = true}, eats = {"iron-plate", "copper-cable", "stone-brick"}},
      {label = "2 on each belt", on_b = {bricks = true, gears = true}, eats = {"iron-plate", "copper-cable", "stone-brick", "iron-gear-wheel"}},
    }

    local function gadgets(iron_count, brick_count, gadget_count, shape, forward)
      local suppliers = {
        iron = furnaces("iron-furnace", iron_count),
        cables = assemblers("cable-assembler", 1, 1, 2, {furnaces("copper-furnace", 2)}),
        bricks = furnaces("brick-furnace", brick_count),
        gears = assemblers("gear-assembler", 1, 2, 1, {furnaces("iron-furnace", 2)}),
      }
      local order = shape.on_b.gears and {"iron", "cables", "bricks", "gears"} or {"iron", "cables", "bricks"}
      local list = {}
      for index = 1, #order do
        local name = order[forward and index or #order + 1 - index]
        list[index] = shape.on_b[name] and on_belt_b(suppliers[name]) or suppliers[name]
      end
      return gadget_assembler(gadget_count, list)
    end

    -- The machines of the tracer, with the gadget assembler eating what the shape says.
    local function machines_eating(eats)
      local copy = {}
      for name, machine in pairs(machines) do
        copy[name] = machine
      end
      copy["gadget-assembler"] = {size = 3, eats = eats, makes = "gadget"}
      return copy
    end

    for _, shape in ipairs(gadget_shapes) do
      for _, iron_count in ipairs({1, 4}) do
        for _, brick_count in ipairs({1, 3}) do
          for _, gadget_count in ipairs({1, 3}) do
            for _, forward in ipairs({true, false}) do
              local label = string.format("%d iron and %d brick furnaces and %d gadget assemblers, %s, %s", iron_count, brick_count, gadget_count, shape.label, forward and "listed in order" or "listed backwards")

              it("passes the validator when building " .. label, function()
                local entities = blocks.build(gadgets(iron_count, brick_count, gadget_count, shape, forward), NAMES)

                assert.are.same({}, validator.validate(entities, catalog()))
              end)

              it("puts every item on a lane of its own where it is eaten when building " .. label, function()
                local entities = blocks.build(gadgets(iron_count, brick_count, gadget_count, shape, forward), NAMES)

                local problems = tracer.problems(entities, {machines = machines_eating(shape.eats), raw = raw, product = "gadget"})

                assert.are.same({}, problems)
              end)
            end
          end
        end
      end
    end

    -- A circuit block above a gear block, the counts chosen so that the columns of belts of the two line up for some of
    -- them: the belt between the furnaces and the assembler of the gear block runs north up to its first row, right
    -- under a belt of the circuit block.
    for _, iron_count in ipairs({1, 2, 3}) do
      for _, copper_count in ipairs({1, 2, 3}) do
        for _, gear_furnaces in ipairs({2, 3, 4}) do
          local label = string.format("%d iron and %d copper furnaces in the circuit block above %d in the gear block", iron_count, copper_count, gear_furnaces)

          local function stacked()
            local circuit = assemblers("circuit-assembler", 1, 2, 1, {
              furnaces("iron-furnace", iron_count),
              assemblers("cable-assembler", 1, 1, 2, {furnaces("copper-furnace", copper_count)}),
            })
            local gear = assemblers("gear-assembler", 1, 2, 1, {furnaces("iron-furnace", gear_furnaces)})
            return gadget_assembler(1, {circuit, gear, on_belt_b(furnaces("brick-furnace", 1))})
          end

          it("passes the validator when building " .. label, function()
            local entities = blocks.build(stacked(), NAMES)

            assert.are.same({}, validator.validate(entities, catalog()))
          end)

          it("keeps the items of the two blocks apart when building " .. label, function()
            local entities = blocks.build(stacked(), NAMES)

            local problems = tracer.problems(entities, {
              machines = machines_eating({"electronic-circuit", "iron-gear-wheel", "stone-brick"}), raw = raw, product = "gadget",
            })

            assert.are.same({}, problems)
          end)
        end
      end
    end

    -- A gadget assembler that is itself one of the suppliers of an outer one: the inner block has a second belt of its own.
    for _, iron_count in ipairs({1, 3}) do
      for _, outer_count in ipairs({1, 2}) do
        for _, inner_on_b in ipairs({true, false}) do
          local label = string.format("%d iron furnaces and %d outer assemblers, the inner gadgets on belt %s", iron_count, outer_count, inner_on_b and "b" or "a")

          local function nested()
            local inner = gadget_assembler(1, {
              furnaces("iron-furnace", 1),
              assemblers("cable-assembler", 1, 1, 2, {furnaces("copper-furnace", 1)}),
              on_belt_b(furnaces("brick-furnace", 1)),
            })
            local outer_suppliers = {furnaces("iron-furnace", iron_count), inner, on_belt_b(furnaces("brick-furnace", 2))}
            if inner_on_b then
              on_belt_b(inner)
              outer_suppliers[3] = furnaces("brick-furnace", 2)
              outer_suppliers[3].belt = nil
            end
            return gadget_assembler(outer_count, outer_suppliers, "outer-assembler")
          end

          it("passes the validator when building a gadget inside a gadget with " .. label, function()
            local entities = blocks.build(nested(), NAMES)

            assert.are.same({}, validator.validate(entities, catalog()))
          end)

          it("puts every item on a lane of its own where it is eaten when building a gadget inside a gadget with " .. label, function()
            local entities = blocks.build(nested(), NAMES)

            local problems = tracer.problems(entities, {machines = machines, raw = raw, product = "outer-gadget"})

            assert.are.same({}, problems)
          end)
        end
      end
    end

    it("puts a raw item alone on belt a, with the other two ingredients on belt b", function()
      -- Wood rides both lanes of belt a, whose head is the raw block in the corner: its belt starts at (0, 0).
      local machines_with_wood = machines_eating({"wood", "copper-cable", "stone-brick"})
      local suppliers = {
        {raw_item = "wood"},
        on_belt_b(assemblers("cable-assembler", 1, 1, 2, {furnaces("copper-furnace", 2)})),
        on_belt_b(furnaces("brick-furnace", 1)),
      }

      local entities = blocks.build(gadget_assembler(2, suppliers), NAMES)

      assert.are.same({}, validator.validate(entities, catalog()))
      assert.are.same({}, tracer.problems(entities, {
        machines = machines_with_wood, raw = raw, product = "gadget", supplies = {{x = 0, y = 0, item = "wood"}},
      }))
    end)

    it("wires a tree to the block below it from the poles at the bottom of the tree", function()
      -- Six furnaces in each plate column make the lower block of the transport belt tree 12 rows tall, so the
      -- poles nearest to the block below that tree are down there, not beside the tree's final column.
      local entities = blocks.build(underground_belts(6, 1, 1, 1, true), NAMES)

      assert.are.same({}, validator.validate(entities, catalog()))
    end)

    it("winds the output belt of the final column when each of its machines has two output inserters", function()
      local root = assemblers("circuit-assembler", 2, 2, 2, {furnaces("iron-furnace", 1), furnaces("copper-furnace", 1)})

      local entities = blocks.build(root, NAMES)

      local product_belts = #belt_rows(entities, 11) + #belt_rows(entities, 12) -- the inner and the outer column
      assert.are.equal(2 * 6 + 1, product_belts)
    end)

    -- A block that is itself a tree on both sides: two transport belt makers, each of plates and gears.
    local function two_trees(plate_count, belt_count)
      local function belt_maker(machine)
        local gears = assemblers("gear-assembler", 1, 2, 1, {furnaces("iron-furnace", plate_count)})
        return assemblers(machine, belt_count, 2, 2, {furnaces("iron-furnace", plate_count), gears})
      end
      return assemblers("double-assembler", 1, 2, 1, {belt_maker("belt-assembler"), belt_maker("other-belt-assembler")})
    end

    for _, plate_count in ipairs({1, 3}) do
      for _, belt_count in ipairs({1, 3}) do
        it("passes the validator when both blocks are trees, with " .. plate_count .. " furnaces per plate column and " .. belt_count .. " belt assemblers", function()
          local entities = blocks.build(two_trees(plate_count, belt_count), NAMES)

          assert.are.same({}, validator.validate(entities, catalog()))
        end)

        it("puts every item on a lane of its own where it is eaten when both blocks are trees, with " .. plate_count .. " furnaces per plate column and " .. belt_count .. " belt assemblers", function()
          local entities = blocks.build(two_trees(plate_count, belt_count), NAMES)

          local problems = tracer.problems(entities, {machines = machines, raw = raw, product = "double-belt"})

          assert.are.same({}, problems)
        end)
      end
    end

    it("lists the raw stages of a tree three levels deep from the top down", function()
      local root = underground_belts(1, 1, 1, 1, true)

      local _, raw_stages = blocks.build(root, NAMES)

      assert.are.equal(3, #raw_stages)
    end)
  end)
end)
