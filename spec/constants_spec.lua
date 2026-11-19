-- spec/constants_spec.lua
-- The numbers that two or more modules agree on (scripts/constants.lua), and that those modules read them from it.
---@diagnostic disable: undefined-field  -- luassert's `assert` has fields (`assert.are`, `assert.is_nil`, ...) the editor cannot see

local constants = require("scripts.constants")
local layout = require("scripts.layout")

describe("constants", function()
  it("has a belt carry one item on each of its two lanes", function()
    assert.are.equal(2, constants.LANES_PER_BELT)
  end)

  it("winds the output belt of a 3 x 3 machine with two output inserters", function()
    assert.are.same({3, 2}, {constants.WINDING_MACHINE_SIZE, constants.WINDING_OUTPUT_INSERTERS})
  end)

  it("lets the layout give a 3 x 3 machine the output inserters the planner counts on for the winding belt", function()
    local inserters = layout.max_output_inserters(constants.WINDING_MACHINE_SIZE)

    assert.are.equal(constants.WINDING_OUTPUT_INSERTERS, inserters)
  end)

  it("treats two numbers a billionth apart as equal", function()
    assert.are.equal(1e-9, constants.EPSILON)
  end)

  it("gives a column that takes a fluid two tile columns for its pipes: the trunk and the column of the underground pipes", function()
    assert.are.equal(2, layout.PIPE_COLUMNS)
  end)
end)
