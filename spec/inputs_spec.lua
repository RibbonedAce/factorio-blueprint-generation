-- spec/inputs_spec.lua
-- The top band of a blueprint that takes one belt of each material (see the top of scripts/inputs.lua). The band
-- is laid out for leaves whose belts come down in tile columns the spec chooses, and drawn with
-- spec/support/picture.lua; the diagrams in the comments are the expected pictures. x grows to the east, y down.
---@diagnostic disable: undefined-field  -- luassert's `assert` has fields (`assert.are`, `assert.is_nil`, ...) the editor cannot see

local builders = require("spec.support.builders")
local feeds = require("scripts.feeds")
local grid = require("scripts.grid")
local inputs = require("scripts.inputs")
local picture = require("spec.support.picture")

local NAMES = builders.NAMES
local LANE = 450
local REACH = 5
local north, east, south, west = defines.direction.north, defines.direction.east, defines.direction.south, defines.direction.west

-- A leaf that takes ore and fuel, its belt coming down in tile column `drop_x`; `index` is its place among the columns.
local function furnace_leaf(index, drop_x, ore, ore_per_minute)
  return {index = index, drop_x = drop_x, feed = {items = {{name = ore, amount = ore_per_minute or 100}, {name = "coal", amount = 8}}}}
end

-- A leaf that takes one item on both lanes.
local function one_item_leaf(index, drop_x, item)
  return {index = index, drop_x = drop_x, feed = {items = {{name = item, amount = 100}}}}
end

-- The band for these leaves: the plan, the entities, the belts that come in and the last row of each leaf's belt.
local function lay(leaves, reach)
  local plan = feeds.plan(leaves, LANE)
  local entities, supplies, ends = inputs.lay(plan, NAMES, reach or REACH)
  return {plan = plan, entities = entities, supplies = supplies, ends = ends}
end

local function draw(band, last_column, last_row)
  return picture.draw(band.entities, {}, 0, 0, last_column, last_row)
end

