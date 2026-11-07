-- control.lua
-- Runs every time a save is created or loaded. At the top level of this file we
-- may ONLY register things (event handlers); the game world is not available
-- yet. All real work happens inside the handler functions further down, which
-- the game calls later.

-- `require` loads another file of this mod (scripts/config.lua, written with a
-- dot instead of a slash) and gives back whatever that file `return`s. It may
-- only be called here at the top of the file, never inside a handler.
local config = require("scripts.config")
local generator = require("scripts.generator")

-- Names of the things we create, written once so a typo can't hide in a string.
-- They never change while the game runs, so file-level `local` constants like
-- these are safe (only variables that CHANGE at runtime cause multiplayer desyncs).
local SHORTCUT_NAME = "blueprint-generation-open"
local FRAME_NAME = "blueprint-generation-frame"
local ITEM_BUTTON_NAME = "blueprint-generation-item"
local RATE_FIELD_NAME = "blueprint-generation-rate"
local MAX_RATE_LABEL_NAME = "blueprint-generation-max-rate"
local GENERATE_BUTTON_NAME = "blueprint-generation-generate"
local CLOSE_BUTTON_NAME = "blueprint-generation-close"

-- Remove our window if it is open. `player.gui.screen[FRAME_NAME]` looks up a
-- direct child of the screen by name; it is nil when there is no such child.
---@param player LuaPlayer
local function close_window(player)
  local frame = player.gui.screen[FRAME_NAME]
  if frame then
    frame.destroy()
  end
end

-- The item picker only offers the products the generator supports. `elem_filters`
-- takes a list of filters; this one means "items whose name is one of these".
local function supported_item_filters()
  local names = {}
  for name in pairs(config.products) do
    names[#names + 1] = name
  end
  return {{filter = "name", name = names}}
end

-- Show, under the rate field, the most one blueprint of the picked item can make
-- per minute (or why that item cannot be made). The text is read from the game's
-- data each time, so it follows the belt, inserters and recipe in the current game.
---@param frame LuaGuiElement  our window
local function update_max_rate(frame)
  local item_name = frame[ITEM_BUTTON_NAME].elem_value --[[@as string|nil]] -- nil if nothing picked
  local label = frame[MAX_RATE_LABEL_NAME]
  if item_name then
    label.caption = generator.max_rate_message(item_name)
  else
    label.caption = {"blueprint-generation.max-rate-no-item"}
  end
end

-- Build the window. Everything the player can type or pick is a direct child
-- of `frame`, so Generate can find it again by name later. That means the GUI
-- itself remembers its state and we never need Factorio's `storage` table.
---@param player LuaPlayer
local function open_window(player)
  close_window(player) -- never end up with two windows

  local frame = player.gui.screen.add{
    type = "frame",
    name = FRAME_NAME,
    caption = {"blueprint-generation.window-title"},
    direction = "vertical",
  }
  frame.auto_center = true

  frame.add{type = "label", caption = {"blueprint-generation.item-label"}}
  local item_button = frame.add{
    type = "choose-elem-button",
    name = ITEM_BUTTON_NAME,
    elem_type = "item",
    elem_filters = supported_item_filters(),
  }
  item_button.elem_value = config.default_product -- the player can still change or clear it

  frame.add{type = "label", caption = {"blueprint-generation.rate-label"}}
  frame.add{type = "label", name = MAX_RATE_LABEL_NAME}
  frame.add{
    type = "textfield",
    name = RATE_FIELD_NAME,
    text = "60",
    numeric = true,
    allow_decimal = true,
  }

  update_max_rate(frame)

  local buttons = frame.add{type = "flow", direction = "horizontal"}
  buttons.add{type = "button", name = CLOSE_BUTTON_NAME, caption = {"blueprint-generation.close"}}
  buttons.add{type = "button", name = GENERATE_BUTTON_NAME, caption = {"blueprint-generation.generate"}}

  -- Makes the Esc and E keys close our window (this raises on_gui_closed).
  player.opened = frame
end

-- Read what the player entered, generate the blueprint and put it on their cursor.
---@param player LuaPlayer
local function generate_blueprint(player)
  local frame = player.gui.screen[FRAME_NAME]
  if not frame then
    return
  end

  local item_name = frame[ITEM_BUTTON_NAME].elem_value -- nil if nothing picked
  local rate = tonumber(frame[RATE_FIELD_NAME].text)   -- nil if the box is empty

  if not item_name then
    player.print({"blueprint-generation.error-no-item"})
    return
  end
  if not rate or rate <= 0 then
    player.print({"blueprint-generation.error-bad-rate"})
    return
  end

  -- Generate first, so a failure leaves the player's cursor untouched.
  local result, error_message = generator.generate(item_name, rate)
  if not result then
    player.print(error_message)
    return
  end

  local cursor = player.cursor_stack
  if not cursor then
    player.print({"blueprint-generation.error-no-cursor"})
    return
  end
  if not player.clear_cursor() then
    player.print({"blueprint-generation.error-cursor-full"})
    return
  end
  if not cursor.set_stack("blueprint") then
    player.print({"blueprint-generation.error-no-cursor"})
    return
  end

  -- A temporary cursor stack is deleted when the player clears the cursor, instead
  -- of being put into their inventory (like a blueprint taken from the library).
  player.cursor_stack_temporary = true

  cursor.set_blueprint_entities(result.entities)
  cursor.blueprint_description = result.description

  close_window(player)
  player.print(result.message)
end

-- The shortcut-bar button was clicked: open the window, or close it if open.
script.on_event(defines.events.on_lua_shortcut, function(event)
  if event.prototype_name ~= SHORTCUT_NAME then
    return -- some other mod's shortcut
  end
  local player = game.get_player(event.player_index)
  if not player then
    return
  end

  if player.gui.screen[FRAME_NAME] then
    close_window(player)
  else
    open_window(player)
  end
end)

-- Any GUI button anywhere was clicked. Only react to our two buttons.
script.on_event(defines.events.on_gui_click, function(event)
  local name = event.element.name
  local player = game.get_player(event.player_index)
  if not player then
    return
  end

  if name == GENERATE_BUTTON_NAME then
    generate_blueprint(player)
  elseif name == CLOSE_BUTTON_NAME then
    close_window(player)
  end
end)

-- The player picked another item, or cleared it: show that item's maximum rate.
script.on_event(defines.events.on_gui_elem_changed, function(event)
  if event.element.name ~= ITEM_BUTTON_NAME then
    return -- some other mod's button
  end
  local frame = event.element.parent
  if frame and frame.name == FRAME_NAME then
    update_max_rate(frame)
  end
end)

-- The player pressed Esc or E while our window was open.
script.on_event(defines.events.on_gui_closed, function(event)
  local element = event.element
  if element and element.valid and element.name == FRAME_NAME then
    element.destroy()
  end
end)
