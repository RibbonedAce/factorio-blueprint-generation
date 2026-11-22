-- spec/input_side_spec.lua
-- The input side of a column of machines that take a fluid through pipe connections on the side they face (see scripts/input_side.lua), for
-- the assembling machine that makes concrete and the chemical plants. Positions are TILES: the top-left tile an entity covers, with y growing
-- down (see scripts/grid.lua). The pictures show the columns 0 to 6: 1 the tunnel column (`w` the end of an underground pipe that opens
-- west, `+` a pole), 2 the belt, 3 the inserters and the ends that open east (`e`), 4 to 6 the machines. The machines are 3 x 3.
---@diagnostic disable: undefined-field  -- luassert's `assert` has fields (`assert.are`, ...) the editor cannot see

local builders = require("spec.support.builders")
local grid = require("scripts.grid")
local input_side = require("scripts.input_side")
local picture = require("spec.support.picture")

local NAMES = builders.NAMES
local west = defines.direction.west

-- A column of `count` machines of 3 x 3, one under the other from the row 0.
local function column(count)
  return {first_row = 0, spacing = 3, size = 3, count = count}
end

-- A column of `count` machines of 7 x 7, one under the other from the row 0.
local function tall(count)
  return {first_row = 0, spacing = 7, size = 7, count = count}
end

-- What `input_side` is asked for `count` machines of 3 x 3 that take their fluid at the rows `connections` say, with a small pole.
local function request(count, connections, changes)
  return builders.merged({
    column = column(count), connections = connections, inserters = 1, inserter = NAMES.inserter, pipe_to_ground = NAMES.pipe_to_ground,
    pole = NAMES.pole, pole_reach = 2, pole_wire_distance = 7.5, inserter_column = 3, tunnel_column = 1,
  }, changes)
end

