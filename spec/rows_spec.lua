-- spec/rows_spec.lua
-- Recipes with several made ingredients, built as a row of columns (see the top of scripts/rows.lua).
-- Positions are TILES read off the diagrams in the small trees below (the top-left tile an
-- entity covers, y growing down; see scripts/grid.lua).
---@diagnostic disable: undefined-field  -- luassert's `assert` has fields (`assert.are`, `assert.is_nil`, ...) the editor cannot see

local builders = require("spec.support.builders")
local grid = require("scripts.grid")
local layout = require("scripts.layout")
local picture = require("spec.support.picture")
local rows = require("scripts.rows")
local tracer = require("spec.support.belt_tracer")
local validator = require("spec.support.blueprint_validator")

local NAMES = builders.NAMES
local north, east, south = defines.direction.north, defines.direction.east, defines.direction.south

-- The most tiles the underground belt spans in the design that brings in one belt of each material (the basic one's).
local UNDERGROUND_REACH = 5

-- The blueprint for `root` in the design that brings in one belt of each material, with a basic belt (450 items a
-- minute on a lane): its entities and the belts that come in, from the top down.
local function build_pure(root)
  return rows.build_pure(root, NAMES, {lane_items_per_minute = 450, underground_reach = UNDERGROUND_REACH})
end

-- The ore each furnace smelts, for the feed of the design that brings in one belt of each material.
local ORES = {["iron-furnace"] = "iron-ore", ["copper-furnace"] = "copper-ore", ["brick-furnace"] = "stone"}

-- What a column of `count` furnaces takes from the belts that come in: some ore on one lane and some coal on the other.
-- (`rows.build`, the original design, ignores it.)
local function furnace_feed(machine, count)
  return {items = {{name = ORES[machine], amount = 20 * count}, {name = "coal", amount = 2 * count}}}
end

-- A column of 2 x 2 furnaces, one inserter on each side, or of 3 x 3 assemblers.
local function furnaces(machine, count)
  return {
    machine_count = count, machine = machine, shape = {machine_size = 2, input_inserters = 1, output_inserters = 1},
    suppliers = {}, feed = furnace_feed(machine, count),
  }
end

-- Furnaces with an inserter on every tile of their input side, which leaves no tile for a pole there: the column
-- gets a row of poles above its first furnace, and its belts start one row lower.
local function crowded_furnaces(machine, count)
  return {
    machine_count = count, machine = machine, shape = {machine_size = 2, input_inserters = 2, output_inserters = 1},
    suppliers = {}, feed = furnace_feed(machine, count),
  }
end

-- The belt of wood that goes with made ingredients: a raw item that no furnace smelts.
local function wood_supplier(per_minute)
  return {raw_item = "wood", feed = {items = {{name = "wood", amount = per_minute or 30}}}}
end

local function assemblers(machine, count, input_inserters, output_inserters, suppliers)
  return {
    machine_count = count, machine = machine,
    shape = {machine_size = 3, input_inserters = input_inserters, output_inserters = output_inserters},
    suppliers = suppliers or {},
  }
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

-- The same column, said to ride belt b.
local function on_belt_b(stage)
  stage.belt = "b"
  return stage
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
  local found = {}
  for _, entity in ipairs(entities) do
    local tile = tile_of(entity, 1)
    if entity.name == NAMES.belt and tile.x == column then
      found[#found + 1] = tile.y
    end
  end
  table.sort(found)
  return found
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

-- The belts inside a box of tiles as "x,y direction", row by row from the west.
local function belts_in(entities, first_column, first_row, last_column, last_row)
  local found = {}
  for _, entity in ipairs(entities) do
    local tile = tile_of(entity, 1)
    if entity.name == NAMES.belt and tile.x >= first_column and tile.x <= last_column and tile.y >= first_row and tile.y <= last_row then
      found[#found + 1] = {x = tile.x, y = tile.y, text = tile.x .. "," .. tile.y .. " " .. entity.direction}
    end
  end
  table.sort(found, function(first, second)
    return first.y < second.y or (first.y == second.y and first.x < second.x)
  end)
  local texts = {}
  for index, belt in ipairs(found) do
    texts[index] = belt.text
  end
  return texts
end

-- Where the belt of a raw item that no furnace smelts (wood) starts: the west end of its row. (The belts of
-- raw items that furnaces smelt are found by the tracer itself, from the furnaces.)
local function supply_of(entities, raw_stages, item)
  for index, stage in ipairs(raw_stages) do
    if stage.raw_item == item then
      local row, west = index - 1, math.huge
      for _, entity in ipairs(entities) do
        local tile = tile_of(entity, 1)
        if entity.name == NAMES.belt and tile.y == row then
          west = math.min(west, tile.x)
        end
      end
      return {x = west, y = row, item = item}
    end
  end
end

describe("rows", function()
  describe("two chains of one furnace each and an assembler that eats what they make", function()
    -- The columns, from the west: the iron furnace (columns 0 to 5: raw belt, inserters, furnace, inserters, product
    -- belt), the copper furnace (6 to 11) and the assembler (belt a in 12, inserters 13, machine 14-16, output
    -- inserters 17, product belt 18). The copper furnace has the top row of raw items, row 0, because its belt comes
    -- down further east; each furnace starts right under its own belt. Belt a runs north. The copper plates join it
    -- from the west in row 3, under the assembler; the iron plates run along row 4 and join it through the gadget
    -- (rows 4 and 5). (I the iron furnace, K the copper furnace, A the assembler, } an inserter, + a pole.)
    --
    --      10123456789012345678
    --   0 |>>>>>>>v.....^}AAA}v|
    --   1 |>v.....v}KK}v^}AAA+v|
    --   2 |.v}II}v.+KK+v^+AAA.v|
    --   3 |..+II+v.....>^......|
    --   4 |......v>>>>>>^......|
    --   5 |......>>^...........|
    local iron, copper = furnaces("iron-furnace", 1), furnaces("copper-furnace", 1)
    local root = assemblers("circuit-assembler", 1, 2, 1, {iron, copper})
    local entities, raw_stages = rows.build(root, NAMES)

    it("stands the columns side by side, the ones that make the ingredients before the one that eats them", function()
      assert.is_not_nil(entity_at(entities, "iron-furnace", 2, 2, 2))
      assert.is_not_nil(entity_at(entities, "copper-furnace", 8, 1, 2))
      assert.is_not_nil(entity_at(entities, "circuit-assembler", 14, 0, 3))
    end)

    it("starts every chain right under its own belt of raw items, so the columns do not start in one row", function()
      assert.are.equal(1, entity_at(entities, "copper-furnace", 8, 1, 2).position.y - 1) -- row 0 is its belt of raw items
      assert.are.equal(2, entity_at(entities, "iron-furnace", 2, 2, 2).position.y - 1) -- row 1 is its belt
    end)

    it("brings the belts of raw items in from the west edge, each along a row of its own", function()
      assert.are.same({"-1,0 east", "0,0 east", "1,0 east", "2,0 east", "3,0 east", "4,0 east", "5,0 east", "6,0 south"}, belts_in(entities, -1, 0, 6, 0))
      assert.are.same({"-1,1 east", "0,1 south"}, belts_in(entities, -1, 1, 0, 1))
    end)

    it("lists the stages fed raw items from the top row down, the one whose belt comes down furthest east first", function()
      assert.are.equal(copper, raw_stages[1])
      assert.are.equal(iron, raw_stages[2])
    end)

    it("runs belt a north along the final column, from the arc of the first product to the top row", function()
      assert.are.same({0, 1, 2, 3, 4}, belt_rows(entities, 12))
      assert.are.same({north}, belt_directions(entities, 12))
    end)

    it("turns the second product east into the side of belt a, in the row under the final column", function()
      assert.are.equal(east, entity_at(entities, NAMES.belt, 11, 3, 1).direction)
    end)

    it("sends the first product through the lane gadget, a stub behind the tile its belt side-loads", function()
      local gadget = belts_in(entities, 5, 4, 7, 5)

      assert.are.same({"5,4 south", "6,4 east", "7,4 east", "5,5 east", "6,5 east", "7,5 north"}, gadget)
    end)

    it("runs the first product along the row under the final column and into belt a from the west", function()
      assert.are.same({"6,4 east", "7,4 east", "8,4 east", "9,4 east", "10,4 east", "11,4 east"}, belts_in(entities, 6, 4, 11, 4))
      assert.are.equal(north, entity_at(entities, NAMES.belt, 12, 4, 1).direction)
    end)

    it("draws the product belt of the root along the final column", function()
      assert.are.same({0, 1, 2}, belt_rows(entities, 18))
    end)

    it("numbers every entity once", function()
      for index, entity in ipairs(entities) do
        assert.are.equal(index, entity.entity_number)
      end
    end)
  end)

  describe("a chain whose first column has a row of poles above its furnaces", function()
    -- The iron chain's belt of raw items comes in along row 1; the chain starts in row 2 with the row of poles, and its
    -- own belt starts in row 3, so the belt of raw items needs a tile in row 2 to reach it (columns -1 to 5):
    --
    --      10123456
    --   1 |>v.....v
    --   2 |.v+..+..
    --   3 |.v}II.v.
    --   4 |.v}II}v>
    it("runs the belt of raw items down through the row of poles into the belt of the chain", function()
      local root = assemblers("circuit-assembler", 1, 2, 1, {crowded_furnaces("iron-furnace", 1), furnaces("copper-furnace", 1)})

      local entities = rows.build(root, NAMES)

      assert.are.same({0, 1, 2, 3, 4}, belt_rows(entities, 0)) -- row 0 is the belt of the copper furnace, passing over
      assert.are.equal(south, entity_at(entities, NAMES.belt, 0, 2, 1).direction) -- the tile in the row of poles
    end)
  end)

  describe("two chains of which the first is much taller", function()
    -- Four furnaces and a cable assembler make the cables, which are first in the recipe, so the gadget is theirs
    -- and they stand west of the iron furnace. The arc of the cables runs deeper than the arc of the iron plates, which
    -- they would cross otherwise: the iron plates turn into belt a in row 3, the cables in row 4 (rows 4 and 5).
    --
    --      10123456789012345678901234
    --   0 |>>>>>>>>>>>>>v.....^}AAA}v|
    --   1 |>v...........v}II}v^}AAA+v|
    --   2 |.v}KK}^}CCC}v.+II+v^+AAA.v|
    --   3 |.v+KK+^+CCC}v.....>^......|
    --   4 |.v.KK.^.CCC+v>>>>>>^......|
    --   5 |.v}KK}^.....>>^...........|
    --   (the furnaces of the cables go down to row 9)
    local cables = assemblers("cable-assembler", 1, 1, 2, {furnaces("copper-furnace", 4)})
    local root = assemblers("circuit-assembler", 1, 2, 1, {cables, furnaces("iron-furnace", 1)})
    local entities = rows.build(root, NAMES)

    it("runs the arc of the first product, which has the gadget, deeper than the arc of the second", function()
      assert.are.equal(east, entity_at(entities, NAMES.belt, 17, 3, 1).direction) -- the iron plates, into belt a
      assert.are.same({"12,4 east", "13,4 east"}, belts_in(entities, 12, 4, 13, 4)) -- the stub and the tile the cables side-load
      assert.are.equal(north, entity_at(entities, NAMES.belt, 13, 5, 1).direction)
    end)

    it("starts the final column in row 0, where no belt of raw items passes over it", function()
      assert.is_not_nil(entity_at(entities, "circuit-assembler", 20, 0, 3))
    end)
  end)

  describe("a column that eats what other columns make, inside another", function()
    -- A circuit (columns 12 to 18) is one of the two ingredients of an outer assembler, with a brick furnace beside
    -- it. The belt of raw items of the bricks comes down in column 19 and passes over the circuit's column in row 0,
    -- so the circuit's assembler starts in row 2, one row lower than that: belt a ends in row 2, and row 1 is free,
    -- so its end does not point into the belt of raw items. (B the brick furnace, O the outer assembler.)
    --
    --      101234567890123456789012345678901
    --   0 |>>>>>>>>>>>>>>>>>>>>v.....^}OOO}v|
    --   1 |>>>>>>>v............v}BB}v^}OOO+v|
    --   2 |>v.....v}CC}v^}AAA}v.+BB+v^+OOO.v|
    --   3 |.v}II}v.+CC+v^}AAA+v.....>^......|
    --   4 |..+II+v.....v^+AAA.v>>>>>>^......|
    --   5 |......v.....>^.....>>^...........|
    --   6 |......v>>>>>>^...................|
    --   7 |......>>^........................|
    local inner = assemblers("circuit-assembler", 1, 2, 1, {furnaces("iron-furnace", 1), furnaces("copper-furnace", 1)})
    local root = assemblers("outer-assembler", 1, 2, 1, {inner, furnaces("brick-furnace", 1)})
    local entities = rows.build(root, NAMES)

    it("starts it under the belts of raw items that pass over it, and one row lower", function()
      assert.is_not_nil(entity_at(entities, "circuit-assembler", 14, 2, 3))
    end)

    it("does not let belt a end with its tail pointing into the side of a belt of raw items", function()
      assert.are.equal(north, entity_at(entities, NAMES.belt, 12, 2, 1).direction)
      assert.is_nil(entity_at(entities, NAMES.belt, 12, 1, 1))
    end)

    it("starts a chain right under its own belt of raw items, whatever passes over the columns beside it", function()
      assert.is_not_nil(entity_at(entities, "copper-furnace", 8, 2, 2)) -- its belt comes in along row 1
    end)

    it("runs the arc of a column deeper than the arcs of the columns east of it", function()
      assert.are.equal(east, entity_at(entities, NAMES.belt, 24, 3, 1).direction) -- the bricks, into belt a
      assert.are.equal(east, entity_at(entities, NAMES.belt, 24, 4, 1).direction) -- the circuit, under them
    end)
  end)

  describe("a raw item that goes with a made one", function()
    -- Wood is first in the recipe, so its column is the first, two wide: the belt in column 1 and a spare column 0
    -- for the gadget. (The copper furnace's column starts in column 2.) Its belt comes in along row 1, under the
    -- belt of the copper furnace, and is its own arc: down column 1, through the gadget (rows 4 and 5) and along
    -- row 4 into belt a. The cables join belt a from the west in row 3. (P the pole assembler, C the cable assembler.)
    --
    --      012345678901234567890
    --   0 |>>v...........^}PPP}v|
    --   1 |>vv}KK}v}CCC}v^}PPP+v|
    --   2 |.v.+KK+.+CCC}v^+PPP.v|
    --   3 |.v.......CCC+>^......|
    --   4 |.v>>>>>>>>>>>>^......|
    --   5 |.>>^.................|
    local wood = {raw_item = "wood"}
    local copper = furnaces("copper-furnace", 1)
    local cables = assemblers("cable-assembler", 1, 1, 2, {copper})
    local root = assemblers("pole-assembler", 1, 2, 1, {wood, cables})
    local entities, raw_stages = rows.build(root, NAMES)

    it("brings the belt of the raw item in along its own row, below the belt of the copper furnace", function()
      assert.are.same({"0,1 east", "1,1 south"}, belts_in(entities, 0, 1, 1, 1))
      assert.are.equal(copper, raw_stages[1])
      assert.are.equal(wood, raw_stages[2])
    end)

    it("runs the raw item down its column and through the gadget into belt a", function()
      assert.are.same({0, 1, 2, 3, 4, 5}, belt_rows(entities, 1)) -- row 0 is the belt of the copper furnace, passing over
      assert.are.same({"1,5 east", "2,5 east", "3,5 north"}, belts_in(entities, 1, 5, 3, 5))
      assert.are.equal(north, entity_at(entities, NAMES.belt, 14, 4, 1).direction)
    end)

    it("builds no machine for the raw item", function()
      local machines = 0
      for _, entity in ipairs(entities) do
        machines = machines + ((entity.name == "copper-furnace" or entity.name == "cable-assembler" or entity.name == "pole-assembler") and 1 or 0)
      end
      assert.are.equal(3, machines)
    end)

    it("starts the next column after the two columns of the raw item", function()
      assert.is_not_nil(entity_at(entities, "copper-furnace", 4, 1, 2))
    end)
  end)

  describe("three ingredients, some of them on a second input belt", function()
    -- Iron plates are alone on belt a. The cables and the bricks share belt b, one column west of belt a (column 24
    -- and 25), which the long-handed inserters of the final column (G, in column 26) reach over belt a. The belts of
    -- belt a's ingredients come first, then belt b's, whatever the recipe's order is. The cables are the head of belt b
    -- and go through the gadget (rows 7 and 8); the bricks join belt b from the west in row 6; the iron plates, alone
    -- on belt a, run under everything in row 9 without one. (B the brick furnace, ] a long-handed inserter.)
    --
    --      101234567890123456789012345678901
    --   0 |>>>>>>>>>>>>>>>>>>>v......^}GGG}v|
    --   1 |>>>>>>>v...........v}BB}v^^]GGG+v|
    --   2 |>v.....v}CC}v}CCC}v.+BB+v^^+GGG.v|
    --   3 |.v}II}v.+CC+.+CCC}v.....v^^+GGG.v|
    --   4 |..+II+v.......CCC+v.....v^^]GGG+v|
    --   5 |......v...........v.....v^^}GGG}v|
    --   6 |......v...........v.....>^^......|
    --   7 |......v...........v>>>>>>^^......|
    --   8 |......v...........>>^.....^......|
    --   9 |......>>>>>>>>>>>>>>>>>>>>^......|
    local iron = furnaces("iron-furnace", 1)
    local cables = on_belt_b(assemblers("cable-assembler", 1, 1, 2, {furnaces("copper-furnace", 1)}))
    local bricks = on_belt_b(furnaces("brick-furnace", 1))

    describe("one on belt a and two on belt b", function()
      local entities = rows.build(gadget_assembler(2, {iron, cables, bricks}), NAMES)

      it("runs belt a north from the arc of its head to the top row, and belt b north from there to the first long-handed inserter", function()
        assert.are.same({0, 1, 2, 3, 4, 5, 6, 7, 8, 9}, belt_rows(entities, 25))
        assert.are.same({1, 2, 3, 4, 5, 6, 7, 9}, belt_rows(entities, 24)) -- row 9 is the arc of the iron plates, under belt b
        assert.are.same({north}, belt_directions(entities, 25))
      end)

      it("lets the long-handed inserters of the final column reach belt b over belt a", function()
        assert.is_not_nil(entity_at(entities, NAMES.long_inserter, 26, 1, 1)) -- the first machine's plain inserter is in row 0, its long-handed one under it
        assert.is_not_nil(entity_at(entities, NAMES.long_inserter, 26, 4, 1)) -- the second machine's, in its bottom rows 4 and 5, are long then plain
      end)

      it("turns the head of belt b through the gadget and the second product of belt b in from the west", function()
        assert.are.same({"17,8 east", "18,8 east", "19,8 north"}, belts_in(entities, 17, 8, 19, 8))
        assert.are.equal(east, entity_at(entities, NAMES.belt, 23, 7, 1).direction) -- the cables, into the head of belt b
        assert.are.equal(east, entity_at(entities, NAMES.belt, 23, 6, 1).direction) -- the bricks, into the side of belt b
      end)

      it("gives a product that has its belt to itself no gadget, and runs it under the arcs of belt b", function()
        assert.are.equal(east, entity_at(entities, NAMES.belt, 5, 9, 1).direction)
        assert.is_nil(entity_at(entities, NAMES.belt, 5, 10, 1))
        assert.are.equal(east, entity_at(entities, NAMES.belt, 24, 9, 1).direction)
      end)

      it("stands the final column after belt a, with belt b in the column west of it", function()
        assert.is_not_nil(entity_at(entities, "gadget-assembler", 27, 0, 3))
      end)
    end)

    it("stands the columns of belt a before those of belt b whatever order the recipe lists them in", function()
      local first, second = furnaces("iron-furnace", 1), on_belt_b(furnaces("brick-furnace", 1))

      local _, raw_stages = rows.build(gadget_assembler(1, {second, first}), NAMES)

      assert.are.equal(second, raw_stages[1]) -- the column furthest east has the top row: belt b's, last in the row
      assert.are.equal(first, raw_stages[2])
    end)
  end)

  describe("the recipe of the machines", function()
    it("sets the recipe of the machines of every column, and none on the furnaces", function()
      local cables = assemblers("cable-assembler", 1, 1, 2, {furnaces("copper-furnace", 1)})
      cables.recipe = "copper-cable"
      local root = assemblers("circuit-assembler", 1, 2, 1, {furnaces("iron-furnace", 1), cables})
      root.recipe = "electronic-circuit"

      local entities = rows.build(root, NAMES)

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

  describe("a stage with no more than one made ingredient at each step", function()
    it("builds the same entities as a chain of columns", function()
      local furnace_column = furnaces("stone-furnace", 7)
      local assembler_column = assemblers("assembling-machine-1", 2, 2, 2, {furnace_column})

      local entities, raw_stages = rows.build(assembler_column, NAMES)

      local expected = layout.build_chain({furnace_column, assembler_column}, NAMES)
      assert.are.same(expected, entities)
      assert.are.same({furnace_column}, raw_stages)
    end)

    it("builds a stage fed raw items on its own", function()
      local column = furnaces("stone-furnace", 3)

      local entities, raw_stages = rows.build(column, NAMES)

      assert.are.same(layout.build_chain({column}, NAMES), entities)
      assert.are.same({column}, raw_stages)
    end)

    it("refuses a chain that starts from a stage with two made ingredients", function()
      local fork = assemblers("circuit-assembler", 1, 2, 1, {furnaces("iron-furnace", 1), furnaces("copper-furnace", 1)})
      local above_the_fork = assemblers("box-assembler", 1, 1, 1, {fork})

      assert.has_error(function() rows.build(above_the_fork, NAMES) end)
    end)
  end)

  describe("the design that brings in one belt of each material", function()
    -- Every chain and every raw column is fed by a belt that comes down from a trunk along the top (see scripts/inputs.lua),
    -- so the columns start under that band, from column 4 + 4 for each bus. The pictures draw the furnaces as i (iron)
    -- and c (copper), the cable assemblers as O, the circuit assemblers as E and the pole assemblers as P.
    local GLYPHS = {
      ["iron-furnace"] = {size = 2, glyph = "i"}, ["copper-furnace"] = {size = 2, glyph = "c"},
      ["cable-assembler"] = {size = 3, glyph = "O"}, ["circuit-assembler"] = {size = 3, glyph = "E"},
      ["pole-assembler"] = {size = 3, glyph = "P"}, ["steel-furnace"] = {size = 2, glyph = "s"}, ["chest-assembler"] = {size = 3, glyph = "T"},
    }

    local function drawn(entities, first_column, first_row, last_column, last_row)
      return picture.draw(entities, GLYPHS, first_column, first_row, last_column, last_row)
    end

    describe("a single chain", function()
      -- Two iron furnaces. The ore and the coal come in along rows 0 and 2, meet in the mixer in column 1 and ride
      -- the trunk in row 1 to column 4, where the belt of raw items of the chain starts (x from 0).
      --
      --      0123456789
      --   0 |>v........|
      --   1 |.>>>v.....|
      --   2 |>^..v.....|
      --   3 |....v}ii}v|
      --   4 |....v+ii+v|
      --   5 |....v.ii.v|
      --   6 |....v}ii}v|
      local entities, inputs = build_pure(furnaces("iron-furnace", 2))

      it("brings the ore and the coal to the chain through a trunk, which a single chain gets too", function()
        assert.are.same({
          ">v........",
          ".>>>v.....",
          ">^..v.....",
          "....v}ii}v",
          "....v+ii+v",
          "....v.ii.v",
          "....v}ii}v",
        }, drawn(entities, 0, 0, 9, 6))
      end)

      it("brings in the ore and the coal from the west edge, each along the row of its feeder", function()
        assert.are.same({{x = 0, y = 0, item = "iron-ore"}, {x = 0, y = 2, item = "coal"}}, inputs)
      end)

      it("numbers every entity once", function()
        for index, entity in ipairs(entities) do
          assert.are.equal(index, entity.entity_number)
        end
      end)
    end)

    describe("a chain whose first column has a row of poles above its furnaces", function()
      -- The belt of the chain starts one row lower than the column (its first furnace has an inserter on both of its input
      -- tiles, so the poles stand above it), and the belt that comes down from the trunk ends in the row of the poles,
      -- which is the first row of the column.
      --
      --      0123456789
      --   0 |>v........|
      --   1 |.>>>v.....|
      --   2 |>^..v+..+.|
      --   3 |....v}ii}v|
      --   4 |....v}ii.v|
      local entities = build_pure(crowded_furnaces("iron-furnace", 1))

      it("starts the column in the row where the belt from the trunk ends, so that the belt of the chain follows it", function()
        assert.are.same({
          ">v........",
          ".>>>v.....",
          ">^..v+..+.",
          "....v}ii}v",
          "....v}ii.v",
        }, drawn(entities, 0, 0, 9, 4))
      end)
    end)

    describe("iron plates and cables to circuits", function()
      -- The coal feeds both trunks, so it is a bus (column 2); the copper trunk, whose chain is further east, is on top.
      -- Each chain starts right under the last tile of the belt that comes down to it, and the final column, which no
      -- trunk passes over, in the top row. The iron plates reach belt a (column 26) through the lane gadget (rows 9, 10).
      --
      --      012345678901234567890123456789012
      --   0 |>>v.......................^}EEE}v|
      --   1 |..v.......................^}EEE+v|
      --   2 |>(v.)v....................^+EEE.v|
      --   3 |..SS.>>>>>>>>>v...........^......|
      --   4 |..v>>^........v...........^......|
      --   5 |>(v.)v........v}cc}v}OOO}v^......|
      --   6 |..v..>>>v......+cc+.+OOO}v^......|
      --   7 |..>>>^..v............OOO+>^......|
      --   8 |........v}ii}v............^......|
      --   9 |.........+ii+v>>>>>>>>>>>>^......|
      --  10 |.............>>^.................|
      local iron = furnaces("iron-furnace", 1)
      local cables = assemblers("cable-assembler", 1, 1, 2, {furnaces("copper-furnace", 1)})
      local entities, inputs = build_pure(assemblers("circuit-assembler", 1, 2, 1, {iron, cables}))

      it("draws the band above the chains", function()
        assert.are.same({
          ">>v.............",
          "..v.............",
          ">(v.)v..........",
          "..SS.>>>>>>>>>v.",
          "..v>>^........v.",
          ">(v.)v........v}",
          "..v..>>>v......+",
          "..>>>^..v.......",
        }, drawn(entities, 0, 0, 15, 7))
      end)

      it("stands the columns side by side after the band, the iron furnace first", function()
        assert.is_not_nil(entity_at(entities, "iron-furnace", 10, 8, 2))
        assert.is_not_nil(entity_at(entities, "copper-furnace", 16, 5, 2))
        assert.is_not_nil(entity_at(entities, "cable-assembler", 21, 5, 3))
        assert.is_not_nil(entity_at(entities, "circuit-assembler", 28, 0, 3))
      end)

      it("brings in the coal, the copper ore and the iron ore from the top down", function()
        assert.are.same({
          {x = 0, y = 0, item = "coal"},
          {x = 0, y = 2, item = "copper-ore"},
          {x = 0, y = 5, item = "iron-ore"},
        }, inputs)
      end)

      it("numbers every entity once", function()
        for index, entity in ipairs(entities) do
          assert.are.equal(index, entity.entity_number)
        end
      end)
    end)

    describe("wood next to cables, wood first", function()
      -- Wood is a trunk of its own with one item (row 4, under the copper trunk in row 1): no mixer, the belt that
      -- comes in at the west edge runs straight to column 5, where the raw column of the wood goes down.
      --
      --      0123456
      --   0 |>v.....
      --   1 |.>>>>>v
      --   2 |>^....v
      --   3 |......v
      --   4 |>>>>>v.
      local copper = furnaces("copper-furnace", 1)
      local cables = assemblers("cable-assembler", 1, 1, 2, {copper})
      local entities, inputs = build_pure(assemblers("pole-assembler", 1, 2, 1, {wood_supplier(), cables}))

      it("runs the belt of wood straight to its column, with no mixer", function()
        assert.are.same({
          ">v.....",
          ".>>>>>v",
          ">^....v",
          "......v",
          ">>>>>v.",
        }, drawn(entities, 0, 0, 6, 4))
      end)

      it("brings the wood in along the row of its trunk", function()
        assert.are.same({
          {x = 0, y = 0, item = "copper-ore"},
          {x = 0, y = 2, item = "coal"},
          {x = 0, y = 4, item = "wood"},
        }, inputs)
      end)
    end)

    describe("a final column shorter than the chains that hang under the band", function()
      -- The pole assembler is 3 rows tall and the cables chain hangs from its trunk, so the nearest poles of the
      -- two are further apart than a wire reaches. A pole on a free tile between them, (19, 4), wires them.
      local cables = assemblers("cable-assembler", 1, 1, 2, {furnaces("copper-furnace", 1)})
      local entities = build_pure(assemblers("pole-assembler", 1, 2, 1, {cables, wood_supplier()}))
      local bridge = entities[#entities]

      it("adds a pole after the other entities, on a free tile between the columns", function()
        assert.are.same({NAMES.pole, 19, 4}, {bridge.name, tile_of(bridge, 1).x, tile_of(bridge, 1).y})
      end)

      it("powers every machine", function()
        local catalog = builders.a_catalog{pole_supply_radius = 2.5, pole_wire_reach = 7.5}
        catalog["cable-assembler"] = {kind = "machine", width = 3, height = 3, needs_power = true}
        catalog["pole-assembler"] = {kind = "machine", width = 3, height = 3, needs_power = true}
        catalog["copper-furnace"] = {kind = "machine", width = 2, height = 2, needs_power = false}

        assert.are.same({}, validator.validate(entities, catalog))
      end)
    end)

    describe("a furnace that eats the plates another makes and burns fuel", function()
      -- Steel chests: iron furnaces (i) make plates, steel furnaces (s) smelt them, a chest assembler (T) eats the steel.
      -- The coal feeds the iron furnaces through their trunk and the steel furnaces through a trunk of its own (row 3): it
      -- comes down column 12, beside the output inserters of the iron furnaces, turns east in row 7 into the tile above the
      -- head of the belt between the two columns (column 13) and side-loads it, with a stub behind that tile (row 6).
      --
      --      11 12 13 14   (columns)
      --   6 |.  v  v  . |
      --   7 |.  >  v  . |
      --   8 |i  }  v  } |
      local steel_furnace = {
        machine_count = 1, machine = "steel-furnace", shape = {machine_size = 2, input_inserters = 1, output_inserters = 1},
        suppliers = {furnaces("iron-furnace", 1)}, fuel_feed = {items = {{name = "coal", amount = 2}}},
      }
      local entities, inputs = build_pure(assemblers("chest-assembler", 1, 1, 1, {steel_furnace}))

      it("brings the fuel down beside the iron furnaces and side-loads the head of the belt to the steel furnaces", function()
        assert.are.same({".vv.", ".>v.", "i}v}"}, drawn(entities, 11, 6, 14, 8))
      end)

      it("runs the belt between the iron furnaces and the steel furnaces south from its head", function()
        assert.are.equal(south, entity_at(entities, NAMES.belt, 13, 8, 1).direction)
      end)

      it("brings in the coal and the iron ore, the coal for both kinds of furnace on one belt", function()
        assert.are.same({{x = 0, y = 0, item = "coal"}, {x = 0, y = 5, item = "iron-ore"}}, inputs)
      end)
    end)

    describe("more iron ore than one belt carries", function()
      -- Three columns of 22 furnaces take 440 ore a minute each. A trunk carries a lane of ore, 450 a minute, so each column
      -- gets a trunk of its own; a belt that comes in carries two lanes, 900, so one belt of iron ore feeds two of the
      -- trunks and the third has a belt of its own. The coal feeds all three.
      local entities, inputs = build_pure(assemblers("underground-assembler", 1, 2, 1, {
        furnaces("iron-furnace", 22),
        assemblers("belt-assembler", 1, 2, 2, {furnaces("iron-furnace", 22), assemblers("gear-assembler", 1, 2, 1, {furnaces("iron-furnace", 22)})}),
      }))

      local function items_of(supplies)
        local items = {}
        for index, supply in ipairs(supplies) do
          items[index] = supply.item
        end
        return items
      end

      it("brings in a second belt of iron ore", function()
        assert.are.same({"coal", "iron-ore", "iron-ore"}, items_of(inputs))
      end)

      it("numbers every entity once", function()
        for index, entity in ipairs(entities) do
          assert.are.equal(index, entity.entity_number)
        end
      end)
    end)
  end)

  describe("the width of the blueprint", function()
    -- The point of the layout: the recipe fixes the width, and the rate only makes the columns taller.
    local function columns_spanned(entities)
      local first, last = math.huge, -math.huge
      for _, entity in ipairs(entities) do
        first, last = math.min(first, entity.position.x), math.max(last, entity.position.x)
      end
      return first, last
    end

    local function circuits(iron_count, copper_count, cable_count, circuit_count)
      local cables = assemblers("cable-assembler", cable_count, 1, 2, {furnaces("copper-furnace", copper_count)})
      return assemblers("circuit-assembler", circuit_count, 2, 1, {furnaces("iron-furnace", iron_count), cables})
    end

    it("stays the same when the rate asks for more machines in every column", function()
      local small = rows.build(circuits(1, 1, 1, 1), NAMES)
      local large = rows.build(circuits(6, 8, 3, 4), NAMES)

      local small_first, small_last = columns_spanned(small)
      local large_first, large_last = columns_spanned(large)
      assert.are.same({small_first, small_last}, {large_first, large_last})
    end)

    it("gets taller when the rate asks for more machines", function()
      local small = rows.build(circuits(1, 1, 1, 1), NAMES)
      local large = rows.build(circuits(6, 8, 3, 4), NAMES)

      local function lowest(entities)
        local row = -math.huge
        for _, entity in ipairs(entities) do
          row = math.max(row, entity.position.y)
        end
        return row
      end
      assert.is_true(lowest(large) > lowest(small))
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
      ["steel-furnace"] = {size = 2, eats = {"iron-plate", "coal"}, makes = "steel-plate"},
      ["chest-assembler"] = {size = 3, eats = {"steel-plate"}, makes = "steel-chest"},
      ["armor-assembler"] = {size = 3, eats = {"copper-plate", "steel-plate"}, makes = "heavy-armor"},
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

    -- What the belt of raw items of each furnace holds in the design that brings in one belt of each material: the ore
    -- on one lane and the fuel on the other.
    local raw_lanes = {
      ["iron-furnace"] = {"iron-ore", "coal"}, ["copper-furnace"] = {"copper-ore", "coal"}, ["brick-furnace"] = {"stone", "coal"},
    }
    -- The two ways to bring in the raw items, as every tree in this section is built and checked in each. `build` gives
    -- the entities and what the tracer needs to know about the belts of raw items (the stages fed raw items for the
    -- original design, the belts that come in for the other); `lanes` turns that into options of the tracer.
    local designs = {
      {
        suffix = "",
        build = function(root) return rows.build(root, NAMES) end,
        lanes = function(entities, raw_stages) return {supplies = {supply_of(entities, raw_stages, "wood")}} end,
      },
      {
        suffix = ", with one belt of each material",
        pure = true,
        build = build_pure,
        lanes = function(_, supplies) return {supplies = supplies, raw_lanes = raw_lanes, underground_reach = UNDERGROUND_REACH} end,
      },
    }

    -- The options of the tracer for a blueprint built in `design`: `base` and what the design adds to it.
    local function options_for(design, entities, second, base)
      for key, value in pairs(design.lanes(entities, second)) do
        base[key] = value
      end
      return base
    end

    -- Adds the two specs every tree gets in each design: the validator finds nothing wrong, and the tracer finds
    -- every item on a lane of its own where it is eaten.
    ---@param subject string  what is built, as in "when building <subject>"
    ---@param tree fun(): table  makes the tree
    ---@param product string  what the final column makes
    ---@param tracer_machines? table  what the tracer is told the machines eat and make; default `machines`
    ---@param eaten? string  what the second spec says is on a lane of its own, if not "every item"
    ---@param only_pure? boolean  for a tree that only the design with one belt of each material can build
    local function it_builds_soundly(subject, tree, product, tracer_machines, eaten, only_pure)
      for _, design in ipairs(designs) do
        if design.pure or not only_pure then
          it("passes the validator when building " .. subject .. design.suffix, function()
            local entities = design.build(tree())

            assert.are.same({}, validator.validate(entities, catalog()))
          end)

          it("puts " .. (eaten or "every item on a lane of its own where it is eaten") .. " when building " .. subject .. design.suffix, function()
            local entities, second = design.build(tree())

            assert.are.same({}, tracer.problems(entities, options_for(design, entities, second, {
              machines = tracer_machines or machines, raw = raw, product = product,
            })))
          end)
        end
      end
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

              it_builds_soundly(label, function() return circuits(iron_count, copper_count, cable_count, circuit_count, iron_first) end, "electronic-circuit")
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

              it_builds_soundly("a column inside a column with " .. label, function() return underground_belts(plate_count, gear_count, belt_count, underground_count, belts_first) end, "underground-belt")
            end
          end
        end
      end
    end

    -- Wood and cables to poles, with the stages listed in either order.
    local function poles(copper_count, cable_count, pole_count, wood_first)
      local cables = assemblers("cable-assembler", cable_count, 1, 2, {furnaces("copper-furnace", copper_count)})
      local wood = wood_supplier(30 * pole_count)
      return assemblers("pole-assembler", pole_count, 2, 1, wood_first and {wood, cables} or {cables, wood})
    end

    for _, copper_count in ipairs({1, 5}) do
      for _, cable_count in ipairs({1, 3}) do
        for _, pole_count in ipairs({1, 4}) do
          for _, wood_first in ipairs({true, false}) do
            local label = string.format("%d copper furnaces, %d cable and %d pole assemblers, wood %s", copper_count, cable_count, pole_count, wood_first and "first" or "second")

            it_builds_soundly(label, function() return poles(copper_count, cable_count, pole_count, wood_first) end, "small-electric-pole", nil,
              "the wood and the cables on a lane of their own where they are eaten")
          end
        end
      end
    end

    -- Steel plate is smelted from iron plates in a furnace that burns fuel, which rides the free lane of the belt of
    -- plates: only the design with one belt of each material builds it.
    local function steel_furnaces(count, suppliers)
      return {
        machine_count = count, machine = "steel-furnace", shape = {machine_size = 2, input_inserters = 1, output_inserters = 1},
        suppliers = suppliers, fuel_feed = {items = {{name = "coal", amount = 2 * count}}},
      }
    end

    for _, iron_count in ipairs({1, 3}) do
      for _, steel_count in ipairs({1, 3}) do
        for _, chest_count in ipairs({1, 2}) do
          local label = string.format("%d iron and %d steel furnaces and %d chest assemblers", iron_count, steel_count, chest_count)

          it_builds_soundly(label, function()
            return assemblers("chest-assembler", chest_count, 1, 1, {steel_furnaces(steel_count, {furnaces("iron-furnace", iron_count)})})
          end, "steel-chest", nil, nil, true)
        end
      end
    end

    -- Heavy armor eats copper plates and steel plates: the steel chain is a column of its own beside the copper furnaces.
    for _, iron_count in ipairs({1, 3}) do
      for _, copper_count in ipairs({1, 3}) do
        for _, armor_count in ipairs({1, 2}) do
          for _, steel_first in ipairs({true, false}) do
            local label = string.format("%d iron and %d copper furnaces and %d armor assemblers, %s first", iron_count, copper_count, armor_count, steel_first and "steel" or "copper")

            it_builds_soundly(label, function()
              local steel = steel_furnaces(2, {furnaces("iron-furnace", iron_count)})
              local copper = furnaces("copper-furnace", copper_count)
              return assemblers("armor-assembler", armor_count, 2, 1, steel_first and {steel, copper} or {copper, steel})
            end, "heavy-armor", nil, nil, true)
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

              it_builds_soundly(label, function() return gadgets(iron_count, brick_count, gadget_count, shape, forward) end, "gadget", machines_eating(shape.eats))
            end
          end
        end
      end
    end

    -- A gadget assembler that is itself one of the suppliers of an outer one: the inner column has a belt b of its own.
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
            end
            return gadget_assembler(outer_count, outer_suppliers, "outer-assembler")
          end

          it_builds_soundly("a gadget inside a gadget with " .. label, nested, "outer-gadget")
        end
      end
    end

    for _, design in ipairs(designs) do
      it("puts a raw item alone on belt a, with the other two ingredients on belt b" .. design.suffix, function()
        -- Wood rides both lanes of belt a and has the column furthest west.
        local suppliers = {
          wood_supplier(),
          on_belt_b(assemblers("cable-assembler", 1, 1, 2, {furnaces("copper-furnace", 2)})),
          on_belt_b(furnaces("brick-furnace", 1)),
        }

        local entities, second = design.build(gadget_assembler(2, suppliers))

        assert.are.same({}, validator.validate(entities, catalog()))
        assert.are.same({}, tracer.problems(entities, options_for(design, entities, second, {
          machines = machines_eating({"wood", "copper-cable", "stone-brick"}), raw = raw, product = "gadget",
        })))
      end)

      it("wires a tall tree from the poles of its columns" .. design.suffix, function()
        -- Six furnaces in each plate column make the columns of the transport belt tree 12 rows tall.
        local entities = design.build(underground_belts(6, 1, 1, 1, true))

        assert.are.same({}, validator.validate(entities, catalog()))
      end)
    end

    it("winds the output belt of the final column when each of its machines has two output inserters", function()
      local root = assemblers("circuit-assembler", 2, 2, 2, {furnaces("iron-furnace", 1), furnaces("copper-furnace", 1)})

      local entities = rows.build(root, NAMES)

      local product_belts = #belt_rows(entities, 18) + #belt_rows(entities, 19) -- the inner and the outer column
      assert.are.equal(1 + 2 * 4 + 2, product_belts) -- the start, a seam of two inserters for each of the two machines, the two rows between them
    end)

    -- A column that is itself a tree on both sides: two transport belt makers, each of plates and gears.
    local function two_trees(plate_count, belt_count)
      local function belt_maker(machine)
        local gears = assemblers("gear-assembler", 1, 2, 1, {furnaces("iron-furnace", plate_count)})
        return assemblers(machine, belt_count, 2, 2, {furnaces("iron-furnace", plate_count), gears})
      end
      return assemblers("double-assembler", 1, 2, 1, {belt_maker("belt-assembler"), belt_maker("other-belt-assembler")})
    end

    for _, plate_count in ipairs({1, 3}) do
      for _, belt_count in ipairs({1, 3}) do
        it_builds_soundly("two trees side by side, with " .. plate_count .. " furnaces per plate column and " .. belt_count .. " belt assemblers",
          function() return two_trees(plate_count, belt_count) end, "double-belt")
      end
    end

    -- The sweeps above would pass vacuously if the tracer were not told about the belts that come in and the lanes of the
    -- furnaces. This builds the circuit of iron plates and cables, turns the ore feeder of the copper mixer straight on
    -- instead of into it, and checks that the tracer, set up as in the sweeps, then reports a problem. (The rules of the
    -- tracer themselves, such as an underground belt with no exit, are tested in spec/belt_tracer_spec.lua.)
    it("is set up so that the tracer reports a band whose ore feeder does not turn into its mixer", function()
      local root = assemblers("circuit-assembler", 1, 2, 1, {
        furnaces("iron-furnace", 1),
        assemblers("cable-assembler", 1, 1, 2, {furnaces("copper-furnace", 1)}),
      })
      local entities, inputs = build_pure(root)
      local options = {
        machines = machines, raw = raw, raw_lanes = raw_lanes, product = "electronic-circuit",
        supplies = inputs, underground_reach = UNDERGROUND_REACH,
      }
      local sound = tracer.problems(entities, options)
      entity_at(entities, NAMES.belt, 5, 2, 1).direction = east

      local broken = tracer.problems(entities, options)

      assert.are.same({}, sound)
      assert.is_true(#broken > 0)
    end)

    it("lists the raw stages of a tree three levels deep from the top down", function()
      local root = underground_belts(1, 1, 1, 1, true)

      local _, raw_stages = rows.build(root, NAMES)

      assert.are.equal(3, #raw_stages)
    end)
  end)
end)
