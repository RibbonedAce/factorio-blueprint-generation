-- spec/blueprint_validator_spec.lua
-- A checker that never complains proves nothing, so these specs hand-build tiny
-- blueprints, break them in one specific way, and expect that problem (and only
-- a problem of that kind) to be reported. The blueprints do not come from the
-- layout, so each example shows every coordinate it relies on.
--
-- Coordinates are tiles: (x, y) is the top-left tile an entity covers, with y
-- growing downward (see scripts/grid.lua). The 2x2 furnace at (2, 0) covers
-- tiles x 2 to 3 and y 0 to 1. An inserter at (1, 0) facing west picks up from
-- tile (0, 0) and drops onto tile (2, 0).
---@diagnostic disable: undefined-field  -- luassert's `assert` has fields (`assert.are`, `assert.is_nil`, ...) the editor cannot see
---@diagnostic disable: need-check-nil  -- entities come from `blueprint_of`, which numbers every one
---@diagnostic disable: param-type-mismatch  -- some entities are damaged on purpose, and the fake `defines` holds strings, not Factorio's numbers

local builders = require("spec.support.builders")
local validator = require("spec.support.blueprint_validator")

local belt, furnace, inserter, pole = builders.belt, builders.furnace, builders.inserter, builders.pole
local long_inserter = builders.long_inserter
local blueprint_of, wire_between, a_catalog = builders.blueprint_of, builders.wire_between, builders.a_catalog
local west, north = defines.direction.west, defines.direction.north

