-- spec/feeds_spec.lua
-- Which belts feed which chains, for the input design that brings in one belt of each material (see
-- scripts/feeds.lua). A lane carries 450 items a minute in these specs, as the basic belt's does, and a belt two lanes.
---@diagnostic disable: undefined-field  -- luassert's `assert` has fields (`assert.are`, `assert.is_nil`, ...) the editor cannot see

local feeds = require("scripts.feeds")

local LANE = 450

-- A leaf that takes ore and fuel: `index` is its place among the columns, from the west.
local function furnace_leaf(index, ore, ore_per_minute, coal_per_minute)
  return {index = index, feed = {items = {{name = ore, amount = ore_per_minute}, {name = "coal", amount = coal_per_minute}}}}
end

-- A leaf that takes one item on both lanes.
local function one_item_leaf(index, item, per_minute)
  return {index = index, feed = {items = {{name = item, amount = per_minute}}}}
end

-- The places of the leaves on a trunk.
local function places_of(trunk)
  local places = {}
  for _, leaf in ipairs(trunk.leaves) do
    places[#places + 1] = leaf.index
  end
  return places
end

-- The belts that come in, as "item: feeders".
local function belts_summary(plan)
  local summary = {}
  for _, belt in ipairs(plan.belts) do
    summary[#summary + 1] = belt.item .. ": " .. #belt.feeders
  end
  return summary
end

describe("feeds", function()
  describe("the trunks", function()
    it("puts the leaves that take the same things on one trunk while the ore fits a lane", function()
      local leaves = {furnace_leaf(1, "iron-ore", 100, 8), furnace_leaf(2, "iron-ore", 150, 12), furnace_leaf(3, "iron-ore", 200, 16)}

      local plan = feeds.plan(leaves, LANE)

      assert.are.equal(1, #plan.trunks) -- 100 + 150 + 200 = 450, a whole lane
      assert.are.same({1, 2, 3}, places_of(plan.trunks[1]))
      assert.are.same({["iron-ore"] = 450, coal = 36}, plan.trunks[1].demand)
    end)

    it("starts another trunk when the next leaf would pass a lane of ore", function()
      local leaves = {furnace_leaf(1, "iron-ore", 300, 24), furnace_leaf(2, "iron-ore", 200, 16), furnace_leaf(3, "iron-ore", 100, 8)}

      local plan = feeds.plan(leaves, LANE)

      assert.are.equal(2, #plan.trunks) -- 300 + 200 = 500 is over 450; 200 + 100 fits
      assert.are.same({{2, 3}, {1}}, {places_of(plan.trunks[1]), places_of(plan.trunks[2])}) -- the trunk with the leaf furthest east (place 3) is on top
    end)

    it("keeps the leaves that take different things on trunks of their own", function()
      local leaves = {furnace_leaf(1, "iron-ore", 50, 4), furnace_leaf(2, "copper-ore", 50, 4), furnace_leaf(3, "iron-ore", 50, 4)}

      local plan = feeds.plan(leaves, LANE)

      assert.are.equal(2, #plan.trunks) -- the two iron leaves are neighbours for the trunk, though a copper leaf stands between them
      assert.are.same({1, 3}, places_of(plan.trunks[1]))
      assert.are.same({2}, places_of(plan.trunks[2]))
    end)

    it("does not count the rounding of the sums against a lane that is exactly full", function()
      local leaves = {furnace_leaf(1, "iron-ore", 0.1, 0.05), furnace_leaf(2, "iron-ore", 0.2, 0.05)}

      local plan = feeds.plan(leaves, 0.3) -- 0.1 + 0.2 is 0.30000000000000004 in floating point

      assert.are.equal(1, #plan.trunks)
    end)

    describe("the second belt of a chain built wide", function()
      -- It comes down just west of the chain's own belt (a place half a column before the chain's), with the ore on both lanes.
      -- The trunk of the chain's leaf must stand above it, so that the belt does not have to cross it where the tap splitter of
      -- the chain's leaf is: so every second belt has a trunk of its own, which the trunks, ordered by their last leaf, put below
      -- the trunk of its chain.
      local function second_leaf(chain, ore_per_minute)
        local leaf = one_item_leaf(chain.index - 0.5, "iron-ore", ore_per_minute)
        leaf.second_of = chain
        return leaf
      end

      it("takes a trunk of its own, below the chain's, though another second belt of the same ore would fit on it", function()
        local first, second = furnace_leaf(3, "iron-ore", 300, 24), furnace_leaf(6, "iron-ore", 300, 24)
        local leaves = {second_leaf(first, 100), first, second_leaf(second, 100), second}

        local plan = feeds.plan(leaves, LANE)

        assert.are.same({{6}, {5.5}, {3}, {2.5}}, {places_of(plan.trunks[1]), places_of(plan.trunks[2]), places_of(plan.trunks[3]), places_of(plan.trunks[4])})
      end)

      it("puts the chain's own leaf on a trunk with the other leaves that take the same, as before", function()
        local first, second = furnace_leaf(3, "iron-ore", 100, 8), furnace_leaf(6, "iron-ore", 100, 8)
        local leaves = {second_leaf(first, 100), first, second_leaf(second, 100), second}

        local plan = feeds.plan(leaves, LANE)

        assert.are.same({3, 6}, places_of(plan.trunks[1]))
      end)

      it("lets the pure ore of two second belts ride one belt that comes in, since it is a bus of feeders", function()
        local first, second = furnace_leaf(3, "iron-ore", 300, 24), furnace_leaf(6, "iron-ore", 300, 24)
        local leaves = {second_leaf(first, 100), first, second_leaf(second, 100), second}

        local plan = feeds.plan(leaves, LANE)

        assert.are.same({"iron-ore: 4", "coal: 2"}, belts_summary(plan)) -- the ore of the two chains and of the two second belts: 300 + 300 + 100 + 100 = 800, a belt of 900
      end)
    end)

    it("lets a trunk with one item carry two lanes of it", function()
      local leaves = {one_item_leaf(1, "wood", 400), one_item_leaf(2, "wood", 500)}

      local plan = feeds.plan(leaves, LANE)

      assert.are.equal(1, #plan.trunks) -- 400 + 500 = 900, both lanes
    end)

    it("starts another trunk when a trunk with one item would pass its two lanes", function()
      local leaves = {one_item_leaf(1, "wood", 500), one_item_leaf(2, "wood", 500)}

      local plan = feeds.plan(leaves, LANE)

      assert.are.equal(2, #plan.trunks) -- 500 + 500 = 1000 is over 900
    end)

    it("puts the trunk whose last leaf is furthest east on top and numbers the trunks from there", function()
      local leaves = {furnace_leaf(1, "copper-ore", 50, 4), furnace_leaf(2, "iron-ore", 50, 4), furnace_leaf(3, "copper-ore", 50, 4)}

      local plan = feeds.plan(leaves, LANE)

      assert.are.same({1, 3}, places_of(plan.trunks[1])) -- the copper leaves, the last of which is in place 3
      assert.are.same({1, 2}, {plan.trunks[1].number, plan.trunks[2].number})
      assert.are.same({3, 2}, {plan.trunks[1].last, plan.trunks[2].last})
    end)

    it("knows the place of the first and the last leaf of a trunk", function()
      local leaves = {furnace_leaf(2, "iron-ore", 50, 4), furnace_leaf(5, "iron-ore", 50, 4)}

      local plan = feeds.plan(leaves, LANE)

      assert.are.same({2, 5}, {plan.trunks[1].first, plan.trunks[1].last})
    end)

    it("puts a leaf whose place is a fraction, the fuel of a stage in the middle of a chain, between its neighbours", function()
      local leaves = {furnace_leaf(1, "iron-ore", 50, 4), one_item_leaf(1.5, "coal", 10), furnace_leaf(2, "copper-ore", 50, 4)}

      local plan = feeds.plan(leaves, LANE)

      assert.are.same({2, 1.5, 1}, {plan.trunks[1].last, plan.trunks[2].last, plan.trunks[3].last}) -- the trunks, furthest east first
      assert.are.same({true, false, true}, {plan.trunks[1].mixed, plan.trunks[2].mixed, plan.trunks[3].mixed}) -- only the coal alone is not mixed
    end)

    it("tells a trunk with two items from one with a single item", function()
      local leaves = {furnace_leaf(1, "iron-ore", 50, 4), one_item_leaf(2, "wood", 50)}

      local plan = feeds.plan(leaves, LANE)

      assert.are.same({false, true}, {plan.trunks[1].mixed, plan.trunks[2].mixed}) -- the wood leaf is further east
    end)
  end)

  describe("the belts that come in", function()
    it("brings in one belt for each item, the fuel included", function()
      local leaves = {furnace_leaf(1, "iron-ore", 100, 8), furnace_leaf(2, "copper-ore", 100, 8)}

      local plan = feeds.plan(leaves, LANE)

      assert.are.same({"copper-ore: 1", "coal: 2", "iron-ore: 1"}, belts_summary(plan)) -- the copper trunk is on top: its leaf is further east
    end)

    it("needs a second belt of an item when its feeders pass the two lanes of one", function()
      local leaves = {furnace_leaf(1, "iron-ore", 450, 36), furnace_leaf(2, "iron-ore", 450, 36), furnace_leaf(3, "iron-ore", 450, 36)}

      local plan = feeds.plan(leaves, LANE)

      assert.are.same({"iron-ore: 2", "iron-ore: 1", "coal: 3"}, belts_summary(plan)) -- three trunks of 450: 900 on the first belt, 450 on the second
    end)

    it("does not count the rounding of the sums against a belt that is exactly full", function()
      local leaves = {furnace_leaf(1, "iron-ore", 0.1, 0.05), furnace_leaf(2, "iron-ore", 0.2, 0.05), furnace_leaf(3, "iron-ore", 0.3, 0.05)}

      local plan = feeds.plan(leaves, 0.3) -- two trunks of iron ore: 0.1 + 0.2 = 0.30000000000000004 and 0.3, 0.6000000000000001 together

      assert.are.same({"iron-ore: 2", "coal: 2"}, belts_summary(plan)) -- one belt of iron ore carries the two lanes of 0.6
    end)

    it("gives a feeder the role of the ore, of the fuel or of the whole trunk, and the amount it needs", function()
      local leaves = {furnace_leaf(1, "iron-ore", 100, 8), one_item_leaf(2, "wood", 30)}

      local plan = feeds.plan(leaves, LANE)

      local roles = {}
      for _, belt in ipairs(plan.belts) do
        roles[#roles + 1] = belt.item .. " " .. belt.feeders[1].role .. " " .. belt.feeders[1].flow
      end
      assert.are.same({"wood pure 30", "iron-ore a 100", "coal b 8"}, roles)
    end)
  end)

  describe("the buses", function()
    it("makes a bus of a belt that feeds two trunks or more and leaves a belt with one feeder direct", function()
      local leaves = {furnace_leaf(1, "iron-ore", 100, 8), furnace_leaf(2, "copper-ore", 100, 8)}

      local plan = feeds.plan(leaves, LANE)

      assert.are.equal(1, #plan.buses) -- the coal feeds both trunks
      assert.are.equal("coal", plan.buses[1].item)
      assert.are.equal(0, plan.buses[1].bus)
    end)

    it("makes no bus when every belt feeds one trunk", function()
      local leaves = {furnace_leaf(1, "iron-ore", 100, 8)}

      local plan = feeds.plan(leaves, LANE)

      assert.are.same({}, plan.buses)
    end)

    it("puts the bus with the most feeders first", function()
      local leaves = {
        furnace_leaf(1, "iron-ore", 450, 36), furnace_leaf(2, "iron-ore", 450, 36),
        furnace_leaf(3, "copper-ore", 100, 8),
      }

      local plan = feeds.plan(leaves, LANE)

      assert.are.same({"coal", "iron-ore"}, {plan.buses[1].item, plan.buses[2].item}) -- the coal feeds three trunks, the iron two
      assert.are.same({0, 1}, {plan.buses[1].bus, plan.buses[2].bus})
    end)

    it("puts first the bus that feeds the trunk on top when two have as many feeders, whatever their names", function()
      local leaves = {
        furnace_leaf(1, "iron-ore", 450, 36), furnace_leaf(2, "copper-ore", 450, 36),
        furnace_leaf(3, "copper-ore", 450, 36), furnace_leaf(4, "iron-ore", 450, 36),
      }

      local plan = feeds.plan(leaves, LANE)

      -- the trunk on top is the iron one (its leaf is furthest east), though copper-ore comes first in the alphabet
      assert.are.same({"coal", "iron-ore", "copper-ore"}, {plan.buses[1].item, plan.buses[2].item, plan.buses[3].item})
    end)

    it("puts the bus with the most feeders before one that feeds the trunk on top", function()
      local leaves = {
        furnace_leaf(1, "copper-ore", 300, 24), furnace_leaf(2, "iron-ore", 300, 24), furnace_leaf(3, "iron-ore", 300, 24),
        furnace_leaf(4, "iron-ore", 300, 24), furnace_leaf(5, "copper-ore", 300, 24),
      }

      local plan = feeds.plan(leaves, LANE)

      -- copper feeds trunks 1 and 5, iron trunks 2 to 4: iron has more feeders
      assert.are.same({"coal", "iron-ore", "copper-ore"}, {plan.buses[1].item, plan.buses[2].item, plan.buses[3].item})
    end)

    it("puts the buses in the order of their names when they have as many feeders and start at the same trunk", function()
      local leaves = {furnace_leaf(1, "iron-ore", 450, 36), furnace_leaf(2, "iron-ore", 450, 36)}

      local plan = feeds.plan(leaves, LANE)

      assert.are.same({"coal", "iron-ore"}, {plan.buses[1].item, plan.buses[2].item}) -- iron-ore is the first belt, coal sorts before it
    end)
  end)
end)
