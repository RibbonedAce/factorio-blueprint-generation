-- spec/fluid_row_spec.lua
-- The row of machines that take a fluid and give one (see scripts/fluid_row.lua), drawn for a machine of 5 x 5 whose connections are the
-- ones of the oil refinery: the fluids it takes at columns 1 and 3 under it, the fluids it gives at columns 0, 2 and 4 above it.
-- Positions are TILES: the top-left tile an entity covers, with y growing down (see scripts/grid.lua).
---@diagnostic disable: undefined-field  -- luassert's `assert` has fields (`assert.are`, `assert.is_nil`, ...) the editor cannot see

local builders = require("spec.support.builders")
local grid = require("scripts.grid")
local fluid_row = require("scripts.fluid_row")
local validator = require("spec.support.blueprint_validator")

local NAMES = builders.NAMES
local east = defines.direction.east

-- The fluid boxes of the machine: two that take a fluid, under it, and three that give one, above it.
local function refinery_boxes()
  return {
    {production_type = "input", tiles = {{x = 1, y = 5}}},
    {production_type = "input", tiles = {{x = 3, y = 5}}},
    {production_type = "output", tiles = {{x = 0, y = -1}}},
    {production_type = "output", tiles = {{x = 2, y = -1}}},
    {production_type = "output", tiles = {{x = 4, y = -1}}},
  }
end

-- What `fluid_row.build` is asked for, with the changes the test says.
local function request(changes)
  return builders.merged({
    machine = "oil-refinery", recipe = "basic-oil-processing", size = 5, count = 2, boxes = refinery_boxes(),
    rows = {inputs = 5, outputs = -1},
    pipe = NAMES.pipe, pole = NAMES.pole, pole_supply_distance = 2.5, pole_wire_distance = 7.5,
  }, changes)
end