-- The {column, row} of each entity.
local function tiles_of(entities)
  local tiles = {}
  for _, entity in ipairs(entities) do
    local tile = grid.top_left_tile(entity.position)
    tiles[#tiles + 1] = {tile.x, tile.y}
  end
  return tiles
end

-- The input side of the request drawn with its machines (an entity of 3 x 3 for each, in the column 4), the rows 0 to `last_row`.
local function drawn(asked, last_row)
  local entities = {}
  for index = 0, asked.column.count - 1 do
    entities[#entities + 1] = {name = "machine", position = grid.position(4, index * 3, 3, 3)}
  end
  input_side.add(entities, asked)
  return picture.draw(entities, {machine = {size = 3, glyph = "M"}}, 0, 0, 6, last_row)
end

describe("input_side", function()
  describe("free_rows", function()
    it("gives the rows of a machine that no connection takes, from the top", function()
      assert.are.same({0, 2}, input_side.free_rows(3, {1}))
      assert.are.same({1}, input_side.free_rows(3, {0, 2}))
      assert.are.same({1, 2, 3}, input_side.free_rows(5, {0, 4}))
    end)

    it("gives every row of a machine that has no connection", function()
      assert.are.same({0, 1, 2, 3, 4}, input_side.free_rows(5, {}))
    end)
  end)

  describe("inserter_rows", function()
    it("puts the inserter of the first machine of a pair in its first free row and that of the second in its last free row", function()
      local rows = {}
      for index = 0, 3 do
        rows[#rows + 1] = input_side.inserter_rows(column(4), {1}, index, 1)[1]
      end

      assert.are.same({0, 5, 6, 11}, rows) -- the machines start at the rows 0, 3, 6 and 9
    end)

    it("takes both free rows of a machine whose connection is in the middle row, for two inserters", function()
      assert.are.same({{0, 2}, {3, 5}}, {input_side.inserter_rows(column(2), {1}, 0, 2), input_side.inserter_rows(column(2), {1}, 1, 2)})
    end)

    it("takes the one free row of a machine whose connections are in its top and its bottom row, whichever machine it is", function()
      local rows = {}
      for index = 0, 2 do
        rows[#rows + 1] = input_side.inserter_rows(column(3), {0, 2}, index, 1)[1]
      end

      assert.are.same({1, 4, 7}, rows)
    end)

    it("takes the first two free rows of the first machine of a pair and the last two of the second, when more rows are free", function()
      -- the second machine starts at the row 7: its free rows are 8 to 12
      assert.are.same({{1, 2}, {11, 12}}, {input_side.inserter_rows(tall(2), {0, 6}, 0, 2), input_side.inserter_rows(tall(2), {0, 6}, 1, 2)})
    end)

    it("counts from the first row of the column, which need not be the row 0", function()
      local lower = {first_row = 4, spacing = 3, size = 3, count = 1}

      assert.are.same({4}, input_side.inserter_rows(lower, {1}, 0, 1))
    end)

    it("refuses more inserters than a machine has free rows", function()
      local build = function() input_side.inserter_rows(column(1), {0, 2}, 0, 2) end

      assert.has_error(build, "input_side: a machine has fewer rows without a pipe connection than input inserters")
    end)
  end)

  describe("pole_rows", function()
    it("puts a pole in the last free tile that reaches the first inserter, and one more for each inserter that pole does not reach", function()
      -- one inserter each, a connection in the middle: the inserters are in the rows 0, 5 and 6; the tiles of the tunnel column that no
      -- pipe takes are the rows 0, 2, 3, 5, 6 and 8. A pole at the row 2 reaches the rows 0 to 4, so the inserter in the row 5 needs the
      -- pole at the row 6, which reaches 4 to 8.
      assert.are.same({2, 6}, input_side.pole_rows(request(3, {1})))
    end)

    it("needs fewer poles when a pole reaches further, a medium pole's three rows", function()
      assert.are.same({3}, input_side.pole_rows(request(3, {1}, {pole_reach = 3, pole_wire_distance = 9})))
    end)

    it("puts a pole beside each plant when the one free tile of each is all there is, for plants with a connection at the top and the bottom row", function()
      assert.are.same({1, 4, 7}, input_side.pole_rows(request(3, {0, 2})))
    end)

    it("keeps each pole within a wire of the one before it: nearer than the last tile that reaches the inserter", function()
      -- two machines of 7 x 7 with a connection in the first and the last row: the inserters are in the rows 1 and 12; poles that reach 3
      -- rows stand at the row 4 for the first and, with a wire of 9, at the row 12 for the second (4 + 9 is 13); with a wire of 7 the row 11
      local wide = request(2, {0, 6}, {column = tall(2), pole_reach = 3, pole_wire_distance = 9})
      local narrow = request(2, {0, 6}, {column = tall(2), pole_reach = 3, pole_wire_distance = 7})

      assert.are.same({{4, 12}, {4, 11}}, {input_side.pole_rows(wide), input_side.pole_rows(narrow)})
    end)

    it("refuses poles that reach one tile, which does not reach the inserters across the belt", function()
      local build = function() input_side.pole_rows(request(2, {1}, {pole_reach = 1})) end

      assert.has_error(build, "input_side: a pole in the tunnel column has to reach the inserters, 2 columns away")
    end)

    it("puts a pole that only bridges the wire when the inserters of two machines stand further apart than it reaches", function()
      -- the inserters are in the rows 1 and 12 and the free tiles of the second machine are the rows 8 to 12: with poles that reach 2 rows and
      -- a wire of 6, the pole for the second inserter (in the rows 10 to 12) is more than 6 from the first (in the row 3), so one stands
      -- in the row 9 between them
      assert.are.same({3, 9, 12}, input_side.pole_rows(request(2, {0, 6}, {column = tall(2), pole_wire_distance = 6})))
    end)

    it("refuses a wire too short for any free tile to be within it of the pole before", function()
      local build = function() input_side.pole_rows(request(2, {0, 6}, {column = tall(2), pole_wire_distance = 0.5})) end

      assert.has_error(build, "weave: no free tile beside the belts reaches the inserter in row 12 within 0.5 tiles of the pole before it: the pole reaches 2 rows")
    end)
  end)

  describe("add_tunnels", function()
    it("puts the end that opens east in the column of the inserters and the end that opens west in the tunnel column, at every connection", function()
      local entities = {}

      input_side.add_tunnels(entities, request(2, {0, 2}))

      assert.are.same({{3, 0}, {1, 0}, {3, 2}, {1, 2}, {3, 3}, {1, 3}, {3, 5}, {1, 5}}, tiles_of(entities))
      assert.are.same({"east", "west"}, {entities[1].direction == defines.direction.east and "east", entities[2].direction == west and "west"})
    end)
  end)

  describe("add_machine_inserters", function()
    it("puts the inserters of one machine in its free rows, facing the belt they take from", function()
      local entities = {}

      input_side.add_machine_inserters(entities, request(2, {1}, {inserters = 2}), 1)

      assert.are.same({{3, 3}, {3, 5}}, tiles_of(entities))
      assert.are.same({west, west}, {entities[1].direction, entities[2].direction})
    end)
  end)

  describe("add", function()
    it("draws two machines with a connection in the middle row: an inserter each, in the first free row of the first and the last of the second", function()
      assert.are.same({
        "...}MMM",
        ".w.eMMM",
        ".+..MMM",
        "....MMM",
        ".w.eMMM",
        ".+.}MMM",
      }, drawn(request(2, {1}), 5))
    end)

    it("draws two machines with two inserters each, in the top and the bottom row", function()
      assert.are.same({
        "...}MMM",
        ".w.eMMM",
        ".+.}MMM",
        "...}MMM",
        ".w.eMMM",
        ".+.}MMM",
      }, drawn(request(2, {1}, {inserters = 2}), 5))
    end)

    it("draws two plants with a connection in the top and the bottom row: the inserter and the pole in the middle row of each", function()
      assert.are.same({
        ".w.eMMM",
        ".+.}MMM",
        ".w.eMMM",
        ".w.eMMM",
        ".+.}MMM",
        ".w.eMMM",
      }, drawn(request(2, {0, 2}), 5))
    end)

    it("gives the poles, wired from the top down", function()
      local entities = {}

      local poles = input_side.add(entities, request(3, {0, 2}))

      assert.are.same({{1, 1}, {1, 4}, {1, 7}}, tiles_of(poles))
      assert.are.same({{poles[1].entity_number, defines.wire_connector_id.pole_copper, poles[2].entity_number, defines.wire_connector_id.pole_copper}}, poles[1].wires)
      assert.are.same({{poles[2].entity_number, defines.wire_connector_id.pole_copper, poles[3].entity_number, defines.wire_connector_id.pole_copper}}, poles[2].wires)
    end)

    it("numbers the entities from 1 with no gap", function()
      local entities = {}

      input_side.add(entities, request(4, {1}, {inserters = 2}))

      assert.has_consecutive_numbers(entities)
    end)
  end)
end)
