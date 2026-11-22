-- spec/item_fluid_chain_spec.lua
-- The blueprint of a recipe that takes items and a fluid, that puts the belts part (a block of furnaces), the plants part and the final plants
-- into one (see scripts/item_fluid_chain.lua). Positions are TILES: the top-left tile an entity covers, with y growing down (see
-- scripts/grid.lua). The plants part is drawn for 2 refineries of 5 x 5 and 3 plants of 3 x 3 that take two fluids (see
-- spec/fluid_plant_spec.lua): their belt is the column 14 and it ends in the row 8, and the refineries end in the row 9. The belts part is a
-- stand-in: a furnace of 2 x 2 with an inserter on each side and a belt on each, the belt of raw items first (the column 0), the product belt
-- the column 5 (rows 0 to 3). The final plants are drawn for 2 plants of 3 x 3 (see spec/item_fluid_plants_spec.lua).
---@diagnostic disable: undefined-field  -- luassert's `assert` has fields (`assert.are`, `assert.is_nil`, ...) the editor cannot see

local builders = require("spec.support.builders")
local grid = require("scripts.grid")
local item_fluid_chain = require("scripts.item_fluid_chain")
local validator = require("spec.support.blueprint_validator")

local NAMES = builders.NAMES
local range = builders.range
local east, south, west = defines.direction.east, defines.direction.south, defines.direction.west

local function refinery_boxes()
  return {
    {production_type = "input", tiles = {{x = 1, y = 5}}}, {production_type = "input", tiles = {{x = 3, y = 5}}},
    {production_type = "output", tiles = {{x = 0, y = -1}}}, {production_type = "output", tiles = {{x = 2, y = -1}}}, {production_type = "output", tiles = {{x = 4, y = -1}}},
  }
end

local function plant_boxes()
  return {
    {production_type = "input", tiles = {{x = 0, y = -1}}}, {production_type = "input", tiles = {{x = 2, y = -1}}},
    {production_type = "output", tiles = {{x = 0, y = 3}}}, {production_type = "output", tiles = {{x = 2, y = 3}}},
  }
end

-- What `fluid_plant.build_block` is asked for: `makers` refineries and `plants` plants of the plants part, which take petroleum gas and water.
local function sulfur_request(makers, plants)
  return {
    makers = {
      machine = "oil-refinery", recipe = "basic-oil-processing", size = 5, count = makers, boxes = refinery_boxes(),
      rows = {inputs = 5, outputs = -1}, pipe = NAMES.pipe, pole = NAMES.pole, pole_supply_distance = 2.5, pole_wire_distance = 7.5,
    },
    plants = {
      machine = "sulfur-plant", recipe = "sulfur", size = 3, count = plants, boxes = plant_boxes(), rows = {inputs = -1, outputs = 3},
      fluid_boxes = {source = 1, supplied = 2},
    },
    inserter = NAMES.inserter, belt = NAMES.belt, pipe_to_ground = NAMES.pipe_to_ground, underground_reach = 10,
  }
end

-- What `item_fluid_plants.build` is asked for `count` final plants, the ones that make the acid.
local function final_request(count)
  return {
    plants = {machine = "acid-plant", recipe = "sulfuric-acid", size = 3, count = count, boxes = plant_boxes(), rows = {inputs = -1, outputs = 3}},
    inserter = NAMES.inserter, belt = NAMES.belt, pipe = NAMES.pipe, pipe_to_ground = NAMES.pipe_to_ground, pole = NAMES.pole,
    pole_supply_distance = 2.5, pole_wire_distance = 7.5, underground_reach = 10,
  }
end

