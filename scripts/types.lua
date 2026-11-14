---@meta _
-- scripts/types.lua
-- Type declarations only, for the editor (EmmyLua). Nothing requires this file
-- and the game never runs anything in it: `---@meta` tells the editor it only
-- describes types. The `---@` comments are ordinary Lua comments to Factorio.
--
-- The `bpgen.` prefix keeps our names apart from Factorio's own types (for
-- example its `BlueprintEntity`), which the Factorio Modding Toolkit supplies.

---@class bpgen.SharedNames  prototype names every column of the layout builds with, and the numbers of its pole
---@field belt string
---@field inserter string
---@field pole string  the pole of the blueprint: the medium electric pole once the force has unlocked it, else the small one
---@field pole_supply_distance number  how far from its centre that pole powers, in tiles, as the game says (2.5 for a small pole, 3.5 for a medium one)
---@field pole_wire_distance number  the longest wire that pole holds, in tiles, as the game says (7.5 for a small pole, 9 for a medium one)
---@field long_inserter? string  the long-handed inserter, for a machine that takes from a second input belt
---@field fast_inserter? string  the fast inserter, for a machine whose side needs more than one plain inserter moves
---@field splitter? string  the splitter, for the input design that brings in one belt of each material
---@field underground? string  the underground belt, for the same design
---@field lamp? string  the small lamp, for the lights of the blueprint (see scripts/lights.lua)

-- What `lights.add` needs to know of the game.
---@class bpgen.LightOptions
---@field lamp string  prototype name of the lamp
---@field pole string  prototype name of the pole that powers it
---@field supply_distance number  how far from its centre a pole powers, in tiles (2.5 for a small pole)
---@field size_of fun(entity: bpgen.Entity): integer, integer  how many tiles across and along the map an entity covers
---@field belts? string[]  prototype names of belts, whose tile ahead of them stays free for the belt to go on

---@class bpgen.Names : bpgen.SharedNames  prototype names one column of the layout builds with
---@field machine string
---@field recipe? string  the recipe to set on the machines: an assembling machine has to be told, a furnace picks its own

---@class bpgen.MachineChoice  the machine that makes the recipes of one category (see config.lua)
---@field machine string  machine prototype name
---@field fuel? string  item the machine burns; nil for a machine that burns nothing (an electric one)
---@field upgrade? string  machine prototype name that replaces `machine` when the force has unlocked it and the game has it; nil: none

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
---@field fast_items_per_minute? number  what one fast inserter moves, when the game has them researched: a side then uses fast inserters when one plain inserter is not enough, and as many as it takes. Nil: only plain inserters
---@field max_input integer  how many inserters the input side of a machine gets
---@field max_output integer  how many inserters the output side of a machine gets
---@field machine_size? integer  the machine's size in tiles, which decides whether its sides are full (a row of poles) and so whether its output belt can wind; nil when not said

