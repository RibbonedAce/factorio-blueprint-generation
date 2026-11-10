-- spec/belt_tracer_spec.lua
-- The tracer follows items along belts, lane by lane. These specs hand it tiny
-- blueprints where every coordinate is visible (tiles, y growing down), each broken in
-- one specific way, and the break has to be reported.
--
-- Machines are 2 x 2. A "furnace" makes plates from ore (its ore comes from a belt the
-- player supplies, so no belt is drawn for it), an "assembler" eats plates and makes gears.
-- An inserter's direction is the side it takes from, as everywhere else.
---@diagnostic disable: undefined-field  -- luassert's `assert` has fields (`assert.are`, `assert.is_nil`, ...) the editor cannot see

local builders = require("spec.support.builders")
local grid = require("scripts.grid")
local tracer = require("spec.support.belt_tracer")

local north, east, south, west = defines.direction.north, defines.direction.east, defines.direction.south, defines.direction.west

local function machine(name, x, y)
  return {name = name, position = grid.position(x, y, 2, 2)}
end

-- `count` belts in a line from tile (x, y), each pointing `direction`.
local function belts_from(x, y, direction, count)
  local belts = {}
  for step = 0, count - 1 do
    local dx = direction == east and step or (direction == west and -step or 0)
    local dy = direction == south and step or (direction == north and -step or 0)
    belts[#belts + 1] = builders.belt(x + dx, y + dy, direction)
  end
  return belts
end

local function all_of(...)
  local entities = {}
  for _, group in ipairs({...}) do
    if group.name then
      entities[#entities + 1] = group
    else
      for _, entity in ipairs(group) do
        entities[#entities + 1] = entity
      end
    end
  end
  return entities
end

local MACHINES = {
  furnace = {size = 2, eats = {"ore"}, makes = "plate"},
  assembler = {size = 2, eats = {"plate"}, makes = "gear"},
}

describe("belt tracer", function()
  -- A furnace at x = 0..1, its inserter in x = 2, a belt running south down x = 3, and an
  -- inserter in x = 4 that takes from the belt's third tile into an assembler at x = 5..6.
  local function furnace_belt_assembler()
    return all_of(
      machine("furnace", 0, 0), builders.inserter(2, 0, west), belts_from(3, 0, south, 3),
      builders.inserter(4, 2, west), machine("assembler", 5, 2))
  end

  it("reports nothing when what a furnace makes reaches the machine that eats it", function()
    local entities = furnace_belt_assembler()

    local problems = tracer.problems(entities, {machines = MACHINES, raw = {furnace = true}, product = "gear"})

    assert.are.same({}, problems)
  end)

  it("reports an input inserter that never sees something its machine eats", function()
    local entities = furnace_belt_assembler()
    local machines = {furnace = MACHINES.furnace, assembler = {size = 2, eats = {"plate", "gear"}, makes = "gear"}}

    local problems = tracer.problems(entities, {machines = machines, raw = {furnace = true}, product = "gear"})

    assert.are.same({"the input inserter at 4,2 never sees gear"}, problems)
  end)

  it("reports an input inserter when the belt does not reach it", function()
    local entities = all_of(
      machine("furnace", 0, 0), builders.inserter(2, 0, west), belts_from(3, 0, south, 2),
      builders.inserter(4, 3, west), machine("assembler", 5, 3), builders.belt(3, 3, south)) -- a belt apart from the first two

    local problems = tracer.problems(entities, {machines = MACHINES, raw = {furnace = true}, product = "gear"})

    assert.are.same({"the input inserter at 4,3 never sees plate"}, problems)
  end)

  it("reports something a machine makes that no machine eats", function()
    local entities = furnace_belt_assembler()
    local machines = {furnace = MACHINES.furnace, assembler = {size = 2, eats = {"slag"}, makes = "gear"}}

    local problems = tracer.problems(entities, {machines = machines, raw = {furnace = true}, product = "gear"})

    assert.has_item_containing("nothing eats plate", problems)
  end)

  it("does not ask for the product to be eaten", function()
    local entities = all_of(machine("furnace", 0, 0), builders.inserter(2, 0, west), belts_from(3, 0, south, 3))

    local problems = tracer.problems(entities, {machines = MACHINES, raw = {furnace = true}, product = "plate"})

    assert.are.same({}, problems)
  end)

  describe("lanes", function()
    -- A belt running south down x = 4, with a machine on each side of its first tile and a
    -- machine that eats both items at the bottom, on the east side.
    local function two_makers_and_an_eater(west_side_item, east_side_item)
      local machines = {
        west_maker = {size = 2, eats = {}, makes = west_side_item},
        east_maker = {size = 2, eats = {}, makes = east_side_item},
        eater = {size = 2, eats = {west_side_item, east_side_item}, makes = "product"},
      }
      local entities = all_of(
        machine("west_maker", 1, 0), builders.inserter(3, 0, west),
        machine("east_maker", 6, 0), builders.inserter(5, 0, east),
        belts_from(4, 0, south, 4),
        builders.inserter(5, 3, west), machine("eater", 6, 3))
      return entities, machines
    end

    it("keeps two items apart when machines on opposite sides of a belt put them on it", function()
      local entities, machines = two_makers_and_an_eater("a", "b")

      local problems = tracer.problems(entities, {machines = machines, raw = {}, product = "product"})

      assert.are.same({}, problems)
    end)

    it("reports a lane that machines on the same side fill with different items", function()
      local entities = all_of(
        machine("first", 1, 0), builders.inserter(3, 0, west),
        machine("second", 1, 2), builders.inserter(3, 2, west),
        belts_from(4, 0, south, 4),
        builders.inserter(5, 3, west), machine("eater", 6, 3))
      local machines = {
        first = {size = 2, eats = {}, makes = "a"}, second = {size = 2, eats = {}, makes = "b"},
        eater = {size = 2, eats = {"a", "b"}, makes = "product"},
      }

      local problems = tracer.problems(entities, {machines = machines, raw = {}, product = "product"})

      assert.has_item_containing("the left lane at 4,2 carries a and b", problems) -- inserters on the west put things on the east lane, the left of a belt running south
    end)

    it("keeps the lanes apart around a curve", function()
      -- The belt runs south down x = 4 and curves east at (4, 2). The first maker is east of the belt: its
      -- inserter is on the belt's left, so it fills the right lane, which is the south lane once the belt runs
      -- east. The second maker is south of the belt running east, so it fills the left lane, the north one.
      local machines = {
        first = {size = 2, eats = {}, makes = "a"}, second = {size = 2, eats = {}, makes = "b"},
        eater = {size = 2, eats = {"a", "b"}, makes = "product"},
      }
      local entities = all_of(
        machine("first", 6, 0), builders.inserter(5, 0, east),
        builders.belt(4, 0, south), builders.belt(4, 1, south), builders.belt(4, 2, east), builders.belt(5, 2, east), builders.belt(6, 2, east),
        machine("second", 5, 4), builders.inserter(5, 3, south),
        builders.inserter(7, 2, west), machine("eater", 8, 2))

      local problems = tracer.problems(entities, {machines = machines, raw = {}, product = "product"})

      assert.are.same({}, problems)
    end)

    it("puts what an inserter in line with a belt that runs away from it drops on the belt's right lane", function()
      -- The first maker's inserter stands behind the belt, which runs south down x = 4. The second maker is east of
      -- the belt, so its inserter is on the belt's
      -- left and fills the right lane too.
      local machines = {
        first = {size = 2, eats = {}, makes = "a"}, second = {size = 2, eats = {}, makes = "b"},
        eater = {size = 2, eats = {"a", "b"}, makes = "product"},
      }
      local entities = all_of(
        machine("first", 3, -3), builders.inserter(4, -1, north),
        machine("second", 6, 1), builders.inserter(5, 1, east),
        belts_from(4, 0, south, 4),
        builders.inserter(5, 3, west), machine("eater", 6, 3))

      local problems = tracer.problems(entities, {machines = machines, raw = {}, product = "product"})

      assert.has_item_containing("the right lane at 4,1 carries a and b", problems)
    end)

    it("takes nothing from a belt that points away from the belt next to it", function()
      -- The belt in (3, 1) points west, away from the belt in (4, 1), so what the maker drops on it does not reach it.
      local machines = {maker = {size = 2, eats = {}, makes = "a"}, eater = {size = 2, eats = {"a"}, makes = "product"}}
      local entities = all_of(
        machine("maker", 2, -2), builders.inserter(3, 0, north), builders.belt(3, 1, west),
        builders.belt(4, 1, south), builders.belt(4, 2, south),
        builders.inserter(5, 2, west), machine("eater", 6, 2))

      local problems = tracer.problems(entities, {machines = machines, raw = {}, product = "product"})

      assert.are.same({"the input inserter at 5,2 never sees a"}, problems)
    end)

    it("puts both lanes of a belt that feeds the side of another on the near lane of the other", function()
      -- The belt in x = 3 runs east into the west side of the belt in x = 4, which has a belt behind it.
      -- It carries one item on each of its lanes (a maker on each side of it).
      local machines = {
        north_maker = {size = 2, eats = {}, makes = "a"}, south_maker = {size = 2, eats = {}, makes = "b"},
        eater = {size = 2, eats = {"a", "b"}, makes = "product"},
      }
      local entities = all_of(
        machine("north_maker", 1, -2), builders.inserter(2, 0, north),
        machine("south_maker", 1, 3), builders.inserter(2, 2, south),
        builders.belt(2, 1, east), builders.belt(3, 1, east),
        builders.belt(4, 0, south), builders.belt(4, 1, south), builders.belt(4, 2, south),
        builders.inserter(5, 2, west), machine("eater", 6, 2))

      local problems = tracer.problems(entities, {machines = machines, raw = {}, product = "product"})

      assert.has_item_containing("the right lane at 4,1 carries a and b", problems) -- the west side of a belt running south is its right
    end)

    it("keeps the two lanes of a belt apart when belts feed it from both sides and none from behind", function()
      -- The belt in x = 4 has nothing behind it; belts feed it from the west and from the east, each with one item.
      local machines = {
        west_maker = {size = 2, eats = {}, makes = "a"}, east_maker = {size = 2, eats = {}, makes = "b"},
        eater = {size = 2, eats = {"a", "b"}, makes = "product"},
      }
      local entities = all_of(
        machine("west_maker", 1, -2), builders.inserter(2, 0, north), builders.belt(2, 1, east), builders.belt(3, 1, east),
        machine("east_maker", 6, -2), builders.inserter(6, 0, north), builders.belt(6, 1, west), builders.belt(5, 1, west),
        builders.belt(4, 1, south), builders.belt(4, 2, south),
        builders.inserter(5, 2, west), machine("eater", 6, 2))

      local problems = tracer.problems(entities, {machines = machines, raw = {}, product = "product"})

      assert.are.same({}, problems)
    end)

    it("puts what an inserter drops onto a curve on the inside lane, whichever side the inserter stands on", function()
      -- The belt runs east along y = 0 and curves north at (6, 0), a left turn: the inside lane is the left one, the
      -- west lane. The first maker's inserter stands south of the curve, in line with the belt, which on a straight
      -- belt would put its item on the right lane, the east one. The second maker fills the right lane of the
      -- belt before the curve (its inserter is on the belt's left), and the curve keeps that lane.
      local machines = {
        first = {size = 2, eats = {}, makes = "a"}, second = {size = 2, eats = {}, makes = "b"},
        eater = {size = 2, eats = {"a", "b"}, makes = "product"},
      }
      local entities = all_of(
        machine("second", 3, -3), builders.inserter(4, -1, north), builders.belt(4, 0, east), builders.belt(5, 0, east),
        builders.belt(6, 0, north), builders.belt(6, -1, north), builders.belt(6, -2, north),
        machine("first", 6, 2), builders.inserter(6, 1, south),
        builders.inserter(7, -2, west), machine("eater", 8, -2))

      local problems = tracer.problems(entities, {machines = machines, raw = {}, product = "product"})

      assert.are.same({}, problems)
    end)

    it("puts what an inserter drops onto a curve on the inside lane of a right turn too", function()
      -- The belt runs east along y = 0 and curves south at (6, 0), a right turn: the inside lane is the right one, the
      -- west lane. The first maker's inserter stands behind the curve and faces north. The second maker fills the left
      -- lane of the belt before the curve (its inserter is south of it, on the belt's right).
      local machines = {
        first = {size = 2, eats = {}, makes = "a"}, second = {size = 2, eats = {}, makes = "b"},
        eater = {size = 2, eats = {"a", "b"}, makes = "product"},
      }
      local entities = all_of(
        machine("second", 3, 2), builders.inserter(4, 1, south), builders.belt(4, 0, east), builders.belt(5, 0, east),
        builders.belt(6, 0, south), builders.belt(6, 1, south), builders.belt(6, 2, south),
        machine("first", 6, -3), builders.inserter(6, -1, north),
        builders.inserter(7, 2, west), machine("eater", 8, 2))

      local problems = tracer.problems(entities, {machines = machines, raw = {}, product = "product"})

      assert.are.same({}, problems)
    end)

    it("puts what an inserter in line with a belt that runs toward it drops on the belt's right lane too", function()
      -- The belt runs north up x = 4 and ends at (4, 0); the first maker's inserter stands in front of its end, so
      -- the belt runs toward it: the right lane of the belt, the east one. The second maker is west of the belt, so
      -- its inserter is on the belt's left and fills the right lane too.
      local machines = {
        first = {size = 2, eats = {}, makes = "a"}, second = {size = 2, eats = {}, makes = "b"},
        eater = {size = 2, eats = {"a", "b"}, makes = "product"},
      }
      local entities = all_of(
        machine("first", 3, -3), builders.inserter(4, -1, north),
        machine("second", 1, 1), builders.inserter(3, 1, west),
        belts_from(4, 2, north, 3),
        builders.inserter(5, 0, west), machine("eater", 6, -1))

      local problems = tracer.problems(entities, {machines = machines, raw = {}, product = "product"})

      assert.has_item_containing("the right lane at 4,0 carries a and b", problems)
    end)
  end)

  describe("belts of raw items that run to an inserter or into the side of a belt", function()
    -- A belt running south down x = 4, a maker on its west side that puts "a" on the far (east, left) lane of its
    -- first tile, and an eater on the east side that takes from its third tile. A belt of "wood" that the player
    -- fills feeds the side of the second tile, from the west or from the east.
    local function maker_belt_and_eater()
      local machines = {
        maker = {size = 2, eats = {}, makes = "a"},
        eater = {size = 2, eats = {"a", "wood"}, makes = "product"},
      }
      local entities = all_of(
        machine("maker", 1, 0), builders.inserter(3, 0, west),
        belts_from(4, 0, south, 4),
        builders.inserter(5, 2, west), machine("eater", 6, 2))
      return entities, machines
    end

    it("puts what the player supplies on the near lane of the belt it feeds from the side", function()
      local entities, machines = maker_belt_and_eater()
      entities[#entities + 1] = builders.belt(3, 1, east)

      local problems = tracer.problems(entities, {
        machines = machines, raw = {}, product = "product", supplies = {{x = 3, y = 1, item = "wood"}},
      })

      assert.are.same({}, problems) -- the west side of a belt running south is its right lane, apart from the maker's left
    end)

    it("reports a lane that what the player supplies shares with what a machine makes", function()
      local entities, machines = maker_belt_and_eater()
      entities[#entities + 1] = builders.belt(5, 1, west)

      local problems = tracer.problems(entities, {
        machines = machines, raw = {}, product = "product", supplies = {{x = 5, y = 1, item = "wood"}},
      })

      assert.has_item_containing("the left lane at 4,1 carries a and wood", problems) -- fed from the east it lands on the left lane too
    end)

    it("reports an input inserter that never sees what the player was not told to supply", function()
      local entities, machines = maker_belt_and_eater()
      entities[#entities + 1] = builders.belt(3, 1, east)

      local problems = tracer.problems(entities, {machines = machines, raw = {}, product = "product"})

      assert.are.same({"the input inserter at 5,2 never sees wood"}, problems)
    end)

    it("puts what the player supplies on both lanes of its belt", function()
      -- The supplied belt runs south down x = 4. A maker on its west side puts "a" on the far (east, left) lane of the
      -- second tile, and a maker on its east side puts "b" on the far (west, right) lane of the same tile.
      local machines = {
        west_maker = {size = 2, eats = {}, makes = "a"}, east_maker = {size = 2, eats = {}, makes = "b"},
      }
      local entities = all_of(
        machine("west_maker", 1, 1), builders.inserter(3, 1, west),
        machine("east_maker", 6, 1), builders.inserter(5, 1, east),
        belts_from(4, 0, south, 3))

      local problems = tracer.problems(entities, {
        machines = machines, raw = {}, product = "product", supplies = {{x = 4, y = 0, item = "wood"}},
      })

      assert.has_item_containing("the left lane at 4,1 carries a and wood", problems)
      assert.has_item_containing("the right lane at 4,1 carries b and wood", problems)
    end)

    it("takes what the player supplies along a belt to an input inserter", function()
      local machines = {eater = {size = 2, eats = {"wood"}, makes = "product"}}
      local entities = all_of(belts_from(3, 0, south, 3), builders.inserter(4, 2, west), machine("eater", 5, 2))

      local problems = tracer.problems(entities, {
        machines = machines, raw = {}, product = "product", supplies = {{x = 3, y = 0, item = "wood"}},
      })

      assert.are.same({}, problems)
    end)
  end)

  describe("long-handed inserters", function()
    -- A maker at x = 0..1 puts "b" on the belt running south down x = 3 (the far lane of its first tile). The belt
    -- next to it, down x = 4, is the one a plain inserter in x = 5 would take from. A long-handed inserter in x = 5,
    -- in row 2, takes from the belt in x = 3 instead, over the belt in x = 4, into an eater at x = 6..7.
    local function belts_and_a_long_inserter_and_an_eater(eats)
      local machines = {
        maker_b = {size = 2, eats = {}, makes = "b"},
        eater = {size = 2, eats = eats, makes = "product"},
      }
      local entities = all_of(
        machine("maker_b", 0, 0), builders.inserter(2, 0, west), belts_from(3, 0, south, 4),
        belts_from(4, 0, south, 4),
        builders.long_inserter(5, 2, west), machine("eater", 6, 2))
      return entities, machines
    end

    it("takes from the belt two tiles away, over the belt next to it", function()
      local entities, machines = belts_and_a_long_inserter_and_an_eater({"b"})

      local problems = tracer.problems(entities, {machines = machines, raw = {}, product = "product"})

      assert.are.same({}, problems)
    end)

    it("does not take from the belt next to it, which a plain inserter would", function()
      -- The belt in x = 4 now carries "a", put there by a maker on its east side in row -2; the eater wants it
      -- too, but the long-handed inserter only sees the belt in x = 3.
      local entities, machines = belts_and_a_long_inserter_and_an_eater({"a", "b"})
      machines.maker_a = {size = 2, eats = {}, makes = "a"}
      entities[#entities + 1] = machine("maker_a", 6, -2)
      entities[#entities + 1] = builders.inserter(5, -2, east)
      entities[#entities + 1] = builders.belt(4, -2, south)
      entities[#entities + 1] = builders.belt(4, -1, south)

      local problems = tracer.problems(entities, {machines = machines, raw = {}, product = "product"})

      assert.are.same({"the input inserter at 5,2 never sees a"}, problems)
    end)

    it("sees what a machine eats between its plain inserter and its long-handed one, each on its own belt", function()
      -- The eater has a plain inserter in row 3 taking from the belt in x = 4 (which carries "a", put there by a maker
      -- on its east side in row -2) and the long-handed inserter in row 2 taking from the belt in x = 3 (which carries "b").
      local entities, machines = belts_and_a_long_inserter_and_an_eater({"a", "b"})
      machines.maker_a = {size = 2, eats = {}, makes = "a"}
      entities[#entities + 1] = machine("maker_a", 6, -2)
      entities[#entities + 1] = builders.inserter(5, -2, east)
      entities[#entities + 1] = builders.belt(4, -2, south)
      entities[#entities + 1] = builders.belt(4, -1, south)
      entities[#entities + 1] = builders.inserter(5, 3, west)

      local problems = tracer.problems(entities, {machines = machines, raw = {}, product = "product"})

      assert.are.same({}, problems)
    end)

    it("reports a long-handed inserter that puts items on a belt, which the tracer does not follow", function()
      local machines = {maker = {size = 2, eats = {}, makes = "a"}}
      local entities = all_of(machine("maker", 0, 0), builders.long_inserter(3, 0, west), belts_from(5, 0, south, 3))

      local problems = tracer.problems(entities, {machines = machines, raw = {}, product = "product"})

      assert.has_item_containing("the long-handed inserter at 3,0 puts items on a belt", problems)
    end)
  end)

  describe("splitters", function()
    -- Two makers put "a" and "b" on the two lanes of a belt running south down x = 4 (the west one on the east, left lane,
    -- the east one on the west, right lane). Under it a splitter facing south covers (4, 2) and (5, 2); the belt feeds its
    -- west half. Its outputs run on down x = 4 and x = 5, and an eater in x = 7 takes from the one in x = 5.
    local function two_makers_a_splitter_and_an_eater()
      local machines = {
        west_maker = {size = 2, eats = {}, makes = "a"}, east_maker = {size = 2, eats = {}, makes = "b"},
        eater = {size = 2, eats = {"a", "b"}, makes = "product"},
      }
      local entities = all_of(
        machine("west_maker", 1, 0), builders.inserter(3, 0, west),
        machine("east_maker", 6, 0), builders.inserter(5, 0, east),
        belts_from(4, 0, south, 2), builders.splitter(4, 2, south),
        builders.belt(4, 3, south), builders.belt(5, 3, south),
        builders.inserter(6, 3, west), machine("eater", 7, 3))
      return entities, machines
    end

    it("keeps the two lanes of its input apart in both of its outputs", function()
      local entities, machines = two_makers_a_splitter_and_an_eater()

      local problems = tracer.problems(entities, {machines = machines, raw = {}, product = "product"})

      assert.are.same({}, problems)
    end)

    it("gives both outputs what both inputs bring, so two belts that share lanes are reported after it", function()
      -- Two belts run east into the west side... into the two halves of a splitter facing east, one carrying "a" on both
      -- its lanes and the other "b".
      local entities = all_of(
        builders.belt(0, 0, east), builders.belt(0, 1, east), builders.splitter(1, 0, east),
        builders.belt(2, 0, east), builders.belt(2, 1, east))

      local problems = tracer.problems(entities, {
        machines = {}, raw = {}, product = "product", supplies = {{x = 0, y = 0, item = "a"}, {x = 0, y = 1, item = "b"}},
      })

      assert.has_item_containing("the left lane at 2,0 carries a and b", problems)
      assert.has_item_containing("the right lane at 2,1 carries a and b", problems)
    end)

    it("reports a belt that feeds the side of a splitter", function()
      local entities = all_of(builders.belt(3, 2, east), builders.splitter(4, 2, south))

      local problems = tracer.problems(entities, {machines = {}, raw = {}, product = "product"})

      assert.has_item_containing("a belt feeds the side of the splitter at 4,2", problems)
    end)
  end)

  describe("underground belts", function()
    -- A maker in x = 1..2 puts "a" on the belt running south down x = 4; the belt goes under another belt that runs east
    -- along row 3 and comes up again, and an eater takes "a" from the belt after it. The other belt carries "b" (the
    -- player supplies it) to a second eater.
    local function underground_under_a_crossing(exit_row)
      local machines = {
        maker = {size = 2, eats = {}, makes = "a"},
        eater = {size = 2, eats = {"a"}, makes = "product"}, other_eater = {size = 2, eats = {"b"}, makes = "other"},
      }
      local entities = all_of(
        machine("maker", 1, 0), builders.inserter(3, 0, west), belts_from(4, 0, south, 2),
        builders.underground(4, 2, south, "input"), builders.underground(4, exit_row, south, "output"),
        builders.belt(3, 3, east), builders.belt(4, 3, east), builders.belt(5, 3, east),
        builders.inserter(6, 3, west), machine("other_eater", 7, 3),
        builders.belt(4, exit_row + 1, south), builders.inserter(5, exit_row + 1, west), machine("eater", 6, exit_row + 1))
      return entities, machines
    end

    it("takes what is behind its entrance out of its exit, over a belt that crosses in between", function()
      local entities, machines = underground_under_a_crossing(5)

      local problems = tracer.problems(entities, {
        machines = machines, raw = {}, product = "product", supplies = {{x = 3, y = 3, item = "b"}},
      })

      assert.are.same({}, problems)
    end)

    it("reports an entrance that meets no exit within the reach of the belt", function()
      local entities, machines = underground_under_a_crossing(5)

      local problems = tracer.problems(entities, {
        machines = machines, raw = {}, product = "product", supplies = {{x = 3, y = 3, item = "b"}}, underground_reach = 2,
      })

      assert.has_item_containing("the underground belt entrance at 4,2 meets no exit within reach", problems)
    end)

    it("reports an exit that no entrance feeds", function()
      local entities = all_of(builders.underground(4, 5, south, "output"))

      local problems = tracer.problems(entities, {machines = {}, raw = {}, product = "product"})

      assert.are.same({"the underground belt exit at 4,5 has no entrance"}, problems)
    end)

    it("reports an entrance that meets another piece of an underground belt before its exit", function()
      local entities = all_of(
        builders.underground(4, 2, south, "input"), builders.underground(4, 4, south, "input"), builders.underground(4, 6, south, "output"))

      local problems = tracer.problems(entities, {machines = {}, raw = {}, product = "product"})

      assert.has_item_containing("the underground belt entrance at 4,2 meets no exit within reach", problems)
    end)

    it("reports a belt that feeds the side of an entrance", function()
      local entities = all_of(builders.belt(3, 2, east), builders.underground(4, 2, south, "input"), builders.underground(4, 4, south, "output"))

      local problems = tracer.problems(entities, {machines = {}, raw = {}, product = "product"})

      assert.are.same({"a belt feeds the side of the entrance at 4,2"}, problems)
    end)
  end)

  describe("the lanes of the belt of a machine fed raw items", function()
    -- A belt running south down x = 3, fed from its two sides in its first tile (nothing is behind it): from the west by a
    -- belt of `west_item` and from the east by a belt of `east_item`. A furnace takes from it with an inserter in x = 4,
    -- row 2. The west side of a belt running south is its right lane.
    local function furnace_on_a_belt_fed_from_both_sides(west_item, east_item)
      local entities = all_of(
        builders.belt(2, 0, east), builders.belt(4, 0, west), builders.belt(3, 0, south), builders.belt(3, 1, south), builders.belt(3, 2, south),
        builders.inserter(4, 2, west), machine("furnace", 5, 2))
      local supplies = {{x = 2, y = 0, item = west_item}, {x = 4, y = 0, item = east_item}}
      return entities, supplies
    end

    it("accepts the ore on one lane and the fuel on the other, whichever lane each is on", function()
      local entities, supplies = furnace_on_a_belt_fed_from_both_sides("ore", "coal")

      local problems = tracer.problems(entities, {
        machines = MACHINES, raw = {furnace = true}, product = "plate", supplies = supplies, raw_lanes = {furnace = {"ore", "coal"}},
      })

      assert.are.same({}, problems)
    end)

    it("reports a belt that holds the ore on both lanes when the furnace needs the fuel on one", function()
      local entities, supplies = furnace_on_a_belt_fed_from_both_sides("ore", "ore")

      local problems = tracer.problems(entities, {
        machines = MACHINES, raw = {furnace = true}, product = "plate", supplies = supplies, raw_lanes = {furnace = {"ore", "coal"}},
      })

      assert.are.same({"the belt next to the inserter at 4,2 carries [ore] on its left lane and [ore] on its right lane, not ore and coal"}, problems)
    end)

    it("reports a belt that holds something else on a lane", function()
      local entities, supplies = furnace_on_a_belt_fed_from_both_sides("ore", "stone")

      local problems = tracer.problems(entities, {
        machines = MACHINES, raw = {furnace = true}, product = "plate", supplies = supplies, raw_lanes = {furnace = {"ore", "coal"}},
      })

      assert.has_item_containing("[stone] on its left lane and [ore] on its right lane, not ore and coal", problems)
    end)

    it("accepts a lone item on both lanes when the machine needs just that", function()
      local entities = all_of(
        builders.belt(3, 0, south), builders.belt(3, 1, south), builders.inserter(4, 1, west), machine("furnace", 5, 1))

      local problems = tracer.problems(entities, {
        machines = MACHINES, raw = {furnace = true}, product = "plate",
        supplies = {{x = 3, y = 0, item = "wood"}}, raw_lanes = {furnace = {"wood"}},
      })

      assert.are.same({}, problems)
    end)

    it("reports a lone item that is only on one lane", function()
      -- The belt from the west side-loads the belt down x = 3, which has an empty belt behind it, so it stays straight and
      -- the wood lands on its right lane only.
      local entities = all_of(
        builders.belt(2, 0, east), builders.belt(3, -1, south), builders.belt(3, 0, south), builders.belt(3, 1, south),
        builders.inserter(4, 1, west), machine("furnace", 5, 1))

      local problems = tracer.problems(entities, {
        machines = MACHINES, raw = {furnace = true}, product = "plate",
        supplies = {{x = 2, y = 0, item = "wood"}}, raw_lanes = {furnace = {"wood"}},
      })

      assert.has_item_containing("[] on its left lane and [wood] on its right lane, not wood", problems)
    end)
  end)

  it("reports a belt of raw items that something we made is put on", function()
    local entities = all_of(
      machine("furnace", 0, 0), builders.inserter(2, 0, west), belts_from(3, 0, south, 3),
      machine("furnace", 5, 2), builders.inserter(4, 2, west)) -- the second furnace takes its ore from the first one's plate belt

    local problems = tracer.problems(entities, {machines = MACHINES, raw = {furnace = true}, product = "plate"})

    assert.are.same({"the belt of raw items next to the inserter at 4,2 carries plate"}, problems)
  end)

  it("reports a belt that carries the product together with something else", function()
    local machines = {
      product_maker = {size = 2, eats = {}, makes = "product"}, other_maker = {size = 2, eats = {}, makes = "other"},
      eater = {size = 2, eats = {"other"}, makes = "gear"},
    }
    local entities = all_of(
      machine("product_maker", 1, 0), builders.inserter(3, 0, west),
      machine("other_maker", 6, 0), builders.inserter(5, 0, east),
      belts_from(4, 0, south, 4),
      builders.inserter(5, 3, west), machine("eater", 6, 3))

    local problems = tracer.problems(entities, {machines = machines, raw = {}, product = "product"})

    assert.has_item_containing("carries the product together with something else", problems)
  end)
end)
