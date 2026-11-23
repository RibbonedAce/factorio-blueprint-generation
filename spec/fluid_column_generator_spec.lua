-- spec/fluid_column_generator_spec.lua
-- A step that takes one made item and a fluid: the column of machines that takes the fluid has the item on one belt (see scripts/rows.lua,
-- `starts_final_column`). Two machines do it: the assembling machine 2, whose fluid connection is in the middle row of the side it faces, fills a
-- barrel with water or crude oil, and the chemical plant, with connections in its top and its bottom row, makes flamethrower ammo from steel
-- plates and crude oil. The barrel is made of a steel plate and the steel plate of iron plates, so both need the steel furnace's fuel on the belt
-- between the two columns of furnaces, which only the design that brings in one belt of each material has (the original design refuses).
---@diagnostic disable: undefined-field  -- luassert's `assert` has fields (`assert.are`, `assert.is_nil`, ...) the editor cannot see
---@diagnostic disable: need-check-nil  -- the assertion before each use fails the test first if the result is nil
---@diagnostic disable: global-in-non-module  -- `_G.prototypes = ...` is how a spec fakes the game's global

local builders = require("spec.support.builders")
local config = require("scripts.config")
local generator = require("scripts.generator")
local grid = require("scripts.grid")
local tracer = require("spec.support.belt_tracer")
local validator = require("spec.support.blueprint_validator")

local a_machine, a_recipe, amount_of, fluid_of, fake_force = builders.a_machine, builders.a_recipe, builders.amount_of, builders.fluid_of, builders.fake_force
local count_named = builders.count_named
local north = defines.direction.north

-- The chemical plant has the connections of the game's: two for what it takes, at the top of the plant as it faces north, and two for what it gives.
local PLANT_BOXES = {
  {production_type = "input", position = {x = -1, y = -1}, direction = north}, {production_type = "input", position = {x = 1, y = -1}, direction = north},
  {production_type = "output", position = {x = -1, y = 1}, direction = defines.direction.south}, {production_type = "output", position = {x = 1, y = 1}, direction = defines.direction.south},
}

local iron = a_recipe{energy = 3.2, ingredients = {amount_of(1, "iron-ore")}, products = {amount_of(1, "iron-plate")}, category = "smelting"}
local steel = a_recipe{energy = 16, ingredients = {amount_of(5, "iron-plate")}, products = {amount_of(1, "steel-plate")}, category = "smelting"}
local barrel = a_recipe{energy = 1, ingredients = {amount_of(1, "steel-plate")}, products = {amount_of(1, "barrel")}}
local function filled(fluid)
  return a_recipe{energy = 0.2, ingredients = {amount_of(1, "barrel"), fluid_of(50, fluid)}, products = {amount_of(1, fluid .. "-barrel")}, category = "crafting-with-fluid"}
end
local ammo = a_recipe{energy = 6, ingredients = {amount_of(5, "steel-plate"), fluid_of(100, "crude-oil")}, products = {amount_of(1, "flamethrower-ammo")}, category = "chemistry"}

local RECIPES = {
  ["iron-plate"] = iron, ["steel-plate"] = steel, ["barrel"] = barrel, ["water-barrel"] = filled("water"), ["crude-oil-barrel"] = filled("crude-oil"),
  ["flamethrower-ammo"] = ammo,
}
for name in pairs(RECIPES) do
  config.recipes[name] = true
end

local function the_game(changes)
  return builders.fake_prototypes(builders.merged({
    furnace_speed = 1,
    items = {"iron-ore", "iron-plate", "steel-plate", "barrel", "water-barrel", "crude-oil-barrel", "flamethrower-ammo", "coal"},
    machines = {
      ["assembling-machine-1"] = a_machine{crafting_speed = 0.5, size = 3},
      ["assembling-machine-2"] = a_machine{crafting_speed = 0.75, size = 3, fluid_input = true},
      ["chemical-plant"] = a_machine{crafting_speed = 1, size = 3, pipe_boxes = PLANT_BOXES},
    },
    recipes = RECIPES,
  }, changes))
end

-- The entities with the machines told apart by name, as the validator and the belt tracer need: the furnaces by the column they stand in (the iron
-- plates, then the steel plates), and the assembling machines 2 by the recipe, since one makes the barrels and one fills them.
---@param entities table[]
---@return table[]
local function named(entities)
  local copies = builders.named_by_column(entities, "stone-furnace", {"iron-furnace", "steel-furnace"}, 2)
  for _, entity in ipairs(copies) do
    if entity.name == "assembling-machine-2" then
      entity.name = entity.recipe == "barrel" and "barrel-maker" or "barrel-filler"
    end
  end
  return copies
end

-- The catalog of the validator: the machines that take a fluid and what they take it for.
local function catalog()
  local entries = builders.a_catalog{}
  entries["barrel-maker"] = {kind = "machine", width = 3, height = 3, needs_power = true}
  entries["barrel-filler"] = {kind = "machine", width = 3, height = 3, needs_power = true, fluid_input = {["water-barrel"] = true, ["crude-oil-barrel"] = true}}
  entries["chemical-plant"] = {kind = "machine", width = 3, height = 3, needs_power = true, fluid_connections = {crude = {{x = 0, y = -1}, {x = 2, y = -1}}}}
  for _, name in ipairs({"iron-furnace", "steel-furnace"}) do
    entries[name] = entries["stone-furnace"]
  end
  return entries
end

