-- spec/lights_spec.lua
-- What the lamps of a blueprint are and where they stand (see scripts/lights.lua). Positions are TILES, read off
-- the pictures: the top-left tile an entity covers, with y growing down (see scripts/grid.lua).
---@diagnostic disable: undefined-field  -- luassert's `assert` has fields (`assert.are`, `assert.is_nil`, ...) the editor cannot see

local builders = require("spec.support.builders")
local grid = require("scripts.grid")
local lights = require("scripts.lights")

local NAMES = builders.NAMES

-- The blueprint's entities, numbered, from the builders' entities.
local function numbered(list)
  for index, entity in ipairs(list) do
    entity.entity_number = index
  end
  return list
end

local function pole_at(x, y)
  return {name = NAMES.pole, position = grid.position(x, y)}
end

-- A 2x2 furnace whose top-left tile is (x, y).
local function furnace_at(x, y)
  return builders.furnace(x, y)
end

-- What `lights.add` is told of the game: a small pole powers 2.5 tiles each way, a furnace covers 2 x 2 tiles.
local function options()
  return {
    lamp = NAMES.lamp, pole = NAMES.pole, supply_distance = 2.5, belts = {NAMES.belt},
    size_of = function(entity) return entity.name == NAMES.machine and 2 or 1, entity.name == NAMES.machine and 2 or 1 end,
  }
end

