-- spec/shared_band_spec.lua
-- The band that brings in the belts of raw items of a blueprint made of several blocks (see the head of scripts/shared_band.lua). The blocks here are
-- columns of belts that run south, the tiles of their own belts of raw items, and are drawn with spec/support/picture.lua; the diagrams in the
-- comments are the expected pictures. x grows to the east, y down.
---@diagnostic disable: undefined-field  -- luassert's `assert` has fields (`assert.are`, `assert.is_nil`, ...) the editor cannot see

local builders = require("spec.support.builders")
local grid = require("scripts.grid")
local picture = require("spec.support.picture")
local shared_band = require("scripts.shared_band")

local NAMES = builders.NAMES
local OPTIONS = {lane_items_per_minute = 450, underground_reach = 5}
local south = defines.direction.south

-- The blueprint of one block: a belt of raw items of `rows` tiles that runs south in the column `x`, from the row `first`.
local function belt_block(x, first, rows)
  local entities = {}
  for row = first, first + rows - 1 do
    entities[#entities + 1] = {name = NAMES.belt, position = grid.position(x, row), direction = south, entity_number = #entities + 1}
  end
  return entities
end

-- What a belt of furnaces takes: ore and coal.
local function furnace_feed(ore)
  return {items = {{name = ore, amount = 100}, {name = "coal", amount = 8}}}
end

local function draw(entities, last_column, last_row)
  return picture.draw(entities, {}, 0, 0, last_column, last_row)
end

describe("shared_band", function()
  describe("add", function()
    describe("for a block whose belt starts in the first row", function()
      -- The band of a single belt of ore and coal (see the first picture of spec/inputs_spec.lua), and the block under it, moved 4 columns east, where
      -- the band leaves room, and 3 rows down, under the belt that comes down to it.
      --
      --      01234
      --   0 |>v...
      --   1 |.>>>v
      --   2 |>^..v
      --   3 |....v      the block's own belt, the first tile of which was in row 0
      --   4 |....v
      --   5 |....v
      local function added()
        local entities = belt_block(0, 0, 3)
        local added = shared_band.add(entities, {{key = "iron", x = 0, y = 0, name = NAMES.belt, belt = true, feed = furnace_feed("iron-ore")}}, NAMES, OPTIONS)
        return entities, added
      end

      it("draws the band, and the block under it, moved east and down", function()
        local entities = added()

        assert.are.same({">v...", ".>>>v", ">^..v", "....v", "....v", "....v"}, draw(entities, 4, 5))
      end)

      it("says how far the blocks moved", function()
        local _, result = added()

        assert.are.same({4, 3}, {result.dx, result.dy})
      end)

      it("gives the belts that come in, from the top down", function()
        local _, result = added()

        assert.are.same({{x = 0, y = 0, item = "iron-ore"}, {x = 0, y = 2, item = "coal"}}, result.supplies)
      end)

      it("numbers the entities from 1 with no gap", function()
        local entities = added()

        assert.has_consecutive_numbers(entities)
      end)
    end)

    describe("for a block whose belt starts lower than the first row", function()
      -- The belt of the block starts in the row 2 of the block, so the belt that comes down to it goes on, two tiles, to the first of its own.
      --
      --      01234
      --   2 |>^..v
      --   3 |....v      the belt that goes on, drawn under the band
      --   4 |....v
      --   5 |....v      the block's own belt, from its row 2
      --   6 |....v
      --   7 |....v
      it("takes the belt that comes down on, down to the first tile of the block's belt", function()
        local entities = belt_block(0, 2, 3)

        local result = shared_band.add(entities, {{key = "iron", x = 0, y = 2, name = NAMES.belt, belt = true, feed = furnace_feed("iron-ore")}}, NAMES, OPTIONS)

        assert.are.same({">^..v", "....v", "....v", "....v", "....v", "....v"}, {table.unpack(draw(entities, 4, 7), 3)})
        assert.are.same({4, 3}, {result.dx, result.dy})
      end)
    end)

    describe("for blocks of two materials, which take the coal from one belt", function()
      -- an iron block in the column 0 and a copper block in the column 10: two trunks, so the coal is a bus that feeds both, which takes 4 columns
      local function added()
        local entities = belt_block(0, 0, 3)
        for _, entity in ipairs(belt_block(10, 0, 3)) do
          entities[#entities + 1] = entity
          entity.entity_number = #entities
        end
        local starts = {
          {key = "iron", x = 0, y = 0, name = NAMES.belt, belt = true, feed = furnace_feed("iron-ore")},
          {key = "copper", x = 10, y = 0, name = NAMES.belt, belt = true, feed = furnace_feed("copper-ore")},
        }
        return entities, shared_band.add(entities, starts, NAMES, OPTIONS)
      end

      it("brings in the coal, the copper ore and the iron ore, one belt each: the trunk that reaches furthest east is on top", function()
        local _, result = added()

        local items = {}
        for _, supply in ipairs(result.supplies) do
          items[#items + 1] = supply.item
        end
        assert.are.same({"coal", "copper-ore", "iron-ore"}, items)
      end)

      it("leaves room for the bus: the blocks move 8 columns east", function()
        local _, result = added()

        assert.are.equal(8, result.dx)
      end)

      it("puts the blocks under the lowest trunk: the trunks are in the rows 3 and 6, so the blocks move to the row 8", function()
        local _, result = added()

        assert.are.equal(8, result.dy)
      end)
    end)

    it("gives back the starts that are not belts of raw items, moved with the blocks", function()
      local entities = belt_block(0, 0, 3)
      local starts = {
        {key = "iron", x = 0, y = 0, name = NAMES.belt, belt = true, feed = furnace_feed("iron-ore")}, {key = "crude", x = 6, y = 1, name = NAMES.pipe},
      }

      local result = shared_band.add(entities, starts, NAMES, OPTIONS)

      assert.are.same({{key = "crude", x = 10, y = 4, name = NAMES.pipe}}, result.starts)
    end)

    it("moves the poles and everything else of the blocks as it moves the belts: every entity of the blocks, by the same amount", function()
      local entities = belt_block(0, 0, 3)
      entities[#entities + 1] = {name = NAMES.pole, position = grid.position(2, 1), entity_number = #entities + 1}

      shared_band.add(entities, {{key = "iron", x = 0, y = 0, name = NAMES.belt, belt = true, feed = furnace_feed("iron-ore")}}, NAMES, OPTIONS)

      assert.are.same(grid.position(6, 4), entities[4].position)
    end)

    it("stops when no belt of raw items comes down to the blocks", function()
      local run = function() shared_band.add({}, {{key = "crude", x = 6, y = 1, name = NAMES.pipe}}, NAMES, OPTIONS) end

      assert.has_error(run, "shared_band: no belt of raw items comes down to the blocks")
    end)

    it("stops when the underground belt does not span enough tiles for the band", function()
      local run = function()
        shared_band.add(belt_block(0, 0, 3), {{key = "iron", x = 0, y = 0, name = NAMES.belt, belt = true, feed = furnace_feed("iron-ore")}}, NAMES, {lane_items_per_minute = 450, underground_reach = 2})
      end

      assert.has_error(run, "inputs: the underground belt does not span enough tiles")
    end)
  end)
end)
