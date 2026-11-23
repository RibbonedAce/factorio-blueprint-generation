-- spec/rows_plants_spec.lua
-- A block made apart as a column of the row (see `bpgen.PlantsBlock` and the head of scripts/rows.lua): plants that make an item from fluids and raw
-- items, with the machines that make the fluids, stand among the columns of machines of a recipe, and the product of the block rides an arc into the
-- belt of the column that eats it, as the product of any column does. The block here is a stand-in: a belt of raw items (coal) and a pipe (crude oil)
-- come into a plant of 3 x 3, whose inserter drops the product on a belt. Positions are tiles read off the diagrams (x from the west edge, y down;
-- `P` the plant, `G` the gadget assembler that eats the product and the iron plates, `i` an iron furnace, `t` and `b` the ends of an underground
-- pipe that open north and south).
---@diagnostic disable: undefined-field  -- luassert's `assert` has fields (`assert.are`, `assert.is_nil`, ...) the editor cannot see

local builders = require("spec.support.builders")
local entity_list = require("scripts.entity_list")
local grid = require("scripts.grid")
local picture = require("spec.support.picture")
local rows = require("scripts.rows")
local tracer = require("spec.support.belt_tracer")
local validator = require("spec.support.blueprint_validator")

local NAMES = builders.NAMES
local south, west = defines.direction.south, defines.direction.west

local GLYPHS = {["iron-furnace"] = {size = 2, glyph = "i"}, plant = {size = 3, glyph = "P"}, gadget = {size = 3, glyph = "G"}, ["fluid-gadget"] = {size = 3, glyph = "F"}}

-- The stand-in block, in its own frame: column 0 is its west edge and row 0 its first row.
--
--      01234567
--   0 |=v.PPP.v      the pipe (x 0), the belt of raw items (x 1), the plant (x 3 to 5), the belt of the product (x 7)
--   1 |=v}PPP}v      the inserter that brings the raw item in, and the one that takes the product out
--   2 |=v+PPP+v      the poles of the two inserters, wired
--
-- With `winds`, a belt of its own runs down column 8, east of the one the product leaves on, as the belt of the product of plants that wind has.
-- `belt_from` and `pipe_from` are the first rows of the belt of raw items and of the pipe (0 by default): they start below the first row of the block.
---@param options? {feed?: bpgen.Feed, pipe?: boolean, fluid?: string, winds?: boolean, belt_from?: integer, pipe_from?: integer}
---@return bpgen.PlantsBlock
local function a_block(options)
  options = options or {}
  local belt_from, pipe_from = options.belt_from or 0, options.pipe_from or 0
  local entities = {}
  local function add(entity)
    return entity_list.append(entities, entity)
  end
  for row = 0, 2 do
    if row >= belt_from then
      add({name = NAMES.belt, position = grid.position(1, row), direction = south})
    end
    add({name = NAMES.belt, position = grid.position(7, row), direction = south})
    if options.winds then
      add({name = NAMES.belt, position = grid.position(8, row), direction = south})
    end
    if options.pipe ~= false and row >= pipe_from then
      add({name = NAMES.pipe, position = grid.position(0, row)})
    end
  end
  add({name = NAMES.inserter, position = grid.position(2, 1), direction = west})
  add({name = "plant", position = grid.position(3, 0, 3, 3)})
  add({name = NAMES.inserter, position = grid.position(6, 1), direction = west})
  local first, second = add({name = NAMES.pole, position = grid.position(2, 2)}), add({name = NAMES.pole, position = grid.position(6, 2)})
  entity_list.connect_poles(first, second)
  local starts = {{key = "belt", x = 1, y = belt_from, name = NAMES.belt, belt = true, feed = options.feed}}
  if options.pipe ~= false then
    starts[2] = {key = "oil", x = 0, y = pipe_from, name = NAMES.pipe, fluid = options.fluid or "crude-oil"}
  end
  return {entities = entities, pole_groups = {{first, second}}, product = {column = 7, last_row = 2}, width = options.winds and 9 or 8, height = 3, sizes = {plant = 3}, starts = starts}