-- The top-left tiles of the entities of one name, as {x, y} in the order of the list; `size` is how many tiles a side of one covers.
local function tiles_of(entities, name, size)
  local tiles = {}
  for _, entity in ipairs(entities) do
    if entity.name == name then
      local tile = grid.top_left_tile(entity.position, size, size)
      tiles[#tiles + 1] = {tile.x, tile.y}
    end
  end
  return tiles
end

local range = builders.range

-- The columns of the pipes in a tile row, from the west.
local function pipe_columns(entities, row)
  return builders.columns_in_row(entities, NAMES.pipe, row)
end

describe("fluid_row", function()
  describe("rows_of, the rows of pipes of a machine", function()
    it("gives the row under the machine for what it takes and the row above it for what it gives", function()
      assert.are.same({inputs = 5, outputs = -1}, fluid_row.rows_of(refinery_boxes(), 5))
    end)

    it("gives the rows the other way round for a machine that takes its fluid from above", function()
      local boxes = {
        {production_type = "input", tiles = {{x = 2, y = -1}}},
        {production_type = "output", tiles = {{x = 2, y = 5}}},
      }

      assert.are.same({inputs = -1, outputs = 5}, fluid_row.rows_of(boxes, 5))
    end)

    it("leaves out a fluid box that takes and gives", function()
      local boxes = refinery_boxes()
      boxes[#boxes + 1] = {production_type = "input-output", tiles = {{x = 0, y = -5}}}

      assert.are.same({inputs = 5, outputs = -1}, fluid_row.rows_of(boxes, 5))
    end)

    it("refuses a machine whose two kinds of connection are on the same side", function()
      local boxes = {
        {production_type = "input", tiles = {{x = 1, y = 5}}},
        {production_type = "output", tiles = {{x = 3, y = 5}}},
      }

      assert.is_nil(fluid_row.rows_of(boxes, 5))
    end)

    it("refuses a machine with a connection at its side", function()
      local boxes = {
        {production_type = "input", tiles = {{x = -1, y = 2}}},
        {production_type = "output", tiles = {{x = 2, y = -1}}},
      }

      assert.is_nil(fluid_row.rows_of(boxes, 5))
    end)

    it("refuses a machine with a connection two tiles from it, which a pipe beside the machine does not reach", function()
      local boxes = {
        {production_type = "input", tiles = {{x = 1, y = 6}}},
        {production_type = "output", tiles = {{x = 2, y = -1}}},
      }

      assert.is_nil(fluid_row.rows_of(boxes, 5))
    end)

    it("refuses a machine with a connection inside it", function()
      local boxes = {
        {production_type = "input", tiles = {{x = 1, y = 2}}},
        {production_type = "output", tiles = {{x = 2, y = -1}}},
      }

      assert.is_nil(fluid_row.rows_of(boxes, 5))
    end)

    it("refuses a machine with a connection past the corner, one column beyond its east edge, or one before its west edge", function()
      local east = {{production_type = "input", tiles = {{x = 5, y = 5}}}, {production_type = "output", tiles = {{x = 2, y = -1}}}}
      local west = {{production_type = "input", tiles = {{x = -1, y = 5}}}, {production_type = "output", tiles = {{x = 2, y = -1}}}}

      assert.are.same({nil, nil}, {fluid_row.rows_of(east, 5), fluid_row.rows_of(west, 5)})
    end)

    it("takes a connection at the first and at the last column of the machine", function()
      local boxes = {
        {production_type = "input", tiles = {{x = 0, y = 5}}},
        {production_type = "output", tiles = {{x = 4, y = -1}}},
      }

      assert.are.same({inputs = 5, outputs = -1}, fluid_row.rows_of(boxes, 5))
    end)

    it("refuses a machine whose connections of one kind are in two rows", function()
      local boxes = {
        {production_type = "input", tiles = {{x = 1, y = 5}, {x = 3, y = -1}}},
        {production_type = "output", tiles = {{x = 2, y = -1}}},
      }

      assert.is_nil(fluid_row.rows_of(boxes, 5))
    end)

    it("refuses a machine that takes no fluid", function()
      local boxes = {{production_type = "output", tiles = {{x = 2, y = -1}}}}

      assert.is_nil(fluid_row.rows_of(boxes, 5))
    end)

    it("refuses a machine that gives no fluid", function()
      local boxes = {{production_type = "input", tiles = {{x = 1, y = 5}}}}

      assert.is_nil(fluid_row.rows_of(boxes, 5))
    end)
  end)

  describe("build", function()
    it("stands the machines side by side, under the row of pipes of what they give, from the top-left of the blueprint", function()
      local entities = fluid_row.build(request{count = 3})

      assert.are.same({{0, 1}, {5, 1}, {10, 1}}, tiles_of(entities, "oil-refinery", 5))
    end)

    it("sets the recipe of every machine", function()
      local entities = fluid_row.build(request{})

      assert.are.same({"basic-oil-processing", "basic-oil-processing"}, {entities[1].recipe, entities[2].recipe})
    end)

    it("runs the pipe of what the machines give along their top, from the first connection column to the last of the last machine", function()
      local entities = fluid_row.build(request{count = 2})

      assert.are.same(range(0, 9), pipe_columns(entities, 0))
    end)

    it("runs the pipe of what the machines take along their bottom, from the west edge to the last connection column", function()
      local entities = fluid_row.build(request{count = 2})

      assert.are.same(range(0, 8), pipe_columns(entities, 6)) -- the last connection is column 3 of the second machine: 5 + 3
    end)

    it("puts a pole under the middle column of each machine, beyond the pipes", function()
      local entities = fluid_row.build(request{count = 3})

      assert.are.same({{2, 7}, {7, 7}, {12, 7}}, tiles_of(entities, NAMES.pole, 1))
    end)

    it("wires each pole to the next", function()
      local entities = fluid_row.build(request{count = 3})

      local poles = builders.entities_named(entities, NAMES.pole)
      local copper = defines.wire_connector_id.pole_copper
      assert.are.same({{poles[1].entity_number, copper, poles[2].entity_number, copper}}, poles[1].wires)
      assert.are.same({{poles[2].entity_number, copper, poles[3].entity_number, copper}}, poles[2].wires)
      assert.is_nil(poles[3].wires)
    end)

    it("numbers the entities from 1 with no gap", function()
      local entities = fluid_row.build(request{count = 3})

      assert.has_consecutive_numbers(entities)
    end)

    it("makes a row of one machine", function()
      local entities = fluid_row.build(request{count = 1})

      assert.are.same({1, 1}, {#tiles_of(entities, "oil-refinery", 5), #tiles_of(entities, NAMES.pole, 1)})
    end)

    describe("for a machine that takes its fluid from above", function()
      local from_above = {inputs = -1, outputs = 5}

      it("puts the pipe of what the machines take above them and the poles above that, from the top-left of the blueprint", function()
        local entities = fluid_row.build(request{count = 2, rows = from_above})

        assert.are.same({{0, 2}, {5, 2}}, tiles_of(entities, "oil-refinery", 5)) -- under the pipes at row 1 and the poles at row 0
        assert.are.same({{2, 0}, {7, 0}}, tiles_of(entities, NAMES.pole, 1))
        assert.are.same(range(0, 8), pipe_columns(entities, 1))
      end)

      it("puts the pipe of what the machines give under them", function()
        local entities = fluid_row.build(request{count = 2, rows = from_above})

        assert.are.same(range(0, 9), pipe_columns(entities, 7))
      end)
    end)

    it("refuses a pole that reaches one tile, which does not power the machine from beyond its pipes", function()
      local too_short = function() fluid_row.build(request{pole_supply_distance = 1.5}) end

      assert.has_error(too_short, "fluid_row: a pole has to reach two tiles to power a machine from beyond its pipes")
    end)

    it("takes a wire exactly as long as a machine is wide, which reaches from the pole of one machine to the next", function()
      local exactly = function() fluid_row.build(request{pole_wire_distance = 5}) end

      assert.has_no.errors(exactly)
    end)

    it("takes a pole that reaches exactly two tiles", function()
      local exactly = function() fluid_row.build(request{pole_supply_distance = 2.5}) end

      assert.has_no.errors(exactly)
    end)

    it("refuses a wire that does not reach from the pole of one machine to the next", function()
      local too_short = function() fluid_row.build(request{pole_wire_distance = 4}) end

      assert.has_error(too_short, "fluid_row: a wire has to reach from the pole of one machine to the next")
    end)

    describe("checked by the validator", function()
      -- The catalog: a refinery of 5 x 5 with the connections of the boxes above, and the pipe and the pole.
      local function catalog()
        local entries = builders.a_catalog{}
        entries["oil-refinery"] = {
          kind = "machine", width = 5, height = 5, needs_power = true,
          fluid_connections = {input = {{x = 1, y = 5}, {x = 3, y = 5}}, output = {{x = 0, y = -1}, {x = 2, y = -1}, {x = 4, y = -1}}},
        }
        return entries
      end

      for _, count in ipairs({1, 2, 3, 4}) do
        it(string.format("passes for a row of %d machines: powered, wired, two networks of pipes, each with an open end", count), function()
          local entities = fluid_row.build(request{count = count})

          assert.are.same({}, validator.validate(entities, catalog()))
        end)
      end

      it("passes for the machines that take their fluid from above too", function()
        local entities = fluid_row.build(request{count = 2, rows = {inputs = -1, outputs = 5}})
        local entries = catalog()
        entries["oil-refinery"].fluid_connections = {input = {{x = 1, y = -1}, {x = 3, y = -1}}, output = {{x = 0, y = 5}, {x = 2, y = 5}, {x = 4, y = 5}}}

        assert.are.same({}, validator.validate(entities, entries))
      end)
    end)
  end)

  describe("turn, which stands the row from north to south", function()
    local function turned(count)
      local entities, entries = fluid_row.build(request{count = count})
      return entities, fluid_row.turn(entities, entries, "oil-refinery", 5)
    end

    it("moves the machines a quarter clockwise, one under the other, facing east", function()
      local entities = turned(2)

      local tiles = tiles_of(entities, "oil-refinery", 5)
      assert.are.same({{2, 0}, {2, 5}}, tiles)
      assert.are.same({east, east}, {entities[1].direction, entities[2].direction})
    end)

    it("moves the pipe that took the fluid in to the west column and the one that gave it out to the east column", function()
      local entities = turned(2)

      assert.are.same({range(0, 8), range(0, 9)}, {builders.rows_in_column(entities, NAMES.pipe, 1), builders.rows_in_column(entities, NAMES.pipe, 7)})
    end)

    it("moves the poles to the column west of the pipes, level with the middle of each machine", function()
      local entities = turned(2)

      assert.are.same({{0, 2}, {0, 7}}, tiles_of(entities, NAMES.pole, 1))
    end)

    it("gives the tiles where the pipes start and end: the north end of the west one and the south end of the east one", function()
      local _, entries = turned(2)

      assert.are.same({input = {x = 1, y = 0}, output = {x = 7, y = 9}}, entries)
    end)

    it("leaves the entities numbered and the wires of the poles to the same entities", function()
      local entities = turned(3)

      local poles = builders.entities_named(entities, NAMES.pole)
      assert.has_consecutive_numbers(entities)
      assert.are.same({poles[2].entity_number, poles[3].entity_number}, {poles[1].wires[1][3], poles[2].wires[1][3]})
    end)

    it("passes the validator, the machines facing east with their connections turned", function()
      local entities = turned(3)
      local entries = builders.a_catalog{}
      entries["oil-refinery"] = {
        kind = "machine", width = 5, height = 5, needs_power = true,
        fluid_connections = {input = {{x = 1, y = 5}, {x = 3, y = 5}}, output = {{x = 0, y = -1}, {x = 2, y = -1}, {x = 4, y = -1}}},
      }

      assert.are.same({}, validator.validate(entities, entries))
    end)
  end)

end)
