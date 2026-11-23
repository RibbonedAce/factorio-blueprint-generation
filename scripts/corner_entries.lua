-- scripts/corner_entries.lua
-- Brings the start of everything the player connects to the top left corner, where the belts they bring in start: each pipe or belt
-- goes up from the tile it starts at, above the blueprint, and west along a row of its own to the west edge, where its end is open
-- to the west and the player joins it (as the water inlet of the concrete columns does, see scripts/rows.lua). Pure, like
-- scripts/fluid_row.lua.
--
-- The rows are ROWS_APART rows apart, so that no two touch (two fluids would mix, and the panels need room), the one that starts
-- furthest west on the row nearest the blueprint and the one furthest east on the top row, as the belts of raw items have it, so that
-- none crosses another. Drawn for a pipe and a belt that start at the columns 1 and 5 of a blueprint (= a pipe, > and v a belt, o the
-- entry, whose open end is west):
--
--   o>>>>v            row -4: the entry of the belt that starts at the column 5
--   . . . v
--   . . . v
--   o=. . v           row -1: the entry of the pipe that starts at the column 1
--   . = . . v         row 0 and below: the blueprint, with its pipe and belt starting here
--
-- Two pipes of one fluid that start at different columns are one entry (`joins`): the pipe of the one that starts furthest east goes up to
-- the row and west along it to the edge, as above, and the other goes up to the same row and joins it there, so that the player brings the
-- fluid once and it divides itself, as pipes do (there is no splitter to build). The entry is on the row that its furthest start has,
-- so another entry may not start between two of its starts: it would have to cross it, which a pipe cannot do on the surface.
--
--   o=======          row -4: the entry that joins the pipes that start at the columns 3 and 7
--   ...=...=
--   ...=...=
--   o=.=...=          row -1: the entry of the pipe that starts at the column 1, west of both
--   .=.=...=          row 0 and below: the blueprint, with the three pipes starting here
--
-- A blueprint with belts across the way of a pipe (the band that divides the belts that come in, see scripts/inputs.lua, which the pipes
-- come down through from above) gives `taken`, the tiles that are in use: a pipe goes under a run of them with an underground pipe, one
-- tile before the run and one after it (`u` is the end of an underground pipe), and the entries come in above the first row of the blueprint
-- as `top` says. The belts of the band are drawn here as `-`:
--
--   o=======v         row -4
--   . . . . =
--   . . . . u         the tile before the belts
--   - - - - -         the belts that the pipe goes under
--   . . . . u         the tile after them
--   . . . . =
--
-- The panels that tell what each entry is are put beside them (scripts/labels.lua).

local constants = require("scripts.constants")
local entity_list = require("scripts.entity_list")
local grid = require("scripts.grid")

local corner_entries = {}

local north, east, south, west = defines.direction.north, defines.direction.east, defines.direction.south, defines.direction.west

local ROWS_APART = 3

-- The tile where a pipe or a belt starts (a pipe opens to the north, a belt runs south), what it is made of, and a key the caller
-- gives it to find the entry again.
---@class bpgen.EntryStart
---@field key string
---@field x integer
---@field y integer
---@field name string  prototype name of the pipe or the belt
---@field belt? boolean  a belt: the tiles run east along the row and south down the column, where a pipe has no direction
---@field fluid? string  of a pipe: the fluid it brings, which the blocks of a blueprint made of several (see scripts/rows.lua) use to bring a fluid in once, however many take it
---@field feed? bpgen.Feed  of a belt of raw items that the band of scripts/shared_band.lua brings down: what it takes a minute; the band draws the belt as far as its first tile, so `corner_entries` is not asked for it
---@field joins? string  of a pipe: the key of the start of another pipe, of the same fluid, whose entry this one joins (see the head of this file)

