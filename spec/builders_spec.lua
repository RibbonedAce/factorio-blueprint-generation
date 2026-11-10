-- spec/builders_spec.lua
-- The stand-ins the other specs build with (see spec/support/builders.lua): when a spec fails because of one of these, it
-- should be here that it is seen first. Only what the specs rely on without saying so is tested.
---@diagnostic disable: undefined-field  -- luassert's `assert` has fields (`assert.are`, `assert.is_nil`, ...) the editor cannot see

local builders = require("spec.support.builders")

local south, east = defines.direction.south, defines.direction.east

describe("builders", function()
  describe("a splitter", function()
    it("is centred between its two tiles side by side when it faces south", function()
      local splitter = builders.splitter(2, 3, south)

      assert.are.same({3, 3.5}, {splitter.position.x, splitter.position.y})
    end)

    it("is centred between its two tiles one above the other when it faces east", function()
      local splitter = builders.splitter(2, 3, east)

      assert.are.same({2.5, 4}, {splitter.position.x, splitter.position.y})
    end)

    it("takes the name the layout is given for splitters, and the direction it faces", function()
      local splitter = builders.splitter(0, 0, east)

      assert.are.same({builders.NAMES.splitter, east}, {splitter.name, splitter.direction})
    end)
  end)

  describe("an underground belt", function()
    it("is on its tile, with the direction and the end it is given", function()
      local exit = builders.underground(4, 1, east, "output")

      assert.are.same({builders.NAMES.underground, 4.5, 1.5, east, "output"}, {exit.name, exit.position.x, exit.position.y, exit.direction, exit.type})
    end)
  end)

  describe("the catalog", function()
    it("knows that a splitter is two tiles wide across the way it faces", function()
      local entry = builders.a_catalog{}[builders.NAMES.splitter]

      assert.are.same({"belt", 2, 1, true}, {entry.kind, entry.width, entry.height, entry.turns})
    end)

    it("knows the underground belt as a belt of one tile", function()
      local entry = builders.a_catalog{}[builders.NAMES.underground]

      assert.are.same({"belt", 1, 1}, {entry.kind, entry.width, entry.height})
    end)
  end)

  describe("the fake game", function()
    it("has a splitter and an underground belt unless it is told otherwise", function()
      local prototypes = builders.fake_prototypes{}

      assert.is_not_nil(prototypes.entity["splitter"])
      assert.is_not_nil(prototypes.entity["underground-belt"])
    end)

    it("lets an underground belt span 5 tiles unless it is told otherwise", function()
      assert.are.equal(5, builders.fake_prototypes{}.entity["underground-belt"].max_underground_distance)
    end)

    it("gives the underground belt the span it is told", function()
      assert.are.equal(3, builders.fake_prototypes{underground_distance = 3}.entity["underground-belt"].max_underground_distance)
    end)

    it("leaves the span out when it is told there is none", function()
      assert.is_nil(builders.fake_prototypes{underground_distance = false}.entity["underground-belt"].max_underground_distance)
    end)

    it("leaves out the buildings it is told the game does not have", function()
      local prototypes = builders.fake_prototypes{missing_entities = {"splitter"}}

      assert.is_nil(prototypes.entity["splitter"])
      assert.is_not_nil(prototypes.entity["underground-belt"])
    end)
  end)

  describe("the fake force", function()
    it("has every recipe unlocked unless it is told otherwise", function()
      assert.is_true(builders.fake_force{}.recipes["splitter"].enabled)
    end)

    it("has the recipes it is told are locked known but not unlocked", function()
      local force = builders.fake_force{locked = {"splitter"}}

      assert.is_false(force.recipes["splitter"].enabled)
      assert.is_true(force.recipes["underground-belt"].enabled)
    end)

    it("does not know the recipes it is told are absent", function()
      assert.is_nil(builders.fake_force{absent = {"splitter"}}.recipes["splitter"])
    end)
  end)
end)
