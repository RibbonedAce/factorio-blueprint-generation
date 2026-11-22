-- spec/output_side_spec.lua
-- The output side of a column of machines: where the inserters, the poles and the belt go, for the assembling machines of scripts/layout.lua
-- and the plants that make an item (see scripts/output_side.lua). Positions are TILES: the top-left tile an entity covers, with y growing
-- down (see scripts/grid.lua). The machines are 3 x 3 unless the test says otherwise.
---@diagnostic disable: undefined-field  -- luassert's `assert` has fields (`assert.are`, ...) the editor cannot see

local builders = require("spec.support.builders")
local grid = require("scripts.grid")
local output_side = require("scripts.output_side")

local NAMES = builders.NAMES
local east, south, west = defines.direction.east, defines.direction.south, defines.direction.west

-- A column of `count` machines of 3 x 3, one under the other from the row 0.
local function column(count)
  return {first_row = 0, spacing = 3, size = 3, count = count}
end

-- The belt of a winding request as "column,row direction" for each tile, in a table by that key.
local function belt_of(inserter_rows, end_row)
  local tiles, end_column = output_side.winding_tiles({inserter_rows = inserter_rows, inner = 0, outer = 1, start_row = inserter_rows[1] - 1, end_row = end_row})
  local found = {}
  for _, tile in ipairs(tiles) do
    found[string.format("%d,%d", tile.column, tile.row)] = tile.direction
  end
  return found, end_column, #tiles
end

