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

    it("limits the rate by what one inserter puts on a lane when two inserters empty each machine", function()
      local recipe = {energy = 1, ingredients = {amount_of(1, "iron-plate")}, products = {amount_of(2, "iron-gear-wheel")}}

      local plan, reason, max_rate = planner.plan{
        product = "iron-gear-wheel", rate_per_minute = 541, recipe = recipe,
        machine_speed = 1, lane_items_per_minute = 450,
        inserters = {items_per_minute = 100, max_input = 2, max_output = 2},
      }

      assert.is_nil(plan)
      assert.are.equal("rate-too-high", reason)
      assert.near(540, max_rate, 1e-6) -- 450 / 100 = 4.5 machines' worth x 120; the two lanes could take 7.5 (900 / 120)
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
      assert.near(535.7142857, max_rate, 1e-6) -- one inserter puts 50.4 on a lane: 450 / 50.4 = 8.93 machines' worth of 60 gears
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

    it("refuses a later stage with more than two ingredients", function()
      local stages = gear_chain(60).stages
      stages[2].recipe = {
        energy = 0.5, ingredients = {amount_of(2, "iron-plate"), amount_of(1, "copper-plate"), amount_of(1, "stone")},
        products = {amount_of(1, "iron-gear-wheel")},
      }

      local _, reason = planner.plan_chain(gear_chain(60, {stages = stages}))

      assert.are.equal("unsupported-recipe", reason)
    end)

    it("refuses a later stage that burns fuel", function()
      local stages = gear_chain(60).stages
      stages[2].fuel = "coal"

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

    it("refuses a stage with three made ingredients, which need three lanes", function()
      local three = {
        energy = 0.5,
        ingredients = {amount_of(1, "iron-plate"), amount_of(1, "copper-plate"), amount_of(1, "copper-cable")},
        products = {amount_of(1, "electronic-circuit")},
      }
      local stage = tree_of("electronic-circuit", three, 0.5, {
        iron_plates(), tree_of("copper-plate", copper_recipe, 1, {}, "coal"), copper_cables(),
      })

      local _, reason = planner.plan_tree(circuits(10, stage))

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

    it("refuses a stage with a raw item and a made one that burns fuel", function()
      local root = tree_of("pole", pole_recipe, 0.5, {cables()}, "coal")

      local _, reason = planner.plan_tree{rate_per_minute = 10, lane_items_per_minute = 450, root = root}

      assert.are.equal("unsupported-recipe", reason)
    end)

    it("refuses a stage with a raw item and two made ones, which need three lanes", function()
      local three = {
        energy = 0.5, ingredients = {amount_of(1, "wood"), amount_of(2, "copper-cable"), amount_of(1, "copper-plate")},
        products = {amount_of(2, "pole")},
      }
      local root = tree_of("pole", three, 0.5, {cables(), tree_of("copper-plate", copper_recipe, 1, {}, "coal")})

      local _, reason = planner.plan_tree{rate_per_minute = 10, lane_items_per_minute = 450, root = root}

      assert.are.equal("unsupported-recipe", reason)
    end)
  end)

  describe("inserter_items_per_minute", function()
    it("turns an inserter's rotation speed into items per minute", function()
      local basic_rotation_speed = 0.014

      local per_minute = planner.inserter_items_per_minute(basic_rotation_speed)

      assert.near(50.4, per_minute, 1e-6) -- 0.014 swings a tick x 60 ticks x 60 seconds, one item a swing
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
end)
