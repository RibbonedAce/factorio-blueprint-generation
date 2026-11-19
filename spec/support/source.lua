-- spec/support/source.lua
-- Reads the Lua files of scripts/ as text, for the specs that check how the code is written (spec/conventions_spec.lua).
-- Test tooling only; the game never loads it.

---@diagnostic disable-next-line: unresolved-require  -- busted's own library (luafilesystem), installed with LuaRocks, not in this repo
local lfs = require("lfs")

local source = {}

-- Where the comment or the string that starts at `from` ends, or nil when none does. A comment runs to the end of its line, or
-- to the closing brackets of a block comment; a string to its closing quote.
---@param text string
---@param from integer
---@return integer|nil stop
---@return boolean|nil is_string
local function end_of_comment_or_string(text, from)
  local char = text:sub(from, from)
  if text:sub(from, from + 1) == "--" then
    local level = text:match("^%-%-%[(=*)%[", from)
    if level then
      return select(2, text:find("]" .. level .. "]", from, true)) or #text, false
    end
    return (text:find("\n", from, true) or #text + 1) - 1, false
  end
  if char == '"' or char == "'" then
    local stop = from + 1
    while stop <= #text and text:sub(stop, stop) ~= char do
      stop = stop + (text:sub(stop, stop) == "\\" and 2 or 1)
    end
    return stop, true
  end
  return nil, nil
end

-- The text with its comments blanked out, and its strings too unless `keep_strings` is set: every character becomes a space,
-- line breaks stay, so a position in the result is the position in the text.
---@param text string
---@param keep_strings? boolean
---@return string
function source.blanked(text, keep_strings)
  local out, at = {}, 1
  while at <= #text do
    local stop, is_string = end_of_comment_or_string(text, at)
    if stop then
      local piece = text:sub(at, stop)
      out[#out + 1] = (is_string and keep_strings) and piece or (piece:gsub("[^\n]", " "))
      at = stop + 1
    else
      out[#out + 1] = text:sub(at, at)
      at = at + 1
    end
  end
  return table.concat(out)
end

-- The lines of a text.
---@param text string
---@return string[]
local function lines_of(text)
  local lines = {}
  for line in (text .. "\n"):gmatch("(.-)\n") do
    lines[#lines + 1] = line
  end
  return lines
end

-- The lines of the text that match the Lua pattern, as "line:the line".
---@param text string
---@param pattern string
---@return string[]
function source.lines_matching(text, pattern)
  local found = {}
  for number, line in ipairs(lines_of(text)) do
    if line:find(pattern) then
      found[#found + 1] = number .. ":" .. (line:gsub("^%s+", ""))
    end
  end
  return found
end

-- The cyclomatic complexity of a piece of code with its comments and strings blanked out: 1 and one for each `if`, `elseif`,
-- `for`, `while`, `and` and `or` (the rule of .agents/instructions.md).
---@param blanked_code string
---@return integer
local function complexity_of(blanked_code)
  local complexity = 1
  for word in blanked_code:gmatch("[%a_][%w_]*") do
    if word == "if" or word == "elseif" or word == "for" or word == "while" or word == "and" or word == "or" then
      complexity = complexity + 1
    end
  end
  return complexity
end

-- The top-level functions of the text (`local function name` or `function name` at the start of a line, ending in a line that
-- is exactly `end`), with how many lines each takes and its cyclomatic complexity.
---@param text string
---@return {name: string, first: integer, length: integer, complexity: integer}[]
function source.functions_of(text)
  local lines, blanked = lines_of(text), lines_of(source.blanked(text))
  local found, first, name = {}, nil, nil
  for number, line in ipairs(lines) do
    local declared = line:match("^local function ([%w_%.:]+)") or line:match("^function ([%w_%.:]+)")
    if declared then
      first, name = number, declared
    end
    if line == "end" and first then
      local body = table.concat(blanked, "\n", first, number)
      found[#found + 1] = {name = name, first = first, length = number - first + 1, complexity = complexity_of(body)}
      first = nil
    end
  end
  return found
end

-- The files of scripts/, sorted by name, as {name = "grid.lua", text = "..."} (line breaks as "\n").
---@return {name: string, text: string}[]
function source.scripts()
  local names = {}
  for name in lfs.dir("scripts") do
    if name:match("%.lua$") then
      names[#names + 1] = name
    end
  end
  table.sort(names)
  local files = {}
  for _, name in ipairs(names) do
    local handle = assert(io.open("scripts/" .. name, "rb"))
    files[#files + 1] = {name = name, text = (handle:read("*a"):gsub("\r\n", "\n"))}
    handle:close()
  end
  return files
end

return source
