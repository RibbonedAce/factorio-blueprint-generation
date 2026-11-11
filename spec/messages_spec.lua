-- spec/messages_spec.lua
-- The words of the mod. Most of what matters here is that the keys the messages use are
-- the keys of the locale file and that each message gives the text as many values as it
-- has places for them (a typo shows up in the game as "Unknown key", and a missing value
-- as an empty gap); the rest checks the few things this file works out itself.
---@diagnostic disable: undefined-field  -- luassert's `assert` has fields (`assert.are`, `assert.is_nil`, ...) the editor cannot see
---@diagnostic disable: global-in-non-module  -- `_G.prototypes = ...` is how a spec fakes the game's global (see generator_spec.lua)

local builders = require("spec.support.builders")
local messages = require("scripts.messages")

local PREFIX = "blueprint-generation."
local LOCALE_FILE = "locale/en/blueprint-generation.cfg"

-- The text of the locale file by key (without the section name), read as the game reads it.
---@return table<string, string>
local function locale_texts()
  local texts = {}
  for line in io.lines(LOCALE_FILE) do
    local key, text = line:match("^([%w%-]+)=(.*)$")
    if key then
      texts[key] = text
    end
  end
  return texts
end

-- Every message of the mod, once for each key it can use.
---@return table<string, LocalisedString>
local function every_message()
  return {
    window_title = messages.window_title(),
    item_caption = messages.item_caption(),
    rate_caption = messages.rate_caption(),
    close_caption = messages.close_caption(),
    generate_caption = messages.generate_caption(),
    max_rate_no_item = messages.max_rate_no_item(),
    max_rate = messages.max_rate(450),
    no_item = messages.no_item(),
    bad_rate = messages.bad_rate(),
    no_cursor = messages.no_cursor(),
    cursor_full = messages.cursor_full(),
    unsupported_item = messages.unsupported_item(),
    unsupported_recipe = messages.unsupported_recipe(),
    missing_prototype = messages.missing_prototype(),
    unsupported_machine = messages.unsupported_machine(),
    unsupported_energy = messages.unsupported_energy(),
    chain_fuel = messages.chain_fuel("iron-plate"),
    fuel_needs_inputs = messages.fuel_needs_inputs("steel-plate"),
    fuel_mismatch = messages.fuel_mismatch({"entity-name.stone-furnace"}),
    locked = messages.locked("iron-plate"),
    rate_too_high = messages.rate_too_high(450),
    no_recipe = messages.chain_problem("no-recipe", "iron-plate"),
    ambiguous = messages.chain_problem("ambiguous", "iron-plate"),
    too_complex = messages.chain_problem("several-crafted", "iron-plate"),
    ready = messages.ready(10, "iron-plate", {{name = "iron-ore", amount = 10}, {name = "coal", amount = 1}}),
    ready_with_belts = messages.ready(10, "iron-plate", {{name = "iron-ore", amount = 10}, {name = "coal", amount = 1}}, {"coal", "iron-ore"}),
  }
end

