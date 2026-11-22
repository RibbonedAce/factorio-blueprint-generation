-- scripts/input_side.lua
-- The input side of a column of machines that take a fluid through pipe connections on the side they face, and items from a belt beside
-- them: the assembling machine that makes concrete from water (`scripts/layout.lua`) and the chemical plants that make something from an
-- item and a fluid (`scripts/fluid_plant.lua` and `scripts/item_fluid_plants.lua`). The one place that decides where the underground
-- pipes, the inserters and their poles stand for all of them. The machines face west and the connections of what they take are on that
-- side. A pipe cannot cross the belt, so an underground pipe goes under it from the tile beside each connection to the tunnel column,
-- where the pipe of the caller is; the inserters stand in the rows that have no connection, and the poles in the tunnel column, two
-- tiles from the inserters. Where the connections are is data (`connections`), which is what differs between machines: the assembling
-- machine has one, in the middle row of the side it faces; the chemical plant two, in its top and its bottom row. Pure, like
-- scripts/layout.lua. Not this: the belt, the pipe of the caller, the output side (`scripts/output_side.lua`), the plain belt of the
-- other assembling machines, woven belts and belts of fuel (`scripts/layout.lua`, `scripts/weave.lua`), and a plant that takes no item,
-- whose connections are beside its pipe.
--
-- From the west, two machines of 3 x 3 with a connection in their middle row (`w` the end of an underground pipe that opens west, `+` a
-- pole, `v` the belt, `e` the end that opens east, `}` an inserter), the machines in the rows 0 to 2 and 3 to 5, with one inserter each, and
-- poles that reach two rows:
--
--   =  .  v  }  [M M M]     row 0: no connection: the inserter of the first machine of a pair, in its first free row
--   =  w  v  e  [M M M]     row 1: the connection
--   =  +  v  .  [M M M]     row 2: a pole in the tunnel column, which reaches the inserter two tiles away, in the row 0
--   =  .  v  .  [M M M]     row 3
--   =  w  v  e  [M M M]     row 4: the connection
--   =  +  v  }  [M M M]     row 5: a pole, and the inserter of the second machine of a pair, in its last free row
--
-- (`=` is the pipe of the caller; the belt is the caller's too.) Machines with a connection at their top and their bottom row have the
-- one free row, the middle one, for the inserter and for the pole.

local entity_list = require("scripts.entity_list")
local grid = require("scripts.grid")
local output_side = require("scripts.output_side")
local weave = require("scripts.weave")

local input_side = {}

local north, east, south, west = defines.direction.north, defines.direction.east, defines.direction.south, defines.direction.west

-- The rows from the top of a machine of `size` that no pipe connection takes, from the top.
---@param size integer
---@param connections integer[]
---@return integer[]
function input_side.free_rows(size, connections)
  local taken, free = {}, {}
  for _, row in ipairs(connections) do
    taken[row] = true
  end
  for row = 0, size - 1 do
    if not taken[row] then
      free[#free + 1] = row
    end
  end
  return free
end

-- The tile rows of the `count` input inserters of machine number `index` (from 0): the first free rows of a machine that is the first of its
-- pair, the last free rows of the second, so that the inserters of the second machine of a pair and of the first of the next stand together
-- (the pattern of `output_side.inserter_top`, for the rows the connections leave).
---@param column bpgen.MachineColumn
---@param connections integer[]
---@param index integer
---@param count integer
---@return integer[]
function input_side.inserter_rows(column, connections, index, count)
  local free = input_side.free_rows(column.size, connections)
  assert(count <= #free, "input_side: a machine has fewer rows without a pipe connection than input inserters")
  local first = index % 2 == 1 and #free - count + 1 or 1
  local rows, top = {}, output_side.machine_top(column, index)
  for position = first, first + count - 1 do
    rows[#rows + 1] = top + free[position]
  end
  return rows
end

-- The two ends of an underground pipe at every connection of every machine: the end beside the machine, in the column of the inserters,
-- opens east to it, and the end in the tunnel column opens west, to the pipe of the caller. The belt goes over them.
---@param entities bpgen.Entity[]
---@param request bpgen.InputSideRequest
function input_side.add_tunnels(entities, request)
  local column = request.column
  for index = 0, column.count - 1 do
    for _, row in ipairs(request.connections) do
      local at = output_side.machine_top(column, index) + row
      entity_list.append(entities, {name = request.pipe_to_ground, position = grid.position(request.inserter_column, at), direction = east})
      entity_list.append(entities, {name = request.pipe_to_ground, position = grid.position(request.tunnel_column, at), direction = west})
    end
  end
end

-- The input inserters of machine number `index`, picking up from the belt (an inserter faces the side it picks up from: west).
---@param entities bpgen.Entity[]
---@param request bpgen.InputSideRequest
---@param index integer
function input_side.add_machine_inserters(entities, request, index)
  for _, row in ipairs(input_side.inserter_rows(request.column, request.connections, index, request.inserters)) do
    entity_list.append(entities, {name = request.inserter, position = grid.position(request.inserter_column, row), direction = west})
  end
end

-- The rows of the poles in the tunnel column that power every input inserter: in the tiles no underground pipe takes, as few as will do,
-- each within a wire of the one before it, with poles between that only bridge the wire where the inserters of two machines stand further
-- apart than it reaches (see `weave.pole_rows`). A pole has to reach across the belt to the inserters.
---@param request bpgen.InputSideRequest
---@return integer[] rows  ascending
function input_side.pole_rows(request)
  local across = request.inserter_column - request.tunnel_column
  assert(request.pole_reach >= across, "input_side: a pole in the tunnel column has to reach the inserters, " .. across .. " columns away")
  local column, plan = request.column, {inserters = {}, free_taps = {}}
  local free = input_side.free_rows(column.size, request.connections)
  for index = 0, column.count - 1 do
    for _, row in ipairs(input_side.inserter_rows(column, request.connections, index, request.inserters)) do
      plan.inserters[#plan.inserters + 1] = {row = row}
    end
    for _, row in ipairs(free) do
      plan.free_taps[#plan.free_taps + 1] = output_side.machine_top(column, index) + row
    end
  end
  return weave.pole_rows(plan, request.pole_reach, request.pole_wire_distance, true)
end

-- The poles of the input inserters, in the tunnel column (see `input_side.pole_rows`), each wired to the one before it. Gives them, top down.
---@param entities bpgen.Entity[]
---@param request bpgen.InputSideRequest
---@return bpgen.Entity[]
function input_side.add_poles(entities, request)
  local poles = {}
  for _, row in ipairs(input_side.pole_rows(request)) do
    poles[#poles + 1] = entity_list.append(entities, {name = request.pole, position = grid.position(request.tunnel_column, row)})
    if #poles > 1 then
      entity_list.connect_poles(poles[#poles - 1], poles[#poles])
    end
  end
  return poles
end

-- The input side of a column of machines, appended to `entities`: the underground pipes, the inserters and their poles. Gives the poles,
-- wired from the top down.
---@param entities bpgen.Entity[]
---@param request bpgen.InputSideRequest
---@return bpgen.Entity[] poles
function input_side.add(entities, request)
  input_side.add_tunnels(entities, request)
  for index = 0, request.column.count - 1 do
    input_side.add_machine_inserters(entities, request, index)
  end
  return input_side.add_poles(entities, request)
end

return input_side
