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

  describe("a fast inserter", function()
    it("is on its tile, with the name the layout is given for fast inserters and the direction it is given", function()
      local inserter = builders.fast_inserter(3, 2, east)

      assert.are.same({builders.NAMES.fast_inserter, 3.5, 2.5, east}, {inserter.name, inserter.position.x, inserter.position.y, inserter.direction})
    end)

    it("is known to the catalog as an inserter that picks up from the next tile", function()
      local entry = builders.a_catalog{}[builders.NAMES.fast_inserter]

      assert.are.same({"inserter", 1, 1, true, nil}, {entry.kind, entry.width, entry.height, entry.needs_power, entry.reach})
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

    it("knows the medium pole as a pole that powers 3.5 tiles and holds a wire of 9 unless it is told otherwise", function()
      local entry = builders.a_catalog{}[builders.POLES.medium.name]

      assert.are.same({"pole", 1, 1, 3.5, 9}, {entry.kind, entry.width, entry.height, entry.supply_radius, entry.wire_reach})
    end)

    it("gives the medium pole the radius and the wire it is told", function()
      local entry = builders.a_catalog{medium_pole_supply_radius = 4, medium_pole_wire_reach = 10}[builders.POLES.medium.name]

      assert.are.same({4, 10}, {entry.supply_radius, entry.wire_reach})
    end)

    it("knows the small pole as a pole that powers 2.5 tiles and holds a wire of 7.5 unless it is told otherwise", function()
      local entry = builders.a_catalog{}[builders.POLES.small.name]

      assert.are.same({"pole", 1, 1, 2.5, 7.5}, {entry.kind, entry.width, entry.height, entry.supply_radius, entry.wire_reach})
    end)
  end)

  describe("the poles", function()
    it("are the base game's: the small pole powers 2.5 tiles and holds a wire of 7.5, the medium pole 3.5 and 9", function()
      assert.are.same({
        small = {name = "small-electric-pole", supply_distance = 2.5, wire_distance = 7.5},
        medium = {name = "medium-electric-pole", supply_distance = 3.5, wire_distance = 9},
      }, builders.POLES)
    end)
  end)

  describe("the names with the medium pole", function()
    it("are the names of the layout with the medium pole and its numbers in place of the small pole's", function()
      local names = builders.medium_pole_names()

      assert.are.same({"medium-electric-pole", 3.5, 9, builders.NAMES.belt}, {names.pole, names.pole_supply_distance, names.pole_wire_distance, names.belt})
    end)

    it("leave the names of the layout as they were", function()
      builders.medium_pole_names()

      assert.are.same({"small-electric-pole", 2.5, 7.5}, {builders.NAMES.pole, builders.NAMES.pole_supply_distance, builders.NAMES.pole_wire_distance})
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

    it("has no fast belts unless it is told to", function()
      local entities = builders.fake_prototypes{}.entity

      assert.are.same({nil, nil, nil}, {entities["fast-transport-belt"], entities["fast-splitter"], entities["fast-underground-belt"]})
    end)

    it("has the fast belts when it is told to: a belt of twice the speed and an underground belt of 7 tiles", function()
      local entities = builders.fake_prototypes{fast_belts = true}.entity

      assert.are.same({0.0625, 7, true}, {entities["fast-transport-belt"].belt_speed, entities["fast-underground-belt"].max_underground_distance, entities["fast-splitter"] ~= nil})
    end)

    it("gives the fast belt the speed and the fast underground belt the span it is told", function()
      local entities = builders.fake_prototypes{fast_belts = true, fast_belt_speed = 0.05, fast_underground_distance = 6}.entity

      assert.are.same({0.05, 6}, {entities["fast-transport-belt"].belt_speed, entities["fast-underground-belt"].max_underground_distance})
    end)

    it("leaves the fast belt's speed out when it is told there is none", function()
      assert.is_nil(builders.fake_prototypes{fast_belts = true, fast_belt_speed = false}.entity["fast-transport-belt"].belt_speed)
    end)

    it("can leave a fast belt out of the fast belts", function()
      assert.is_nil(builders.fake_prototypes{fast_belts = true, missing_entities = {"fast-splitter"}}.entity["fast-splitter"])
    end)

    it("has a fast inserter that swings at 0.04 unless it is told otherwise", function()
      assert.are.equal(0.04, builders.fake_prototypes{}.entity["fast-inserter"].get_inserter_rotation_speed())
    end)

    it("gives the fast inserter the speed it is told", function()
      assert.are.equal(0.05, builders.fake_prototypes{fast_inserter_rotation_speed = 0.05}.entity["fast-inserter"].get_inserter_rotation_speed())
    end)

    it("leaves the fast inserter's speed out when it is told there is none", function()
      assert.is_nil(builders.fake_prototypes{fast_inserter_rotation_speed = false}.entity["fast-inserter"].get_inserter_rotation_speed())
    end)

    it("gives every inserter no stack size bonus of its own, and the force's research counts for it, unless it is told otherwise", function()
      local entities = builders.fake_prototypes{}.entity

      local stacks = {}
      for _, name in ipairs({"inserter", "long-handed-inserter", "fast-inserter"}) do
        stacks[name] = {entities[name].inserter_stack_size_bonus, entities[name].uses_inserter_stack_size_bonus}
      end

      assert.are.same({["inserter"] = {0, true}, ["long-handed-inserter"] = {0, true}, ["fast-inserter"] = {0, true}}, stacks)
    end)

    it("gives an inserter the stack size bonus it is told, and the others none", function()
      local entities = builders.fake_prototypes{inserter_stacks = {["fast-inserter"] = {built_in = 2}}}.entity

      assert.are.same({0, 2}, {entities["inserter"].inserter_stack_size_bonus, entities["fast-inserter"].inserter_stack_size_bonus})
    end)

    it("makes an inserter the force's research does not count for when it is told so", function()
      local entities = builders.fake_prototypes{inserter_stacks = {["long-handed-inserter"] = {takes_research = false}}}.entity

      assert.are.same({true, false}, {entities["inserter"].uses_inserter_stack_size_bonus, entities["long-handed-inserter"].uses_inserter_stack_size_bonus})
    end)

    it("leaves the stack size bonus out when it is told the game does not say", function()
      local inserter = builders.fake_prototypes{inserter_stacks = {["inserter"] = {built_in = false}}}.entity["inserter"]

      assert.is_nil(inserter.inserter_stack_size_bonus)
    end)

    it("leaves out whether the research counts when it is told the game does not say", function()
      local inserter = builders.fake_prototypes{inserter_stacks = {["inserter"] = {takes_research = "unsaid"}}}.entity["inserter"]

      assert.is_nil(inserter.uses_inserter_stack_size_bonus)
    end)

    it("has a small pole that powers 2.5 tiles and holds a wire of 7.5", function()
      local pole = builders.fake_prototypes{}.entity["small-electric-pole"]

      assert.are.same({2.5, 7.5}, {pole.get_supply_area_distance(), pole.get_max_wire_distance()})
    end)

    it("has a medium pole that powers 3.5 tiles and holds a wire of 9 unless it is told otherwise", function()
      local pole = builders.fake_prototypes{}.entity["medium-electric-pole"]

      assert.are.same({3.5, 9}, {pole.get_supply_area_distance(), pole.get_max_wire_distance()})
    end)

    it("gives the small pole the distances it is told, and leaves them out when it is told there are none", function()
      local told = builders.fake_prototypes{small_pole_supply_distance = 3, small_pole_wire_distance = 8}.entity["small-electric-pole"]
      local none = builders.fake_prototypes{small_pole_supply_distance = false, small_pole_wire_distance = false}.entity["small-electric-pole"]

      assert.are.same({{3, 8}, {nil, 0}}, {{told.get_supply_area_distance(), told.get_max_wire_distance()}, {none.get_supply_area_distance(), none.get_max_wire_distance()}})
    end)

    it("gives the medium pole the distances it is told", function()
      local pole = builders.fake_prototypes{medium_pole_supply_distance = 2.5, medium_pole_wire_distance = 7.5}.entity["medium-electric-pole"]

      assert.are.same({2.5, 7.5}, {pole.get_supply_area_distance(), pole.get_max_wire_distance()})
    end)

    it("leaves out how far the medium pole powers when it is told there is none, and gives a wire of 0, as the game does for an entity with no wire", function()
      local pole = builders.fake_prototypes{medium_pole_supply_distance = false, medium_pole_wire_distance = false}.entity["medium-electric-pole"]

      assert.are.same({nil, 0}, {pole.get_supply_area_distance(), pole.get_max_wire_distance()})
    end)

    it("leaves out the buildings it is told the game does not have", function()
      local prototypes = builders.fake_prototypes{missing_entities = {"splitter"}}

      assert.is_nil(prototypes.entity["splitter"])
      assert.is_not_nil(prototypes.entity["underground-belt"])
    end)
  end)

  describe("the numbering of entities", function()
    it("numbers the entities of a list from 1 in the order of the list", function()
      local list = builders.numbered({builders.belt(0, 0), builders.belt(1, 0)})

      assert.are.same({1, 2}, {list[1].entity_number, list[2].entity_number})
    end)

    it("numbers the entities it is passed in the order passed", function()
      local list = builders.blueprint_of(builders.belt(0, 0), builders.furnace(2, 0))

      assert.are.same({1, 2}, {list[1].entity_number, list[2].entity_number})
    end)
  end)

  describe("looking entities up by name", function()
    it("lists the entities that have the name, in the order of the list", function()
      local entities = {builders.belt(0, 0), builders.furnace(2, 0), builders.belt(5, 0)}

      local belts = builders.entities_named(entities, builders.NAMES.belt)

      assert.are.same({entities[1], entities[3]}, belts)
    end)

    it("counts the entities that have the name", function()
      local entities = {builders.belt(0, 0), builders.furnace(2, 0), builders.belt(5, 0)}

      local count = builders.count_named(entities, builders.NAMES.belt)

      assert.are.equal(2, count)
    end)

    it("lists the rows of the belts in a tile column, from the top", function()
      local entities = {builders.belt(3, 4), builders.belt(3, 1), builders.belt(2, 0)}

      local rows = builders.belt_rows(entities, 3)

      assert.are.same({1, 4}, rows)
    end)

    it("lists each direction the belts of a tile column face once, in the order they are met", function()
      local entities = {builders.belt(3, 0, east), builders.belt(3, 1, south), builders.belt(3, 2, east), builders.belt(4, 0, south)}

      local directions = builders.belt_directions(entities, 3)

      assert.are.same({east, south}, directions)
    end)
  end)

  describe("merging fields", function()
    it("puts the changes over the fields of the base without touching the base", function()
      local base = {speed = 1, size = 3}

      local merged = builders.merged(base, {size = 2, name = "x"})

      assert.are.same({{speed = 1, size = 2, name = "x"}, {speed = 1, size = 3}}, {merged, base})
    end)

    it("copies the base when there are no changes", function()
      local base = {speed = 1}

      local merged = builders.merged(base)

      assert.are.same({true, false}, {merged.speed == 1, merged == base})
    end)
  end)

  describe("the distance between the closest two tiles", function()
    it("is the shortest of the distances between any two of them", function()
      local closest = builders.closest_pair({{x = 0, y = 0}, {x = 10, y = 0}, {x = 13, y = 4}})

      assert.are.equal(5, closest)
    end)

    it("is infinity for fewer than two tiles", function()
      local closest = builders.closest_pair({{x = 0, y = 0}})

      assert.are.equal(math.huge, closest)
    end)
  end)

  describe("replacing a function of a module for one run", function()
    it("gives back what the run gives, with the replacement in place while it runs", function()
      local module = {greet = function() return "hello" end}

      local seen = builders.with_replaced(module, "greet", function() return "hi" end, function() return module.greet() end)

      assert.are.equal("hi", seen)
    end)

    it("puts the original back after the run", function()
      local module = {greet = function() return "hello" end}

      builders.with_replaced(module, "greet", function() return "hi" end, function() end)

      assert.are.equal("hello", module.greet())
    end)

    it("fails with the message of the run when the run fails", function()
      local module = {greet = function() return "hello" end}

      local function failing() builders.with_replaced(module, "greet", function() end, function() error("boom", 0) end) end

      assert.has_error(failing, "boom")
    end)

    it("puts the original back when the run fails", function()
      local module = {greet = function() return "hello" end}

      pcall(builders.with_replaced, module, "greet", function() end, function() error("boom", 0) end)

      assert.are.equal("hello", module.greet())
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

    it("has researched no inserter capacity bonus unless it is told otherwise", function()
      assert.are.equal(0, builders.fake_force{}.inserter_stack_size_bonus)
    end)

    it("has the inserter capacity bonus it is told", function()
      assert.are.equal(1.5, builders.fake_force{inserter_stack_size_bonus = 1.5}.inserter_stack_size_bonus)
    end)

    it("leaves out the inserter capacity bonus when it is told the game does not say", function()
      assert.is_nil(builders.fake_force{inserter_stack_size_bonus = false}.inserter_stack_size_bonus)
    end)
  end)
end)
