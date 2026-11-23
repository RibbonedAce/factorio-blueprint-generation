-- spec/rows_fluid_supplier_spec.lua
-- A final column that takes a fluid that a block makes (the petroleum gas of a barrel, from refineries): the block is the column right west of the
-- pipes of the column, with no arc, its pipe is joined to the trunk of those pipes and no pump brings the fluid (see the head of scripts/rows.lua).
-- The block here is a stand-in: a machine of 3 x 3 (`R`) with the pipe the fluid leaves by east of it, a pole west of it and, when it says, poles east
-- of the pipe too. Positions are tiles read off the diagrams (x from the west edge, y down; `B` the machines that take the fluid, `G` the assembler
-- that takes their product and the plates of a furnace, `i` an iron furnace, `w` and `e` the ends of the underground pipes of the machines).
---@diagnostic disable: undefined-field  -- luassert's `assert` has fields (`assert.are`, `assert.is_nil`, ...) the editor cannot see

local builders = require("spec.support.builders")
local entity_list = require("scripts.entity_list")
local grid = require("scripts.grid")
local picture = require("spec.support.picture")
local rows = require("scripts.rows")
local validator = require("spec.support.blueprint_validator")

local NAMES = builders.NAMES

local GLYPHS = {
  ["iron-furnace"] = {size = 2, glyph = "i"}, refinery = {size = 3, glyph = "R"}, ["barrel-assembler"] = {size = 3, glyph = "B"},
  ["gadget-assembler"] = {size = 3, glyph = "G"}, ["copper-furnace"] = {size = 2, glyph = "c"},
}

