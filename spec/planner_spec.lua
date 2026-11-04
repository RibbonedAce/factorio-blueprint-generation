-- spec/planner_spec.lua
-- How many machines does a rate need? The arithmetic behind the numbers is
-- written next to the test that relies on it: one furnace with speed 1 and a
-- 3.2 s recipe crafts 60 / 3.2 = 18.75 times a minute.
--
-- `planner.plan` takes one table of named values, so each test says exactly which
-- numbers it depends on. A furnace burns `fuel = "coal"`, which takes one of the
-- two lanes of the input belt; a machine with no `fuel` (an electric one) leaves
-- both lanes to its ingredients.
---@diagnostic disable: undefined-field  -- luassert's `assert` has fields (`assert.are`, `assert.is_nil`, ...) the editor cannot see
---@diagnostic disable: need-check-nil  -- the assertion before each use fails the test first if the plan is nil

local planner = require("scripts.planner")
local builders = require("spec.support.builders")

local amount_of = builders.amount_of

describe("planner", function()
  describe("plan, for a furnace (one ingredient, with fuel on the other lane)", function()
    it("needs one furnace for exactly one furnace's output, without float noise adding another", function()
      local recipe = {energy = 3.2, ingredients = {amount_of(1, "iron-ore")}, products = {amount_of(1, "iron-plate")}}
      local plates_per_minute_of_one_furnace = 18.75 -- 60 s / 3.2 s

      local plan = planner.plan{
        product = "iron-plate", rate_per_minute = plates_per_minute_of_one_furnace, recipe = recipe,
        machine_speed = 1, lane_items_per_minute = 450, fuel = "coal",
      }

      assert.are.equal(1, plan.machines)
      assert.near(18.75, plan.output_per_minute, 1e-6)
    end)

    it("needs two furnaces for a rate just above one furnace's output", function()
      local recipe = {energy = 3.2, ingredients = {amount_of(1, "iron-ore")}, products = {amount_of(1, "iron-plate")}}

      local plan = planner.plan{
        product = "iron-plate", rate_per_minute = 18.76, recipe = recipe,
        machine_speed = 1, lane_items_per_minute = 450, fuel = "coal",
      }

      assert.are.equal(2, plan.machines)
    end)

    it("still needs one furnace for a tiny rate", function()
      local recipe = {energy = 3.2, ingredients = {amount_of(1, "iron-ore")}, products = {amount_of(1, "iron-plate")}}

      local plan = planner.plan{
        product = "iron-plate", rate_per_minute = 0.001, recipe = recipe,
        machine_speed = 1, lane_items_per_minute = 450, fuel = "coal",
      }

      assert.are.equal(1, plan.machines)
    end)

    it("still needs one furnace, not none, for a rate too small to notice", function()
      local recipe = {energy = 3.2, ingredients = {amount_of(1, "iron-ore")}, products = {amount_of(1, "iron-plate")}}
      local almost_nothing = 1e-12 -- less than the float guard, so the division rounds to zero

      local plan = planner.plan{
        product = "iron-plate", rate_per_minute = almost_nothing, recipe = recipe,
        machine_speed = 1, lane_items_per_minute = 450, fuel = "coal",
      }

      assert.are.equal(1, plan.machines)
    end)

    it("needs four furnaces for 60 plates a minute", function()
      local recipe = {energy = 3.2, ingredients = {amount_of(1, "iron-ore")}, products = {amount_of(1, "iron-plate")}}

      local plan = planner.plan{
        product = "iron-plate", rate_per_minute = 60, recipe = recipe,
        machine_speed = 1, lane_items_per_minute = 450, fuel = "coal",
      }

      assert.are.equal(4, plan.machines) -- 60 / 18.75 = 3.2, rounded up
    end)

    it("makes 75 plates a minute with four furnaces", function()
      local recipe = {energy = 3.2, ingredients = {amount_of(1, "iron-ore")}, products = {amount_of(1, "iron-plate")}}

      local plan = planner.plan{
        product = "iron-plate", rate_per_minute = 60, recipe = recipe,
        machine_speed = 1, lane_items_per_minute = 450, fuel = "coal",
      }

      assert.near(75, plan.output_per_minute, 1e-6) -- 4 x 18.75
    end)

    it("makes four furnaces eat 75 ore a minute, with the ore as the input", function()
      local recipe = {energy = 3.2, ingredients = {amount_of(1, "iron-ore")}, products = {amount_of(1, "iron-plate")}}

      local plan = planner.plan{
        product = "iron-plate", rate_per_minute = 60, recipe = recipe,
        machine_speed = 1, lane_items_per_minute = 450, fuel = "coal",
      }

      assert.are.equal(1, #plan.inputs)
      assert.are.equal("iron-ore", plan.inputs[1].name)
      assert.near(75, plan.inputs[1].per_minute, 1e-6) -- one ore per plate
    end)

    it("draws twice the ore for a recipe that eats two ore per craft", function()
      local recipe = {energy = 3.2, ingredients = {amount_of(2, "iron-ore")}, products = {amount_of(1, "iron-plate")}}

      local plan = planner.plan{
        product = "iron-plate", rate_per_minute = 60, recipe = recipe,
        machine_speed = 1, lane_items_per_minute = 450, fuel = "coal",
      }

      assert.are.equal(4, plan.machines)
      assert.near(150, plan.inputs[1].per_minute, 1e-6) -- 4 furnaces x 18.75 crafts x 2 ore
    end)

    it("makes twice the output per furnace for a recipe that makes two items per craft", function()
      local recipe = {energy = 3.2, ingredients = {amount_of(1, "iron-ore")}, products = {amount_of(2, "iron-plate")}}

      local plan = planner.plan{
        product = "iron-plate", rate_per_minute = 75, recipe = recipe,
        machine_speed = 1, lane_items_per_minute = 450, fuel = "coal",
      }

      assert.are.equal(2, plan.machines) -- 75 / (18.75 crafts x 2 items) = 2
      assert.near(75, plan.output_per_minute, 1e-6)
      assert.near(37.5, plan.inputs[1].per_minute, 1e-6) -- 2 furnaces x 18.75 crafts x 1 ore
    end)

    it("is limited by the ingredient lane when that is the one that runs out first", function()
      local recipe = {energy = 3.2, ingredients = {amount_of(2, "iron-ore")}, products = {amount_of(1, "iron-plate")}}
      -- One furnace eats 37.5 ore a minute, so a 450 lane feeds 12 furnaces (225 plates),
      -- even though the plates alone would fit on the output lane up to 450.

      local plan, reason, max_rate = planner.plan{
        product = "iron-plate", rate_per_minute = 240, recipe = recipe,
        machine_speed = 1, lane_items_per_minute = 450, fuel = "coal",
      }

      assert.is_nil(plan)
      assert.are.equal("rate-too-high", reason)
      assert.near(225, max_rate, 1e-6) -- 12 furnaces x 18.75
    end)

    it("needs half the machines for a machine twice as fast", function()
      local recipe = {energy = 3.2, ingredients = {amount_of(1, "iron-ore")}, products = {amount_of(1, "iron-plate")}}
      local double_speed = 2 -- 37.5 plates a minute each

      local plan = planner.plan{
        product = "iron-plate", rate_per_minute = 60, recipe = recipe,
        machine_speed = double_speed, lane_items_per_minute = 450, fuel = "coal",
      }

      assert.are.equal(2, plan.machines) -- 60 / 37.5 = 1.6, rounded up
    end)

    it("does not let float noise in the division add an extra machine", function()
      -- Eleven machines of a 1.1 s recipe make exactly 600 a minute, but 600 / (60 / 1.1)
      -- comes out as 11.000000000000002 in floating point and would round up to 12.
      local recipe = {energy = 1.1, ingredients = {amount_of(1, "iron-ore")}, products = {amount_of(1, "iron-plate")}}
      local wide_lane = 10000

      local plan = planner.plan{
        product = "iron-plate", rate_per_minute = 600, recipe = recipe,
        machine_speed = 1, lane_items_per_minute = wide_lane, fuel = "coal",
      }

      assert.are.equal(11, plan.machines)
    end)

    it("does not let float noise in the ingredient lane's division take a machine away from an exact fit", function()
      -- A machine of speed 0.5 on a 0.35 s recipe crafts 85.714... times a minute and eats twice that
      -- in ore. Seven of them eat exactly 1200, but 1200 / 171.428... comes out as 6.999999999999999.
      local recipe = {energy = 0.35, ingredients = {amount_of(2, "iron-ore")}, products = {amount_of(1, "iron-plate")}}

      local plan = planner.plan{
        product = "iron-plate", rate_per_minute = 600, recipe = recipe,
        machine_speed = 0.5, lane_items_per_minute = 1200, fuel = "coal",
      }

      assert.are.equal(7, plan.machines) -- 600 plates / 85.714... a machine
    end)

    it("fills one belt lane exactly with 24 furnaces at 450 plates a minute", function()
      local recipe = {energy = 3.2, ingredients = {amount_of(1, "iron-ore")}, products = {amount_of(1, "iron-plate")}}

      local plan = planner.plan{
        product = "iron-plate", rate_per_minute = 450, recipe = recipe,
        machine_speed = 1, lane_items_per_minute = 450, fuel = "coal",
      }

      assert.are.equal(24, plan.machines) -- 450 / 18.75
    end)

    it("refuses more than one belt lane carries, naming the most that fits", function()
      local recipe = {energy = 3.2, ingredients = {amount_of(1, "iron-ore")}, products = {amount_of(1, "iron-plate")}}

      local plan, reason, max_rate = planner.plan{
        product = "iron-plate", rate_per_minute = 451, recipe = recipe,
        machine_speed = 1, lane_items_per_minute = 450, fuel = "coal",
      }

      assert.is_nil(plan)
      assert.are.equal("rate-too-high", reason)
      assert.near(450, max_rate, 1e-6) -- 24 furnaces x 18.75
    end)

    it("puts the ingredient on one lane of the input belt and the fuel on the other", function()
      local recipe = {energy = 3.2, ingredients = {amount_of(1, "iron-ore")}, products = {amount_of(1, "iron-plate")}}

      local plan = planner.plan{
        product = "iron-plate", rate_per_minute = 10, recipe = recipe,
        machine_speed = 1, lane_items_per_minute = 450, fuel = "coal",
      }

      assert.are.same({"iron-ore", "coal"}, plan.lanes)
    end)
  end)

  describe("plan, for a machine with no fuel and one ingredient (both lanes carry it)", function()
    it("puts the ingredient on both lanes of the input belt", function()
      local recipe = {energy = 0.5, ingredients = {amount_of(2, "iron-plate")}, products = {amount_of(1, "iron-gear-wheel")}}

      local plan = planner.plan{
        product = "iron-gear-wheel", rate_per_minute = 10, recipe = recipe,
        machine_speed = 0.5, lane_items_per_minute = 450,
      }

      assert.are.same({"iron-plate", "iron-plate"}, plan.lanes)
    end)

    it("fits twice the machines on the input belt: 16 machines eating 56.25 ore each fill two 450 lanes", function()
      local recipe = {energy = 3.2, ingredients = {amount_of(3, "iron-ore")}, products = {amount_of(1, "iron-plate")}}

      local plan = planner.plan{
        product = "iron-plate", rate_per_minute = 300, recipe = recipe,
        machine_speed = 1, lane_items_per_minute = 450,
      }

      assert.are.equal(16, plan.machines) -- 300 / 18.75; 900 / (18.75 crafts x 3 ore) = 16
    end)

    it("refuses 301 a minute, naming 300, when two lanes of input are full", function()
      local recipe = {energy = 3.2, ingredients = {amount_of(3, "iron-ore")}, products = {amount_of(1, "iron-plate")}}

      local plan, reason, max_rate = planner.plan{
        product = "iron-plate", rate_per_minute = 301, recipe = recipe,
        machine_speed = 1, lane_items_per_minute = 450,
      }

      assert.is_nil(plan)
      assert.are.equal("rate-too-high", reason)
      assert.near(300, max_rate, 1e-6) -- 16 machines x 18.75
    end)

    it("gives the same ingredient only one lane when a fuel takes the other, so 160 a minute is refused", function()
      local recipe = {energy = 3.2, ingredients = {amount_of(3, "iron-ore")}, products = {amount_of(1, "iron-plate")}}

      local plan, reason, max_rate = planner.plan{
        product = "iron-plate", rate_per_minute = 160, recipe = recipe,
        machine_speed = 1, lane_items_per_minute = 450, fuel = "coal",
      }

      assert.is_nil(plan)
      assert.are.equal("rate-too-high", reason)
      assert.near(150, max_rate, 1e-6) -- 450 / 56.25 = 8 machines x 18.75
    end)

    it("does not let float noise in the output lane's division take a machine away from an exact fit", function()
      -- Seven machines make exactly 600 a minute, the whole lane, but 600 / 85.714... comes out as 6.999999999999999.
      local recipe = {energy = 0.35, ingredients = {amount_of(1, "iron-plate")}, products = {amount_of(1, "iron-gear-wheel")}}

      local plan = planner.plan{
        product = "iron-gear-wheel", rate_per_minute = 600, recipe = recipe,
        machine_speed = 0.5, lane_items_per_minute = 600,
      }

      assert.are.equal(7, plan.machines) -- 600 gears / 85.714... a machine
    end)

    it("keeps the product on one lane, whatever the input has: 3 machines of 120 a minute fill the output lane", function()
      local recipe = {energy = 1, ingredients = {amount_of(1, "iron-ore")}, products = {amount_of(2, "iron-plate")}}

      local plan, reason, max_rate = planner.plan{
        product = "iron-plate", rate_per_minute = 400, recipe = recipe,
        machine_speed = 1, lane_items_per_minute = 450,
      }

      assert.is_nil(plan)
      assert.are.equal("rate-too-high", reason)
      assert.near(360, max_rate, 1e-6) -- each machine makes 60 crafts x 2 = 120; 450 / 120 = 3.75, so 3 machines
    end)
  end)

  describe("plan, for a machine with two ingredients (one lane each)", function()
    it("puts one ingredient on each lane of the input belt", function()
      local recipe = {
        energy = 0.5,
        ingredients = {amount_of(1, "iron-plate"), amount_of(3, "copper-cable")},
        products = {amount_of(1, "electronic-circuit")},
      }

      local plan = planner.plan{
        product = "electronic-circuit", rate_per_minute = 60, recipe = recipe,
        machine_speed = 0.5, lane_items_per_minute = 450,
      }

      assert.are.same({"iron-plate", "copper-cable"}, plan.lanes)
    end)

    it("totals what each ingredient needs: 120 plates and 360 cables a minute for two machines", function()
      local recipe = {
        energy = 0.5,
        ingredients = {amount_of(1, "iron-plate"), amount_of(3, "copper-cable")},
        products = {amount_of(1, "electronic-circuit")},
      }

      local plan = planner.plan{
        product = "electronic-circuit", rate_per_minute = 120, recipe = recipe,
        machine_speed = 0.5, lane_items_per_minute = 450,
      }

      assert.are.equal(2, plan.machines) -- 60 crafts a minute each
      assert.are.equal("iron-plate", plan.inputs[1].name)
      assert.near(120, plan.inputs[1].per_minute, 1e-6) -- 2 machines x 60 crafts x 1
      assert.are.equal("copper-cable", plan.inputs[2].name)
      assert.near(360, plan.inputs[2].per_minute, 1e-6) -- 2 machines x 60 crafts x 3
    end)

    it("is limited by the ingredient whose lane fills first: cables, 2 machines of 180 on a 450 lane", function()
      local recipe = {
        energy = 0.5,
        ingredients = {amount_of(1, "iron-plate"), amount_of(3, "copper-cable")},
        products = {amount_of(1, "electronic-circuit")},
      }

      local plan, reason, max_rate = planner.plan{
        product = "electronic-circuit", rate_per_minute = 121, recipe = recipe,
        machine_speed = 0.5, lane_items_per_minute = 450,
      }

      assert.is_nil(plan)
      assert.are.equal("rate-too-high", reason)
      assert.near(120, max_rate, 1e-6) -- 450 / 180 = 2.5, so 2 machines x 60; the plates alone would allow 7
    end)

    it("is limited by the first ingredient too, when its lane fills first", function()
      local recipe = {
        energy = 0.5,
        ingredients = {amount_of(3, "copper-cable"), amount_of(1, "iron-plate")},
        products = {amount_of(1, "electronic-circuit")},
      }

      local plan, reason, max_rate = planner.plan{
        product = "electronic-circuit", rate_per_minute = 121, recipe = recipe,
        machine_speed = 0.5, lane_items_per_minute = 450,
      }

      assert.is_nil(plan)
      assert.are.equal("rate-too-high", reason)
      assert.near(120, max_rate, 1e-6) -- the same recipe with its ingredients listed the other way round
    end)

    it("counts the inserters for both ingredients together: 240 items a minute need three inserters of 100", function()
      local recipe = {
        energy = 0.5,
        ingredients = {amount_of(1, "iron-plate"), amount_of(3, "copper-cable")},
        products = {amount_of(1, "electronic-circuit")},
      }

      local plan = planner.plan{
        product = "electronic-circuit", rate_per_minute = 60, recipe = recipe,
        machine_speed = 0.5, lane_items_per_minute = 450,
        inserters = {items_per_minute = 100, max_input = 3, max_output = 3},
      }

      assert.are.equal(3, plan.input_inserters) -- 60 crafts x (1 plate + 3 cables) = 240; 240 / 100 = 2.4, rounded up
      assert.are.equal(1, plan.output_inserters) -- 60 circuits
    end)
  end)

  describe("plan, for recipes that do not fit the input belt", function()
    it("does not support two ingredients plus a fuel, because three items do not fit on two lanes", function()
      local recipe = {
        energy = 3.2,
        ingredients = {amount_of(1, "iron-ore"), amount_of(1, "stone")},
        products = {amount_of(1, "iron-plate")},
      }

      local plan, reason = planner.plan{
        product = "iron-plate", rate_per_minute = 10, recipe = recipe,
        machine_speed = 1, lane_items_per_minute = 450, fuel = "coal",
      }

      assert.is_nil(plan)
      assert.are.equal("unsupported-recipe", reason)
    end)

    it("does not support three ingredients", function()
      local recipe = {
        energy = 0.5,
        ingredients = {amount_of(1, "iron-plate"), amount_of(1, "iron-gear-wheel"), amount_of(1, "electronic-circuit")},
        products = {amount_of(1, "inserter")},
      }

      local plan, reason = planner.plan{
        product = "inserter", rate_per_minute = 10, recipe = recipe,
        machine_speed = 0.5, lane_items_per_minute = 450,
      }

      assert.is_nil(plan)
      assert.are.equal("unsupported-recipe", reason)
    end)

    it("does not support a recipe with no ingredients", function()
      local recipe = {energy = 1, ingredients = {}, products = {amount_of(1, "iron-plate")}}

      local plan, reason = planner.plan{
        product = "iron-plate", rate_per_minute = 10, recipe = recipe,
        machine_speed = 1, lane_items_per_minute = 450,
      }

      assert.is_nil(plan)
      assert.are.equal("unsupported-recipe", reason)
    end)

    it("does not support a recipe that makes a second product, which would clog the machine", function()
      local recipe = {
        energy = 1,
        ingredients = {amount_of(1, "iron-ore")},
        products = {amount_of(1, "iron-plate"), amount_of(1, "stone")},
      }

      local plan, reason = planner.plan{
        product = "iron-plate", rate_per_minute = 10, recipe = recipe,
        machine_speed = 1, lane_items_per_minute = 450,
      }

      assert.is_nil(plan)
      assert.are.equal("unsupported-recipe", reason)
    end)

    it("does not support a recipe that takes no time", function()
      local instant = {energy = 0, ingredients = {amount_of(1, "iron-ore")}, products = {amount_of(1, "iron-plate")}}

      local plan, reason = planner.plan{
        product = "iron-plate", rate_per_minute = 10, recipe = instant,
        machine_speed = 1, lane_items_per_minute = 450, fuel = "coal",
      }

      assert.is_nil(plan)
      assert.are.equal("unsupported-recipe", reason)
    end)

    it("does not support a product the recipe does not make", function()
      local recipe = {energy = 3.2, ingredients = {amount_of(1, "iron-ore")}, products = {amount_of(1, "iron-plate")}}

      local plan, reason = planner.plan{
        product = "iron-gear-wheel", rate_per_minute = 10, recipe = recipe,
        machine_speed = 1, lane_items_per_minute = 450, fuel = "coal",
      }

      assert.is_nil(plan)
      assert.are.equal("unsupported-recipe", reason)
    end)
  end)

  describe("plan, with inserters that limit how fast a machine can be fed and emptied", function()
    it("needs one inserter on each side for a recipe far below an inserter's throughput", function()
      local recipe = {energy = 3.2, ingredients = {amount_of(1, "iron-ore")}, products = {amount_of(1, "iron-plate")}}

      local plan = planner.plan{
        product = "iron-plate", rate_per_minute = 18.75, recipe = recipe,
        machine_speed = 1, lane_items_per_minute = 450, fuel = "coal",
        inserters = {items_per_minute = 50, max_input = 3, max_output = 3},
      }

      assert.are.equal(1, plan.input_inserters) -- 18.75 ore a minute
      assert.are.equal(1, plan.output_inserters) -- 18.75 plates a minute
    end)

    it("needs more inserters on the busier side: three in and two out for a machine that eats 120 and makes 60", function()
      local recipe = {energy = 0.5, ingredients = {amount_of(2, "iron-plate")}, products = {amount_of(1, "iron-gear-wheel")}}

      local plan = planner.plan{
        product = "iron-gear-wheel", rate_per_minute = 60, recipe = recipe,
        machine_speed = 0.5, lane_items_per_minute = 450,
        inserters = {items_per_minute = 50, max_input = 3, max_output = 3},
      }

      assert.are.equal(3, plan.input_inserters) -- 60 x 0.5 / 0.5 = 60 crafts x 2 plates = 120; 120 / 50 = 2.4, rounded up
      assert.are.equal(2, plan.output_inserters) -- 60 gears; 60 / 50 = 1.2, rounded up
    end)

    it("does not add an inserter because of float noise in an exact fit", function()
      local recipe = {energy = 0.35, ingredients = {amount_of(2, "iron-plate")}, products = {amount_of(1, "iron-gear-wheel")}}

      local plan = planner.plan{
        product = "iron-gear-wheel", rate_per_minute = 60, recipe = recipe,
        machine_speed = 0.35, lane_items_per_minute = 450,
        inserters = {items_per_minute = 60, max_input = 3, max_output = 3},
      }

      assert.are.equal(2, plan.input_inserters) -- 120 plates a minute, written by the computer as 120.00000000000001
    end)

    it("runs a machine slower when its inserters cannot move what it eats: 25 gears a minute from one inserter of 50", function()
      local recipe = {energy = 0.5, ingredients = {amount_of(2, "iron-plate")}, products = {amount_of(1, "iron-gear-wheel")}}

      local plan = planner.plan{
        product = "iron-gear-wheel", rate_per_minute = 25, recipe = recipe,
        machine_speed = 0.5, lane_items_per_minute = 450,
        inserters = {items_per_minute = 50, max_input = 1, max_output = 1},
      }

      assert.are.equal(1, plan.machines)
      assert.are.equal(25, plan.output_per_minute) -- eats 120 at full speed, gets 50, so makes 60 x 50 / 120
      assert.are.equal(50, plan.inputs[1].per_minute)
      assert.are.equal(1, plan.input_inserters)
      assert.are.equal(1, plan.output_inserters)
    end)

    it("needs more machines when each one runs slower: 60 gears a minute from machines making 25", function()
      local recipe = {energy = 0.5, ingredients = {amount_of(2, "iron-plate")}, products = {amount_of(1, "iron-gear-wheel")}}

      local plan = planner.plan{
        product = "iron-gear-wheel", rate_per_minute = 60, recipe = recipe,
        machine_speed = 0.5, lane_items_per_minute = 450,
        inserters = {items_per_minute = 50, max_input = 1, max_output = 1},
      }

      assert.are.equal(3, plan.machines) -- 60 / 25 = 2.4, rounded up
    end)

    it("slows by the output side when that side is the busier one", function()
      local recipe = {energy = 1, ingredients = {amount_of(1, "iron-ore")}, products = {amount_of(4, "iron-plate")}}

      local plan = planner.plan{
        product = "iron-plate", rate_per_minute = 200, recipe = recipe,
        machine_speed = 1, lane_items_per_minute = 450, fuel = "coal",
        inserters = {items_per_minute = 100, max_input = 2, max_output = 2},
      }

      assert.are.equal(1, plan.machines)
      assert.are.equal(200, plan.output_per_minute) -- makes 240 at full speed, 2 inserters move 200
      assert.are.equal(50, plan.inputs[1].per_minute) -- eats 60 at full speed, so 60 x 200 / 240
      assert.are.equal(1, plan.input_inserters)
      assert.are.equal(2, plan.output_inserters)
    end)

    it("slows by both ingredients together when they are what the inserters cannot move", function()
      local recipe = {
        energy = 0.5,
        ingredients = {amount_of(1, "iron-plate"), amount_of(3, "copper-cable")},
        products = {amount_of(1, "electronic-circuit")},
      }

      local plan = planner.plan{
        product = "electronic-circuit", rate_per_minute = 30, recipe = recipe,
        machine_speed = 0.5, lane_items_per_minute = 450,
        inserters = {items_per_minute = 60, max_input = 2, max_output = 2},
      }

      assert.are.equal(1, plan.machines)
      assert.near(30, plan.output_per_minute, 1e-6) -- eats 240 at full speed, 2 inserters move 120, so makes 60 x 120 / 240
      assert.near(30, plan.inputs[1].per_minute, 1e-6) -- 1 plate a craft
      assert.near(90, plan.inputs[2].per_minute, 1e-6) -- 3 cables a craft
    end)

    it("fits as many machines as the slowed flow allows on the input lanes: 18 gear machines of 50 plates a minute on 900", function()
      local recipe = {energy = 0.5, ingredients = {amount_of(2, "iron-plate")}, products = {amount_of(1, "iron-gear-wheel")}}

      local plan, reason, max_rate = planner.plan{
        product = "iron-gear-wheel", rate_per_minute = 500, recipe = recipe,
        machine_speed = 0.5, lane_items_per_minute = 450,
        inserters = {items_per_minute = 50, max_input = 1, max_output = 1},
      }

      assert.is_nil(plan)
      assert.are.equal("rate-too-high", reason)
      assert.near(450, max_rate, 1e-6) -- each machine eats 50 and makes 25; 900 / 50 = 18 machines, and 18 x 25 fills the output lane
    end)

    it("counts one inserter per side when no inserter limit is given", function()
      local recipe = {energy = 0.5, ingredients = {amount_of(2, "iron-plate")}, products = {amount_of(1, "iron-gear-wheel")}}

      local plan = planner.plan{
        product = "iron-gear-wheel", rate_per_minute = 60, recipe = recipe,
        machine_speed = 0.5, lane_items_per_minute = 450,
      }

      assert.are.equal(1, plan.input_inserters)
      assert.are.equal(1, plan.output_inserters)
    end)
  end)

  describe("plan, with each side's own inserter limit", function()
    it("slows a machine by the output side's limit when the input side has room: 100 of the 120 it makes", function()
      local recipe = {energy = 1, ingredients = {amount_of(1, "iron-plate")}, products = {amount_of(2, "iron-gear-wheel")}}

      local plan = planner.plan{
        product = "iron-gear-wheel", rate_per_minute = 100, recipe = recipe,
        machine_speed = 1, lane_items_per_minute = 450,
        inserters = {items_per_minute = 100, max_input = 3, max_output = 1},
      }

      assert.are.equal(1, plan.machines)
      assert.near(100, plan.output_per_minute, 1e-6) -- makes 60 crafts x 2 = 120, one inserter moves 100
      assert.near(50, plan.inputs[1].per_minute, 1e-6) -- eats 60, so 60 x 100 / 120
      assert.are.equal(1, plan.input_inserters)
      assert.are.equal(1, plan.output_inserters)
    end)

    it("slows a machine by the input side's limit when the output side has room: 100 of the 120 it eats", function()
      local recipe = {energy = 1, ingredients = {amount_of(2, "iron-plate")}, products = {amount_of(1, "iron-gear-wheel")}}

      local plan = planner.plan{
        product = "iron-gear-wheel", rate_per_minute = 50, recipe = recipe,
        machine_speed = 1, lane_items_per_minute = 450,
        inserters = {items_per_minute = 100, max_input = 1, max_output = 3},
      }

      assert.are.equal(1, plan.machines)
      assert.near(100, plan.inputs[1].per_minute, 1e-6) -- eats 60 crafts x 2 = 120, one inserter moves 100
      assert.near(50, plan.output_per_minute, 1e-6) -- makes 60, so 60 x 100 / 120
    end)
  end)

  describe("plan, with the product on one lane or two", function()
    it("keeps the product on one lane while one inserter empties each machine: 7 machines of 60 fill a 450 lane", function()
      local recipe = {energy = 1, ingredients = {amount_of(1, "iron-plate")}, products = {amount_of(1, "iron-gear-wheel")}}

      local plan, reason, max_rate = planner.plan{
        product = "iron-gear-wheel", rate_per_minute = 421, recipe = recipe,
        machine_speed = 1, lane_items_per_minute = 450,
        inserters = {items_per_minute = 100, max_input = 2, max_output = 2},
      }

      assert.is_nil(plan)
      assert.are.equal("rate-too-high", reason)
      assert.near(420, max_rate, 1e-6) -- makes and eats 60 a minute, one inserter each side; 450 / 60 = 7.5
    end)

    it("puts the product on both lanes when two inserters empty each machine, so 4 machines of 120 fit", function()
      local recipe = {energy = 1, ingredients = {amount_of(1, "iron-plate")}, products = {amount_of(2, "iron-gear-wheel")}}

      local plan = planner.plan{
        product = "iron-gear-wheel", rate_per_minute = 480, recipe = recipe,
        machine_speed = 1, lane_items_per_minute = 450,
        inserters = {items_per_minute = 100, max_input = 2, max_output = 2},
      }

      assert.are.equal(4, plan.machines) -- one lane alone would stop at 3 (450 / 120)
      assert.are.equal(2, plan.output_inserters) -- 120 a minute needs two inserters of 100
    end)

    it("limits the machines by what one inserter can put on one lane, because the first inserter takes all it can", function()
      local recipe = {energy = 1, ingredients = {amount_of(1, "iron-plate")}, products = {amount_of(2, "iron-gear-wheel")}}

      local plan, reason, max_rate = planner.plan{
        product = "iron-gear-wheel", rate_per_minute = 481, recipe = recipe,
        machine_speed = 1, lane_items_per_minute = 450,
        inserters = {items_per_minute = 100, max_input = 2, max_output = 2},
      }

      assert.is_nil(plan)
      assert.are.equal("rate-too-high", reason)
      assert.near(480, max_rate, 1e-6) -- 450 / 100 = 4.5 machines, so 4 x 120; the two lanes could take 7 (900 / 120)
    end)

    it("keeps the product on one lane for three output inserters, which the belt cannot wind for", function()
      local recipe = {energy = 1, ingredients = {amount_of(1, "iron-plate")}, products = {amount_of(5, "iron-gear-wheel")}}

      local plan, reason, max_rate = planner.plan{
        product = "iron-gear-wheel", rate_per_minute = 301, recipe = recipe,
        machine_speed = 1, lane_items_per_minute = 450,
        inserters = {items_per_minute = 100, max_input = 3, max_output = 3},
      }

      assert.is_nil(plan)
      assert.are.equal("rate-too-high", reason)
      assert.near(300, max_rate, 1e-6) -- each machine makes 60 crafts x 5 = 300 and needs 3 inserters; 450 / 300 = 1.5
    end)
  end)

  describe("inserter_items_per_minute", function()
    it("gives about 50 items a minute for the basic inserter's rotation speed of 0.014", function()
      local basic_rotation_speed = 0.014

      local per_minute = planner.inserter_items_per_minute(basic_rotation_speed)

      assert.near(50.4, per_minute, 1e-6) -- 0.014 swings a tick x 60 ticks x 60 seconds, one item a swing
    end)
  end)

  describe("lane_items_per_minute", function()
    it("gives 450 items a minute per lane for a belt of speed 0.03125", function()
      local standard_belt_speed = 0.03125

      local per_minute = planner.lane_items_per_minute(standard_belt_speed)

      assert.near(450, per_minute, 1e-6) -- 0.03125 x 4 items x 60 ticks x 60 seconds
    end)

    it("carries twice as much per lane on a belt twice as fast", function()
      local double_belt_speed = 0.0625

      local per_minute = planner.lane_items_per_minute(double_belt_speed)

      assert.near(900, per_minute, 1e-6)
    end)
  end)
end)
