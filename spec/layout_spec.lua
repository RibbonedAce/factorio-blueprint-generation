-- spec/layout_spec.lua
-- What the furnace-column layout builds. Positions are TILES read off the diagram
-- at the top of scripts/layout.lua (the top-left tile an entity covers, y growing
-- down; see scripts/grid.lua): x = 0 input belt, 1 input inserters, 2 furnace
-- (covering columns 2 and 3), 4 output inserters, 5 output belt. Every furnace is
-- two tiles tall, so furnace number i (from 0) starts at y = 2i.
---@diagnostic disable: undefined-field  -- luassert's `assert` has fields (`assert.are`, `assert.is_nil`, ...) the editor cannot see

local builders = require("spec.support.builders")
local layout = require("scripts.layout")
local grid = require("scripts.grid")
local validator = require("spec.support.blueprint_validator")

local NAMES = builders.NAMES

-- Helpers that only look things up in the result.

local function entities_named(entities, name)
  local found = {}
  for _, entity in ipairs(entities) do
    if entity.name == name then
      found[#found + 1] = entity
    end
  end
  return found
end

local function count_named(entities, name)
  return #entities_named(entities, name)
end

-- The entity whose top-left tile is (tile_x, tile_y), or nil. `size` is how many
-- tiles wide and tall it is (default 1, a furnace is 2).
local function entity_at(entities, tile_x, tile_y, size)
  for _, entity in ipairs(entities) do
    local tile = grid.top_left_tile(entity.position, size, size)
    if tile.x == tile_x and tile.y == tile_y then
      return entity
    end
  end
end

-- What stands on a tile, as a name; nil if nothing does.
local function name_at(entities, tile_x, tile_y, size)
  local entity = entity_at(entities, tile_x, tile_y, size)
  return entity and entity.name
end

-- Which way the entity on a tile faces; nil if nothing stands there.
local function direction_at(entities, tile_x, tile_y)
  local entity = entity_at(entities, tile_x, tile_y)
  return entity and entity.direction
end

-- The top-left tiles of 1x1 entities, in order.
local function tiles_of(entities)
  local tiles = {}
  for _, entity in ipairs(entities) do
    tiles[#tiles + 1] = grid.top_left_tile(entity.position)
  end
  return tiles
end

local function directions_of(entities)
  local directions = {}
  for _, entity in ipairs(entities) do
    directions[#directions + 1] = entity.direction
  end
  return directions
end

local function count_wires(entities)
  local total = 0
  for _, entity in ipairs(entities) do
    total = total + #(entity.wires or {})
  end
  return total
end

describe("layout", function()
  describe("how many of each thing", function()
    it("gives three furnaces three furnaces", function()
      local shape = {machine_size = 2, input_inserters = 1, output_inserters = 1}
      local entities = layout.build(3, NAMES, shape)

      assert.are.equal(3, count_named(entities, NAMES.machine))
    end)

    it("gives three furnaces eleven belts: six for the output, five for the input that stops at the last inserter", function()
      local shape = {machine_size = 2, input_inserters = 1, output_inserters = 1}
      local entities = layout.build(3, NAMES, shape)

      assert.are.equal(11, count_named(entities, NAMES.belt)) -- 3 furnaces x 2 rows = 6 output; the last inserter is in row 4, so 5 input
    end)

    it("gives three furnaces six inserters, one in and one out each", function()
      local shape = {machine_size = 2, input_inserters = 1, output_inserters = 1}
      local entities = layout.build(3, NAMES, shape)

      assert.are.equal(6, count_named(entities, NAMES.inserter))
    end)

    it("gives one furnace two poles, one on each side", function()
      local shape = {machine_size = 2, input_inserters = 1, output_inserters = 1}
      local entities = layout.build(1, NAMES, shape)

      assert.are.equal(2, count_named(entities, NAMES.pole))
    end)

    it("lets two furnaces share their poles, so they still need only two", function()
      local shape = {machine_size = 2, input_inserters = 1, output_inserters = 1}
      local entities = layout.build(2, NAMES, shape)

      assert.are.equal(2, count_named(entities, NAMES.pole))
    end)

    it("needs a new pair of poles for a third furnace", function()
      local shape = {machine_size = 2, input_inserters = 1, output_inserters = 1}
      local entities = layout.build(3, NAMES, shape)

      assert.are.equal(4, count_named(entities, NAMES.pole))
    end)

    it("needs six poles for five furnaces", function()
      local shape = {machine_size = 2, input_inserters = 1, output_inserters = 1}
      local entities = layout.build(5, NAMES, shape)

      assert.are.equal(6, count_named(entities, NAMES.pole))
    end)

    it("makes exactly 24 entities for three furnaces, with nothing else added", function()
      local shape = {machine_size = 2, input_inserters = 1, output_inserters = 1}
      local entities = layout.build(3, NAMES, shape)

      assert.are.equal(24, #entities) -- 3 furnaces + 11 belts + 6 inserters + 4 poles
    end)

    it("numbers the entities 1 to n in order, one number each", function()
      local shape = {machine_size = 2, input_inserters = 1, output_inserters = 1}
      local entities = layout.build(1, NAMES, shape)

      local numbers = {}
      for _, entity in ipairs(entities) do
        numbers[#numbers + 1] = entity.entity_number
      end
      assert.are.same({1, 2, 3, 4, 5, 6, 7, 8}, numbers) -- 3 belts + furnace + 2 inserters + 2 poles
    end)
  end)

  describe("where things stand", function()
    it("makes the output belt four tiles long for two furnaces and the input belt three, ending at the last input inserter", function()
      local shape = {machine_size = 2, input_inserters = 1, output_inserters = 1}
      local entities = layout.build(2, NAMES, shape)

      local belts = entities_named(entities, NAMES.belt)

      assert.are.same({
        {x = 0, y = 0}, {x = 0, y = 1}, {x = 0, y = 2}, -- the second furnace's input inserter is in row 2
        {x = 5, y = 0}, {x = 5, y = 1}, {x = 5, y = 2}, {x = 5, y = 3},
      }, tiles_of(belts))
    end)

    it("makes the input belt a single tile for one furnace, level with its input inserter", function()
      local shape = {machine_size = 2, input_inserters = 1, output_inserters = 1}
      local entities = layout.build(1, NAMES, shape)

      local belts = entities_named(entities, NAMES.belt)

      assert.are.same({
        {x = 0, y = 0},
        {x = 5, y = 0}, {x = 5, y = 1},
      }, tiles_of(belts))
    end)

    it("makes every belt run south", function()
      local shape = {machine_size = 2, input_inserters = 1, output_inserters = 1}
      local entities = layout.build(1, NAMES, shape)

      local belts = entities_named(entities, NAMES.belt)

      local south = defines.direction.south
      assert.are.same({south, south, south}, directions_of(belts))
    end)

    it("reads input belt, input inserter, furnace, output inserter, output belt along the first furnace's top row", function()
      local shape = {machine_size = 2, input_inserters = 1, output_inserters = 1}
      local entities = layout.build(1, NAMES, shape)

      assert.are.equal(NAMES.belt, name_at(entities, 0, 0))
      assert.are.equal(NAMES.inserter, name_at(entities, 1, 0))
      assert.are.equal(NAMES.machine, name_at(entities, 2, 0, 2))
      assert.are.equal(NAMES.inserter, name_at(entities, 4, 0))
      assert.are.equal(NAMES.belt, name_at(entities, 5, 0))
    end)

    it("puts the second furnace two tiles below the first", function()
      local shape = {machine_size = 2, input_inserters = 1, output_inserters = 1}
      local entities = layout.build(2, NAMES, shape)

      assert.are.equal(NAMES.machine, name_at(entities, 2, 0, 2))
      assert.are.equal(NAMES.machine, name_at(entities, 2, 2, 2))
    end)

    it("makes both inserters face west, picking up from the west and dropping to the east", function()
      local shape = {machine_size = 2, input_inserters = 1, output_inserters = 1}
      local entities = layout.build(1, NAMES, shape)

      local input_direction = direction_at(entities, 1, 0) -- picks up from the input belt, drops into the furnace
      local output_direction = direction_at(entities, 4, 0) -- picks up from the furnace, drops onto the output belt

      assert.are.equal(defines.direction.west, input_direction)
      assert.are.equal(defines.direction.west, output_direction)
    end)

    it("puts poles in the free tile below each inserter, for every second furnace", function()
      local shape = {machine_size = 2, input_inserters = 1, output_inserters = 1}
      local entities = layout.build(3, NAMES, shape)

      local poles = entities_named(entities, NAMES.pole)

      assert.are.same({
        {x = 1, y = 1}, {x = 4, y = 1}, -- below the first furnace's inserters
        {x = 1, y = 5}, {x = 4, y = 5}, -- below the third furnace's inserters
      }, tiles_of(poles))
    end)
  end)

  describe("wires", function()
    it("joins one furnace's two poles with a single wire", function()
      local shape = {machine_size = 2, input_inserters = 1, output_inserters = 1}
      local entities = layout.build(1, NAMES, shape)

      assert.are.equal(1, count_wires(entities))
    end)

    it("joins four poles with three wires: one down each side and one across the top", function()
      local shape = {machine_size = 2, input_inserters = 1, output_inserters = 1}
      local entities = layout.build(3, NAMES, shape)

      assert.are.equal(3, count_wires(entities))
    end)
  end)

  describe("a 3x3 machine fed by three inserters and emptied by two", function()
    it("puts the machine's three input inserters in the machine's three rows, west of it", function()
      local shape = {machine_size = 3, input_inserters = 3, output_inserters = 2}

      local entities = layout.build(1, NAMES, shape)

      assert.are.equal(NAMES.machine, name_at(entities, 2, 1, 3)) -- the machine starts below the top row of poles
      assert.are.equal(NAMES.inserter, name_at(entities, 1, 1))
      assert.are.equal(NAMES.inserter, name_at(entities, 1, 2))
      assert.are.equal(NAMES.inserter, name_at(entities, 1, 3))
    end)

    it("puts two output inserters in the machine's first two rows, east of it", function()
      local shape = {machine_size = 3, input_inserters = 3, output_inserters = 2}

      local entities = layout.build(1, NAMES, shape)

      assert.are.equal(NAMES.inserter, name_at(entities, 5, 1))
      assert.are.equal(NAMES.inserter, name_at(entities, 5, 2))
      assert.is_nil(name_at(entities, 5, 3))
    end)

    it("separates machines with a row of poles, because the inserters leave no free tile beside a machine", function()
      local shape = {machine_size = 3, input_inserters = 3, output_inserters = 2}

      local entities = layout.build(2, NAMES, shape)

      local poles = entities_named(entities, NAMES.pole)
      assert.are.same({
        {x = 1, y = 0}, {x = 5, y = 0}, -- above the first machine
        {x = 1, y = 4}, {x = 5, y = 4}, -- between the machines
        {x = 1, y = 8}, {x = 5, y = 8}, -- below the second machine
      }, tiles_of(poles))
    end)

    it("starts the second machine one row below the pole row that follows the first", function()
      local shape = {machine_size = 3, input_inserters = 3, output_inserters = 2}

      local entities = layout.build(2, NAMES, shape)

      assert.are.equal(NAMES.machine, name_at(entities, 2, 1, 3))
      assert.are.equal(NAMES.machine, name_at(entities, 2, 5, 3))
    end)

    it("runs the input belt from the first machine's top row to the last input inserter, and the output belt to the bottom pole row", function()
      local shape = {machine_size = 3, input_inserters = 3, output_inserters = 2}

      local entities = layout.build(2, NAMES, shape)

      local belts = entities_named(entities, NAMES.belt)
      assert.are.same({
        {x = 0, y = 1}, {x = 0, y = 2}, {x = 0, y = 3}, {x = 0, y = 4}, {x = 0, y = 5}, {x = 0, y = 6}, {x = 0, y = 7}, -- last input inserter is in row 7
        {x = 6, y = 1}, {x = 6, y = 2}, {x = 6, y = 3}, {x = 6, y = 4}, {x = 6, y = 5}, {x = 6, y = 6}, {x = 6, y = 7}, {x = 6, y = 8},
      }, tiles_of(belts))
    end)

    it("makes every inserter face west, picking up from the west", function()
      local shape = {machine_size = 3, input_inserters = 3, output_inserters = 2}

      local entities = layout.build(1, NAMES, shape)

      local inserters = entities_named(entities, NAMES.inserter)
      local west = defines.direction.west
      assert.are.same({west, west, west, west, west}, directions_of(inserters))
    end)
  end)

  describe("a 3x3 machine with a free tile beside it, fed by two inserters and emptied by one", function()
    it("puts each side's pole in the first free tile after that side's inserters", function()
      local shape = {machine_size = 3, input_inserters = 2, output_inserters = 1}

      local entities = layout.build(2, NAMES, shape)

      local poles = entities_named(entities, NAMES.pole)
      assert.are.same({
        {x = 1, y = 2}, -- after the two input inserters in rows 0 and 1
        {x = 5, y = 1}, -- after the one output inserter in row 0
      }, tiles_of(poles)) -- one pair serves both machines
    end)
  end)

  describe("supports_machine_size", function()
    it("supports machines 2 and 3 tiles wide", function()
      assert.is_true(layout.supports_machine_size(2))
      assert.is_true(layout.supports_machine_size(3))
    end)

    it("does not support machines 1 or 4 tiles wide, whose poles would not reach", function()
      assert.is_false(layout.supports_machine_size(1))
      assert.is_false(layout.supports_machine_size(4))
    end)
  end)

  describe("the whole blueprint, checked by the generic validator", function()
    for _, machine_count in ipairs({1, 2, 3, 4, 5, 24}) do
      it("passes the validator for " .. machine_count .. " powered 3x3 machines with a pole row between them", function()
        local shape = {machine_size = 3, input_inserters = 3, output_inserters = 2}
        local powered_catalog = builders.a_catalog{machine_size = 3, machine_needs_power = true}

        local entities = layout.build(machine_count, NAMES, shape)
        local problems = validator.validate(entities, powered_catalog)

        assert.are.same({}, problems)
      end)

      it("passes the validator for " .. machine_count .. " powered 3x3 machines fed by two inserters and emptied by three", function()
        local shape = {machine_size = 3, input_inserters = 2, output_inserters = 3}
        local powered_catalog = builders.a_catalog{machine_size = 3, machine_needs_power = true}

        local entities = layout.build(machine_count, NAMES, shape)
        local problems = validator.validate(entities, powered_catalog)

        assert.are.same({}, problems)
      end)

      it("passes the validator for " .. machine_count .. " powered 3x3 machines with free tiles beside them", function()
        local shape = {machine_size = 3, input_inserters = 2, output_inserters = 1}
        local powered_catalog = builders.a_catalog{machine_size = 3, machine_needs_power = true}

        local entities = layout.build(machine_count, NAMES, shape)
        local problems = validator.validate(entities, powered_catalog)

        assert.are.same({}, problems)
      end)

      it("passes the validator for " .. machine_count .. " powered 2x2 machines with two inserters on each side", function()
        local shape = {machine_size = 2, input_inserters = 2, output_inserters = 2}
        local powered_catalog = builders.a_catalog{machine_size = 2, machine_needs_power = true}

        local entities = layout.build(machine_count, NAMES, shape)
        local problems = validator.validate(entities, powered_catalog)

        assert.are.same({}, problems)
      end)
    end
  end)

  describe("the whole blueprint of furnaces, checked by the generic validator", function()
    for _, furnace_count in ipairs({1, 2, 3, 4, 5, 24}) do
      it("passes the validator for " .. furnace_count .. " furnaces", function()
        local small_pole_catalog = builders.a_catalog{pole_supply_radius = 2.5, pole_wire_reach = 7.5}

        local shape = {machine_size = 2, input_inserters = 1, output_inserters = 1}
        local entities = layout.build(furnace_count, NAMES, shape)
        local problems = validator.validate(entities, small_pole_catalog)

        assert.are.same({}, problems)
      end)
    end
  end)
end)
