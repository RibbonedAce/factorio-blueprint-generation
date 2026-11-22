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

-- Records a copper wire between two poles. Each wire is stored once, on the pole it starts from, as {from number, connector, to number,
-- connector}.
---@param from bpgen.Entity
---@param to bpgen.Entity
function entity_list.connect_poles(from, to)
  local connector = defines.wire_connector_id.pole_copper
  from.wires = from.wires or {}
  from.wires[#from.wires + 1] = {from.entity_number, connector, to.entity_number, connector}
end

-- Adds the entities of `source` to `target`, each moved `dx` tiles east and `dy` tiles south and numbered after the ones in `target`,
-- and the wires of the poles of `source` with them (a wire says the numbers of the two poles it joins, which are not the same any
-- more). The entities of `source` are left as they are. For putting blueprints made apart into one (see scripts/item_fluid_chain.lua).
---@param target bpgen.Entity[]
---@param source bpgen.Entity[]  numbered from 1 with no gap, as an entity list is
---@param dx number
---@param dy number
---@return bpgen.Entity[] added  the new entities, in the order of `source`
function entity_list.merge(target, source, dx, dy)
  local added, numbers = {}, {}
  for index, entity in ipairs(source) do
    local copy = {}
    for key, value in pairs(entity) do
      copy[key] = value
    end
    copy.position, copy.wires = {x = entity.position.x + dx, y = entity.position.y + dy}, nil
    entity_list.append(target, copy)
    numbers[entity.entity_number], added[index] = copy.entity_number, copy
  end
  for index, entity in ipairs(source) do
    if entity.wires then
      local wires = {}
      for _, wire in ipairs(entity.wires) do
        wires[#wires + 1] = {numbers[wire[1]], wire[2], numbers[wire[3]], wire[4]}
      end
      added[index].wires = wires
    end
  end
  return added
end

return entity_list
