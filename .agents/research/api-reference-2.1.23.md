# Factorio 2.1.23 API reference (verified)

Source: `runtime-api.json` and `prototype-api.json`, supplied by the owner on 2026-10-24. Both report `application_version` 2.1.23 and `api_version` 6. Everything here was read from those files unless marked otherwise. When the owner supplies newer files, re-check this page and update the version in the title.

## Reading the JSON files (gotchas)

- Parameter lists are NOT in call order. Sort by each parameter's `order` field. Example: `add_command` lists function, help, name, but the call order is name, help, function.
- `BlueprintEntity` keeps its entity-type-specific fields under `variant_parameter_groups` inside its `type`, not under `properties`.
- Methods flagged `format.takes_table` take one table of named arguments (for example `build_blueprint{...}`).
- Absence from the JSON does not mean absence from the game. The `storage` table is not documented in these files at all.
- The files are about 2 MB each. Query them with a script; do not read them whole.

## Shortcut button (data stage)

- Prototype `type = "shortcut"`. `action` is required. Allowed values: `toggle-alt-mode`, `undo`, `redo`, `paste`, `import-string`, `toggle-personal-roboport`, `toggle-personal-logistic-requests`, `toggle-equipment-movement-bonus`, `spawn-item`, `lua`.
- With `action = "lua"`, clicking the button raises `on_lua_shortcut`.
- Icons: `icon` plus `icon_size` (default 64), unless `icons` (a list of `IconData`) is given. Small icon: `small_icon` plus `small_icon_size` (default 64), unless `small_icons` is given. The docs describe `icon_size` as the size of a SQUARE icon, and say the base game uses 32 px icons and 24 px small icons.
- `IconData` has no `mipmap_count`, and neither does `ShortcutPrototype`.
- Optional fields: `associated_control_input` (only shows the keybind in the tooltip), `order`, `style` (`default`, `blue`, `red`, `green`), `technology_to_unlock`, `unavailable_until_unlocked`, `item_to_spawn` (for `spawn-item`), `toggleable` (default false; must be true before `LuaPlayer.set_shortcut_toggled` works).
- Runtime: `LuaPlayer.is_shortcut_available`, `set_shortcut_available`, `is_shortcut_toggled`, `set_shortcut_toggled`; `prototypes.shortcut`.
- The official shortcut example in the 2.1.23 prototype docs: `icon = "__base__/graphics/icons/shortcut-toolbar/mip/new-deconstruction-planner-x56.png"`, `icon_size = 56`, `small_icon = ".../...-x24.png"`, `small_icon_size = 24`, plus `localised_name = {"shortcut.make-deconstruction-planner"}`. The repo's files (36x24 and 84x56 px, read from the PNG headers) follow this same naming. The widths are 1.5 times the heights, consistent with a strip holding a full-size icon plus a half-size copy; so `icon_size` is the height of one icon, not the image width. Using the sizes 56 and 24 is therefore the standard pattern. Rendering is still untested.
- `localised_name` can be set directly on a shortcut (it is a property of `PrototypeBase`); it overrides the name from the locale file and takes a LocalisedString such as `{"section.key"}`.
- A mod's own folder is addressed in file paths as `__<mod-name>__/...` (FileName docs); `..` paths are not supported.

## Events, commands, settings

