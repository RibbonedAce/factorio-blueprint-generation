-- spec/weave_spec.lua
-- The pattern of the woven input belts of a column of 3 x 3 machines (scripts/weave.lua), drawn the way the other specs draw
-- layouts (spec/support/picture.lua): the belts run down, row 0 is the row of the first inserter. The columns drawn are the
-- tile columns -4 to 1: the trunk of belt c, where it goes under, the trunk of belt b, the taps, the inner column and the
-- inserters. ( ) are the entrance and the exit of an underground belt that goes east, n u of one that goes down, S the two
-- halves of a splitter, + a pole and } an inserter. The letter after a row is the belt that row shows in the inner column.
-- The pattern for machines with a pipe is drawn the same way (its trunk of belt b is in column -1, and < is a belt that
-- goes west).
---@diagnostic disable: undefined-field  -- luassert's `assert` has fields (`assert.are`, `assert.is_nil`, ...) the editor cannot see

local weave = require("scripts.weave")

local FIRST_COLUMN, LAST_COLUMN = -4, 1

-- What each kind of tile is drawn as.
local function glyph_of(tile)
  if tile.kind == "splitter" then
    return "S"
  elseif tile.kind == "belt" then
    return ({east = ">", west = "<"})[tile.way] or "v"
  elseif tile.kind == "entrance" then
    return tile.way == "east" and "(" or "n"
  end
  return tile.way == "east" and ")" or "u"
end