-- The stand-in block, in its own frame: column 0 is its west edge and row 0 its first row.
--
--      0123456
--   0 |.RRR=.     the pole (x 0, row 1), the machine (x 1 to 3), the pipe the fluid leaves by (x 4) and, with `gap`, a pole east of the pipe (x 5)
--   1 |+RRR=+
--   2 |.RRR=.
--   3 |....=.     the pipe goes on to `pipe_to`
--
-- `pipe_from` is the first row of the pipe (0 by default) and `gap_rows` the rows of the poles east of it (row 1 with `gap`).
---@param options? {gap?: boolean, gap_rows?: integer[], pipe_from?: integer, pipe_to?: integer, item?: boolean}
---@return bpgen.PlantsBlock
local function a_fluid_block(options)
  options = options or {}
  local from, to = options.pipe_from or 0, options.pipe_to or 3
  local entities = {}
  local function add(entity)
    return entity_list.append(entities, entity)
  end
  add({name = "refinery", position = grid.position(1, 0, 3, 3)})
  for row = from, to do
    add({name = NAMES.pipe, position = grid.position(4, row)})
  end
  local first = add({name = NAMES.pole, position = grid.position(0, 1)})
  local poles = {first}
  for _, row in ipairs(options.gap_rows or (options.gap and {1}) or {}) do
    poles[#poles + 1] = add({name = NAMES.pole, position = grid.position(5, row)})
    entity_list.connect_poles(first, poles[#poles])
  end
  return {
    entities = entities, pole_groups = {poles}, product = {column = 4, last_row = to, fluid = not options.item},
    width = (options.gap or options.gap_rows) and 6 or 5, height = math.max(3, to + 1), sizes = {refinery = 3}, starts = {},
  }
end

local function furnaces(count)
  return {
    machine_count = count, machine = "iron-furnace", shape = {machine_size = 2, input_inserters = 1, output_inserters = 1}, suppliers = {},
    feed = {items = {{name = "iron-ore", amount = 20 * count}, {name = "coal", amount = 2 * count}}},
  }
end

-- Furnaces of copper whose plates ride the belt b of the column that takes them.
local function copper_furnaces(count)
  local column = furnaces(count)
  column.machine, column.belt = "copper-furnace", "b"
  column.feed = {items = {{name = "copper-ore", amount = 20 * count}, {name = "coal", amount = 2 * count}}}
  return column
end

-- The column that takes the fluid from two woven belts (iron plates on belt a, copper plates on belt b): its machines take the fluid in the middle row
-- as before, and its trunk of pipes starts a row below the top of its block, since the pattern of the belts needs the row above the first machine.
---@param block bpgen.PlantsBlock
---@return bpgen.StageLayout
local function woven_column(block)
  return {
    machine_count = 1, machine = "barrel-assembler", fluid_supplier = block,
    shape = {machine_size = 3, input_inserters = 2, input_belts = {a = 1, b = 1}, output_inserters = 1, fluid_input = true},
    suppliers = {furnaces(1), copper_furnaces(1)},
  }
end

-- The column that takes the fluid: assemblers whose machines have a pipe in the middle row of their input side, fed by a column of furnaces, with
-- `block` the block that makes the fluid.
---@param block bpgen.PlantsBlock|nil
---@param count? integer
---@return bpgen.StageLayout
local function barrel_column(block, count)
  return {
    machine_count = count or 1, machine = "barrel-assembler", fluid_supplier = block,
    shape = {machine_size = 3, input_inserters = 1, output_inserters = 1, fluid_input = true}, suppliers = {furnaces(1)},
  }
end

-- An assembler that takes the product of the column that takes the fluid and the plates of a furnace, whose belt of raw items runs over the column.
local function gadget_column(block)
  return {
    machine_count = 1, machine = "gadget-assembler", shape = {machine_size = 3, input_inserters = 2, output_inserters = 1},
    suppliers = {barrel_column(block), furnaces(1)},
  }
end

-- An assembler that takes the product of `column` and the plates of a furnace, whose belt of raw items runs over the column.
---@param column bpgen.StageLayout
---@return bpgen.StageLayout
local function gadget_with(column)
  return {
    machine_count = 1, machine = "gadget-assembler", shape = {machine_size = 3, input_inserters = 2, output_inserters = 1},
    suppliers = {column, furnaces(1)},
  }
end

local function catalog()
  local entries = builders.a_catalog{}
  entries.refinery = {kind = "machine", width = 3, height = 3, needs_power = true}
  entries["barrel-assembler"] = {kind = "machine", width = 3, height = 3, needs_power = true, fluid_input = true}
  entries["gadget-assembler"] = {kind = "machine", width = 3, height = 3, needs_power = true}
  entries["iron-furnace"] = {kind = "machine", width = 2, height = 2, needs_power = false}
  entries["copper-furnace"] = {kind = "machine", width = 2, height = 2, needs_power = false}
  entries[builders.POLES.medium.name] = {
    kind = "pole", width = 1, height = 1, supply_radius = builders.POLES.medium.supply_distance, wire_reach = builders.POLES.medium.wire_distance,
  }
  return entries
end

local function build_pure(root)
  return rows.build_pure(root, NAMES, {lane_items_per_minute = 450, underground_reach = 5})
end

local function drawn(entities, last_column, last_row)
  return picture.draw(entities, GLYPHS, 0, 0, last_column, last_row)
end

local function count_named(entities, name)
  local count = 0
  for _, entity in ipairs(entities) do
    count = count + (entity.name == name and 1 or 0)
  end
  return count
end

describe("a final column that takes a fluid that a block makes", function()
  describe("in the original design of the belts", function()
    -- The pipe the fluid leaves by (x 10) is right beside the trunk of the pipes of the column (x 11, `=`), so the two are one network: there is no pump
    -- and no link, and the block has no arc (the arc under it is the one of the furnaces, which run east to belt a, x 13).
    local entities = rows.build(barrel_column(a_fluid_block()), NAMES)

    it("puts the block right west of the pipes of the column, its pipe beside the trunk", function()
      assert.are.same({
        "v......RRR==.^}BBB}v",
        "v}ii}v+RRR==w^eBBB+v",
        ".+ii+v.RRR=.+^.BBB.v",
        ".....v....=..^......",
        ".....>>>>>>>>^......",
      }, drawn(entities, 19, 4))
    end)

    it("joins the pipe to the trunk", function()
      assert.are.same({0, {}}, {count_named(entities, NAMES.pump), validator.validate(entities, catalog())})
    end)

    it("joins the pipe through the tile between when a pole of the block stands east of it, along a row where that tile is free", function()
      local result = rows.build(barrel_column(a_fluid_block{gap = true}), NAMES)

      assert.are.same({
        "v......RRR===.^}BBB}v",
        "v}ii}v+RRR=+=w^eBBB+v",
        ".+ii+v.RRR=..+^.BBB.v",
        ".....v....=...^......",
        ".....>>>>>>>>>^......",
      }, drawn(result, 20, 4))
      assert.are.same({}, validator.validate(result, catalog()))
    end)

    it("moves the column that takes the fluid down to the rows of the pipe when the pipe starts under the end of its trunk", function()
      local result = rows.build(barrel_column(a_fluid_block{pipe_from = 8, pipe_to = 11}), NAMES)

      assert.are.same({
        "v......RRR..........",
        "v}ii}v+RRR..........",
        ".+ii+v.RRR..........",
        ".....v..............",
        ".....v..............",
        ".....v..............",
        ".....v..............",
        ".....v...+.=.^}BBB}v",
        ".....v....==w^eBBB+v",
        ".....v....=.+^.BBB.v",
        ".....v....=..^......",
        ".....v....=..^......",
        ".....>>>>>>>>^......",
      }, drawn(result, 19, 12))
      assert.are.same({}, validator.validate(result, catalog()))
    end)

    it("moves the block down when the trunk of the pipes starts under the end of its pipe, as the belt of the furnaces runs over both", function()
      local result = rows.build(gadget_column(a_fluid_block{pipe_to = 0}), NAMES)

      assert.are.same({
        ">>>>>>>>>>>>>>>>>>>>",
        "v...................",
        "v}ii}v.RRR==.^}BBB}v",
        ".+ii+v+RRR.=w^eBBB+v",
        ".....v.RRR..+^.BBB.v",
        ".....>>>>>>>>^.....>",
      }, drawn(result, 19, 5))
      assert.are.same({}, validator.validate(result, catalog()))
    end)

    it("starts the arc under the column that takes the fluid, which moved down, when the block is shorter than that column is low", function()
      local result = rows.build(barrel_column(a_fluid_block{pipe_from = 8, pipe_to = 8}), NAMES)

      assert.are.same({
        "v......RRR..........",
        "v}ii}v+RRR..........",
        ".+ii+v.RRR..........",
        ".....v..............",
        ".....v..............",
        ".....v..............",
        ".....v..............",
        ".....v...+.=.^}BBB}v",
        ".....v....==w^eBBB+v",
        ".....v......+^.BBB.v",
        ".....>>>>>>>>^......",
        "....................",
        "....................",
      }, drawn(result, 19, 12))
      assert.are.same({}, validator.validate(result, catalog()))
    end)

    it("takes the row of the trunk that starts under the top of the column when the belts are woven", function()
      local result = rows.build(gadget_with(woven_column(a_fluid_block{pipe_to = 0})), NAMES)

      assert.are.same({
        ">>>>>>>>>>>>>>>>>>>>>>>>>>>v.....^}GGG}v.....",
        ">>>>>>v....................v}ii}v^}GGG+v.....",
        "v.....v}cc}v.......^<.......+ii+v^+GGG.v.....",
        "v}ii}v.+cc+v.RRR==+>^}BBB}v.....v^...........",
        ".+ii+v.....v+RRR.=w^+eBBB+v>>>>>>^...........",
        ".....v.....v.RRR...^>}BBB.>>^................",
        ".....v.....>>>>>>>>^^........................",
        ".....>>>>>>>>>>>>>>>^........................",
      }, drawn(result, 44, 7))
      assert.are.same({}, validator.validate(result, catalog()))
    end)

    it("stops when no row has a pipe on both sides with the tiles between them free", function()
      local run = function() rows.build(barrel_column(a_fluid_block{gap_rows = {0, 1}}), NAMES) end

      assert.has_error(run, "rows: the pipe of a block that makes a fluid cannot be joined to the trunk of the pipes of the column that takes it")
    end)
  end)

  describe("in the design that brings in one belt of each material", function()
    it("builds the same: the block right west of the pipes, joined, with no pump", function()
      local entities = build_pure(barrel_column(a_fluid_block()))

      assert.are.same({
        ">v.........RRR==.^}BBB}v",
        ".>>>v.....+RRR==w^eBBB+v",
        ">^..v......RRR=.+^.BBB.v",
        "....v}ii}v....=..^......",
        ".....+ii+>>>>>>>>^......",
      }, drawn(entities, 23, 4))
      assert.are.same({0, {}}, {count_named(entities, NAMES.pump), validator.validate(entities, catalog())})
    end)

    it("joins the pipe through the tile between when a pole of the block stands east of it", function()
      local entities = build_pure(barrel_column(a_fluid_block{gap = true}))

      assert.are.same({
        ">v.........RRR===.^}BBB}v",
        ".>>>v.....+RRR=+=w^eBBB+v",
        ">^..v......RRR=..+^.BBB.v",
        "....v}ii}v....=...^......",
        ".....+ii+>>>>>>>>>^......",
      }, drawn(entities, 24, 4))
      assert.are.same({}, validator.validate(entities, catalog()))
    end)

    it("moves the column that takes the fluid down to the rows of the pipe", function()
      local entities = build_pure(barrel_column(a_fluid_block{pipe_from = 8, pipe_to = 11}))

      assert.are.same({
        ">v.........RRR...........",
        ".>>>v.....+RRR...........",
        ">^..v......RRR...........",
        "....v}ii}v...............",
        ".....+ii+v...............",
        ".........v...............",
        ".........v...............",
        ".........v....+=.^}BBB}v.",
        ".........v....==w^eBBB+v.",
        ".........v....=.+^.BBB.v.",
        ".........v....=..^.......",
        ".........v....=..^.......",
        ".........>>>>>>>>^.......",
      }, drawn(entities, 24, 12))
      assert.are.same({}, validator.validate(entities, catalog()))
    end)
  end)

  describe("what it refuses", function()
    it("stops when the block makes an item", function()
      local run = function() rows.build(barrel_column(a_fluid_block{item = true}), NAMES) end

      assert.has_error(run, "rows: a block that makes an item cannot make the fluid a column takes")
    end)

    it("stops when a block that makes a fluid is asked to be the column that makes an item of another", function()
      local root = {
        machine_count = 1, machine = "gadget-assembler", shape = {machine_size = 3, input_inserters = 2, output_inserters = 1},
        suppliers = {{plants = a_fluid_block()}, furnaces(1)},
      }

      assert.has_error(function() rows.build(root, NAMES) end, "rows: a block that makes a fluid cannot be the column that makes an item")
    end)

    it("stops when a column that takes no fluid, of two made ingredients, has a block that makes one", function()
      local root = gadget_column(a_fluid_block())
      root.fluid_supplier = a_fluid_block()

      assert.has_error(function() rows.build(root, NAMES) end, "rows: a column that takes no fluid has a block that makes one")
    end)

    it("stops when a step with one ingredient, that takes no fluid, has a block that makes one", function()
      local root = gadget_column(a_fluid_block())
      root.suppliers[1].shape.fluid_input = nil

      assert.has_error(function() rows.build(root, NAMES) end, "rows: a block that makes a fluid is taken only by the first stage of a column that takes a fluid")
    end)

    it("stops when a stage fed raw items has a block that makes a fluid", function()
      local root = furnaces(1)
      root.fluid_supplier = a_fluid_block()

      assert.has_error(function() rows.build(root, NAMES) end, "rows: a block that makes a fluid is taken only by the first stage of a column that takes a fluid")
    end)

    it("stops when the block says it is narrower than its pipe is", function()
      local block = a_fluid_block()
      block.width = 4 -- the pipe is in column 4

      assert.has_error(function() rows.build(barrel_column(block), NAMES) end, "rows: the pipes of a column that takes a fluid are not east of the block that makes it")
    end)

    it("stops when a step that stands beside the column that takes the fluid has a block that makes one", function()
      local beside = {
        machine_count = 1, machine = "gadget-assembler", shape = {machine_size = 3, input_inserters = 1, output_inserters = 1},
        suppliers = {barrel_column(nil)}, fluid_supplier = a_fluid_block(),
      }

      assert.has_error(function() rows.build(beside, NAMES) end, "rows: a block that makes a fluid is taken only by the first stage of a column that takes a fluid")
    end)
  end)
end)