- `on_lua_shortcut` data: `name`, `player_index` (uint32), `prototype_name` (string), `tick`.
- `script.on_event(event, handler, filters?)`, `script.on_init(handler)`, `script.on_load(handler)`, `script.on_configuration_changed(handler)`, `script.register_metatable(name, metatable)`. Attributes `script.mod_name` and `script.active_mods` (table of name to version).
- `commands.add_command(name, help, function)`. It errors if the name is already used. `commands.remove_command(name)`. Per the docs, registrations do not persist through save and load, so they must be made again whenever the script loads (inference: register them at the top level of `control.lua`).
- `CustomCommandData`: `name`, `tick`, optional `parameter` (string) and `player_index` (nil when issued from the server console).
- `LuaPlayer.print(message, print_settings?)` prints a message to a player.
- Settings: `settings.startup`, `settings.global`, `settings.player_default`, `settings.get_player_settings(player)`; each entry has a `.value`. The wiki tutorial (https://wiki.factorio.com/Tutorial:Mod_settings, last edited September 2025, so not 2.1-specific) says settings are defined in `settings.lua` with `data:extend`, in three kinds (startup, runtime-global, runtime-per-user), of types bool, int, double, string and color.

## Cursor and blueprint items

- `LuaControl.cursor_stack` (a `LuaItemStack`, may be nil), `is_cursor_blueprint()`, `is_cursor_empty()`. `LuaPlayer.clear_cursor()`; `LuaPlayer.cursor_stack_temporary` (read/write boolean; its description text was not read). **Secondary** (forum, 2026-10-29): a temporary cursor stack is removed, not returned to the inventory, when the cursor is cleared; blueprints from the library behave this way ([Allow temporary cursor stack for selection tool](https://forums.factorio.com/viewtopic.php?p=669249), [Paste doesn't work with cursor_stack_temporary, 1.1.74](https://forums.factorio.com/104354)).
- `LuaItemStack.set_stack(stack?)` returns a boolean; `can_set_stack(stack?)` checks first. The argument is an `ItemStackIdentification`: a string (the item name, meaning a full stack), an `ItemStackDefinition`, or a `LuaItemStack`.
- `LuaItemStack.import_stack(data: string)` returns an int: 0 = succeeded, -1 = succeeded with errors, 1 = failed. `export_stack()` returns a string. They support blueprint, blueprint-book, deconstruction-planner, upgrade-planner and item-with-tags.
- The blueprint methods live on `LuaItemCommon`, the parent of `LuaItemStack`:
  - `set_blueprint_entities(entities: BlueprintEntity[], fix_positions?: boolean)`. If `fix_positions` is false, positions are left unchanged unless invalid for the current snapping.
  - `get_blueprint_entities()` returns a list or nil. Also `get_blueprint_entity_count()`, `get_blueprint_tiles()`, `set_blueprint_tiles(tiles)`, `is_blueprint_setup()`, `clear_blueprint()`.
  - Per-entity tags: `get_blueprint_entity_tag(s)`, `set_blueprint_entity_tag(s)`.
  - `create_blueprint{surface, force, area, ...}` and `build_blueprint{surface, force, position, direction?, build_mode?, ...}`.
  - Attributes: `is_blueprint`, `is_blueprint_book`, `blueprint_description`, `blueprint_snap_to_grid`, `blueprint_absolute_snapping`, `blueprint_position_relative_to_grid`.

## Blueprint entity format

- Base `BlueprintEntity` fields: `entity_number` (uint32, required, unique in the blueprint), `name` (required), `position` (required), `direction` (only when not north), `mirror`, `quality` (quality prototype name), `items` (`BlueprintInsertPlan[]`), `tags`, `wires`, `burner_fuel_inventory`.
- Extra fields depend on the entity TYPE. Relevant groups:
  - `assembling-machine`: `recipe`, `recipe_quality`, `control_behavior`
  - `furnace`: `control_behavior` only (no recipe field)
  - `mining-drill`: `filter`, `control_behavior`
  - `inserter`: `filters`, `filter_mode`, `use_filters`, `override_stack_size`, `spoil_priority`, `drop_position`, `pickup_position`, `control_behavior`
  - `transport-belt`: `control_behavior`; `underground-belt`: `type`
  - `splitter`: `filter`, `input_priority`, `output_priority`, `control_behavior`; `lane-splitter` has the same without `control_behavior`
  - `loader` and `loader-1x1`: `filters`, `filter_mode`, `type`, `belt_stack_size_override`, `control_behavior`
  - `pipe`, `pipe-to-ground`, `storage-tank`: `control_behavior`
  - There is no group for electric poles, so they use the base fields only.
- `wires` is a list of `BlueprintWire`, each a tuple: source entity number, source connector id, target entity number, target connector id.
- `defines.wire_connector_id` values: `circuit_green`, `circuit_red`, `combinator_input_green`, `combinator_input_red`, `combinator_output_green`, `combinator_output_red`, `pole_copper`, `power_switch_left_copper`, `power_switch_right_copper`.
- `defines.direction` has 16 values. The JSON's own ordering (0 to 15, clockwise from north) is: north, northnortheast, northeast, eastnortheast, east, eastsoutheast, southeast, southsoutheast, south, southsouthwest, southwest, westsouthwest, west, westnorthwest, northwest, northnorthwest. The JSON does not state numeric values, so always use `defines.direction.<name>` in code and never hard-code numbers.
- `BlueprintInsertPlan`: `id` (item name and quality) and `items` (which inventories and slots).

## Recipes

- Prototype stage (`RecipePrototype`, type `recipe`): `categories` (list of recipe category ids, default `{"crafting"}`) replaces `category`. These fields do NOT exist in 2.1.23: `category`, `additional_categories`, `result`, `result_count`, `normal`, `expensive`.
- `energy_required` (default 0.5) is the craft time in seconds at crafting speed 1. `ingredients` and `results` are lists of tagged tables:
  - item ingredient: `{type = "item", name, amount}`; fluid ingredient: `{type = "fluid", name, amount, ...}`
  - item product: `type`, `name`, and either `amount` or `amount_min` and `amount_max`, plus options such as `extra_count_fraction`. Fluid products are similar.
- Other fields: `allow_productivity` (default false), `maximum_productivity` (default 3.0), `allow_quality` (default true), `surface_conditions`, `enabled` (default true), `hidden`.
- Runtime: `prototypes.recipe[name]` is a `LuaRecipePrototype`, and `prototypes.get_recipe_filtered(filters)` searches. Attributes: `categories` (string list), `ingredients` (`{type, name, amount: double, ...}`), `products`, `energy`, `enabled`, `main_product`, `maximum_productivity`, `surface_conditions`, `allowed_effects`. Methods: `has_category(category)`, `get_product_amount(index, productivity?)`.
- A force's live recipe state is `LuaForce.recipes[name]`, a `LuaRecipe` with `enabled` (read/write), `hidden`, `categories`, `name`, `prototype`.
- Not read yet: the fields of `ItemProduct` and `FluidProduct` at runtime.

## Machines and mining

- `CraftingMachinePrototype` (abstract parent of assemblers and furnaces): required `crafting_categories`, `crafting_speed`, `energy_source`, `energy_usage`; optional `module_slots` (default 0), `allowed_effects`, `crafting_speed_quality_multiplier`, `fluid_boxes`.
- `AssemblingMachinePrototype` (type `assembling-machine`) adds `fixed_recipe`, `fixed_quality`, `ingredient_count`. `FurnacePrototype` (type `furnace`) adds required `source_inventory_size` and `result_inventory_size`. Both use `crafting_categories`, so one category lookup finds machines for smelting and for crafting.
- `MiningDrillPrototype` (type `mining-drill`): required `mining_speed`, `resource_categories`, `resource_searching_radius`, `vector_to_place_result`, `energy_source`, `energy_usage`; optional `module_slots`, `input_fluid_box`, `output_fluid_box`.
- `ResourceEntityPrototype` (type `resource`): `category` (default `basic-solid`), `minimum`, `normal`, `infinite`, required `stage_counts`.
- Runtime, via `prototypes.entity[name]` (`LuaEntityPrototype`): `get_crafting_speed(quality?)`, `get_max_energy_usage(quality?)`, `get_mining_drill_radius(quality?)`, `crafting_categories` (table of name to true), `resource_categories`, `mining_speed`, `energy_usage`, `module_inventory_size`, `tile_width`, `tile_height`, `collision_box`, `selection_box`, `belt_speed`, `items_to_place_this`, `resource_category`, `mineable_properties`. Base attributes (from `LuaPrototypeBase`): `name`, `type`, `hidden`, `group`, `subgroup`, `order`.
- `MineableProperties`: `minable`, `mining_time` (required), `products`, `required_fluid`, `fluid_amount`, `transfer_entity_health_to_products`.

## GUI

- `LuaGuiElement.add{...}` takes a table: `type` plus optional `name`, `caption`, `tooltip`, `elem_tooltip`, `enabled`, `visible`, `locked`, `ignored_by_interaction`, `style`, `tags`, `index`, `anchor`, `game_controller_interaction`, `raise_hover_events`. Type-specific arguments were not read.
- Element types: button, sprite-button, checkbox, flow, frame, label, line, progressbar, table, textfield, radiobutton, sprite, scroll-pane, drop-down, list-box, camera, choose-elem-button, text-box, slider, minimap, entity-preview, empty-widget, tabbed-pane, tab, switch, inventory.
- Events: `on_gui_click`, `on_gui_text_changed`, `on_gui_confirmed`, `on_gui_elem_changed`, `on_gui_selection_state_changed`, `on_gui_closed`, `on_gui_opened`.
- `LuaGuiElement` attributes include `caption`, `text`, `value`, `slider_value`, `elem_type`, `elem_value`, `items`, `selected_index`, `name`, `tags`, `style`, `type`. Methods include `add`, `clear`, `clear_items`, `destroy`, `add_item`.
- Player GUI root: `player.gui` is a `LuaGui`; its `screen` attribute is where free-floating windows go. `LuaGui` also has `center`, `children`, `goal`, `left`, `relative`, `top`.
- A `LuaGuiElement` indexed by a name (`parent[name]`) gives the DIRECT child with that name. Also `children`, `parent`, `destroy()` (removes the element and its children), `valid`, `name` (`""` when unnamed), `text` (textfield), `elem_value` (choose-elem-button), `auto_center` and `force_auto_center()` (frames stored directly in `screen`), `bring_to_front()`, `focus()`.
- `add{...}` variant fields used so far: `frame` and `flow` take `direction`; `textfield` takes `text`, `numeric`, `allow_decimal`, `allow_negative`, `is_password`, `lose_focus_on_confirm`, `icon_selector`; `choose-elem-button` takes `elem_type` (required; values include `item`, `fluid`, `recipe`, `entity`, `signal`, `technology` and others) plus `elem_filters`; `button` takes `mouse_button_filter`, `auto_toggle`, `toggled`; `drop-down` takes `items`, `selected_index`; `table` takes `column_count` plus line options.
- `player.opened` is the GUI the player has open. Setting it to a `LuaGuiElement` makes Esc and E raise `on_gui_closed` for that element.
- Event data: `on_gui_click` has `element`, `player_index`, `button`, `shift`, `control`, `alt`; `on_gui_closed` has `element` (optional), `player_index`, `gui_type`, and more; `on_gui_confirmed` and `on_gui_elem_changed` have `element` and `player_index`.
- `LuaPlayer.clear_cursor()` returns whether the cursor is now empty. `cursor_stack` is nil only when the player is a spectator.
- LocalisedString is a list `{"section.key", param1, param2}`; parameters may be strings, numbers, booleans or nested LocalisedStrings. Placeholders in the locale text are `__1__`, `__2__`, and so on.
- Not checked yet: style names for GUI elements.

## Quality and Space Age

- `BlueprintEntity.quality` and `recipe_quality` (assembling machines) exist. Recipes have `allow_quality` and `surface_conditions`. Machine getters take an optional `quality`, which defaults to normal when omitted.

## Helpers and statistics

- `helpers.write_file(filename, data, append?, for_player?)`, `helpers.table_to_json`, `helpers.json_to_table`, `helpers.game_version`, `helpers.stage` (`settings`, `prototype` or `runtime`) exist on the `helpers` object.
- `LuaForce.get_item_production_statistics(surface)` takes a surface argument. When these two arrived (2.0 or 2.1) is not known.

## Details used by the plate generator (verified in the JSON unless marked)

- Item picker filter: `elem_filters = {{filter = "name", name = {"iron-plate", "copper-plate"}}}` for `elem_type = "item"`. An `ItemPrototypeFilter` has `filter` (many values; includes `name`, `type`, `flag`, `subgroup`, `fuel`), optional `invert`, and `mode` (`or` by default, `and` binds tighter). The `name` filter takes a string or a list of strings.
- Recipe at runtime: `prototypes.recipe[name]` has `energy` (seconds at crafting speed 1), `ingredients` (each `type`, `name`, `amount`), `products` (items have `type`, `name`, optional `amount` or `amount_min`/`amount_max`, probabilities and more), and `get_product_amount(product_index, productivity?)`, the average per craft (called with a dot, not a colon).
- `prototypes.entity[name].get_crafting_speed(quality?)` returns a number, or nil if the entity is not a crafting machine. Names for display: `localised_name` on any prototype (it comes from `LuaPrototypeBase`).
- Belts: the runtime `LuaEntityPrototype.belt_speed` (double, nil unless the entity is a belt) is documented only as "the speed of this transport belt". The prototype stage docs for `speed` (on `TransportBeltConnectablePrototype`) say: `speed x 480 = items per second` for the whole belt (both lanes); the raw value is tiles travelled per tick relative to a full belt, i.e. `items/s / (4 items per lane x 2 lanes x 60 ticks per second)`; it is a fixed-point number with 8 bits of fraction (smallest step 0.00390625). One lane therefore carries `speed x 240` items/s, which is `speed x 14400` per minute. Assuming the runtime value equals the prototype `speed` is **unverified**.
- Poles: `get_supply_area_distance(quality?)` and `get_max_wire_distance(quality?)` exist on `LuaEntityPrototype`. In the prototype stage, `supply_area_distance` is the "radius" (3.5 means a 7x7 area) and `maximum_wire_distance` is the wire reach in tiles.
- Inserters: `LuaEntityPrototype` has `inserter_pickup_position` and `inserter_drop_position` (vectors), and `LuaEntity` has `pickup_position` and `drop_position`. The docs do not say which side an inserter's `direction` refers to. **Unverified (memory):** the direction is the side it picks up from. The generator relies on this; see `../project-status.md`.
- Blueprint wires: `BlueprintEntity.wires` is described only as "wires connected to this entity in the blueprint", and a `BlueprintWire` is a four-entry tuple (source entity number, source connector, target entity number, target connector). Whether a wire appears on one entity or both is **unverified**. The generator lists each wire once, on the source entity.

## Added 2026-10-31 (iron gear iteration)

- **Verified** (`runtime-api.json` 2.1.23): `LuaEntityPrototype.tile_width` and `tile_height` (uint32); `get_inserter_rotation_speed(quality?)` and `get_inserter_extension_speed(quality?)` (optional double: nil when the entity is not an inserter); `inserter_stack_size_bonus` (optional); `get_crafting_speed(quality?)`.
- **Unverified**: the unit of the rotation speed. The JSON gives no unit; the code assumes turns per tick (see `project-status.md`).

## Energy sources and fuel items (owner, 2026-11-03)

Source: the owner described these from the 2.1 documentation and pasted the `ItemPrototypeFilter` page; the assistant could not check the JSON (it was no longer in the session). Treat as **Owner-stated**, not read from `runtime-api.json`.

- `LuaEntityPrototype.burner_prototype` and `electric_energy_source_prototype` are nil when the entity does not use that energy source. A prototype has at most one of the two.
- `LuaBurnerPrototype.fuel_categories` is `dict[string -> true]`: only the keys matter.
- `LuaItemPrototype.fuel_categories` (plural, the categories a fuel item belongs to) replaced a singular `fuel_category` in 2.1.
- `prototypes.get_item_filtered(filters)`: each filter is a table with `filter` (a string such as `"fuel-category"`) plus fields that depend on it, `mode` (`"or"` by default, or `"and"`; `"and"` binds tighter) and `invert`. The `"fuel-category"` filter has one extra field, `["fuel-category"]` (a fuel category name). Other filters used later: `"name"` (`name`), `"type"` (`type`), `"fuel-value"` (`comparison`, `value`), `"fuel"`.
- Return type not confirmed (see project-status, "Unverified in the energy source iteration").
