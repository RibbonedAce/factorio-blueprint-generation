-- scripts/gui.lua
-- The window the player uses: building it, reading what was entered, and putting the
-- finished blueprint on the cursor. control.lua registers the events and hands them to
-- the `on_*` functions at the bottom; what the window says comes from messages.lua, and
-- what a blueprint is from generator.lua. Everything here runs in event handlers, never
-- while control.lua is first loading.

local config = require("scripts.config")
local generator = require("scripts.generator")
local messages = require("scripts.messages")

local gui = {}

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

-- The name of what the player picked, an item or a fluid, or nil when nothing is picked. The picker is a "signal" picker, the
-- game's picker for items and fluids both, so what it holds is a SignalID: a table with the name and a type (nil for an item).
---@param frame LuaGuiElement  our window
---@return string|nil
local function picked_name(frame)
  local signal = frame[ITEM_BUTTON_NAME].elem_value --[[@as SignalID|nil]]
  return signal and signal.name
end

-- Show, under the rate field, the most one blueprint of the picked item or fluid can make
-- per minute (or why that cannot be made). The text is read from the game's
-- data each time, so it follows the belt, inserters and recipe in the current game.
---@param frame LuaGuiElement  our window
---@param force LuaForce  the force of the player who has it open
local function update_max_rate(frame, force)
  local item_name = picked_name(frame) -- nil if nothing picked
  local label = frame[MAX_RATE_LABEL_NAME]
  if item_name then
    label.caption = generator.max_rate_message(item_name, force)
  else
    label.caption = messages.max_rate_no_item()
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
    caption = messages.window_title(),
    direction = "vertical",
  }
  frame.auto_center = true

  -- One picker for items and fluids: a "signal" picker. The game cannot filter it ("signal" does not support `elem_filters`), so
  -- it offers everything in the game, and what cannot be made (not supported, or not unlocked by the force) is answered with the
  -- message under the rate field.
  frame.add{type = "label", caption = messages.item_label()}
  local item_button = frame.add{type = "choose-elem-button", name = ITEM_BUTTON_NAME, elem_type = "signal"}
  -- The player can still change or clear it. The default only shows when it is on offer.
  for _, name in ipairs(generator.unlocked_products(player.force)) do
    if name == config.default_product then
      item_button.elem_value = {type = "item", name = name}
    end
  end

  frame.add{type = "label", caption = messages.rate_label()}
  frame.add{type = "label", name = MAX_RATE_LABEL_NAME}
  frame.add{
    type = "textfield",
    name = RATE_FIELD_NAME,
    text = "60",
    numeric = true,
    allow_decimal = true,
  }

  update_max_rate(frame, player.force)

  local buttons = frame.add{type = "flow", direction = "horizontal"}
  buttons.add{type = "button", name = CLOSE_BUTTON_NAME, caption = messages.close()}
  buttons.add{type = "button", name = GENERATE_BUTTON_NAME, caption = messages.generate()}

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

  local item_name = picked_name(frame)                -- nil if nothing picked
  local rate = tonumber(frame[RATE_FIELD_NAME].text) -- nil if the box is empty

  if not item_name then
    player.print(messages.no_item())
    return
  end
  if not rate or rate <= 0 then
    player.print(messages.bad_rate())
    return
  end

  -- Generate first, so a failure leaves the player's cursor untouched.
  local result, error_message = generator.generate(item_name, rate, player.force)
  if not result then
    player.print(error_message)
    return
  end

  local cursor = player.cursor_stack
  if not cursor then
    player.print(messages.no_cursor())
    return
  end
  if not player.clear_cursor() then
    player.print(messages.cursor_full())
    return
  end
  if not cursor.set_stack("blueprint") then
    player.print(messages.no_cursor())
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
---@param event EventData.on_lua_shortcut
function gui.on_shortcut(event)
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
end

-- Any GUI button anywhere was clicked. Only react to our two buttons.
---@param event EventData.on_gui_click
function gui.on_click(event)
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
end

-- The player picked another item or fluid, or cleared it: show its maximum rate.
---@param event EventData.on_gui_elem_changed
function gui.on_elem_changed(event)
  local element = event.element
  if element.name ~= ITEM_BUTTON_NAME then
    return -- some other mod's button
  end
  local frame = element.parent
  local player = game.get_player(event.player_index)
  if frame and frame.name == FRAME_NAME and player then
    update_max_rate(frame, player.force)
  end
end

-- The player pressed Esc or E while our window was open.
---@param event EventData.on_gui_closed
function gui.on_closed(event)
  local element = event.element
  if element and element.valid and element.name == FRAME_NAME then
    element.destroy()
  end
end

return gui
