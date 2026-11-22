-- scripts/weave.lua
-- The pattern of the woven input belts of a column of 3 x 3 machines that eat from two or three belts, in place of
-- long-handed inserters (which a blueprint keeps until its force has what the weave is made of: `generator.can_weave`):
-- every inserter is a plain (or fast) one that takes from the tile beside it, and the belts take turns in the column of
-- those tiles. Pure, like scripts/layout.lua, which turns the pattern into entities.
--
-- The pattern is worked out for belts that run SOUTH, from row 0 (the row of the first inserter, the machine nearest the
-- source of the belts) down, and the layout draws it the way the belts really run (north, for the columns that eat what
-- other columns make). The tile columns are counted from the inner column, the one next to the inserters; west is
-- negative:
--
--   0  inner column  belt a goes under it, and the stubs of belt b and belt c end in it, where the inserters take from them
--  -1  taps          where a tap of belt b or belt c reaches the inner column; poles in the tiles that stay free
--  -2  trunk of b    belt b runs down it, and a splitter at the head of every tap
--  -3  c underground belt c goes under, and the entrance of the tap that crosses belt b
--  -4  trunk of c    belt c comes down it to a splitter that peels the tap off
--
-- Every row of a machine shows one belt in the inner column. The machines take turns, a pair for every six rows, so that
-- the second machine of a pair and the first of the next show the same belt where they meet:
--
--   three belts, one inserter on each           two belts, two inserters on a      two belts, two inserters on b
--   (the pattern of the owner's blueprint)      (and one on b)                     (and one on a)
--       a b c | c b a                               a b a | a b a                      b b a | a b b
--
-- The belts reach their rows in three ways:
--   * Belt a goes under the rows of the others: an underground belt that comes up at its rows. A row of a that has other
--     rows before it is the exit of a hop, one that has other rows after it the entrance of the next; an exit is never
--     followed by anything but belt a, which it would feed.
--   * Belt b runs down the trunk, and a splitter in the trunk and the taps column peels a share off into a tile that points
--     east into the inner column: a stub, for one row of b, or, for several rows in a row, a tile that turns south and goes
--     on until the last, which turns east. Both lanes stay as they are, since the stubs are curves (nothing runs behind
--     them) and the splitter keeps the lanes of its belt.
--   * Belt c comes down its own trunk, a splitter peels a tap off, and the tap goes east under belt b, comes up in the taps
--     column and feeds the inner column the same way. The rest of belt c goes under the tap, to the next splitter.
--
-- Three belts, two machines (the belts run down, ( ) are the entrance and the exit of an underground belt that goes east,
-- n u of one that goes down, S the two halves of a splitter, } an inserter, > v belts and + a pole). The letter after a row is
-- the belt it shows in the inner column:
--
--   -4-3-2-1 0 1      the tile columns
--    ...+..           row -1: a free tile, where the pole that reaches the rows 0 to 2 stands
--    SSSSn}  a        row 0: the splitters of b and of c; belt a goes under from here
--    vnv>>}  b        row 1: the stub of b; belt c goes under in its column, from the entrance in column -3
--    >(v)v}  c        row 2: the tap of c goes east under b, and comes up in the taps column (the exit)
--    ..SS>}  c        row 3: the tap of c turns east, the splitter of b; belt a goes on under
--    ..v>>}  b        row 4: the stub of b
--    .uv+u}  a        row 5: belt a comes up, and belt c; a pole in the tile that stays free
--
-- The tile columns are fixed, and so are the rows each belt shows, for a given number of inserters on each belt: the patterns
-- are drawn in `spec/weave_spec.lua`. The pattern asks for belt a to go under up to five tiles, and for poles that reach three
-- rows when the three belts have one inserter each (the tiles that stay free are few).
--
-- A machine that takes a fluid has a pipe in the middle row of its input side (an underground pipe that comes in under the
-- belts), so its two inserters stand in the top and the bottom row: the second pattern, `weave.plan_with_pipes`, for two belts,
-- one inserter on each. Belt b has no splitter and no taps there: all of it goes through the inner column for the rows its
-- inserters take from, in a detour made of curves (the trunk tile turns east, the inner column goes on for a tile, turns west
-- and goes back into the trunk), which keeps the lanes. The poles stand in the free tiles of the inner column. The pattern is the
-- one of the owner's blueprint; two machines of it, with the belts running down (it repeats for the next two):
--
--   -1 0 1       the tile columns, the trunk of b, the inner column, the inserters
--    .  n }  a   row 0: belt a comes down into an entrance, the inserter takes from it
--    .  . .      row 1: the middle row of the machine, where its pipe is; a pole may stand in the inner column
--    >  v }  b   row 2: belt b turns east into the inner column
--    v  < }  b   row 3: and back west into the trunk; the second inserter takes from it
--    v  . .      row 4: (the trunk of b goes on)
--    .  u }  a   row 5: belt a comes up out of its hop of five tiles, under belt b