-- Every message of the mod inside a LocalisedString: {key, values...}, with the messages
-- of other keys nested among the values.
---@param localised any
---@param found table[]  receives each {key, value count}
local function collect_keys(localised, found)
  if type(localised) ~= "table" then
    return
  end
  local key = localised[1]
  if type(key) == "string" and key:sub(1, #PREFIX) == PREFIX then
    found[#found + 1] = {key = key:sub(#PREFIX + 1), values = #localised - 1}
  end
  for index = 2, #localised do
    collect_keys(localised[index], found)
  end
end

describe("messages", function()
  before_each(function()
    _G.prototypes = builders.fake_prototypes{items = {"iron-plate", "iron-ore", "coal"}}
  end)

  describe("the locale file", function()
    it("has every key the messages use, with a place in the text for each value they give", function()
      local texts = locale_texts()
      local found = {}
      for _, message in pairs(every_message()) do
        collect_keys(message, found)
      end

      for _, use in ipairs(found) do
        local text = texts[use.key]
        assert.is_not_nil(text, "no text for the key " .. use.key)
        local places = 0
        for place in text:gmatch("__(%d+)__") do
          places = math.max(places, tonumber(place))
        end
        assert.are.equal(places, use.values, "values given to " .. use.key)
      end
    end)

    it("has no key that the messages do not use, besides the name of the shortcut", function()
      local found = {}
      for _, message in pairs(every_message()) do
        collect_keys(message, found)
      end
      collect_keys(messages.plan_problem("rate-too-high", 450), found)
      collect_keys(messages.plan_problem("anything else"), found)
      local used = {["shortcut-name"] = true} -- data.lua uses this one
      for _, use in ipairs(found) do
        used[use.key] = true
      end

      for key in pairs(locale_texts()) do
        assert.is_true(used[key] == true, "nothing uses the key " .. key)
      end
    end)
  end)

  describe("number", function()
    it("keeps up to two decimals and drops the zeros that follow", function()
      assert.are.equal("56.25", messages.number(56.25))
      assert.are.equal("60", messages.number(60))
      assert.are.equal("4.05", messages.number(4.05))
      assert.are.equal("4.5", messages.number(4.5))
      assert.are.equal("14.52", messages.number(14.5152))
    end)

    it("does not shorten a whole number that ends in zeros", function()
      assert.are.equal("100", messages.number(100))
      assert.are.equal("1000", messages.number(1000))
    end)
  end)

  describe("item", function()
    it("gives the item's localised name", function()
      assert.are.same({"item-name.iron-plate"}, messages.item("iron-plate"))
    end)

    it("gives the plain name of an item the game does not have", function()
      assert.are.equal("mystery-item", messages.item("mystery-item"))
    end)
  end)

  describe("why the recipe tree could not be made", function()
    it("names the item when nothing makes it", function()
      assert.are.same({PREFIX .. "error-no-recipe", {"item-name.iron-plate"}}, messages.chain_problem("no-recipe", "iron-plate"))
    end)

    it("names the item when several recipes make it", function()
      assert.are.same({PREFIX .. "error-ambiguous-recipe", {"item-name.iron-plate"}}, messages.chain_problem("ambiguous", "iron-plate"))
    end)

    it("names the item for each way a step can be too complex", function()
      for _, reason in ipairs({"several-crafted", "extra-ingredient", "fork-in-chain"}) do
        assert.are.same({PREFIX .. "error-chain-too-complex", {"item-name.iron-plate"}}, messages.chain_problem(reason, "iron-plate"))
      end
    end)

    it("says the recipe is not what the generator expects for any other reason", function()
      for _, reason in ipairs({"unsupported", "cycle"}) do
        assert.are.same({PREFIX .. "error-unsupported-recipe"}, messages.chain_problem(reason, "iron-plate"))
      end
    end)
  end)

  describe("why the planner said no", function()
    it("names the most that can be made when the rate is too high", function()
      assert.are.same({PREFIX .. "error-rate-too-high", "112.5"}, messages.plan_problem("rate-too-high", 112.5))
    end)

    it("says the recipe is not what the generator expects for any other reason", function()
      assert.are.same({PREFIX .. "error-unsupported-recipe"}, messages.plan_problem("unsupported-recipe"))
    end)
  end)

  describe("a blueprint that is ready", function()
    it("names the product and its rate, and each raw item with its rate, a comma between them", function()
      local message = messages.ready(56.25, "iron-plate", {{name = "iron-ore", amount = 56.25}, {name = "coal", amount = 4.05}})

      assert.are.same({
        PREFIX .. "generated",
        "56.25",
        {"item-name.iron-plate"},
        {"",
          {PREFIX .. "raw-amount", "56.25", {"item-name.iron-ore"}},
          ", ",
          {PREFIX .. "raw-amount", "4.05", {"item-name.coal"}},
        },
      }, message)
    end)

    it("puts no comma before a single raw item", function()
      local message = messages.ready(10, "iron-plate", {{name = "iron-ore", amount = 10}})

      assert.are.same({"", {PREFIX .. "raw-amount", "10", {"item-name.iron-ore"}}}, message[4])
    end)

    it("lists no raw item when there is none", function()
      local message = messages.ready(10, "iron-plate", {})

      assert.are.same({""}, message[4])
    end)

    it("names the items of the belts that come in, from the top down, after the raw items", function()
      local message = messages.ready(56.25, "iron-plate", {{name = "iron-ore", amount = 56.25}}, {"coal", "iron-ore", "iron-ore"})

      assert.are.same({
        PREFIX .. "generated-with-belts",
        "56.25",
        {"item-name.iron-plate"},
        {"", {PREFIX .. "raw-amount", "56.25", {"item-name.iron-ore"}}},
        {"", {"item-name.coal"}, ", ", {"item-name.iron-ore"}, ", ", {"item-name.iron-ore"}},
      }, message)
    end)

    it("words the message the original way when it is given no belts", function()
      local message = messages.ready(10, "iron-plate", {{name = "iron-ore", amount = 10}})

      assert.are.equal(PREFIX .. "generated", message[1])
    end)
  end)

  describe("the description of a blueprint", function()
    it("gives the rate and the machines of every step, in order", function()
      local description = messages.description("iron-gear-wheel", 100.8, {
        {machines = 11, machine = "stone-furnace"},
        {machines = 2, machine = "assembling-machine-1"},
      })

      assert.are.equal("iron-gear-wheel: 100.8 per minute from 11 x stone-furnace, 2 x assembling-machine-1", description)
    end)

    it("rounds the rate to two decimals", function()
      local description = messages.description("iron-plate", 56.256, {{machines = 3, machine = "stone-furnace"}})

      assert.are.equal("iron-plate: 56.26 per minute from 3 x stone-furnace", description)
    end)
  end)

  describe("the line under the rate field", function()
    it("gives the most one blueprint can make", function()
      assert.are.same({PREFIX .. "max-rate", "450"}, messages.max_rate(450))
    end)
  end)
end)
