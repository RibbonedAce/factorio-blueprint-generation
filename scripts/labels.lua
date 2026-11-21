-- scripts/labels.lua
-- Puts a display panel beside every belt that the player brings in, showing the item it carries (or the fluid a pipe carries), so that it is easy to
-- see which resource goes where. Pure, like scripts/lights.lua, and it runs on the finished blueprint. Only the design that
-- brings in one belt of each material has such belts, each carrying one item (see scripts/inputs.lua).
--
-- A panel stands on a tile of its own that is free: nothing stands on it, no belt runs on to it, and it is not the tile
-- behind a pump, where the water comes in. For the entry at (x, y) the tiles tried are the ones above and
-- under it, then the ones above and under the tile west of it, in that order. A tile in the row of another entry, or right
-- above or under it, is skipped, so that a panel is never between two belts and so tells which one it belongs to. An entry that
-- has none of them free goes without a panel (the rest of the blueprint does not depend on it). A panel needs no power.
--
--     . P .      P = a panel; the entry is the first belt of the row, at x = 0
--     > > >      the belt the player brings in comes from the west, along this row
--     . P .

local entity_list = require("scripts.entity_list")
local grid = require("scripts.grid")
local lights = require("scripts.lights")

local labels = {}

-- The tiles tried for the panel of an entry, as steps from the entry tile, the first free one taken.
local TRIES = {{x = 0, y = -1}, {x = 0, y = 1}, {x = -1, y = -1}, {x = -1, y = 1}}

-- Whether a tile is in the row of an entry other than `supply` (where the belt the player brings in arrives) or right above
-- or under it.
---@param supply bpgen.Supply
---@param supplies bpgen.Supply[]
---@param y integer  the row of the tile
---@return boolean
local function next_to_another(supply, supplies, y)
  for _, other in ipairs(supplies) do
    if other ~= supply and math.abs(other.y - y) <= 1 then
      return true
    end
  end
  return false
end

-- The first free tile among those tried for `supply`, or nil.
---@param supply bpgen.Supply
---@param supplies bpgen.Supply[]
---@param blocked table<string, true>
---@return {x: integer, y: integer}|nil
local function spot_for(supply, supplies, blocked)
  for _, step in ipairs(TRIES) do
    local x, y = supply.x + step.x, supply.y + step.y
    if not blocked[grid.key(x, y)] and not next_to_another(supply, supplies, y) then
      return {x = x, y = y}
    end
  end
  return nil
end

-- Adds a display panel for each entry of `supplies` that has room for one, numbered after the entities there are.
---@param entities bpgen.Entity[]  the finished blueprint; the panels are appended
---@param supplies bpgen.Supply[]  the belts the player brings in
---@param options bpgen.LabelOptions
function labels.add(entities, supplies, options)
  local blocked = lights.taken_tiles(entities, {belts = options.belts, inlets = options.inlets, size_of = options.size_of})
  for _, supply in ipairs(supplies) do
    local spot = spot_for(supply, supplies, blocked)
    if spot then
      entity_list.append(entities, {
        name = options.panel, position = grid.position(spot.x, spot.y),
        icon = {type = supply.type or "item", name = supply.item}, always_show = true,
      })
    end
  end
end

return labels