-- The splitters as "x,y direction", with the top-left tile of each.
local function splitters_of(entities)
  local found = {}
  for _, entity in ipairs(entities) do
    if entity.name == NAMES.splitter then
      local width = (entity.direction == south) and 2 or 1
      local height = (entity.direction == south) and 1 or 2
      found[#found + 1] = (entity.position.x - width / 2) .. "," .. (entity.position.y - height / 2) .. " " .. entity.direction
    end
  end
  return found
end

describe("inputs", function()
  describe("a single chain fed ore and fuel, with no bus", function()
    -- The ore comes in at the west edge in row 0 and the coal in row 2. The trunk is row 1; its first tile, the mixer
    -- (column 1), faces east with nothing behind it, the ore turns south into its north side and the coal north into
    -- its south side, so each side-loads one lane. The trunk turns south in column 4, where the first column starts.
    --
    --      01234
    --   0 |>v...
    --   1 |.>>>v
    --   2 |>^..v
    local leaf = furnace_leaf(1, 4, "iron-ore")
    local band = lay({leaf})

    it("brings the ore and the fuel into a mixer that puts one on each lane of the trunk, which turns south at the leaf", function()
      assert.are.same({">v...", ".>>>v", ">^..v"}, draw(band, 4, 2))
    end)

    it("brings in each material from the west edge, in the row of its feeder, from the top down", function()
      assert.are.same({{x = 0, y = 0, item = "iron-ore"}, {x = 0, y = 2, item = "coal"}}, band.supplies)
    end)

    it("ends the belt of the leaf in the row under the trunk", function()
      assert.are.equal(2, band.ends[leaf])
    end)

    it("starts the first column in column 4", function()
      assert.are.equal(4, inputs.start_column(band.plan))
    end)
  end)

  describe("a trunk with two leaves", function()
    -- A splitter facing east in front of the first leaf (column 3, rows 1 and 2) sends the trunk on from its top half
    -- and the leaf's belt south from its bottom half; the trunk turns south at the last leaf.
    --
    --      01234567890
    --   0 |>v.........
    --   1 |.>>S>>>>>>v
    --   2 |>^.Sv.....v
    local first, second = furnace_leaf(1, 4, "iron-ore"), furnace_leaf(2, 10, "iron-ore")
    local band = lay({first, second})

    it("taps the trunk with a splitter in front of every leaf but the last", function()
      assert.are.same({">v.........", ".>>S>>>>>>v", ">^.Sv.....v"}, draw(band, 10, 2))
    end)

    it("faces the splitter the way the trunk runs", function()
      assert.are.same({"3,1 " .. east}, splitters_of(band.entities))
    end)

    it("ends the belt of every leaf in the row under the trunk", function()
      assert.are.same({2, 2}, {band.ends[first], band.ends[second]})
    end)
  end)

  describe("a bus that feeds two trunks", function()
    -- The coal feeds both trunks, so it is a bus: it comes in at row 0 and runs down column 2, with a splitter above
    -- the first feeder (row 3) that sends the coal out east in row 4, and ends turning east in row 7. The ore
    -- feeders in rows 2 and 5 go under the bus (the entrance in column 1, the exit in column 4) and turn
    -- into the mixers in column 5. The copper trunk (row 3), the one whose leaf is furthest east, is on top.
    --
    --      012345678901234
    --   0 |>>v............
    --   1 |..v............
    --   2 |>(v.)v.........
    --   3 |..SS.>>>>>>>>>v
    --   4 |..v>>^........v
    --   5 |>(v.)v.........
    --   6 |..v..>>>v......
    --   7 |..>>>^..v......
    local iron, copper = furnace_leaf(1, 8, "iron-ore"), furnace_leaf(2, 14, "copper-ore")
    local band = lay({iron, copper})

    it("runs the bus down its column, splits it above the first feeder and ends it in the row of the last", function()
      assert.are.same({
        ">>v............",
        "..v............",
        ">(v.)v.........",
        "..SS.>>>>>>>>>v",
        "..v>>^........v",
        ">(v.)v.........",
        "..v..>>>v......",
        "..>>>^..v......",
      }, draw(band, 14, 7))
    end)

    it("faces the splitter of the bus south, the way the bus runs", function()
      assert.are.same({"2,3 " .. south}, splitters_of(band.entities))
    end)

    it("brings in the coal, the copper ore and the iron ore from the top down, each in the row of its feeder", function()
      assert.are.same({
        {x = 0, y = 0, item = "coal"},
        {x = 0, y = 2, item = "copper-ore"},
        {x = 0, y = 5, item = "iron-ore"},
      }, band.supplies)
    end)

    it("gives the trunks the rows 3 apart, the first N + 2 from the top for N buses", function()
      assert.are.same({3, 6}, {band.plan.trunks[1].row, band.plan.trunks[2].row})
    end)

    it("starts the first column 4 columns further east for each bus", function()
      assert.are.equal(8, inputs.start_column(band.plan))
    end)

    it("starts a column that no trunk passes over in the top row", function()
      assert.are.equal(0, inputs.first_row_under(band.plan, 20))
    end)

    it("starts a column in the top row when the trunk ends exactly in its own column", function()
      assert.are.equal(0, inputs.first_row_under(band.plan, 14)) -- the copper trunk turns south in column 14
    end)

    it("starts a column under the lowest trunk that reaches further east, with a free row between", function()
      assert.are.equal(5, inputs.first_row_under(band.plan, 10)) -- only the copper trunk (row 3) reaches east of column 10
    end)

    it("starts a column under the lowest of the trunks that pass over it when more than one does", function()
      assert.are.equal(8, inputs.first_row_under(band.plan, 4)) -- both do; the iron trunk is in row 6
    end)
  end)

  describe("a leaf whose belt comes down past a trunk below it that reaches further east", function()
    -- Two trunks that carry one item each, so no mixer and no bus. The wood trunk (row 1, the one whose last leaf is
    -- furthest east) has a leaf in column 4, in front of the stone trunk (row 4), which runs on to column 8. The
    -- belt of that leaf goes under the stone trunk: it enters in row 3 and comes out in row 5.
    --
    --      0123456789012
    --   0 |.............
    --   1 |>>>S>>>>>>>>v
    --   2 |...Sv.......v
    --   3 |....n........
    --   4 |>>>>>>>>v....
    --   5 |....u...v....
    local near, stone, far = one_item_leaf(1, 4, "wood"), one_item_leaf(2, 8, "stone"), one_item_leaf(3, 12, "wood")
    local band = lay({near, stone, far})

    it("takes the belt of the leaf under the trunk, in the row before it and out the row after it", function()
      assert.are.same({
        ".............",
        ">>>S>>>>>>>>v",
        "...Sv.......v",
        "....n........",
        ">>>>>>>>v....",
        "....u...v....",
      }, draw(band, 12, 5))
    end)

    it("ends the belt of the leaf in the row of the exit", function()
      assert.are.equal(5, band.ends[near])
    end)

    it("keeps the belt of a leaf further east than the trunk below on the surface", function()
      assert.are.equal(2, band.ends[far])
    end)

    it("feeds a trunk with one item straight from its belt, which comes in at the west edge in the row of the trunk", function()
      assert.are.same({{x = 0, y = 1, item = "wood"}, {x = 0, y = 4, item = "stone"}}, band.supplies)
    end)
  end)

  describe("a leaf whose belt passes two trunks", function()
    -- The top trunk (wood) has leaves in columns 4 and 16; the trunks of the iron plates (row 4) and the stone (row 7)
    -- reach columns 12 and 8. The belt of the leaf in column 4 goes under both: an exit in row 5 and the next entrance
    -- in row 6 stand side by side.
    local first = one_item_leaf(1, 4, "wood")
    local band = lay({first, one_item_leaf(2, 8, "stone"), one_item_leaf(3, 12, "iron-plate"), one_item_leaf(4, 16, "wood")})

    it("goes under each of them in turn", function()
      assert.are.same({">", "v", "n", ">", "u", "n", ">", "u"}, picture.draw(band.entities, {}, 4, 1, 4, 8))
    end)

    it("ends the belt in the row of the last exit", function()
      assert.are.equal(8, band.ends[first])
    end)
  end)

  describe("two buses", function()
    -- Three trunks of iron ore (450 a minute each), so the iron needs two feeders on one belt and one on another, and the
    -- coal three: two buses, the coal (most feeders) furthest east. Buses are 4 columns apart, the first column starts in 12.
    local band = lay({furnace_leaf(1, 12, "iron-ore", 450), furnace_leaf(2, 16, "iron-ore", 450), furnace_leaf(3, 20, "iron-ore", 450)})

    it("puts the bus with the most feeders furthest east, and the next 4 columns west of it", function()
      assert.are.same({"coal", "iron-ore"}, {band.plan.buses[1].item, band.plan.buses[2].item})
      assert.are.same({6, 2}, {band.plan.buses[1].column, band.plan.buses[2].column})
    end)
  end)

  describe("every band", function()
    local function wood_trunks()
      return {one_item_leaf(1, 4, "wood"), one_item_leaf(2, 8, "stone"), one_item_leaf(3, 12, "iron-plate"), one_item_leaf(4, 16, "wood")}
    end
    local scenarios = {
      single = function() return {furnace_leaf(1, 4, "iron-ore")} end,
      tapped = function() return {furnace_leaf(1, 4, "iron-ore"), furnace_leaf(2, 10, "iron-ore")} end,
      bus = function() return {furnace_leaf(1, 8, "iron-ore"), furnace_leaf(2, 14, "copper-ore")} end,
      hops = wood_trunks,
    }

    for name, leaves in pairs(scenarios) do
      it("covers no tile twice and none above or west of the blueprint: " .. name, function()
        local covered, crowded, least_x, least_y = {}, {}, math.huge, math.huge
        for _, entity in ipairs(lay(leaves()).entities) do
          local width, height = inputs.footprint(entity, NAMES, {})
          local tile = grid.top_left_tile(entity.position, width, height)
          for dx = 0, width - 1 do
            for dy = 0, height - 1 do
              local key = (tile.x + dx) .. "," .. (tile.y + dy)
              if covered[key] then crowded[#crowded + 1] = key end
              covered[key] = true
            end
          end
          least_x, least_y = math.min(least_x, tile.x), math.min(least_y, tile.y)
        end

        assert.are.same({{}, true, true}, {crowded, least_x >= 0, least_y >= 0})
      end)
    end
  end)

  describe("the tiles an entity covers", function()
    local machine_sizes = {["stone-furnace"] = 2, ["assembling-machine-1"] = 3}

    local function footprint(entity)
      local width, height = inputs.footprint(entity, NAMES, machine_sizes)
      return {width, height}
    end

    it("is two across and one along for a splitter that faces south", function()
      assert.are.same({2, 1}, footprint(builders.splitter(0, 0, south)))
    end)

    it("is two across and one along for a splitter that faces north", function()
      assert.are.same({2, 1}, footprint(builders.splitter(0, 0, north)))
    end)

    it("is one across and two along for a splitter that faces east", function()
      assert.are.same({1, 2}, footprint(builders.splitter(0, 0, east)))
    end)

    it("is one across and two along for a splitter that faces west", function()
      assert.are.same({1, 2}, footprint(builders.splitter(0, 0, west)))
    end)

    it("is the size the machine's name says, on both sides", function()
      assert.are.same({3, 3}, footprint({name = "assembling-machine-1"}))
    end)

    it("is one tile for a belt, an inserter or a pole", function()
      assert.are.same({1, 1}, footprint(builders.belt(0, 0)))
    end)
  end)

  describe("the underground belt", function()
    it("is refused when it spans fewer tiles than the hops under the belts need", function()
      local leaves = {furnace_leaf(1, 8, "iron-ore"), furnace_leaf(2, 14, "copper-ore")}

      assert.has_error(function() lay(leaves, 2) end)
    end)

    it("is enough when it spans exactly as many tiles as the hops need", function()
      local leaves = {furnace_leaf(1, 8, "iron-ore"), furnace_leaf(2, 14, "copper-ore")}

      assert.has_no.errors(function() lay(leaves, 3) end)
    end)
  end)
end)