end

local COAL = {items = {{name = "coal", amount = 10}}}

local function furnaces(count)
  return {
    machine_count = count, machine = "iron-furnace", shape = {machine_size = 2, input_inserters = 1, output_inserters = 1}, suppliers = {},
    feed = {items = {{name = "iron-ore", amount = 20 * count}, {name = "coal", amount = 2 * count}}},
  }
end

-- The assembler that eats the product of the block (belt a, one lane) and the plates of one furnace (also belt a, the other lane).
local function root_of(block, belt)
  return {
    machine_count = 1, machine = "gadget", shape = {machine_size = 3, input_inserters = 2, output_inserters = 1},
    suppliers = {{plants = block, belt = belt or "a"}, furnaces(1)},
  }
end

local function build_pure(root)
  return rows.build_pure(root, NAMES, {lane_items_per_minute = 450, underground_reach = 5})
end

local function drawn(entities, last_column, last_row, first_row)
  return picture.draw(entities, GLYPHS, 0, first_row, last_column, last_row)
end

local function catalog()
  local entries = builders.a_catalog{}
  entries.plant = {kind = "machine", width = 3, height = 3, needs_power = true}
  entries.gadget = {kind = "machine", width = 3, height = 3, needs_power = true}
  entries["iron-furnace"] = {kind = "machine", width = 2, height = 2, needs_power = false}
  return entries
end

