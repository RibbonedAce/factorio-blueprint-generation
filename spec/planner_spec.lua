-- spec/planner_spec.lua
-- How many machines does a rate need? The arithmetic behind the numbers is
-- written next to the test that relies on it: one furnace with speed 1 and a
-- 3.2 s recipe crafts 60 / 3.2 = 18.75 times a minute.
---@diagnostic disable: undefined-field  -- luassert's `assert` has fields (`assert.are`, `assert.is_nil`, ...) the editor cannot see
---@diagnostic disable: need-check-nil  -- the assertion before each use fails the test first if the plan is nil

local planner = require("scripts.planner")
local builders = require("spec.support.builders")

local amount_of = builders.amount_of

describe("planner", function()
  describe("plan", function()
    it("needs one furnace for exactly one furnace's output, without float noise adding another", function()
      local recipe = {energy = 3.2, ingredients = {amount_of(1, "iron-ore")}, products = {amount_of(1, "iron-plate")}}
      local furnace_speed = 1
      local plates_per_minute_of_one_furnace = 18.75 -- 60 s / 3.2 s
      local belt_lane_limit = 450

      local plan = planner.plan("iron-plate", plates_per_minute_of_one_furnace, recipe, furnace_speed, belt_lane_limit)

      assert.are.equal(1, plan.machines)
      assert.near(18.75, plan.output_per_minute, 1e-6)
    end)

    it("needs two furnaces for a rate just above one furnace's output", function()
      local recipe = {energy = 3.2, ingredients = {amount_of(1, "iron-ore")}, products = {amount_of(1, "iron-plate")}}

      local plan = planner.plan("iron-plate", 18.76, recipe, 1, 450)

      assert.are.equal(2, plan.machines)
    end)

    it("still needs one furnace for a tiny rate", function()
      local recipe = {energy = 3.2, ingredients = {amount_of(1, "iron-ore")}, products = {amount_of(1, "iron-plate")}}

      local plan = planner.plan("iron-plate", 0.001, recipe, 1, 450)

      assert.are.equal(1, plan.machines)
    end)

    it("still needs one furnace, not none, for a rate too small to notice", function()
      local recipe = {energy = 3.2, ingredients = {amount_of(1, "iron-ore")}, products = {amount_of(1, "iron-plate")}}
      local almost_nothing = 1e-12 -- less than the float guard, so the division rounds to zero

      local plan = planner.plan("iron-plate", almost_nothing, recipe, 1, 450)

      assert.are.equal(1, plan.machines)
    end)

    it("needs four furnaces for 60 plates a minute", function()
      local recipe = {energy = 3.2, ingredients = {amount_of(1, "iron-ore")}, products = {amount_of(1, "iron-plate")}}

      local plan = planner.plan("iron-plate", 60, recipe, 1, 450)

      assert.are.equal(4, plan.machines) -- 60 / 18.75 = 3.2, rounded up
    end)

    it("makes 75 plates a minute with four furnaces", function()
      local recipe = {energy = 3.2, ingredients = {amount_of(1, "iron-ore")}, products = {amount_of(1, "iron-plate")}}

      local plan = planner.plan("iron-plate", 60, recipe, 1, 450)

      assert.near(75, plan.output_per_minute, 1e-6) -- 4 x 18.75
    end)

    it("makes four furnaces eat 75 ore a minute, with the ore as the ingredient", function()
      local recipe = {energy = 3.2, ingredients = {amount_of(1, "iron-ore")}, products = {amount_of(1, "iron-plate")}}

      local plan = planner.plan("iron-plate", 60, recipe, 1, 450)

      assert.near(75, plan.ingredient_per_minute, 1e-6) -- one ore per plate
      assert.are.equal("iron-ore", plan.ingredient)
    end)

    it("draws twice the ore for a recipe that eats two ore per craft", function()
      local recipe = {energy = 3.2, ingredients = {amount_of(2, "iron-ore")}, products = {amount_of(1, "iron-plate")}}

      local plan = planner.plan("iron-plate", 60, recipe, 1, 450)

      assert.are.equal(4, plan.machines)
      assert.near(150, plan.ingredient_per_minute, 1e-6) -- 4 furnaces x 18.75 crafts x 2 ore
    end)

    it("makes twice the output per furnace for a recipe that makes two items per craft", function()
      local recipe = {energy = 3.2, ingredients = {amount_of(1, "iron-ore")}, products = {amount_of(2, "iron-plate")}}

      local plan = planner.plan("iron-plate", 75, recipe, 1, 450)

      assert.are.equal(2, plan.machines) -- 75 / (18.75 crafts x 2 items) = 2
      assert.near(75, plan.output_per_minute, 1e-6)
      assert.near(37.5, plan.ingredient_per_minute, 1e-6) -- 2 furnaces x 18.75 crafts x 1 ore
    end)

    it("is limited by the ingredient lane when that is the one that runs out first", function()
      local recipe = {energy = 3.2, ingredients = {amount_of(2, "iron-ore")}, products = {amount_of(1, "iron-plate")}}
      -- One furnace eats 37.5 ore a minute, so a 450 lane feeds 12 furnaces (225 plates),
      -- even though the plates alone would fit on the output lane up to 450.

      local plan, reason, max_rate = planner.plan("iron-plate", 240, recipe, 1, 450)

      assert.is_nil(plan)
      assert.are.equal("rate-too-high", reason)
      assert.near(225, max_rate, 1e-6) -- 12 furnaces x 18.75
    end)

    it("needs half the machines for a machine twice as fast", function()
      local recipe = {energy = 3.2, ingredients = {amount_of(1, "iron-ore")}, products = {amount_of(1, "iron-plate")}}
      local double_speed = 2 -- 37.5 plates a minute each

      local plan = planner.plan("iron-plate", 60, recipe, double_speed, 450)

      assert.are.equal(2, plan.machines) -- 60 / 37.5 = 1.6, rounded up
    end)

    it("does not let float noise in the division add an extra machine", function()
      -- Eleven machines of a 1.1 s recipe make exactly 600 a minute, but 600 / (60 / 1.1)
      -- comes out as 11.000000000000002 in floating point and would round up to 12.
      local recipe = {energy = 1.1, ingredients = {amount_of(1, "iron-ore")}, products = {amount_of(1, "iron-plate")}}
      local wide_lane = 10000

      local plan = planner.plan("iron-plate", 600, recipe, 1, wide_lane)

      assert.are.equal(11, plan.machines)
    end)

    it("fills one belt lane exactly with 24 furnaces at 450 plates a minute", function()
      local recipe = {energy = 3.2, ingredients = {amount_of(1, "iron-ore")}, products = {amount_of(1, "iron-plate")}}
      local lane_limit = 450

      local plan = planner.plan("iron-plate", 450, recipe, 1, lane_limit)

      assert.are.equal(24, plan.machines) -- 450 / 18.75
    end)

    it("refuses more than one belt lane carries, naming the most that fits", function()
      local recipe = {energy = 3.2, ingredients = {amount_of(1, "iron-ore")}, products = {amount_of(1, "iron-plate")}}
      local lane_limit = 450

      local plan, reason, max_rate = planner.plan("iron-plate", 451, recipe, 1, lane_limit)

      assert.is_nil(plan)
      assert.are.equal("rate-too-high", reason)
      assert.near(450, max_rate, 1e-6) -- 24 furnaces x 18.75
    end)

    it("does not support a recipe with two ingredients", function()
      local recipe = {
        energy = 3.2,
        ingredients = {amount_of(1, "iron-ore"), amount_of(1, "coal")},
        products = {amount_of(1, "iron-plate")},
      }

      local plan, reason = planner.plan("iron-plate", 10, recipe, 1, 450)

      assert.is_nil(plan)
      assert.are.equal("unsupported-recipe", reason)
    end)

    it("does not support a recipe that takes no time", function()
      local instant = {energy = 0, ingredients = {amount_of(1, "iron-ore")}, products = {amount_of(1, "iron-plate")}}

      local plan, reason = planner.plan("iron-plate", 10, instant, 1, 450)

      assert.is_nil(plan)
      assert.are.equal("unsupported-recipe", reason)
    end)

    it("does not support a product the recipe does not make", function()
      local recipe = {energy = 3.2, ingredients = {amount_of(1, "iron-ore")}, products = {amount_of(1, "iron-plate")}}

      local plan, reason = planner.plan("iron-gear-wheel", 10, recipe, 1, 450)

      assert.is_nil(plan)
      assert.are.equal("unsupported-recipe", reason)
    end)
  end)

  describe("plan, with inserters that limit how fast a machine can be fed and emptied", function()
    it("needs one inserter on each side for a recipe far below an inserter's throughput", function()
      local recipe = {energy = 3.2, ingredients = {amount_of(1, "iron-ore")}, products = {amount_of(1, "iron-plate")}}
      local inserters = {items_per_minute = 50, max_per_side = 3}

      local plan = planner.plan("iron-plate", 18.75, recipe, 1, 450, inserters)

      assert.are.equal(1, plan.input_inserters) -- 18.75 ore a minute
      assert.are.equal(1, plan.output_inserters) -- 18.75 plates a minute
    end)

    it("needs more inserters on the busier side: three in and two out for a machine that eats 120 and makes 60", function()
      local recipe = {energy = 0.5, ingredients = {amount_of(2, "iron-plate")}, products = {amount_of(1, "iron-gear-wheel")}}
      local inserters = {items_per_minute = 50, max_per_side = 3}

      local plan = planner.plan("iron-gear-wheel", 60, recipe, 0.5, 450, inserters)

      assert.are.equal(3, plan.input_inserters) -- 60 x 0.5 / 0.5 = 60 crafts x 2 plates = 120; 120 / 50 = 2.4, rounded up
      assert.are.equal(2, plan.output_inserters) -- 60 gears; 60 / 50 = 1.2, rounded up
    end)

    it("does not add an inserter because of float noise in an exact fit", function()
      local recipe = {energy = 0.35, ingredients = {amount_of(2, "iron-plate")}, products = {amount_of(1, "iron-gear-wheel")}}
      local inserters = {items_per_minute = 60, max_per_side = 3}

      local plan = planner.plan("iron-gear-wheel", 60, recipe, 0.35, 450, inserters)

      assert.are.equal(2, plan.input_inserters) -- 120 plates a minute, written by the computer as 120.00000000000001
    end)

    it("refuses when the inserters needed on a side do not fit around the machine", function()
      local recipe = {energy = 0.5, ingredients = {amount_of(2, "iron-plate")}, products = {amount_of(1, "iron-gear-wheel")}}
      local inserters = {items_per_minute = 50, max_per_side = 2}

      local plan, reason = planner.plan("iron-gear-wheel", 60, recipe, 0.5, 450, inserters)

      assert.is_nil(plan)
      assert.are.equal("inserters-do-not-fit", reason) -- 3 input inserters are needed, 2 fit
    end)

    it("refuses when only the output side needs more inserters than fit", function()
      local recipe = {energy = 1, ingredients = {amount_of(1, "iron-ore")}, products = {amount_of(4, "iron-plate")}}
      local inserters = {items_per_minute = 100, max_per_side = 2}

      local plan, reason = planner.plan("iron-plate", 60, recipe, 1, 450, inserters)

      assert.is_nil(plan)
      assert.are.equal("inserters-do-not-fit", reason) -- 60 in needs 1 inserter, 240 out needs 3, 2 fit
    end)

    it("counts one inserter per side when no inserter limit is given", function()
      local recipe = {energy = 0.5, ingredients = {amount_of(2, "iron-plate")}, products = {amount_of(1, "iron-gear-wheel")}}

      local plan = planner.plan("iron-gear-wheel", 60, recipe, 0.5, 450)

      assert.are.equal(1, plan.input_inserters)
      assert.are.equal(1, plan.output_inserters)
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
