-- spec/entity_list_spec.lua
-- How an entity gets its number as it is added to the entity list of a blueprint (see scripts/entity_list.lua).
---@diagnostic disable: undefined-field  -- luassert's `assert` has fields (`assert.are`, `assert.is_nil`, ...) the editor cannot see

local entity_list = require("scripts.entity_list")

describe("entity_list", function()
  describe("merge", function()
    local function two_poles()
      local first = {name = "pole", entity_number = 1, position = {x = 0.5, y = 0.5}}
      local second = {name = "pole", entity_number = 2, position = {x = 3.5, y = 0.5}}
      first.wires = {{1, "copper", 2, "copper"}}
      return {first, second, {name = "belt", entity_number = 3, position = {x = 1.5, y = 2.5}, direction = "south"}}
    end

    it("adds the entities moved by the tiles, after the ones in the target", function()
      local target = {{name = "lamp", entity_number = 1, position = {x = 9.5, y = 9.5}}}

      local added = entity_list.merge(target, two_poles(), 10, 5)

      assert.are.same({{10.5, 5.5}, {13.5, 5.5}, {11.5, 7.5}}, {
        {added[1].position.x, added[1].position.y}, {added[2].position.x, added[2].position.y}, {added[3].position.x, added[3].position.y},
      })
      assert.are.same({2, 3, 4}, {added[1].entity_number, added[2].entity_number, added[3].entity_number})
      assert.are.equal(4, #target)
    end)

    it("keeps what else an entity has, the direction", function()
      local target = {}

      local added = entity_list.merge(target, two_poles(), 0, 0)

      assert.are.same({"belt", "south"}, {added[3].name, added[3].direction})
    end)

    it("gives the wires of the poles the new numbers of the poles they join", function()
      local target = {{name = "lamp", entity_number = 1, position = {x = 0.5, y = 0.5}}, {name = "lamp", entity_number = 2, position = {x = 0.5, y = 1.5}}}

      local added = entity_list.merge(target, two_poles(), 4, 0)

      assert.are.same({{3, "copper", 4, "copper"}}, added[1].wires)
    end)

    it("leaves the entities of the source as they were", function()
      local source = two_poles()

      entity_list.merge({}, source, 5, 5)

      assert.are.same({{0.5, 0.5}, {1, "copper", 2, "copper"}}, {{source[1].position.x, source[1].position.y}, source[1].wires[1]})
    end)

    it("gives no wires to an entity that had none", function()
      local added = entity_list.merge({}, two_poles(), 0, 0)

      assert.is_nil(added[2].wires)
    end)
  end)

  describe("append", function()
    it("numbers the first entity of an empty list 1", function()
      local list = {}

      local belt = entity_list.append(list, {name = "belt"})

      assert.are.equal(1, belt.entity_number)
    end)

    it("numbers an entity after the ones that are in the list", function()
      local list = {{name = "belt", entity_number = 1}, {name = "belt", entity_number = 2}}

      local inserter = entity_list.append(list, {name = "inserter"})

      assert.are.equal(3, inserter.entity_number)
    end)

    it("puts the entity at the end of the list", function()
      local list = {{name = "belt", entity_number = 1}}

      entity_list.append(list, {name = "inserter"})

      assert.are.same({"belt", "inserter"}, {list[1].name, list[2].name})
    end)

    it("gives back the table it was given, with the number in it", function()
      local list = {}
      local entity = {name = "belt"}

      local numbered = entity_list.append(list, entity)

      assert.are.equal(entity, numbered)
    end)
  end)
end)