describe("a block made apart, as a column of the row", function()
  describe("in the original design of the belts", function()
    -- The belts of raw items run along the rows above, the one that comes down furthest east on the top row: the furnaces' (x 8) in row 0, the
    -- block's (x 1) in row 1. The block has a pipe, so it starts one row lower (row 3) than right under its belt, leaving the row 2 for the end of the
    -- underground pipe that comes out there, from under the two belts that run over its column. Its product belt goes on down from its last row to the
    -- arc, which runs east to the belt a of the assembler (x 14) through the lane gadget, since the furnaces' plates join it from the west.
    --
    --      012345678901234567890
    --  -3 |=....................     the entry of the crude oil: a row of its own above the blueprint
    --  -2 |=....................
    --  -1 |t....................     the end of the underground pipe, which opens north
    --   0 |>>>>>>>>v.....^}GGG}v     the belt of the furnaces
    --   1 |>v......v}ii}v^}GGG+v     the belt of the block comes down in the column 1
    --   2 |bv.......+ii+v^+GGG.v     the end that opens south
    --   3 |=v.PPP.v.....v^......
    --   4 |=v}PPP}v.....v^......
    --   5 |=v+PPP+v.....v^......
    --   6 |.......v>>>>>>^......     the arc of the product of the block, which ends in the belt a
    --   7 |.......>>^...........     the lane gadget of the head
    local entities, _, entries = rows.build(root_of(a_block()), NAMES)

    it("puts the block under the belts of raw items, with a row free under them for the pipe, and the arc of its product to the assembler", function()
      assert.are.same({
        "=....................", "=....................", "t....................", ">>>>>>>>v.....^}GGG}v", ">v......v}ii}v^}GGG+v", "bv.......+ii+v^+GGG.v",
        "=v.PPP.v.....v^......", "=v}PPP}v.....v^......", "=v+PPP+v.....v^......", ".......v>>>>>>^......", ".......>>^...........",
      }, drawn(entities, 20, 7, -3))
    end)

    it("brings in the pipe at the top left corner, above the blueprint, and says what it brings", function()
      assert.are.same({{x = -2, y = -3, item = "crude-oil", type = "fluid"}}, entries)
    end)

    it("passes the validator", function()
      assert.are.same({}, validator.validate(entities, catalog()))
    end)

    it("numbers the entities from 1 with no gap", function()
      assert.has_consecutive_numbers(entities)
    end)

    it("starts the next column east of the whole block, when its belt winds and has a column east of the one the product leaves on", function()
      local result = rows.build(root_of(a_block{winds = true}), NAMES)

      -- the belt of the furnaces comes down column 9, east of the second belt of the block (column 8), and every column after it is one more east
      assert.are.same({
        "=........................", "=........................", "t........................", ">>>>>>>>>v.....^}GGG}v...", ">v.......v}ii}v^}GGG+v...",
        "bv........+ii+v^+GGG.v...", "=v.PPP.vv.....v^.........", "=v}PPP}vv.....v^.........", "=v+PPP+vv.....v^.........", ".......v>>>>>>>^.........",
        ".......>>^...............",
      }, drawn(result, 24, 7, -3))
      assert.are.same({}, validator.validate(result, catalog()))
    end)

    it("brings the belt of raw items down to its own first tile when that is below the first row of the block", function()
      local result = rows.build(root_of(a_block{belt_from = 1}), NAMES)

      -- the belt of the block starts in its row 1, so the descent comes down to its row 0: the belt is the same one as the block with a belt from its first row
      assert.are.same({
        "=....................", "=....................", "t....................", ">>>>>>>>v.....^}GGG}v", ">v......v}ii}v^}GGG+v", "bv.......+ii+v^+GGG.v",
        "=v.PPP.v.....v^......", "=v}PPP}v.....v^......", "=v+PPP+v.....v^......", ".......v>>>>>>^......", ".......>>^...........",
      }, drawn(result, 20, 7, -3))
    end)

    it("starts the pipe at the row of the block where it starts, which is below the first row", function()
      local result, _, entries = rows.build(root_of(a_block{pipe_from = 1}), NAMES)

      -- the pipe starts in the row 1 of the block, so the pipe that comes in goes down to its row 0 and the pipe of the block goes on from there
      assert.are.same({
        "=....................", "=....................", "t....................", ">>>>>>>>v.....^}GGG}v", ">v......v}ii}v^}GGG+v", "bv.......+ii+v^+GGG.v",
        "=v.PPP.v.....v^......", "=v}PPP}v.....v^......", "=v+PPP+v.....v^......", ".......v>>>>>>^......", ".......>>^...........",
      }, drawn(result, 20, 7, -3))
      assert.are.same({{x = -2, y = -3, item = "crude-oil", type = "fluid"}}, entries)
      assert.are.same({}, validator.validate(result, catalog()))
    end)

    it("leaves no row free under the belts for a block with no pipe, which starts right under its own belt", function()
      local result = rows.build(root_of(a_block{pipe = false}), NAMES)

      -- the belt of the block (x 1) is in row 1 and the plant starts in row 2, right under it
      assert.are.same({">>>>>>>>v.....^}GGG}v", ">v......v}ii}v^}GGG+v", ".v.PPP.v.+ii+v^+GGG.v"}, drawn(result, 20, 2, 0))
    end)
  end)

  describe("in the design that brings in one belt of each material", function()
    -- The belt of coal of the block comes down from a trunk of its own (row 6; the furnaces' trunk, with the ore and the coal, is row 3), and the
    -- pipe of the crude oil goes down column 8 from the row -3 under both trunks, with an underground pipe for each: the end that opens north above the
    -- trunk (rows 2 and 5) and the one that opens south under it (rows 4 and 7). The block starts in row 8, the first row under the lowest trunk with a
    -- row free between, and the belt of coal goes on down column 9 from the end of its descent (row 7) to the first tile of its own.
    --
    --      0123456789012345678901234567
    --  -3 |=========....................
    --  -2 |........=....................
    --  -1 |........=....................
    --   0 |>>v.....=.............^}GGG}v
    --   1 |..v.....=.............^}GGG+v
    --   2 |>(v.)v..t.............^+GGG.v
    --   3 |..SS.>>>>>>>>>>>v.....^......     the trunk of the furnaces, with the splitter that takes the belt of the block off it
    --   4 |..v>>^..b.......v.....^......
    --   5 |..v.....t.......v}ii}v^......
    --   6 |..>>>>>>>v.......+ii+v^......     the trunk of coal of the block, down in column 9
    --   7 |........bv...........v^......
    --   8 |........=v.PPP.v.....v^......
    --   9 |........=v}PPP}v.....v^......
    --  10 |........=v+PPP+v.....v^......
    --  11 |...............v>>>>>>^......
    --  12 |...............>>^...........
    local entities, supplies = build_pure(root_of(a_block{feed = COAL}))

    it("brings the coal of the block in by a pure belt of its own and the pipe above the band, both through the same trunks as any column's", function()
      assert.are.same({
        "=========....................", "........=....................", "........=....................", ">>v.....=.............^}GGG}v", ".+v.....=.............^}GGG+v",
        ">(v.)v..t.............^+GGG.v", "..SS.>>>>>>>>>>>v.....^......", "..v>>^..b.......v.....^......", "..v...+.t.......v}ii}v^......",
        "..>>>>>>>v.......+ii+v^......", "........bv...........v^......", "........=v.PPP.v.....v^......", "........=v}PPP}v.....v^......",
        "........=v+PPP+v.....v^......", "...............v>>>>>>^......", "...............>>^...........",
      }, drawn(entities, 28, 12, -3))
    end)

    it("says what comes in, from the top down", function()
      assert.are.same({
        {x = -2, y = -3, item = "crude-oil", type = "fluid"}, {x = 0, y = 0, item = "coal"}, {x = 0, y = 2, item = "iron-ore"},
      }, {supplies[3], supplies[1], supplies[2]})
    end)

    it("passes the validator and the belt tracer", function()
      local problems = tracer.problems(entities, {
        machines = {
          ["iron-furnace"] = {size = 2, eats = {"iron-ore"}, makes = "iron-plate"}, plant = {size = 3, eats = {"coal"}, makes = "plastic"},
          gadget = {size = 3, eats = {"plastic", "iron-plate"}, makes = "gadget"},
        },
        raw = {["iron-furnace"] = true, plant = true}, product = "gadget", underground_reach = 5,
        raw_lanes = {["iron-furnace"] = {"iron-ore", "coal"}, plant = {"coal"}},
        supplies = {{x = 0, y = 0, item = "coal"}, {x = 0, y = 2, item = "iron-ore"}},
      })

      assert.are.same({}, validator.validate(entities, catalog()))
      assert.are.same({}, problems)
    end)

    it("starts the next column east of the whole block here too, when its belt winds", function()
      local result = build_pure(root_of(a_block{feed = COAL, winds = true}))

      assert.are.same({
        "=========........................", "........=........................", "........=........................", ">>v.....=..............^}GGG}v...",
        ".+v.....=..............^}GGG+v...", ">(v.)v..t..............^+GGG.v...", "..SS.>>>>>>>>>>>>v.....^.........", "..v>>^..b........v.....^.........",
        "..v...+.t........v}ii}v^.........", "..>>>>>>>v........+ii+v^.........", "........bv............v^.........",
        "........=v.PPP.vv.....v^.........", "........=v}PPP}vv.....v^.........", "........=v+PPP+vv.....v^.........",
        "...............v>>>>>>>^.........", "...............>>^...............",
      }, drawn(result, 32, 12, -3))
      assert.are.same({}, validator.validate(result, catalog()))
    end)

    it("stops when a belt of raw items of the block has no feed, which the band needs to divide the belts", function()
      local run = function() build_pure(root_of(a_block())) end

      assert.has_error(run, "rows: a belt of raw items of a block made apart has no feed")
    end)

    it("starts the block right under the lowest trunk when the belt of raw items starts in a row of its own", function()
      local block = a_block{feed = COAL}
      block.starts[1].y = 2 -- the belt of raw items has its first tile in the row 2 of the block

      local result = build_pure(root_of(block))

      -- the descent ends in row 7 and the block starts in row 8 all the same (under the lowest trunk), so the belt comes down to its own first tile at row 10
      assert.are.same({"v", "v", "v"}, {table.unpack(picture.draw(result, GLYPHS, 9, 8, 9, 10))})
      assert.are.same({"=v.PPP.v.....", "=v}PPP}v.....", "=v+PPP+v.....", ".......v>>>>>"}, picture.draw(result, GLYPHS, 8, 8, 20, 11))
    end)
  end)

  describe("a block with a pipe, in a blueprint with a column that takes water from a pump", function()
    -- The machines of the gadget take water through a pipe (`F`), which one pump in the top left corner brings (`P`, two tiles, east of the picture's column 0); the
    -- block brings crude oil in by a pipe too. The entry of the crude oil goes in the rows above the pump's, so the two do not meet.
    local function fluid_root_of(block)
      return {
        machine_count = 1, machine = "fluid-gadget", shape = {machine_size = 3, input_inserters = 2, output_inserters = 1, fluid_input = true},
        suppliers = {{plants = block, belt = "a"}, furnaces(1)},
      }
    end

    it("puts the entry of the pipe of the block above the pump of the column, in the original design", function()
      local result, _, entries = rows.build(fluid_root_of(a_block()), NAMES)

      assert.are.same({
        ".........................", ".........................", "=........................", "t........................", "+........................",
        "PP=============..........", ">>>>>>>>v.....=.^}FFF}v..", ">v......v}ii}v=w^eFFF+v..", "bv.......+ii+v.+^}FFF.v..", "=v.PPP.v.....v..^........",
        "=v}PPP}v.....v..^........", "=v+PPP+v.....v..^........", ".......v>>>>>>>>^........",
      }, picture.draw(result, GLYPHS, 0, -6, 24, 6))
      assert.are.same({{x = -2, y = -4, item = "crude-oil", type = "fluid"}}, entries)
    end)
  end)

  describe("more than one block, and a block that is the only thing a column takes", function()
    it("brings a fluid that two blocks take in once", function()
      local root = {
        machine_count = 1, machine = "gadget", shape = {machine_size = 3, input_inserters = 2, output_inserters = 1},
        suppliers = {{plants = a_block(), belt = "a"}, {plants = a_block(), belt = "a"}},
      }

      local _, _, entries = rows.build(root, NAMES)

      assert.are.same({{x = -2, y = -3, item = "crude-oil", type = "fluid"}}, entries)
    end)

    it("keeps two fluids apart", function()
      local root = {
        machine_count = 1, machine = "gadget", shape = {machine_size = 3, input_inserters = 2, output_inserters = 1},
        suppliers = {{plants = a_block{fluid = "water"}, belt = "a"}, {plants = a_block{fluid = "crude-oil"}, belt = "a"}},
      }

      local _, _, entries = rows.build(root, NAMES)

      local rows_of = {}
      for _, entry in ipairs(entries) do
        rows_of[#rows_of + 1] = entry.y
      end
      table.sort(rows_of)
      assert.are.same({-6, -3}, rows_of)
    end)

    it("stops when a pipe of a block does not say its fluid, which is what makes the fluids one entry each", function()
      local block = a_block()
      block.starts[2].fluid = nil

      local run = function() rows.build(root_of(block), NAMES) end

      assert.has_error(run, "rows: a pipe of a block made apart does not say its fluid")
    end)

    it("makes a column of its own of a block that is the only thing a step takes, not a step of the chain before it", function()
      local only = {machine_count = 1, machine = "gadget", shape = {machine_size = 3, input_inserters = 1, output_inserters = 1}, suppliers = {{plants = a_block(), belt = "a"}}}

      local entities = rows.build(only, NAMES)

      -- the block is the column before the assembler, and its product goes to the assembler along an arc
      assert.are.same({1, 1}, {#builders.entities_named(entities, "plant"), #builders.entities_named(entities, "gadget")})
      assert.are.same({}, validator.validate(entities, catalog()))
    end)
  end)
end)
