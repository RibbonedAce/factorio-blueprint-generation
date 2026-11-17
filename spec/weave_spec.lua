-- spec/weave_spec.lua
-- The pattern of the woven input belts of a column of 3 x 3 machines (scripts/weave.lua), drawn the way the other specs draw
-- layouts (spec/support/picture.lua): the belts run down, row 0 is the row of the first inserter. The columns drawn are the
-- tile columns -4 to 1: the trunk of belt c, where it goes under, the trunk of belt b, the taps, the inner column and the
-- inserters. ( ) are the entrance and the exit of an underground belt that goes east, n u of one that goes down, S the two
-- halves of a splitter, + a pole and } an inserter. The letter after a row is the belt that row shows in the inner column.
---@diagnostic disable: undefined-field  -- luassert's `assert` has fields (`assert.are`, `assert.is_nil`, ...) the editor cannot see

local weave = require("scripts.weave")

local FIRST_COLUMN, LAST_COLUMN = -4, 1

-- What each kind of tile is drawn as.
local function glyph_of(tile)
  if tile.kind == "splitter" then
    return "S"
  elseif tile.kind == "belt" then
    return tile.way == "east" and ">" or "v"
  elseif tile.kind == "entrance" then
    return tile.way == "east" and "(" or "n"
  end
  return tile.way == "east" and ")" or "u"
end

