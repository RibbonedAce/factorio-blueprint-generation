-- scripts/grid.lua
-- Converts between the two ways of saying where an entity is.
--
--   TILE:      the top-left tile the entity covers, as whole numbers. x grows to
--              the east and y grows to the south (down the page). A furnace that
--              covers tiles x 2 to 3 and y 0 to 1 is at tile (2, 0). This is how
--              the layout and the tests think.
--   POSITION:  the centre of the entity, which is what Factorio blueprints want.
--              That same furnace is at position (3, 1); a 1x1 belt on tile
--              (0, 0) is at position (0.5, 0.5).
--
-- The centre is the tile plus half the entity's size, so the "+ 0.5" lives here
-- and nowhere else. Sizes are in tiles and default to 1x1. The module also names the tiles
-- of a set of tiles (`grid.key`) and says which tiles a list of entities covers
-- (`grid.taken_tiles`), so that no other module writes either. Pure: no game access.

local grid = {}

-- The centre position of an entity whose top-left tile is (tile_x, tile_y).
---@param tile_x number
---@param tile_y number
---@param width? number  tiles, default 1
---@param height? number  tiles, default 1
---@return bpgen.Position
function grid.position(tile_x, tile_y, width, height)
  return {x = tile_x + (width or 1) / 2, y = tile_y + (height or 1) / 2}
end

-- The top-left tile of an entity centred at `position`. The numbers are not whole
-- if the entity is not lined up with the tile grid.
---@param position bpgen.Position
---@param width? number  tiles, default 1
---@param height? number  tiles, default 1
---@return bpgen.Tile
function grid.top_left_tile(position, width, height)
  return {x = position.x - (width or 1) / 2, y = position.y - (height or 1) / 2}
end

-- The name of a tile in a set of tiles: "x,y", the same for 3 and 3.0, so that a tile found by arithmetic on positions
-- finds the one written down as whole numbers.
---@param x number
---@param y number
---@return string
function grid.key(x, y)
  return string.format("%g,%g", x, y)
end

-- The tiles that hold something, as a set of `grid.key`s: every tile each entity covers, from its top-left tile.
-- `size_of` says how many tiles an entity covers across and along the map.
---@param entities bpgen.Entity[]
---@param size_of fun(entity: bpgen.Entity): integer, integer
---@return table<string, true>
function grid.taken_tiles(entities, size_of)
  local taken = {}
  for _, entity in ipairs(entities) do
    local width, height = size_of(entity)
    local tile = grid.top_left_tile(entity.position, width, height)
    for dx = 0, width - 1 do
      for dy = 0, height - 1 do
        taken[grid.key(tile.x + dx, tile.y + dy)] = true
      end
    end
  end
  return taken
end

return grid
