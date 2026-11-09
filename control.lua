-- control.lua
-- Runs every time a save is created or loaded. At the top level of this file we
-- may ONLY register things (event handlers); the game world is not available
-- yet. All real work happens inside the handler functions, which the game calls
-- later. They live in scripts/gui.lua (the window), which uses scripts/generator.lua
-- (the blueprint) and scripts/messages.lua (the words).

-- `require` loads another file of this mod (scripts/gui.lua, written with a
-- dot instead of a slash) and gives back whatever that file `return`s. It may
-- only be called here at the top of the file, never inside a handler.
local gui = require("scripts.gui")

-- The shortcut-bar button was clicked.
script.on_event(defines.events.on_lua_shortcut, gui.on_shortcut)

-- Any GUI button anywhere was clicked.
script.on_event(defines.events.on_gui_click, gui.on_click)

-- The player picked another item, or cleared it.
script.on_event(defines.events.on_gui_elem_changed, gui.on_elem_changed)

-- The player pressed Esc or E while our window was open.
script.on_event(defines.events.on_gui_closed, gui.on_closed)
