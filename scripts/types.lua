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
---@field long_inserter? string  the long-handed inserter, for a machine that takes from a second input belt

---@class bpgen.Names : bpgen.SharedNames  prototype names one column of the layout builds with
---@field machine string
---@field recipe? string  the recipe to set on the machines: an assembling machine has to be told, a furnace picks its own

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
--   "several-crafted"    a step has more than two ingredients that are made from others
--   "extra-ingredient"   a step with made ingredients has more than two ingredients in all
--   "fork-in-chain"      a step with one made ingredient is fed by a step with two inputs (two made ingredients, or one made and one raw)
--   "cycle"              an item is, in the end, made from itself
---@alias bpgen.ChainReason "no-recipe"|"ambiguous"|"unsupported"|"several-crafted"|"extra-ingredient"|"fork-in-chain"|"cycle"

-- How an item is made, as far as the chain is concerned: `lookup(item)` returns
--   a `bpgen.Production`  when exactly one recipe makes it, in a machine we have,
--   nil, "no-recipe"      when nothing makes it (it is mined, or too basic to craft),
--   nil, "ambiguous"      when several recipes make it, and we cannot choose,
--   nil, "unsupported"    when its recipe cannot be built (a fluid, say).
-- An ingredient with no recipe is a raw item; the item asked for with no recipe is a failure.
---@alias bpgen.RecipeLookup fun(item: string): bpgen.Production|nil, bpgen.ChainReason|nil

---@class bpgen.ChainStage : bpgen.Production  one step on the way from raw items to the product
---@field item string  the item this step makes
---@field suppliers bpgen.ChainStage[]  the steps that make its made ingredients, in the recipe's order: none for a step fed raw items, one in a chain, two for a recipe with two made ingredients
---@field raw_item? string  the one raw ingredient of a step that has one made ingredient and one raw one: it rides the other lane of the input belt

---@class bpgen.RecipeItem
---@field name string
---@field amount number

---@class bpgen.Recipe  the numbers the planner needs, copied from a recipe prototype
---@field name? string  the name of the recipe prototype, which a blueprint uses to set the recipe of an assembling machine
---@field energy number  seconds per craft at crafting speed 1
---@field ingredients bpgen.RecipeItem[]
---@field products bpgen.RecipeItem[]

---@class bpgen.InserterLimits  what limits feeding and emptying a machine
---@field items_per_minute number  what one inserter moves
---@field long_items_per_minute? number  what one long-handed inserter moves; a plain inserter's figure when nil
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

---@class bpgen.StageTree  a stage with the stages that make its ingredients
---@field stage bpgen.StageRequest
---@field suppliers bpgen.StageTree[]  none for a stage fed raw items; otherwise one for each ingredient, in the recipe's order (one in a chain, two when the recipe has two made ingredients)

---@class bpgen.TreeRequest  what the planner is asked for a tree of stages
---@field rate_per_minute number  of the root stage's product
---@field lane_items_per_minute number  what one belt lane carries
---@field root bpgen.StageTree  the stage that makes what the player wants

---@class bpgen.PlanTree  the plans for a tree of stages
---@field plan bpgen.Plan  the plan of the stage
---@field suppliers bpgen.PlanTree[]  the plans of the stages that feed it, in the order of the request's

---@class bpgen.PlanRequest : bpgen.StageRequest  what the planner is asked for one stage on its own
---@field rate_per_minute number  of the product
---@field lane_items_per_minute number  what one belt lane carries

---@class bpgen.PlanInput  how much of an ingredient is eaten each minute (by one machine or by all of them)
---@field name string  item name
---@field per_minute number

