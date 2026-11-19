-- scripts/entity_list.lua
-- The entity list of a blueprint: blueprints identify entities by number, so an entity gets its number as it is added, from 1
-- and with no gaps. Pure, like scripts/layout.lua.

local entity_list = {}

-- Adds `entity` at the end of `list` and gives it the number of its place.
---@param list bpgen.Entity[]
---@param entity bpgen.NewEntity
---@return bpgen.Entity
function entity_list.append(list, entity)
  local numbered = entity --[[@as bpgen.Entity]] -- it gets its number just below
  list[#list + 1] = numbered
  numbered.entity_number = #list
  return numbered
end

return entity_list
