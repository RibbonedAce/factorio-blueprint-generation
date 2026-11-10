-- scripts/feeds.lua
-- Which belts bring raw items to which chains, for the input design that brings in one belt of
-- each material (see .agents/inputs-plan.md). Pure, like scripts/layout.lua: it works with names
-- and numbers and knows nothing of tiles.
--
-- A chain fed raw items, and the column of a raw item that goes with made ones, is a LEAF. What
-- a leaf takes rides one belt that ends in it: a furnace takes its ore on one lane and its fuel
-- on the other, a machine that eats one raw item takes it on both lanes. The leaves that take the
-- same things are put, from the west, on TRUNKS: belts along the top of the blueprint, each as full
-- as a lane (or two lanes, for one item) allows. A trunk with two items is made inside the blueprint
-- from two PURE belts, one item on both lanes, which are what the player brings in; the pure
-- belts that feed several trunks are BUSES, the ones that feed one are direct.
--
-- The trunk whose last leaf is furthest east is on top, so that the belt that comes down to a leaf
-- only has to cross the trunks below that reach further east.

local feeds = {}

-- Amounts are sums of fractions, so a lane that is exactly full can add up to a hair more than it carries; that is not over.
local ROUNDING = 1e-9

-- The names of the items of a feed, and one name for the kind of feed they make.
---@param feed bpgen.Feed
---@return string key
---@return string[] names
local function kind_of(feed)
  local names = {}
  for _, item in ipairs(feed.items) do
    names[#names + 1] = item.name
  end
  return table.concat(names, "|"), names
end

-- Whether `leaf` still fits on `trunk`: a trunk with two items carries a lane of each, a trunk with
-- one item two lanes of it. (The leaves of a trunk take the same items, so the trunk has an amount for each.)
---@param trunk bpgen.Trunk  with at least one leaf
---@param leaf bpgen.FeedLeaf
---@param lane number  what one lane carries a minute
---@return boolean
local function fits(trunk, leaf, lane)
  local limit = trunk.mixed and lane or 2 * lane
  for _, item in ipairs(leaf.feed.items) do
    if trunk.demand[item.name] + item.amount > limit + ROUNDING then
      return false
    end
  end
  return true
end

---@param trunk bpgen.Trunk
---@param leaf bpgen.FeedLeaf
local function add_leaf(trunk, leaf)
  trunk.leaves[#trunk.leaves + 1] = leaf
  for _, item in ipairs(leaf.feed.items) do
    trunk.demand[item.name] = (trunk.demand[item.name] or 0) + item.amount
  end
  trunk.first = math.min(trunk.first or leaf.index, leaf.index)
  trunk.last = math.max(trunk.last or leaf.index, leaf.index)
end

-- The leaves grouped by what they take, in the order the kinds first appear, each group from the west.
---@param leaves bpgen.FeedLeaf[]  from the west
---@return {names: string[], leaves: bpgen.FeedLeaf[]}[]
local function group_by_kind(leaves)
  local by_key, groups = {}, {}
  for _, leaf in ipairs(leaves) do
    local key, names = kind_of(leaf.feed)
    if not by_key[key] then
      by_key[key] = {names = names, leaves = {}}
      groups[#groups + 1] = by_key[key]
    end
    table.insert(by_key[key].leaves, leaf)
  end
  return groups
end

-- Fills trunks with the leaves of each kind in turn ("contiguous first fit"): a leaf goes on the
-- trunk before it if it fits, else on a new one.
---@param groups {names: string[], leaves: bpgen.FeedLeaf[]}[]
---@param lane number
---@return bpgen.Trunk[]
local function fill_trunks(groups, lane)
  local trunks = {}
  for _, group in ipairs(groups) do
    local current
    for _, leaf in ipairs(group.leaves) do
      if not current or not fits(current, leaf, lane) then
        current = {items = group.names, mixed = #group.names == 2, leaves = {}, demand = {}}
        trunks[#trunks + 1] = current
      end
      add_leaf(current, leaf)
    end
  end
  return trunks
end

-- The trunks, the one whose last leaf is furthest east first, numbered from the top.
---@param leaves bpgen.FeedLeaf[]  from the west
---@param lane number
---@return bpgen.Trunk[]
local function trunks_of(leaves, lane)
  local trunks = fill_trunks(group_by_kind(leaves), lane)
  table.sort(trunks, function(first, second) return first.last > second.last end)
  for number, trunk in ipairs(trunks) do
    trunk.number = number
  end
  return trunks
end

-- What each item is needed for: a mixed trunk's ore, its fuel, or the whole of a trunk that carries one
-- item, in the order of the trunks, and the items in the order they first appear.
---@param trunks bpgen.Trunk[]
---@return table<string, bpgen.Feeder[]> feeders
---@return string[] order
local function feeders_by_item(trunks)
  local feeders, order = {}, {}
  for _, trunk in ipairs(trunks) do
    for position, name in ipairs(trunk.items) do
      if not feeders[name] then
        feeders[name] = {}
        order[#order + 1] = name
      end
      local role = trunk.mixed and (position == 1 and "a" or "b") or "pure"
      table.insert(feeders[name], {trunk = trunk, role = role, flow = trunk.demand[name]})
    end
  end
  return feeders, order
end

-- The belts of one item that come in: the feeders in turn on a belt, which carries two lanes, until the
-- next would not fit.
---@param item string
---@param feeders bpgen.Feeder[]
---@param lane number
---@return bpgen.PureBelt[]
local function pack_belts(item, feeders, lane)
  local belts, current, load = {}, nil, 0
  for _, feeder in ipairs(feeders) do
    if not current or load + feeder.flow > 2 * lane + ROUNDING then
      current, load = {item = item, feeders = {}}, 0
      belts[#belts + 1] = current
    end
    table.insert(current.feeders, feeder)
    load = load + feeder.flow
  end
  return belts
end

---@param trunks bpgen.Trunk[]
---@param lane number
---@return bpgen.PureBelt[]
local function belts_of(trunks, lane)
  local feeders, order = feeders_by_item(trunks)
  local belts = {}
  for _, item in ipairs(order) do
    for _, belt in ipairs(pack_belts(item, feeders[item], lane)) do
      belts[#belts + 1] = belt
    end
  end
  return belts
end

-- Puts the belts with two feeders or more, the buses, in order: the most feeders first (the fuel, which every
-- trunk with two items needs), then the one that feeds the higher trunk. Numbers them from 0.
---@param belts bpgen.PureBelt[]
---@return bpgen.PureBelt[]
local function buses_of(belts)
  local buses = {}
  for _, belt in ipairs(belts) do
    if #belt.feeders >= 2 then
      buses[#buses + 1] = belt
    end
  end
  table.sort(buses, function(first, second)
    if #first.feeders ~= #second.feeders then
      return #first.feeders > #second.feeders
    end
    local first_trunk, second_trunk = first.feeders[1].trunk.number, second.feeders[1].trunk.number
    if first_trunk ~= second_trunk then
      return first_trunk < second_trunk
    end
    return first.item < second.item
  end)
  for position, bus in ipairs(buses) do
    bus.bus = position - 1
  end
  return buses
end

-- The trunks, the belts that come in and the buses for these leaves.
---@param leaves bpgen.FeedLeaf[]  from the west, each with its `feed`
---@param lane number  what one lane of a belt carries a minute
---@return bpgen.FeedPlan
function feeds.plan(leaves, lane)
  local trunks = trunks_of(leaves, lane)
  local belts = belts_of(trunks, lane)
  return {trunks = trunks, belts = belts, buses = buses_of(belts)}
end

return feeds