---@class bpgen.StageRequest  one stage of a chain: a recipe made by one column of machines
---@field product string  item name this stage makes
---@field recipe bpgen.Recipe
---@field machine_speed number  the machine's crafting speed
---@field fuel? string  item the machine burns; it takes one of the two input lanes (a stage fed raw items, or one that eats one made ingredient)
---@field inserters? bpgen.InserterLimits  nil means no limit: one inserter a side, full speed
---@field wide? boolean  the stage may be built wide, which the planner does only when the rate asks more than the plain design makes: a stage fed raw items that burns fuel and eats one ingredient gets a second input belt (the ingredient on both its lanes), woven with the first (the ingredient on one lane, the fuel on the other) so that two plain inserters on every machine reach both, so three lanes of the ingredient, and an output belt that winds (two lanes of product), also when it feeds another column. The stage that eats its product takes it on both lanes, if it eats nothing else and burns no fuel, and the stage must be the root or such a stage's supplier. Needs `inserters.machine_size`, one plain inserter on each side of a machine, and poles that reach the input side from the output side (the generator checks the last)

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
---@field input_inserters integer  inserters per machine, for belt a
---@field input_fast boolean  whether those are fast inserters
---@field long_inserters integer  long-handed inserters per machine, for belt b (0 when belt b carries nothing)
---@field output_inserters integer  per machine
---@field output_fast boolean  whether those are fast inserters
---@field wide boolean  whether the stage is built wide (see `bpgen.StageRequest.wide`): `lanes` then has the four lanes of its two input belts, and each machine has two plain input inserters, one for each belt

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
---@field input_inserters integer  inserters per machine, for the input belt next to the machine
---@field input_fast? boolean  whether those are fast inserters (plain when nil)
---@field long_inserters? integer  long-handed inserters per machine, in the rows under the plain ones, for a second belt one column further out (0 when nil); the two kinds together are at most `machine_size`
---@field output_inserters integer  per machine, at most `machine_size`; a 3x3 machine with two (and no pole rows) gets a winding output belt
---@field output_fast? boolean  whether those are fast inserters (plain when nil)
---@field output_paired? boolean  the machines go in twos and the output belt winds, whatever the size of the machine and the inserter (plain, for a furnace), so that machines side by side fill a lane each and the product rides both lanes, also when the belt feeds another column; needs one output inserter and at least two machines
---@field powered_from_output? boolean  the inserters of the input side stand within reach of the poles beside the output side (a medium pole reaches the input inserters of a 2x2 machine from there), so the input side may be full without rows of poles between the machines; the output side keeps a free tile for each machine
---@field fuel_belt? boolean  the stage burns fuel and eats what the stage before it makes, which that stage puts on both lanes of the belt between them (it is built wide too): the fuel has a belt of its own, in a column beside the inserters (one column further east than usual) that goes under for two rows while the belt between the two stages detours through that column, so that two plain input inserters on every machine reach both (see `Builder:add_fuel_weave`); needs `output_paired` and `powered_from_output`
---@field second_input_belt? boolean  the column draws its two input belts itself, woven (belt a goes under for two rows in the column beside the inserters while belt b, one column west, comes into it and goes back; `input_inserters` is 2), since they come down from the band: for a stage fed raw items that takes its second belt from there; the first column of a chain only

-- One column of machines in a chain.
---@class bpgen.StageLayout
---@field machine_count integer  at least 1
---@field load? number  how many machines' worth of work the rate asks of the column: less than `machine_count` when the last machine is only partly used, `machine_count` when left out. It decides which way the belt to the next column runs, so that the direction does not change with the rate
---@field machine string  prototype name of the machine
---@field shape bpgen.Shape  the machine size must be one `supports_machine_size` accepts
---@field belt? "a"|"b"  for a stage that is a supplier: which input belt of the stage that eats it the product rides ("a" when nil): belt a is next to the machines, belt b one column further out, for the long-handed inserters
---@field recipe? string  the recipe to set on the machines; nil for a machine that picks its own recipe (a furnace)
---@field suppliers? (bpgen.StageLayout|bpgen.RawSupplier)[]  what it eats: the stages whose products it eats, in the order of the recipe's ingredients, then the raw item that goes with them, if any; none or one in a chain, two when a recipe has two made ingredients or one made ingredient and a raw one (`rows.build` uses it; `layout.build_chain` ignores it)
---@field feed? bpgen.Feed  of a stage that eats only raw items: what it takes from the belts that come in a minute (`rows.build_pure` uses it; the original `rows.build` ignores it)
---@field second_feed? bpgen.Feed  of a stage built wide (its shape has `second_input_belt`): what it takes from its second input belt, one item on both lanes; `feed` is then what it takes from the first belt, the ingredient on one lane and the fuel on the other
---@field fuel_feed? bpgen.Feed  of a stage that burns fuel and eats what the stage before it in its chain makes (steel plate from iron plates): the fuel it takes a minute. It rides the free lane of the belt between the two stages, which therefore runs south, and is side-loaded at the head of that belt (`rows.build_pure` only; the original `rows.build` cannot do it)

-- A raw item that a stage eats next to a made one: no machines, only a belt that brings the
-- item to the column that eats it (see scripts/rows.lua).
---@class bpgen.RawSupplier
---@field raw_item string  the item
---@field feed? bpgen.Feed  what the stage takes of it, a minute

-- What a stage fed raw items, or the column of a raw item, takes from the belts that come in, a minute.
---@class bpgen.Feed
---@field items bpgen.FeedItem[]  one item rides both lanes of its belt (wood for a chest); two ride one lane each, the second being the fuel

---@class bpgen.FeedItem
---@field name string
---@field amount number  a minute

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
---@field fuel_feeds bpgen.FuelFeed[]  the stages of the block that take fuel from the belt before them, left to right

