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

-- Which way the entity on each tile of a column faces, from `first_row` down to
-- `last_row`; a gap in the column shows as `false`.
local function directions_down(entities, column, first_row, last_row)
  local directions = {}
  for row = first_row, last_row do
    directions[#directions + 1] = direction_at(entities, column, row) or false
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
    it("builds one machine for each machine asked for", function()
      local shape = {machine_size = 2, input_inserters = 1, output_inserters = 1}
      local entities = layout.build(3, NAMES, shape)

      assert.are.equal(3, count_named(entities, NAMES.machine))
    end)

    it("builds as many belt tiles as the column needs, with the input belt ending at the last inserter", function()
      local shape = {machine_size = 2, input_inserters = 1, output_inserters = 1}
      local entities = layout.build(3, NAMES, shape)

      assert.are.equal(11, count_named(entities, NAMES.belt)) -- 3 furnaces x 2 rows = 6 output; the last inserter is in row 4, so 5 input
    end)

    it("builds one input and one output inserter per machine when each side needs one", function()
      local shape = {machine_size = 2, input_inserters = 1, output_inserters = 1}
      local entities = layout.build(3, NAMES, shape)

      assert.are.equal(6, count_named(entities, NAMES.inserter))
    end)

    it("builds a pole on each side when there is one machine", function()
      local shape = {machine_size = 2, input_inserters = 1, output_inserters = 1}
      local entities = layout.build(1, NAMES, shape)

      assert.are.equal(2, count_named(entities, NAMES.pole))
    end)

    it("lets two machines share their poles", function()
      local shape = {machine_size = 2, input_inserters = 1, output_inserters = 1}
      local entities = layout.build(2, NAMES, shape)

      assert.are.equal(2, count_named(entities, NAMES.pole))
    end)

    it("builds a new pair of poles when a third machine is added", function()
      local shape = {machine_size = 2, input_inserters = 1, output_inserters = 1}
      local entities = layout.build(3, NAMES, shape)

      assert.are.equal(4, count_named(entities, NAMES.pole))
    end)

    it("builds a pole pair for every second machine", function()
      local shape = {machine_size = 2, input_inserters = 1, output_inserters = 1}
      local entities = layout.build(5, NAMES, shape)

      assert.are.equal(6, count_named(entities, NAMES.pole))
    end)

    it("builds nothing beyond the machines, belts, inserters and poles", function()
      local shape = {machine_size = 2, input_inserters = 1, output_inserters = 1}
      local entities = layout.build(3, NAMES, shape)

      assert.are.equal(24, #entities) -- 3 furnaces + 11 belts + 6 inserters + 4 poles
    end)

    it("numbers the entities in order, one number each", function()
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
    it("lays the belts along the column, with the input belt ending at the last input inserter", function()
      local shape = {machine_size = 2, input_inserters = 1, output_inserters = 1}
      local entities = layout.build(2, NAMES, shape)

      local belts = entities_named(entities, NAMES.belt)

      assert.are.same({
        {x = 0, y = 0}, {x = 0, y = 1}, {x = 0, y = 2}, -- the second furnace's input inserter is in row 2
        {x = 5, y = 0}, {x = 5, y = 1}, {x = 5, y = 2}, {x = 5, y = 3},
      }, tiles_of(belts))
    end)

    it("makes the input belt just long enough for the inserter when there is one machine", function()
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

    it("places the parts in order across the first machine's row, from the input belt to the output belt", function()
      local shape = {machine_size = 2, input_inserters = 1, output_inserters = 1}
      local entities = layout.build(1, NAMES, shape)

      assert.are.equal(NAMES.belt, name_at(entities, 0, 0))
      assert.are.equal(NAMES.inserter, name_at(entities, 1, 0))
      assert.are.equal(NAMES.machine, name_at(entities, 2, 0, 2))
      assert.are.equal(NAMES.inserter, name_at(entities, 4, 0))
      assert.are.equal(NAMES.belt, name_at(entities, 5, 0))
    end)

    it("stacks machines directly one below the next when more than one is built", function()
      local shape = {machine_size = 2, input_inserters = 1, output_inserters = 1}
      local entities = layout.build(2, NAMES, shape)

      assert.are.equal(NAMES.machine, name_at(entities, 2, 0, 2))
      assert.are.equal(NAMES.machine, name_at(entities, 2, 2, 2))
    end)

    it("makes inserters pick up from the input side and drop on the output side", function()
      local shape = {machine_size = 2, input_inserters = 1, output_inserters = 1}
      local entities = layout.build(1, NAMES, shape)

      local input_direction = direction_at(entities, 1, 0) -- picks up from the input belt, drops into the furnace
      local output_direction = direction_at(entities, 4, 0) -- picks up from the furnace, drops onto the output belt

      assert.are.equal(defines.direction.west, input_direction)
      assert.are.equal(defines.direction.west, output_direction)
    end)

    it("puts poles in the free tile beside the inserters, for every second machine", function()
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
    it("joins a machine's two poles with a wire", function()
      local shape = {machine_size = 2, input_inserters = 1, output_inserters = 1}
      local entities = layout.build(1, NAMES, shape)

      assert.are.equal(1, count_wires(entities))
    end)

    it("chains the poles down each side and join the two sides at the top", function()
      local shape = {machine_size = 2, input_inserters = 1, output_inserters = 1}
      local entities = layout.build(3, NAMES, shape)

      assert.are.equal(3, count_wires(entities))
    end)
  end)

  describe("a 3x3 machine fed by three inserters and emptied by two", function()
    it("puts an inserter beside each row of the machine when every row of the input side is used", function()
      local shape = {machine_size = 3, input_inserters = 3, output_inserters = 2}

      local entities = layout.build(1, NAMES, shape)

      assert.are.equal(NAMES.machine, name_at(entities, 2, 1, 3)) -- the machine starts below the top row of poles
      assert.are.equal(NAMES.inserter, name_at(entities, 1, 1))
      assert.are.equal(NAMES.inserter, name_at(entities, 1, 2))
      assert.are.equal(NAMES.inserter, name_at(entities, 1, 3))
    end)

    it("puts the output inserters in the machine's first rows when the output side is not full", function()
      local shape = {machine_size = 3, input_inserters = 3, output_inserters = 2}

      local entities = layout.build(1, NAMES, shape)

      assert.are.equal(NAMES.inserter, name_at(entities, 5, 1))
      assert.are.equal(NAMES.inserter, name_at(entities, 5, 2))
      assert.is_nil(name_at(entities, 5, 3))
    end)

    it("separates machines with a row of poles when the inserters leave no free tile", function()
      local shape = {machine_size = 3, input_inserters = 3, output_inserters = 2}

      local entities = layout.build(2, NAMES, shape)

      local poles = entities_named(entities, NAMES.pole)
      assert.are.same({
        {x = 1, y = 0}, {x = 5, y = 0}, -- above the first machine
        {x = 1, y = 4}, {x = 5, y = 4}, -- between the machines
        {x = 1, y = 8}, {x = 5, y = 8}, -- below the second machine
      }, tiles_of(poles))
    end)

    it("starts the next machine one row below the pole row", function()
      local shape = {machine_size = 3, input_inserters = 3, output_inserters = 2}

      local entities = layout.build(2, NAMES, shape)

      assert.are.equal(NAMES.machine, name_at(entities, 2, 1, 3))
      assert.are.equal(NAMES.machine, name_at(entities, 2, 5, 3))
    end)

    it("runs the belts from the first machine to the last inserter and the bottom pole row when machines are separated by pole rows", function()
      local shape = {machine_size = 3, input_inserters = 3, output_inserters = 2}

      local entities = layout.build(2, NAMES, shape)

      local belts = entities_named(entities, NAMES.belt)
      assert.are.same({
        {x = 0, y = 1}, {x = 0, y = 2}, {x = 0, y = 3}, {x = 0, y = 4}, {x = 0, y = 5}, {x = 0, y = 6}, {x = 0, y = 7}, -- last input inserter is in row 7
        {x = 6, y = 1}, {x = 6, y = 2}, {x = 6, y = 3}, {x = 6, y = 4}, {x = 6, y = 5}, {x = 6, y = 6}, {x = 6, y = 7}, {x = 6, y = 8},
      }, tiles_of(belts))
    end)

    it("makes every inserter pick up from the west when machines are separated by pole rows", function()
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

  describe("a 3x3 machine fed by two inserters and emptied by two, the most that leave a tile for a pole", function()
    it("puts the poles below the inserters when each side leaves one free tile", function()
      local shape = {machine_size = 3, input_inserters = 2, output_inserters = 2}

      local entities = layout.build(2, NAMES, shape)

      local poles = entities_named(entities, NAMES.pole)
      assert.are.same({
        {x = 1, y = 2}, -- after the two input inserters in rows 0 and 1
        {x = 5, y = 2}, -- after the two output inserters in rows 0 and 1
      }, tiles_of(poles))
    end)

    it("stacks machines with no pole row between them when each side leaves a free tile", function()
      local shape = {machine_size = 3, input_inserters = 2, output_inserters = 2}

      local entities = layout.build(2, NAMES, shape)

      assert.are.equal(NAMES.machine, name_at(entities, 2, 0, 3))
      assert.are.equal(NAMES.machine, name_at(entities, 2, 3, 3)) -- rows 3 to 5, right after rows 0 to 2
    end)
  end)

  describe("a 3x3 machine with two output inserters winds the output belt, so one inserter fills each lane", function()
    -- Columns: 5 output inserters, 6 inner belt (right beside them), 7 outer belt.
    -- Machine 1 covers rows 0 to 2 and machine 2 rows 3 to 5.
    local east, south, west = defines.direction.east, defines.direction.south, defines.direction.west

    it("runs the outer belt south, dipping west to pass the second inserter, when the output belt winds", function()
      local shape = {machine_size = 3, input_inserters = 2, output_inserters = 2}

      local entities = layout.build(2, NAMES, shape)

      assert.are.same({south, west, south, south, west, south}, directions_down(entities, 7, 0, 5))
    end)

    it("runs the inner belt as a stub, a southbound belt and a stub again for each machine", function()
      local shape = {machine_size = 3, input_inserters = 2, output_inserters = 2}

      local entities = layout.build(2, NAMES, shape)

      assert.are.same({east, south, east, east, south, east}, directions_down(entities, 6, 0, 5))
    end)

    it("places the two output inserters beside the stub and the southbound belt of the inner column", function()
      local shape = {machine_size = 3, input_inserters = 2, output_inserters = 2}

      local entities = layout.build(1, NAMES, shape)

      assert.are.equal(NAMES.inserter, name_at(entities, 5, 0)) -- drops onto the east stub, which joins the outer belt from the side
      assert.are.equal(NAMES.inserter, name_at(entities, 5, 1)) -- drops onto the south belt of the inner column
      assert.are.equal(NAMES.belt, name_at(entities, 6, 0))
      assert.are.equal(NAMES.belt, name_at(entities, 6, 1))
    end)

    it("runs the outer belt from the first machine's top row to the last machine's bottom row", function()
      local shape = {machine_size = 3, input_inserters = 2, output_inserters = 2}

      local entities = layout.build(2, NAMES, shape)

      assert.is_nil(name_at(entities, 7, -1))
      assert.is_nil(name_at(entities, 7, 6)) -- the player continues the belt from here
      assert.is_nil(name_at(entities, 6, 6))
    end)

    it("uses the same number of belt tiles for every machine when the output belt winds", function()
      local shape = {machine_size = 3, input_inserters = 2, output_inserters = 2}

      local entities = layout.build(3, NAMES, shape)

      local output_belts = {}
      for _, belt in ipairs(entities_named(entities, NAMES.belt)) do
        if grid.top_left_tile(belt.position).x >= 6 then
          output_belts[#output_belts + 1] = belt
        end
      end
      assert.are.equal(18, #output_belts)
    end)

    it("keeps a plain output belt when a machine has one output inserter", function()
      local shape = {machine_size = 3, input_inserters = 2, output_inserters = 1}

      local entities = layout.build(2, NAMES, shape)

      assert.are.same({south, south, south, south, south, south}, directions_down(entities, 6, 0, 5))
      assert.are.same({false, false, false, false, false, false}, directions_down(entities, 7, 0, 5))
    end)
  end)

  describe("max_input_inserters", function()
    it("leaves a tile beside the machine free for a pole when counting input inserters", function()
      assert.are.equal(1, layout.max_input_inserters(2))
      assert.are.equal(2, layout.max_input_inserters(3))
      assert.are.equal(3, layout.max_input_inserters(4))
    end)
  end)

  describe("max_output_inserters", function()
    it("leaves a tile free and never exceed what the winding belt serves when counting output inserters", function()
      assert.are.equal(1, layout.max_output_inserters(2))
      assert.are.equal(2, layout.max_output_inserters(3))
      assert.are.equal(2, layout.max_output_inserters(4))
      assert.are.equal(2, layout.max_output_inserters(5))
    end)
  end)

  describe("supports_machine_size", function()
    it("supports the machine sizes the poles can reach", function()
      assert.is_true(layout.supports_machine_size(2))
      assert.is_true(layout.supports_machine_size(3))
    end)

    it("does not support machine sizes whose poles would not reach", function()
      assert.is_false(layout.supports_machine_size(1))
      assert.is_false(layout.supports_machine_size(4))
    end)
  end)

  describe("the whole blueprint, checked by the generic validator", function()
    for _, machine_count in ipairs({1, 2, 3, 4, 5, 24}) do
      it("passes the validator when building " .. machine_count .. " 3x3 machines separated by pole rows", function()
        local shape = {machine_size = 3, input_inserters = 3, output_inserters = 2}
        local powered_catalog = builders.a_catalog{machine_size = 3, machine_needs_power = true}

        local entities = layout.build(machine_count, NAMES, shape)
        local problems = validator.validate(entities, powered_catalog)

        assert.are.same({}, problems)
      end)

      it("passes the validator when building " .. machine_count .. " 3x3 machines fed by two inserters and emptied by three", function()
        local shape = {machine_size = 3, input_inserters = 2, output_inserters = 3}
        local powered_catalog = builders.a_catalog{machine_size = 3, machine_needs_power = true}

        local entities = layout.build(machine_count, NAMES, shape)
        local problems = validator.validate(entities, powered_catalog)

        assert.are.same({}, problems)
      end)

      it("passes the validator when building " .. machine_count .. " 3x3 machines fed and emptied by one inserter each, with no pole row", function()
        local shape = {machine_size = 3, input_inserters = 1, output_inserters = 1}
        local powered_catalog = builders.a_catalog{machine_size = 3, machine_needs_power = true}

        local entities = layout.build(machine_count, NAMES, shape)
        local problems = validator.validate(entities, powered_catalog)

        assert.are.same({}, problems)
      end)

      it("passes the validator when building " .. machine_count .. " 3x3 machines fed by two inserters and emptied by two", function()
        local shape = {machine_size = 3, input_inserters = 2, output_inserters = 2}
        local powered_catalog = builders.a_catalog{machine_size = 3, machine_needs_power = true}

        local entities = layout.build(machine_count, NAMES, shape)
        local problems = validator.validate(entities, powered_catalog)

        assert.are.same({}, problems)
      end)

      it("passes the validator when building " .. machine_count .. " 3x3 machines fed by one inserter and emptied by two", function()
        local shape = {machine_size = 3, input_inserters = 1, output_inserters = 2}
        local powered_catalog = builders.a_catalog{machine_size = 3, machine_needs_power = true}

        local entities = layout.build(machine_count, NAMES, shape)
        local problems = validator.validate(entities, powered_catalog)

        assert.are.same({}, problems)
      end)

      it("passes the validator when building " .. machine_count .. " 3x3 machines with free tiles beside them", function()
        local shape = {machine_size = 3, input_inserters = 2, output_inserters = 1}
        local powered_catalog = builders.a_catalog{machine_size = 3, machine_needs_power = true}

        local entities = layout.build(machine_count, NAMES, shape)
        local problems = validator.validate(entities, powered_catalog)

        assert.are.same({}, problems)
      end)

      it("passes the validator when building " .. machine_count .. " 2x2 machines with two inserters on each side", function()
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
      it("passes the validator when building " .. furnace_count .. " furnaces", function()
        local small_pole_catalog = builders.a_catalog{pole_supply_radius = 2.5, pole_wire_reach = 7.5}

        local shape = {machine_size = 2, input_inserters = 1, output_inserters = 1}
        local entities = layout.build(furnace_count, NAMES, shape)
        local problems = validator.validate(entities, small_pole_catalog)

        assert.are.same({}, problems)
      end)
    end
  end)
end)
