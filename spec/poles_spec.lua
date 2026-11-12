-- spec/poles_spec.lua
-- Joining the poles of the columns of a blueprint into one network (see scripts/poles.lua). Positions are tiles
-- (see scripts/grid.lua): a pole on tile (7, 0) is at position (7.5, 0.5). A wire is stored once, on the pole it
-- starts from, as {from number, connector, to number, connector}.
---@diagnostic disable: undefined-field  -- luassert's `assert` has fields (`assert.are`, `assert.is_nil`, ...) the editor cannot see

local builders = require("spec.support.builders")
local poles = require("scripts.poles")

local NAMES = builders.NAMES
local CONNECTOR = defines.wire_connector_id.pole_copper
local SMALL_WIRE = NAMES.pole_wire_distance -- 7.5: poles are put at most 7 apart
local MEDIUM_WIRE = builders.POLES.medium.wire_distance -- 9: poles are put at most 8.5 apart

-- A pole with the number it has in the blueprint.
local function pole_at(number, tile_x, tile_y)
  local pole = builders.pole(tile_x, tile_y)
  pole.entity_number = number
  return pole
end

-- The bridge for a blueprint that has these poles, whose wire holds `wire_distance` tiles: bridge poles are added to the
-- same list.
local function bridge_for(entities, wire_distance, taken)
  return {entities = entities, taken = taken or {}, pole = NAMES.pole, wire_distance = wire_distance}
end

