-- scripts/fluid_boxes.lua
-- The fluid boxes of a machine of the game as plain data: where the pipes of each connect, for the machine facing north. It takes the prototype of
-- the machine and gives tiles, so that the layouts know nothing of the game. Pure of any other game access, like scripts/accounting.lua.

local fluid_boxes = {}

local north, east, south, west = defines.direction.north, defines.direction.east, defines.direction.south, defines.direction.west

-- The tile beyond a tile of a machine, as a step in tiles, by the way a pipe connection points.
---@type table<defines.direction, {x: integer, y: integer}>
local CONNECTION_STEPS = {
  [north] = {x = 0, y = -1}, [east] = {x = 1, y = 0}, [south] = {x = 0, y = 1}, [west] = {x = -1, y = 0},
}

-- Whether a tile is one of the tiles of a machine of `size` tiles on a side, counted from its top-left tile.
---@param tile {x: integer, y: integer}
---@param size integer
---@return boolean
local function on_machine(tile, size)
  return tile.x >= 0 and tile.x < size and tile.y >= 0 and tile.y < size
end

-- The tile of the pipe at a pipe connection of a machine of `size` tiles, from its top-left tile, as it faces north. The game gives
-- a connection as the position, from the centre of the machine, of the tile OF THE MACHINE it is on, at its edge, and the way it
-- points (its own example is the assembling machine 2: `position = {0, -1}`, `direction = north`, so the connection is on the top
-- row, in the middle). The pipe stands on the tile beyond, outside the machine. `positions` has the position for each of the four
-- ways the machine can face, the one for north first. Nil for a connection that is not an ordinary one (an underground one, a
-- linked one).
---@param connection PipeConnectionDefinition
---@param size integer
---@return {x: integer, y: integer}|nil
local function connection_tile(connection, size)
  if connection.connection_type ~= "normal" then
    return nil
  end
  local position = assert(connection.positions[1], "generator: the game does not give the position of a pipe connection of the machine")
  local step = assert(CONNECTION_STEPS[connection.direction], "generator: the game gives a pipe connection of the machine a direction other than north, east, south or west")
  local on = {x = math.floor(size / 2 + position.x), y = math.floor(size / 2 + position.y)}
  local beyond = {x = on.x + step.x, y = on.y + step.y}
  assert(on_machine(on, size) and not on_machine(beyond, size), string.format(
    "generator: a pipe connection of the machine is on the tile %d,%d and points to the tile %d,%d, which is not from a tile at the edge of the machine to one outside it (%d tiles on a side)",
    on.x, on.y, beyond.x, beyond.y, size))
  return beyond
end

-- The fluid boxes of a machine as plain data: where the pipes of each connect, for the machine facing north.
---@param machine LuaEntityPrototype
---@param size integer
---@return bpgen.FluidBox[]
function fluid_boxes.read(machine, size)
  local boxes = {}
  for _, box in ipairs(machine.fluidbox_prototypes) do
    local tiles = {}
    for _, connection in ipairs(box.pipe_connections) do
      tiles[#tiles + 1] = connection_tile(connection, size)
    end
    boxes[#boxes + 1] = {production_type = box.production_type, tiles = tiles}
  end
  return boxes
end

return fluid_boxes