---@class bpgen.Plan  what the planner decided to build
---@field machines integer
---@field load number  how many machines' worth of work the rate asks of the stage: less than `machines` when the last machine is only partly used
---@field output_per_minute number
---@field inputs bpgen.PlanInput[]  per ingredient, in the recipe's order
---@field lanes string[]  the item on each lane of the input belt: two for a stage fed raw items, one for each ingredient of any other
---@field belts bpgen.Belts  which ingredients ride which input belt: all on belt a, except for a stage with three or four ingredients
---@field input_inserters integer  plain inserters per machine, for belt a
---@field long_inserters integer  long-handed inserters per machine, for belt b (0 when belt b carries nothing)
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
---@field input_inserters integer  plain inserters per machine, for the input belt next to the machine
---@field long_inserters? integer  long-handed inserters per machine, in the rows under the plain ones, for a second belt one column further out (0 when nil); the two kinds together are at most `machine_size`
---@field output_inserters integer  per machine, at most `machine_size`; a 3x3 machine with two (and no pole rows) gets a winding output belt

-- One column of machines in a chain.
---@class bpgen.StageLayout
---@field machine_count integer  at least 1
---@field load? number  how many machines' worth of work the rate asks of the column: less than `machine_count` when the last machine is only partly used, `machine_count` when left out. It decides which way the belt to the next column runs, so that the direction does not change with the rate
---@field machine string  prototype name of the machine
---@field shape bpgen.Shape  the machine size must be one `supports_machine_size` accepts
---@field belt? "a"|"b"  for a stage that is a supplier: which input belt of the stage that eats it the product rides ("a" when nil): belt a is next to the machines, belt b one column further out, for the long-handed inserters
---@field recipe? string  the recipe to set on the machines; nil for a machine that picks its own recipe (a furnace)
---@field suppliers? (bpgen.StageLayout|bpgen.RawSupplier)[]  what it eats: the stages whose products it eats, in the order of the recipe's ingredients, then the raw item that goes with them, if any; none or one in a chain, two when a recipe has two made ingredients or one made ingredient and a raw one (`rows.build` uses it; `layout.build_chain` ignores it)

-- A raw item that a stage eats next to a made one: no machines, only a belt that brings the
-- item to the column that eats it (see scripts/rows.lua).
---@class bpgen.RawSupplier
---@field raw_item string  the item

-- What a block is told about the product belt of its chain.
---@class bpgen.BlockOptions
---@field product_belt boolean  whether the chain draws its product belt, and may wind it (the last block of a blueprint), or whoever uses the block draws it

-- A part of a blueprint that makes one item: the columns of a chain (or one column, which
-- eats what other columns make). A block stands in a frame whose x = 0 is its
-- left edge and y = 0 its top; whoever uses it moves it.
---@class bpgen.Block
---@field entities bpgen.Entity[]  numbered from 1
---@field poles bpgen.Entity[]  every pole of the block, for wiring it to its neighbours
---@field product_column integer  tile column of the product belt, the rightmost column. The block does not draw it unless it is the last block of the blueprint
---@field height integer  rows
---@field output_rows {first: integer, last: integer}  the rows where the output inserters of the last column drop onto the product belt
---@field long_rows? {first: integer, last: integer}  the rows of the first and the last long-handed input inserter of the first column, nil when it has none
---@field raw_belts bpgen.RawBelt[]  where the belts of raw items start, from the top of the block down

-- The first tile of a belt of raw items, which runs south from there.
---@class bpgen.RawBelt
---@field stage bpgen.StageLayout|bpgen.RawSupplier  the stage fed raw items by the belt
---@field column integer  tile column
---@field row integer  tile row

---@class bpgen.NewEntity  an entity as the layout describes it, before it gets its number
---@field name string
---@field position bpgen.Position
---@field direction? defines.direction
---@field recipe? string  the recipe of an assembling machine

---@class bpgen.Entity : bpgen.NewEntity  one entity of a blueprint, as Factorio's set_blueprint_entities wants it
---@field entity_number integer
---@field wires? bpgen.Wire[]  stored on the pole the wire starts from

---@class bpgen.Generated  a finished blueprint
---@field entities bpgen.Entity[]
---@field description string  text for the blueprint's description field
---@field message LocalisedString  shown to the player