-- The tiles of the stand-in block of furnaces, moved `x` columns east: a belt of raw items (the column 0 of the block, `rows` rows from the
-- top), an inserter that takes from it into the furnace (2, 0), an inserter that takes from the furnace onto the product belt (the column 5,
-- the same rows), a pole.
local function furnace_block(x, raw, rows)
  rows = rows or 4
  local list = {}
  local function add(entity)
    entity.entity_number = #list + 1
    list[#list + 1] = entity
    return entity
  end
  for row = 0, rows - 1 do
    add({name = NAMES.belt, position = grid.position(x, row), direction = south})
    add({name = NAMES.belt, position = grid.position(x + 5, row), direction = south})
  end
  add({name = NAMES.inserter, position = grid.position(x + 1, 0), direction = west})
  add({name = "stone-furnace", position = grid.position(x + 2, 0, 2, 2)})
  add({name = NAMES.inserter, position = grid.position(x + 4, 0), direction = west})
  local pole = add({name = NAMES.pole, position = grid.position(x + 3, 2)})
  return {entities = list, poles = {pole}, product = {column = x + 5, last_row = rows - 1}, raw = raw}
end

-- The block with its belt of raw items coming in from the north at its top.
local function iron_from_the_north(rows)
  return furnace_block(0, {{key = "iron", x = 0, y = 0, direction = south}}, rows)
end

-- The block with two belts of raw items that come in from the west and run east into it: the block is moved 3 columns east, and a belt runs
-- east along the rows 0 and 2 from the west edge of its frame to the belt of raw items, which stands in the column 3.
local function iron_from_the_west()
  local block = furnace_block(3, {{key = "ore", x = 0, y = 0, direction = east}, {key = "coal", x = 0, y = 2, direction = east}})
  for _, row in ipairs({0, 2}) do
    for column = 0, 2 do
      block.entities[#block.entities + 1] = {
        name = NAMES.belt, position = grid.position(column, row), direction = east, entity_number = #block.entities + 1,
      }
    end
  end
  block.product = {column = 8, last_row = 3}
  return block
end

local SIZES = {["oil-refinery"] = 5, ["sulfur-plant"] = 3, ["acid-plant"] = 3, ["stone-furnace"] = 2}

-- What `item_fluid_chain.build` is asked for, with the block of furnaces (the belts part) given. The fluid the two kinds of plants take from
-- outside, the water, is the same unless the test says it is not.
local function request(belts_part, final_count, shared_fluid)
  return {
    plants_part = sulfur_request(2, 3), belts_part = belts_part, final_plants = final_request(final_count or 2), shared_fluid = shared_fluid ~= false,
    size_of = function(entity)
      local size = SIZES[entity.name] or 1
      return size, size
    end,
  }
end

-- The entity that stands in the tile, or nil when none does.
local function entity_at(entities, tile_x, tile_y)
  for _, entity in ipairs(entities) do
    local tile = grid.top_left_tile(entity.position, SIZES[entity.name] or 1, SIZES[entity.name] or 1)
    if tile.x == tile_x and tile.y == tile_y then
      return entity
    end
  end
  return nil
end

-- What stands in the tile, by name and direction ("belt south"), or nil when nothing does.
local function at(entities, tile_x, tile_y)
  local entity = entity_at(entities, tile_x, tile_y)
  return entity and (entity.name .. (entity.direction and (" " .. entity.direction) or "")) or nil
end

-- The name of what stands in the tile, or nil.
local function name_at(entities, tile_x, tile_y)
  local entity = entity_at(entities, tile_x, tile_y)
  return entity and entity.name
end

-- The columns of the entities with the name in a row, sorted.
local function columns_in_row(entities, name, row)
  local columns = {}
  for _, entity in ipairs(entities) do
    local tile = grid.top_left_tile(entity.position)
    if entity.name == name and tile.y == row then
      columns[#columns + 1] = tile.x
    end
  end
  table.sort(columns)
  return columns
end

-- The catalog of the validator: the refineries that give petroleum gas, the plants of the plants part that take it and water, the final
-- plants that take water and give the acid, and the furnaces. The water of the final plants is the network of the water of the
-- others when it is the same fluid, and has a network of its own when it is not.
local function catalog(shared_fluid)
  local entries = builders.a_catalog{}
  entries["oil-refinery"] = {
    kind = "machine", width = 5, height = 5, needs_power = true, networks = {input = "crude", output = "gas"},
    fluid_connections = {input = {{x = 1, y = 5}, {x = 3, y = 5}}, output = {{x = 0, y = -1}, {x = 2, y = -1}, {x = 4, y = -1}}},
  }
  entries["sulfur-plant"] = {
    kind = "machine", width = 3, height = 3, needs_power = true, fluid_connections = {gas = {{x = 0, y = -1}}, water = {{x = 2, y = -1}}},
  }
  local water = shared_fluid == false and "final_fluid" or "water"
  entries["acid-plant"] = {
    kind = "machine", width = 3, height = 3, needs_power = true,
    fluid_connections = {[water] = {{x = 0, y = -1}, {x = 2, y = -1}}, acid = {{x = 0, y = 3}, {x = 2, y = 3}}},
  }
  entries["stone-furnace"] = {kind = "machine", width = 2, height = 2}
  return entries
end

describe("item_fluid_chain", function()
  describe("build", function()
    it("puts the belts part at the west, the plants part east of it and the final plants east of both", function()
      local chain = item_fluid_chain.build(request(iron_from_the_north()))

      -- the furnaces are in the columns 0 to 5, the plants part starts 2 columns after (the column 7), its belt is the column 14 of its block,
      -- so the column 21, and the final plants start 2 columns after that; their belt is their column 2
      assert.are.same({
        belts_x = 0, belts_product = 5, plants_x = 7, plants_product = 21, final_x = 23, trunk = 23, belt_b = 25, arc_row = 10,
      }, chain.places)
      assert.are.same({"stone-furnace", "oil-refinery", "sulfur-plant", "acid-plant"}, {
        name_at(chain.entities, 2, 0), name_at(chain.entities, 9, 0), name_at(chain.entities, 17, 0), name_at(chain.entities, 27, 0),
      })
    end)

    it("leaves a free column between a block and the next", function()
      local chain = item_fluid_chain.build(request(iron_from_the_north()))

      -- the product belt of the furnaces is the column 5 and the pole column of the next block starts in the column 7; the belt of the plants part
      -- is the column 21 and the trunk of the final plants the column 23
      assert.are.same({nil, nil, nil}, {name_at(chain.entities, 6, 0), name_at(chain.entities, 6, 5), name_at(chain.entities, 22, 0)})
    end)

    it("puts the arc under the refineries of the plants part, which end lower than its plants", function()
      local chain = item_fluid_chain.build(request(iron_from_the_north()))

      assert.are.equal(10, chain.places.arc_row) -- the refineries end in the row 9
    end)

    it("puts the arc under a belts part that is taller than the rest", function()
      local chain = item_fluid_chain.build(request(iron_from_the_north(14)))

      assert.are.equal(14, chain.places.arc_row)
    end)

    it("puts the arc under the final plants when they are the tallest", function()
      local chain = item_fluid_chain.build(request(iron_from_the_north(), 5))

      assert.are.equal(15, chain.places.arc_row) -- 5 plants end in the row 14
    end)

    it("takes the belt of the belts part down its column to the row of the arc and through the lane gadget under it", function()
      local chain = item_fluid_chain.build(request(iron_from_the_north()))

      assert.are.same({
        "transport-belt south", "transport-belt south", "transport-belt east", "transport-belt east", "transport-belt north",
      }, {at(chain.entities, 5, 4), at(chain.entities, 5, 10), at(chain.entities, 5, 11), at(chain.entities, 6, 11), at(chain.entities, 7, 11)})
    end)

    it("takes the gadget into the side of the arc, which has a stub behind it so that it stays straight", function()
      local chain = item_fluid_chain.build(request(iron_from_the_north()))

      assert.are.same({"transport-belt east", "transport-belt east", nil, nil, nil}, {
        at(chain.entities, 6, 10), at(chain.entities, 7, 10), at(chain.entities, 5, 12), at(chain.entities, 6, 12), at(chain.entities, 7, 12),
      })
    end)

    it("runs the arc east along its row to the tile before the belt b", function()
      local chain = item_fluid_chain.build(request(iron_from_the_north()))

      local columns = columns_in_row(chain.entities, NAMES.belt, 10)
      assert.are.same(range(5, 25), columns)
      assert.are.same({"transport-belt east", "transport-belt east", "transport-belt east"}, {at(chain.entities, 8, 10), at(chain.entities, 21, 10), at(chain.entities, 24, 10)})
    end)

    it("turns the arc north into the first tile of the belt b, which runs north along the final plants", function()
      local chain = item_fluid_chain.build(request(iron_from_the_north()))

      assert.are.same({"transport-belt north", "transport-belt north", "transport-belt north", "transport-belt north", nil}, {
        at(chain.entities, 25, 10), at(chain.entities, 25, 6), at(chain.entities, 25, 5), at(chain.entities, 25, 0), at(chain.entities, 25, 11),
      })
    end)

    it("takes the belt of the plants part down the east side of its plants to the row above the arc, where its last tile points into the side of the arc", function()
      local chain = item_fluid_chain.build(request(iron_from_the_north()))

      -- the belt of the plants ends in the row 8: the column goes on in the row 9, and the arc is the row 10
      assert.are.same({"transport-belt south", "transport-belt south", "transport-belt east"}, {at(chain.entities, 21, 8), at(chain.entities, 21, 9), at(chain.entities, 21, 10)})
    end)

    it("takes the belt of the plants part further down when the belts part is taller", function()
      local chain = item_fluid_chain.build(request(iron_from_the_north(14)))

      assert.are.same({"transport-belt south", "transport-belt south", "transport-belt east"}, {at(chain.entities, 21, 8), at(chain.entities, 21, 13), at(chain.entities, 21, 14)})
    end)

    it("gives the entries at the west edge, the one that starts furthest east on the top row, with the water of both plants as one", function()
      local chain = item_fluid_chain.build(request(iron_from_the_north()))

      assert.are.same({{key = "iron", x = 0, y = -1}, {key = "input", x = 0, y = -4}, {key = "supplied", x = 0, y = -7}}, chain.inlets)
    end)

    it("brings the water to both plants by one pipe along the top, down to the pipe of the plants part and the trunk of the final plants", function()
      local chain = item_fluid_chain.build(request(iron_from_the_north()))

      -- the row -7 from the edge to the column 23, and the columns 16 and 23 down from it to the rows where the plants' pipes start
      assert.are.same(range(0, 23), columns_in_row(chain.entities, NAMES.pipe, -7))
      assert.are.same({"pipe", "pipe", "pipe", "pipe", nil}, {
        at(chain.entities, 16, -6), at(chain.entities, 16, -1), at(chain.entities, 23, -6), at(chain.entities, 23, -1), at(chain.entities, 12, -6),
      })
      assert.are.same(range(-7, 5), builders.rows_in_column(chain.entities, NAMES.pipe, 23))
    end)

    it("takes the crude oil to its own row, west of the water, so that nothing crosses", function()
      local chain = item_fluid_chain.build(request(iron_from_the_north()))

      -- the crude oil pipe of the refineries is the column 8; its row is -4, and it reaches no further east than the column 8: the pipes
      -- further east in that row are the two legs of the water, which go down through it at the columns 16 and 23
      assert.are.same({range(0, 8), {16, 23}}, {{table.unpack(columns_in_row(chain.entities, NAMES.pipe, -4), 1, 9)}, {table.unpack(columns_in_row(chain.entities, NAMES.pipe, -4), 10)}})
    end)

    it("gives the fluid of the final plants an entry of its own when it is not the one the plants part takes", function()
      local chain = item_fluid_chain.build(request(iron_from_the_north(), 2, false))

      assert.are.same({
        {key = "iron", x = 0, y = -1}, {key = "input", x = 0, y = -4}, {key = "supplied", x = 0, y = -7}, {key = "final_fluid", x = 0, y = -10},
      }, chain.inlets)
      -- the water of the plants part in the row -7 from the edge to the column 16, with the pipe of the other fluid going down through it at
      -- the column 23; the fluid of the final plants in the row -10 from the edge to the column 23
      local water_row = columns_in_row(chain.entities, NAMES.pipe, -7)
      assert.are.same({range(0, 16), {23}}, {{table.unpack(water_row, 1, 17)}, {table.unpack(water_row, 18)}})
      assert.are.same(range(0, 23), columns_in_row(chain.entities, NAMES.pipe, -10))
    end)

    it("takes a belt of raw items that runs south at the top of the block of the belts part straight down to it", function()
      local chain = item_fluid_chain.build(request(iron_from_the_north()))

      assert.are.same({"transport-belt south", "transport-belt south"}, {at(chain.entities, 0, -1), at(chain.entities, 0, 3)})
    end)

    it("takes a belt that runs south at the first tile of the block, and is not in its first column, down the column it is in", function()
      local block = iron_from_the_north()
      block.raw = {{key = "iron", x = 2, y = 0, direction = south}}

      local chain = item_fluid_chain.build(request(block))

      assert.are.same({"transport-belt south", "transport-belt east", {key = "iron", x = 0, y = -1}}, {at(chain.entities, 2, -1), at(chain.entities, 1, -1), chain.inlets[1]})
    end)

    it("refuses a belt that runs east into the block but does not start at its west edge", function()
      local block = iron_from_the_west()
      block.raw[1].x = 1

      local build = function() item_fluid_chain.build(request(block)) end

      assert.has_error(build, "item_fluid_chain: a belt of raw items comes in at the west edge of the block of the belts part, running east, or at its top, running south")
    end)

    it("takes belts that run east into the block down the columns before it, and east along the rows of the block, the upper one nearest the block", function()
      local chain = item_fluid_chain.build(request(iron_from_the_west()))

      -- the block is moved to the column 2, so that the two belts come down the columns 1 and 0: the ore, the upper, down the column 1
      assert.are.equal(2, chain.places.belts_x)
      assert.are.same({
        "transport-belt south", "transport-belt south", "transport-belt east", "transport-belt east", "transport-belt east", "transport-belt east",
      }, {at(chain.entities, 1, -1), at(chain.entities, 0, 1), at(chain.entities, 1, 0), at(chain.entities, 0, 2), at(chain.entities, 1, 2), at(chain.entities, 2, 2)})
      assert.are.same({
        {key = "coal", x = 0, y = -1}, {key = "ore", x = 0, y = -4}, {key = "input", x = 0, y = -7}, {key = "supplied", x = 0, y = -10},
      }, chain.inlets)
    end)

    describe("with a belts part that is only the belt of a raw item, which has no machines and no poles", function()
      local function raw_block()
        return {
          entities = {{entity_number = 1, name = NAMES.belt, position = grid.position(0, 0), direction = south}}, poles = {},
          product = {column = 0, last_row = 0}, raw = {{key = "coal", x = 0, y = 0, direction = south}},
        }
      end

      it("brings the belt in at the top left, down its column to the arc, through the gadget and along the arc to the belt b", function()
        local chain = item_fluid_chain.build(request(raw_block()))

        -- the block is one column wide, so the plants part starts in the column 2 and the final plants in the column 18
        assert.are.equal(20, chain.places.belt_b)
        assert.are.same({"transport-belt south", "transport-belt south", "transport-belt east", "transport-belt north", "transport-belt north"}, {
          at(chain.entities, 0, -1), at(chain.entities, 0, 10), at(chain.entities, 1, 11), at(chain.entities, 2, 11), at(chain.entities, 20, 10),
        })
        assert.are.same({key = "coal", x = 0, y = -1}, chain.inlets[1])
      end)

      it("passes the validator: the poles of the other two blocks are one network", function()
        local chain = item_fluid_chain.build(request(raw_block()))

        assert.are.same({}, validator.validate(chain.entities, catalog()))
      end)
    end)

    it("numbers the entities from 1 with no gap", function()
      local chain = item_fluid_chain.build(request(iron_from_the_north()))

      assert.has_consecutive_numbers(chain.entities)
    end)

    for _, case in ipairs({{1, "north", true}, {2, "north", true}, {5, "north", true}, {3, "west", true}, {2, "north", false}, {3, "west", false}}) do
      it(string.format("passes the validator for %d final plants, with the belt of raw items from the %s%s: powered, one network of poles, the pipes meet", case[1], case[2], case[3] and "" or ", the water not shared"), function()
        local chain = item_fluid_chain.build(request(case[2] == "north" and iron_from_the_north() or iron_from_the_west(), case[1], case[3]))

        local problems = validator.validate(chain.entities, catalog(case[3]))

        assert.are.same({}, problems)
      end)
    end
  end)
end)
