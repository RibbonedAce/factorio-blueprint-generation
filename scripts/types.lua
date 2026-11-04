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

---@class bpgen.RecipeItem
---@field name string
---@field amount number

---@class bpgen.Recipe  the numbers the planner needs, copied from a recipe prototype
---@field energy number  seconds per craft at crafting speed 1
---@field ingredients bpgen.RecipeItem[]
---@field products bpgen.RecipeItem[]

---@class bpgen.InserterLimits  what limits feeding and emptying a machine
---@field items_per_minute number  what one inserter moves
---@field max_per_side integer  how many inserters fit on one side of the machine

---@class bpgen.Plan  what the planner decided to build
---@field machines integer
---@field output_per_minute number
---@field ingredient string  item name
---@field ingredient_per_minute number
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