-- The tiles of a run of an entry, from `first` to `last` along the column or the row `across`, going the way given (nothing for a pipe).
---@param entities bpgen.Entity[]
---@param start bpgen.EntryStart
---@param run {along: "column"|"row", across: integer, first: integer, last: integer, direction?: defines.direction}
local function add_run(entities, start, run)
  for at = run.first, run.last do
    local tile = run.along == "column" and {x = run.across, y = at} or {x = at, y = run.across}
    entity_list.append(entities, {name = start.name, position = grid.position(tile.x, tile.y), direction = run.direction})
  end
end

-- What a run of an entry is asked for.
---@class bpgen.EntryOptions
---@field top? integer  the first row of the blueprint: the entries come in above it (the top row of the starts by default)
---@field west? integer  the column of the west edge of the blueprint, where the entries open to the west (0 by default)
---@field taken? table<string, true>  the tiles in use, as `grid.key`s: a pipe goes under them
---@field pipe_to_ground? string  the prototype name of the underground pipe, when `taken` is given
---@field pump? string  the prototype name of a pump: each pipe entry then starts with a pump facing east, in the two tiles west of the west edge, which the player's pipe feeds, so that the long pipe that brings the fluid in has its flow divided from the others'; needs `pole`
---@field pole? string  the prototype name of the pole that powers the pump of each entry, in the row under it (the panel that tells what the entry is goes above)

-- A pipe down a column, from row `first` to row `last`: plain pipes, and where tiles are taken an underground pipe from the tile before them to
-- the tile after them.
---@param entities bpgen.Entity[]
---@param start bpgen.EntryStart
---@param first integer
---@param last integer
---@param options bpgen.EntryOptions
local function add_pipe_column(entities, start, first, last, options)
  local taken, row = options.taken or {}, first
  local function add(name, at, direction)
    assert(not taken[grid.key(start.x, at)] and at >= first and at <= last, "corner_entries: a pipe has no free tile to come out of the ground at")
    entity_list.append(entities, {name = name, position = grid.position(start.x, at), direction = direction})
  end
  while row <= last do
    if taken[grid.key(start.x, row + 1)] and row + 1 <= last then
      local after = row + 1
      while taken[grid.key(start.x, after + 1)] do
        after = after + 1
      end
      assert(after + 1 - row < constants.PIPE_REACH, "corner_entries: a pipe has to pass under more belts than an underground pipe spans")
      add(assert(options.pipe_to_ground, "corner_entries: no underground pipe for a pipe that crosses belts"), row, north)
      add(options.pipe_to_ground, after + 1, south)
      row = after + 2
    else
      add(start.name, row)
      row = row + 1
    end
  end
end

-- The tiles of one entry: up from the tile where it starts to the row, and west along it to the edge.
---@param entities bpgen.Entity[]
---@param start bpgen.EntryStart
---@param row integer
---@param options bpgen.EntryOptions
local function add_line(entities, start, row, options)
  if start.belt then
    add_run(entities, start, {along = "column", across = start.x, first = row, last = start.y - 1, direction = south})
  else
    add_pipe_column(entities, start, row, start.y - 1, options)
  end
  local west, pole = options.west or 0, nil
  if options.pump and not start.belt then
    assert(options.pole, "corner_entries: a pump needs a pole")
    entity_list.append(entities, {name = options.pump, position = grid.position(west - 2, row, 2, 1), direction = east}) -- west of the edge: the pipe runs to its east end
    pole = entity_list.append(entities, {name = options.pole, position = grid.position(west - 2, row + 1)})
  end
  add_run(entities, start, {along = "row", across = row, first = west, last = start.x - 1, direction = start.belt and east or nil})
  return pole
end

-- One entry: the starts that come in as one, the one the others join first.
---@class bpgen.Entry
---@field starts bpgen.EntryStart[]  the first is the one the others join, the others follow in the order they were given
---@field far bpgen.EntryStart  the start furthest east: the row of the entry is by its column

