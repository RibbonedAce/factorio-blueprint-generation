-- scripts/finishing.lua
-- The finishing touches of a blueprint that is laid out: the display panels beside what comes in at the top left corner and the lamps, when the
-- job asks for them (see scripts/labels.lua and scripts/lights.lua). Pure, like scripts/accounting.lua: it reads the names and the wishes of the
-- job and moves nothing.

local inputs = require("scripts.inputs")
local labels = require("scripts.labels")
local lights = require("scripts.lights")

local finishing = {}

-- Adds the sizes of the machines of a block made apart.
---@param sizes table<string, integer>
---@param block_sizes table<string, integer>
local function add_sizes(sizes, block_sizes)
  for machine, size in pairs(block_sizes) do
    sizes[machine] = size
  end
end

-- The tiles on a side of the machine of each column of the layout, by machine name: the names the entities carry.
---@param stage bpgen.StageLayout
---@param sizes table<string, integer>
---@return table<string, integer>
function finishing.machine_sizes_of(stage, sizes)
  sizes[stage.machine] = stage.shape.machine_size
  if stage.fluid_supplier then -- the part that makes its fluid has machines of its own
    add_sizes(sizes, stage.fluid_supplier.sizes)
  end
  for _, supplier in ipairs(stage.suppliers or {}) do
    if supplier.plants then -- a block made apart has machines of its own, which it gives the sizes of
      add_sizes(sizes, supplier.plants.sizes)
    elseif supplier.machine then -- a raw item has no machines
      finishing.machine_sizes_of(supplier, sizes)
    end
  end
  return sizes
end

-- Puts the display panels on the blueprint when the job asks for them (see scripts/labels.lua).
---@param job bpgen.Job
---@param entities bpgen.Entity[]
---@param root bpgen.StageLayout  what the blueprint was laid out from
---@param supplies bpgen.Supply[]  the belts the player brings in and the pipes of the blocks made apart (their `type` is "fluid")
function finishing.add_labels(job, entities, root, supplies)
  local wanted = {}
  for _, supply in ipairs(supplies) do
    if supply.type == "fluid" and job.row_labels or supply.type ~= "fluid" and job.labels then
      wanted[#wanted + 1] = supply
    end
  end
  if #wanted == 0 then
    return
  end
  local sizes = finishing.machine_sizes_of(root, {})
  labels.add(entities, wanted, {
    panel = job.names.panel,
    belts = {job.names.belt, job.names.underground},
    inlets = {job.names.pump},
    size_of = function(entity) return inputs.footprint(entity, job.names, sizes) end,
  })
end

-- Puts the lamps on the blueprint when the job asks for them (see scripts/lights.lua).
---@param job bpgen.Job
---@param entities bpgen.Entity[]
---@param root bpgen.StageLayout  what the blueprint was laid out from
---@param supplies bpgen.Supply[]  the belts the player brings in and the pipes of the blocks made apart: the tile west of each pipe stays free
function finishing.add_lights(job, entities, root, supplies)
  if not job.lamp_supply_distance then
    return
  end
  local sizes, free = finishing.machine_sizes_of(root, {}), {}
  for _, supply in ipairs(supplies) do
    if supply.type == "fluid" then
      free[#free + 1] = {x = supply.x - 1, y = supply.y}
    end
  end
  lights.add(entities, {
    lamp = job.names.lamp, pole = job.names.pole, supply_distance = job.lamp_supply_distance,
    belts = {job.names.belt, job.names.underground}, free_tiles = free,
    inlets = {job.names.pump}, -- the tile behind the pump is where the water comes in
    size_of = function(entity) return inputs.footprint(entity, job.names, sizes) end,
  })
end

-- Puts the lamps on a row of machines, or on plants with the machines that make their fluid, or on a chain of blocks, when the job asks for
-- them (see scripts/lights.lua). The tile a belt runs on to stays free, and so does the tile west of each entry of a pipe or a belt, where the
-- player joins it.
---@param job bpgen.Job
---@param entities bpgen.Entity[]
---@param inlets {key: string, x: integer, y: integer}[]  the entries of what comes in
---@param sizes table<string, integer>  the tiles on a side of each machine, by name
function finishing.add_row_lights(job, entities, inlets, sizes)
  if not job.lamp_supply_distance then
    return
  end
  local free = {}
  for _, inlet in ipairs(inlets) do
    free[#free + 1] = {x = inlet.x - 1, y = inlet.y}
  end
  lights.add(entities, {
    lamp = job.names.lamp, pole = job.names.pole, supply_distance = job.lamp_supply_distance, belts = {job.names.belt, job.names.underground},
    free_tiles = free, size_of = function(entity) return inputs.footprint(entity, job.names, sizes) end,
  })
end

-- Puts a display panel beside each entry of a pipe or a belt that comes in at the top left corner, showing the fluid or the item, once
-- the force has unlocked the display panel (see scripts/labels.lua). An entry that `things` has nothing for goes without.
---@param job bpgen.Job
---@param entities bpgen.Entity[]
---@param inlets {key: string, x: integer, y: integer}[]  the entries; the one with the key "items" is a belt, the others are pipes
---@param things table<string, {name: string, type: "item"|"fluid"}>  what each entry brings, by its key
---@param sizes table<string, integer>  the tiles on a side of each machine, by name
function finishing.add_inlet_labels(job, entities, inlets, things, sizes)
  if not job.row_labels then
    return
  end
  local supplies = {}
  for _, inlet in ipairs(inlets) do
    local thing = things[inlet.key]
    if thing then
      supplies[#supplies + 1] = {x = inlet.x, y = inlet.y, item = thing.name, type = thing.type}
    end
  end
  labels.add(entities, supplies, {
    panel = job.names.panel, belts = {job.names.belt, job.names.underground},
    size_of = function(entity) return inputs.footprint(entity, job.names, sizes) end,
  })
end

return finishing
