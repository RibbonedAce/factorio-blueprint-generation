-- spec/labels_spec.lua
-- Where the display panels of the belts that come in stand, and what they show (see scripts/labels.lua). Positions are
-- TILES, read off the pictures: the top-left tile an entity covers, with y growing down (see scripts/grid.lua).
---@diagnostic disable: undefined-field  -- luassert's `assert` has fields (`assert.are`, `assert.is_nil`, ...) the editor cannot see

local builders = require("spec.support.builders")
local grid = require("scripts.grid")
local labels = require("scripts.labels")

local NAMES = builders.NAMES

-- What `labels.add` is told of the game: everything covers one tile but a pump, which covers two, facing east.
local function options()
  return {
    panel = NAMES.panel, belts = {NAMES.belt}, inlets = {NAMES.pump},
    size_of = function(entity) return entity.name == NAMES.pump and 2 or 1, 1 end,
  }
end

-- A belt at the tile (x, y), running east like the belts that come in unless told another way.
local function belt_at(x, y, way)
  return {name = NAMES.belt, position = grid.position(x, y), direction = way or defines.direction.east}
end

-- A pole at the tile (x, y), which only has to be something that stands there.
local function pole_at(x, y)
  return {name = NAMES.pole, position = grid.position(x, y)}
end

-- The entry of a belt at the west edge, in `row`, carrying `item`.
local function entry(row, item)
  return {x = 0, y = row, item = item}
end

-- The entities of the blueprint, numbered.
local function numbered(list)
  for index, entity in ipairs(list) do
    entity.entity_number = index
  end
  return list
end

-- The panels `labels.add` puts on `list` for `supplies`, as {tile column, tile row, item}.
local function panels_after(list, supplies)
  local entities = numbered(list)
  labels.add(entities, supplies, options())
  local panels = {}
  for _, entity in ipairs(entities) do
    if entity.name == NAMES.panel then
      local tile = grid.top_left_tile(entity.position)
      panels[#panels + 1] = {tile.x, tile.y, entity.icon.name}
    end
  end
  return panels
end

describe("labels", function()
  it("puts the panel of an entry on the tile above it", function()
    assert.are.same({{0, -1, "iron-ore"}}, panels_after({belt_at(0, 0)}, {entry(0, "iron-ore")}))
  end)

  it("puts the panel under the entry when the tile above it holds something", function()
    assert.are.same({{0, 1, "coal"}}, panels_after({belt_at(0, 0), pole_at(0, -1)}, {entry(0, "coal")}))
  end)

  it("puts the panel above and west of the entry when the tiles above and under it hold something", function()
    assert.are.same({{-1, -1, "coal"}}, panels_after({belt_at(0, 0), pole_at(0, -1), pole_at(0, 1)}, {entry(0, "coal")}))
  end)

  it("puts the panel under and west of the entry when the three tiles before that hold something", function()
    local list = {belt_at(0, 0), pole_at(0, -1), pole_at(0, 1), pole_at(-1, -1)}

    assert.are.same({{-1, 1, "coal"}}, panels_after(list, {entry(0, "coal")}))
  end)

  it("puts no panel on an entry with no free tile among the four", function()
    local list = {belt_at(0, 0), pole_at(0, -1), pole_at(0, 1), pole_at(-1, -1), pole_at(-1, 1)}

    assert.are.same({}, panels_after(list, {entry(0, "coal")}))
  end)

  it("keeps off a tile that a belt runs on to", function()
    assert.are.same({{0, 1, "coal"}}, panels_after({belt_at(0, 0), belt_at(0, -2, defines.direction.south)}, {entry(0, "coal")}))
  end)

  it("keeps off the tile behind a pump, where the water comes in", function()
    local pump = {name = NAMES.pump, position = grid.position(1, -1, 2, 1), direction = defines.direction.east}

    assert.are.same({{0, 1, "coal"}}, panels_after({belt_at(0, 0), pump}, {entry(0, "coal")}))
  end)

  it("keeps off the tiles right above and under the row of another entry, so that a panel is not between two belts", function()
    local list = {belt_at(0, 0), belt_at(0, 2)}

    assert.are.same({{0, -1, "coal"}, {0, 3, "stone"}}, panels_after(list, {entry(0, "coal"), entry(2, "stone")}))
  end)

  it("puts no panel on an entry whose every free tile is next to another entry", function()
    local list = {belt_at(0, 0), belt_at(0, 1), belt_at(0, 2)}
    local supplies = {entry(0, "coal"), entry(1, "stone"), entry(2, "iron-ore")}

    assert.are.same({{0, -1, "coal"}, {0, 3, "iron-ore"}}, panels_after(list, supplies))
  end)

  it("takes a tile that another panel has not taken", function()
    local list = {belt_at(0, 0), belt_at(0, 4)}

    assert.are.same({{0, -1, "coal"}, {0, 3, "stone"}}, panels_after(list, {entry(0, "coal"), entry(4, "stone")}))
  end)

  it("shows the item as an icon, always, numbered after the entities there are", function()
    local entities = numbered({belt_at(0, 0)})

    labels.add(entities, {entry(0, "copper-ore")}, options())

    assert.are.same({name = NAMES.panel, entity_number = 2, icon = {type = "item", name = "copper-ore"}, always_show = true},
      {name = entities[2].name, entity_number = entities[2].entity_number, icon = entities[2].icon, always_show = entities[2].always_show})
  end)

  it("puts no panel on a blueprint with no entries", function()
    assert.are.same({}, panels_after({belt_at(0, 0)}, {}))
  end)
end)
