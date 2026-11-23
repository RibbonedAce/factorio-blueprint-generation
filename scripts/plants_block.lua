-- scripts/plants_block.lua
-- The blocks that make an item in plants, or a fluid in machines, as `bpgen.PlantsBlock`s, which stand as columns among the columns of machines of a
-- recipe (see scripts/rows.lua): plastic bar from petroleum gas and coal (`fluid_plant.build_block`: refineries that make the gas and the plants that
-- take it), explosives (`item_fluid_chain.build_block`: the sulfur of its plants, its coal, and the plants of the explosives), battery
-- (`item_fluid_chain.build_nested_block`: the furnaces of the plates, the chain of the sulfuric acid and the plants of the battery) and, for blocks
-- whose product leaves by a pipe and not by a belt, the refineries of petroleum gas (`fluid_row.build`) and the chain of the sulfuric acid
-- (`item_fluid_chain.build_block` again, whose final plants make a fluid). Each builder
-- gives the entities, the groups of poles, where what comes in starts and where the product leaves; this module says the rest that `rows`
-- needs: the fluid each pipe brings, what each belt of raw items takes, the width and the height and the sizes of the machines. Pure, like
-- scripts/fluid_plant.lua.

local grid = require("scripts.grid")

local plants_block = {}

-- The starts of a block: each pipe with the fluid it brings (`fluids`, by the key of its start), and each belt of raw items with what it takes
-- (`feeds`, by key), unless the builder gave it one already.
---@param starts bpgen.EntryStart[]
---@param fluids table<string, string>
---@param feeds table<string, bpgen.Feed>
---@return bpgen.EntryStart[]
local function starts_of(starts, fluids, feeds)
  local told = {}
  for index, start in ipairs(starts) do
    local copy = {}
    for key, value in pairs(start) do
      copy[key] = value
    end
    if start.belt then
      copy.feed = start.feed or feeds[start.key]
    else
      copy.fluid = assert(fluids[start.key], "plants_block: no fluid is said for the pipe that starts as " .. start.key)
    end
    told[index] = copy
  end
  return told
end

-- How many columns and how many rows the entities take: one past the last column of the easternmost one and one past the last row of the lowest
-- one (a machine covers as many tiles as its size says). The belt the product leaves on is not always the last column: a belt that winds has
-- a column more, east of it.
---@param entities bpgen.Entity[]
---@param sizes table<string, integer>
---@return integer width
---@return integer height
local function extent_of(entities, sizes)
  local width, height = 0, 0
  for _, entity in ipairs(entities) do
    local size = sizes[entity.name] or 1
    local tile = grid.top_left_tile(entity.position, size, size)
    width, height = math.max(width, tile.x + size), math.max(height, tile.y + size)
  end
  return width, height
end

-- The block as `rows` takes it.
---@param made {entities: bpgen.Entity[], groups: bpgen.Entity[][], starts: bpgen.EntryStart[], product: {column: integer, last_row: integer}}
---@param fluids table<string, string>
---@param feeds table<string, bpgen.Feed>
---@param sizes table<string, integer>
---@return bpgen.PlantsBlock
local function finished(made, fluids, feeds, sizes)
  local width, height = extent_of(made.entities, sizes)
  assert(width > made.product.column, "plants_block: the belt the product leaves on is not among the entities of the block")
  return {
    entities = made.entities, pole_groups = made.groups, product = made.product, width = width, height = height,
    starts = starts_of(made.starts, fluids, feeds), sizes = sizes,
  }
end

-- Plants that make an item from a fluid and an item (plastic bar), with the machines that make the fluid, as `fluid_plant.build_block` gives
-- them. Its starts are "input" (the pipe of the fluid the machines of the row take), "supplied" (a second fluid that comes in beside the plants,
-- if the recipe takes one) and "items" (the belt of the item).
---@param block {entities: bpgen.Entity[], entries: {starts: bpgen.EntryStart[]}, groups: bpgen.Entity[][], product_belt: {column: integer, last_row: integer}}
---@param fluids table<string, string>  the fluid of each pipe, by the key of its start
---@param feeds table<string, bpgen.Feed>  what each belt takes, by the key of its start
---@param sizes table<string, integer>  the tiles on a side of each machine, by name
---@return bpgen.PlantsBlock
function plants_block.of_fluid_plant(block, fluids, feeds, sizes)
  return finished({entities = block.entities, groups = block.groups, starts = block.entries.starts, product = block.product_belt}, fluids, feeds, sizes)
end

-- A row of machines that make a fluid (`fluid_row.build`, turned by `fluid_row.turn`: the refineries that make petroleum gas), as a block that
-- makes a fluid: the pipe it leaves by is the last column, and the one start is the pipe that brings in the fluid its machines take.
---@param row {entities: bpgen.Entity[], entries: {input: {x: integer, y: integer}, output: {x: integer, y: integer}}}
---@param fluid string  what its machines take
---@param sizes table<string, integer>  the tiles on a side of each machine, by name
---@param names {pole: string, pipe: string}
---@return bpgen.PlantsBlock
function plants_block.of_fluid_row(row, fluid, sizes, names)
  local poles = {}
  for _, entity in ipairs(row.entities) do
    if entity.name == names.pole then
      poles[#poles + 1] = entity
    end
  end
  local starts = {{key = "input", x = row.entries.input.x, y = row.entries.input.y, name = names.pipe}}
  local product = {column = row.entries.output.x, last_row = row.entries.output.y, fluid = true}
  return finished({entities = row.entities, groups = {poles}, starts = starts, product = product}, {input = fluid}, {}, sizes)
end

-- The product of the final plants of a chain or a nested chain: for an item, the belt they drop it on, in the column the block puts its final
-- plants in, from its first row down to the last row of the last plant; for a fluid, the pipe that takes it away, down to its last row.
---@param final bpgen.ItemFluidPlantsBlock
---@param final_x integer
---@return {column: integer, last_row: integer, fluid?: boolean}
local function product_of(final, final_x)
  if final.output_belt then
    return {column = final_x + final.output_belt, last_row = final.last_row}
  end
  local last_row = assert(final.output_exit_row, "plants_block: the final plants give neither a belt nor a pipe")
  return {column = final_x + final.columns.output, last_row = last_row, fluid = true}
end

-- A chain that makes an item (explosives), as `item_fluid_chain.build_block` gives it. Its starts are those of the chain: "input" and "supplied"
-- (the pipes of its plants part), "final_fluid" (the pipe of the fluid its final plants take, joined to the other when it is the same fluid) and
-- the belt of raw items of its belts part.
---@param block bpgen.ItemFluidChainBlock
---@param fluids table<string, string>
---@param feeds table<string, bpgen.Feed>
---@param sizes table<string, integer>
---@return bpgen.PlantsBlock
function plants_block.of_chain(block, fluids, feeds, sizes)
  return finished({entities = block.entities, groups = block.groups, starts = block.starts, product = product_of(block.final, block.places.final_x)}, fluids, feeds, sizes)
end

-- A nested chain that makes an item (battery), as `item_fluid_chain.build_nested_block` gives it. Its starts are those of its parts, with the
-- name of the part before the key: "first:", "second:" and "chain:".
---@param block bpgen.NestedChainBlock
---@param fluids table<string, string>
---@param feeds table<string, bpgen.Feed>
---@param sizes table<string, integer>
---@return bpgen.PlantsBlock
function plants_block.of_nested(block, fluids, feeds, sizes)
  return finished({entities = block.entities, groups = block.groups, starts = block.starts, product = product_of(block.final, block.places.final_x)}, fluids, feeds, sizes)
end

return plants_block
