-- spec/grid_spec.lua
-- A tile is the top-left tile an entity covers; a position is its centre.
-- The expected numbers are written out by hand, so a mistake in grid.lua cannot
-- hide behind the same mistake elsewhere.
---@diagnostic disable: undefined-field  -- luassert's `assert` has fields (`assert.are`, `assert.is_nil`, ...) the editor cannot see

local grid = require("scripts.grid")

describe("grid", function()
  describe("position", function()
    it("centres a small entity half a tile in from its tile's edges", function()
      local position = grid.position(0, 0)

      assert.are.same({x = 0.5, y = 0.5}, position)
    end)

    it("keeps the half-tile offset when the tile is further along", function()
      local position = grid.position(4, 7)

      assert.are.same({x = 4.5, y = 7.5}, position)
    end)

    it("centres an entity on the corner its tiles share when it is two tiles wide", function()
      local position = grid.position(2, 0, 2, 2)

      assert.are.same({x = 3, y = 1}, position)
    end)

    it("centres an entity on its middle tile when it is three tiles wide", function()
      local position = grid.position(10, 20, 3, 3)

      assert.are.same({x = 11.5, y = 21.5}, position)
    end)

    it("centres an entity half a tile across and a tile down when it is one wide and two tall", function()
      local position = grid.position(1, 1, 1, 2)

      assert.are.same({x = 1.5, y = 2}, position)
    end)

    it("works the same way when the tiles are negative", function()
      local position = grid.position(-3, -1)

      assert.are.same({x = -2.5, y = -0.5}, position)
    end)
  end)

  describe("top_left_tile", function()
    it("finds the tile of a one-tile entity from its centre", function()
      local tile = grid.top_left_tile({x = 0.5, y = 0.5})

      assert.are.same({x = 0, y = 0}, tile)
    end)

    it("finds the top-left tile of a two-tile entity from its centre", function()
      local tile = grid.top_left_tile({x = 3, y = 1}, 2, 2)

      assert.are.same({x = 2, y = 0}, tile)
    end)

    it("gives a tile with a fraction when the entity is centred off the grid", function()
      local tile = grid.top_left_tile({x = 1.25, y = 0.5})

      assert.are.same({x = 0.75, y = 0}, tile)
    end)

    it("gives back the same tile after converting to a position and back, for any size", function()
      local position = grid.position(6, 9, 3, 2)

      local tile = grid.top_left_tile(position, 3, 2)

      assert.are.same({x = 6, y = 9}, tile)
    end)
  end)
end)
