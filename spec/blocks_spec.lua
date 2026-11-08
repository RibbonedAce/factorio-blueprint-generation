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
    -- The first-listed furnace block is the upper one when the blocks are equally tall, so its belts
    -- stand one column east of the lower block's. Rows 0 and 1 are the upper block, row 2 the join row,
    -- rows 3 and 4 the lower block. Columns: upper block 1 (raw belt), 2 (inserters), 3-4 (furnace),
    -- 5 (inserters), 6 (product belt, which goes on as the assembler's input belt); lower block 0, 1, 2-3,
    -- 4, 5 (product belt, running north); the assembler's input inserters in 7, the machine in 8-10, its
    -- output inserters in 11 and its output belt in 12.
    --
    --      x: 0 1 2 3 4 5 6 7 8 9 10 11 12
    --  row 0:   v } F F } v
    --  row 1:     + F F + v
    --  row 2:           > v
    --  row 3:   v } F F } ^ v } A A A  }  v
    --  row 4:     + F F + ^ v } A A A  +  v
    local iron, copper = furnaces("iron-furnace", 1), furnaces("copper-furnace", 1)
    local root = assemblers("circuit-assembler", 1, 2, 1, {iron, copper})
    local entities, raw_stages = blocks.build(root, NAMES)

    it("lets the upper block's product belt go on south as the input belt of the final column", function()
      assert.are.same({0, 1, 2, 3, 4}, belt_rows(entities, 6)) -- down to the last input inserter, in row 4
      assert.are.same({south}, belt_directions(entities, 6))
    end)

    it("runs the lower block's product belt north, from its last row up to the join row", function()
      assert.are.same({2, 3, 4}, belt_rows(entities, 5)) -- the tile in the join row turns east
      assert.are.equal(north, entity_at(entities, NAMES.belt, 5, 4, 1).direction)
      assert.are.equal(north, entity_at(entities, NAMES.belt, 5, 3, 1).direction)
    end)

    it("turns the lower block's product belt east into the side of the input belt in the join row", function()
      local turn = assert(entity_at(entities, NAMES.belt, 5, 2, 1))

      assert.are.equal(east, turn.direction)
    end)

    it("puts the final column to the right of the lower block, starting below the join row", function()
      assert.is_not_nil(entity_at(entities, "circuit-assembler", 8, 3, 3))
    end)

    it("draws the final product belt along the final column", function()
      assert.are.same({3, 4, 5}, belt_rows(entities, 12))
    end)

    it("places the lower block below the join row", function()
      assert.is_not_nil(entity_at(entities, "copper-furnace", 2, 3, 2))
    end)

    it("places the upper block at the top, one column further east than the lower block", function()
      assert.is_not_nil(entity_at(entities, "iron-furnace", 3, 0, 2))
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
      -- 4 furnaces (8 rows), so the tree starts in row 9 and its first pole would be in row 13 without the line.
      local tree = assemblers("belt-assembler", 1, 2, 1, {furnaces("iron-furnace", 1), furnaces("copper-furnace", 1)})
      local root = assemblers("circuit-assembler", 1, 2, 1, {tree, furnaces("iron-furnace", 4)})

      local entities = blocks.build(root, NAMES)

      local head = assert(poles_at(entities, 11, 9)) -- the top row of the tree, in the column of the tree's output inserters
      assert.is_true(wired(assert(poles_at(entities, 11, 13)), head))
    end)

    it("adds no poles to the last block of the blueprint, which has no neighbours", function()
      -- The final column is 3 rows tall beside a lower block of 8 rows, which would leave a gap at the bottom of
      -- the column beside the product belt if the last block had a line.
      local cables = assemblers("cable-assembler", 1, 1, 2, {furnaces("copper-furnace", 4)})
      local root = assemblers("circuit-assembler", 1, 2, 1, {furnaces("iron-furnace", 1), cables})

      local entities = blocks.build(root, NAMES)

      assert.is_nil(poles_at(entities, 21, 17))
    end)
  end)

  describe("the belts of raw items, which all start at the top left", function()
    -- The small tree again: the upper block's belt of raw items starts at (1, 0), one column east of the corner,
    -- and the lower block's at (0, 3). Each gets a trail along the west side of the blueprint, the lower belt's
    -- one further west, so that no trail crosses another.
    local function small_tree()
      local root = assemblers("circuit-assembler", 1, 2, 1, {furnaces("iron-furnace", 1), furnaces("copper-furnace", 1)})
      return (blocks.build(root, NAMES))
    end

    it("runs the trail of the upper block's belt along the top row, east into the belt", function()
      local entities = small_tree()

      assert.are.same({0, 3}, belt_rows(entities, -1)) -- row 0 is this trail, which turns east at once; row 3 is the lower trail passing east
      assert.are.equal(east, entity_at(entities, NAMES.belt, -1, 0, 1).direction) -- in the top row, level with the top of the other belt
      assert.are.equal(east, entity_at(entities, NAMES.belt, 0, 0, 1).direction) -- the tile before the belt, which is in column 1
    end)

    it("runs the trail of a lower belt further west, down to its row, then east into the belt", function()
      local entities = small_tree()

      assert.are.same({0, 1, 2, 3}, belt_rows(entities, -2)) -- from the top row
      assert.are.equal(south, entity_at(entities, NAMES.belt, -2, 2, 1).direction)
      assert.are.equal(east, entity_at(entities, NAMES.belt, -2, 3, 1).direction)
      assert.are.equal(east, entity_at(entities, NAMES.belt, -1, 3, 1).direction) -- next to the belt in column 0
    end)

    it("gives no trail to a belt that already starts in the top left corner", function()
      -- The upper block is 4 furnaces and a cable assembler (8 rows), 11 columns wide: its belt starts at (0, 0).
      -- The lower block starts in row 9.
      local cables = assemblers("cable-assembler", 1, 1, 2, {furnaces("copper-furnace", 4)})
      local root = assemblers("circuit-assembler", 1, 2, 1, {cables, furnaces("iron-furnace", 1)})

      local entities = blocks.build(root, NAMES)

      assert.are.same({0, 1, 2, 3, 4, 5, 6, 7, 8, 9}, belt_rows(entities, -1)) -- only the lower belt's trail
      assert.are.same({}, belt_rows(entities, -2))
    end)

    it("gives a chain no trail, since its belt starts in the corner", function()
      local entities = blocks.build(assemblers("gear-assembler", 2, 2, 1, {furnaces("iron-furnace", 3)}), NAMES)

      assert.are.same({}, belt_rows(entities, -1))
    end)
  end)

  describe("a raw item that goes with a made one, on a belt of its own", function()
    -- A pole assembler eats wood and cables. The cables' block is one copper furnace and one cable assembler, with
    -- a belt of raw items at (0, 0); it is the upper block. The wood is a block of its own with no machines, below:
    -- one belt tile in the row under the join row, in the column where the lower block's product belt would run.
    local function poles(first_raw)
      local cables = assemblers("cable-assembler", 1, 1, 2, {furnaces("copper-furnace", 1)})
      local wood = {raw_item = "wood"}
      return assemblers("pole-assembler", 1, 2, 1, first_raw and {wood, cables} or {cables, wood})
    end

    -- Columns: -1 the wood's trail; 0 the copper's raw belt, 1 inserters, 2-3 the furnace, 4 inserters, 5 the
    -- cables' input belt, 6 inserters, 7-9 the cable assembler, 10 the wood tile (north) or the join (east),
    -- 11 the product belt of the cables, which goes on as the input belt of the poles, 12 inserters, 13-15 the pole assembler.
    -- Rows: 0-2 the cables' block, 3 the join row, 4 the wood tile and the top row of the poles.
    it("runs the raw item east along the bottom of the block above, then north, then east into the input belt", function()
      local entities = blocks.build(poles(false), NAMES)

      assert.are.same({3, 4}, belt_rows(entities, 10))
      assert.are.equal(east, entity_at(entities, NAMES.belt, 10, 3, 1).direction) -- the join row, into the side of the input belt in column 11
      assert.are.equal(north, entity_at(entities, NAMES.belt, 10, 4, 1).direction) -- the first tile of the raw item's belt
    end)

    it("brings the trail of the raw item down the west side and east along the row of its first tile", function()
      local entities = blocks.build(poles(false), NAMES)

      assert.are.same({0, 1, 2, 3, 4}, belt_rows(entities, -1))
      assert.are.equal(south, entity_at(entities, NAMES.belt, -1, 3, 1).direction)
      assert.are.equal(east, entity_at(entities, NAMES.belt, -1, 4, 1).direction)
      assert.are.equal(east, entity_at(entities, NAMES.belt, 9, 4, 1).direction) -- the tile before the first tile of the raw item's belt
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
      assert.is_not_nil(entity_at(entities, "copper-furnace", 3, 0, 2))
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
    }
    local raw = {["iron-furnace"] = true, ["copper-furnace"] = true}

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

    it("wires a tree to the block below it from the poles at the bottom of the tree", function()
      -- Six furnaces in each plate column make the lower block of the transport belt tree 12 rows tall, so the
      -- poles nearest to the block below that tree are down there, not beside the tree's final column.
      local entities = blocks.build(underground_belts(6, 1, 1, 1, true), NAMES)

      assert.are.same({}, validator.validate(entities, catalog()))
    end)

    it("winds the output belt of the final column when each of its machines has two output inserters", function()
      local root = assemblers("circuit-assembler", 2, 2, 2, {furnaces("iron-furnace", 1), furnaces("copper-furnace", 1)})

      local entities = blocks.build(root, NAMES)

      local product_belts = #belt_rows(entities, 12) + #belt_rows(entities, 13) -- the inner and the outer column
      assert.are.equal(2 * 6 + 1, product_belts)
    end)

    it("puts the lower block against the input belt when the upper block is wider", function()
      -- The upper block is a furnace column and a cable column: 4 furnaces are 8 rows and its product belt is in
      -- column 11. The lower block is one furnace column, 6 columns wide, so its product belt is in column 10 and
      -- its furnace in columns 7 and 8, from row 9 (row 8, below the upper block, is the join row).
      local cables = assemblers("cable-assembler", 1, 1, 2, {furnaces("copper-furnace", 4)})
      local root = assemblers("circuit-assembler", 1, 2, 1, {cables, furnaces("iron-furnace", 1)})

      local entities = blocks.build(root, NAMES)

      assert.is_not_nil(entity_at(entities, "iron-furnace", 7, 9, 2))
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
