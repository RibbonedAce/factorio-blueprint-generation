-- spec/source_spec.lua
-- What the helpers that read the code as text find (spec/support/source.lua): each must find what it should AND leave alone what
-- it should, or a broken helper would quietly make every convention spec pass.
---@diagnostic disable: undefined-field  -- luassert's `assert` has fields (`assert.are`, `assert.is_nil`, ...) the editor cannot see

local source = require("spec.support.source")

describe("source", function()
  describe("blanked", function()
    it("blanks a comment to the end of its line and keeps the line break", function()
      local text = source.blanked("x = 1 -- move it\ny = 2")

      assert.are.equal("x = 1" .. string.rep(" ", 11) .. "\ny = 2", text) -- the space before the dashes, and the ten characters of the comment
    end)

    it("blanks a string, quotes included", function()
      local text = source.blanked('x = "a-b" .. y')

      assert.are.equal("x = " .. string.rep(" ", 5) .. " .. y", text)
    end)

    it("keeps the strings when asked to blank the comments only", function()
      local text = source.blanked('x = "a" -- b', true)

      assert.are.equal('x = "a"' .. string.rep(" ", 5), text)
    end)

    it("blanks a comment in blocks, over several lines", function()
      local text = source.blanked("a\n--[[ one\ntwo ]] b")

      assert.are.equal("a\n" .. string.rep(" ", 8) .. "\n" .. string.rep(" ", 7) .. "b", text)
    end)

    it("does not take the dashes inside a string for a comment", function()
      local text = source.blanked('x = "--" .. y', true)

      assert.are.equal('x = "--" .. y', text)
    end)
  end)

  describe("lines_matching", function()
    it("gives the number and the text of each line that matches", function()
      local found = source.lines_matching("a = 1\n  b = table.insert(x, 1)\nc = 3", "table%.insert")

      assert.are.same({"2:b = table.insert(x, 1)"}, found)
    end)

    it("gives nothing when no line matches", function()
      local found = source.lines_matching("a = 1\nb = 2", "table%.insert")

      assert.are.same({}, found)
    end)
  end)

  describe("functions_of", function()
    it("gives the name, the first line and the number of lines of a function", function()
      local functions = source.functions_of("local x = 1\n\nlocal function add(a, b)\n  return a + b\nend\n")

      assert.are.same({{name = "add", first = 3, length = 3, complexity = 1}}, functions)
    end)

    it("counts one for each branch, loop, and and or", function()
      local text = "local function f(a, b)\n  if a and b or a then\n    for _ = 1, 2 do\n    end\n  elseif b then\n  end\nend\n"

      local functions = source.functions_of(text)

      assert.are.equal(1 + 1 + 1 + 1 + 1 + 1, functions[1].complexity) -- if, and, or, for, elseif
    end)

    it("does not count the words of a comment or a string", function()
      local text = 'local function f()\n  -- if and or for\n  local s = "if and or for"\n  return s\nend\n'

      local functions = source.functions_of(text)

      assert.are.equal(1, functions[1].complexity)
    end)

    it("knows a function of a module: function module.name and function Class:method", function()
      local functions = source.functions_of("function grid.key(x, y)\n  return x\nend\nfunction Builder:add(entity)\n  return entity\nend\n")

      assert.are.same({"grid.key", "Builder:add"}, {functions[1].name, functions[2].name})
    end)
  end)

  describe("scripts", function()
    it("lists the files of scripts/, sorted, with their text", function()
      local files = source.scripts()

      assert.are.same({"chain.lua", "config.lua"}, {files[1].name, files[2].name})
    end)

    it("reads a file whole, with its line breaks as one character", function()
      local files = source.scripts()

      assert.is_nil(files[1].text:find("\r", 1, true))
    end)
  end)
end)