local weave = {}

-- The tile columns, from the inner column (0), the one beside the inserters.
weave.INNER = 0
weave.TAPS = -1
weave.TRUNK_B = -2
weave.UNDER_C = -3
weave.TRUNK_C = -4

-- The trunk of belt b in the pattern for machines with a pipe, which has no taps column: next to the inner column.
weave.NEAR_TRUNK_B = -1

-- How many tile columns west of the inner column the weave takes, by the number of belts woven: belt b's trunk and the taps
-- column for two, and the two columns of belt c besides for three. The pattern for machines with a pipe takes belt b's trunk alone.
weave.WIDTH = {[2] = -weave.TRUNK_B, [3] = -weave.TRUNK_C}
weave.PIPED_WIDTH = -weave.NEAR_TRUNK_B

-- The most tiles from an entrance of belt a to its exit: what a basic underground belt spans.
weave.REACH = 5

-- The size of the machines the pattern is for, and so the rows of each.
weave.MACHINE_SIZE = 3

-- The belt each row of a machine shows, from the first row the belts reach to the last, for the machines that go first,
-- third, ... and second, fourth, ... from the source.
local PATTERNS = {
  abc = {{"a", "b", "c"}, {"c", "b", "a"}},
  aba = {{"a", "b", "a"}, {"a", "b", "a"}},
  bba = {{"b", "b", "a"}, {"a", "b", "b"}},
}

-- How many inserters each machine has on belt a, b and c: 0 for a belt that carries nothing.
---@param counts table<string, integer>  by belt, "a", "b" and "c" (nil or 0 for a belt that carries nothing)
---@return integer a
---@return integer b
---@return integer c
local function inserters_by_belt(counts)
  return counts.a or 0, counts.b or 0, counts.c or 0
end

-- The pattern for the inserters each machine has on each belt.
---@param counts table<string, integer>  by belt, "a", "b" and "c" (nil or 0 for a belt that carries nothing)
---@return "abc"|"aba"|"bba"
local function kind_of(counts)
  local a, b, c = inserters_by_belt(counts)
  if c > 0 then
    assert(a == 1 and b == 1 and c == 1, "weave: three belts get one inserter each")
    return "abc"
  end
  assert(b > 0 and a > 0 and a + b <= weave.MACHINE_SIZE, "weave: two belts need an inserter each and at most three in all")
  return b > a and "bba" or "aba"
end

-- The belt each row shows, for `machine_count` machines.
---@param kind "abc"|"aba"|"bba"
---@param machine_count integer
---@return table<integer, string> rows
local function rows_of(kind, machine_count)
  local rows = {}
  for machine = 0, machine_count - 1 do
    for step, belt in ipairs(PATTERNS[kind][machine % 2 + 1]) do
      rows[machine * weave.MACHINE_SIZE + step - 1] = belt
    end
  end
  return rows
end