-- Where fuel has to arrive for a stage that burns it and eats what the stage before it makes: the belt between the two
-- stages runs south from `row`, and the fuel is side-loaded onto its free lane from the tile above it. A stage built wide
-- has a belt of fuel of its own instead (`woven`): the fuel comes straight down into its first tile, in the column beside
-- the stage's inserters, from `row`.
---@class bpgen.FuelFeed
---@field stage bpgen.StageLayout
---@field belt_column integer  tile column of the belt between the two stages, in the frame of the block (of the belt of fuel, when `woven`)
---@field row integer  tile row of the first tile of that belt, in the frame of the block
---@field woven boolean  the fuel has a belt of its own, woven with the belt between the two stages (see `bpgen.Shape.fuel_belt`)

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
---@field type? "input"|"output"  of an underground belt: the entrance or the exit

---@class bpgen.Entity : bpgen.NewEntity  one entity of a blueprint, as Factorio's set_blueprint_entities wants it
---@field entity_number integer
---@field wires? bpgen.Wire[]  stored on the pole the wire starts from

-- The input design that brings in one belt of each material (see .agents/inputs-plan.md) is asked for
-- by passing these to `rows.build_pure`; the original design is `rows.build` without them.
---@class bpgen.InputOptions
---@field lane_items_per_minute number  what one lane of a belt carries
---@field underground_reach integer  the most tiles an underground belt spans, from its entrance to its exit

-- A belt of one material that the player brings in: the tile where it starts, at the west edge. The item rides both lanes.
---@class bpgen.Input
---@field x integer  tile column
---@field y integer  tile row
---@field item string

-- What `scripts/poles.lua` needs to put poles between two that are further apart than a wire reaches: the blueprint's
-- entities to add them to, which tiles are taken, and the pole's name and wire.
---@class bpgen.PoleBridge
---@field entities bpgen.Entity[]  the poles are added after the ones there, numbered
---@field taken table<string, true>  the tiles that hold something, by "x,y" (see `poles.taken_tiles`)
---@field pole string  prototype name of the pole
---@field wire_distance number  the longest wire the pole holds, in tiles (see `bpgen.SharedNames.pole_wire_distance`)

-- A chain or the column of a raw item, as `scripts/feeds.lua` sees it.
---@class bpgen.FeedLeaf
---@field index number  place among the columns, from the west (a fraction for the fuel of a stage in the middle of a chain, just after its chain, and for the second input belt of a chain built wide, just before it)
---@field feed bpgen.Feed
---@field drop_x? integer  the tile column its belt comes down, once the columns are placed
---@field second_of? bpgen.Column  for the second input belt of a chain built wide: the chain
---@field owner? bpgen.Column  for a fuel feed: the chain column whose stage burns the fuel
---@field fuel? bpgen.FuelFeed  for a fuel feed: where the fuel has to arrive in the block of `owner`

-- A belt along the top of the blueprint that feeds some leaves with what they take.
---@class bpgen.Trunk
---@field items string[]  one name (both lanes) or two (the ore on one lane, the fuel on the other)
---@field mixed boolean  whether it carries two items
---@field leaves bpgen.FeedLeaf[]  from the west
---@field demand table<string, number>  of each item, a minute
---@field first integer  the place of its first leaf
---@field last integer  the place of its last leaf
---@field number integer  from the top
---@field row? integer  its row, once laid out
---@field east? integer  the column of its last leaf, once the columns are placed

-- What one trunk needs of one item.
---@class bpgen.Feeder
---@field trunk bpgen.Trunk
---@field role "a"|"b"|"pure"  the ore of a mixed trunk, its fuel, or the whole of a trunk that carries one item
---@field flow number  a minute
---@field row? integer  the row of the belt that brings it, once laid out

-- A belt of one item that comes in, and what it feeds. With two feeders or more it is a bus.
---@class bpgen.PureBelt
---@field item string
---@field feeders bpgen.Feeder[]  in the order of the trunks
---@field bus? integer  of a belt with two feeders or more: its place among the buses, 0 for the one furthest east
---@field column? integer  of a bus, the tile column it comes down
---@field entry? integer  of a bus, the row it comes in
---@field last? integer  of a bus, the row of its last feeder

---@class bpgen.FeedPlan
---@field trunks bpgen.Trunk[]  the one whose last leaf is furthest east first
---@field belts bpgen.PureBelt[]
---@field buses bpgen.PureBelt[]  the belts with two feeders or more, the one with the most feeders first

---@class bpgen.Generated  a finished blueprint
---@field entities bpgen.Entity[]
---@field description string  text for the blueprint's description field
---@field message LocalisedString  shown to the player
