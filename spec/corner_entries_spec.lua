-- spec/corner_entries_spec.lua
-- The pipes that take the start of each pipe the player connects to the top left corner (see scripts/corner_entries.lua). Positions are
-- TILES: the top-left tile an entity covers, with y growing down (see scripts/grid.lua).
---@diagnostic disable: undefined-field  -- luassert's `assert` has fields (`assert.are`, ...) the editor cannot see

local builders = require("spec.support.builders")
local grid = require("scripts.grid")
local corner_entries = require("scripts.corner_entries")

-- The tiles of the pipes, sorted by row and then by column.
local function pipe_tiles(entities)
  local tiles = {}
  for _, entity in ipairs(entities) do
    local tile = grid.top_left_tile(entity.position)
    tiles[#tiles + 1] = {tile.x, tile.y}
  end
  table.sort(tiles, function(first, second)
    if first[2] ~= second[2] then
      return first[2] < second[2]
    end
    return first[1] < second[1]
  end)
  return tiles
end

describe("corner_entries", function()
  describe("add", function()
    it("takes a pipe that starts at a tile up one row above the blueprint and west to the edge", function()
      local entities = {}

      local entries = corner_entries.add(entities, {{key = "crude", x = 3, y = 0, name = "pipe"}})

      assert.are.same({{0, -1}, {1, -1}, {2, -1}, {3, -1}}, pipe_tiles(entities))
      assert.are.same({{key = "crude", x = 0, y = -1}}, entries)
    end)

    it("takes the pipe that starts at the edge up, with no pipe along", function()
      local entities = {}

      corner_entries.add(entities, {{key = "crude", x = 0, y = 0, name = "pipe"}})

      assert.are.same({{0, -1}}, pipe_tiles(entities))
    end)

    it("starts the rows above the first row of the blueprint, whichever row the pipe starts at", function()
      local entities = {}

      corner_entries.add(entities, {{key = "crude", x = 1, y = 2, name = "pipe"}})

      assert.are.same({{1, 1}, {0, 1}}, {pipe_tiles(entities)[2], pipe_tiles(entities)[1]})
    end)

    it("takes the pipe that starts furthest east to the top row, three rows above the one that starts furthest west", function()
      local entities = {}

      local entries = corner_entries.add(entities, {{key = "east", x = 4, y = 0, name = "pipe"}, {key = "west", x = 1, y = 0, name = "pipe"}})

      assert.are.same({{key = "west", x = 0, y = -1}, {key = "east", x = 0, y = -4}}, entries)
    end)

    it("takes the pipes up and along so that no pipe of one touches a pipe of the other", function()
      local first, second = {}, {}

      corner_entries.add(first, {{key = "west", x = 1, y = 0, name = "pipe"}})
      corner_entries.add(second, {{key = "east", x = 5, y = 0, name = "pipe"}}) -- alone, it takes the row -1: the two rows apart are what the pair below has
      local both = {}
      corner_entries.add(both, {{key = "east", x = 5, y = 0, name = "pipe"}, {key = "west", x = 1, y = 0, name = "pipe"}})

      local rows = {}
      for _, tile in ipairs(pipe_tiles(both)) do
        rows[tile[2]] = (rows[tile[2]] or 0) + 1
      end
      -- the row -4 has the six tiles of the east pipe (0 to 5), the row -1 the two of the west pipe, and the east pipe goes up the column 5
      assert.are.same({[-4] = 6, [-3] = 1, [-2] = 1, [-1] = 3}, rows)
    end)

    it("takes a belt that starts at a tile east along the row above, and south down its column, to the tile it starts at", function()
      local entities = {}

      local entries = corner_entries.add(entities, {{key = "coal", x = 2, y = 0, name = "belt", belt = true}})

      local ways = {}
      for _, belt in ipairs(entities) do
        local tile = grid.top_left_tile(belt.position)
        ways[#ways + 1] = string.format("%d,%d %s", tile.x, tile.y, belt.direction)
      end
      table.sort(ways)
      assert.are.same({"0,-1 east", "1,-1 east", "2,-1 south"}, ways)
      assert.are.same({{key = "coal", x = 0, y = -1}}, entries)
    end)

    it("takes a pipe and a belt three rows apart, the belt that starts furthest east on the top row", function()
      local entities = {}

      local entries = corner_entries.add(entities, {{key = "coal", x = 5, y = 0, name = "belt", belt = true}, {key = "crude", x = 1, y = 0, name = "pipe"}})

      assert.are.same({{key = "crude", x = 0, y = -1}, {key = "coal", x = 0, y = -4}}, entries)
    end)

    it("numbers the entities from 1 with no gap", function()
      local entities = {}

      corner_entries.add(entities, {{key = "a", x = 2, y = 0, name = "pipe"}, {key = "b", x = 4, y = 0, name = "pipe"}})

      assert.has_consecutive_numbers(entities)
    end)

    describe("with a start that joins the entry of another", function()
      -- the water starts at the columns 3 and 7, the crude oil at the column 1, west of both
      local function water_and_crude(extra)
        local starts = {
          {key = "crude", x = 1, y = 0, name = "pipe"}, {key = "water", x = 3, y = 0, name = "pipe"},
          {key = "more_water", x = 7, y = 0, name = "pipe", joins = "water"},
        }
        for _, start in ipairs(extra or {}) do
          starts[#starts + 1] = start
        end
        return starts
      end

      it("brings the two pipes to one row, the row of the one that starts furthest east, with a pipe down at each column", function()
        local entities = {}

        corner_entries.add(entities, water_and_crude())

        -- the row -4 from the edge to the column 7 (the entry), the columns 3 and 7 down from it to the row -1, the crude oil in the row -1
        assert.are.same({
          {0, -4}, {1, -4}, {2, -4}, {3, -4}, {4, -4}, {5, -4}, {6, -4}, {7, -4},
          {3, -3}, {7, -3}, {3, -2}, {7, -2},
          {0, -1}, {1, -1}, {3, -1}, {7, -1},
        }, pipe_tiles(entities))
      end)

      it("gives one entry for the two, with the key of the start that the other joins, above the one that starts west of both", function()
        local entities = {}

        local entries = corner_entries.add(entities, water_and_crude())

        assert.are.same({{key = "crude", x = 0, y = -1}, {key = "water", x = 0, y = -4}}, entries)
      end)

      it("takes the row by the furthest start whichever of the two the other joins", function()
        local entities = {}
        local starts = {
          {key = "east", x = 7, y = 0, name = "pipe"}, {key = "west", x = 3, y = 0, name = "pipe", joins = "east"}, {key = "belt", x = 9, y = 0, name = "belt", belt = true},
        }

        local entries = corner_entries.add(entities, starts)

        assert.are.same({{key = "east", x = 0, y = -1}, {key = "belt", x = 0, y = -4}}, entries)
      end)

      it("goes up from a start in the row of the entry, with no pipe between, when the entry is right above it", function()
        local entities = {}

        corner_entries.add(entities, {{key = "water", x = 5, y = 0, name = "pipe"}, {key = "more_water", x = 2, y = 0, name = "pipe", joins = "water"}})

        assert.are.same({{0, -1}, {1, -1}, {2, -1}, {3, -1}, {4, -1}, {5, -1}}, pipe_tiles(entities))
      end)

      it("lets an entry that starts east of both starts take a row above", function()
        local entities = {}

        local entries = corner_entries.add(entities, water_and_crude({{key = "coal", x = 11, y = 0, name = "belt", belt = true}}))

        assert.are.same({"crude", "water", "coal"}, {entries[1].key, entries[2].key, entries[3].key})
      end)

      it("refuses an entry that starts between the two starts, which would have to cross the pipe", function()
        local entities = {}

        local add = function() corner_entries.add(entities, water_and_crude({{key = "coal", x = 5, y = 0, name = "belt", belt = true}})) end

        assert.has_error(add, "corner_entries: an entry has the start of another entry between two of its own starts, which it would cross")
      end)

      it("refuses an entry that starts in the column of the start that is not the furthest", function()
        local entities = {}

        local add = function() corner_entries.add(entities, water_and_crude({{key = "coal", x = 3, y = 1, name = "belt", belt = true}})) end

        assert.has_error(add, "corner_entries: an entry has the start of another entry between two of its own starts, which it would cross")
      end)

      it("refuses an entry that starts in the column of the furthest start of the pipe, which would be in its way whichever is above", function()
        local entities = {}

        local add = function() corner_entries.add(entities, water_and_crude({{key = "coal", x = 7, y = 1, name = "belt", belt = true}})) end

        assert.has_error(add, "corner_entries: an entry has the start of another entry between two of its own starts, which it would cross")
      end)

      it("refuses two starts of one entry in the same column", function()
        local entities = {}

        local add = function() corner_entries.add(entities, {{key = "water", x = 3, y = 0, name = "pipe"}, {key = "more", x = 3, y = 2, name = "pipe", joins = "water"}}) end

        assert.has_error(add, "corner_entries: two starts of an entry are in the same column")
      end)

      it("refuses a start that joins one that is not there", function()
        local entities = {}

        local add = function() corner_entries.add(entities, {{key = "water", x = 3, y = 0, name = "pipe", joins = "nothing"}}) end

        assert.has_error(add, "corner_entries: a start joins the entry of a start that is not there")
      end)

      it("refuses a belt that joins a pipe, and a pipe that joins a belt", function()
        local belt_joins = function()
          corner_entries.add({}, {{key = "water", x = 3, y = 0, name = "pipe"}, {key = "coal", x = 5, y = 0, name = "belt", belt = true, joins = "water"}})
        end
        local pipe_joins = function()
          corner_entries.add({}, {{key = "coal", x = 3, y = 0, name = "belt", belt = true}, {key = "water", x = 5, y = 0, name = "pipe", joins = "coal"}})
        end

        assert.has_error(belt_joins, "corner_entries: only pipes join each other")
        assert.has_error(pipe_joins, "corner_entries: only pipes join each other")
      end)

      it("numbers the entities from 1 with no gap", function()
        local entities = {}

        corner_entries.add(entities, water_and_crude())

        assert.has_consecutive_numbers(entities)
      end)
    end)

    it("puts the first entry above the row the options give as the top of the blueprint", function()
      local entities = {}

      local entries = corner_entries.add(entities, {{key = "crude", x = 3, y = 5, name = "pipe"}}, {top = 2})

      assert.are.same({{key = "crude", x = 0, y = 1}}, entries)
    end)

    describe("with belts across the way of a pipe", function()
      -- What stands in the column `x` from the row -4 to the row 6, a letter for each tile: p a pipe, n the end of an underground pipe that is
      -- open to the north, s one open to the south, . nothing.
      local function column(entities, x)
        local letters = {}
        for row = -4, 6 do
          letters[row] = "."
        end
        for _, entity in ipairs(entities) do
          local tile = grid.top_left_tile(entity.position)
          if tile.x == x and entity.name == "pipe" then
            letters[tile.y] = "p"
          elseif tile.x == x and entity.name == "pipe-to-ground" then
            letters[tile.y] = entity.direction == defines.direction.north and "n" or "s"
          end
        end
        return table.concat(letters, "", -4, 6)
      end

      local function options_with(rows)
        local taken = {}
        for _, row in ipairs(rows) do
          taken[grid.key(4, row)] = true
        end
        return {top = 0, taken = taken, pipe_to_ground = "pipe-to-ground"}
      end

      it("goes under a belt with an underground pipe, from the tile before it to the tile after it", function()
        local entities = {}

        corner_entries.add(entities, {{key = "crude", x = 4, y = 6, name = "pipe"}}, options_with({2}))

        -- the entry is in the row -1; the underground pipe starts in the row 1 and comes out in the row 3
        assert.are.equal("...ppn.spp.", column(entities, 4))
      end)

      it("goes under belts in rows next to each other with one underground pipe", function()
        local entities = {}

        corner_entries.add(entities, {{key = "crude", x = 4, y = 7, name = "pipe"}}, options_with({2, 3}))

        assert.are.equal("...ppn..spp", column(entities, 4))
      end)

      it("goes under belts three rows apart with two underground pipes that meet in the rows between", function()
        local entities = {}

        corner_entries.add(entities, {{key = "crude", x = 4, y = 7, name = "pipe"}}, options_with({1, 4}))

        assert.are.equal("...pn.sn.sp", column(entities, 4))
      end)

      it("goes under the belts for the pipe that joins an entry too", function()
        local entities = {}

        corner_entries.add(entities, {
          {key = "water", x = 8, y = 7, name = "pipe"}, {key = "more", x = 4, y = 7, name = "pipe", joins = "water"},
        }, options_with({2}))

        assert.are.equal("...ppn.sppp", column(entities, 4))
      end)

      local function rows_from(first, count)
        local rows = {}
        for row = first, first + count - 1 do
          rows[#rows + 1] = row
        end
        return rows
      end

      it("goes under as many belts as an underground pipe spans: 8, with the tile before and the tile after them, 10 tiles apart at the most", function()
        local run = function() corner_entries.add({}, {{key = "crude", x = 4, y = 14, name = "pipe"}}, options_with(rows_from(1, 8))) end

        assert.has_no.errors(run)
      end)

      it("stops when the belts are more than an underground pipe spans: 9", function()
        local run = function() corner_entries.add({}, {{key = "crude", x = 4, y = 14, name = "pipe"}}, options_with(rows_from(1, 9))) end

        assert.has_error(run, "corner_entries: a pipe has to pass under more belts than an underground pipe spans")
      end)

      it("stops when a belt is right above the tile where the pipe starts, which leaves no tile to come out of the ground at", function()
        local run = function() corner_entries.add({}, {{key = "crude", x = 4, y = 6, name = "pipe"}}, options_with({5})) end

        assert.has_error(run, "corner_entries: a pipe has no free tile to come out of the ground at")
      end)

      it("stops when no underground pipe is named for a pipe that crosses belts", function()
        local options = options_with({2})
        options.pipe_to_ground = nil

        local run = function() corner_entries.add({}, {{key = "crude", x = 4, y = 6, name = "pipe"}}, options) end

        assert.has_error(run, "corner_entries: no underground pipe for a pipe that crosses belts")
      end)
    end)
  end)
end)