describe("poles", function()
  describe("joining groups of poles", function()
    it("wires the nearest pair of poles of two groups", function()
      local near_end, far_end = pole_at(2, 3, 0), pole_at(1, 0, 0)
      local first, second = pole_at(3, 6, 0), pole_at(4, 20, 0)

      poles.join({{far_end, near_end}, {first, second}})

      assert.are.same({{2, CONNECTOR, 3, CONNECTOR}}, near_end.wires)
    end)

    it("wires nothing else", function()
      local far_end, near_end = pole_at(1, 0, 0), pole_at(2, 3, 0)
      local first, second = pole_at(3, 6, 0), pole_at(4, 20, 0)

      poles.join({{far_end, near_end}, {first, second}})

      assert.is_nil(far_end.wires)
      assert.is_nil(first.wires)
      assert.is_nil(second.wires)
    end)

    it("joins the nearest group first, and the next to the nearest pole of the poles joined so far", function()
      local west, middle, east = pole_at(1, 0, 0), pole_at(2, 5, 0), pole_at(3, 10, 0)

      poles.join({{west}, {east}, {middle}})

      assert.are.same({{{1, CONNECTOR, 2, CONNECTOR}}, {{2, CONNECTOR, 3, CONNECTOR}}}, {west.wires, middle.wires})
    end)

    it("leaves out a group with no pole", function()
      local west, east = pole_at(1, 0, 0), pole_at(2, 5, 0)

      poles.join({{west}, {}, {east}})

      assert.are.same({{1, CONNECTOR, 2, CONNECTOR}}, west.wires)
    end)

    it("keeps the first of two pairs that are equally near", function()
      local first, second = pole_at(1, 0, 0), pole_at(2, 0, 10)
      local between = pole_at(3, 5, 5) -- 7.07 tiles from both

      poles.join({{first, second}, {between}})

      assert.are.same({{1, CONNECTOR, 3, CONNECTOR}}, first.wires)
      assert.is_nil(second.wires)
    end)

    it("joins the first of two groups that are equally near first", function()
      local middle, east, west = pole_at(1, 0, 0), pole_at(2, 5, 0), pole_at(3, -5, 0)

      poles.join({{middle}, {east}, {west}})

      assert.are.same({{1, CONNECTOR, 2, CONNECTOR}, {1, CONNECTOR, 3, CONNECTOR}}, middle.wires)
    end)

    it("starts from the first group that has a pole when the groups before it have none", function()
      local west, east = pole_at(1, 0, 0), pole_at(2, 5, 0)

      poles.join({{}, {west}, {east}})

      assert.are.same({{1, CONNECTOR, 2, CONNECTOR}}, west.wires)
    end)

    it("wires nothing for one group", function()
      local only = pole_at(1, 0, 0)

      poles.join({{only}})

      assert.is_nil(only.wires)
    end)

    it("wires poles that are far apart when there is no bridge, as the original design does", function()
      local west, east = pole_at(1, 0, 0), pole_at(2, 30, 0)

      poles.join({{west}, {east}})

      assert.are.same({{1, CONNECTOR, 2, CONNECTOR}}, west.wires)
    end)
  end)

  describe("bridging poles that are further apart than a wire reaches", function()
    it("wires poles that are exactly as far apart as a wire reaches without a pole between", function()
      local west, east = pole_at(1, 0, 0), pole_at(2, 7, 0)
      local entities = {west, east}

      poles.join({{west}, {east}}, bridge_for(entities, SMALL_WIRE))

      assert.are.equal(2, #entities)
    end)

    it("puts a pole as far toward the other pole as a wire reaches when they are further apart than that", function()
      local west, east = pole_at(1, 0, 0), pole_at(2, 8, 0)
      local entities = {west, east}

      poles.join({{west}, {east}}, bridge_for(entities, SMALL_WIRE))

      assert.are.same({x = 7.5, y = 0.5}, entities[3].position)
    end)

    it("names and numbers the pole it adds after the entities already there", function()
      local west, east = pole_at(1, 0, 0), pole_at(2, 14, 0)
      local entities = {west, east}

      poles.join({{west}, {east}}, bridge_for(entities, SMALL_WIRE))

      assert.are.same({NAMES.pole, 3}, {entities[3].name, entities[3].entity_number})
    end)

    it("wires the first pole to the new one and the new one to the second", function()
      local west, east = pole_at(1, 0, 0), pole_at(2, 14, 0)
      local entities = {west, east}

      poles.join({{west}, {east}}, bridge_for(entities, SMALL_WIRE))

      assert.are.same({{{1, CONNECTOR, 3, CONNECTOR}}, {{3, CONNECTOR, 2, CONNECTOR}}}, {west.wires, entities[3].wires})
    end)

    it("keeps the pole off a tile that holds something and goes as far as it can on a free one", function()
      local west, east = pole_at(1, 0, 0), pole_at(2, 14, 0)
      local entities = {west, east}

      poles.join({{west}, {east}}, bridge_for(entities, SMALL_WIRE, {["7,0"] = true})) -- the tile it would have used

      assert.are.same({{x = 6.5, y = 0.5}, {x = 13.5, y = 0.5}}, {entities[3].position, entities[4].position})
    end)

    it("chains as many poles as the gap needs", function()
      local west, east = pole_at(1, 0, 0), pole_at(2, 21, 0)
      local entities = {west, east}

      poles.join({{west}, {east}}, bridge_for(entities, SMALL_WIRE))

      assert.are.same({{x = 7.5, y = 0.5}, {x = 14.5, y = 0.5}}, {entities[3].position, entities[4].position})
    end)

    it("does not put a second pole on the tile of the first", function()
      local west, east = pole_at(1, 0, 0), pole_at(2, 14, 0)
      local taken = {}

      poles.join({{west}, {east}}, bridge_for({west, east}, SMALL_WIRE, taken))

      assert.is_true(taken["7,0"])
    end)

    it("wires medium poles that are 8 tiles apart without a pole between, which a small pole's wire would not hold", function()
      local west, east = pole_at(1, 0, 0), pole_at(2, 8, 0)
      local entities = {west, east}

      poles.join({{west}, {east}}, bridge_for(entities, MEDIUM_WIRE))

      assert.are.equal(2, #entities)
    end)

    it("puts a pole as far toward the other pole as a medium pole's wire reaches, 8 tiles of the 9 it holds", function()
      local west, east = pole_at(1, 0, 0), pole_at(2, 10, 0)
      local entities = {west, east}

      poles.join({{west}, {east}}, bridge_for(entities, MEDIUM_WIRE))

      assert.are.same({x = 8.5, y = 0.5}, entities[3].position)
    end)

    it("gives up, saying so, when no free tile within reach is nearer to the other pole", function()
      local west, east = pole_at(1, 0, 0), pole_at(2, 14, 0)
      local taken = {}
      for x = -8, 16 do
        for y = -8, 8 do
          taken[x .. "," .. y] = true
        end
      end

      assert.has_error(function() poles.join({{west}, {east}}, bridge_for({west, east}, SMALL_WIRE, taken)) end, "poles: no room for a pole between two poles")
    end)
  end)

  describe("the tiles that hold something", function()
    it("marks every tile an entity covers, from its top-left tile", function()
      local furnace = builders.furnace(2, 3)

      local taken = poles.taken_tiles({furnace}, function() return 2, 2 end)

      assert.are.same({["2,3"] = true, ["3,3"] = true, ["2,4"] = true, ["3,4"] = true}, taken)
    end)

    it("asks for the size of each entity separately", function()
      local belt, splitter = builders.belt(0, 0), builders.splitter(5, 5, defines.direction.south)
      local function size_of(entity)
        if entity.name == NAMES.splitter then
          return 2, 1
        end
        return 1, 1
      end

      local taken = poles.taken_tiles({belt, splitter}, size_of)

      assert.are.same({["0,0"] = true, ["5,5"] = true, ["6,5"] = true}, taken)
    end)
  end)
end)