describe("blueprint validator", function()
  describe("a blueprint that is fine", function()
    it("reports no problems when a belt feeds a furnace through a powered inserter", function()
      local entities = blueprint_of(belt(0, 0), inserter(1, 0, west), furnace(2, 0), pole(1, 1))

      local problems = validator.validate(entities, a_catalog{})

      assert.are.same({}, problems)
    end)

    it("reports no problems when the blueprint has only belts, whichever way they turn", function()
      local entities = blueprint_of(belt(0, 0, defines.direction.east), belt(1, 0, north))

      local problems = validator.validate(entities, a_catalog{})

      assert.are.same({}, problems)
    end)
  end)

  describe("names, numbers and the tile grid", function()
    it("reports an entity when the catalog does not know it", function()
      local mystery_belt = belt(0, 0)
      mystery_belt.name = "mystery-belt"
      local entities = blueprint_of(mystery_belt)

      local problems = validator.validate(entities, a_catalog{})

      assert.has_item_containing("not in the catalog", problems)
    end)

    it("reports an entity when it has no number", function()
      local numberless = belt(0, 0) -- not passed through blueprint_of, so it has no number

      local problems = validator.validate({numberless}, a_catalog{})

      assert.has_item_containing("has no entity number", problems)
    end)

    it("reports two entities when they share a number", function()
      local entities = blueprint_of(belt(0, 0), belt(0, 1))
      entities[2].entity_number = entities[1].entity_number

      local problems = validator.validate(entities, a_catalog{})

      assert.has_item_containing("reuses an entity number", problems)
    end)

    it("reports a 1x1 entity when it is off the half-tile grid", function()
      local entities = blueprint_of(inserter(0.75, 0, west))

      local problems = validator.validate(entities, a_catalog{})

      assert.has_item_containing("not aligned to the tile grid", problems)
    end)

    it("reports a 2x2 furnace when it sits on a half tile", function()
      local entities = blueprint_of(furnace(2.5, 0))

      local problems = validator.validate(entities, a_catalog{})

      assert.has_item_containing("not aligned to the tile grid", problems)
    end)
  end)

  describe("overlaps", function()
    it("reports two poles when they are on the same tile", function()
      local entities = blueprint_of(pole(1, 1), pole(1, 1))

      local problems = validator.validate(entities, a_catalog{})

      assert.has_item_containing("overlaps", problems)
    end)

    it("reports a pole when it stands on a corner tile of a furnace", function()
      local entities = blueprint_of(furnace(2, 0), pole(2, 0)) -- the furnace covers tile (2, 0)

      local problems = validator.validate(entities, a_catalog{})

      assert.has_item_containing("overlaps", problems)
    end)
  end)

  describe("inserters", function()
    it("reports an inserter when it has no direction", function()
      local entities = blueprint_of(inserter(1, 0, nil), pole(1, 1))

      local problems = validator.validate(entities, a_catalog{})

      assert.has_item_containing("no usable direction", problems)
    end)

    it("reports an inserter when nothing is on its pickup tile", function()
      local entities = blueprint_of(inserter(1, 0, west), furnace(2, 0), pole(1, 1)) -- tile (0, 0) is empty

      local problems = validator.validate(entities, a_catalog{})

      assert.has_item_containing("nothing to pick up from", problems)
    end)

    it("reports an inserter when it picks up from a pole", function()
      local entities = blueprint_of(pole(0, 0), inserter(1, 0, west), furnace(2, 0))

      local problems = validator.validate(entities, a_catalog{})

      assert.has_item_containing("nothing to pick up from", problems)
    end)

    it("reports an inserter when nothing is on its drop tile", function()
      local entities = blueprint_of(belt(0, 0), inserter(1, 0, west), pole(1, 1)) -- tile (2, 0) is empty

      local problems = validator.validate(entities, a_catalog{})

      assert.has_item_containing("nothing to drop onto", problems)
    end)

    it("reports both ends when an inserter points at open ground and a pole", function()
      -- Facing north it picks up from tile (1, -1), which is empty, and drops onto tile (1, 1), a pole.
      local entities = blueprint_of(inserter(1, 0, north), furnace(2, 0), pole(1, 1))

      local problems = validator.validate(entities, a_catalog{})

      assert.has_item_containing("nothing to pick up from", problems)
      assert.has_item_containing("nothing to drop onto", problems)
    end)

    it("reports an inserter when it moves items from one belt to another with no machine involved", function()
      local entities = blueprint_of(belt(0, 0), inserter(1, 0, west), belt(2, 0), pole(1, 1))

      local problems = validator.validate(entities, a_catalog{})

      assert.has_item_containing("does not touch a machine", problems)
    end)
  end)

  describe("long-handed inserters, which reach two tiles", function()
    it("reports no problems when a long-handed inserter picks up two tiles away, over a belt, and drops two tiles in", function()
      -- Facing west at (2, 0) it picks up from tile (0, 0), over the belt in (1, 0), and drops onto tile (4, 0), the far column of the furnace.
      local entities = blueprint_of(belt(0, 0), belt(1, 0), long_inserter(2, 0, west), furnace(3, 0), pole(2, 1))

      local problems = validator.validate(entities, a_catalog{})

      assert.are.same({}, problems)
    end)

    it("reports a long-handed inserter when only the tile next to it holds something to pick up", function()
      local entities = blueprint_of(belt(1, 0), long_inserter(2, 0, west), furnace(3, 0), pole(2, 1)) -- tile (0, 0) is empty

      local problems = validator.validate(entities, a_catalog{})

      assert.has_item_containing("nothing to pick up from", problems)
    end)

    it("reports a long-handed inserter when only the tile next to it holds something to drop onto", function()
      local entities = blueprint_of(belt(0, 0), long_inserter(2, 0, west), belt(3, 0), pole(2, 1)) -- tile (4, 0) is empty

      local problems = validator.validate(entities, a_catalog{})

      assert.has_item_containing("nothing to drop onto", problems)
    end)

    it("reports a long-handed inserter when it moves items from one belt to another with no machine involved", function()
      local entities = blueprint_of(belt(0, 0), long_inserter(2, 0, west), belt(4, 0), pole(2, 1))

      local problems = validator.validate(entities, a_catalog{})

      assert.has_item_containing("does not touch a machine", problems)
    end)
  end)

  describe("power: supply area", function()
    it("reports an inserter as unpowered when no pole is near", function()
      local entities = blueprint_of(belt(0, 0), inserter(1, 0, west), furnace(2, 0))

      local problems = validator.validate(entities, a_catalog{})

      assert.has_item_containing("outside every pole's supply area", problems)
    end)

    it("powers an inserter when it is within the pole's supply area", function()
      local entities = blueprint_of(belt(0, 0), inserter(1, 0, west), furnace(2, 0), pole(1, 2))

      local problems = validator.validate(entities, a_catalog{pole_supply_radius = 2.5})

      assert.are.same({}, problems)
    end)

    it("does not power an inserter when the supply area only touches its edge", function()
      -- The pole on tile row 3 is centred at y = 3.5, so it powers everything down to
      -- y = 1.0 (3.5 - 2.5). The inserter covers y = 0 to 1, so the two only share an
      -- edge, not any floor space.
      local entities = blueprint_of(belt(0, 0), inserter(1, 0, west), furnace(2, 0), pole(1, 3))

      local problems = validator.validate(entities, a_catalog{pole_supply_radius = 2.5})

      assert.has_item_containing("outside every pole's supply area", problems)
    end)

    it("powers a machine when the supply area overlaps its side edge", function()
      local entities = blueprint_of(furnace(2, 0), pole(5, 1)) -- its centre is 2.5 tiles from the furnace's centre, but only 1.5 from its edge

      local problems = validator.validate(entities, a_catalog{machine_needs_power = true, pole_supply_radius = 2.5})

      assert.are.same({}, problems)
    end)

    it("does not power a machine when a pole is too far to its side", function()
      local entities = blueprint_of(furnace(2, 0), pole(7, 1)) -- its centre is 4.5 tiles from the furnace's centre, 3.5 from its edge

      local problems = validator.validate(entities, a_catalog{machine_needs_power = true, pole_supply_radius = 2.5})

      assert.has_item_containing("outside every pole's supply area", problems)
    end)

    it("powers a machine when the supply area overlaps its bottom edge", function()
      local entities = blueprint_of(furnace(2, 0), pole(1, 3)) -- its centre is 2.5 tiles below the furnace's centre, 1.5 below its edge

      local problems = validator.validate(entities, a_catalog{machine_needs_power = true, pole_supply_radius = 2.5})

      assert.are.same({}, problems)
    end)

    it("does not power a machine when a pole is too far below it", function()
      local entities = blueprint_of(furnace(2, 0), pole(1, 5)) -- its centre is 4.5 tiles below the furnace's centre, 3.5 below its edge

      local problems = validator.validate(entities, a_catalog{machine_needs_power = true, pole_supply_radius = 2.5})

      assert.has_item_containing("outside every pole's supply area", problems)
    end)
  end)

  describe("power: wires and networks", function()
    it("joins two poles into one network when a wire connects them", function()
      local first, second = pole(0, 0), pole(5, 0)
      local entities = blueprint_of(first, second)
      wire_between(first, second)

      local problems = validator.validate(entities, a_catalog{pole_wire_reach = 7.5})

      assert.are.same({}, problems)
    end)

    it("reports separate networks when poles have no wire between them", function()
      local entities = blueprint_of(pole(0, 0), pole(5, 0))

      local problems = validator.validate(entities, a_catalog{})

      assert.has_item_containing("separate networks", problems)
    end)

    it("accepts a wire when it is exactly as long as the reach", function()
      local first, second = pole(0, 0), pole(7, 0) -- 7 tiles apart
      local entities = blueprint_of(first, second)
      wire_between(first, second)

      local problems = validator.validate(entities, a_catalog{pole_wire_reach = 7})

      assert.are.same({}, problems)
    end)

    it("reports a wire when it is longer than the reach", function()
      local first, second = pole(0, 0), pole(8, 0) -- 8 tiles apart
      local entities = blueprint_of(first, second)
      wire_between(first, second)

      local problems = validator.validate(entities, a_catalog{pole_wire_reach = 7})

      assert.has_item_containing("longer than its reach", problems)
    end)

    it("limits a wire by the shorter reach of its two poles", function()
      local first = pole(0, 0)                  -- reach 7.5
      local second = pole(5, 0, "short-pole")   -- reach 3, 5 tiles away
      local catalog = a_catalog{pole_wire_reach = 7.5}
      catalog["short-pole"] = {kind = "pole", width = 1, height = 1, supply_radius = 1, wire_reach = 3}
      local entities = blueprint_of(first, second)
      wire_between(first, second)

      local problems = validator.validate(entities, catalog)

      assert.has_item_containing("longer than its reach", problems)
    end)

    it("reports a wire when it is listed on an entity it does not start from", function()
      local first, second = pole(0, 0), pole(5, 0)
      local entities = blueprint_of(first, second)
      wire_between(first, second)
      first.wires[1][1] = second.entity_number -- now claims to start on the second pole

      local problems = validator.validate(entities, a_catalog{})

      assert.has_item_containing("starts on another entity", problems)
    end)

    it("reports a wire when it goes to something that is not a pole", function()
      local a_pole, a_belt = pole(0, 0), belt(3, 0)
      local entities = blueprint_of(a_pole, a_belt)
      wire_between(a_pole, a_belt)

      local problems = validator.validate(entities, a_catalog{})

      assert.has_item_containing("does not join two poles", problems)
    end)

    it("reports a wire to a misaligned pole as a problem, not a crash", function()
      local first, second = pole(0, 0), pole(4.75, 0) -- the second is off the tile grid
      local entities = blueprint_of(first, second)
      wire_between(first, second)

      local problems = validator.validate(entities, a_catalog{})

      assert.has_item_containing("not aligned to the tile grid", problems)
    end)

    it("still reports separate networks when a wire goes to a misaligned pole", function()
      local first, second, misaligned = pole(0, 0), pole(5, 0), pole(9.75, 0)
      local entities = blueprint_of(first, second, misaligned)
      wire_between(first, misaligned) -- the first and second poles are still not connected to each other

      local problems = validator.validate(entities, a_catalog{})

      assert.has_item_containing("separate networks", problems)
    end)

    it("reports a wire when it does not use the copper connector", function()
      local first, second = pole(0, 0), pole(5, 0)
      local entities = blueprint_of(first, second)
      wire_between(first, second)
      first.wires[1][2] = "something_else"

      local problems = validator.validate(entities, a_catalog{})

      assert.has_item_containing("copper connector", problems)
    end)
  end)
end)