-- The pattern as text, one line for each row from the first any tile or pole is in to the last any is in or the last row of the machines.
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
  local first, last = plan.first_row, plan.row_count - 1
  for _, tile in ipairs(plan.tiles) do
    last = math.max(last, tile.row)
  end
  for _, row in ipairs(pole_rows) do
    put(plan.pole_column, row, "+")
    first, last = math.min(first, row), math.max(last, row)
  end
  for _, inserter in ipairs(plan.inserters) do
    put(weave.INNER + 1, inserter.row, "}")
  end
  local lines = {}
  for row = first, last do
    local line = {}
    for column = FIRST_COLUMN, LAST_COLUMN do
      line[#line + 1] = columns[row] and columns[row][column] or "."
    end
    lines[#lines + 1] = table.concat(line) .. (plan.rows[row] and "  " .. plan.rows[row] or "")
  end
  return lines
end

-- The rows of the inserters that no pole of `pole_rows` powers: those further than `reach` rows from every pole.
local function unpowered_rows(plan, pole_rows, reach)
  local missing = {}
  for _, inserter in ipairs(plan.inserters) do
    local powered = false
    for _, row in ipairs(pole_rows) do
      powered = powered or math.abs(row - inserter.row) <= reach
    end
    if not powered then
      missing[#missing + 1] = inserter.row
    end
  end
  return missing
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

    it("refuses a pole that reaches only two rows, which leaves a row of inserters with no pole in reach", function()
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

    it("refuses it when the nearest free tile is one row further than the pole reaches", function()
      local plan = {inserters = {{row = 5, belt = "a"}}, free_taps = {1}}

      assert.has_error(function() weave.pole_rows(plan, 3) end, "weave: no free tile beside the belts reaches the inserter in row 5: the pole reaches 3 rows")
    end)
  end)

  describe("poles that stay within a wire of each other", function()
    -- Inserters in rows 0, 5, 6, 11 and 12, and free tiles at the top and the bottom row of each of five machines.
    local function sparse_plan()
      return {
        inserters = {{row = 0}, {row = 5}, {row = 6}, {row = 11}, {row = 12}},
        free_taps = {0, 2, 3, 5, 6, 8, 9, 11, 12, 14},
      }
    end

    it("takes the last free tile that reaches the next inserter when no wire limits it", function()
      local rows = weave.pole_rows(sparse_plan(), 3)

      assert.are.same({3, 14}, rows)
    end)

    it("takes the last free tile within the wire of the pole before it when a wire limits it", function()
      local rows = weave.pole_rows(sparse_plan(), 3, 9)

      assert.are.same({3, 12}, rows)
    end)

    it("takes the poles of a small pole nearer each other, which reaches two rows and holds a wire of seven", function()
      local rows = weave.pole_rows(sparse_plan(), 2, 7)

      assert.are.same({2, 6, 12}, rows)
    end)

    it("counts a wire of seven and a half tiles as seven rows, since the rows between two poles in one column are whole tiles", function()
      local rows = weave.pole_rows(sparse_plan(), 2, 7.5)

      assert.are.same({2, 6, 12}, rows)
    end)

    it("refuses an inserter when no free tile that reaches it is within the wire of the pole before it", function()
      local plan = {inserters = {{row = 0}, {row = 20}}, free_taps = {0, 20}}

      local build = function() weave.pole_rows(plan, 3, 9) end

      assert.has_error(build, "weave: no free tile beside the belts reaches the inserter in row 20 within 9 tiles of the pole before it: the pole reaches 3 rows")
    end)

    describe("with poles that only bridge the wire", function()
      -- Inserters in the rows 0 and 9, and the tiles that reach the second (the rows 7 to 11 for poles that reach two) are further than a wire of
      -- 7.5 from the pole in the row 0: the free tiles 8 and 9 are, and the tile 7 is a pipe's.
      local function far_plan()
        return {inserters = {{row = 0}, {row = 9}}, free_taps = {0, 3, 5, 8, 9}}
      end

      it("puts a pole in the last free tile the wire reaches, before the tiles that reach the inserter, and the next pole there", function()
        local rows = weave.pole_rows(far_plan(), 2, 7.5, true)

        assert.are.same({0, 5, 9}, rows)
      end)

      it("refuses the same plan when it is not asked to bridge", function()
        local build = function() weave.pole_rows(far_plan(), 2, 7.5) end

        assert.has_error(build, "weave: no free tile beside the belts reaches the inserter in row 9 within 7.5 tiles of the pole before it: the pole reaches 2 rows")
      end)

      it("bridges more than once when the inserters are more than two wires apart", function()
        local plan = {inserters = {{row = 0}, {row = 30}}, free_taps = {0, 5, 10, 15, 20, 25, 29, 30}}

        local rows = weave.pole_rows(plan, 2, 7, true)

        assert.are.same({0, 5, 10, 15, 20, 25, 30}, rows)
      end)

      it("does not bridge to a free tile past the inserter, which does not reach it", function()
        -- the tiles that reach the inserter in the row 10 (8 to 12) are none; the tile in the row 14 is further down than it reaches
        local plan = {inserters = {{row = 0}, {row = 10}}, free_taps = {0, 5, 14}}

        local build = function() weave.pole_rows(plan, 2, 20, true) end

        assert.has_error(build, "weave: no free tile beside the belts reaches the inserter in row 10 within 20 tiles of the pole before it: the pole reaches 2 rows")
      end)

      it("does not bridge when the poles are not limited by a wire, or when no pole came before", function()
        assert.are.same({3, 14}, weave.pole_rows(sparse_plan(), 3, nil, true))
        assert.are.same({0}, weave.pole_rows({inserters = {{row = 0}}, free_taps = {0}}, 2, 7, true))
      end)

      it("takes the same poles as without bridging when no inserter needs one", function()
        assert.are.same(weave.pole_rows(sparse_plan(), 3, 9), weave.pole_rows(sparse_plan(), 3, 9, true))
      end)

      it("still refuses an inserter that no free tile reaches, whatever bridges there are", function()
        local plan = {inserters = {{row = 0}, {row = 20}}, free_taps = {0, 3}}

        local build = function() weave.pole_rows(plan, 3, 9, true) end

        assert.has_error(build, "weave: no free tile beside the belts reaches the inserter in row 20 within 9 tiles of the pole before it: the pole reaches 3 rows")
      end)
    end)
  end)

  describe("machines with a pipe in the middle row of their input side, two belts", function()
    it("draws four machines: belt a under belt b, which goes in and out of the inner column where two inserters meet", function()
      local plan = weave.plan_with_pipes(4)

      assert.are.same({
        "....n}  a",
        "......",
        "...>v}  b",
        "...v<}  b",
        "...v..",
        "...vu}  a",
        "...vn}  a",
        "...v..",
        "...>v}  b",
        "...v<}  b",
        "......",
        "....u}  a",
      }, drawn(plan, {}))
    end)

    it("draws three machines: belt a ends in a plain tile and belt b in a detour of its own, which goes on a row past the machines", function()
      local plan = weave.plan_with_pipes(3)

      assert.are.same({
        "....n}  a",
        "......",
        "...>v}  b",
        "...v<}  b",
        "...v..",
        "...vu}  a",
        "...v>}  a",
        "...v..",
        "...>v}  b",
        "...v<.",
      }, drawn(plan, {}))
    end)

    it("draws one machine: belt a is a plain tile, where the first inserter takes from it, and belt b has its detour in the bottom row", function()
      local plan = weave.plan_with_pipes(1)

      assert.are.same({
        "....>}  a",
        "......",
        "...>v}  b",
        "...v<.",
      }, drawn(plan, {}))
    end)

    it("puts the inserters in the top and the bottom row of every machine, and none in the middle row", function()
      local plan = weave.plan_with_pipes(3)

      assert.are.same({{0, 2, 3, 5, 6, 8}, {"a", "b", "b", "a", "a", "b"}}, {
        {plan.inserters[1].row, plan.inserters[2].row, plan.inserters[3].row, plan.inserters[4].row, plan.inserters[5].row, plan.inserters[6].row},
        {plan.inserters[1].belt, plan.inserters[2].belt, plan.inserters[3].belt, plan.inserters[4].belt, plan.inserters[5].belt, plan.inserters[6].belt},
      })
    end)

    it("has belt a in the bottom row of the last machine when the count is even, and belt b when it is odd", function()
      local odd, even = weave.plan_with_pipes(5), weave.plan_with_pipes(4)

      assert.are.same({"b", "a"}, {odd.rows[14], even.rows[11]})
    end)

    it("starts belt a in row 0, the top row of the first machine, whether the count is odd or even", function()
      local even, odd = weave.plan_with_pipes(2), weave.plan_with_pipes(3)

      assert.are.same({0, 0}, {even.starts.a, odd.starts.a})
    end)

    it("starts belt b in the first row that shows it", function()
      local plan = weave.plan_with_pipes(4)

      assert.are.equal(2, plan.starts.b)
    end)

    it("has the poles in the inner column", function()
      local plan = weave.plan_with_pipes(4)

      assert.are.equal(weave.INNER, plan.pole_column)
    end)

    it("takes the rows where the inner column holds nothing for poles, from the first tile of belt a to one row past the last machine", function()
      local plan = weave.plan_with_pipes(2)

      assert.are.same({1, 4, 6}, plan.free_taps)
    end)

    it("leaves no row before the first tile of belt a to a pole, since the belt that brings belt a comes up through them", function()
      local plan = weave.plan_with_pipes(1)

      assert.are.same({1}, plan.free_taps)
    end)

    it("needs a pole in the middle row of the machine for one machine", function()
      local plan = weave.plan_with_pipes(1)

      assert.are.same({1}, weave.pole_rows(plan, 2))
    end)

    it("needs poles in rows 1 and 6 for two machines when a pole reaches two rows, the last of them a row past the machines", function()
      local plan = weave.plan_with_pipes(2)

      assert.are.same({1, 6}, weave.pole_rows(plan, 2))
    end)

    it("needs three poles for four machines when a pole reaches two rows, the last a row past the machines", function()
      local plan = weave.plan_with_pipes(4)

      assert.are.same({1, 7, 12}, weave.pole_rows(plan, 2))
    end)

    it("needs poles at the middle rows of the first and the third of three machines, which a pole that reaches two rows serves", function()
      local plan = weave.plan_with_pipes(3)

      assert.are.same({1, 7}, weave.pole_rows(plan, 2))
    end)

    describe("every number of machines", function()
      for machines = 1, 12 do
        it("is drawn without two things on a tile, the poles included, for " .. machines .. " machines", function()
          local plan = weave.plan_with_pipes(machines)

          assert.is_true(#drawn(plan, weave.pole_rows(plan, 2)) > 0) -- `drawn` stops when two things stand on one tile
        end)

        it("has a pole within two rows of every inserter, for " .. machines .. " machines and a pole that reaches two rows", function()
          local plan = weave.plan_with_pipes(machines)

          assert.are.same({}, unpowered_rows(plan, weave.pole_rows(plan, 2, 7), 2))
        end)
      end
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

  describe("the tile columns the weave takes west of the inner column", function()
    it("takes two for two belts: the trunk of belt b and the taps", function()
      assert.are.equal(2, weave.WIDTH[2])
    end)

    it("takes four for three belts: the two columns of belt c besides", function()
      assert.are.equal(4, weave.WIDTH[3])
    end)

    it("takes one beside a pipe: the trunk of belt b alone", function()
      assert.are.equal(1, weave.PIPED_WIDTH)
    end)
  end)
end)
