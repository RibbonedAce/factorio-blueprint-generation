-- spec/assertions_spec.lua
-- The custom assertions get specs too: each must accept what it should AND
-- reject what it should, or a broken assertion would quietly pass everything.
---@diagnostic disable: undefined-field  -- luassert's `assert` has fields (`assert.are`, `assert.is_nil`, ...) the editor cannot see

describe("has_item_containing", function()
  it("passes when one item in the list contains the text", function()
    local problems = {"belt #1: overlaps pole #2", "inserter #3: has no usable direction"}

    assert.has_item_containing("overlaps", problems)
  end)

  it("fails when no item contains the text", function()
    local problems = {"belt #1: overlaps pole #2"}

    local assertion = function() assert.has_item_containing("not aligned", problems) end

    assert.has_error(assertion)
  end)

  it("fails when the list is empty", function()
    local assertion = function() assert.has_item_containing("anything", {}) end

    assert.has_error(assertion)
  end)

  it("treats special characters literally when the text has them", function()
    local list = {"abc"}

    assert.is_not.has_item_containing("a.c", list)
  end)

  it("still finds text when it contains special characters", function()
    local list = {"a.c"}

    assert.has_item_containing("a.c", list)
  end)

  it("reports no match rather than erroring when the list is not a list", function()
    assert.is_not.has_item_containing("x", nil)
    assert.is_not.has_item_containing("x", "x")
  end)

  it("reports no match rather than erroring when the text is not a string", function()
    local list = {"x"}

    assert.is_not.has_item_containing(nil, list)
    assert.is_not.has_item_containing(1, list)
  end)

  it("ignores items when they are not strings", function()
    local list = {42, {"overlaps"}}

    assert.is_not.has_item_containing("overlaps", list)
  end)

  it("says what it expected and what it found when it fails", function()
    local assertion = function() assert.has_item_containing("overlaps", {"something else"}) end

    local ok, message = pcall(assertion)

    assert.is_false(ok)
    assert.matches("Expected a list with an item containing", message, 1, true)
    assert.matches("overlaps", message, 1, true)
    assert.matches("something else", message, 1, true)
  end)
end)