-- The lamps `lights.add` puts on `list`, as tiles.
local function lamps_after(list)
  local entities = numbered(list)
  lights.add(entities, options())
  local lamps = {}
  for _, entity in ipairs(entities) do
    if entity.name == NAMES.lamp then
      lamps[#lamps + 1] = grid.top_left_tile(entity.position)
    end
  end
  return lamps
end

-- The poles one under the other, five rows apart, in column 0, from row 0 down.
local function column_of_poles(count)
  local list = {}
  for index = 0, count - 1 do
    list[#list + 1] = pole_at(0, index * 5)
  end
  return list
end

-- The shortest distance between two of the lamps, or infinity when there are fewer than two.
local function closest_pair(lamps)
  local closest = math.huge
  for i = 1, #lamps - 1 do
    for j = i + 1, #lamps do
      closest = math.min(closest, math.sqrt((lamps[i].x - lamps[j].x) ^ 2 + (lamps[i].y - lamps[j].y) ^ 2))
    end
  end
  return closest
end

-- How many of the tiles a pole powers have no lamp within 10 tiles.
local function uncovered_tiles(poles, lamps)
  local uncovered = 0
  for _, pole in ipairs(poles) do
    local centre = grid.top_left_tile(pole.position)
    for dx = -2, 2 do
      for dy = -2, 2 do
        local covered = false
        for _, lamp in ipairs(lamps) do
          covered = covered or (lamp.x - centre.x - dx) ^ 2 + (lamp.y - centre.y - dy) ^ 2 <= 100
        end
        uncovered = uncovered + (covered and 0 or 1)
      end
    end
  end
  return uncovered
end

-- How many of the lamps stand outside the supply area of every pole.
local function unpowered_lamps(poles, lamps)
  local unpowered = 0
  for _, lamp in ipairs(lamps) do
    local powered = false
    for _, pole in ipairs(poles) do
      local centre = grid.top_left_tile(pole.position)
      powered = powered or (math.abs(lamp.x - centre.x) <= 2 and math.abs(lamp.y - centre.y) <= 2)
    end
    unpowered = unpowered + (powered and 0 or 1)
  end
  return unpowered
end

describe("lights", function()
  describe("where the lamps stand", function()
    it("puts no lamp on a blueprint without poles", function()
      assert.are.same({}, lamps_after({builders.belt(0, 0)}))
    end)

    it("puts one lamp on the first tile a lone pole powers, the top left one", function()
      assert.are.same({{x = 3, y = 3}}, lamps_after({pole_at(5, 5)})) -- the pole at (5, 5) powers tiles 3 to 7 across and down
    end)

    it("puts the lamp on the closest free tile when the first tile is taken", function()
      local list = {pole_at(5, 5), furnace_at(3, 3)} -- the furnace covers (3, 3) to (4, 4)

      assert.are.same({{x = 5, y = 3}}, lamps_after(list))
    end)

    it("leaves the tile ahead of a belt that runs south free, so that the belt can go on", function()
      local list = {pole_at(5, 5), builders.belt(3, 2)} -- the belt runs south, on to (3, 3)

      assert.are.same({{x = 4, y = 3}}, lamps_after(list))
    end)

    it("leaves the tile ahead of a belt that runs north free", function()
      local list = {pole_at(5, 5), builders.belt(3, 4, defines.direction.north)} -- on to (3, 3)

      assert.are.same({{x = 4, y = 3}}, lamps_after(list))
    end)

    it("leaves the tile ahead of a belt that runs east free", function()
      local list = {pole_at(5, 5), builders.belt(2, 3, defines.direction.east)} -- on to (3, 3)

      assert.are.same({{x = 4, y = 3}}, lamps_after(list))
    end)

    it("leaves the tile ahead of a belt that runs west free", function()
      local list = {pole_at(5, 5), builders.belt(4, 3, defines.direction.west)} -- on to (3, 3), the belt itself takes (4, 3)

      assert.are.same({{x = 3, y = 4}}, lamps_after(list))
    end)

    it("does not keep the tile ahead of an inserter free, which is no belt", function()
      local inserter = {name = NAMES.inserter, position = grid.position(3, 4), direction = defines.direction.north}

      assert.are.same({{x = 3, y = 3}}, lamps_after({pole_at(5, 5), inserter}))
    end)

    it("takes every tile of a machine, the last row too", function()
      local list = {pole_at(5, 5), furnace_at(3, 2)} -- the furnace covers (3, 2) to (4, 3): the first tile, (3, 3), is taken

      assert.are.same({{x = 3, y = 4}}, lamps_after(list))
    end)

    it("goes further for a free tile when a block of things takes the nearer ones", function()
      local list = {pole_at(5, 5)}
      for x = 3, 6 do
        for y = 3, 6 do
          if x ~= 5 or y ~= 5 then
            list[#list + 1] = {name = "stone-wall", position = grid.position(x, y)}
          end
        end
      end

      assert.are.same({{x = 7, y = 3}}, lamps_after(list)) -- 4 tiles from (3, 3), as far as (3, 7)
    end)

    it("puts no lamp where every tile within reach of the powered one is taken", function()
      local list = {pole_at(5, 5)}
      for x = 3, 7 do
        for y = 3, 7 do
          if x ~= 5 or y ~= 5 then
            list[#list + 1] = {name = "stone-wall", position = grid.position(x, y)} -- anything that takes a tile
          end
        end
      end

      assert.are.same({}, lamps_after(list))
    end)
  end)

  describe("which tiles get a lamp, from the top row down and from the left", function()
    it("starts with the tile of the pole that is highest, whatever the order of the poles", function()
      local list = {pole_at(5, 5), pole_at(30, 2)} -- the second pole powers rows 0 to 4, so its top left tile, (28, 0), comes first

      assert.are.same({{x = 28, y = 0}, {x = 3, y = 3}}, lamps_after(list))
    end)

    it("lights a tile 14 tiles away from the lamp, across", function()
      assert.are.same({{x = 3, y = 3}, {x = 17, y = 3}}, lamps_after({pole_at(5, 5), pole_at(19, 5)}))
    end)

    it("counts a tile exactly 10 tiles from a lamp as covered, and puts the next lamp 11 tiles away", function()
      -- the second pole powers x 13 to 17: (13, 3) is 10 tiles from the lamp at (3, 3), (14, 3) is 11
      assert.are.same({{x = 3, y = 3}, {x = 14, y = 3}}, lamps_after({pole_at(5, 5), pole_at(15, 5)}))
    end)

    it("puts a lamp exactly 10 tiles from another when the closer tiles are taken, and not nearer", function()
      -- lamps at (-2, -2); the uncovered tile (-1, 8) is taken. The tile above it, (-1, 7), is 9.06 from the lamp: refused.
      -- (-2, 8) is exactly 10 from it, which is allowed, and is the first of the tiles one away from (-1, 8) that is left
      local wall = {name = "stone-wall", position = grid.position(-1, 8)}

      assert.are.same({{x = -2, y = -2}, {x = -2, y = 8}}, lamps_after({pole_at(0, 0), pole_at(0, 5), pole_at(0, 10), wall}))
    end)
  end)

  describe("the rule that no two lamps are closer than 10 tiles", function()
    it("holds for a long column of poles, the lamps being 10 apart at least", function()
      local lamps = lamps_after(column_of_poles(14))

      assert.is_true(#lamps > 1 and closest_pair(lamps) >= 10)
    end)

    it("holds for two columns of poles side by side", function()
      local list = column_of_poles(14)
      for index = 0, 13 do
        list[#list + 1] = pole_at(4, index * 5)
      end

      local lamps = lamps_after(list)

      assert.is_true(#lamps > 2 and closest_pair(lamps) >= 10)
    end)
  end)

  describe("the rule that every tile a pole powers has a lamp within 10 tiles", function()
    it("holds for a long column of poles, where there is room for the lamps", function()
      local poles = column_of_poles(14)

      assert.are.equal(0, uncovered_tiles(poles, lamps_after(column_of_poles(14))))
    end)

    it("holds for two columns of poles side by side", function()
      local poles = column_of_poles(14)
      for index = 0, 13 do
        poles[#poles + 1] = pole_at(4, index * 5)
      end

      assert.are.equal(0, uncovered_tiles(poles, lamps_after(poles)))
    end)
  end)

  describe("the lamps themselves", function()
    it("are all powered, each inside the supply area of a pole", function()
      local poles = column_of_poles(14)

      assert.are.equal(0, unpowered_lamps(poles, lamps_after(column_of_poles(14))))
    end)

    it("are numbered after the entities there are, one number each", function()
      local entities = numbered(column_of_poles(3))

      lights.add(entities, options())

      local numbers = {}
      for _, entity in ipairs(entities) do
        numbers[#numbers + 1] = entity.entity_number
      end
      assert.are.same({1, 2, 3, 4, 5}, numbers) -- the three poles, 5 rows apart, and two lamps: 12 rows are more than one lamp covers
    end)

    it("stand where they stood when the same blueprint is lit again", function()
      assert.are.same(lamps_after(column_of_poles(8)), lamps_after(column_of_poles(8)))
    end)
  end)
end)
