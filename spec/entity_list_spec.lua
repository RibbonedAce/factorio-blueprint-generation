-- spec/entity_list_spec.lua
-- How an entity gets its number as it is added to the entity list of a blueprint (see scripts/entity_list.lua).
---@diagnostic disable: undefined-field  -- luassert's `assert` has fields (`assert.are`, `assert.is_nil`, ...) the editor cannot see

local entity_list = require("scripts.entity_list")

describe("entity_list", function()
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
