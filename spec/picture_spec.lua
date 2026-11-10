-- spec/picture_spec.lua
-- The text pictures that other specs compare with their diagrams (see spec/support/picture.lua). Positions are tiles
-- (the top-left tile an entity covers, y growing down; see scripts/grid.lua).
---@diagnostic disable: undefined-field  -- luassert's `assert` has fields (`assert.are`, `assert.is_nil`, ...) the editor cannot see

local builders = require("spec.support.builders")
local picture = require("spec.support.picture")

local north, east, south, west = defines.direction.north, defines.direction.east, defines.direction.south, defines.direction.west

local MACHINES = {["stone-furnace"] = {size = 2, glyph = "i"}}

describe("picture", function()
  describe("belts", function()
    it("draws each belt as an arrow the way it runs", function()
      local entities = {builders.belt(0, 0, north), builders.belt(1, 0, east), builders.belt(2, 0, south), builders.belt(3, 0, west)}

      assert.are.same({"^>v<"}, picture.draw(entities, {}, 0, 0, 3, 0))
    end)
  end)

  describe("splitters", function()
    it("draws a splitter that faces south on two tiles side by side", function()
      assert.are.same({".SS."}, picture.draw({builders.splitter(1, 0, south)}, {}, 0, 0, 3, 0))
    end)

    it("draws a splitter that faces east on two tiles one above the other", function()
      assert.are.same({"S.", "S."}, picture.draw({builders.splitter(0, 0, east)}, {}, 0, 0, 1, 1))
    end)
  end)

  describe("underground belts", function()
    it("draws the entrance and the exit of one that runs east as ( and )", function()
      local entities = {builders.underground(0, 0, east, "input"), builders.underground(1, 0, east, "output")}

      assert.are.same({"()"}, picture.draw(entities, {}, 0, 0, 1, 0))
    end)

    it("draws the entrance and the exit of one that runs south as n and u", function()
      local entities = {builders.underground(0, 0, south, "input"), builders.underground(0, 1, south, "output")}

      assert.are.same({"n", "u"}, picture.draw(entities, {}, 0, 0, 0, 1))
    end)
  end)

  describe("the rest", function()
    it("draws an inserter, a long-handed inserter and a pole", function()
      local entities = {builders.inserter(0, 0), builders.long_inserter(1, 0), builders.pole(2, 0)}

      assert.are.same({"}}+"}, picture.draw(entities, {}, 0, 0, 2, 0))
    end)

    it("draws a machine on every tile it covers, with the glyph its table gives", function()
      assert.are.same({"ii", "ii"}, picture.draw({builders.furnace(0, 0)}, MACHINES, 0, 0, 1, 1))
    end)

    it("draws an entity it does not know as ?", function()
      local entities = {{name = "mystery", position = {x = 0.5, y = 0.5}}}

      assert.are.same({"?"}, picture.draw(entities, {}, 0, 0, 0, 0))
    end)

    it("leaves a tile with nothing as .", function()
      assert.are.same({"...", "..."}, picture.draw({}, {}, 0, 0, 2, 1))
    end)
  end)

  describe("the box", function()
    it("draws only the tiles inside it, counted from its first column and row", function()
      local entities = {builders.belt(0, 0, east), builders.belt(2, 1, south), builders.belt(5, 5, north)}

      assert.are.same({"..", ".v"}, picture.draw(entities, {}, 1, 0, 2, 1))
    end)

    it("cuts a machine that stands half inside it", function()
      assert.are.same({"i."}, picture.draw({builders.furnace(0, 0)}, MACHINES, 1, 0, 2, 0))
    end)
  end)
end)
