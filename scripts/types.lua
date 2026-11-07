---@meta _
-- scripts/types.lua
-- Type declarations only, for the editor (EmmyLua). Nothing requires this file
-- and the game never runs anything in it: `---@meta` tells the editor it only
-- describes types. The `---@` comments are ordinary Lua comments to Factorio.
--
-- The `bpgen.` prefix keeps our names apart from Factorio's own types (for
-- example its `BlueprintEntity`), which the Factorio Modding Toolkit supplies.

---@class bpgen.SharedNames  prototype names every column of the layout builds with
---@field belt string
---@field inserter string
---@field pole string

---@class bpgen.Names : bpgen.SharedNames  prototype names one column of the layout builds with
---@field machine string

---@class bpgen.MachineChoice  the machine that makes the recipes of one category (see config.lua)
---@field machine string  machine prototype name
---@field fuel? string  item the machine burns; nil for a machine that burns nothing (an electric one)

---@class bpgen.Production  one way to make an item: its recipe and the machine the config picks for it
---@field recipe bpgen.Recipe
---@field machine string  machine prototype name
---@field fuel? string  item the machine burns

-- Why a chain could not be made:
--   "no-recipe"          the item itself is not made by anything we can build
--   "ambiguous"          more than one recipe makes an item on the way
--   "unsupported"        the recipe of an item on the way cannot be built
--   "several-crafted"    a step has more than one ingredient that is made from others
--   "extra-ingredient"   a step mixes the product of the step before with other ingredients
--   "cycle"              an item is, in the end, made from itself
---@alias bpgen.ChainReason "no-recipe"|"ambiguous"|"unsupported"|"several-crafted"|"extra-ingredient"|"cycle"

-- How an item is made, as far as the chain is concerned: `lookup(item)` returns
--   a `bpgen.Production`  when exactly one recipe makes it, in a machine we have,
--   nil, "no-recipe"      when nothing makes it (it is mined, or too basic to craft),
--   nil, "ambiguous"      when several recipes make it, and we cannot choose,
--   nil, "unsupported"    when its recipe cannot be built (a fluid, say).
-- An ingredient with no recipe is a raw item; the item asked for with no recipe is a failure.
---@alias bpgen.RecipeLookup fun(item: string): bpgen.Production|nil, bpgen.ChainReason|nil

---@class bpgen.ChainStage : bpgen.Production  one step of the chain from raw items to the product
---@field item string  the item this step makes

---@class bpgen.RecipeItem
---@field name string
---@field amount number

---@class bpgen.Recipe  the numbers the planner needs, copied from a recipe prototype
---@field energy number  seconds per craft at crafting speed 1
---@field ingredients bpgen.RecipeItem[]
---@field products bpgen.RecipeItem[]

---@class bpgen.InserterLimits  what limits feeding and emptying a machine
---@field items_per_minute number  what one inserter moves
---@field max_input integer  how many inserters the input side of a machine gets
---@field max_output integer  how many inserters the output side of a machine gets

---@class bpgen.StageRequest  one stage of a chain: a recipe made by one column of machines
---@field product string  item name this stage makes
---@field recipe bpgen.Recipe
---@field machine_speed number  the machine's crafting speed
---@field fuel? string  item the machine burns; it takes one of the two input lanes (first stage only)
---@field inserters? bpgen.InserterLimits  nil means no limit: one inserter a side, full speed

---@alias bpgen.PlanReason "unsupported-recipe"|"rate-too-high"  why the planner gave no plan

---@class bpgen.ChainRequest  what the planner is asked for a chain of stages
---@field rate_per_minute number  of the last stage's product
---@field lane_items_per_minute number  what one belt lane carries
---@field stages bpgen.StageRequest[]  from the stage fed raw items to the one that makes what the player wants

---@class bpgen.PlanRequest : bpgen.StageRequest  what the planner is asked for one stage on its own
---@field rate_per_minute number  of the product
---@field lane_items_per_minute number  what one belt lane carries

---@class bpgen.PlanInput  how much of an ingredient is eaten each minute (by one machine or by all of them)
---@field name string  item name
---@field per_minute number

---@class bpgen.Plan  what the planner decided to build
---@field machines integer
---@field output_per_minute number
---@field inputs bpgen.PlanInput[]  per ingredient, in the recipe's order
---@field lanes string[]  the item on each of the input belt's two lanes
---@field input_inserters integer  per machine
---@field output_inserters integer  per machine

---@class bpgen.Position  the centre of an entity, in tiles
---@field x number
---@field y number

---@class bpgen.Tile  the top-left tile an entity covers (whole numbers unless misaligned)
---@field x number
---@field y number

---@alias bpgen.Wire [integer, defines.wire_connector_id, integer, defines.wire_connector_id]  {from entity number, connector, to entity number, connector}

-- What the layout needs to know about the machine.
---@class bpgen.Shape
---@field machine_size integer  tiles wide and tall; see `supports_machine_size`
---@field input_inserters integer  per machine, at most `machine_size`
---@field output_inserters integer  per machine, at most `machine_size`; a 3x3 machine with two (and no pole rows) gets a winding output belt

-- One column of machines in a chain.
---@class bpgen.StageLayout
---@field machine_count integer  at least 1
---@field machine string  prototype name of the machine
---@field shape bpgen.Shape  the machine size must be one `supports_machine_size` accepts

---@class bpgen.NewEntity  an entity as the layout describes it, before it gets its number
---@field name string
---@field position bpgen.Position
---@field direction? defines.direction

---@class bpgen.Entity : bpgen.NewEntity  one entity of a blueprint, as Factorio's set_blueprint_entities wants it
---@field entity_number integer
---@field wires? bpgen.Wire[]  stored on the pole the wire starts from

---@class bpgen.Generated  a finished blueprint
---@field entities bpgen.Entity[]
---@field description string  text for the blueprint's description field
---@field message LocalisedString  shown to the player
