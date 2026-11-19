-- scripts/messages.lua
-- Everything the player reads that this mod words itself: the refusals, the line under
-- the rate field, the message after a blueprint is made, the captions of the window and
-- the text in the blueprint's description. The modules that decide things (generator.lua,
-- gui.lua) pass in the facts, and this file says how they are told.
--
-- Most functions return a LocalisedString: a list whose first entry is
-- "blueprint-generation.<key>", a key of locale/en/blueprint-generation.cfg, followed by
-- the values for __1__, __2__ ... in that text. The wording itself lives in the locale
-- file; this file picks the key and the values. Items and machines are named by the
-- game's own localised names, so call these only from event handlers: `prototypes` does
-- not exist while control.lua is first loading.

local messages = {}

-- A LocalisedString for a key of the [blueprint-generation] section of the locale file.
---@param key string
---@param ... LocalisedString|number|string  values for __1__, __2__ ... in the text
---@return LocalisedString
local function text(key, ...)
  return {"blueprint-generation." .. key, ...} --[[@as LocalisedString]]
end

-- Turn a number into short text for messages: 56.25 -> "56.25", 60 -> "60".
-- (`string.format` rounds to 2 decimals; the gsub then trims trailing zeros.
-- The extra parentheses keep only gsub's first result, the text.)
---@param value number
---@return string
function messages.number(value)
  return (string.format("%.2f", value):gsub("%.?0+$", ""))
end

-- The localised name of an item, or of a fluid (water is a raw "item" of a recipe that takes it). One the game does not have
-- (another mod could have removed one the config names) is shown by its plain name.
---@param item_name string
---@return LocalisedString
function messages.item(item_name)
  local prototype = prototypes.item[item_name] or prototypes.fluid[item_name]
  return prototype and prototype.localised_name or item_name
end

-- The window ---------------------------------------------------------------

---@return LocalisedString
function messages.window_title()
  return text("window-title")
end

---@return LocalisedString
function messages.item_label()
  return text("item-label")
end

---@return LocalisedString
function messages.rate_label()
  return text("rate-label")
end

---@return LocalisedString
function messages.close()
  return text("close")
end

---@return LocalisedString
function messages.generate()
  return text("generate")
end

-- The line under the rate field when no item is picked.
---@return LocalisedString
function messages.max_rate_no_item()
  return text("max-rate-no-item")
end

-- The line under the rate field: the most one blueprint can make a minute.
---@param max_rate number
---@return LocalisedString
function messages.max_rate(max_rate)
  return text("max-rate", messages.number(max_rate))
end

-- What the player did wrong in the window --------------------------------------

---@return LocalisedString
function messages.no_item()
  return text("error-no-item")
end

---@return LocalisedString
function messages.bad_rate()
  return text("error-bad-rate")
end

---@return LocalisedString
function messages.no_cursor()
  return text("error-no-cursor")
end

---@return LocalisedString
function messages.cursor_full()
  return text("error-cursor-full")
end

-- Why a blueprint cannot be made --------------------------------------------------

---@return LocalisedString
function messages.unsupported_item()
  return text("error-unsupported-item")
end

---@return LocalisedString
function messages.unsupported_recipe()
  return text("error-unsupported-recipe")
end

-- Something the blueprint needs (a recipe or a building) is not in the game.
---@return LocalisedString
function messages.missing_prototype()
  return text("error-missing-prototype")
end

---@return LocalisedString
function messages.unsupported_machine()
  return text("error-unsupported-machine")
end

---@return LocalisedString
function messages.unsupported_energy()
  return text("error-unsupported-energy")
end

-- A step after the first is made in a machine that burns fuel.
---@param item_name string  the item the step makes
---@return LocalisedString
function messages.chain_fuel(item_name)
  return text("error-chain-fuel", messages.item(item_name))
end

-- The fuel the config sets for a machine does not suit it.
---@param machine_name LocalisedString  the localised name of the machine
---@return LocalisedString
function messages.fuel_mismatch(machine_name)
  return text("error-fuel-mismatch", machine_name)
end

-- The player has not unlocked the recipe of the item.
---@param item_name string
---@return LocalisedString
function messages.locked(item_name)
  return text("error-locked", messages.item(item_name))
end

-- Why a step in the middle of a chain that burns fuel (steel plate) cannot be made: only the design that brings in one
-- belt of each material can bring it the fuel.
---@param item_name string  the item the step makes
---@return LocalisedString
function messages.fuel_needs_inputs(item_name)
  return text("error-fuel-needs-inputs", messages.item(item_name))
end

-- Why a step with more ingredients than two belts carry cannot be made: its machines take them from three woven belts, which
-- need the splitters and underground belts of the blueprint that brings in one belt of each material, and a pole that reaches
-- the inserters beside three belts (the medium electric pole).
---@param item_name string  the item the step makes
---@return LocalisedString
function messages.belts_need_weave(item_name)
  return text("error-belts-need-weave", messages.item(item_name))
end

-- Why a step that takes a fluid cannot be made where it stands: the pipes come to a column that takes two or more ingredients
-- from other steps or belts, which has room for them beside its belt.
---@param item_name string  the item the step makes
---@return LocalisedString
function messages.fluid_single_input(item_name)
  return text("error-fluid-single-input", messages.item(item_name))
end

-- Why a step that takes a fluid cannot be made with the machine it has: its recipe takes more than one fluid or more than four
-- items, or the machine is not a 3 x 3 machine with a fluid input.
---@param item_name string  the item the step makes
---@return LocalisedString
function messages.fluid_unsupported(item_name)
  return text("error-fluid-unsupported", messages.item(item_name))
end

-- Why a step that takes a fluid and more than two items cannot be made: its machines take the items from two woven belts,
-- which need the splitters and underground belts of the blueprint that brings in one belt of each material.
---@param item_name string  the item the step makes
---@return LocalisedString
function messages.fluid_needs_weave(item_name)
  return text("error-fluid-needs-weave", messages.item(item_name))
end

---@param max_rate number  the most one blueprint can make a minute
---@return LocalisedString
function messages.rate_too_high(max_rate)
  return text("error-rate-too-high", messages.number(max_rate))
end

-- Why the recipe tree could not be made.
---@param reason bpgen.ChainReason
---@param item_name string  the item the reason is about
---@return LocalisedString
function messages.chain_problem(reason, item_name)
  if reason == "no-recipe" then
    return text("error-no-recipe", messages.item(item_name))
  end
  if reason == "ambiguous" then
    return text("error-ambiguous-recipe", messages.item(item_name))
  end
  if reason == "several-crafted" or reason == "extra-ingredient" or reason == "fork-in-chain" then
    return text("error-chain-too-complex", messages.item(item_name))
  end
  return messages.unsupported_recipe()
end

-- Why the planner said no.
---@param reason bpgen.PlanReason
---@param max_rate number|nil  given with "rate-too-high"
---@return LocalisedString
function messages.plan_problem(reason, max_rate)
  if reason == "rate-too-high" then
    ---@cast max_rate number -- the planner always gives it with this reason
    return messages.rate_too_high(max_rate)
  end
  return messages.unsupported_recipe()
end

-- A blueprint that is ready ---------------------------------------------------------

-- The entries one after another with a comma between them, as one LocalisedString.
---@param entries LocalisedString[]
---@return LocalisedString
local function comma_list(entries)
  ---@type LocalisedString
  local list = {""}
  for index, entry in ipairs(entries) do
    if index > 1 then
      list[#list + 1] = ", "
    end
    list[#list + 1] = entry
  end
  return list
end

-- The message after a blueprint is made: how much of the product it makes a minute and
-- how much of each raw item it uses a minute. For the design that brings in one belt of each
-- material it also names the items of those belts, from the top of the blueprint down, so the
-- player knows which belt goes to which row.
---@param made number  what the machines really make a minute of `product`
---@param product string
---@param raws bpgen.RawAmount[]  in the order they are listed
---@param belts? string[]  items of the belts that come in, from the top down; nil for the original design
---@return LocalisedString
function messages.ready(made, product, raws, belts)
  local amounts = {}
  for index, raw in ipairs(raws) do
    amounts[index] = text("raw-amount", messages.number(raw.amount), messages.item(raw.name))
  end
  if not belts then
    return text("generated", messages.number(made), messages.item(product), comma_list(amounts))
  end
  local items = {}
  for index, name in ipairs(belts) do
    items[index] = messages.item(name)
  end
  return text("generated-with-belts", messages.number(made), messages.item(product), comma_list(amounts), comma_list(items))
end

-- The text for the blueprint's description field: the machines, step by step. A plain
-- string, not a LocalisedString: a blueprint's description is stored as written.
---@param item_name string
---@param made number  what the machines really make a minute
---@param stages bpgen.StageSummary[]  from the first stage to the last
---@return string
function messages.description(item_name, made, stages)
  local machines = {}
  for _, stage in ipairs(stages) do
    machines[#machines + 1] = string.format("%d x %s", stage.machines, stage.machine)
  end
  return string.format("%s: %s per minute from %s", item_name, messages.number(made), table.concat(machines, ", "))
end

return messages
