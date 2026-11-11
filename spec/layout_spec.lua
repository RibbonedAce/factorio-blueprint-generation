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
local picture = require("spec.support.picture")
local tracer = require("spec.support.belt_tracer")
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

    it("runs the outer belt from one row above the first machine's top row to the last machine's bottom row", function()
      local shape = {machine_size = 3, input_inserters = 2, output_inserters = 2}

      local entities = layout.build(2, NAMES, shape)

      assert.are.equal(NAMES.belt, name_at(entities, 7, -1)) -- carries nothing; see the next test
      assert.is_nil(name_at(entities, 7, -2))
      assert.is_nil(name_at(entities, 7, 6)) -- the player continues the belt from here
      assert.is_nil(name_at(entities, 6, 6))
    end)

    it("starts the outer belt with an empty tile running south behind the first stub, so the first lane does not bend", function()
      local shape = {machine_size = 3, input_inserters = 2, output_inserters = 2}

      local entities = layout.build(2, NAMES, shape)

      assert.are.equal(defines.direction.south, direction_at(entities, 7, -1))
      assert.are.equal(defines.direction.south, direction_at(entities, 7, 0)) -- straight on from the empty tile
      assert.are.equal(defines.direction.east, direction_at(entities, 6, 0)) -- the stub side-loads it
      assert.is_nil(name_at(entities, 6, -1))
    end)

    it("uses the same number of belt tiles for every machine when the output belt winds, plus the empty tile", function()
      local shape = {machine_size = 3, input_inserters = 2, output_inserters = 2}

      local entities = layout.build(3, NAMES, shape)

      local output_belts = {}
      for _, belt in ipairs(entities_named(entities, NAMES.belt)) do
        if grid.top_left_tile(belt.position).x >= 6 then
          output_belts[#output_belts + 1] = belt
        end
      end
      assert.are.equal(19, #output_belts) -- 3 machines x 6, and the empty tile
    end)

    it("keeps a plain output belt when a machine has one output inserter", function()
      local shape = {machine_size = 3, input_inserters = 2, output_inserters = 1}

      local entities = layout.build(2, NAMES, shape)

      assert.are.same({south, south, south, south, south, south}, directions_down(entities, 6, 0, 5))
      assert.are.same({false, false, false, false, false, false}, directions_down(entities, 7, 0, 5))
    end)
  end)

  describe("a 3x3 machine fed by a plain and a long-handed inserter and emptied by one", function()
    -- The plain inserter takes from the input belt in column 0; the long-handed one, in the same column of
    -- inserters, takes from the belt one column further west (column -1), over the input belt.
    local shape = {machine_size = 3, input_inserters = 1, long_inserters = 1, output_inserters = 1}

    it("puts the long-handed inserter in the row under the plain one, in the same column, for every machine", function()
      local entities = layout.build(2, NAMES, shape)

      assert.are.equal(NAMES.inserter, name_at(entities, 1, 0))
      assert.are.equal(NAMES.long_inserter, name_at(entities, 1, 1))
      assert.are.equal(NAMES.inserter, name_at(entities, 1, 3)) -- the second machine, rows 3 to 5
      assert.are.equal(NAMES.long_inserter, name_at(entities, 1, 4))
      assert.are.equal(2, count_named(entities, NAMES.long_inserter))
    end)

    it("points the long-handed inserters the same way as the plain ones, at the machine", function()
      local entities = layout.build(1, NAMES, shape)

      assert.are.equal(direction_at(entities, 1, 0), direction_at(entities, 1, 1))
    end)

    it("puts the pole of the input side under the long-handed inserter", function()
      local entities = layout.build(2, NAMES, shape)

      local poles = entities_named(entities, NAMES.pole)
      assert.are.same({
        {x = 1, y = 2}, -- after the plain inserter in row 0 and the long-handed one in row 1
        {x = 5, y = 1}, -- after the one output inserter in row 0
      }, tiles_of(poles))
    end)

    it("stacks machines with no pole row between them when the two inserters leave a tile free", function()
      local entities = layout.build(2, NAMES, shape)

      assert.are.equal(NAMES.machine, name_at(entities, 2, 0, 3))
      assert.are.equal(NAMES.machine, name_at(entities, 2, 3, 3))
    end)

    it("separates the machines with rows of poles when the inserters fill every tile beside them", function()
      local full = {machine_size = 3, input_inserters = 2, long_inserters = 1, output_inserters = 1}

      local entities = layout.build(2, NAMES, full)

      assert.are.equal(NAMES.machine, name_at(entities, 2, 1, 3)) -- a row of poles above the first machine
      assert.are.equal(NAMES.machine, name_at(entities, 2, 5, 3)) -- and one between the machines
    end)

    it("ends the input belt at the last plain inserter, not at the last long-handed one", function()
      local entities = layout.build(2, NAMES, shape)

      local rows = {}
      for _, belt in ipairs(entities_named(entities, NAMES.belt)) do
        if grid.top_left_tile(belt.position).x == 0 then
          rows[#rows + 1] = grid.top_left_tile(belt.position).y
        end
      end
      table.sort(rows)
      assert.are.same({0, 1, 2, 3}, rows) -- the second machine's plain inserter is in row 3, its long-handed one in row 4
    end)

    it("passes the validator when a belt runs in the column west of the input belt for the long-handed inserters", function()
      local entities = layout.build(2, NAMES, shape)
      for row = 0, 4 do
        local belt = builders.belt(-1, row)
        belt.entity_number = #entities + 1
        entities[#entities + 1] = belt
      end
      local catalog = builders.a_catalog{machine_size = 3, machine_needs_power = true}

      local problems = validator.validate(entities, catalog)

      assert.are.same({}, problems)
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

  describe("a chain of furnaces whose plates feed gear assemblers", function()
    -- Furnaces (2x2) at x = 2..3 with plain belts at x = 0 (ore) and x = 5 (plates);
    -- the assemblers (3x3) follow at x = 7..9, fed from the plate belt at x = 5.
    local ASSEMBLER = "assembling-machine-1"
    local furnace_shape = {machine_size = 2, input_inserters = 1, output_inserters = 1}
    local assembler_shape = {machine_size = 3, input_inserters = 2, output_inserters = 2}

    local function gear_chain(furnace_count, assembler_count)
      return layout.build_chain({
        {machine_count = furnace_count, machine = NAMES.machine, shape = furnace_shape},
        {machine_count = assembler_count, machine = ASSEMBLER, shape = assembler_shape},
      }, NAMES)
    end

    local function belts_in_column(entities, x)
      local rows = {}
      for _, entity in ipairs(entities_named(entities, NAMES.belt)) do
        if grid.top_left_tile(entity.position).x == x then
          rows[#rows + 1] = grid.top_left_tile(entity.position).y
        end
      end
      table.sort(rows)
      return rows
    end

    -- The directions the belts of one tile column run in, without repeats.
    local function belt_directions_in_column(entities, x)
      local directions, seen = {}, {}
      for _, entity in ipairs(entities_named(entities, NAMES.belt)) do
        if grid.top_left_tile(entity.position).x == x and not seen[entity.direction] then
          seen[entity.direction] = true
          directions[#directions + 1] = entity.direction
        end
      end
      return directions
    end

    -- The rows of the inserters in one tile column.
    local function inserter_rows(entities, x)
      local rows = {}
      for _, entity in ipairs(entities_named(entities, NAMES.inserter)) do
        local tile = grid.top_left_tile(entity.position)
        if tile.x == x then
          rows[#rows + 1] = tile.y
        end
      end
      return rows
    end

    -- Whether an item put on a belt running `direction` in `from_row` passes `row` (the same row counts).
    local function belt_passes(direction, from_row, row)
      if direction == defines.direction.north then
        return row <= from_row
      end
      return row >= from_row
    end

    -- The inserters of a two-column chain (belt in tile column `belt_x`) that waste their plates or
    -- never get any, as text: an output inserter drops plates that no input inserter is ahead of, or
    -- an input inserter has no output inserter before it.
    local function plate_flow_problems(entities, belt_x)
      local direction = belt_directions_in_column(entities, belt_x)[1]
      local drops, pickups = inserter_rows(entities, belt_x - 1), inserter_rows(entities, belt_x + 1)
      local problems = {}
      for _, drop in ipairs(drops) do
        local reached = false
        for _, pickup in ipairs(pickups) do
          reached = reached or belt_passes(direction, drop, pickup)
        end
        if not reached then
          problems[#problems + 1] = "the plates dropped in row " .. drop .. " pass no input inserter"
        end
      end
      for _, pickup in ipairs(pickups) do
        local supplied = false
        for _, drop in ipairs(drops) do
          supplied = supplied or belt_passes(direction, drop, pickup)
        end
        if not supplied then
          problems[#problems + 1] = "the input inserter in row " .. pickup .. " gets no plates"
        end
      end
      return problems
    end

    it("builds each column's machines with that stage's machine name", function()
      local entities = gear_chain(7, 2)

      assert.are.equal(7, count_named(entities, NAMES.machine))
      assert.are.equal(2, count_named(entities, ASSEMBLER))
    end)

    it("places the assemblers right after the plate belt", function()
      local entities = gear_chain(7, 2)

      local first_assembler = assert(entities_named(entities, ASSEMBLER)[1])
      assert.are.same({x = 7, y = 0}, grid.top_left_tile(first_assembler.position, 3, 3))
    end)

    it("runs the plate belt between the columns without a gap, from the top to the last row either column needs", function()
      local entities = gear_chain(7, 2) -- furnaces cover rows 0 to 13 and their last inserter is in row 12; the assemblers' inserters end at row 4

      local rows = belts_in_column(entities, 5)

      assert.are.same({0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12}, rows) -- nothing in row 13, below the last furnace's inserter
    end)

    it("draws a single plate belt tile when the one furnace and the one assembler use the same row", function()
      local entities = layout.build_chain({
        {machine_count = 1, machine = NAMES.machine, shape = furnace_shape},
        {machine_count = 1, machine = ASSEMBLER, shape = {machine_size = 3, input_inserters = 1, output_inserters = 1}},
      }, NAMES) -- both inserters are in row 0; the furnace covers rows 0 and 1

      assert.are.same({0}, belts_in_column(entities, 5))
    end)

    it("runs the plate belt down to the last assembler's inserters when the assemblers reach further than the furnaces", function()
      local entities = gear_chain(1, 4) -- one furnace covers rows 0 and 1; four assemblers take rows 0 to 11

      local rows = belts_in_column(entities, 5)

      assert.are.equal(0, rows[1])
      assert.are.equal(10, rows[#rows]) -- the last assembler's last input inserter is in row 10
    end)

    it("runs the plate belt north, so every furnace's plates pass the assemblers, when the furnaces reach further down", function()
      local entities = gear_chain(11, 2) -- the last furnace drops in row 20; the last assembler inserter is in row 4

      assert.are.same({defines.direction.north}, belt_directions_in_column(entities, 5))
    end)

    it("draws only the belts the three belt columns need, so the assemblers get no input belt of their own", function()
      local entities = gear_chain(7, 2)

      -- ore: down to the last furnace's inserter (row 12) = 13; plates: the same 13; gears: 2 machines * 3 rows * 2 columns = 12, and the empty tile
      assert.are.equal(13 + 13 + 12 + 1, count_named(entities, NAMES.belt))
    end)

    it("winds only the last column's output belt", function()
      local entities = gear_chain(7, 2)

      assert.are.equal(2 * 3 * 2 + 1, #belts_in_column(entities, 11) + #belts_in_column(entities, 12))
      assert.are.equal(13, #belts_in_column(entities, 5)) -- straight, down to the last furnace's inserter
    end)

    it("numbers every entity once across the columns", function()
      local entities = gear_chain(7, 2)

      for index, entity in ipairs(entities) do
        assert.are.equal(index, entity.entity_number)
      end
    end)

    it("joins the poles of the two columns by a wire", function()
      local entities = gear_chain(3, 2)

      local catalog = builders.a_catalog{pole_supply_radius = 2.5, pole_wire_reach = 7.5}
      catalog[ASSEMBLER] = {kind = "machine", width = 3, height = 3, needs_power = true}
      local problems = validator.validate(entities, catalog)

      assert.are.same({}, problems)
    end)

    it("starts the assemblers on the furnaces' row, below the pole row, when only the furnaces are separated by pole rows", function()
      -- furnaces with two input inserters have a pole row above the first one, so their first machine row is 1
      local entities = layout.build_chain({
        {machine_count = 3, machine = NAMES.machine, shape = {machine_size = 2, input_inserters = 2, output_inserters = 1}},
        {machine_count = 2, machine = ASSEMBLER, shape = assembler_shape},
      }, NAMES)

      local first_assembler = assert(entities_named(entities, ASSEMBLER)[1])
      assert.are.same({x = 7, y = 1}, grid.top_left_tile(first_assembler.position, 3, 3))
    end)

    it("starts the furnaces on the assemblers' row, below the pole row, when only the assemblers are separated by pole rows", function()
      local entities = layout.build_chain({
        {machine_count = 3, machine = NAMES.machine, shape = furnace_shape},
        {machine_count = 2, machine = ASSEMBLER, shape = {machine_size = 3, input_inserters = 3, output_inserters = 2}},
      }, NAMES)

      local first_furnace = assert(entities_named(entities, NAMES.machine)[1])
      assert.are.same({x = 2, y = 1}, grid.top_left_tile(first_furnace.position, 2, 2))
    end)

    it("keeps the belt between two columns straight when the first column's machines would wind their output belt", function()
      -- 3x3 machines with two output inserters wind a belt of their own when they are the last column
      local entities = layout.build_chain({
        {machine_count = 2, machine = ASSEMBLER, shape = assembler_shape},
        {machine_count = 1, machine = NAMES.machine, shape = furnace_shape},
      }, NAMES)

      -- the machines cover columns 2 to 4 and their output inserters are in 5, so the belt is in 6; their last output inserter is in row 4
      assert.are.same({0, 1, 2, 3, 4}, belts_in_column(entities, 6))
      assert.are.same({}, belts_in_column(entities, 7))
    end)

    it("joins the top output pole of a column to the top input pole of the next with one wire", function()
      local entities = gear_chain(3, 2)

      -- furnaces: the output pole is in column 4, beside the first furnace's inserter (row 1);
      -- assemblers: the input pole is in column 6, below the two input inserters (row 2)
      local function pole_at(x, y)
        for _, entity in ipairs(entities_named(entities, NAMES.pole)) do
          local tile = grid.top_left_tile(entity.position)
          if tile.x == x and tile.y == y then
            return entity
          end
        end
      end
      local furnace_output_pole, assembler_input_pole = pole_at(4, 1), pole_at(6, 2)

      local wires_between = 0
      for _, wire in ipairs(furnace_output_pole.wires or {}) do
        if wire[3] == assembler_input_pole.entity_number then
          wires_between = wires_between + 1
        end
      end
      assert.are.equal(1, wires_between)
    end)

    -- The same chain for every pairing of column shapes, with a few machine counts each.
    local column_shapes = {
      {label = "2x2 machines fed and emptied by one inserter", machine = NAMES.machine, shape = furnace_shape},
      {label = "2x2 machines separated by pole rows", machine = NAMES.machine, shape = {machine_size = 2, input_inserters = 2, output_inserters = 1}},
      {label = "3x3 machines fed and emptied by two inserters", machine = ASSEMBLER, shape = assembler_shape},
      {label = "3x3 machines fed by one inserter and emptied by one", machine = ASSEMBLER, shape = {machine_size = 3, input_inserters = 1, output_inserters = 1}},
      {label = "3x3 machines separated by pole rows", machine = ASSEMBLER, shape = {machine_size = 3, input_inserters = 3, output_inserters = 2}},
    }
    for _, first in ipairs(column_shapes) do
      for _, second in ipairs(column_shapes) do
        for _, counts in ipairs({{1, 1}, {3, 1}, {1, 4}, {7, 3}}) do
          it("passes the validator when " .. first.label .. " feed " .. second.label .. ", " .. counts[1] .. " and " .. counts[2] .. " machines", function()
            local catalog = builders.a_catalog{pole_supply_radius = 2.5, pole_wire_reach = 7.5}
            catalog[NAMES.machine] = {kind = "machine", width = 2, height = 2, needs_power = true}
            catalog[ASSEMBLER] = {kind = "machine", width = 3, height = 3, needs_power = true}

            local entities = layout.build_chain({
              {machine_count = counts[1], machine = first.machine, shape = first.shape},
              {machine_count = counts[2], machine = second.machine, shape = second.shape},
            }, NAMES)

            assert.are.same({}, validator.validate(entities, catalog))
          end)
        end
      end
    end

    -- The same pairings again, for the flow of the items on the belt between the columns. The work is
    -- the same in both columns (`rate` items a minute), so each column gets `rate / flow` machines' worth
    -- of it, with `flow` what one of its machines handles: that is how the planner sizes a chain, and
    -- the belt runs the way the columns' lengths for that work say.
    local flows = {18.75, 18.75, 100.8, 50.4, 100.8} -- items a minute one machine of each of column_shapes handles

    -- The belt has to run the same way at every rate, since the shapes decide it: the owner's rule
    -- (2026-11-06 22:59), after 1 copper cable a minute ran south and 900 ran north.
    local function belt_direction_at(second, flow, rate)
      local first_load, second_load = rate / flows[1], rate / flow
      local entities = layout.build_chain({
        {machine_count = math.ceil(first_load), load = first_load, machine = NAMES.machine, shape = furnace_shape},
        {machine_count = math.ceil(second_load), load = second_load, machine = ASSEMBLER, shape = second},
      }, NAMES)
      local directions = belt_directions_in_column(entities, 5)
      assert.are.equal(1, #directions)
      return directions[1]
    end

    it("runs the plate belt north when the two columns are equally long for the work they do", function()
      local entities = layout.build_chain({
        {machine_count = 3, load = 3, machine = NAMES.machine, shape = furnace_shape}, -- 3 x 2 rows
        {machine_count = 2, load = 2, machine = ASSEMBLER, shape = assembler_shape}, -- 2 x 3 rows
      }, NAMES)

      assert.are.same({defines.direction.north}, belt_directions_in_column(entities, 5))
    end)

    it("runs the plate belt by the work the columns do, not by the machines they have", function()
      local entities = layout.build_chain({
        {machine_count = 3, load = 0.3, machine = NAMES.machine, shape = furnace_shape}, -- 0.6 rows of work
        {machine_count = 1, load = 1, machine = ASSEMBLER, shape = assembler_shape}, -- 3 rows
      }, NAMES) -- by machines, the furnaces' last inserter (row 4) is below the assembler's last (row 1): north

      assert.are.same({defines.direction.south}, belt_directions_in_column(entities, 5))
    end)

    local north, south = defines.direction.north, defines.direction.south
    for _, case in ipairs({
      {label = "gears (2 plates in, 1 gear out)", shape = assembler_shape, flow = 100.8, direction = north},
      {label = "cables (1 plate in, 2 cables out)", shape = {machine_size = 3, input_inserters = 1, output_inserters = 2}, flow = 50.4, direction = north},
      {label = "a slow recipe that eats 6 plates a minute a machine", shape = {machine_size = 3, input_inserters = 1, output_inserters = 1}, flow = 6, direction = south},
    }) do
      for _, rate in ipairs({0.5, 1, 5, 20, 100, 225}) do
        it("runs the plate belt the same way for " .. case.label .. " at " .. rate .. " items a minute as at any other rate", function()
          assert.are.equal(case.direction, belt_direction_at(case.shape, case.flow, rate))
        end)
      end
    end
    -- Only a furnace column comes first, as in the chains the generator makes. A column of assemblers
    -- feeding another one of the same kind is not covered: with columns of nearly the same length for
    -- the work, the rows of the two columns do not always overlap, and the belt direction cannot help.
    local first_index, first = 1, column_shapes[1]
    do
      for second_index, second in ipairs(column_shapes) do
        for _, rate in ipairs({20, 50, 100, 300}) do
          local first_load, second_load = rate / flows[first_index], rate / flows[second_index]
          it("lets every plate reach an input inserter and every input inserter get plates when " .. first.label .. " feed " .. second.label .. ", " .. rate .. " items a minute", function()
            local entities = layout.build_chain({
              {machine_count = math.ceil(first_load), load = first_load, machine = first.machine, shape = first.shape},
              {machine_count = math.ceil(second_load), load = second_load, machine = second.machine, shape = second.shape},
            }, NAMES)

            local plate_belt_column = 3 + first.shape.machine_size -- the machines start in column 2, then come their width and a column of output inserters
            assert.are.same({}, plate_flow_problems(entities, plate_belt_column))
          end)
        end
      end
    end
  end)

  describe("fast inserters", function()
    local function names_without_fast_inserter()
      return {machine = NAMES.machine, belt = NAMES.belt, inserter = NAMES.inserter, long_inserter = NAMES.long_inserter, pole = NAMES.pole}
    end

    it("draws the input side with fast inserters when the shape says so, and the output side with plain ones", function()
      local shape = {machine_size = 2, input_inserters = 1, input_fast = true, output_inserters = 1}

      local entities = layout.build(1, NAMES, shape)

      assert.are.same({NAMES.fast_inserter, NAMES.inserter}, {name_at(entities, 1, 0), name_at(entities, 4, 0)})
    end)

    it("draws the output side with fast inserters when the shape says so, and the input side with plain ones", function()
      local shape = {machine_size = 2, input_inserters = 1, output_inserters = 1, output_fast = true}

      local entities = layout.build(1, NAMES, shape)

      assert.are.same({NAMES.inserter, NAMES.fast_inserter}, {name_at(entities, 1, 0), name_at(entities, 4, 0)})
    end)

    it("draws every inserter of a side with the same prototype, one under the next", function()
      local shape = {machine_size = 3, input_inserters = 2, input_fast = true, output_inserters = 1}

      local entities = layout.build(1, NAMES, shape)

      assert.are.same({NAMES.fast_inserter, NAMES.fast_inserter}, {name_at(entities, 1, 0), name_at(entities, 1, 1)})
    end)

    it("keeps a long-handed inserter long-handed under a fast one", function()
      local shape = {machine_size = 3, input_inserters = 1, input_fast = true, long_inserters = 1, output_inserters = 1}

      local entities = layout.build(1, NAMES, shape)

      assert.are.same({NAMES.fast_inserter, NAMES.long_inserter}, {name_at(entities, 1, 0), name_at(entities, 1, 1)})
    end)

    it("draws plain inserters when the shape says nothing, as it always did", function()
      local entities = layout.build(1, NAMES, {machine_size = 2, input_inserters = 1, output_inserters = 1})

      assert.are.equal(0, count_named(entities, NAMES.fast_inserter))
    end)

    describe("three fast inserters on a 3x3 machine, which take every tile beside it", function()
      -- No tile is free for a pole, so the machines stand 4 rows apart with a row of poles above each (rows 0, 4 and 8).
      local shape = {machine_size = 3, input_inserters = 3, input_fast = true, output_inserters = 1}
      local entities = layout.build(2, NAMES, shape)

      it("stands the machines apart, the first in row 1 and the second in row 5", function()
        assert.is_not_nil(entity_at(entities, 2, 1, 3))
        assert.is_not_nil(entity_at(entities, 2, 5, 3))
      end)

      it("puts the three inserters of each machine under each other, and a pole in the row above", function()
        assert.are.same({NAMES.pole, NAMES.fast_inserter, NAMES.fast_inserter, NAMES.fast_inserter},
          {name_at(entities, 1, 0), name_at(entities, 1, 1), name_at(entities, 1, 2), name_at(entities, 1, 3)})
      end)

      it("passes the validator, every inserter fed, emptied and powered", function()
        local catalog = builders.a_catalog{machine_size = 3, machine_needs_power = true}

        assert.are.same({}, validator.validate(entities, catalog))
      end)
    end)

    describe("the paired winding belt: one fast output inserter on each 3x3 machine, the machines in twos", function()
      -- Columns 5 (the output inserters), 6 (the inner belt) and 7 (the outer belt) for four machines, rows 0 to 11: the
      -- belt starts in the inner column, and at each seam two inserters (the upper machine's in its last row, the lower
      -- one's in its first) drop on a curve (outer lane) or on a stub that side-loads (inner lane); the seams alternate.
      --
      --      567
      --   0 |.v.
      --   1 |+v.      pole: in the middle row of the upper machine of a pair
      --   2 |}>v      the upper machine's inserter drops on the curve
      --   3 |}>v      the lower machine's inserter drops on the stub
      --   4 |..v
      --   5 |..v
      --   6 |..v
      --   7 |+.v
      --   8 |}>v      the upper machine's inserter drops on the stub
      --   9 |}v<      the belt turns west; the lower machine's inserter drops on the curve
      --  10 |.v.
      --  11 |.v.
      local shape = {machine_size = 3, input_inserters = 1, input_fast = true, output_inserters = 1, output_fast = true}
      local machines = {[NAMES.machine] = {size = 3, glyph = "M"}}

      local function drawn(count, last_row)
        return picture.draw(layout.build(count, NAMES, shape), machines, 5, 0, 7, last_row)
      end

      it("weaves the belt between the inner and the outer column, a seam every two machines", function()
        assert.are.same({".v.", "+v.", "}>v", "}>v", "..v", "..v", "..v", "+.v", "}>v", "}v<", ".v.", ".v."}, drawn(4, 11))
      end)

      it("puts the inserters of the upper and the lower machine of a pair side by side", function()
        local entities = layout.build(4, NAMES, shape)
        local rows = {}
        for _, entity in ipairs(entities_named(entities, NAMES.fast_inserter)) do
          local tile = grid.top_left_tile(entity.position)
          if tile.x == 5 then
            rows[#rows + 1] = tile.y
          end
        end
        table.sort(rows)

        assert.are.same({2, 3, 8, 9}, rows)
      end)

      it("ends two machines in the outer column, the belt running on to the bottom", function()
        assert.are.same({".v.", "+v.", "}>v", "}>v", "..v", "..v"}, drawn(2, 5))
      end)

      it("gives a machine left alone at the end a stub that side-loads the outer belt", function()
        assert.are.same({"..v", "+.v", "}>v"}, {drawn(3, 8)[7], drawn(3, 8)[8], drawn(3, 8)[9]})
      end)

      it("lets the belt come down in the inner column to a machine left alone after a turn west", function()
        assert.are.same({".v.", ".v.", ".v.", "+v.", "}>v"}, {drawn(5, 14)[11], drawn(5, 14)[12], drawn(5, 14)[13], drawn(5, 14)[14], drawn(5, 14)[15]})
      end)

      -- The output inserter, the pole and the belt of a plain output belt, in columns 5 and 6, for the first machine.
      local plain_belt = {"}v", "+v", ".v"}

      it("does not pair one machine alone, which has a plain output belt", function()
        local entities = layout.build(1, NAMES, shape)

        assert.are.same(plain_belt, picture.draw(entities, machines, 5, 0, 6, 2))
      end)

      it("does not pair machines with a plain output inserter, whose one lane the plain belt keeps", function()
        local plain = {machine_size = 3, input_inserters = 1, output_inserters = 1}
        local entities = layout.build(4, NAMES, plain)

        assert.are.same(plain_belt, picture.draw(entities, machines, 5, 0, 6, 2))
      end)

      it("does not pair a column that feeds another column, whose output belt is the next column's input belt", function()
        local stages = {
          {machine_count = 4, machine = NAMES.machine, shape = shape},
          {machine_count = 4, machine = NAMES.machine, shape = shape},
        }

        local block = layout.chain_block(stages, NAMES, {product_belt = false})

        assert.are.same({"}^", "+^", ".^"}, picture.draw(block.entities, machines, 5, 0, 6, 2)) -- two columns of equal length: the belt runs north
      end)

      it("passes the validator for an even and an odd number of machines, every inserter fed, emptied and powered", function()
        local catalog = builders.a_catalog{machine_size = 3, machine_needs_power = true}

        assert.are.same({}, validator.validate(layout.build(4, NAMES, shape), catalog))
        assert.are.same({}, validator.validate(layout.build(5, NAMES, shape), catalog))
      end)

      describe("which lane each inserter fills, found by making a different thing in every machine", function()
        -- The machines of the column are renamed one by one so that each makes its own product. When two machines whose
        -- inserters share a lane make different things, the tracer reports a lane that carries both.
        local function lane_problems(count, makes)
          local entities = layout.build(count, NAMES, shape)
          local machine_options, index = {}, 0
          for _, entity in ipairs(entities) do
            if entity.name == NAMES.machine then
              index = index + 1
              entity.name = "machine-" .. index
              machine_options[entity.name] = {size = 3, eats = {}, makes = makes[index]}
            end
          end
          local problems = {}
          for _, problem in ipairs(tracer.problems(entities, {machines = machine_options, raw = {}, product = "nothing"})) do
            if problem:find("lane", 1, true) then
              problems[#problems + 1] = problem
            end
          end
          return problems
        end

        it("fills the outer lane from the first and the fourth machine and the inner lane from the second and the third", function()
          assert.are.same({}, lane_problems(4, {"outer", "inner", "inner", "outer"}))
        end)

        it("fills the same lane from the first two machines, so two different things on them are reported", function()
          assert.is_true(#lane_problems(4, {"one", "two", "two", "one"}) == 0 and #lane_problems(4, {"outer", "outer", "inner", "inner"}) > 0)
        end)

        it("goes on alternating, outer, inner, inner, outer, outer, inner, inner, outer, for eight machines", function()
          assert.are.same({}, lane_problems(8, {"o", "i", "i", "o", "o", "i", "i", "o"}))
        end)
      end)
    end)

    it("is refused for a shape that wants fast inserters when the layout is not given their name", function()
      local shape = {machine_size = 2, input_inserters = 1, input_fast = true, output_inserters = 1}

      assert.has_error(function() layout.build(1, names_without_fast_inserter(), shape) end)
    end)

    describe("how many inserters a side may have", function()
      it("is one fewer than the machine is tall for the input side, plain or fast, which leaves a tile for a pole", function()
        assert.are.same({1, 2}, {layout.max_input_inserters(2), layout.max_input_inserters(3)})
      end)

      it("is at most the two that the winding belt serves for the output side, plain or fast", function()
        assert.are.same({1, 2}, {layout.max_output_inserters(2), layout.max_output_inserters(3)})
      end)
    end)
  end)

  describe("a stage that burns fuel which rides the free lane of the belt before it", function()
    -- Seven furnaces and seven more that eat their plates (a furnace eats the plates one furnace makes, so the two columns
    -- are as long as each other). The belt between them is in column 5: without fuel it runs north, as for any two columns
    -- of equal length; with fuel it runs south, so that its head, where the fuel is side-loaded, is at the top.
    local furnace_shape = {machine_size = 2, input_inserters = 1, output_inserters = 1}

    local function two_columns(fuel_feed)
      local first = {machine_count = 7, machine = NAMES.machine, shape = furnace_shape}
      local second = {machine_count = 7, machine = NAMES.machine, shape = furnace_shape, fuel_feed = fuel_feed}
      return layout.chain_block({first, second}, NAMES, {product_belt = false}), second
    end

    local function belt_directions(block, x)
      local directions, seen = {}, {}
      for _, entity in ipairs(entities_named(block.entities, NAMES.belt)) do
        if grid.top_left_tile(entity.position).x == x and not seen[entity.direction] then
          seen[entity.direction] = true
          directions[#directions + 1] = entity.direction
        end
      end
      return directions
    end

    local coal = {items = {{name = "coal", amount = 10}}}

    it("runs the belt between two columns of equal length north when no fuel rides it", function()
      local block = two_columns(nil)

      assert.are.same({defines.direction.north}, belt_directions(block, 5))
    end)

    it("runs the belt between the two columns south when fuel rides it", function()
      local block = two_columns(coal)

      assert.are.same({defines.direction.south}, belt_directions(block, 5))
    end)

    it("says where the fuel has to arrive: the column of the belt between the columns and its first row", function()
      local block, second = two_columns(coal)

      assert.are.equal(second, block.fuel_feeds[1].stage)
      assert.are.same({5, 0}, {block.fuel_feeds[1].belt_column, block.fuel_feeds[1].row})
    end)

    it("says nothing of fuel for a chain whose stages burn none from the belt", function()
      local block = two_columns(nil)

      assert.are.same({}, block.fuel_feeds)
    end)

    it("refuses fuel for the first column of a chain, which has no belt before it", function()
      local only = {machine_count = 1, machine = NAMES.machine, shape = furnace_shape, fuel_feed = coal}

      assert.has_error(function() layout.chain_block({only}, NAMES, {product_belt = false}) end)
    end)

    it("refuses fuel for a column after one that needs a row of poles, whose column the fuel comes down", function()
      local crowded = {machine_size = 2, input_inserters = 2, output_inserters = 1}
      local first = {machine_count = 2, machine = NAMES.machine, shape = crowded}
      local second = {machine_count = 2, machine = NAMES.machine, shape = furnace_shape, fuel_feed = coal}

      assert.has_error(function() layout.chain_block({first, second}, NAMES, {product_belt = false}) end)
    end)
  end)

  describe("chain_block, a chain of columns as a block", function()
    local furnace_shape = {machine_size = 2, input_inserters = 1, output_inserters = 1}
    local assembler_shape = {machine_size = 3, input_inserters = 2, output_inserters = 2}
    local ASSEMBLER = "assembling-machine-1"

    -- 7 furnaces (14 rows) feeding 2 assemblers (6 rows): the furnaces cover columns 2-3, the assemblers 7-9.
    local function furnaces_and_assemblers(options)
      local stages = {
        {machine_count = 7, machine = NAMES.machine, shape = furnace_shape},
        {machine_count = 2, machine = ASSEMBLER, shape = assembler_shape},
      }
      return layout.chain_block(stages, NAMES, options)
    end

    local function belt_rows(entities, x)
      local rows = {}
      for _, entity in ipairs(entities_named(entities, NAMES.belt)) do
        if grid.top_left_tile(entity.position).x == x then
          rows[#rows + 1] = grid.top_left_tile(entity.position).y
        end
      end
      table.sort(rows)
      return rows
    end

    it("gives every pole of the block", function()
      local block = furnaces_and_assemblers{product_belt = false}

      assert.are.equal(count_named(block.entities, NAMES.pole), #block.poles)
    end)

    it("gives the column of the product belt, which is the output belt of the last column", function()
      local block = furnaces_and_assemblers{product_belt = false}

      assert.are.equal(11, block.product_column) -- the assemblers' output inserters are in column 10
    end)

    it("gives the rows of the tallest column as its height", function()
      local block = furnaces_and_assemblers{product_belt = false}

      assert.are.equal(14, block.height) -- seven furnaces of two rows; the assemblers take six
    end)

    it("does not draw the product belt when whoever uses the block draws it", function()
      local block = furnaces_and_assemblers{product_belt = false}

      assert.are.same({}, belt_rows(block.entities, 11))
      assert.are.same({}, belt_rows(block.entities, 12))
    end)

    it("draws the product belt, wound for two output inserters, when it is the last block", function()
      local block = furnaces_and_assemblers{product_belt = true}

      assert.are.equal(2 * 6 + 1, #belt_rows(block.entities, 11) + #belt_rows(block.entities, 12))
    end)

    it("gives the rows where the output inserters of the last column drop on the product belt", function()
      local block = furnaces_and_assemblers{product_belt = false}

      assert.are.same({first = 0, last = 4}, block.output_rows) -- the assemblers' two output inserters, in rows 0 and 1 and 3 and 4
    end)

    it("gives the rows of the first and the last long-handed inserter of the first column", function()
      local stage = {machine_count = 2, machine = ASSEMBLER, shape = {machine_size = 3, input_inserters = 1, long_inserters = 1, output_inserters = 1}}

      local block = layout.chain_block({stage}, NAMES, {product_belt = false})

      assert.are.same({first = 1, last = 4}, block.long_rows) -- the long-handed inserters are in rows 1 and 4, under the plain ones in rows 0 and 3
    end)

    it("gives no row of a long-handed inserter when the column has none", function()
      local block = furnaces_and_assemblers{product_belt = false}

      assert.is_nil(block.long_rows)
    end)

    it("lists the belt of the first column in the first row of its machines, one down when poles take the row above", function()
      local stage = {machine_count = 1, machine = ASSEMBLER, shape = {machine_size = 3, input_inserters = 3, output_inserters = 1}}

      local block = layout.chain_block({stage}, NAMES, {product_belt = false})

      assert.are.equal(1, block.raw_belts[1].row) -- three input inserters fill the side of the machine, so a row of poles comes first
    end)

    it("lists the first tile of the belt of the first column, with its stage", function()
      local block = furnaces_and_assemblers{product_belt = false}

      assert.are.equal(1, #block.raw_belts)
      assert.are.equal(0, block.raw_belts[1].column)
      assert.are.equal(0, block.raw_belts[1].row) -- where its belt starts, the first row
      assert.are.equal(NAMES.machine, block.raw_belts[1].stage.machine)
    end)
  end)

  describe("the recipe of the machines", function()
    local shape = {machine_size = 3, input_inserters = 1, output_inserters = 1}

    local function names_with(recipe)
      return {machine = "assembling-machine-1", belt = NAMES.belt, inserter = NAMES.inserter, pole = NAMES.pole, recipe = recipe}
    end

    local function recipes_of(entities, machine_name)
      local recipes = {}
      for _, entity in ipairs(entities_named(entities, machine_name)) do
        recipes[#recipes + 1] = entity.recipe or "none"
      end
      return recipes
    end

    it("sets the recipe named in the names on every machine of a column", function()
      local entities = layout.build(3, names_with("iron-gear-wheel"), shape)

      assert.are.same({"iron-gear-wheel", "iron-gear-wheel", "iron-gear-wheel"}, recipes_of(entities, "assembling-machine-1"))
    end)

    it("sets no recipe when none is named, as for a furnace, which picks its own", function()
      local entities = layout.build(2, names_with(nil), shape)

      assert.are.same({"none", "none"}, recipes_of(entities, "assembling-machine-1"))
    end)

    it("sets the recipe of each column of a chain from its own stage", function()
      local entities = layout.build_chain({
        {machine_count = 2, machine = "stone-furnace", shape = {machine_size = 2, input_inserters = 1, output_inserters = 1}},
        {machine_count = 1, machine = "assembling-machine-1", recipe = "iron-gear-wheel", shape = shape},
      }, NAMES)

      assert.are.same({"none", "none"}, recipes_of(entities, "stone-furnace"))
      assert.are.same({"iron-gear-wheel"}, recipes_of(entities, "assembling-machine-1"))
    end)
  end)
end)
