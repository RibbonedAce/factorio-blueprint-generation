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
  end)
end)
