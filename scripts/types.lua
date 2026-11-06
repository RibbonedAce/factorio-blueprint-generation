---@meta _
-- scripts/types.lua
-- Type declarations only, for the editor (EmmyLua). Nothing requires this file
-- and the game never runs anything in it: `---@meta` tells the editor it only
-- describes types. The `---@` comments are ordinary Lua comments to Factorio.
--
-- The `bpgen.` prefix keeps our names apart from Factorio's own types (for
-- example its `BlueprintEntity`), which the Factorio Modding Toolkit supplies.

---@class bpgen.Names  prototype names the layout builds with
---@field machine string
---@field belt string
---@field inserter string
---@field pole string

---@class bpgen.Product  how one supported item is made (see config.lua)
---@field recipe string  recipe prototype name
---@field machine string  machine prototype name
---@field fuel? string  item the machine burns; nil for a machine that burns nothing (an electric one)

---@class bpgen.EnergySource  what a machine runs on
---@field kind "electric"|"burner"
---@field fuel_categories string[]  the fuel categories a burner machine accepts, sorted; empty for an electric one

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

---@class bpgen.PlanRequest  what the planner is asked
---@field product string  item name the player wants
---@field rate_per_minute number
---@field recipe bpgen.Recipe
---@field machine_speed number  the machine's crafting speed
---@field lane_items_per_minute number  what one belt lane carries
---@field fuel? string  item the machine burns; it takes one of the two input lanes
---@field inserters? bpgen.InserterLimits  nil means no limit: one inserter a side, full speed

---@class bpgen.MachineRates  what ONE machine does each minute, once its inserters are counted
---@field output number  items of the product it makes
---@field inputs bpgen.PlanInput[]  what it eats, per ingredient, in the recipe's order
---@field input_inserters integer  on its input side
---@field output_inserters integer  on its output side

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