-- The pattern as text, one line for each row from the first any tile or pole is in to the last row of the machines.
local function drawn(plan, pole_rows)
  local columns = {}
  local function put(column, row, glyph)
    columns[row] = columns[row] or {}
    assert(columns[row][column] == nil, "two things on column " .. column .. ", row " .. row)
    columns[row][column] = glyph
  end
  for _, tile in ipairs(plan.tiles) do
    put(tile.column, tile.row, glyph_of(tile))
    if tile.kind == "splitter" then
      put(tile.column + 1, tile.row, "S")
    end
  end
  local first = plan.first_row
  for _, row in ipairs(pole_rows) do
    put(weave.TAPS, row, "+")
    first = math.min(first, row)
  end
  for _, inserter in ipairs(plan.inserters) do
    put(weave.INNER + 1, inserter.row, "}")
  end
  local lines = {}
  for row = first, plan.row_count - 1 do
    local line = {}
    for column = FIRST_COLUMN, LAST_COLUMN do
      line[#line + 1] = columns[row] and columns[row][column] or "."
    end
    lines[#lines + 1] = table.concat(line) .. (plan.rows[row] and "  " .. plan.rows[row] or "")
  end
  return lines
end

-- The rows with an inserter on a belt.
local function rows_of_belt(plan, belt)
  local rows = {}
  for _, inserter in ipairs(plan.inserters) do
    if inserter.belt == belt then
      rows[#rows + 1] = inserter.row
    end
  end
  return rows
end

describe("weave", function()
  describe("three belts, one inserter on each", function()
    local counts = {a = 1, b = 1, c = 1}

    it("draws the pattern of the owner's blueprint for four machines: the belts show a b c, c b a, a b c, c b a", function()
      local plan = weave.plan(counts, 4)

      assert.are.same({
        "...+..",
        "SSSSn}  a",
        "vnv>>}  b",
        ">(v)v}  c",
        "..SS>}  c",
        "..v>>}  b",
        ".uv+u}  a",
        "SSSSn}  a",
        "v.v>>}  b",
        ">(v)v}  c",
        "..SS>}  c",
        "...>>}  b",
        "...+u}  a",
      }, drawn(plan, weave.pole_rows(plan, 3)))
    end)

    it("draws one machine: belt a ends in a tile that turns east, since nothing may run into the tiles of the others", function()
      local plan = weave.plan(counts, 1)

      assert.are.same({
        "...+..",
        "SSSS>}  a",
        "v..>>}  b",
        ">(.)>}  c",
      }, drawn(plan, weave.pole_rows(plan, 3)))
    end)

    it("draws three machines: the last has no machine after it to pair its row of belt c with", function()
      local plan = weave.plan(counts, 3)

      assert.are.same({
        "...+..",
        "SSSSn}  a",
        "vnv>>}  b",
        ">(v)v}  c",
        "..SS>}  c",
        "..v>>}  b",
        ".uv+u}  a",
        "SSSS>}  a",
        "v..>>}  b",
        ">(.)>}  c",
      }, drawn(plan, weave.pole_rows(plan, 3)))
    end)

    it("puts an inserter on every row, one for each belt of every machine", function()
      local plan = weave.plan(counts, 2)

      assert.are.same({{0, 5}, {1, 4}, {2, 3}}, {rows_of_belt(plan, "a"), rows_of_belt(plan, "b"), rows_of_belt(plan, "c")})
    end)

    it("starts every belt in row 0: the belts that bring them end in the first tile of each", function()
      local plan = weave.plan(counts, 4)

      assert.are.same({a = 0, b = 0, c = 0}, plan.starts)
    end)

    it("needs poles that reach three rows, with the tiles that stay free: one above the first row and one in every sixth row", function()
      local plan = weave.plan(counts, 4)

      assert.are.same({-1, 5, 11}, weave.pole_rows(plan, 3))
    end)

    it("is refused for a pole that reaches only two rows, which leaves a row of inserters with no pole in reach", function()
      local plan = weave.plan(counts, 4)

      assert.has_error(function() weave.pole_rows(plan, 2) end)
    end)
  end)

  describe("two belts, two inserters on belt a", function()
    local counts = {a = 2, b = 1}

    it("draws three machines: belt a shows in the first and the last row of every machine, and goes under belt b between", function()
      local plan = weave.plan(counts, 3)

      assert.are.same({
        "..SSn}  a",
        "..v>>}  b",
        "..v+u}  a",
        "..SSn}  a",
        "..v>>}  b",
        "..v+u}  a",
        "..SSn}  a",
        "...>>}  b",
        "...+u}  a",
      }, drawn(plan, weave.pole_rows(plan, 2)))
    end)

    it("puts an inserter on every row", function()
      local plan = weave.plan(counts, 2)

      assert.are.same({{0, 2, 3, 5}, {1, 4}}, {rows_of_belt(plan, "a"), rows_of_belt(plan, "b")})
    end)

    it("is also the pattern for one inserter on each belt, with the second inserter of belt a left out", function()
      local plan = weave.plan({a = 1, b = 1}, 2)

      assert.are.same({
        "..SSn}  a",
        "..v>>}  b",
        "..v+u.  a",
        "..SSn}  a",
        "...>>}  b",
        "....u.  a",
      }, drawn(plan, weave.pole_rows(plan, 2)))
    end)

    it("needs a pole where every third row has a free tile, which a pole that reaches two rows does", function()
      local plan = weave.plan(counts, 3)

      assert.are.same({2, 5, 8}, weave.pole_rows(plan, 2))
    end)

    it("needs fewer poles for a pole that reaches three rows", function()
      local plan = weave.plan(counts, 3)

      assert.are.same({2, 8}, weave.pole_rows(plan, 3))
    end)

    it("starts belt a and belt b in row 0", function()
      local plan = weave.plan(counts, 3)

      assert.are.same({a = 0, b = 0}, plan.starts)
    end)
  end)

  describe("two belts, two inserters on belt b", function()
    local counts = {a = 1, b = 2}

    it("draws four machines: belt b shows in four rows at a time, and belt a comes up in pairs of rows, an exit and an entrance", function()
      local plan = weave.plan(counts, 4)

      assert.are.same({
        "..SSn.",
        "..v>v}  b",
        "..v.>}  b",
        "..v+u}  a",
        "..SSn}  a",
        "..v>v}  b",
        "..v.v}  b",
        "..v.v}  b",
        "..v+>}  b",
        "..v.u}  a",
        "..SS>}  a",
        "...>v}  b",
        "...+>}  b",
      }, drawn(plan, weave.pole_rows(plan, 2)))
    end)

    it("draws one machine: belt a comes up from an entrance in the row before the machine", function()
      local plan = weave.plan(counts, 1)

      assert.are.same({
        "..SSn.",
        "...>v}  b",
        "....>}  b",
        "...+u}  a",
      }, drawn(plan, weave.pole_rows(plan, 2)))
    end)

    it("starts both belts one row before the first row, where the belt that brings it ends", function()
      local plan = weave.plan(counts, 4)

      assert.are.same({a = -1, b = -1}, plan.starts)
    end)

    it("puts two inserters on belt b and one on belt a in every machine", function()
      local plan = weave.plan(counts, 2)

      assert.are.same({{2, 3}, {0, 1, 4, 5}}, {rows_of_belt(plan, "a"), rows_of_belt(plan, "b")})
    end)
  end)

  describe("the rows of the taps column that hold nothing", function()
    it("are the rows a pole may take: the first row, and the rows with no splitter, no tap and no exit", function()
      local plan = weave.plan({a = 2, b = 1}, 2)

      assert.are.same({-1, 2, 5}, plan.free_taps)
    end)
  end)

  describe("every number of machines", function()
    for _, counts in ipairs({{a = 1, b = 1, c = 1}, {a = 2, b = 1}, {a = 1, b = 2}, {a = 1, b = 1}}) do
      it("is drawn without two things on a tile, for " .. counts.a .. ", " .. counts.b .. " and " .. (counts.c or 0) .. " inserters on the belts", function()
        local lines
        for machines = 1, 12 do
          local plan = weave.plan(counts, machines)
          lines = drawn(plan, {})
        end

        assert.is_true(#lines > 0)
      end)
    end
  end)

  describe("the rows of the poles, for a plan with its inserters and the free tiles of its taps column", function()
    it("takes a free tile exactly as many rows away as the pole reaches, when it is the only one in reach", function()
      local plan = {inserters = {{row = 4, belt = "a"}}, free_taps = {1}}

      assert.are.same({1}, weave.pole_rows(plan, 3))
    end)

    it("is refused when the nearest free tile is one row further than the pole reaches", function()
      local plan = {inserters = {{row = 5, belt = "a"}}, free_taps = {1}}

      assert.has_error(function() weave.pole_rows(plan, 3) end, "weave: no free tile beside the belts reaches the inserter in row 5: the pole reaches 3 rows")
    end)
  end)

  describe("counts it cannot draw", function()
    local TWO_BELTS = "weave: two belts need an inserter each and at most three in all"

    it("refuses two inserters on both of two belts, which need four of the three rows", function()
      assert.has_error(function() weave.plan({a = 2, b = 2}, 2) end, TWO_BELTS)
    end)

    it("refuses three belts with more than one inserter on one of them", function()
      assert.has_error(function() weave.plan({a = 1, b = 1, c = 2}, 2) end, "weave: three belts get one inserter each")
    end)

    it("refuses a single belt, which needs no weave", function()
      assert.has_error(function() weave.plan({a = 2}, 2) end, TWO_BELTS)
    end)

    it("refuses belt b alone, since belt a has to carry something", function()
      assert.has_error(function() weave.plan({b = 2}, 2) end, TWO_BELTS)
    end)

    it("refuses two belts when belt b has no inserter", function()
      assert.has_error(function() weave.plan({a = 2, b = 0}, 2) end, TWO_BELTS)
    end)

    it("refuses two belts when belt a has no inserter", function()
      assert.has_error(function() weave.plan({a = 0, b = 2}, 2) end, TWO_BELTS)
    end)
  end)
end)