---@param tiles bpgen.WeaveTile[]
---@param column integer
---@param row integer
---@param kind "belt"|"entrance"|"exit"|"splitter"
---@param way "flow"|"east"
local function tile(tiles, column, row, kind, way)
  tiles[#tiles + 1] = {column = column, row = row, kind = kind, way = way}
end

-- The rows that show `belt` and are not preceded by one that does: the rows where a run of rows of it starts, with how
-- long the run is.
---@param rows table<integer, string>
---@param row_count integer
---@param belt string
---@return {first: integer, length: integer}[]
local function runs_of(rows, row_count, belt)
  local runs = {}
  local row = 0
  while row < row_count do
    if rows[row] == belt then
      local first = row
      while rows[row + 1] == belt do
        row = row + 1
      end
      runs[#runs + 1] = {first = first, length = row - first + 1}
    end
    row = row + 1
  end
  return runs
end

-- The hops of belt a under the rows of the others: from the entrance to the exit, with a leading one from row -1 when the
-- first row is not a row of belt a (the belt that brings it ends in an entrance there).
---@param rows table<integer, string>
---@param row_count integer
---@return {from: integer, to: integer}[] hops
---@return integer[] shown  the rows that show belt a
local function hops_of(rows, row_count)
  local shown = {}
  for row = 0, row_count - 1 do
    if rows[row] == "a" then
      shown[#shown + 1] = row
    end
  end
  assert(#shown > 0, "weave: no row shows belt a")
  local hops = {}
  if shown[1] > 0 then
    hops[1] = {from = -1, to = shown[1]}
  end
  for index = 1, #shown - 1 do
    if shown[index + 1] > shown[index] + 1 then
      hops[#hops + 1] = {from = shown[index], to = shown[index + 1]}
    end
  end
  for _, hop in ipairs(hops) do
    assert(hop.to - hop.from <= weave.REACH, "weave: a hop of belt a is longer than an underground belt spans")
  end
  return hops, shown
end

-- What belt a has in a row that shows it: the exit of a hop, the entrance of one, or plain belt.
---@param entrances table<integer, true>  the rows where a hop starts
---@param exits table<integer, true>  the rows where a hop ends
---@param row integer
---@return "exit"|"entrance"|"belt"
local function kind_of_tile(entrances, exits, row)
  assert(not (entrances[row] and exits[row]), "weave: a row of belt a would be the exit of one hop and the entrance of the next")
  if exits[row] then
    return "exit"
  end
  return entrances[row] and "entrance" or "belt"
end

-- The tile of belt a in `row` of the inner column, which must not feed a tile of another belt below it.
---@param tiles bpgen.WeaveTile[]
---@param rows table<integer, string>
---@param row_count integer
---@param row integer
---@param kind "exit"|"entrance"|"belt"
---@param is_last boolean  the last row that shows belt a, where it turns east
local function add_tile_of_belt_a(tiles, rows, row_count, row, kind, is_last)
  if kind == "exit" then
    assert(row == row_count - 1 or rows[row + 1] == "a", "weave: an exit of belt a would feed a tile of another belt")
    tile(tiles, weave.INNER, row, "exit", "flow")
  elseif kind == "entrance" then
    tile(tiles, weave.INNER, row, "entrance", "flow")
  else
    assert(is_last or rows[row + 1] == "a", "weave: a plain tile of belt a would feed a tile of another belt")
    tile(tiles, weave.INNER, row, "belt", is_last and "east" or "flow")
  end
end

-- The tiles of belt a in the inner column: the entrances and exits of its hops, and plain belt for rows that are neither,
-- the last of which turns east so that it feeds no tile of another belt below it.
---@param tiles bpgen.WeaveTile[]
---@param rows table<integer, string>
---@param row_count integer
local function add_belt_a(tiles, rows, row_count)
  local hops, shown = hops_of(rows, row_count)
  local entrances, exits = {}, {}
  for _, hop in ipairs(hops) do
    entrances[hop.from], exits[hop.to] = true, true
  end
  if hops[1] and hops[1].from < 0 then
    tile(tiles, weave.INNER, -1, "entrance", "flow")
  end
  for index, row in ipairs(shown) do
    add_tile_of_belt_a(tiles, rows, row_count, row, kind_of_tile(entrances, exits, row), index == #shown)
  end
end

-- The tiles of a run of rows of belt b or c in the inner column: tiles that run on, and the last turns east (the only one for
-- a row alone), so that nothing runs behind the first and the tile after the last is not fed.
---@param tiles bpgen.WeaveTile[]
---@param run {first: integer, length: integer}
local function add_run(tiles, run)
  for row = run.first, run.first + run.length - 2 do
    tile(tiles, weave.INNER, row, "belt", "flow")
  end
  tile(tiles, weave.INNER, run.first + run.length - 1, "belt", "east")
end

-- The trunk of belt b and the taps: a splitter in the trunk and the taps column in the row before every run, and a tile
-- under it in the taps column, that points east. Between two splitters the trunk is plain belt.
---@param plan bpgen.WeavePlan
---@param runs {first: integer, length: integer}[]
local function add_taps_of_b(plan, runs)
  local tiles = plan.tiles
  for index, run in ipairs(runs) do
    local splitter = run.first - 1
    tile(tiles, weave.TRUNK_B, splitter, "splitter", "flow")
    tile(tiles, weave.TAPS, run.first, "belt", "east")
    local next_run = runs[index + 1]
    for row = splitter + 1, (next_run and next_run.first - 2 or splitter) do
      tile(tiles, weave.TRUNK_B, row, "belt", "flow")
    end
  end
  plan.starts.b = runs[1].first - 1
end

-- The trunk of belt c and the taps: in the second row before a run a splitter in the trunk and the underground column
-- peels a tap off, which runs down and turns east in the trunk column, goes under belt b and comes up in the taps column
-- in the first row of the run. The rest of belt c goes under the tap, to the splitter of the next run.
---@param plan bpgen.WeavePlan
---@param runs {first: integer, length: integer}[]
local function add_taps_of_c(plan, runs)
  local tiles = plan.tiles
  for index, run in ipairs(runs) do
    local first = run.first
    assert(first >= 2, "weave: a tap of belt c needs two rows above its run")
    tile(tiles, weave.TRUNK_C, first - 2, "splitter", "flow")
    tile(tiles, weave.TRUNK_C, first - 1, "belt", "flow")
    tile(tiles, weave.TRUNK_C, first, "belt", "east")
    tile(tiles, weave.UNDER_C, first, "entrance", "east")
    tile(tiles, weave.TAPS, first, "exit", "east")
    local next_run = runs[index + 1]
    if next_run then
      local exit = next_run.first - 3
      assert(exit > first and exit - (first - 1) <= weave.REACH, "weave: belt c does not reach the splitter of its next run under the tap")
      tile(tiles, weave.UNDER_C, first - 1, "entrance", "flow")
      tile(tiles, weave.UNDER_C, exit, "exit", "flow")
    end
  end
  plan.starts.c = runs[1].first - 2
end

-- The inserters: on every machine, for every belt, the first rows that show it, as many as it has inserters.
---@param rows table<integer, string>
---@param machine_count integer
---@param counts table<string, integer>
---@return {row: integer, belt: string}[]
local function inserters_of(rows, machine_count, counts)
  local inserters = {}
  for machine = 0, machine_count - 1 do
    local placed = {}
    for step = 0, weave.MACHINE_SIZE - 1 do
      local row = machine * weave.MACHINE_SIZE + step
      local belt = rows[row]
      placed[belt] = (placed[belt] or 0) + 1
      if placed[belt] <= (counts[belt] or 0) then
        inserters[#inserters + 1] = {row = row, belt = belt}
      end
    end
  end
  return inserters
end

-- The rows where the taps column holds nothing, from row -1 to the last row of the machines.
---@param tiles bpgen.WeaveTile[]
---@param row_count integer
---@return integer[]
local function free_taps_of(tiles, row_count)
  local taken = {}
  for _, entry in ipairs(tiles) do
    local west = entry.column
    local east = entry.kind == "splitter" and west + 1 or west
    if west <= weave.TAPS and weave.TAPS <= east then
      taken[entry.row] = true
    end
  end
  local free = {}
  for row = -1, row_count - 1 do
    if not taken[row] then
      free[#free + 1] = row
    end
  end
  return free
end

-- The pattern for `machine_count` machines that have `counts` inserters on each belt.
-- Two belts with one inserter on each, or two on belt a, are the pattern `aba`; one on belt a and two on belt b `bba`;
-- three belts with one on each `abc`.
---@param counts table<string, integer>  by belt, "a", "b" and "c"
---@param machine_count integer  at least 1
---@return bpgen.WeavePlan
function weave.plan(counts, machine_count)
  local kind = kind_of(counts)
  local row_count = machine_count * weave.MACHINE_SIZE
  local rows = rows_of(kind, machine_count)
  ---@type bpgen.WeavePlan
  local plan = {kind = kind, pole_column = weave.TAPS, rows = rows, row_count = row_count, tiles = {}, inserters = {}, free_taps = {}, first_row = 0, starts = {}}
  add_belt_a(plan.tiles, rows, row_count)
  for _, belt in ipairs({"b", "c"}) do
    for _, run in ipairs(runs_of(rows, row_count, belt)) do
      add_run(plan.tiles, run)
    end
  end
  add_taps_of_b(plan, runs_of(rows, row_count, "b"))
  if kind == "abc" then
    add_taps_of_c(plan, runs_of(rows, row_count, "c"))
  end
  for _, entry in ipairs(plan.tiles) do
    plan.first_row = math.min(plan.first_row, entry.row)
  end
  plan.starts.a = rows[0] == "a" and 0 or -1
  plan.inserters = inserters_of(rows, machine_count, counts)
  plan.free_taps = free_taps_of(plan.tiles, row_count)
  return plan
end

-- The pattern for machines with a pipe in the middle row of their input side (see the diagram above), two belts, one inserter
-- each. Which belt a row shows: the first machine has belt a in its top row, where belt a starts (the tile of a belt that comes
-- up from the arcs), and belt b in its bottom row, the next machine the other way round, and so on, so that two machines side
-- by side show the same belt where they meet. The middle row of the first machine is free, for a pole that reaches its inserters.
---@param machine_count integer
---@return table<integer, "a"|"b">
local function rows_with_pipes(machine_count)
  local rows = {}
  for machine = 0, machine_count - 1 do
    local top, bottom = "a", "b"
    if machine % 2 == 1 then
      top, bottom = "b", "a"
    end
    rows[machine * weave.MACHINE_SIZE] = top
    rows[machine * weave.MACHINE_SIZE + 2] = bottom
  end
  return rows
end

-- The tiles of belt b: for every run of rows that show it, which are two (the bottom row of a machine and the top row of the
-- next) or one (the last machine of an odd number), a detour of two rows, since the belt goes in and comes back out: in the
-- inner column a tile that runs on and, in the second row, one that turns west (a run of one row goes on into the middle row of
-- its machine, or a row past the last); in the trunk (column -1) a tile that turns east in the first row and plain belt down to
-- the first row of the next run.
---@param plan bpgen.WeavePlan
---@param rows table<integer, string>
---@param runs {first: integer, length: integer}[]
local function add_detours_of_b(plan, rows, runs)
  local tiles = plan.tiles
  for index, run in ipairs(runs) do
    local second = run.first + 1
    assert(rows[second] == nil or rows[second] == "b", "weave: the detour of belt b would run into a row of belt a")
    tile(tiles, weave.INNER, run.first, "belt", "flow")
    tile(tiles, weave.INNER, second, "belt", "west")
    tile(tiles, weave.NEAR_TRUNK_B, run.first, "belt", "east")
    local next_run = runs[index + 1]
    for row = second, next_run and next_run.first - 1 or second do
      tile(tiles, weave.NEAR_TRUNK_B, row, "belt", "flow")
    end
  end
  plan.starts.b = runs[1].first
end

-- The rows where the inner column holds nothing, from the first tile of belt a (the belt that brings it comes up through the
-- rows before) to the row after the last of the machines.
---@param tiles bpgen.WeaveTile[]
---@param first_row integer  the row of the first tile of belt a
---@param row_count integer
---@return integer[]
local function free_inner_rows(tiles, first_row, row_count)
  local taken = {}
  for _, entry in ipairs(tiles) do
    if entry.column == weave.INNER then
      taken[entry.row] = true
    end
  end
  local free = {}
  for row = first_row, row_count do
    if not taken[row] then
      free[#free + 1] = row
    end
  end
  return free
end

---@param rows table<integer, "a"|"b">
---@param machine_count integer
---@return {row: integer, belt: "a"|"b"}[]
local function inserters_with_pipes(rows, machine_count)
  local inserters = {}
  for machine = 0, machine_count - 1 do
    for _, step in ipairs({0, 2}) do
      local row = machine * weave.MACHINE_SIZE + step
      inserters[#inserters + 1] = {row = row, belt = rows[row]}
    end
  end
  return inserters
end

-- The pattern for `machine_count` machines with a pipe in the middle of their input side: two belts, one inserter on each.
-- Belt b takes the trunk in column -1, with no splitters; the poles stand in the free tiles of the inner column, from the first
-- tile of belt a to one row past the machines. Belt a starts in row 0, and nothing stands before it.
---@param machine_count integer  at least 1
---@return bpgen.WeavePlan
function weave.plan_with_pipes(machine_count)
  local row_count = machine_count * weave.MACHINE_SIZE
  local rows = rows_with_pipes(machine_count)
  ---@type bpgen.WeavePlan
  local plan = {kind = "pipes", pole_column = weave.INNER, rows = rows, row_count = row_count, tiles = {}, inserters = {}, free_taps = {}, first_row = 0, starts = {}}
  add_belt_a(plan.tiles, rows, row_count)
  add_detours_of_b(plan, rows, runs_of(rows, row_count, "b"))
  plan.starts.a = 0
  plan.inserters = inserters_with_pipes(rows, machine_count)
  plan.free_taps = free_inner_rows(plan.tiles, plan.starts.a, row_count)
  return plan
end

-- The last of the free tiles that reaches `row` (a pole powers the rows `reach` away from it either way) and lies no further
-- down than `lowest`, or nil.
---@param free_taps integer[]  ascending
---@param row integer
---@param reach integer
---@param lowest number
---@return integer|nil
local function last_free_tile(free_taps, row, reach, lowest)
  local best
  for _, free in ipairs(free_taps) do
    if free >= row - reach and free <= math.min(row + reach, lowest) then
      best = free
    end
  end
  return best
end

---@param row integer
---@param reach integer
---@param longest_wire number|nil
---@return string
local function unreached_message(row, reach, longest_wire)
  local near = longest_wire and (" within " .. longest_wire .. " tiles of the pole before it") or ""
  return "weave: no free tile beside the belts reaches the inserter in row " .. row .. near .. ": the pole reaches " .. reach .. " rows"
end

-- The last of the free tiles after `from` and no further down than `upto`, or nil.
---@param free_taps integer[]  ascending
---@param from number
---@param upto number
---@return integer|nil
local function bridge_tile(free_taps, from, upto)
  local best
  for _, free in ipairs(free_taps) do
    if free > from and free <= upto then
      best = free
    end
  end
  return best
end

-- The row of the pole after the one in the row `before` (nil for the first), for the inserter in `row`: the last free tile that reaches
-- it within the wire of that pole. With `bridges`, when there is none, the last free tile within the wire that is not past the inserter
-- (none that reaches it is within the wire, so those are further up): a pole that only bridges the wire, and leaves the inserter to the pole
-- after it. A tile past the inserter is not one: it would count as powering an inserter it does not reach.
---@param plan {free_taps: integer[]}
---@param row integer
---@param reach integer
---@param before integer|nil
---@param longest_wire number|nil
---@param bridges boolean|nil
---@return integer
local function next_pole(plan, row, reach, before, longest_wire, bridges)
  local lowest = (before and longest_wire) and before + longest_wire or math.huge
  local best = last_free_tile(plan.free_taps, row, reach, lowest)
  if not best and bridges and before then
    best = bridge_tile(plan.free_taps, before, math.min(lowest, row))
  end
  assert(best, unreached_message(row, reach, longest_wire))
  return best
end

-- The rows of the poles that power every inserter, in the free tiles of the column of the poles: from the first row that no
-- pole powers, the last free tile that reaches it, so as few as will do. A pole powers the rows `reach` away from it either way
-- (the inserters are at most two tiles from that column, which both poles reach). When the inserters stand far apart, the
-- last free tile may be further from the pole before it than a wire reaches, so `longest_wire` keeps it nearer (the poles stand
-- in one column: the rows between two are the tiles). When no tile that reaches an inserter is within the wire of the pole before it,
-- the plan is refused, unless `bridges` lets poles stand between that only bridge the wire (see `next_pole`).
---@param plan {inserters: {row: integer}[], free_taps: integer[]}  a `bpgen.WeavePlan`, or any plan that says these two
---@param reach integer  how many rows each way a pole powers (see `layout.pole_reach`)
---@param longest_wire? number  the longest wire a pole holds, in tiles; no limit when nil (see `bpgen.SharedNames.pole_wire_distance`)
---@param bridges? boolean
---@return integer[] rows  ascending
function weave.pole_rows(plan, reach, longest_wire, bridges)
  local rows, powered_to = {}, -math.huge
  for _, inserter in ipairs(plan.inserters) do
    while inserter.row > powered_to do
      rows[#rows + 1] = next_pole(plan, inserter.row, reach, rows[#rows], longest_wire, bridges)
      powered_to = rows[#rows] + reach
    end
  end
  return rows
end

return weave
