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
    it("needs one machine when the rate is exactly what one machine makes", function()
      local recipe = {energy = 3.2, ingredients = {amount_of(1, "iron-ore")}, products = {amount_of(1, "iron-plate")}}
      local plates_per_minute_of_one_furnace = 18.75 -- 60 s / 3.2 s

      local plan = planner.plan{
        product = "iron-plate", rate_per_minute = plates_per_minute_of_one_furnace, recipe = recipe,
        machine_speed = 1, lane_items_per_minute = 450, fuel = "coal",
      }

      assert.are.equal(1, plan.machines)
      assert.near(18.75, plan.output_per_minute, 1e-6)
    end)

    it("needs another machine when the rate is just above what one machine makes", function()
      local recipe = {energy = 3.2, ingredients = {amount_of(1, "iron-ore")}, products = {amount_of(1, "iron-plate")}}

      local plan = planner.plan{
        product = "iron-plate", rate_per_minute = 18.76, recipe = recipe,
        machine_speed = 1, lane_items_per_minute = 450, fuel = "coal",
      }

      assert.are.equal(2, plan.machines)
    end)

    it("needs one machine when the rate is tiny", function()
      local recipe = {energy = 3.2, ingredients = {amount_of(1, "iron-ore")}, products = {amount_of(1, "iron-plate")}}

      local plan = planner.plan{
        product = "iron-plate", rate_per_minute = 0.001, recipe = recipe,
        machine_speed = 1, lane_items_per_minute = 450, fuel = "coal",
      }

      assert.are.equal(1, plan.machines)
    end)

    it("needs at least one machine when the rate is too small to notice", function()
      local recipe = {energy = 3.2, ingredients = {amount_of(1, "iron-ore")}, products = {amount_of(1, "iron-plate")}}
      local almost_nothing = 1e-12 -- less than the float guard, so the division rounds to zero

      local plan = planner.plan{
        product = "iron-plate", rate_per_minute = almost_nothing, recipe = recipe,
        machine_speed = 1, lane_items_per_minute = 450, fuel = "coal",
      }

      assert.are.equal(1, plan.machines)
    end)

    it("rounds up to whole machines when the rate is not a multiple of one machine's output", function()
      local recipe = {energy = 3.2, ingredients = {amount_of(1, "iron-ore")}, products = {amount_of(1, "iron-plate")}}

      local plan = planner.plan{
        product = "iron-plate", rate_per_minute = 60, recipe = recipe,
        machine_speed = 1, lane_items_per_minute = 450, fuel = "coal",
      }

      assert.are.equal(4, plan.machines) -- 60 / 18.75 = 3.2, rounded up
    end)

    it("reports the rate actually made when the machines are rounded up", function()
      local recipe = {energy = 3.2, ingredients = {amount_of(1, "iron-ore")}, products = {amount_of(1, "iron-plate")}}

      local plan = planner.plan{
        product = "iron-plate", rate_per_minute = 60, recipe = recipe,
        machine_speed = 1, lane_items_per_minute = 450, fuel = "coal",
      }

      assert.near(75, plan.output_per_minute, 1e-6) -- 4 x 18.75
    end)

    it("totals what all the machines eat when the recipe has one ingredient", function()
      local recipe = {energy = 3.2, ingredients = {amount_of(1, "iron-ore")}, products = {amount_of(1, "iron-plate")}}

      local plan = planner.plan{
        product = "iron-plate", rate_per_minute = 60, recipe = recipe,
        machine_speed = 1, lane_items_per_minute = 450, fuel = "coal",
      }

      assert.are.equal(1, #plan.inputs)
      assert.are.equal("iron-ore", plan.inputs[1].name)
      assert.near(75, plan.inputs[1].per_minute, 1e-6) -- one ore per plate
    end)

    it("scales the ingredient needed when the recipe uses several per craft", function()
      local recipe = {energy = 3.2, ingredients = {amount_of(2, "iron-ore")}, products = {amount_of(1, "iron-plate")}}

      local plan = planner.plan{
        product = "iron-plate", rate_per_minute = 60, recipe = recipe,
        machine_speed = 1, lane_items_per_minute = 450, fuel = "coal",
      }

      assert.are.equal(4, plan.machines)
      assert.near(150, plan.inputs[1].per_minute, 1e-6) -- 4 furnaces x 18.75 crafts x 2 ore
    end)

    it("scales the output per machine when the recipe makes several items per craft", function()
      local recipe = {energy = 3.2, ingredients = {amount_of(1, "iron-ore")}, products = {amount_of(2, "iron-plate")}}

      local plan = planner.plan{
        product = "iron-plate", rate_per_minute = 75, recipe = recipe,
        machine_speed = 1, lane_items_per_minute = 450, fuel = "coal",
      }

      assert.are.equal(2, plan.machines) -- 75 / (18.75 crafts x 2 items) = 2
      assert.near(75, plan.output_per_minute, 1e-6)
      assert.near(37.5, plan.inputs[1].per_minute, 1e-6) -- 2 furnaces x 18.75 crafts x 1 ore
    end)

    it("limits the rate when the ingredient lane fills before the output lane", function()
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

    it("needs fewer machines when the machine is faster", function()
      local recipe = {energy = 3.2, ingredients = {amount_of(1, "iron-ore")}, products = {amount_of(1, "iron-plate")}}
      local double_speed = 2 -- 37.5 plates a minute each

      local plan = planner.plan{
        product = "iron-plate", rate_per_minute = 60, recipe = recipe,
        machine_speed = double_speed, lane_items_per_minute = 450, fuel = "coal",
      }

      assert.are.equal(2, plan.machines) -- 60 / 37.5 = 1.6, rounded up
    end)

    it("does not add a machine when rounding error makes an exact rate look slightly over", function()
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

    it("does not remove a machine when rounding error makes an exact ingredient fit look slightly over", function()
      -- A machine of speed 0.5 on a 0.35 s recipe crafts 85.714... times a minute and eats twice that
      -- in ore. Seven of them eat exactly 1200, but 1200 / 171.428... comes out as 6.999999999999999.
      local recipe = {energy = 0.35, ingredients = {amount_of(2, "iron-ore")}, products = {amount_of(1, "iron-plate")}}

      local plan = planner.plan{
        product = "iron-plate", rate_per_minute = 600, recipe = recipe,
        machine_speed = 0.5, lane_items_per_minute = 1200, fuel = "coal",
      }

      assert.are.equal(7, plan.machines) -- 600 plates / 85.714... a machine
    end)

    it("allows the rate when it exactly fills a belt lane", function()
      local recipe = {energy = 3.2, ingredients = {amount_of(1, "iron-ore")}, products = {amount_of(1, "iron-plate")}}

      local plan = planner.plan{
        product = "iron-plate", rate_per_minute = 450, recipe = recipe,
        machine_speed = 1, lane_items_per_minute = 450, fuel = "coal",
      }

      assert.are.equal(24, plan.machines) -- 450 / 18.75
    end)

    it("refuses the rate when it is more than a belt lane carries, naming the most that fits", function()
      local recipe = {energy = 3.2, ingredients = {amount_of(1, "iron-ore")}, products = {amount_of(1, "iron-plate")}}

      local plan, reason, max_rate = planner.plan{
        product = "iron-plate", rate_per_minute = 451, recipe = recipe,
        machine_speed = 1, lane_items_per_minute = 450, fuel = "coal",
      }

      assert.is_nil(plan)
      assert.are.equal("rate-too-high", reason)
      assert.near(450, max_rate, 1e-6) -- 24 furnaces x 18.75
    end)

    it("puts the ingredient and the fuel on separate input lanes when the machine burns fuel", function()
      local recipe = {energy = 3.2, ingredients = {amount_of(1, "iron-ore")}, products = {amount_of(1, "iron-plate")}}

      local plan = planner.plan{
        product = "iron-plate", rate_per_minute = 10, recipe = recipe,
        machine_speed = 1, lane_items_per_minute = 450, fuel = "coal",
      }

      assert.are.same({"iron-ore", "coal"}, plan.lanes)
    end)
  end)

  describe("plan, for a machine with no fuel and one ingredient (both lanes carry it)", function()
    it("puts the ingredient on both input lanes when the machine needs no fuel", function()
      local recipe = {energy = 0.5, ingredients = {amount_of(2, "iron-plate")}, products = {amount_of(1, "iron-gear-wheel")}}

      local plan = planner.plan{
        product = "iron-gear-wheel", rate_per_minute = 10, recipe = recipe,
        machine_speed = 0.5, lane_items_per_minute = 450,
      }

      assert.are.same({"iron-plate", "iron-plate"}, plan.lanes)
    end)

    it("fits more machines on the input belt when the ingredient has both lanes to itself", function()
      local recipe = {energy = 3.2, ingredients = {amount_of(3, "iron-ore")}, products = {amount_of(1, "iron-plate")}}

      local plan = planner.plan{
        product = "iron-plate", rate_per_minute = 300, recipe = recipe,
        machine_speed = 1, lane_items_per_minute = 450,
      }

      assert.are.equal(16, plan.machines) -- 300 / 18.75; 900 / (18.75 crafts x 3 ore) = 16
    end)

    it("refuses the rate when both input lanes are full, naming the most that fits", function()
      local recipe = {energy = 3.2, ingredients = {amount_of(3, "iron-ore")}, products = {amount_of(1, "iron-plate")}}

      local plan, reason, max_rate = planner.plan{
        product = "iron-plate", rate_per_minute = 301, recipe = recipe,
        machine_speed = 1, lane_items_per_minute = 450,
      }

      assert.is_nil(plan)
      assert.are.equal("rate-too-high", reason)
      assert.near(300, max_rate, 1e-6) -- 16 machines x 18.75
    end)

    it("gives the ingredient only one lane when a fuel takes the other", function()
      local recipe = {energy = 3.2, ingredients = {amount_of(3, "iron-ore")}, products = {amount_of(1, "iron-plate")}}

      local plan, reason, max_rate = planner.plan{
        product = "iron-plate", rate_per_minute = 160, recipe = recipe,
        machine_speed = 1, lane_items_per_minute = 450, fuel = "coal",
      }

      assert.is_nil(plan)
      assert.are.equal("rate-too-high", reason)
      assert.near(150, max_rate, 1e-6) -- 450 / 56.25 = 8 machines x 18.75
    end)

    it("does not remove a machine when rounding error makes an exact output lane fit look slightly over", function()
      -- Seven machines make exactly 600 a minute, the whole lane, but 600 / 85.714... comes out as 6.999999999999999.
      local recipe = {energy = 0.35, ingredients = {amount_of(1, "iron-plate")}, products = {amount_of(1, "iron-gear-wheel")}}

      local plan = planner.plan{
        product = "iron-gear-wheel", rate_per_minute = 600, recipe = recipe,
        machine_speed = 0.5, lane_items_per_minute = 600,
      }

      assert.are.equal(7, plan.machines) -- 600 gears / 85.714... a machine
    end)

    it("keeps the product on one lane when the input uses both lanes", function()
      local recipe = {energy = 1, ingredients = {amount_of(1, "iron-ore")}, products = {amount_of(2, "iron-plate")}}

      local plan, reason, max_rate = planner.plan{
        product = "iron-plate", rate_per_minute = 451, recipe = recipe,
        machine_speed = 1, lane_items_per_minute = 450,
      }

      assert.is_nil(plan)
      assert.are.equal("rate-too-high", reason)
      assert.near(450, max_rate, 1e-6) -- each machine makes 60 crafts x 2 = 120; the lane takes 450 / 120 = 3.75 machines' worth
    end)
  end)

  describe("plan, for a machine with two ingredients (one lane each)", function()
    it("puts one ingredient on each input lane when the recipe has two", function()
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

    it("totals each ingredient separately when the recipe has two", function()
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

    it("builds a machine for the part of a machine that the lane of the most eaten ingredient can still feed", function()
      local recipe = {
        energy = 0.5,
        ingredients = {amount_of(1, "iron-plate"), amount_of(3, "copper-cable")},
        products = {amount_of(1, "electronic-circuit")},
      }

      local plan = planner.plan{
        product = "electronic-circuit", rate_per_minute = 150, recipe = recipe,
        machine_speed = 0.5, lane_items_per_minute = 450,
      }

      assert.are.equal(3, plan.machines) -- the cable lane feeds 450 / 180 = 2.5 machines' worth
      assert.near(150, plan.output_per_minute, 1e-6) -- 2.5 x 60, not 3 x 60
      assert.near(450, plan.inputs[2].per_minute, 1e-6) -- 2.5 machines x 60 crafts x 3 cables: the whole lane
    end)

    it("limits the rate by the ingredient whose lane fills first when the recipe has two", function()
      local recipe = {
        energy = 0.5,
        ingredients = {amount_of(1, "iron-plate"), amount_of(3, "copper-cable")},
        products = {amount_of(1, "electronic-circuit")},
      }

      local plan, reason, max_rate = planner.plan{
        product = "electronic-circuit", rate_per_minute = 151, recipe = recipe,
        machine_speed = 0.5, lane_items_per_minute = 450,
      }

      assert.is_nil(plan)
      assert.are.equal("rate-too-high", reason)
      assert.near(150, max_rate, 1e-6) -- 450 / 180 = 2.5 machines' worth x 60; the plates alone would allow 7.5
    end)

    it("limits the rate by the first ingredient when its lane fills first", function()
      local recipe = {
        energy = 0.5,
        ingredients = {amount_of(3, "copper-cable"), amount_of(1, "iron-plate")},
        products = {amount_of(1, "electronic-circuit")},
      }

      local plan, reason, max_rate = planner.plan{
        product = "electronic-circuit", rate_per_minute = 151, recipe = recipe,
        machine_speed = 0.5, lane_items_per_minute = 450,
      }

      assert.is_nil(plan)
      assert.are.equal("rate-too-high", reason)
      assert.near(150, max_rate, 1e-6) -- the same recipe with its ingredients listed the other way round
    end)

    it("counts inserters for both ingredients together when they share a machine's input side", function()
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
    it("does not support the recipe when two ingredients and a fuel need three lanes", function()
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

    it("does not support the recipe when it has three ingredients", function()
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

    it("does not support the recipe when it has no ingredients", function()
      local recipe = {energy = 1, ingredients = {}, products = {amount_of(1, "iron-plate")}}

      local plan, reason = planner.plan{
        product = "iron-plate", rate_per_minute = 10, recipe = recipe,
        machine_speed = 1, lane_items_per_minute = 450,
      }

      assert.is_nil(plan)
      assert.are.equal("unsupported-recipe", reason)
    end)

    it("does not support the recipe when it makes a second product that would clog the machine", function()
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

    it("does not support the recipe when it takes no time", function()
      local instant = {energy = 0, ingredients = {amount_of(1, "iron-ore")}, products = {amount_of(1, "iron-plate")}}

      local plan, reason = planner.plan{
        product = "iron-plate", rate_per_minute = 10, recipe = instant,
        machine_speed = 1, lane_items_per_minute = 450, fuel = "coal",
      }

      assert.is_nil(plan)
      assert.are.equal("unsupported-recipe", reason)
    end)

    it("does not support the request when the recipe does not make the product", function()
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
    it("needs one inserter on each side when the flow is far below what an inserter moves", function()
      local recipe = {energy = 3.2, ingredients = {amount_of(1, "iron-ore")}, products = {amount_of(1, "iron-plate")}}

      local plan = planner.plan{
        product = "iron-plate", rate_per_minute = 18.75, recipe = recipe,
        machine_speed = 1, lane_items_per_minute = 450, fuel = "coal",
        inserters = {items_per_minute = 50, max_input = 3, max_output = 3},
      }

      assert.are.equal(1, plan.input_inserters) -- 18.75 ore a minute
      assert.are.equal(1, plan.output_inserters) -- 18.75 plates a minute
    end)

    it("needs more inserters on the busier side when a machine moves more than one inserter can", function()
      local recipe = {energy = 0.5, ingredients = {amount_of(2, "iron-plate")}, products = {amount_of(1, "iron-gear-wheel")}}

      local plan = planner.plan{
        product = "iron-gear-wheel", rate_per_minute = 60, recipe = recipe,
        machine_speed = 0.5, lane_items_per_minute = 450,
        inserters = {items_per_minute = 50, max_input = 3, max_output = 3},
      }

      assert.are.equal(3, plan.input_inserters) -- 60 x 0.5 / 0.5 = 60 crafts x 2 plates = 120; 120 / 50 = 2.4, rounded up
      assert.are.equal(2, plan.output_inserters) -- 60 gears; 60 / 50 = 1.2, rounded up
    end)

    it("does not add an inserter when rounding error makes an exact fit look slightly over", function()
      local recipe = {energy = 0.35, ingredients = {amount_of(2, "iron-plate")}, products = {amount_of(1, "iron-gear-wheel")}}

      local plan = planner.plan{
        product = "iron-gear-wheel", rate_per_minute = 60, recipe = recipe,
        machine_speed = 0.35, lane_items_per_minute = 450,
        inserters = {items_per_minute = 60, max_input = 3, max_output = 3},
      }

      assert.are.equal(2, plan.input_inserters) -- 120 plates a minute, written by the computer as 120.00000000000001
    end)

    it("runs a machine slower when its inserters cannot move what it needs", function()
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

    it("needs more machines when each one runs slower because of its inserters", function()
      local recipe = {energy = 0.5, ingredients = {amount_of(2, "iron-plate")}, products = {amount_of(1, "iron-gear-wheel")}}

      local plan = planner.plan{
        product = "iron-gear-wheel", rate_per_minute = 60, recipe = recipe,
        machine_speed = 0.5, lane_items_per_minute = 450,
        inserters = {items_per_minute = 50, max_input = 1, max_output = 1},
      }

      assert.are.equal(3, plan.machines) -- 60 / 25 = 2.4, rounded up
    end)

    it("slows a machine by its output side when that side is the busier one", function()
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

    it("slows a machine by all its ingredients together when they are more than the input inserters move", function()
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

    it("fits more machines on the input lanes when the machines are slowed by their inserters", function()
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
    it("slows a machine by the output side's limit when the input side has room", function()
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

    it("slows a machine by the input side's limit when the output side has room", function()
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
    it("keeps the product on one lane when one inserter empties each machine", function()
      local recipe = {energy = 1, ingredients = {amount_of(1, "iron-plate")}, products = {amount_of(1, "iron-gear-wheel")}}

      local plan, reason, max_rate = planner.plan{
        product = "iron-gear-wheel", rate_per_minute = 451, recipe = recipe,
        machine_speed = 1, lane_items_per_minute = 450,
        inserters = {items_per_minute = 100, max_input = 2, max_output = 2},
      }

      assert.is_nil(plan)
      assert.are.equal("rate-too-high", reason)
      assert.near(450, max_rate, 1e-6) -- makes and eats 60 a minute, one inserter each side; 450 / 60 = 7.5 machines' worth
    end)

    it("uses both output lanes when two inserters empty each machine", function()
      local recipe = {energy = 1, ingredients = {amount_of(1, "iron-plate")}, products = {amount_of(2, "iron-gear-wheel")}}

      local plan = planner.plan{
        product = "iron-gear-wheel", rate_per_minute = 480, recipe = recipe,
        machine_speed = 1, lane_items_per_minute = 450,
        inserters = {items_per_minute = 100, max_input = 2, max_output = 2},
      }

      assert.are.equal(4, plan.machines) -- one lane alone would stop at 450 (450 / 120 = 3.75 machines' worth)
      assert.are.equal(2, plan.output_inserters) -- 120 a minute needs two inserters of 100
    end)

    it("limits the rate by what the two lanes carry together when two inserters empty each machine", function()
      local recipe = {energy = 1, ingredients = {amount_of(1, "iron-plate")}, products = {amount_of(2, "iron-gear-wheel")}}

      local plan, reason, max_rate = planner.plan{
        product = "iron-gear-wheel", rate_per_minute = 901, recipe = recipe,
        machine_speed = 1, lane_items_per_minute = 450,
        inserters = {items_per_minute = 100, max_input = 2, max_output = 2},
      }

      assert.is_nil(plan)
      assert.are.equal("rate-too-high", reason)
      assert.near(900, max_rate, 1e-6) -- 2 x 450 / 120 = 7.5 machines' worth x 120, whichever lane fills first
    end)

    it("takes a rate that one lane cannot carry when two inserters empty each machine, as the second lane takes the rest", function()
      local recipe = {energy = 1, ingredients = {amount_of(1, "iron-plate")}, products = {amount_of(2, "iron-gear-wheel")}}

      local plan = planner.plan{
        product = "iron-gear-wheel", rate_per_minute = 541, recipe = recipe,
        machine_speed = 1, lane_items_per_minute = 450,
        inserters = {items_per_minute = 100, max_input = 2, max_output = 2},
      }

      assert.are.equal(5, plan.machines) -- 541 / 120 = 4.5; the lane of one inserter's 100 each would have stopped at 540
    end)

    it("keeps the product on one lane when three inserters empty each machine, which the belt cannot wind for", function()
      local recipe = {energy = 1, ingredients = {amount_of(1, "iron-plate")}, products = {amount_of(5, "iron-gear-wheel")}}

      local plan, reason, max_rate = planner.plan{
        product = "iron-gear-wheel", rate_per_minute = 451, recipe = recipe,
        machine_speed = 1, lane_items_per_minute = 450,
        inserters = {items_per_minute = 100, max_input = 3, max_output = 3},
      }

      assert.is_nil(plan)
      assert.are.equal("rate-too-high", reason)
      assert.near(450, max_rate, 1e-6) -- each machine makes 60 crafts x 5 = 300 and needs 3 inserters; 450 / 300 = 1.5 machines' worth
    end)
  end)

  describe("plan_chain, for ore smelted into plates that are crafted into gears", function()
    local plate_recipe = {energy = 3.2, ingredients = {amount_of(1, "iron-ore")}, products = {amount_of(1, "iron-plate")}}
    -- A speed 0.5 machine crafts 60 * 0.5 / 0.5 s = 60 gears a minute and eats 120 plates a minute.
    local gear_recipe = {energy = 0.5, ingredients = {amount_of(2, "iron-plate")}, products = {amount_of(1, "iron-gear-wheel")}}

    ---@param rate number
    ---@param overrides? table
    local function gear_chain(rate, overrides)
      local chain = {
        rate_per_minute = rate, lane_items_per_minute = 450,
        stages = {
          {product = "iron-plate", recipe = plate_recipe, machine_speed = 1, fuel = "coal"},
          {product = "iron-gear-wheel", recipe = gear_recipe, machine_speed = 0.5},
        },
      }
      for key, value in pairs(overrides or {}) do
        chain[key] = value
      end
      return chain
    end

    it("makes the plates the gear machines eat", function()
      local plans = planner.plan_chain(gear_chain(60))

      assert.are.equal(1, plans[2].machines)
      assert.near(120, plans[2].inputs[1].per_minute, 1e-6)
      assert.are.equal(7, plans[1].machines) -- 120 plates a minute / 18.75 a furnace = 6.4
      assert.is_true(plans[1].output_per_minute >= plans[2].inputs[1].per_minute)
    end)

    it("takes ore and fuel into the first stage, and only plates into the second", function()
      local plans = planner.plan_chain(gear_chain(60))

      assert.are.same({"iron-ore", "coal"}, plans[1].lanes)
      assert.are.same({"iron-plate"}, plans[2].lanes)
    end)

    it("needs as many gear machines as the rate asks for", function()
      local plans = planner.plan_chain(gear_chain(121))

      assert.are.equal(3, plans[2].machines)
    end)

    it("builds a gear machine for the part of a machine that the plate lane can still feed", function()
      local plans = planner.plan_chain(gear_chain(225))

      assert.are.equal(4, plans[2].machines) -- 225 / 60 = 3.75
      assert.are.equal(24, plans[1].machines) -- 450 plates / 18.75; four machines at full speed would eat 480 and need 26
      assert.near(225, plans[2].output_per_minute, 1e-6) -- the lane holds 3.75 machines' worth, not four
    end)

    it("refuses a rate the plate lane cannot carry to the gear machines", function()
      local plans, reason, max_rate = planner.plan_chain(gear_chain(226))

      assert.is_nil(plans)
      assert.are.equal("rate-too-high", reason)
      assert.near(225, max_rate, 1e-6) -- one plate lane carries 450 plates, enough for 3.75 machines' worth of 120 plates (60 gears)
    end)

    it("refuses a rate that the ore lane of the first stage cannot carry", function()
      local two_ore_per_plate = {
        energy = 3.2, ingredients = {amount_of(2, "iron-ore")}, products = {amount_of(1, "iron-plate")},
      }
      local stages = gear_chain(120).stages
      stages[1].recipe = two_ore_per_plate -- a furnace eats 37.5 ore a minute, so 12 of them fill the lane

      local plans, reason, max_rate = planner.plan_chain(gear_chain(120, {stages = stages}))

      assert.is_nil(plans)
      assert.are.equal("rate-too-high", reason)
      assert.near(112.5, max_rate, 1e-6) -- 12 furnaces make 225 plates a minute, 2 plates a gear
    end)

    it("uses both lanes of the last stage's output belt when two inserters empty each of its machines", function()
      local stages = gear_chain(60).stages
      stages[2].inserters = {items_per_minute = 50.4, max_input = 2, max_output = 2}
      stages[2].machine_speed = 1
      -- a machine eats 30 plates a minute and makes 60 gears: two output inserters
      stages[2].recipe = {energy = 2, ingredients = {amount_of(1, "iron-plate")}, products = {amount_of(2, "iron-gear-wheel")}}

      local plans, reason, max_rate = planner.plan_chain(gear_chain(1000, {stages = stages}))

      assert.is_nil(plans)
      assert.are.equal("rate-too-high", reason)
      assert.near(900, max_rate, 1e-6) -- the two lanes carry 2 x 450 / 60 = 15 machines' worth of 60 gears
    end)

    it("refuses a later stage that eats something other than the stage before it makes", function()
      local stages = gear_chain(60).stages
      stages[2].recipe = {energy = 0.5, ingredients = {amount_of(2, "copper-plate")}, products = {amount_of(1, "iron-gear-wheel")}}

      local plans, reason = planner.plan_chain(gear_chain(60, {stages = stages}))

      assert.is_nil(plans)
      assert.are.equal("unsupported-recipe", reason)
    end)

    it("refuses the chain when its first stage does not fit, even if a later stage would", function()
      local stages = gear_chain(60).stages
      stages[1].recipe = {
        energy = 3.2, ingredients = {amount_of(1, "iron-ore")},
        products = {amount_of(1, "iron-plate"), amount_of(1, "slag")},
      }

      local plans, reason = planner.plan_chain(gear_chain(60, {stages = stages}))

      assert.is_nil(plans)
      assert.are.equal("unsupported-recipe", reason)
    end)

    it("refuses a chain with no stages", function()
      local plans, reason = planner.plan_chain{rate_per_minute = 60, lane_items_per_minute = 450, stages = {}}

      assert.is_nil(plans)
      assert.are.equal("unsupported-recipe", reason)
    end)

    it("limits the rate to what the first stage can make when one machine of the last stage already eats more", function()
      local stages = gear_chain(60).stages
      stages[1].recipe = {energy = 3.2, ingredients = {amount_of(2, "iron-ore")}, products = {amount_of(1, "iron-plate")}}
      stages[2].recipe = {energy = 0.5, ingredients = {amount_of(5, "iron-plate")}, products = {amount_of(1, "iron-gear-wheel")}}

      local plans, reason, max_rate = planner.plan_chain(gear_chain(60, {stages = stages}))

      assert.is_nil(plans)
      assert.are.equal("rate-too-high", reason)
      assert.near(45, max_rate, 1e-6) -- one assembler eats 300 plates a minute; the ore lane feeds 12 furnaces (450 / 37.5), 225 plates, 5 a gear
    end)

    it("builds only the furnaces the gear machines can use when their output lane fills before their plate lane", function()
      local stages = gear_chain(60).stages
      -- a machine eats 60 plates a minute and makes 240 gears, so its output lane holds 450 / 240 = 1.875 machines' worth
      stages[2].recipe = {energy = 0.5, ingredients = {amount_of(1, "iron-plate")}, products = {amount_of(4, "iron-gear-wheel")}}

      local plans = planner.plan_chain(gear_chain(450, {stages = stages}))

      assert.are.equal(2, plans[2].machines) -- 450 / 240 = 1.875
      assert.are.equal(6, plans[1].machines) -- the machines work at 1.875 x 60 = 112.5 plates a minute, not 2 x 60 (which would take 7 furnaces)
    end)

    it("builds furnaces for the plates the rate needs, not for all the assembler could eat", function()
      local stages = gear_chain(60).stages
      stages[2].recipe = {energy = 0.5, ingredients = {amount_of(5, "iron-plate")}, products = {amount_of(1, "iron-gear-wheel")}}

      local plans = planner.plan_chain(gear_chain(40, {stages = stages}))

      assert.are.equal(11, plans[1].machines) -- 40 gears take 200 plates: 10.67 furnaces; the assembler could eat 300 (16 furnaces)
      assert.near(41.25, plans[2].output_per_minute, 1e-6) -- 11 furnaces make 206.25 plates, 5 a gear
    end)

    it("builds one furnace for a rate that takes a fraction of one furnace's plates", function()
      local plans = planner.plan_chain(gear_chain(1))

      assert.are.equal(1, plans[1].machines) -- 1 gear takes 2 plates; the assembler could eat 100.8
      assert.are.equal(1, plans[2].machines)
    end)

    it("shows an earlier stage making only what its output lane carries when its last machine is more than the lane takes", function()
      local stages = gear_chain(60).stages
      stages[1].machine_speed = 1.1 -- 20.625 plates a minute a furnace: the lane takes 21.8 of them

      local plans = planner.plan_chain(gear_chain(225, {stages = stages}))

      assert.are.equal(22, plans[1].machines)
      assert.near(450, plans[1].output_per_minute, 1e-6) -- not 22 x 20.625
    end)

    it("gives each stage the machines' worth of work the rate asks of it, as a fraction", function()
      local plans = planner.plan_chain(gear_chain(1))

      assert.near(2 / 18.75, plans[1].load, 1e-9) -- 2 plates a minute of a furnace's 18.75
      assert.near(1 / 60, plans[2].load, 1e-9) -- 1 gear of an assembler's 60 (this request has no inserter limit)
    end)

    it("gives the load of every stage in proportion to the rate", function()
      local at_one, at_ten = planner.plan_chain(gear_chain(1)), planner.plan_chain(gear_chain(10))

      assert.near(10 * at_one[1].load, at_ten[1].load, 1e-9)
      assert.near(10 * at_one[2].load, at_ten[2].load, 1e-9)
    end)

    -- The assembler takes two input inserters (100.8 plates a minute) and makes at most 60 gears with them.
    local function gear_chain_with_inserters(rate)
      local chain = gear_chain(rate)
      chain.stages[1].inserters = {items_per_minute = 50.4, max_input = 1, max_output = 1}
      chain.stages[2].inserters = {items_per_minute = 50.4, max_input = 2, max_output = 2}
      return chain
    end

    it("gives a single machine only the inserters its share of the work needs", function()
      local plans = planner.plan_chain(gear_chain_with_inserters(25)) -- half an assembler: 50 plates a minute

      assert.are.equal(1, plans[2].machines)
      assert.are.equal(1, plans[2].input_inserters) -- 49.6 plates fit one inserter's 50.4
      assert.are.equal(1, plans[2].output_inserters)
    end)

    it("keeps both inserters of a single machine when its share needs more than one", function()
      local plans = planner.plan_chain(gear_chain_with_inserters(40)) -- 80 plates a minute

      assert.are.equal(2, plans[2].input_inserters)
      assert.are.equal(1, plans[2].output_inserters) -- 40 gears fit one inserter
    end)

    it("keeps every inserter when there are two machines, since the first runs flat out", function()
      local plans = planner.plan_chain(gear_chain_with_inserters(60))

      assert.are.equal(2, plans[2].machines)
      assert.are.equal(2, plans[2].input_inserters)
    end)

    it("trims an earlier stage too, which then makes no more than its trimmed inserters move", function()
      local chain = gear_chain_with_inserters(20) -- 40 plates a minute
      chain.stages[1].machine_speed = 4 -- 75 plates a minute a furnace: two output inserters at full speed
      chain.stages[1].inserters = {items_per_minute = 50.4, max_input = 2, max_output = 2}

      local plans = planner.plan_chain(chain)

      assert.are.equal(1, plans[1].machines)
      assert.are.equal(1, plans[1].input_inserters) -- 40 of 75 plates: 0.53 of the furnace
      assert.are.equal(1, plans[1].output_inserters)
      assert.near(50.4, plans[1].output_per_minute, 1e-6)
      assert.near(50.4, plans[1].inputs[1].per_minute, 1e-6) -- ore in, one for one
    end)

    it("trims a machine that can have three inserters to two when 0.65 of it is used", function()
      local chain = gear_chain_with_inserters(33) -- 99 plates a minute; three inserters move 151.2 at full speed
      chain.stages[2].inserters = {items_per_minute = 50.4, max_input = 3, max_output = 3}
      chain.stages[2].recipe = {energy = 0.5, ingredients = {amount_of(3, "iron-plate")}, products = {amount_of(1, "iron-gear-wheel")}}

      local plans = planner.plan_chain(chain)

      assert.are.equal(1, plans[2].machines)
      assert.are.equal(2, plans[2].input_inserters) -- 99 plates fit two inserters' 100.8
    end)

    it("shows the last stage making no more than its trimmed inserters move", function()
      local plans = planner.plan_chain(gear_chain_with_inserters(25))

      assert.near(25.2, plans[2].output_per_minute, 1e-6) -- one input inserter: 50.4 plates, 2 a gear
      assert.near(50.4, plans[2].inputs[1].per_minute, 1e-6)
    end)

    it("shows the last stage making and eating what the stage before gives it", function()
      local plans = planner.plan_chain(gear_chain(1))

      assert.near(18.75, plans[1].output_per_minute, 1e-6) -- one furnace
      assert.near(9.375, plans[2].output_per_minute, 1e-6) -- 18.75 plates, 2 a gear
      assert.near(18.75, plans[2].inputs[1].per_minute, 1e-6)
    end)

    it("puts the plates of a later stage that burns fuel on one lane and the fuel on the other", function()
      local stages = gear_chain(60).stages
      stages[2].fuel = "coal"

      local plans = planner.plan_chain(gear_chain(60, {stages = stages}))

      assert.are.same({"iron-plate", "coal"}, plans[2].lanes)
    end)

    it("refuses a later stage that burns fuel when the stage before it does not make its one ingredient", function()
      local stages = gear_chain(60).stages
      stages[2].fuel = "coal"
      stages[2].recipe = {energy = 0.5, ingredients = {amount_of(2, "copper-plate")}, products = {amount_of(1, "iron-gear-wheel")}}

      local _, reason = planner.plan_chain(gear_chain(60, {stages = stages}))

      assert.are.equal("unsupported-recipe", reason)
    end)

    it("refuses a later stage that burns fuel and eats a second ingredient, which leaves no lane free", function()
      local stages = gear_chain(60).stages
      stages[2].fuel = "coal"
      stages[2].recipe = {
        energy = 0.5, ingredients = {amount_of(2, "iron-plate"), amount_of(1, "copper-plate")}, products = {amount_of(1, "iron-gear-wheel")},
      }

      local _, reason = planner.plan_chain(gear_chain(60, {stages = stages}))

      assert.are.equal("unsupported-recipe", reason)
    end)
    it("gives the same plan for one stage as plan does", function()
      local stage = gear_chain(60).stages[1]
      local plan = planner.plan{
        product = stage.product, recipe = stage.recipe, machine_speed = 1, fuel = "coal",
        rate_per_minute = 60, lane_items_per_minute = 450,
      }
      local plans = planner.plan_chain{rate_per_minute = 60, lane_items_per_minute = 450, stages = {stage}}

      assert.are.same(plan, plans[1])
    end)
  end)

  describe("max_rate, for the same chain", function()
    local plate_recipe = {energy = 3.2, ingredients = {amount_of(1, "iron-ore")}, products = {amount_of(1, "iron-plate")}}
    local gear_recipe = {energy = 0.5, ingredients = {amount_of(2, "iron-plate")}, products = {amount_of(1, "iron-gear-wheel")}}

    ---@param rate number
    ---@param stages? table
    local function request(rate, stages)
      return {
        rate_per_minute = rate, lane_items_per_minute = 450,
        stages = stages or {
          {product = "iron-plate", recipe = plate_recipe, machine_speed = 1, fuel = "coal"},
          {product = "iron-gear-wheel", recipe = gear_recipe, machine_speed = 0.5},
        },
      }
    end

    it("gives the most the lane of plates lets the last stage make", function()
      assert.are.equal(225, planner.max_rate(request(60))) -- 450 plates / 2 per gear
    end)

    it("gives what plan_chain names when the rate is just above it", function()
      local _, _, max_rate = planner.plan_chain(request(225.5))

      assert.are.equal(max_rate, planner.max_rate(request(60)))
    end)

    it("does not depend on the rate in the request", function()
      assert.are.equal(planner.max_rate(request(1)), planner.max_rate(request(100000)))
    end)

    it("gives nil and unsupported-recipe when a stage makes more than one product", function()
      local two_products = {energy = 3.2, ingredients = {amount_of(1, "iron-ore")}, products = {amount_of(1, "iron-plate"), amount_of(1, "stone")}}

      local max_rate, reason = planner.max_rate(request(60, {{product = "iron-plate", recipe = two_products, machine_speed = 1, fuel = "coal"}}))

      assert.is_nil(max_rate)
      assert.are.equal("unsupported-recipe", reason)
    end)
  end)

  describe("plan_tree, for a recipe with two made ingredients", function()
    -- A furnace (speed 1, 3.2 s) makes 18.75 plates a minute. An assembler (speed 0.5, 0.5 s) crafts 60 times a
    -- minute: cables, 1 plate to 2 cables, eat 60 plates and make 120; circuits, 1 plate and 3 cables to 1, eat 60
    -- plates and 180 cables and make 60.
    local iron_recipe = {energy = 3.2, ingredients = {amount_of(1, "iron-ore")}, products = {amount_of(1, "iron-plate")}}
    local copper_recipe = {energy = 3.2, ingredients = {amount_of(1, "copper-ore")}, products = {amount_of(1, "copper-plate")}}
    local cable_recipe = {energy = 0.5, ingredients = {amount_of(1, "copper-plate")}, products = {amount_of(2, "copper-cable")}}
    local circuit_recipe = {
      energy = 0.5, ingredients = {amount_of(1, "iron-plate"), amount_of(3, "copper-cable")},
      products = {amount_of(1, "electronic-circuit")},
    }

    -- A stage of the tree with the stages that make its ingredients.
    local function tree_of(product, recipe, machine_speed, suppliers, fuel)
      return {stage = {product = product, recipe = recipe, machine_speed = machine_speed, fuel = fuel}, suppliers = suppliers}
    end

    local function iron_plates() return tree_of("iron-plate", iron_recipe, 1, {}, "coal") end
    local function copper_cables()
      return tree_of("copper-cable", cable_recipe, 0.5, {tree_of("copper-plate", copper_recipe, 1, {}, "coal")})
    end

    local function circuits(rate, circuit_stage)
      return {
        rate_per_minute = rate, lane_items_per_minute = 450,
        root = circuit_stage or tree_of("electronic-circuit", circuit_recipe, 0.5, {iron_plates(), copper_cables()}),
      }
    end

    it("builds for each ingredient the machines its share of the rate needs", function()
      local plans = planner.plan_tree(circuits(60))

      assert.are.equal(1, plans.plan.machines) -- 60 circuits a minute is one assembler
      assert.are.equal(4, plans.suppliers[1].plan.machines) -- 60 plates / 18.75 = 3.2
      assert.are.equal(2, plans.suppliers[2].plan.machines) -- 180 cables / 120 = 1.5
      assert.are.equal(5, plans.suppliers[2].suppliers[1].plan.machines) -- 90 plates for the cables / 18.75 = 4.8
    end)

    it("takes each made ingredient on a lane of its own", function()
      local plans = planner.plan_tree(circuits(60))

      assert.are.same({"iron-plate", "copper-cable"}, plans.plan.lanes)
    end)

    it("takes ore and fuel on the lanes of the stages fed raw items", function()
      local plans = planner.plan_tree(circuits(60))

      assert.are.same({"iron-ore", "coal"}, plans.suppliers[1].plan.lanes)
      assert.are.same({"copper-plate"}, plans.suppliers[2].plan.lanes)
    end)

    it("shows the root making what all its stages make together, which is at least the rate asked", function()
      local plans = planner.plan_tree(circuits(55))

      -- one assembler could make 60, 5 copper furnaces make 93.75 plates for 62.5 circuits' cables,
      -- but 3 iron furnaces make only 56.25 plates, one for each circuit
      assert.near(56.25, plans.plan.output_per_minute, 1e-6)
    end)

    it("shows the root making only what the chain of the second ingredient can feed", function()
      local plans = planner.plan_tree(circuits(50))

      -- 4 copper furnaces make 75 plates, which is 150 cables and so 50 circuits; 3 iron furnaces would allow 56.25
      assert.near(50, plans.plan.output_per_minute, 1e-6)
    end)

    it("refuses a rate that the lane of one ingredient cannot carry", function()
      local plans, reason, max_rate = planner.plan_tree(circuits(151))

      assert.is_nil(plans)
      assert.are.equal("rate-too-high", reason)
      assert.near(150, max_rate, 1e-6) -- one lane carries 450 cables, 3 for each circuit
    end)

    it("refuses a rate that the lane of the other ingredient cannot carry", function()
      local hungry = {
        energy = 0.5, ingredients = {amount_of(10, "iron-plate"), amount_of(3, "copper-cable")},
        products = {amount_of(1, "electronic-circuit")},
      }

      local _, reason, max_rate = planner.plan_tree(circuits(100, tree_of("electronic-circuit", hungry, 0.5, {iron_plates(), copper_cables()})))

      assert.are.equal("rate-too-high", reason)
      assert.near(45, max_rate, 1e-6) -- a lane carries 450 plates a minute, 10 for each circuit
    end)

    it("allows the rate when the lane of an ingredient is exactly full", function()
      local plans = planner.plan_tree(circuits(150))

      assert.are.equal(3, plans.plan.machines) -- 150 / 60 = 2.5, rounded up
      assert.are.equal(8, plans.suppliers[1].plan.machines) -- 150 plates / 18.75
      assert.are.equal(12, plans.suppliers[2].suppliers[1].plan.machines) -- 225 plates / 18.75
    end)

    it("names the same most as the refusal does", function()
      local _, _, refused_max = planner.plan_tree(circuits(1000))

      local max_rate = planner.max_tree_rate(circuits(1))

      assert.are.equal(refused_max, max_rate)
    end)

    it("gives nil and unsupported-recipe for the most when a stage far down the tree does not fit", function()
      local two_products = {energy = 3.2, ingredients = {amount_of(1, "copper-ore")}, products = {amount_of(1, "copper-plate"), amount_of(1, "slag")}}
      local cables = tree_of("copper-cable", cable_recipe, 0.5, {tree_of("copper-plate", two_products, 1, {}, "coal")})

      local max_rate, reason = planner.max_tree_rate(circuits(60, tree_of("electronic-circuit", circuit_recipe, 0.5, {iron_plates(), cables})))

      assert.is_nil(max_rate)
      assert.are.equal("unsupported-recipe", reason)
    end)

    it("sizes the stages that feed a stage by what it eats of each, whatever order they are listed in", function()
      local swapped = tree_of("electronic-circuit", circuit_recipe, 0.5, {copper_cables(), iron_plates()})

      local plans = planner.plan_tree(circuits(60, swapped))

      assert.are.same({"iron-plate", "copper-cable"}, plans.plan.lanes) -- the recipe's order
      assert.are.equal(2, plans.suppliers[1].plan.machines) -- 180 cables / 120 = 1.5
      assert.are.equal(4, plans.suppliers[2].plan.machines) -- 60 plates / 18.75 = 3.2
    end)

    it("refuses a stage fed by a stage that makes none of its ingredients", function()
      local wrong = tree_of("electronic-circuit", circuit_recipe, 0.5, {iron_plates(), tree_of("stone-brick", iron_recipe, 1, {}, "coal")})

      local plans, reason = planner.plan_tree(circuits(60, wrong))

      assert.is_nil(plans)
      assert.are.equal("unsupported-recipe", reason)
    end)

    it("refuses a stage fed by two stages that make the same ingredient", function()
      local twice = tree_of("electronic-circuit", circuit_recipe, 0.5, {iron_plates(), iron_plates()})

      local plans, reason = planner.plan_tree(circuits(60, twice))

      assert.is_nil(plans)
      assert.are.equal("unsupported-recipe", reason)
    end)

    it("refuses a stage fed by made ingredients that burns fuel", function()
      local burning = tree_of("electronic-circuit", circuit_recipe, 0.5, {iron_plates(), copper_cables()}, "coal")

      local _, reason = planner.plan_tree(circuits(10, burning))

      assert.are.equal("unsupported-recipe", reason)
    end)

    it("passes the demand down through every level of a tree", function()
      -- One machine (speed 1, 1 s) crafts 60 a minute. T eats 2 U and 1 plate; U eats 3 plates and 1 gear; plates and gears come from ore.
      local function stage(product, ingredients, suppliers)
        local recipe = {energy = 1, ingredients = ingredients, products = {amount_of(1, product)}}
        return tree_of(product, recipe, 1, suppliers, #suppliers == 0 and "coal" or nil)
      end
      local plate = stage("plate", {amount_of(1, "ore")}, {})
      local gear = stage("gear", {amount_of(1, "scrap")}, {})
      local u = stage("u", {amount_of(3, "plate"), amount_of(1, "gear")}, {plate, gear})
      local t = stage("t", {amount_of(2, "u"), amount_of(1, "plate")}, {u, stage("plate", {amount_of(1, "ore")}, {})})

      local plans = planner.plan_tree{rate_per_minute = 60, lane_items_per_minute = 450, root = t}

      assert.are.equal(1, plans.plan.machines) -- 60 t
      assert.are.equal(2, plans.suppliers[1].plan.machines) -- 120 u
      assert.are.equal(6, plans.suppliers[1].suppliers[1].plan.machines) -- 360 plates for the u
      assert.are.equal(2, plans.suppliers[1].suppliers[2].plan.machines) -- 120 gears for the u
      assert.are.equal(1, plans.suppliers[2].plan.machines) -- 60 plates for the t
    end)
  end)

  describe("plan_tree, for a recipe with one made ingredient and a raw one", function()
    -- A pole: 1 wood and 2 cables make 2 poles, in 0.5 s. An assembler (speed 0.5) crafts 60 times a minute:
    -- 60 wood and 120 cables in, 120 poles out. Cables: 1 plate to 2 cables, 120 cables is one assembler.
    local pole_recipe = {
      energy = 0.5, ingredients = {amount_of(1, "wood"), amount_of(2, "copper-cable")}, products = {amount_of(2, "pole")},
    }
    local cable_recipe = {energy = 0.5, ingredients = {amount_of(1, "copper-plate")}, products = {amount_of(2, "copper-cable")}}
    local copper_recipe = {energy = 3.2, ingredients = {amount_of(1, "copper-ore")}, products = {amount_of(1, "copper-plate")}}

    local function tree_of(product, recipe, machine_speed, suppliers, fuel)
      return {stage = {product = product, recipe = recipe, machine_speed = machine_speed, fuel = fuel}, suppliers = suppliers}
    end

    local function cables()
      return tree_of("copper-cable", cable_recipe, 0.5, {tree_of("copper-plate", copper_recipe, 1, {}, "coal")})
    end

    local function poles(rate, recipe)
      return {
        rate_per_minute = rate, lane_items_per_minute = 450,
        root = tree_of("pole", recipe or pole_recipe, 0.5, {cables()}),
      }
    end

    it("takes the raw item and the made one on a lane each, in the recipe's order", function()
      local plans = planner.plan_tree(poles(60))

      assert.are.same({"wood", "copper-cable"}, plans.plan.lanes)
    end)

    it("builds the machines of the made ingredient for its share of the rate", function()
      local plans = planner.plan_tree(poles(60))

      assert.are.equal(1, plans.plan.machines) -- 60 poles is 30 crafts, half an assembler
      assert.are.equal(1, plans.suppliers[1].plan.machines) -- 60 cables, half an assembler
      assert.are.equal(2, plans.suppliers[1].suppliers[1].plan.machines) -- 30 plates / 18.75 = 1.6
    end)

    it("sizes the made ingredient the same when the raw item comes after it in the recipe", function()
      local cable_first = {
        energy = 0.5, ingredients = {amount_of(2, "copper-cable"), amount_of(1, "wood")}, products = {amount_of(2, "pole")},
      }

      local plans = planner.plan_tree(poles(60, cable_first))

      assert.are.same({"copper-cable", "wood"}, plans.plan.lanes)
      assert.are.equal(2, plans.suppliers[1].suppliers[1].plan.machines) -- 30 plates / 18.75 = 1.6
    end)

    it("shows the stage eating the raw item as well", function()
      local plans = planner.plan_tree(poles(60))

      -- 2 copper furnaces make 37.5 plates, which is 75 cables and so 37.5 crafts of 1 wood and 2 cables
      assert.are.same({{name = "wood", per_minute = 37.5}, {name = "copper-cable", per_minute = 75}}, plans.plan.inputs)
    end)

    it("refuses a rate that the lane of the raw item cannot carry", function()
      local hungry = {
        energy = 0.5, ingredients = {amount_of(10, "wood"), amount_of(2, "copper-cable")}, products = {amount_of(2, "pole")},
      }

      local plans, reason, max_rate = planner.plan_tree(poles(100, hungry))

      assert.is_nil(plans)
      assert.are.equal("rate-too-high", reason)
      assert.near(90, max_rate, 1e-6) -- a lane carries 450 wood, 10 for each craft of 2 poles
    end)

    it("refuses a rate that the lane of the made ingredient cannot carry", function()
      local plans, reason, max_rate = planner.plan_tree(poles(1000))

      assert.is_nil(plans)
      assert.are.equal("rate-too-high", reason)
      assert.near(450, max_rate, 1e-6) -- a lane carries 450 cables, 2 for each craft of 2 poles
    end)
  end)

  -- A gadget is made in an assembler of speed 0.5 in 0.5 s, so 60 times a minute: one machine eats 60 times the
  -- amount of each ingredient a minute, at full speed. Each ingredient is made from its own ore by a furnace-like
  -- machine (speed 1, 1 s: 60 a minute). The next two groups of examples are about the gadget with three or more
  -- ingredients, whose machines take from more than one input belt.
  local function made_from_ore(product)
    local recipe = {energy = 1, ingredients = {amount_of(1, product .. "-ore")}, products = {amount_of(1, product)}}
    return {stage = {product = product, recipe = recipe, machine_speed = 1, fuel = "coal"}, suppliers = {}}
  end

  -- The request for gadgets from `ingredients`, each made by its own stage except the raw ones.
  local function gadgets(rate, ingredients, inserters, raw)
    local suppliers = {}
    for _, ingredient in ipairs(ingredients) do
      if not (raw and raw[ingredient.name]) then
        suppliers[#suppliers + 1] = made_from_ore(ingredient.name)
      end
    end
    local recipe = {energy = 0.5, ingredients = ingredients, products = {amount_of(1, "gadget")}}
    return {
      rate_per_minute = rate, lane_items_per_minute = 450,
      root = {stage = {product = "gadget", recipe = recipe, machine_speed = 0.5, inserters = inserters}, suppliers = suppliers},
    }
  end

  local circuit_gear_plate = {amount_of(1, "circuit"), amount_of(1, "gear"), amount_of(1, "plate")}

  describe("plan_tree, for a recipe with three or more ingredients, which take woven input belts", function()
    -- A plain inserter moves 50.4 items a minute. A machine has one input slot less than its size on a single belt, and as
    -- many as its size when its belts are woven (see scripts/weave.lua), which the planner shares between the belts, at least
    -- one each.
    local three_slots = {items_per_minute = 50.4, max_input = 2, max_woven_input = 3, max_output = 2}

    it("splits the ingredients between the belts so that the machine runs fastest, on as few belts as it takes", function()
      -- Every item is 60 a minute for one machine, 180 in all, and three plain inserters move 151.2: 0.84 however the three
      -- ingredients are split into two belts (two slots for the pair and one for the other, or one and two) or into three
      -- belts of one slot each. So two belts, with the last ingredient of the recipe alone on belt b.
      local plans = planner.plan_tree(gadgets(50.4, circuit_gear_plate, three_slots))

      assert.are.same({a = {"circuit", "gear"}, b = {"plate"}}, plans.plan.belts)
    end)

    it("shares the three slots of its woven belts: two inserters on the belt of the two ingredients, one on the other", function()
      local plans = planner.plan_tree(gadgets(50.4, circuit_gear_plate, three_slots))

      assert.are.same({3, {a = 2, b = 1}}, {plans.plan.input_inserters, plans.plan.belt_inserters})
    end)

    it("builds the machines that the belts allow", function()
      -- One machine runs at 0.84 of 60 crafts a minute: 50.4 gadgets a minute. 100 / 50.4 = 1.98.
      local plans = planner.plan_tree(gadgets(100, circuit_gear_plate, three_slots))

      assert.are.equal(2, plans.plan.machines)
    end)

    it("takes every ingredient on a lane of its own, in the recipe's order", function()
      local plans = planner.plan_tree(gadgets(50.4, circuit_gear_plate, three_slots))

      assert.are.same({"circuit", "gear", "plate"}, plans.plan.lanes)
    end)

    describe("the output belt of the root stage when the belts of the input side are woven", function()
      -- A craft makes 3 gadgets from a circuit, a gear and a plate, 120 crafts a minute: 120 of each ingredient and 360 gadgets.
      -- Three plain inserters on the input side move 151.2 and two on the output side 100.8, so the machine runs at 100.8 / 360
      -- = 0.28: 33.6 of each ingredient (two inserters for the circuit and the gear on belt a, one for the plate on belt b: all
      -- three slots) and 100.8 gadgets on two inserters. A side of woven belts takes no row of poles, the poles stand
      -- beside the belts, so the output belt winds and the two lanes of 450 carry 900 gadgets a minute, not the 450 of one lane.
      local limits = {items_per_minute = 50.4, max_input = 2, max_woven_input = 3, max_output = 2, machine_size = 3}

      it("winds, so that the product rides both lanes", function()
        local recipe = {
          energy = 0.5, products = {amount_of(3, "gadget")},
          ingredients = {amount_of(1, "circuit"), amount_of(1, "gear"), amount_of(1, "plate")},
        }
        local request = {
          rate_per_minute = 1, lane_items_per_minute = 450,
          root = {
            stage = {product = "gadget", recipe = recipe, machine_speed = 1, inserters = limits},
            suppliers = {made_from_ore("circuit"), made_from_ore("gear"), made_from_ore("plate")},
          },
        }

        assert.near(900, planner.max_tree_rate(request), 1e-6)
      end)
    end)

    describe("with fast inserters, which move 144 a minute", function()
      local fast_three_slots = {items_per_minute = 50.4, fast_items_per_minute = 144, max_input = 2, max_woven_input = 3, max_output = 2}

      it("puts two ingredients on belt a and the one that is eaten last on belt b", function()
        -- Circuit and gear on belt a: 120 a minute, one fast inserter. Plate alone on belt b: 60 a minute, one more. All
        -- of them fit, so the machine runs flat out, on as few belts as it takes (every other split is as fast, and a third
        -- belt would be one more).
        local plans = planner.plan_tree(gadgets(60, circuit_gear_plate, fast_three_slots))

        assert.are.same({a = {"circuit", "gear"}, b = {"plate"}}, plans.plan.belts)
      end)

      it("runs the machine flat out, with one fast inserter on each belt", function()
        local plans = planner.plan_tree(gadgets(60, circuit_gear_plate, fast_three_slots))

        assert.are.same({1, 60, 2, true, {a = 1, b = 1}}, {plans.plan.machines, plans.plan.output_per_minute, plans.plan.input_inserters, plans.plan.input_fast, plans.plan.belt_inserters})
      end)

      it("uses plain inserters for a machine that needs no more, which let it make what they move", function()
        -- 18 gadgets a minute is 0.3 of a machine: 36 circuits and gears on belt a and 18 plates on belt b, which one plain
        -- inserter on each moves (50.4). They let a machine make 50.4 / 120 = 0.42 of its 60 crafts a minute: 25.2.
        local plans = planner.plan_tree(gadgets(18, circuit_gear_plate, fast_three_slots))

        assert.are.same({false, {a = 1, b = 1}}, {plans.plan.input_fast, plans.plan.belt_inserters})
        assert.near(25.2, plans.plan.output_per_minute, 1e-9)
      end)
    end)

    it("gives the two inserters to the belt of the ingredients that are eaten most when they are much heavier than the other", function()
      -- 3 circuits, 5 gears and 9 plates a craft: 180, 300 and 540 a minute. The circuit and the plate on belt a (720) with
      -- two plain inserters, the gear alone on belt b (300) with one: min(100.8 / 720, 50.4 / 300) = 0.14, 8.4 crafts a minute.
      -- The best of the splits into two belts, and better than the 0.093 of one inserter for each of three belts.
      local heavy = {amount_of(3, "circuit"), amount_of(5, "gear"), amount_of(9, "plate")}

      local plans = planner.plan_tree(gadgets(30, heavy, three_slots))

      assert.are.same({{a = {"circuit", "plate"}, b = {"gear"}}, {a = 2, b = 1}}, {plans.plan.belts, plans.plan.belt_inserters})
      assert.are.equal(4, plans.plan.machines) -- 30 / 8.4 = 3.57
    end)

    it("puts a heavy first ingredient alone on belt b, with the lighter ones sharing belt a", function()
      -- 9 plates a craft: 540 a minute, the gear and the circuit 60 each. The plate alone with two inserters: 100.8 / 540 =
      -- 0.187, and the other two on one: 50.4 / 120 = 0.42, so 0.187. The plate with a light one on a belt with two inserters
      -- is worse, 100.8 / 600 = 0.168. The plate alone is as fast on belt a as on belt b, and belt b gets the fewer ingredients.
      local plate_first = {amount_of(9, "plate"), amount_of(1, "gear"), amount_of(1, "circuit")}

      local plans = planner.plan_tree(gadgets(12, plate_first, three_slots))

      assert.are.same({{a = {"gear", "circuit"}, b = {"plate"}}, {a = 1, b = 2}}, {plans.plan.belts, plans.plan.belt_inserters})
    end)

    it("puts a heavy first ingredient alone on belt b for five ingredients, with the pairs of the others on belts a and c", function()
      -- 9 of the first ingredient a craft: 540 a minute, the others 60 each. With one inserter on each of three belts it is
      -- 50.4 / 540 = 0.093 alone, and 50.4 / 600 = 0.084 with a light one. The heavy one alone is as fast on belt a or b (a
      -- split with belt c before belt b is only the same split with the two letters swapped), and belt b gets the fewer
      -- ingredients, the others in pairs on belts a and c, in the recipe's order.
      local heavy_first = {amount_of(9, "one"), amount_of(1, "two"), amount_of(1, "three"), amount_of(1, "four"), amount_of(1, "five")}

      local plans = planner.plan_tree(gadgets(5, heavy_first, three_slots))

      assert.are.same({a = {"two", "three"}, b = {"one"}, c = {"four", "five"}}, plans.plan.belts)
    end)

    it("puts the fewest ingredients on belt b, the last ones in the recipe, when no inserter limits the machine", function()
      local plans = planner.plan_tree(gadgets(60, circuit_gear_plate, nil))

      assert.are.same({a = {"circuit", "gear"}, b = {"plate"}}, plans.plan.belts)
      assert.are.same({2, {a = 1, b = 1}}, {plans.plan.input_inserters, plans.plan.belt_inserters})
    end)

    it("puts two ingredients on each belt when there are four, rather than a third belt that is no faster", function()
      -- Two ingredients of 60 on a belt with one inserter: 50.4 / 120 = 0.42, and so with the pair on one belt and one slot for
      -- each of three belts (a pair, and two of one), 0.42 too: two belts is fewer.
      local four = {amount_of(1, "circuit"), amount_of(1, "gear"), amount_of(1, "plate"), amount_of(1, "stick")}

      local plans = planner.plan_tree(gadgets(20, four, three_slots))

      assert.are.same({a = {"circuit", "gear"}, b = {"plate", "stick"}}, plans.plan.belts)
    end)

    it("never puts more than two ingredients on belt a, even where one heavy ingredient alone would be faster", function()
      -- 9 plates a craft: 540 a minute, the other three 60 each. The plate and a light one on a belt with two inserters:
      -- 100.8 / 600 = 0.168, the other pair on a belt with one: 50.4 / 120 = 0.42, so 0.168. The plate alone on a belt would
      -- leave the three lights for two belts, which hold two each, so three belts in all with one inserter each, and the plate
      -- 50.4 / 540 = 0.093 at the most. The later ones in the recipe go on belt b.
      local heavy_last = {amount_of(1, "gear"), amount_of(1, "circuit"), amount_of(1, "stick"), amount_of(9, "plate")}

      local plans = planner.plan_tree(gadgets(5, heavy_last, three_slots))

      assert.are.same({a = {"gear", "circuit"}, b = {"stick", "plate"}}, plans.plan.belts)
    end)

    it("never puts more than two ingredients on belt b, even where one heavy raw ingredient alone on belt a would be faster", function()
      -- 9 wood a craft: 540 a minute, raw, so on belt a. Wood alone on belt a with three lights on belt b would need a third
      -- belt, and run at 50.4 / 540 = 0.093 on one inserter. Wood and a light one on belt a with two inserters: 100.8 / 600 =
      -- 0.168, the best left; the first light one in the recipe goes with the wood.
      local wood_first = {amount_of(9, "wood"), amount_of(1, "gear"), amount_of(1, "circuit"), amount_of(1, "stick")}

      local plans = planner.plan_tree(gadgets(5, wood_first, three_slots, {wood = true}))

      assert.are.same({a = {"wood", "gear"}, b = {"circuit", "stick"}}, plans.plan.belts)
    end)

    it("gives a stage with two ingredients no belts to weave when no inserter limits the machine", function()
      local plans = planner.plan_tree(gadgets(20, {amount_of(1, "plate"), amount_of(1, "cable")}, nil))

      assert.is_nil(plans.plan.belt_inserters)
    end)

    it("keeps a raw ingredient on belt a, even where the speed would put it on belt b", function()
      -- 9 wood a craft: 540 a minute. Alone on belt b it would be faster, but a raw belt can only be side-loaded onto
      -- belt a. Wood alone on belt a with two inserters, gear and circuit on belt b with one: min(100.8 / 540, 50.4 / 120) =
      -- 0.187, the best left: 11.2 gadgets a minute for a machine, so 12 a minute is a whole machine and a part.
      local with_wood = {amount_of(9, "wood"), amount_of(1, "gear"), amount_of(1, "circuit")}

      local plans = planner.plan_tree(gadgets(12, with_wood, three_slots, {wood = true}))

      assert.are.same({{a = {"wood"}, b = {"gear", "circuit"}}, {a = 2, b = 1}}, {plans.plan.belts, plans.plan.belt_inserters})
    end)

    it("keeps the two ingredients of a stage on belt a", function()
      local plans = planner.plan_tree(gadgets(20, {amount_of(1, "plate"), amount_of(1, "cable")}, three_slots))

      assert.are.same({a = {"plate", "cable"}, b = {}}, plans.plan.belts)
      assert.is_nil(plans.plan.belt_inserters)
    end)

    it("takes only the inserters a machine needs when it is used for a small share of its time", function()
      -- The same recipe, but only 5 gadgets a minute: a tenth of a machine, which needs one inserter for belt a (a pair
      -- of 10 a minute) and one for belt b (5 a minute) where it has three slots.
      local plans = planner.plan_tree(gadgets(5, circuit_gear_plate, three_slots))

      assert.are.same({2, {a = 1, b = 1}}, {plans.plan.input_inserters, plans.plan.belt_inserters})
    end)

    describe("five or six ingredients, which take a third belt", function()
      local five = {amount_of(1, "one"), amount_of(1, "two"), amount_of(1, "three"), amount_of(1, "four"), amount_of(1, "five")}
      local six = {amount_of(1, "one"), amount_of(1, "two"), amount_of(1, "three"), amount_of(1, "four"), amount_of(1, "five"), amount_of(1, "six")}

      it("puts five ingredients on three belts, two on each of the first two, in the recipe's order", function()
        -- Two ingredients of 60 on a belt with one inserter: 50.4 / 120 = 0.42, whichever way the five are split into belts
        -- of two, two and one.
        local plans = planner.plan_tree(gadgets(20, five, three_slots))

        assert.are.same({a = {"one", "two"}, b = {"three", "four"}, c = {"five"}}, plans.plan.belts)
      end)

      it("puts six ingredients on three belts of two", function()
        local plans = planner.plan_tree(gadgets(20, six, three_slots))

        assert.are.same({a = {"one", "two"}, b = {"three", "four"}, c = {"five", "six"}}, plans.plan.belts)
      end)

      it("gives each belt one inserter, the three slots there are", function()
        local plans = planner.plan_tree(gadgets(20, six, three_slots))

        assert.are.same({3, {a = 1, b = 1, c = 1}}, {plans.plan.input_inserters, plans.plan.belt_inserters})
      end)

      it("builds the machines that three belts of two ingredients allow", function()
        -- One machine runs at 50.4 / 120 = 0.42 of 60 crafts a minute: 25.2 gadgets a minute. 100 / 25.2 = 3.97.
        local plans = planner.plan_tree(gadgets(100, six, three_slots))

        assert.are.equal(4, plans.plan.machines)
      end)

      it("keeps the raw ingredient on belt a with five ingredients", function()
        local plans = planner.plan_tree(gadgets(20, {amount_of(1, "wood"), amount_of(1, "two"), amount_of(1, "three"), amount_of(1, "four"), amount_of(1, "five")}, three_slots, {wood = true}))

        assert.are.same({"wood", "two"}, plans.plan.belts.a)
      end)

      it("refuses seven ingredients, which three belts of two lanes do not hold", function()
        local seven = {amount_of(1, "a1"), amount_of(1, "a2"), amount_of(1, "a3"), amount_of(1, "a4"), amount_of(1, "a5"), amount_of(1, "a6"), amount_of(1, "a7")}

        local plans, reason = planner.plan_tree(gadgets(20, seven, three_slots))

        assert.is_nil(plans)
        assert.are.equal("unsupported-recipe", reason)
      end)

      it("refuses five ingredients when the limits allow two belts, whose four lanes do not hold them", function()
        local two_belts = {items_per_minute = 50.4, max_input = 2, max_woven_input = 3, most_belts = 2, max_output = 2}

        local plans, reason = planner.plan_tree(gadgets(20, five, two_belts))

        assert.is_nil(plans)
        assert.are.equal("unsupported-recipe", reason)
      end)

      it("still takes four ingredients on two belts when the limits allow two", function()
        local two_belts = {items_per_minute = 50.4, max_input = 2, max_woven_input = 3, most_belts = 2, max_output = 2}
        local four = {amount_of(1, "circuit"), amount_of(1, "gear"), amount_of(1, "plate"), amount_of(1, "stick")}

        local plans = planner.plan_tree(gadgets(20, four, two_belts))

        assert.are.same({a = {"circuit", "gear"}, b = {"plate", "stick"}}, plans.plan.belts)
      end)
    end)

    it("gives belt b plain inserters, not long-handed ones, when the limits give slots for woven belts, whatever a long-handed inserter moves", function()
      -- The circuit and the gear on belt a (120 a minute) get two plain inserters and the plate on belt b (60) one, 0.84 for
      -- each (100.8 / 120, 50.4 / 60): all three slots hold plain inserters, and none is long-handed.
      local with_long_figure = {items_per_minute = 50.4, long_items_per_minute = 72, max_input = 2, max_woven_input = 3, max_output = 2}

      local plans = planner.plan_tree(gadgets(50.4, circuit_gear_plate, with_long_figure))

      assert.are.same({3, 0, {a = 2, b = 1}}, {plans.plan.input_inserters, plans.plan.long_inserters, plans.plan.belt_inserters})
    end)

    it("refuses five ingredients when its machine has only two slots for woven belts, which three belts need three of", function()
      local two_slots = {items_per_minute = 50.4, max_input = 2, max_woven_input = 2, max_output = 2}
      local five = {amount_of(1, "one"), amount_of(1, "two"), amount_of(1, "three"), amount_of(1, "four"), amount_of(1, "five")}

      local plans, reason = planner.plan_tree(gadgets(20, five, two_slots))

      assert.is_nil(plans)
      assert.are.equal("unsupported-recipe", reason)
    end)

    it("gives each of two belts one slot when its machine has two slots for woven belts", function()
      -- Every split is 0.42: 50.4 / 120 for a pair on one inserter. 100 / (60 * 0.42) = 3.97 machines.
      local two_slots = {items_per_minute = 50.4, max_input = 2, max_woven_input = 2, max_output = 2}

      local plans = planner.plan_tree(gadgets(100, circuit_gear_plate, two_slots))

      assert.are.same({4, {a = 1, b = 1}}, {plans.plan.machines, plans.plan.belt_inserters})
    end)

    it("refuses a rate that the lane of one ingredient cannot carry, whichever belt it is on", function()
      -- 10 plates a craft: 600 a minute for one machine at full speed, and a lane carries 450, so 0.75 of a machine:
      -- 45 gadgets a minute.
      local plates = {amount_of(1, "circuit"), amount_of(1, "gear"), amount_of(10, "plate")}

      local plans, reason, max_rate = planner.plan_tree(gadgets(100, plates, nil))

      assert.is_nil(plans)
      assert.are.equal("rate-too-high", reason)
      assert.near(45, max_rate, 1e-6)
    end)

  end)

  describe("plan_tree, for a recipe with three or four ingredients, whose belts are not woven: a second belt for long-handed inserters", function()
    -- The same gadgets, for a machine whose limits give no slots for woven belts (`max_woven_input`): a plain inserter moves
    -- 50.4 items a minute and a long-handed one 72, and a machine has two input slots. The plain inserters take from belt a,
    -- the long-handed ones from belt b, one column further out, over belt a.
    local two_slots = {items_per_minute = 50.4, long_items_per_minute = 72, max_input = 2, max_output = 2}

    it("splits the ingredients between the belts so that the machine runs fastest", function()
      -- Each belt carries 60 of each item. Circuit alone on belt a: 50.4 / 60 = 0.84 and 72 / 120 = 0.6, so 0.6.
      -- Circuit and gear on belt a: 50.4 / 120 = 0.42. The first is faster.
      local plans = planner.plan_tree(gadgets(36, circuit_gear_plate, two_slots))

      assert.are.same({a = {"circuit"}, b = {"gear", "plate"}}, plans.plan.belts)
    end)

    it("gives a machine one plain and one long-handed inserter when it has two input slots", function()
      local plans = planner.plan_tree(gadgets(36, circuit_gear_plate, two_slots))

      assert.are.same({1, 1, nil}, {plans.plan.input_inserters, plans.plan.long_inserters, plans.plan.belt_inserters})
    end)

    it("builds the machines that the slower belt allows", function()
      -- One machine runs at 0.6 of 60 crafts a minute: 36 gadgets a minute. 100 / 36 = 2.78.
      local plans = planner.plan_tree(gadgets(100, circuit_gear_plate, two_slots))

      assert.are.equal(3, plans.plan.machines)
    end)

    it("takes every ingredient on a lane of its own, in the recipe's order", function()
      local plans = planner.plan_tree(gadgets(36, circuit_gear_plate, two_slots))

      assert.are.same({"circuit", "gear", "plate"}, plans.plan.lanes)
    end)

    describe("the output belt of the root stage when the long-handed inserters fill the input side", function()
      -- Circuit and gear on belt a (one fast inserter), plate on belt b: 120 a minute, two long-handed inserters. The three
      -- slots are full, which takes a row of poles between the machines, and a winding belt has no room for that: the 180 a
      -- minute that two fast inserters move from a machine ride one lane, 450 / 180 machines' worth.
      local limits = {items_per_minute = 50.4, long_items_per_minute = 72, fast_items_per_minute = 144, max_input = 3, max_output = 3, machine_size = 3}

      it("is a plain belt, with the product on one lane", function()
        local recipe = {
          energy = 0.5, products = {amount_of(3, "gadget")},
          ingredients = {amount_of(1, "circuit"), amount_of(1, "gear"), amount_of(2, "plate")},
        }
        local request = {
          rate_per_minute = 1, lane_items_per_minute = 450,
          root = {
            stage = {product = "gadget", recipe = recipe, machine_speed = 0.5, inserters = limits},
            suppliers = {made_from_ore("circuit"), made_from_ore("gear"), made_from_ore("plate")},
          },
        }

        assert.near(450, planner.max_tree_rate(request), 1e-6)
      end)
    end)

    describe("with fast inserters, which beat the long-handed ones", function()
      -- A fast inserter moves 144 a minute, more than the long-handed one's 72. A machine eats 60 of each ingredient.
      local fast_two_slots = {items_per_minute = 50.4, long_items_per_minute = 72, fast_items_per_minute = 144, max_input = 2, max_output = 2}

      it("puts two ingredients on belt a, for the fast inserter, and the one that is eaten last on belt b", function()
        -- Circuit and gear on belt a: 120 a minute, one fast inserter. Plate alone on belt b: 60 of the 72 a minute. Both
        -- fit, so the machine runs flat out. (With plain inserters the circuit was alone on belt a, 50.4 a minute.)
        local plans = planner.plan_tree(gadgets(60, circuit_gear_plate, fast_two_slots))

        assert.are.same({a = {"circuit", "gear"}, b = {"plate"}}, plans.plan.belts)
      end)

      it("runs the machine flat out, with one fast inserter and one long-handed one on its input side", function()
        local plans = planner.plan_tree(gadgets(60, circuit_gear_plate, fast_two_slots))

        assert.are.same({1, 60, 1, true, 1}, {plans.plan.machines, plans.plan.output_per_minute, plans.plan.input_inserters, plans.plan.input_fast, plans.plan.long_inserters})
      end)

      it("keeps the inserter of belt a plain when only belt b is more than a plain inserter moves, which a long-handed one does", function()
        -- 0.4 circuits, 0.4 plates and 1 gear a craft: 24, 24 and 60 a minute. The circuit and the plate on belt a, 48 a
        -- minute, which one plain inserter moves (50.4), and the gear alone on belt b, 60 a minute, more than a plain inserter
        -- moves and less than the long-handed one's 72: the machine runs flat out, and no inserter is a fast one.
        local light_pair = {amount_of(0.4, "circuit"), amount_of(0.4, "plate"), amount_of(1, "gear")}

        local plans = planner.plan_tree(gadgets(60, light_pair, fast_two_slots))

        assert.are.same({{a = {"circuit", "plate"}, b = {"gear"}}, false, 1, 1}, {plans.plan.belts, plans.plan.input_fast, plans.plan.input_inserters, plans.plan.long_inserters})
      end)
    end)

    it("puts the ingredient that is eaten most alone on the long-handed belt when it is much heavier than the others", function()
      -- 3 circuits, 5 gears and 9 plates a craft: 180, 300 and 540 a minute. Plate alone on belt b: 72 / 540 = 0.133,
      -- circuit and gear on belt a: 50.4 / 480 = 0.105, so 0.105 (6.3 crafts a minute). Any other split is slower.
      local heavy = {amount_of(3, "circuit"), amount_of(5, "gear"), amount_of(9, "plate")}

      local plans = planner.plan_tree(gadgets(30, heavy, two_slots))

      assert.are.same({a = {"circuit", "gear"}, b = {"plate"}}, plans.plan.belts)
      assert.are.equal(5, plans.plan.machines) -- 30 / 6.3 = 4.76
    end)

    it("puts two ingredients on each belt when there are four", function()
      local four = {amount_of(1, "circuit"), amount_of(1, "gear"), amount_of(1, "plate"), amount_of(1, "stick")}

      local plans = planner.plan_tree(gadgets(20, four, two_slots))

      assert.are.same({a = {"circuit", "gear"}, b = {"plate", "stick"}}, plans.plan.belts)
    end)

    it("never puts more than two ingredients on belt a, even where one heavy ingredient alone on belt b would be faster", function()
      -- 9 plates a craft: 540 a minute. Plate alone on belt b: 72 / 540 = 0.133 with three lights on belt a (0.28),
      -- which belt a cannot hold. Plate and stick on belt b: 72 / 600 = 0.12, gear and circuit on belt a: 0.42.
      local heavy_last = {amount_of(1, "gear"), amount_of(1, "circuit"), amount_of(1, "stick"), amount_of(9, "plate")}

      local plans = planner.plan_tree(gadgets(5, heavy_last, two_slots))

      assert.are.same({a = {"gear", "circuit"}, b = {"stick", "plate"}}, plans.plan.belts)
    end)

    it("never puts more than two ingredients on belt b, even where one heavy raw ingredient alone on belt a would be faster", function()
      -- 9 wood a craft: 540 a minute, raw, so on belt a. Wood alone on belt a with three lights on belt b would run at
      -- 50.4 / 540 = 0.093, but belt b cannot hold three. Wood and gear on belt a: 50.4 / 600 = 0.084, the best left.
      local wood_first = {amount_of(9, "wood"), amount_of(1, "gear"), amount_of(1, "circuit"), amount_of(1, "stick")}

      local plans = planner.plan_tree(gadgets(5, wood_first, two_slots, {wood = true}))

      assert.are.same({a = {"wood", "gear"}, b = {"circuit", "stick"}}, plans.plan.belts)
    end)

    it("gives a stage with two ingredients no long-handed inserter when no inserter limits the machine", function()
      local plans = planner.plan_tree(gadgets(20, {amount_of(1, "plate"), amount_of(1, "cable")}, nil))

      assert.are.equal(0, plans.plan.long_inserters)
    end)

    it("keeps a raw ingredient on belt a, even where the speed would put it on belt b", function()
      -- 9 wood a craft: 540 a minute, raw, so on belt a. Alone on belt b it would run at 72 / 540 = 0.133, but a raw belt can
      -- only be side-loaded onto belt a. Wood alone on belt a, gear and circuit on belt b: 50.4 / 540 = 0.093 is the best left.
      local with_wood = {amount_of(9, "wood"), amount_of(1, "gear"), amount_of(1, "circuit")}

      local plans = planner.plan_tree(gadgets(5, with_wood, two_slots, {wood = true}))

      assert.are.same({a = {"wood"}, b = {"gear", "circuit"}}, plans.plan.belts)
    end)

    it("keeps the two ingredients of a stage on belt a", function()
      local plans = planner.plan_tree(gadgets(20, {amount_of(1, "plate"), amount_of(1, "cable")}, two_slots))

      assert.are.same({a = {"plate", "cable"}, b = {}}, plans.plan.belts)
      assert.are.equal(0, plans.plan.long_inserters)
    end)

    it("refuses a stage with more than four ingredients", function()
      local five = {amount_of(1, "a"), amount_of(1, "b"), amount_of(1, "c"), amount_of(1, "d"), amount_of(1, "e")}

      local plans, reason = planner.plan_tree(gadgets(20, five, two_slots))

      assert.is_nil(plans)
      assert.are.equal("unsupported-recipe", reason)
    end)

    it("refuses five ingredients even where the limits allow three belts, since a long-handed inserter reaches only a second", function()
      local three_belts = {items_per_minute = 50.4, long_items_per_minute = 72, max_input = 3, most_belts = 3, max_output = 2}
      local five = {amount_of(1, "a"), amount_of(1, "b"), amount_of(1, "c"), amount_of(1, "d"), amount_of(1, "e")}

      local plans, reason = planner.plan_tree(gadgets(20, five, three_belts))

      assert.is_nil(plans)
      assert.are.equal("unsupported-recipe", reason)
    end)

    it("refuses a stage with three ingredients when its machine has only one input slot", function()
      local one_slot = {items_per_minute = 50.4, long_items_per_minute = 72, max_input = 1, max_output = 2}

      local plans, reason = planner.plan_tree(gadgets(20, circuit_gear_plate, one_slot))

      assert.is_nil(plans)
      assert.are.equal("unsupported-recipe", reason)
    end)

    it("gives the belt that needs them more of three input slots", function()
      -- Circuit and gear on belt a (120 a minute), plate on belt b (60): two plain inserters give 100.8 / 120 = 0.84,
      -- one long-handed inserter 72 / 60 is plenty. One plain and two long-handed would also give 0.84, and the
      -- tie goes to the fewest ingredients on belt b.
      local three_slots = {items_per_minute = 50.4, long_items_per_minute = 72, max_input = 3, max_output = 2}

      local plans = planner.plan_tree(gadgets(50.4, circuit_gear_plate, three_slots))

      assert.are.same({a = {"circuit", "gear"}, b = {"plate"}}, plans.plan.belts)
      assert.are.same({2, 1}, {plans.plan.input_inserters, plans.plan.long_inserters})
      assert.are.equal(1, plans.plan.machines) -- 60 * 0.84 = 50.4 a minute
    end)

    it("takes only the inserters a machine needs when it is used for a small share of its time", function()
      -- The same recipe with three slots, but only 5 gadgets a minute: a tenth of a machine, which needs one inserter
      -- for belt a (12 a minute) and one for belt b (6 a minute).
      local three_slots = {items_per_minute = 50.4, long_items_per_minute = 72, max_input = 3, max_output = 2}

      local plans = planner.plan_tree(gadgets(5, circuit_gear_plate, three_slots))

      assert.are.same({1, 1}, {plans.plan.input_inserters, plans.plan.long_inserters})
    end)

    it("gives a machine all the long-handed inserters its slots allow when belt b is the heavy one", function()
      -- Four slots, and 1 circuit, 6 gears and 6 plates a craft: 60, 360 and 360 a minute. Circuit alone on belt a
      -- (50.4 / 60 = 0.84) and the heavy pair on belt b with three long-handed inserters (216 / 720 = 0.3) is the
      -- fastest split; 0.3 of 60 crafts is 18 gadgets a minute, and belt b then moves 216 a minute.
      local four_slots = {items_per_minute = 50.4, long_items_per_minute = 72, max_input = 4, max_output = 2}
      local heavy_pair = {amount_of(1, "circuit"), amount_of(6, "gear"), amount_of(6, "plate")}

      local plans = planner.plan_tree(gadgets(18, heavy_pair, four_slots))

      assert.are.same({a = {"circuit"}, b = {"gear", "plate"}}, plans.plan.belts)
      assert.are.same({1, 3}, {plans.plan.input_inserters, plans.plan.long_inserters})
    end)

    it("takes fewer long-handed inserters when the machine is used for part of its time", function()
      -- The same machine used for 5 of its 18 gadgets a minute: belt b then moves 60 a minute, which one long-handed
      -- inserter (72) carries but one plain inserter (50.4) would not.
      local four_slots = {items_per_minute = 50.4, long_items_per_minute = 72, max_input = 4, max_output = 2}
      local heavy_pair = {amount_of(1, "circuit"), amount_of(6, "gear"), amount_of(6, "plate")}

      local plans = planner.plan_tree(gadgets(5, heavy_pair, four_slots))

      assert.are.equal(1, plans.plan.long_inserters)
    end)

    it("takes the speed of a plain inserter for a long-handed one when the limits give none", function()
      -- Everything moves 50.4 a minute: circuit and gear on belt a, 50.4 / 120 = 0.42, 25.2 gadgets a minute. 100 / 25.2 = 3.97.
      local plain_only = {items_per_minute = 50.4, max_input = 2, max_output = 2}

      local plans = planner.plan_tree(gadgets(100, circuit_gear_plate, plain_only))

      assert.are.equal(4, plans.plan.machines)
    end)
  end)

  describe("plan, with fast inserters", function()
    -- A machine of speed 1 that crafts every second eats `flow` items of its one ingredient a minute and makes as many of its
    -- product. One plain inserter moves 50.4 a minute, one fast inserter 144 (so two move 288 and three 432). The planner
    -- takes the slots it is given: the generator gives two to a 3x3 machine (see `layout.max_input_inserters`), and these
    -- specs give three to show the whole ladder.
    local limits = {items_per_minute = 50.4, fast_items_per_minute = 144, max_input = 3, max_output = 3, machine_size = 3}

    local function recipe_moving(flow)
      return {energy = 1, ingredients = {amount_of(flow / 60, "plate")}, products = {amount_of(flow / 60, "part")}}
    end

    local function plan_moving(flow, inserters)
      return planner.plan{
        product = "part", rate_per_minute = flow, recipe = recipe_moving(flow), machine_speed = 1,
        lane_items_per_minute = 450, inserters = inserters or limits,
      }
    end

    local function ladder(plan)
      return {plan.input_inserters, plan.input_fast, plan.output_inserters, plan.output_fast}
    end

    it("uses one plain inserter on each side while that moves what the machine eats and makes", function()
      assert.are.same({1, false, 1, false}, ladder(plan_moving(48)))
    end)

    it("keeps one plain inserter when the flow is exactly what it moves", function()
      assert.are.same({1, false, 1, false}, ladder(plan_moving(50.4)))
    end)

    it("uses one fast inserter when one plain inserter is not enough", function()
      assert.are.same({1, true, 1, true}, ladder(plan_moving(90)))
    end)

    it("uses one fast inserter, not two plain ones, for a flow only two plain inserters would move", function()
      assert.are.same({1, true, 1, true}, ladder(plan_moving(100)))
    end)

    it("keeps one fast inserter when the flow is exactly what it moves", function()
      assert.are.same({1, true, 1, true}, ladder(plan_moving(144)))
    end)

    it("uses two fast inserters when one is not enough", function()
      assert.are.same({2, true, 2, true}, ladder(plan_moving(200)))
    end)

    it("keeps two fast inserters when the flow is exactly what they move", function()
      assert.are.same({2, true, 2, true}, ladder(plan_moving(288)))
    end)

    it("uses three fast inserters when two are not enough", function()
      assert.are.same({3, true, 3, true}, ladder(plan_moving(300)))
    end)

    it("gives each side the inserters its own flow needs", function()
      local recipe = {energy = 1, ingredients = {amount_of(5, "plate")}, products = {amount_of(2 / 3, "part")}} -- 300 in, 40 out
      local plan = planner.plan{product = "part", rate_per_minute = 40, recipe = recipe, machine_speed = 1, lane_items_per_minute = 450, inserters = limits}

      assert.are.same({3, true, 1, false}, {plan.input_inserters, plan.input_fast, plan.output_inserters, plan.output_fast})
    end)

    it("uses plain inserters when the request gives no limits at all", function()
      local plan = planner.plan{product = "part", rate_per_minute = 90, recipe = recipe_moving(90), machine_speed = 1, lane_items_per_minute = 450}

      assert.are.same({1, false, 1, false}, ladder(plan)) -- one inserter on each side, as ever without limits
    end)

    it("uses plain inserters only, as many as it takes, when no fast inserter is given", function()
      local plain_only = {items_per_minute = 50.4, max_input = 3, max_output = 3}

      assert.are.same({2, false, 2, false}, ladder(plan_moving(90, plain_only)))
    end)

    it("runs the machine slower when even all its fast inserters cannot move what it needs", function()
      local two_slots = {items_per_minute = 50.4, fast_items_per_minute = 144, max_input = 2, max_output = 2, machine_size = 3}

      local plan = plan_moving(300, two_slots)

      assert.are.equal(2, plan.machines) -- two fast inserters move 288 of the 300 a minute, so one machine makes 288 and 300 take two
    end)

    it("gives a machine that is used for part of its time the inserters that share needs: one plain for 45 of its 300", function()
      local plan = planner.plan{
        product = "part", rate_per_minute = 45, recipe = recipe_moving(300), machine_speed = 1,
        lane_items_per_minute = 450, inserters = limits,
      }

      assert.are.same({1, false, 1, false}, ladder(plan)) -- 45 a minute: one plain inserter moves them
    end)

    it("gives a machine that is used for part of its time a fast inserter when its share is more than a plain one moves", function()
      local plan = planner.plan{
        product = "part", rate_per_minute = 60, recipe = recipe_moving(300), machine_speed = 1,
        lane_items_per_minute = 450, inserters = limits,
      }

      assert.are.same({1, true, 1, true}, ladder(plan)) -- 60 a minute is more than the 50.4 of a plain inserter
    end)

    describe("the paired winding belt of the root stage, which one fast output inserter per 3x3 machine fills in turns", function()
      -- Machines that eat 60 plates and make 120 parts a minute: one fast output inserter each (144 a minute), so a lane
      -- carries 3.75 machines' worth. The belt gives both lanes to the machines, in turns outer, inner, inner, outer, so a
      -- lane gets half of them, and one more for an odd number, the last (partial) machine's: 3 + 3 whole machines and 0.75
      -- of the seventh, which is on the lane that has the fourth: 6.75 machines' worth.
      local function stage(product, input, output, extra)
        local recipe = {energy = 1, ingredients = {amount_of(input, extra and extra.eats or "ore")}, products = {amount_of(output, product)}}
        return {product = product, recipe = recipe, machine_speed = 1, inserters = limits}
      end

      local function max_rate_of(root, suppliers)
        return planner.max_tree_rate({rate_per_minute = 1, lane_items_per_minute = 450, root = {stage = root, suppliers = suppliers or {}}})
      end

      it("carries what the whole machines of a lane and the lane's share of the last make, when each has one fast output inserter", function()
        assert.near(810, max_rate_of(stage("part", 1, 2)), 1e-6) -- 6.75 machines, each making 120
      end)

      it("carries twice the whole machines of a lane when a lane carries a whole number of them", function()
        assert.near(900, max_rate_of(stage("part", 1, 1.5)), 1e-6) -- machines making 90 a minute: 5 on each lane, 10 machines
      end)

      it("carries one lane when one plain inserter moves what each machine makes", function()
        assert.near(450, max_rate_of(stage("part", 1, 2 / 3)), 1e-6) -- 40 a minute: a plain inserter; 450 / 40 machines' worth, each making 40
      end)

      it("winds the belt the other way, a lane for each of two fast inserters, when a machine makes more than one moves", function()
        assert.near(900, max_rate_of(stage("part", 1, 3)), 1e-6) -- 180 a minute: two fast inserters; 2 x 450 / 180 = 5 machines' worth, each making 180
      end)

      it("does not pair the belt of a stage that feeds another, which carries one lane", function()
        local first = stage("plate", 1, 2) -- makes 120 plates a minute a machine, with one fast inserter
        local second = stage("part", 1, 1, {eats = "plate"})

        local most = max_rate_of(second, {{stage = first, suppliers = {}}})

        assert.near(450, most, 1e-6) -- one lane of plates; the root alone would take 840
      end)
    end)

    describe("the output belt of the root stage, which winds for two output inserters on a 3x3 machine", function()
      -- 5 plates in and 3 parts out a craft, 60 crafts a minute: 300 in (three fast inserters, every tile beside the machine,
      -- so rows of poles between the machines) and 180 out (two fast inserters).
      local function max_rate_with(input_per_craft)
        local recipe = {energy = 1, ingredients = {amount_of(input_per_craft, "plate")}, products = {amount_of(3, "part")}}
        local request = {
          rate_per_minute = 1, lane_items_per_minute = 450,
          root = {stage = {product = "part", recipe = recipe, machine_speed = 1, inserters = limits}, suppliers = {}},
        }
        return planner.max_tree_rate(request)
      end

      it("winds when a side is not full: the two lanes carry what the machines make together", function()
        assert.near(900, max_rate_with(1), 1e-6) -- 2 x 450 / 180 = 5 machines' worth, each making 180
      end)

      it("does not wind when the input side is full, which takes a row of poles: the product rides one lane", function()
        assert.near(450, max_rate_with(5), 1e-6) -- 450 / 180 machines' worth, each making 180
      end)
    end)
  end)

  describe("a furnace stage that may be built wide: a second input belt, an output belt that winds in twos", function()
    -- A furnace column makes 18.75 plates a minute a furnace, and a lane carries 450: 24 furnaces fill the lane of ore and the
    -- lane of plates. Built wide, the ore rides three lanes (the second belt carries it on both) and the plates two, which
    -- the winding belt in twos carries for 2 * 24 = 48 furnaces (24 on each lane, which is a lane full): 48 * 18.75 = 900
    -- plates a minute.
    local plate_recipe = {energy = 3.2, ingredients = {amount_of(1, "iron-ore")}, products = {amount_of(1, "iron-plate")}}
    local gear_recipe = {energy = 0.5, ingredients = {amount_of(2, "iron-plate")}, products = {amount_of(1, "iron-gear-wheel")}}
    local furnace_inserters = {items_per_minute = 50.4, max_input = 1, max_output = 1, machine_size = 2}
    local assembler_inserters = {items_per_minute = 50.4, max_input = 2, max_output = 2, machine_size = 3}

    local function furnace(options)
      options = options or {}
      return {
        product = "iron-plate", recipe = plate_recipe, machine_speed = 1, fuel = options.fuel == nil and "coal" or options.fuel or nil,
        inserters = options.inserters == nil and furnace_inserters or options.inserters, wide = options.wide,
      }
    end

    local function gear_assembler()
      return {product = "iron-gear-wheel", recipe = gear_recipe, machine_speed = 0.5, inserters = assembler_inserters}
    end

    it("builds the furnaces plain while the rate fits what a plain column makes", function()
      local plan = planner.plan{rate_per_minute = 450, lane_items_per_minute = 450, product = "iron-plate", recipe = plate_recipe,
        machine_speed = 1, fuel = "coal", inserters = furnace_inserters, wide = true}

      assert.are.same({24, false, {"iron-ore", "coal"}}, {plan.machines, plan.wide, plan.lanes})
    end)

    it("builds them wide when the rate is above that, with three lanes of ore and a second plain input inserter, for belt b", function()
      local plan = planner.plan{rate_per_minute = 451, lane_items_per_minute = 450, product = "iron-plate", recipe = plate_recipe,
        machine_speed = 1, fuel = "coal", inserters = furnace_inserters, wide = true}

      assert.are.same({25, true, {"iron-ore", "coal", "iron-ore", "iron-ore"}, 2}, {plan.machines, plan.wide, plan.lanes, plan.input_inserters})
    end)

    it("makes 900 plates a minute at the most, with 48 furnaces, where it made 450 with 24", function()
      local request = {rate_per_minute = 1, lane_items_per_minute = 450, stages = {furnace{wide = true}}}
      local plain = {rate_per_minute = 1, lane_items_per_minute = 450, stages = {furnace()}}

      assert.are.same({900, 450}, {planner.max_rate(request), planner.max_rate(plain)})
    end)

    it("plans the most with 48 furnaces", function()
      local plans = planner.plan_chain{rate_per_minute = 900, lane_items_per_minute = 450, stages = {furnace{wide = true}}}

      assert.are.same({48, true}, {plans[1].machines, plans[1].wide})
    end)

    it("refuses a rate above that, naming the most", function()
      local plans, reason, most = planner.plan_chain{rate_per_minute = 901, lane_items_per_minute = 450, stages = {furnace{wide = true}}}

      assert.are.same({nil, "rate-too-high", 900}, {plans, reason, most})
    end)

    it("does not build furnaces wide that are not asked to be, and refuses the rate", function()
      local plans, reason, most = planner.plan_chain{rate_per_minute = 451, lane_items_per_minute = 450, stages = {furnace()}}

      assert.are.same({nil, "rate-too-high", 450}, {plans, reason, most})
    end)

    it("does not build furnaces wide when the layout does not know the size of the machine", function()
      local stage = furnace{wide = true, inserters = {items_per_minute = 50.4, max_input = 1, max_output = 1}}

      assert.are.equal(450, planner.max_rate{rate_per_minute = 1, lane_items_per_minute = 450, stages = {stage}})
    end)

    it("does not build furnaces wide when one plain inserter on a side is not all the machine gets", function()
      local stage = furnace{wide = true, inserters = {items_per_minute = 50.4, max_input = 2, max_output = 2, machine_size = 2}}
      stage.recipe = {energy = 0.5, ingredients = {amount_of(1, "iron-ore")}, products = {amount_of(1, "iron-plate")}} -- 120 plates a minute: two inserters a side

      local plain = {product = stage.product, recipe = stage.recipe, machine_speed = 1, fuel = "coal", inserters = stage.inserters}

      assert.are.equal(planner.max_rate{rate_per_minute = 1, lane_items_per_minute = 450, stages = {plain}},
        planner.max_rate{rate_per_minute = 1, lane_items_per_minute = 450, stages = {stage}})
    end)

    it("does not build a machine wide that burns no fuel: its belt has no lane of fuel to share", function()
      local stage = furnace{wide = true, fuel = false}

      assert.are.equal(450, planner.max_rate{rate_per_minute = 1, lane_items_per_minute = 450, stages = {stage}}) -- the lane of plates: 24 machines
    end)

    it("builds the furnaces of a chain wide, and the stage that eats their plates takes them on both lanes", function()
      local request = {rate_per_minute = 226, lane_items_per_minute = 450, stages = {furnace{wide = true}, gear_assembler()}}

      local plans = planner.plan_chain(request)

      assert.are.same({{25, true, {"iron-ore", "coal", "iron-ore", "iron-ore"}}, {5, false, {"iron-plate", "iron-plate"}}}, -- 226 gears are 4.5 assemblers of 50.4
        {{plans[1].machines, plans[1].wide, plans[1].lanes}, {plans[2].machines, plans[2].wide, plans[2].lanes}})
    end)

    it("makes more gears with wide furnaces than with plain ones: 450 a minute, where it made 225", function()
      local wide = {rate_per_minute = 1, lane_items_per_minute = 450, stages = {furnace{wide = true}, gear_assembler()}}
      local plain = {rate_per_minute = 1, lane_items_per_minute = 450, stages = {furnace(), gear_assembler()}}

      assert.are.same({450, 225}, {planner.max_rate(wide), planner.max_rate(plain)})
    end)

    it("leaves the furnaces of a chain plain at a rate the plain chain makes", function()
      local plans = planner.plan_chain{rate_per_minute = 225, lane_items_per_minute = 450, stages = {furnace{wide = true}, gear_assembler()}}

      assert.are.same({false, {"iron-plate"}}, {plans[1].wide, plans[2].lanes})
    end)

    it("leaves the furnaces plain that feed a stage that burns fuel too: the fuel needs the lane the plates would take", function()
      local steel_recipe = {energy = 16, ingredients = {amount_of(5, "iron-plate")}, products = {amount_of(1, "steel-plate")}}
      local steel = {product = "steel-plate", recipe = steel_recipe, machine_speed = 1, fuel = "coal", inserters = furnace_inserters}
      local wide = {rate_per_minute = 1, lane_items_per_minute = 450, stages = {furnace{wide = true}, steel}}
      local plain = {rate_per_minute = 1, lane_items_per_minute = 450, stages = {furnace(), steel}}

      assert.are.equal(planner.max_rate(plain), planner.max_rate(wide))
    end)

    describe("steel furnaces after furnaces built wide, which take their fuel on a belt of their own", function()
      -- A steel furnace eats 5 plates every 16 s: 18.75 a minute, like a furnace makes, and makes 3.75 steel a minute. The
      -- plates ride both lanes of the belt (900 a minute from 48 furnaces) and the fuel has a belt of its own, so 48
      -- steel furnaces make 180 where the plain design, with the fuel on a lane of the plates' belt, made 90.
      local steel_recipe = {energy = 16, ingredients = {amount_of(5, "iron-plate")}, products = {amount_of(1, "steel-plate")}}
      local function steel(options)
        options = options or {}
        return {
          product = "steel-plate", recipe = steel_recipe, machine_speed = 1, fuel = "coal", wide = options.wide,
          inserters = options.inserters or furnace_inserters,
        }
      end

      it("makes 180 steel a minute at the most, with 48 steel furnaces, where it made 90", function()
        local wide = {rate_per_minute = 1, lane_items_per_minute = 450, stages = {furnace{wide = true}, steel{wide = true}}}
        local plain = {rate_per_minute = 1, lane_items_per_minute = 450, stages = {furnace(), steel()}}

        assert.are.same({180, 90}, {planner.max_rate(wide), planner.max_rate(plain)})
      end)

      it("builds both wide, the steel furnaces with the plates on two lanes and the fuel on two of its own", function()
        local plans = planner.plan_chain{rate_per_minute = 100, lane_items_per_minute = 450, stages = {furnace{wide = true}, steel{wide = true}}}

        assert.are.same({{true, 27}, {true, 27, {"iron-plate", "iron-plate", "coal", "coal"}, 2}},
          {{plans[1].wide, plans[1].machines}, {plans[2].wide, plans[2].machines, plans[2].lanes, plans[2].input_inserters}})
      end)

      it("builds both plain at a rate the plain design makes", function()
        local plans = planner.plan_chain{rate_per_minute = 90, lane_items_per_minute = 450, stages = {furnace{wide = true}, steel{wide = true}}}

        assert.are.same({false, false, {"iron-plate", "coal"}}, {plans[1].wide, plans[2].wide, plans[2].lanes})
      end)

      it("leaves the steel furnaces and the iron furnaces before them plain when the stage that eats the steel eats more", function()
        -- A widget takes 100 gears and a steel plate. Three widgets a minute are 600 plates for the gears, which only wide
        -- furnaces make, so the tree is built wide, but not the steel furnaces: the widget does not take steel on both lanes.
        local widget_recipe = {energy = 1, ingredients = {amount_of(100, "iron-gear-wheel"), amount_of(1, "steel-plate")}, products = {amount_of(1, "widget")}}
        local widget = {product = "widget", recipe = widget_recipe, machine_speed = 1, inserters = assembler_inserters}
        local gears = {stage = gear_assembler(), suppliers = {{stage = furnace{wide = true}, suppliers = {}}}}
        local steel_chain = {stage = steel{wide = true}, suppliers = {{stage = furnace{wide = true}, suppliers = {}}}}

        local plans = planner.plan_tree{rate_per_minute = 3, lane_items_per_minute = 450, root = {stage = widget, suppliers = {gears, steel_chain}}}

        assert.are.same({true, false, false}, {
          plans.suppliers[1].suppliers[1].plan.wide, plans.suppliers[2].plan.wide, plans.suppliers[2].suppliers[1].plan.wide,
        }) -- the iron furnaces of the gears, the steel furnaces, the iron furnaces of the steel
      end)

      it("makes no more than the plain design when the steel furnaces cannot be built wide", function()
        local unknown_size = {items_per_minute = 50.4, max_input = 1, max_output = 1}
        local request = {rate_per_minute = 1, lane_items_per_minute = 450, stages = {furnace{wide = true}, steel{wide = true, inserters = unknown_size}}}

        assert.are.equal(90, planner.max_rate(request))
      end)
    end)

    it("leaves the furnaces plain that feed a stage with a second ingredient: the lane is that ingredient's", function()
      local alloy_recipe = {energy = 1, ingredients = {amount_of(1, "iron-plate"), amount_of(1, "copper-plate")}, products = {amount_of(1, "alloy")}}
      local copper = furnace()
      copper.product, copper.recipe = "copper-plate", {energy = 3.2, ingredients = {amount_of(1, "copper-ore")}, products = {amount_of(1, "copper-plate")}}
      local wide_copper = furnace{wide = true}
      wide_copper.product, wide_copper.recipe = copper.product, copper.recipe
      local alloy = {product = "alloy", recipe = alloy_recipe, machine_speed = 0.5, inserters = assembler_inserters}
      local wide = {rate_per_minute = 1, lane_items_per_minute = 450, root = {stage = alloy, suppliers = {{stage = furnace{wide = true}, suppliers = {}}, {stage = wide_copper, suppliers = {}}}}}
      local plain = {rate_per_minute = 1, lane_items_per_minute = 450, root = {stage = alloy, suppliers = {{stage = furnace(), suppliers = {}}, {stage = copper, suppliers = {}}}}}

      assert.are.equal(planner.max_tree_rate(plain), planner.max_tree_rate(wide))
    end)

    it("keeps both input inserters of furnaces built wide that do only a fraction of one furnace's work", function()
      -- A widget takes 100 gears and a pipe. Three widgets a minute are 600 plates for the gears, more than a plain column
      -- makes, so the furnaces are built wide, those that make the plates of the pipes too: 3 plates a minute, 3 / 18.75 of a
      -- furnace, which a machine used for a part of its time would give fewer inserters.
      local pipe_recipe = {energy = 0.5, ingredients = {amount_of(1, "iron-plate")}, products = {amount_of(1, "pipe")}}
      local widget_recipe = {energy = 1, ingredients = {amount_of(100, "iron-gear-wheel"), amount_of(1, "pipe")}, products = {amount_of(1, "widget")}}
      local pipe_assembler = {product = "pipe", recipe = pipe_recipe, machine_speed = 0.5, inserters = assembler_inserters}
      local widget = {product = "widget", recipe = widget_recipe, machine_speed = 1, inserters = assembler_inserters}
      local gears = {stage = gear_assembler(), suppliers = {{stage = furnace{wide = true}, suppliers = {}}}}
      local pipes = {stage = pipe_assembler, suppliers = {{stage = furnace{wide = true}, suppliers = {}}}}

      local plans = planner.plan_tree{rate_per_minute = 3, lane_items_per_minute = 450, root = {stage = widget, suppliers = {gears, pipes}}}

      local pipe_furnaces = plans.suppliers[2].suppliers[1].plan
      assert.are.same({1, true, 2}, {pipe_furnaces.machines, pipe_furnaces.wide, pipe_furnaces.input_inserters})
    end)
  end)

  describe("item_interval_ticks", function()
    it("gives the ticks a full lane takes to carry one more item past a point", function()
      local standard_belt_speed = 0.03125

      local ticks = planner.item_interval_ticks(standard_belt_speed)

      assert.near(8, ticks, 1e-9) -- 1 / (4 items a tile x 0.03125 tiles a tick)
    end)

    it("gives fewer ticks on a faster belt", function()
      local fast_belt_speed = 0.0625

      local ticks = planner.item_interval_ticks(fast_belt_speed)

      assert.near(4, ticks, 1e-9) -- 1 / (4 x 0.0625)
    end)
  end)

  describe("inserter_items_per_minute", function()
    local basic_rotation_speed, standard_belt_speed = 0.014, 0.03125

    it("turns an inserter's rotation speed into items per minute when a swing moves one item", function()
      local per_minute = planner.inserter_items_per_minute(basic_rotation_speed, 1, standard_belt_speed)

      assert.near(50.4, per_minute, 1e-6) -- 0.014 swings a tick x 60 ticks x 60 seconds, one item a swing
    end)

    it("does not wait for the belt when a swing moves one item", function()
      local slow_belt_speed = 0.001

      local per_minute = planner.inserter_items_per_minute(basic_rotation_speed, 1, slow_belt_speed)

      assert.near(50.4, per_minute, 1e-6) -- no second item to wait for
    end)

    it("waits at the belt for the second item when a swing moves two", function()
      local per_minute = planner.inserter_items_per_minute(basic_rotation_speed, 2, standard_belt_speed)

      assert.near(90.647, per_minute, 1e-3) -- a swing is 1 / 0.014 = 71.43 ticks and the wait 8: 2 items in 79.43 ticks, 2 x 3600 / 79.43
    end)

    it("waits less on a faster belt", function()
      local fast_belt_speed = 0.0625

      local per_minute = planner.inserter_items_per_minute(basic_rotation_speed, 2, fast_belt_speed)

      assert.near(95.455, per_minute, 1e-3) -- the wait is 4 ticks: 2 items in 75.43 ticks, 2 x 3600 / 75.43
    end)

    it("waits for each item after the first when a swing moves three", function()
      local per_minute = planner.inserter_items_per_minute(basic_rotation_speed, 3, standard_belt_speed)

      assert.near(123.529, per_minute, 1e-3) -- 3 items in 71.43 + 2 x 8 = 87.43 ticks, 3 x 3600 / 87.43
    end)

    it("refuses a swing that moves no item", function()
      local no_item = function() planner.inserter_items_per_minute(basic_rotation_speed, 0, standard_belt_speed) end

      assert.has_error(no_item, "planner: an inserter moves at least one item in a swing")
    end)
  end)

  describe("belt_of, the input belt of a stage that an ingredient rides", function()
    local belts = {a = {"circuit", "gear"}, b = {"plate"}, c = {"stick"}}

    it("says belt a for an ingredient that is on it", function()
      assert.are.equal("a", planner.belt_of(belts, "gear"))
    end)

    it("says belt b for an ingredient that is on it", function()
      assert.are.equal("b", planner.belt_of(belts, "plate"))
    end)

    it("says belt c for an ingredient that is on it", function()
      assert.are.equal("c", planner.belt_of(belts, "stick"))
    end)

    it("says belt a for the ingredient of a stage that has no belt c", function()
      assert.are.equal("a", planner.belt_of({a = {"plate", "cable"}, b = {}}, "cable"))
    end)

    it("refuses an item that is on none of the belts", function()
      assert.has_error(function() planner.belt_of(belts, "wood") end, "planner: wood is on none of the input belts of the stage")
    end)
  end)

  describe("lane_items_per_minute", function()
    it("turns a belt's speed into items per minute for one lane", function()
      local standard_belt_speed = 0.03125

      local per_minute = planner.lane_items_per_minute(standard_belt_speed)

      assert.near(450, per_minute, 1e-6) -- 0.03125 x 4 items x 60 ticks x 60 seconds
    end)

    it("carries more per lane when the belt is faster", function()
      local double_belt_speed = 0.0625

      local per_minute = planner.lane_items_per_minute(double_belt_speed)

      assert.near(900, per_minute, 1e-6)
    end)
  end)

  describe("a row of machines that make a fluid from a fluid", function()
    -- 100 units of one fluid make 45 of another in 5 s: a machine of speed 1 makes 9 a second, 540 a minute, and takes in 1,200. A run
    -- of pipes has as many machines as stand in 320 tiles, 64 of 5 x 5: it carries all they need (the wiki: no limit of its flow).
    local crude = {name = "crude", amount = 100}
    local recipe = {energy = 5, ingredients = {}, fluids = {crude}, products = {builders.fluid_of(45, "gas")}}

    local function recipe_with(changes)
      return builders.merged(recipe, changes)
    end

    local function request(changes)
      return builders.merged({product = "gas", recipe = recipe, machine_speed = 1, rate_per_minute = 1000, machines_that_fit = 64}, changes)
    end

    describe("is_fluid_recipe", function()
      it("takes a recipe that takes one fluid and makes the product", function()
        assert.is_true(planner.is_fluid_recipe(recipe, "gas"))
      end)

      it("refuses a recipe that takes an item as well", function()
        local with_item = recipe_with{ingredients = {builders.amount_of(1, "iron-plate")}}

        assert.is_false(planner.is_fluid_recipe(with_item, "gas"))
      end)

      it("refuses a recipe that takes two fluids", function()
        local two_fluids = recipe_with{fluids = {crude, {name = "water", amount = 50}}}

        assert.is_false(planner.is_fluid_recipe(two_fluids, "gas"))
      end)

      it("refuses a recipe that takes no fluid", function()
        local no_fluid = recipe_with{fluids = {}}

        assert.is_false(planner.is_fluid_recipe(no_fluid, "gas"))
      end)

      it("refuses a recipe that makes more than one product", function()
        local two = recipe_with{products = {builders.fluid_of(45, "gas"), builders.fluid_of(25, "oil")}}

        assert.is_false(planner.is_fluid_recipe(two, "gas"))
      end)

      it("refuses a recipe that makes something other than the product", function()
        assert.is_false(planner.is_fluid_recipe(recipe, "oil"))
      end)

      it("refuses a recipe that takes no time, which no rate comes from", function()
        assert.is_false(planner.is_fluid_recipe(recipe_with{energy = 0}, "gas"))
      end)
    end)

    describe("plan_fluid_row", function()
      it("gives as many machines as the rate needs, which make a little more than asked", function()
        local plan = planner.plan_fluid_row(request{rate_per_minute = 1000})

        assert.are.same({machines = 2, output_per_minute = 1080, per_machine = 540}, plan) -- 1000 / 540 = 1.85 machines, 2 x 540
      end)

      it("gives one machine for the most one machine makes", function()
        local plan = planner.plan_fluid_row(request{rate_per_minute = 540})

        assert.are.equal(1, plan.machines)
      end)

      it("makes more from a machine of a better crafting speed", function()
        local plan = planner.plan_fluid_row(request{machine_speed = 2, rate_per_minute = 1000})

        assert.are.same({machines = 1, output_per_minute = 1080, per_machine = 1080}, plan)
      end)

      it("refuses a rate that needs more machines than stand in the length of a run of pipes, naming the most the row makes", function()
        local plan, reason, max_rate = planner.plan_fluid_row(request{machines_that_fit = 2, rate_per_minute = 1081})

        assert.are.same({nil, "rate-too-high", 1080}, {plan, reason, max_rate}) -- 2 x 540
      end)

      it("allows the most that stand in the length", function()
        local plan = planner.plan_fluid_row(request{machines_that_fit = 2, rate_per_minute = 1080})

        assert.are.equal(2, plan.machines)
      end)

      it("does not limit the machines by what they take in: a row of 64 takes in 76,800 crude oil a minute from one pipe", function()
        local plan = planner.plan_fluid_row(request{rate_per_minute = 34560})

        assert.are.equal(64, plan.machines)
      end)

      it("refuses a recipe the planner cannot handle", function()
        local plan, reason = planner.plan_fluid_row(request{recipe = recipe_with{energy = 0}})

        assert.are.same({nil, "unsupported-recipe"}, {plan, reason})
      end)
    end)

    describe("max_fluid_row_rate", function()
      it("gives what as many machines as stand in the length of a run of pipes make", function()
        assert.are.equal(34560, planner.max_fluid_row_rate(request{})) -- 64 machines of 540
      end)

      it("gives more from machines that craft faster, as many of them", function()
        assert.are.equal(69120, planner.max_fluid_row_rate(request{machine_speed = 2})) -- 64 machines of 1,080
      end)

      it("gives one machine's worth at least, however long the machine is", function()
        assert.are.equal(540, planner.max_fluid_row_rate(request{machines_that_fit = 0}))
      end)

      it("gives no rate, and the reason, for a recipe it cannot handle", function()
        local max_rate, reason = planner.max_fluid_row_rate(request{recipe = recipe_with{energy = 0}})

        assert.are.same({nil, "unsupported-recipe"}, {max_rate, reason})
      end)
    end)
  end)

  describe("a plant of machines that make an item from a fluid that a row of machines makes", function()
    -- 20 gas make 1 solid fuel in 2 s: a machine of speed 1 makes 30 a minute and takes 600 gas. The gas comes from machines that make
    -- 45 of it from 100 crude oil in 5 s: 540 a minute from 1,200 crude oil each. A lane of the belt carries 450 a minute.
    local fuel = {energy = 2, ingredients = {}, fluids = {{name = "gas", amount = 20}}, products = {builders.amount_of(1, "fuel")}}
    local gas_maker = {energy = 5, ingredients = {}, fluids = {{name = "crude", amount = 100}}, products = {builders.fluid_of(45, "gas")}}

    local function request(changes)
      return builders.merged({
        product = "fuel", recipe = fuel, machine_speed = 1, maker_recipe = gas_maker, maker_speed = 1, rate_per_minute = 100,
        makers_that_fit = 64, plants_that_fit = 106, lane_items_per_minute = 450, inserter_items_per_minute = 90,
      }, changes)
    end

    describe("plan_fluid_plant", function()
      it("gives as many machines as the rate needs and as many that make the fluid as those take", function()
        local plan = planner.plan_fluid_plant(request{rate_per_minute = 100})

        -- 100 / 30 = 3.3 machines, 4: 120 a minute, from 2,400 gas, which takes 4.4 machines of 540, 5, and 5,333.3 crude oil
        assert.are.equal(4, plan.plants)
        assert.are.equal(5, plan.makers)
        assert.are.same({120, 30, 2400}, {plan.output_per_minute, plan.per_plant, plan.fluid_per_minute})
        assert.near(5333.333, plan.source_per_minute, 1e-3)
      end)

      it("needs a second machine for the fluid when the first makes less than one machine of the plant takes", function()
        local plan = planner.plan_fluid_plant(request{rate_per_minute = 30})

        assert.are.same({1, 2}, {plan.plants, plan.makers}) -- 600 gas against 540
      end)

      it("makes less from a machine whose inserter cannot move what it makes, and takes less fluid for it", function()
        local plan = planner.plan_fluid_plant(request{rate_per_minute = 100, inserter_items_per_minute = 20})

        -- 20 a minute from each machine, from 400 gas: 5 machines, 2,000 gas, 4 machines for it
        assert.are.same({5, 4, 100, 20, 2000}, {plan.plants, plan.makers, plan.output_per_minute, plan.per_plant, plan.fluid_per_minute})
      end)

      it("refuses a rate that needs more machines than a lane of the belt carries, naming the most", function()
        local plan, reason, max_rate = planner.plan_fluid_plant(request{rate_per_minute = 451})

        assert.are.same({nil, "rate-too-high", 450}, {plan, reason, max_rate}) -- 15 machines of 30
      end)

      it("allows the most a lane carries", function()
        local plan = planner.plan_fluid_plant(request{rate_per_minute = 450})

        assert.are.equal(15, plan.plants)
      end)

      it("allows the most a lane carries when float rounding puts the count just under a whole number", function()
        -- 3.33 a minute from each machine: 450 / 3.3333333333333335 is 134.99999999999997, which is 135 machines
        local slow = request{machine_speed = 0.5, recipe = builders.merged(fuel, {energy = 9}), rate_per_minute = 450, inserter_items_per_minute = 1000, plants_that_fit = 1000}

        local plan = planner.plan_fluid_plant(slow)

        assert.are.equal(135, plan.plants)
      end)

      it("refuses a rate that needs more fluid than the machines that make it make, which are as many as fit in the length of the pipe", function()
        -- 5 machines of 540 make 2,700 gas: 4 machines of the plant take 2,400, not 3,000
        local plan, reason, max_rate = planner.plan_fluid_plant(request{makers_that_fit = 5, rate_per_minute = 150})

        assert.are.same({nil, "rate-too-high", 120}, {plan, reason, max_rate})
      end)

      it("refuses a rate that needs more machines of the plant than fit in the length of the pipe, naming the most", function()
        local plan, reason, max_rate = planner.plan_fluid_plant(request{plants_that_fit = 3, rate_per_minute = 100})

        assert.are.same({nil, "rate-too-high", 90}, {plan, reason, max_rate})
      end)

      it("has one machine at least, however little fits", function()
        local plan = planner.plan_fluid_plant(request{makers_that_fit = 0, plants_that_fit = 0, rate_per_minute = 10})

        assert.are.equal(1, plan.plants)
      end)

      it("counts what a craft makes: a recipe that makes two items a craft makes twice as much from the same fluid", function()
        local twice = builders.merged(fuel, {products = {builders.amount_of(2, "fuel")}})

        local plan = planner.plan_fluid_plant(request{recipe = twice, rate_per_minute = 100})

        -- 60 a minute from each machine (30 crafts of 2, from 600 gas): 2 machines, 120 a minute, 1,200 gas, 3 machines for it
        assert.are.same({2, 3, 120, 60, 1200}, {plan.plants, plan.makers, plan.output_per_minute, plan.per_plant, plan.fluid_per_minute})
      end)

      it("refuses a recipe that takes an item as well", function()
        local with_item = builders.merged(fuel, {ingredients = {builders.amount_of(1, "iron-plate")}})

        local plan, reason = planner.plan_fluid_plant(request{recipe = with_item})

        assert.are.same({nil, "unsupported-recipe"}, {plan, reason})
      end)

      it("refuses a fluid that the machines of the row do not make", function()
        local other = builders.merged(gas_maker, {products = {builders.fluid_of(45, "oil")}})

        local plan, reason = planner.plan_fluid_plant(request{maker_recipe = other})

        assert.are.same({nil, "unsupported-recipe"}, {plan, reason})
      end)
    end)

    describe("a recipe that takes a second fluid, which comes in by a pipe", function()
      -- 30 water and 30 gas make 2 sulfur in 1 s: a machine of speed 1 makes 120 a minute and takes 1,800 gas, held to the 90 that its
      -- inserter moves (the request's): 45 crafts a minute, from 1,350 gas and 1,350 water.
      local sulfur = {
        energy = 1, ingredients = {}, fluids = {{name = "water", amount = 30}, {name = "gas", amount = 30}}, products = {builders.amount_of(2, "sulfur")},
      }

      local function sulfur_request(changes)
        return request(builders.merged({product = "sulfur", recipe = sulfur, rate_per_minute = 100}, changes))
      end

      it("takes the recipes of one fluid or two, and of nothing else", function()
        local three = builders.merged(sulfur, {fluids = {{name = "a", amount = 1}, {name = "b", amount = 1}, {name = "c", amount = 1}}})
        local with_item = builders.merged(sulfur, {ingredients = {builders.amount_of(1, "iron-plate")}})

        assert.are.same({true, true, false, false}, {
          planner.is_plant_recipe(sulfur, "sulfur"), planner.is_plant_recipe(fuel, "fuel"), planner.is_plant_recipe(three, "sulfur"),
          planner.is_plant_recipe(with_item, "sulfur"),
        })
      end)

      it("takes the gas of the machines that make it by the fluid they make, whichever the recipe lists first", function()
        local plan = planner.plan_fluid_plant(sulfur_request{})

        -- 100 / 90: 2 machines, 180 a minute, from 2,700 gas: 5 machines of 540, from 6,000 crude oil
        assert.are.same({2, 5, 180, 90, 2700}, {plan.plants, plan.makers, plan.output_per_minute, plan.per_plant, plan.fluid_per_minute})
        assert.near(6000, plan.source_per_minute, 1e-6)
      end)

      it("says how much of the fluid that comes in the plants take a minute", function()
        local plan = planner.plan_fluid_plant(sulfur_request{})

        assert.are.same({{name = "water", amount = 2700}}, plan.supplied) -- 2 machines x 45 crafts x 30
      end)

      it("says no fluid comes in for a recipe of one fluid", function()
        local plan = planner.plan_fluid_plant(request{rate_per_minute = 100})

        assert.are.same({}, plan.supplied)
      end)

      it("limits the rate by the lane of the belt, as for one fluid: 5 machines of 90", function()
        assert.are.equal(450, planner.max_fluid_plant_rate(sulfur_request{}))
      end)

      it("refuses a recipe that takes none of the fluid the machines of the row make", function()
        local no_gas = builders.merged(sulfur, {fluids = {{name = "water", amount = 30}, {name = "oil", amount = 30}}})

        local plan, reason = planner.plan_fluid_plant(sulfur_request{recipe = no_gas})

        assert.are.same({nil, "unsupported-recipe"}, {plan, reason})
      end)
    end)

    describe("max_fluid_plant_rate", function()
      it("gives what the machines make that a lane carries, 15 of 30", function()
        assert.are.equal(450, planner.max_fluid_plant_rate(request{}))
      end)

      it("gives one machine's worth at least, however little fits", function()
        assert.are.equal(30, planner.max_fluid_plant_rate(request{makers_that_fit = 0, plants_that_fit = 0}))
      end)

      it("gives no rate, and the reason, for a recipe it cannot handle", function()
        local max_rate, reason = planner.max_fluid_plant_rate(request{recipe = builders.merged(fuel, {energy = 0})})

        assert.are.same({nil, "unsupported-recipe"}, {max_rate, reason})
      end)
    end)
  end)
end)