-- What the belt tracer finds wrong with the lanes: the furnaces that make the iron plates eat ore that the player brings, the ones that smelt the steel
-- eat the plates and take their coal from the free lane of the belt of the plates, and the machines of the barrels or of the ammo eat what the ones
-- before them make. `belts` names the belts that come in, from the top down, which start at the west edge: the design that brings in one belt of
-- each material.
local function lane_problems(entities, final, belts)
  local options = {
    machines = {
      ["iron-furnace"] = {size = 2, eats = {"iron-ore"}, makes = "iron-plate"}, ["steel-furnace"] = {size = 2, eats = {"iron-plate", "coal"}, makes = "steel-plate"},
      ["barrel-maker"] = {size = 3, eats = {"steel-plate"}, makes = "barrel"},
      ["barrel-filler"] = {size = 3, eats = {"barrel"}, makes = final},
      ["chemical-plant"] = {size = 3, eats = {"steel-plate"}, makes = final},
    },
    raw = {["iron-furnace"] = true}, product = final, underground_reach = 5, raw_lanes = {["iron-furnace"] = {"iron-ore", "coal"}},
    raw_second_lanes = {["iron-furnace"] = {"iron-ore"}}, -- at the most the iron furnaces are built wide, with a second belt of ore on both lanes
  }
  local rows = {}
  for _, belt in ipairs(builders.entities_named(entities, "transport-belt")) do
    local tile = grid.top_left_tile(belt.position)
    if tile.x == 0 then
      rows[#rows + 1] = tile.y
    end
  end
  table.sort(rows)
  options.supplies = {}
  for index, item in ipairs(belts) do
    options.supplies[index] = {x = 0, y = rows[index], item = item}
  end
  return tracer.problems(named(entities), options)
end

local function medium_pole(entries)
  entries[builders.POLES.medium.name] = {kind = "pole", width = 1, height = 1, supply_radius = builders.POLES.medium.supply_distance, wire_reach = builders.POLES.medium.wire_distance}
  return entries
end

describe("a step that takes one made item and a fluid", function()
  describe("a barrel filled with water or crude oil, in an assembling machine 2", function()
    for _, fluid in ipairs({"water", "crude-oil"}) do
      local name = fluid .. "-barrel"

      it("builds the machines of the steps before it and the ones that take the " .. fluid .. "", function()
        _G.prototypes = the_game()

        local result = generator.generate(name, 100, fake_force{})

        local fillers = 0
        for _, machine in ipairs(builders.entities_named(result.entities, "assembling-machine-2")) do
          fillers = fillers + (machine.recipe == name and 1 or 0)
        end
        assert.is_true(fillers >= 1 and count_named(result.entities, "stone-furnace") > 0)
        assert.are.equal(1, count_named(result.entities, "pump"))
      end)

      it("passes the validator and the belt tracer for " .. name .. "", function()
        _G.prototypes = the_game()
        local most = generator.max_rate_message(name, fake_force{})

        for _, rate in ipairs({1, 100, tonumber(most[2])}) do
          local result = generator.generate(name, rate, fake_force{})

          assert.are.same({}, validator.validate(named(result.entities), medium_pole(catalog())))
          assert.are.same({}, lane_problems(result.entities, name, builders.belts_named(result.message)))
        end
      end)
    end

    it("says what it takes", function()
      _G.prototypes = the_game()

      local result = generator.generate("water-barrel", 100, fake_force{})

      local names = {}
      for _, raw in ipairs(result.message[4]) do
        if type(raw) == "table" then
          names[#names + 1] = (raw[3] or {})[1]
        end
      end
      assert.are.same({"item-name.iron-ore", "item-name.coal", "fluid-name.water"}, names)
    end)

    it("refuses the original design of the belts", function()
      _G.prototypes = the_game()

      local result, error_message = generator.generate("water-barrel", 100)

      assert.are.same({nil, {"blueprint-generation.error-fuel-needs-inputs", {"item-name.steel-plate"}}}, {result, error_message})
    end)
  end)

  describe("flamethrower ammo, in chemical plants", function()
    it("builds chemical plants that face west", function()
      _G.prototypes = the_game()

      local result = generator.generate("flamethrower-ammo", 10, fake_force{})

      local plants = builders.entities_named(result.entities, "chemical-plant")
      assert.is_true(#plants >= 1)
      for _, plant in ipairs(plants) do
        assert.are.equal(defines.direction.west, plant.direction)
      end
    end)

    it("takes the steel in with one inserter for each plant", function()
      _G.prototypes = the_game()

      local result = generator.generate("flamethrower-ammo", 10, fake_force{})

      local plants = builders.entities_named(result.entities, "chemical-plant")
      local inserters_at_input_side = 0
      for _, inserter in ipairs(builders.entities_named(result.entities, "inserter")) do
        local tile = grid.top_left_tile(inserter.position)
        local plant_tile = grid.top_left_tile(plants[1].position, 3, 3)
        inserters_at_input_side = inserters_at_input_side + (tile.x == plant_tile.x - 1 and 1 or 0)
      end
      assert.are.equal(#plants, inserters_at_input_side)
    end)

    it("passes the validator and the belt tracer", function()
      _G.prototypes = the_game()
      local most = generator.max_rate_message("flamethrower-ammo", fake_force{})

      for _, rate in ipairs({1, 10, tonumber(most[2])}) do
        local result = generator.generate("flamethrower-ammo", rate, fake_force{})

        assert.are.same({}, validator.validate(named(result.entities), medium_pole(catalog())))
        assert.are.same({}, lane_problems(result.entities, "flamethrower-ammo", builders.belts_named(result.message)))
      end
    end)

    it("takes the crude oil by pipe", function()
      _G.prototypes = the_game()

      local result = generator.generate("flamethrower-ammo", 10, fake_force{})

      local oil
      for _, raw in ipairs(result.message[4]) do
        oil = type(raw) == "table" and raw[3] and raw[3][1] == "fluid-name.crude-oil" and raw[2] or oil
      end
      assert.is_not_nil(oil)
    end)
  end)
end)