-- The starts as entries: each start that joins none is an entry, with the starts that join it.
---@param starts bpgen.EntryStart[]
---@return bpgen.Entry[]
local function entries_of(starts)
  local by_key, entries = {}, {}
  for _, start in ipairs(starts) do
    if not start.joins then
      by_key[start.key] = {starts = {start}, far = start}
      entries[#entries + 1] = by_key[start.key]
    end
  end
  for _, start in ipairs(starts) do
    if start.joins then
      local entry = assert(by_key[start.joins], "corner_entries: a start joins the entry of a start that is not there")
      assert(not (start.belt or entry.starts[1].belt), "corner_entries: only pipes join each other")
      entry.starts[#entry.starts + 1] = start
      entry.far = start.x > entry.far.x and start or entry.far
    end
  end
  return entries
end

-- Whether the leg of `entry` that goes down from the row of the entry at the column of `start` crosses `other`: the rows of the entries
-- that start further west are under the row of this one, and they run east up to the column of their furthest start, so the leg of a start
-- west of the furthest one crosses those that reach its column.
---@param entry bpgen.Entry
---@param start bpgen.EntryStart  one of the starts of `entry`
---@param other bpgen.Entry
---@return boolean
local function crosses(entry, start, other)
  return other ~= entry and start ~= entry.far and start.x <= other.far.x and other.far.x <= entry.far.x
end

-- Stops when the entries cross each other, or two starts of an entry are in the same column.
---@param entries bpgen.Entry[]
local function assert_planar(entries)
  for _, entry in ipairs(entries) do
    local columns = {}
    for _, start in ipairs(entry.starts) do
      assert(not columns[start.x], "corner_entries: two starts of an entry are in the same column")
      columns[start.x] = true
      for _, other in ipairs(entries) do
        assert(not crosses(entry, start, other), "corner_entries: an entry has the start of another entry between two of its own starts, which it would cross")
      end
    end
  end
end

-- The first row of the blueprint: the one the options give, or the top row of the starts.
---@param starts bpgen.EntryStart[]
---@param options bpgen.EntryOptions
---@return integer
local function first_row_of(starts, options)
  if options.top then
    return options.top
  end
  local top = math.huge
  for _, start in ipairs(starts) do
    top = math.min(top, start.y)
  end
  return top
end

-- The pipes and belts of the entries of `starts`, appended to `entities`. Gives the entry of each, at the west edge, in the order of the
-- entries from the west: the key is that of the start the others join, when there are several.
---@param entities bpgen.Entity[]
---@param starts bpgen.EntryStart[]
---@param options? bpgen.EntryOptions
---@return {key: string, x: integer, y: integer, pole?: bpgen.Entity}[] entries  `x` is 0 and `y` the row of the entry; `pole` powers the pump of an entry that has one
function corner_entries.add(entities, starts, options)
  options = options or {}
  local ordered = entries_of(starts)
  assert_planar(ordered)
  table.sort(ordered, function(first, second) return first.far.x < second.far.x end)
  local top = first_row_of(starts, options)
  local entries = {}
  for index, entry in ipairs(ordered) do
    local row = top - 1 - ROWS_APART * (index - 1)
    local pole = add_line(entities, entry.far, row, options)
    for _, start in ipairs(entry.starts) do
      if start ~= entry.far then
        assert(not start.belt, "corner_entries: only pipes join each other")
        add_pipe_column(entities, start, row + 1, start.y - 1, options)
      end
    end
    entries[index] = {key = entry.starts[1].key, x = pole and (options.west or 0) - 2 or 0, y = row, pole = pole}
  end
  return entries
end

-- The poles of the pumps of some entries (those that have one).
---@param entries {pole?: bpgen.Entity}[]
---@return bpgen.Entity[]
function corner_entries.poles_of(entries)
  local found = {}
  for _, entry in ipairs(entries) do
    found[#found + 1] = entry.pole
  end
  return found
end

return corner_entries