describe("output_side", function()
  describe("machine_top", function()
    it("counts from the first row by the spacing, which is more than the size for machines with a row of poles between them", function()
      local spaced = {first_row = 1, spacing = 4, size = 3, count = 3}

      assert.are.same({1, 5, 9}, {output_side.machine_top(spaced, 0), output_side.machine_top(spaced, 1), output_side.machine_top(spaced, 2)})
    end)
  end)

  describe("inserter_top", function()
    it("puts the inserters of the first machine of a pair in its top rows and those of the second in its bottom rows", function()
      local plain, double = {}, {}
      for index = 0, 3 do
        plain[#plain + 1], double[#double + 1] = output_side.inserter_top(column(4), index, 1), output_side.inserter_top(column(4), index, 2)
      end

      assert.are.same({{0, 5, 6, 11}, {0, 4, 6, 10}}, {plain, double})
    end)

    it("leaves a machine without a partner, the last of an odd number, like the first", function()
      assert.are.equal(6, output_side.inserter_top(column(3), 2, 1))
    end)
  end)

  describe("inserter_rows", function()
    it("gives every inserter of every machine, top to bottom", function()
      assert.are.same({0, 1, 4, 5, 6, 7}, output_side.inserter_rows(column(3), 2))
      assert.are.same({0, 5, 6}, output_side.inserter_rows(column(3), 1))
    end)
  end)

  describe("pole_plan", function()
    it("puts the pole of a machine under its inserters when they are in its top rows and above them when they are in its bottom rows", function()
      local plan = output_side.pole_plan(column(3), 2, 2)

      assert.are.same({[0] = 2, [1] = 3, [2] = 8}, plan)
    end)

    it("leaves out the pole of a machine whose inserters a pole above it reaches", function()
      -- one inserter each: the poles at the rows 1 and 4; the third machine's inserter, in the row 6, is two rows from the pole at the row 4
      assert.are.same({[0] = 1, [1] = 4}, output_side.pole_plan(column(3), 1, 2))
    end)

    it("leaves out more with a pole that reaches further, a medium pole's three tiles", function()
      assert.are.same({[0] = 1, [1] = 4, [3] = 10}, output_side.pole_plan(column(4), 1, 3))
    end)

    it("makes the poles reach every row of a machine when it asks, which a full side on the other side of it needs", function()
      assert.are.same({[0] = 1, [1] = 4, [2] = 7}, output_side.pole_plan(column(3), 1, 2, true))
    end)
  end)

  describe("longest_wire", function()
    it("is the most rows between two poles of the plan, for one inserter or two: 6 for machines of 3 x 3 and a pole of two tiles", function()
      assert.are.equal(6, output_side.longest_wire(3, 2))
    end)

    it("grows with the size of the machines: 14 for machines of 7 x 7", function()
      assert.are.equal(14, output_side.longest_wire(7, 3))
    end)

    it("is twice the size for machines of 5 x 5 and a pole of two tiles", function()
      assert.are.equal(10, output_side.longest_wire(5, 2))
    end)

    it("counts the first gap too, which can be longer than all the ones after it: 21 for machines of 3 x 3 and a pole of 18 tiles", function()
      -- the poles with one inserter each stand in the second row of machines 0, 7, 13, 19, ... (rows 1, 22, 40, 58): 21 apart, then 18
      assert.are.equal(21, output_side.longest_wire(3, 18))
    end)

    it("goes on until the poles repeat, however far a pole reaches: 24 for machines of 3 x 3 and a pole of 20 tiles, which a pole does not repeat in the first sixteen machines", function()
      -- the poles with one inserter each stand in the second row of machines 0, 7, 15, 23, ... (rows 1, 22, 46, 70): 21 apart, then 24
      assert.are.equal(24, output_side.longest_wire(3, 20))
    end)
  end)

  describe("winds", function()
    it("winds for machines of 3 x 3 with two inserters each", function()
      assert.is_true(output_side.winds(3, 2, 1, false))
    end)

    it("winds with one inserter each when there are two machines and the caller allows it", function()
      assert.are.same({true, false, false}, {output_side.winds(3, 1, 2, true), output_side.winds(3, 1, 1, true), output_side.winds(3, 1, 2, false)})
    end)

    it("does not wind for machines of another size", function()
      assert.are.same({false, false}, {output_side.winds(2, 2, 4, true), output_side.winds(5, 2, 4, true)})
    end)
  end)

  describe("reflected", function()
    it("gives the rows of the inserters of a belt that runs north as the belt that runs south sees them: each row reflected in the mirror, from the top down", function()
      assert.are.same({0, 2, 3}, output_side.reflected({7, 8, 10}, 10))
    end)
  end)

  describe("winding_tiles", function()
    it("curves east at the first inserter and side-loads at the second, for the two inserters of one machine", function()
      local belt, end_column, count = belt_of({0, 1}, 3)

      assert.are.same({south, east, south, east, south, south}, {belt["0,-1"], belt["0,0"], belt["1,0"], belt["0,1"], belt["1,1"], belt["1,2"]})
      assert.are.same({1, 6}, {end_column, count})
    end)

    it("makes a seam of one tile for an inserter alone", function()
      local belt, end_column, count = belt_of({0}, 2)

      assert.are.same({south, east, south, south}, {belt["0,-1"], belt["0,0"], belt["1,0"], belt["1,1"]})
      assert.are.same({1, 4}, {end_column, count})
    end)

    it("hops back to the outer column in a row to spare between two seams, so that the belt ends there", function()
      local belt, end_column = belt_of({0, 1, 3, 4}, 6)

      -- the second seam turns the belt west in the row 4, and the row 5 is spare: the belt hops east
      assert.are.same({east, south, west, east, south}, {belt["0,3"], belt["1,3"], belt["1,4"], belt["0,5"], belt["1,5"]})
      assert.are.equal(1, end_column)
    end)

    it("ends in the inner column when the last seam turns the belt west and no row is left, as for machines whose inserters are in their bottom rows", function()
      local belt, end_column = belt_of({0, 1, 4, 5}, 6)

      assert.are.same({south, west}, {belt["0,5"], belt["1,5"]})
      assert.are.equal(0, end_column)
    end)

    it("makes the machines fill the lanes in turn when they have one inserter each: a curve, a stub, the curve where the belt turns west, a stub", function()
      local belt, end_column = belt_of({0, 5, 6, 11}, 12)

      -- the first machine's inserter drops on the curve in the row 0; the second's, in the row 5, on a stub that side-loads the belt coming
      -- down the outer column; the third's, in the row 6, on the curve where the belt turns west into the inner column; the fourth's, in the
      -- row 11, is alone at the end: a stub again, which leaves the belt in the outer column
      assert.are.same({east, east, south, west}, {belt["0,0"], belt["0,5"], belt["1,5"], belt["1,6"]})
      assert.are.same({south, east, east}, {belt["0,6"], belt["0,7"], belt["0,11"]})
      assert.are.equal(1, end_column)
    end)
  end)

  describe("add", function()
    -- What `output_side.add` is asked for `count` machines of 3 x 3, the inserters in the column 10.
    local function request(count, changes)
      return builders.merged({
        column = column(count), inserters = 1, winds = false, inserter = NAMES.inserter, belt = NAMES.belt, pole = NAMES.pole,
        pole_reach = 2, pole_wire_distance = 7.5, inserter_column = 10,
      }, changes)
    end

    -- The tiles, as {x, y}, of the entities with the name, sorted by row.
    local function tiles_of(entities, name)
      local found = {}
      for _, entity in ipairs(entities) do
        if entity.name == name then
          local tile = grid.top_left_tile(entity.position)
          found[#found + 1] = {tile.x, tile.y}
        end
      end
      table.sort(found, function(first, second) return first[2] < second[2] or (first[2] == second[2] and first[1] < second[1]) end)
      return found
    end

    it("puts the inserters where the rule says, facing the machines they take from", function()
      local entities = {}

      output_side.add(entities, request(3))

      assert.are.same({{10, 0}, {10, 5}, {10, 6}}, tiles_of(entities, NAMES.inserter))
      assert.are.same({west, west, west}, {entities[1].direction, entities[2].direction, entities[3].direction})
    end)

    it("puts the poles of the plan in the column of the inserters, each wired to the one before it", function()
      local entities = {}

      local poles = output_side.add(entities, request(3))

      assert.are.same({{10, 1}, {10, 4}}, tiles_of(entities, NAMES.pole))
      assert.are.same({{poles[1].entity_number, defines.wire_connector_id.pole_copper, poles[2].entity_number, defines.wire_connector_id.pole_copper}}, poles[1].wires)
    end)

    it("runs a plain belt south beside the inserters from the first row to the last row of the last machine", function()
      local entities = {}

      local _, belt_column = output_side.add(entities, request(3))

      assert.are.equal(11, belt_column)
      assert.are.same({{11, 0}, {11, 1}, {11, 2}, {11, 3}, {11, 4}, {11, 5}, {11, 6}, {11, 7}, {11, 8}}, tiles_of(entities, NAMES.belt))
    end)

    it("winds the belt in the two columns when it says so, and says the column the belt ends in", function()
      local entities = {}

      local _, belt_column = output_side.add(entities, request(2, {inserters = 2, winds = true}))

      -- the inserters in the rows 0, 1, 4 and 5: the belt ends in the inner column, the second seam having turned it west
      assert.are.same({{10, 0}, {10, 1}, {10, 4}, {10, 5}}, tiles_of(entities, NAMES.inserter))
      assert.are.same({11, {11, -1}}, {belt_column, tiles_of(entities, NAMES.belt)[1]})
    end)

    it("takes a wire exactly as long as the poles of the plan are apart", function()
      local build = function() output_side.add({}, request(3, {pole_wire_distance = 3})) end

      assert.has_no.errors(build)
    end)

    it("refuses a wire that does not reach from one pole to the next", function()
      local build = function() output_side.add({}, request(3, {pole_wire_distance = 2.5})) end

      assert.has_error(build, "output_side: a wire has to reach from the pole of one machine to the next")
    end)

    it("numbers the entities from 1 with no gap", function()
      local entities = {}

      output_side.add(entities, request(4, {inserters = 2, winds = true}))

      assert.has_consecutive_numbers(entities)
    end)
  end)
end)
