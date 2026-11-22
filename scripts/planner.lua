-- scripts/planner.lua
-- Pure maths: how many machines does a product rate need?
-- It never touches the game (no `game`, no `prototypes`), so it can be tested
-- outside Factorio. The caller passes in plain tables with the numbers.

local constants = require("scripts.constants")

local planner = {}

-- Decimal numbers like 3.2 cannot be stored exactly, so 18.75 / 18.749999999999996
-- can come out as 1.0000000000000002 and round up to a whole extra machine.
-- Subtracting a tiny amount before rounding up avoids that.
local EPSILON = constants.EPSILON

-- An inserter drops items on the FAR lane of a belt that runs across its line (on a
-- curve, the inside lane; on a belt in line with it, the lane on the side to the right of
-- the way it faces), so the output inserters of a machine fill only one
-- lane of a plain output belt. The layout winds the belt when a machine has
-- exactly this many output inserters, so that each fills a different lane (see
-- layout.lua); the product then travels on both lanes.
local WINDING_OUTPUT_INSERTERS = constants.WINDING_OUTPUT_INSERTERS
local WINDING_MACHINE_SIZE = constants.WINDING_MACHINE_SIZE

-- The input belt of a stage has two lanes, so a stage fed raw items takes at most this
-- many items from it: its ingredients and its fuel. A stage fed by other stages has up to
-- three belts, woven (see `bpgen.Belts` and scripts/weave.lua), so it takes at most three
-- times as many ingredients, one on each lane.
local LANES_PER_BELT = constants.LANES_PER_BELT
local MOST_BELTS = 3

-- The names of the input belts of a stage, in order.
local BELT_LETTERS = {"a", "b", "c"}

-- Add up how many of `item_name` one craft of the recipe makes.
---@param recipe bpgen.Recipe
---@param item_name string
---@return number
function planner.amount_made(recipe, item_name)
  ---@type number
  local total = 0
  for _, product in ipairs(recipe.products) do
    if product.name == item_name then
      total = total + product.amount
    end
  end
  return total
end

-- How many items ONE LANE of a belt carries per minute, from the belt's speed
-- (the `belt_speed` of the belt entity prototype). The prototype docs define the
-- speed as tiles travelled per tick relative to a full belt, and a full lane holds
-- 4 items per tile, so a lane moves belt_speed * 4 items/tick * 60 ticks/second.
-- (The standard belt's speed, 0.03125, gives 7.5 items/s, which is 450 per minute.)
local ITEMS_PER_LANE_PER_TILE = 4
local TICKS_PER_SECOND = 60
local SECONDS_PER_MINUTE = 60

---@param belt_speed number  the belt entity prototype's `belt_speed`
---@return number
function planner.lane_items_per_minute(belt_speed)
  return belt_speed * ITEMS_PER_LANE_PER_TILE * TICKS_PER_SECOND * SECONDS_PER_MINUTE
end

-- How many ticks a full lane takes to carry one more item past a point: its items are a quarter of a tile apart and the belt
-- carries them `belt_speed` tiles a tick. (The basic belt's 0.03125 gives 8 ticks, which is the 7.5 items a second of
-- `lane_items_per_minute`.)
---@param belt_speed number  the belt entity prototype's `belt_speed`
---@return number
function planner.item_interval_ticks(belt_speed)
  return 1 / (ITEMS_PER_LANE_PER_TILE * belt_speed)
end

-- How many items ONE INSERTER moves per minute, from its rotation speed (the inserter prototype's
-- `get_inserter_rotation_speed()`, in turns per tick), the items its hand holds in a swing (`stack_size`: one, and more once the
-- inserter capacity bonus is researched) and the speed of the belts it takes from and drops onto:
--   items a minute = stack_size * 60 ticks * 60 seconds / (time to fully rotate + (stack_size - 1) * wait), the times in ticks.
-- One swing, which is one full turn there and back, takes 1 / rotation_speed ticks and moves a hand of items. (With a hand of one
-- the basic inserter's 0.014 gives 50.4 items, which matches its known 0.83 swings a second.) A hand of more than one item holds
-- still at the belt for each item after the first: on the way in it waits for the next item to come along the belt to it, and on
-- the way out for the item it has just dropped to be carried clear of the place of the next. Each wait is `item_interval_ticks`
-- long, so a faster belt costs an inserter less. (A lane that carries less than a full lane makes an inserter wait longer, and the
-- items of other inserters on the belt can hold it up: not counted.)
---@param rotation_speed number
---@param stack_size integer  how many items one swing moves: at least one
---@param belt_speed number  of the belts it works with
---@return number
function planner.inserter_items_per_minute(rotation_speed, stack_size, belt_speed)
  assert(stack_size >= 1, "planner: an inserter moves at least one item in a swing")
  local rotation_ticks = 1 / rotation_speed
  local waiting_ticks = (stack_size - 1) * planner.item_interval_ticks(belt_speed)
  return stack_size * TICKS_PER_SECOND * SECONDS_PER_MINUTE / (rotation_ticks + waiting_ticks)
end

-- The input belt of a stage that carries `item`, by letter (see `bpgen.Belts`): the belt that the product of the step that
-- makes it rides. Every ingredient of the stage is on one.
---@param belts bpgen.Belts
---@param item string  an ingredient of the stage
---@return "a"|"b"|"c"
function planner.belt_of(belts, item)
  for _, letter in ipairs(BELT_LETTERS) do
    for _, name in ipairs(belts[letter] or {}) do
      if name == item then
        return letter
      end
    end
  end
  error("planner: " .. item .. " is on none of the input belts of the stage")
end

-- Whether this planner can handle the recipe: it must make the product (and
-- only the product, or the machine's output would clog with the rest), and take
-- time to craft.
---@param recipe bpgen.Recipe
---@param product_name string
---@return boolean
local function is_supported(recipe, product_name)
  return planner.amount_made(recipe, product_name) > 0 and #recipe.products == 1 and recipe.energy > 0
end

-- The two lanes of the input belt, one item on each, or nil when the items do not
-- fit. The items are the ingredients plus the fuel, if the machine burns one:
--   one item (an ingredient, no fuel)   it fills both lanes
--   two items (ingredient and fuel, or two ingredients)   one lane each
---@param ingredients bpgen.RecipeItem[]
---@param fuel string|nil
---@return string[]|nil lanes  the item on the first lane, then on the second
local function assign_lanes(ingredients, fuel)
  local items = {}
  for _, ingredient in ipairs(ingredients) do
    items[#items + 1] = ingredient.name
  end
  if fuel then
    items[#items + 1] = fuel
  end
  if #ingredients == 0 or #items > LANES_PER_BELT then
    return nil
  end
  return {items[1], items[2] or items[1]}
end

-- How many of the two input lanes carry this item.
---@param lanes string[]
---@param item_name string
---@return integer
local function lanes_carrying(lanes, item_name)
  local count = 0
  for _, lane_item in ipairs(lanes) do
    if lane_item == item_name then
      count = count + 1
    end
  end
  return count
end

-- How much of its full speed a machine can use on one side: 1 unless the flow
-- of that side (items a minute) is more than its inserters can move.
---@param flow number
---@param most_movable number
---@return number
local function side_fraction(flow, most_movable)
  if flow <= most_movable then
    return 1
  end
  return most_movable / flow
end

-- How many inserters it takes to move `items_per_machine` a minute when one moves
-- `inserter_items_per_minute`: at least one.
---@param items_per_machine number
---@param inserter_items_per_minute number
---@return integer
local function inserters_needed(items_per_machine, inserter_items_per_minute)
  return math.max(1, math.ceil(items_per_machine / inserter_items_per_minute - EPSILON))
end

-- The letters of the belts that carry something, belt a first.
---@param belts bpgen.Belts
---@return string[]
local function belts_in_use(belts)
  local used = {"a"}
  for _, letter in ipairs({"b", "c"}) do
    if belts[letter] and #belts[letter] > 0 then
      used[#used + 1] = letter
    end
  end
  return used
end

-- How many inserters a machine's input side has on each belt (a letter and the count): plain or fast ones, but for belt b
-- when the belts are not woven, whose inserters are long-handed.
---@class bpgen.InputInserters
---@field a integer
---@field b? integer
---@field c? integer
---@field fast? boolean  whether the plain inserters are fast ones; nil while the split is only being compared with others

-- What one machine eats of each ingredient and makes a minute at full speed.
---@param request bpgen.StageRequest
---@return bpgen.PlanInput[] inputs
---@return number output
local function full_speed(request)
  local recipe = request.recipe
  local crafts_per_minute = 60 * request.machine_speed / recipe.energy
  local inputs = {}
  for _, ingredient in ipairs(recipe.ingredients) do
    inputs[#inputs + 1] = {name = ingredient.name, per_minute = crafts_per_minute * ingredient.amount}
  end
  return inputs, crafts_per_minute * planner.amount_made(recipe, request.product)
end

-- How many items a minute the ingredients named in `names` add up to.
---@param inputs bpgen.PlanInput[]
---@param names string[]
---@return number
local function flow_of(inputs, names)
  local wanted = {}
  for _, name in ipairs(names) do
    wanted[name] = true
  end
  ---@type number
  local total = 0
  for _, input in ipairs(inputs) do
    if wanted[input.name] then
      total = total + input.per_minute
    end
  end
  return total
end

-- How many items a minute each belt in use brings, by letter, at full speed.
---@param inputs bpgen.PlanInput[]
---@param belts bpgen.Belts
---@return table<string, number>
local function flows_of(inputs, belts)
  local flows = {}
  for _, letter in ipairs(belts_in_use(belts)) do
    flows[letter] = flow_of(inputs, belts[letter])
  end
  return flows
end

-- What one inserter of the input side and of the output side moves, as far as the planner counts: a fast one when the game
-- has them researched (`limits.fast_items_per_minute`), else a plain one. A side that needs it uses fast ones; one that
-- needs less uses a plain one (see `side_inserters`).
---@param limits bpgen.InserterLimits
---@return number
local function side_rate(limits)
  return limits.fast_items_per_minute or limits.items_per_minute
end

-- The inserters a side of a machine needs for `flow` items a minute: one plain inserter when that moves it, else fast
-- ones, as many as it takes, when the game has them; else plain ones, as many as it takes.
---@param flow number
---@param limits bpgen.InserterLimits
---@return integer count
---@return boolean fast
local function side_inserters(flow, limits)
  if flow <= limits.items_per_minute + EPSILON or not limits.fast_items_per_minute then
    return inserters_needed(flow, limits.items_per_minute), false
  end
  return inserters_needed(flow, limits.fast_items_per_minute), true
end

-- What one long-handed inserter moves a minute: the figure the limits give, or a plain inserter's when they give none.
---@param limits bpgen.InserterLimits
---@return number
local function long_rate(limits)
  return limits.long_items_per_minute or limits.items_per_minute
end

-- Whether the inserters that take from belt `letter` are long-handed: those of belt b when the belts are not woven (the
-- limits give no slots for woven belts), which reach over belt a to the column one further out.
---@param letter string
---@param limits bpgen.InserterLimits
---@return boolean
local function is_long_handed(letter, limits)
  return letter == "b" and limits.max_woven_input == nil
end

-- What one inserter that takes from belt `letter` moves a minute: a long-handed one's figure for belt b when it is not
-- woven, else a fast inserter's when `fast` says so, a plain one's when it says not, and the best the game has when it says
-- nothing (a split being compared with others).
---@param letter string
---@param fast boolean|nil
---@param limits bpgen.InserterLimits
---@return number
local function inserter_rate(letter, fast, limits)
  if is_long_handed(letter, limits) then
    return long_rate(limits)
  end
  if fast == nil then
    return side_rate(limits)
  end
  return fast and limits.fast_items_per_minute or limits.items_per_minute
end

-- Whether a belt of plain inserters needs more than one of them moves while the game has fast ones to give. (A long-handed
-- inserter has no fast kind.)
---@param flows table<string, number>  items a minute, by belt letter
---@param limits bpgen.InserterLimits
---@return boolean
local function needs_fast(flows, limits)
  if not limits.fast_items_per_minute then
    return false
  end
  for letter, flow in pairs(flows) do
    if not is_long_handed(letter, limits) and flow > limits.items_per_minute + EPSILON then
      return true
    end
  end
  return false
end

-- The inserters the input side of a machine needs on each belt for `flows` (items a minute, by belt letter): at least one on
-- each. When one belt needs more than one plain inserter moves and the game has fast ones, every plain inserter of the side
-- is a fast one, as many as each belt needs; else plain ones. The long-handed inserters of belt b are as many as it needs of
-- them. (For one belt this is `side_inserters`.)
---@param flows table<string, number>
---@param limits bpgen.InserterLimits
---@return table<string, integer> counts  by belt letter
---@return boolean fast
local function needed_inserters(flows, limits)
  local fast = needs_fast(flows, limits)
  local counts = {}
  for letter, flow in pairs(flows) do
    counts[letter] = inserters_needed(flow, inserter_rate(letter, fast, limits))
  end
  return counts, fast
end

-- How much of its full speed a machine can use for what the inserters of its input
-- side can move: the belt that holds it back the most decides.
-- The plain inserters are fast ones when `counts.fast` says so, plain ones when it says not, and the best the game has
-- when it says nothing (a split being compared with others).
---@param flows table<string, number>  items a minute that each belt brings, at full speed, by belt letter
---@param counts bpgen.InputInserters
---@param limits bpgen.InserterLimits
---@return number
local function input_fraction(flows, counts, limits)
  local fraction = 1
  for letter, flow in pairs(flows) do
    fraction = math.min(fraction, side_fraction(flow, counts[letter] * inserter_rate(letter, counts.fast, limits)))
  end
  return fraction
end

-- The ways to share `total` slots between `parts` belts, at least one slot each, the first belt's share growing first.
---@param total integer
---@param parts integer
---@return integer[][]
local function compositions(total, parts)
  if parts == 1 then
    return {{total}}
  end
  local found = {}
  for first = 1, total - parts + 1 do
    for _, rest in ipairs(compositions(total - first, parts - 1)) do
      found[#found + 1] = {first, table.unpack(rest)}
    end
  end
  return found
end

-- The letters of the belts that `flows` has, belt a first.
---@param flows table<string, number>
---@return string[]
local function letters_in(flows)
  local letters = {}
  for _, letter in ipairs(BELT_LETTERS) do
    if flows[letter] then
      letters[#letters + 1] = letter
    end
  end
  return letters
end

-- The split of the `slots` of a machine between the belts `letters` (at least one slot each) that lets the machine run
-- fastest, the first one when several do.
---@param letters string[]
---@param flows table<string, number>  by belt letter
---@param slots integer
---@param limits bpgen.InserterLimits
---@return bpgen.InputInserters
local function best_allotment(letters, flows, slots, limits)
  local best, best_fraction
  for _, shares in ipairs(compositions(slots, #letters)) do
    local counts = {}
    for position, letter in ipairs(letters) do
      counts[letter] = shares[position]
    end
    local fraction = input_fraction(flows, counts, limits)
    if not best_fraction or fraction > best_fraction + EPSILON then
      best, best_fraction = counts, fraction
    end
  end
  return best
end

-- How many input slots a machine has for `belts` belts: the woven slots when the belts are woven, which serve two or three
-- belts. Without them belt b is reached by long-handed inserters, which share the slots of one belt with the plain ones of
-- belt a, and there is no third belt: none.
---@param belts integer  how many belts carry something
---@param limits bpgen.InserterLimits
---@return integer
local function slots_for(belts, limits)
  if limits.max_woven_input then
    return limits.max_woven_input
  end
  return belts == 2 and limits.max_input or 0
end

-- How the input slots of a machine are shared between the belts: all to belt a when it is the only one, otherwise the
-- best split (see `best_allotment`). Nil when the machine has too few slots for the belts.
---@param flows table<string, number>  by belt letter, the belts in use
---@param limits bpgen.InserterLimits
---@return bpgen.InputInserters|nil
local function allotted_counts(flows, limits)
  local letters = letters_in(flows)
  if #letters == 1 then
    return {a = limits.max_input}
  end
  local slots = slots_for(#letters, limits)
  if slots < #letters then
    return nil
  end
  return best_allotment(letters, flows, slots, limits)
end

-- The counts cut down to what a machine that is used for `share` of its time needs:
-- a machine that takes two inserters to run flat out takes one for 40%.
---@param counts bpgen.InputInserters
---@param flows table<string, number>  by belt letter
---@param limits bpgen.InserterLimits
---@param share number
---@return bpgen.InputInserters
local function trimmed_counts(counts, flows, limits, share)
  local scaled = {}
  for letter, flow in pairs(flows) do
    scaled[letter] = share * flow
  end
  local needed, fast = needed_inserters(scaled, limits)
  local trimmed = {fast = fast}
  for letter in pairs(flows) do
    trimmed[letter] = math.min(counts[letter], needed[letter])
  end
  return trimmed
end

---@class bpgen.MachineRates  what ONE machine does each minute, once its inserters are counted
---@field output number  items of the product it makes
---@field inputs bpgen.PlanInput[]  what it eats, per ingredient, in the recipe's order
---@field input_inserters integer  inserters on its input side that take from the column in front of them: all of them for one belt or for woven belts, those of belt a for a belt b that long-handed inserters reach
---@field input_fast boolean  whether those are fast inserters
---@field long_inserters integer  long-handed inserters on its input side, for belt b, when its belts are not woven (0 otherwise)
---@field belt_inserters? table<string, integer>  how many of the input inserters take from each belt (a letter and the count), when the machine takes from more than one woven belt (see scripts/weave.lua)
---@field output_inserters integer  on its output side
---@field output_fast boolean  whether those are fast inserters

-- The inserters of a machine that runs at `fraction` of its full speed: what each side needs for the flow it then has.
---@param flows table<string, number>  by belt letter
---@param output number  what it makes at full speed
---@param fraction number
---@param limits bpgen.InserterLimits
---@return {input: table<string, integer>, input_fast: boolean, output: integer, output_fast: boolean}
local function inserters_for(flows, output, fraction, limits)
  local scaled = {}
  for letter, flow in pairs(flows) do
    scaled[letter] = flow * fraction
  end
  local input, input_fast = needed_inserters(scaled, limits)
  local output_count, output_fast = side_inserters(output * fraction, limits)
  return {input = input, input_fast = input_fast, output = output_count, output_fast = output_fast}
end

-- The inserters of a machine when the caller sets no limits: one on each belt and one on the output, plain ones.
---@param flows table<string, number>  by belt letter
---@return {input: table<string, integer>, input_fast: boolean, output: integer, output_fast: boolean}
local function bare_counts(flows)
  local input = {}
  for letter in pairs(flows) do
    input[letter] = 1
  end
  return {input = input, input_fast = false, output = 1, output_fast = false}
end

-- The figures the inserters of a machine are counted against: those of the busiest machine of the stage when this one is
-- only partly used (`partial`), else its own at full use.
---@param partial {share: number, rates: bpgen.MachineRates}|nil
---@param belts bpgen.Belts
---@param flows table<string, number>  of the machine at full speed
---@param output number  what it makes at full speed
---@return {flows: table<string, number>, output: number, share: number}
local function reference_of(partial, belts, flows, output)
  if not partial then
    return {flows = flows, output = output, share = 1}
  end
  return {flows = flows_of(partial.rates.inputs, belts), output = partial.rates.output, share = partial.share}
end

-- How much of its full speed a machine runs at for the inserters it may have (`allotted` on its input side, at most
-- `limits.max_output` on its output side), the inserters being counted against `reference`.
---@param flows table<string, number>  of the machine at full speed
---@param output number  what it makes at full speed
---@param reference {flows: table<string, number>, output: number, share: number}
---@param allotted bpgen.InputInserters
---@param limits bpgen.InserterLimits
---@return number
local function served_fraction(flows, output, reference, allotted, limits)
  local movable = trimmed_counts(allotted, reference.flows, limits, reference.share)
  local needed, fast = side_inserters(reference.share * reference.output, limits)
  local rate = fast and limits.fast_items_per_minute or limits.items_per_minute
  return math.min(input_fraction(flows, movable, limits), side_fraction(output, math.min(limits.max_output, needed) * rate))
end

-- The sum of the inserters of all the belts.
---@param counts table<string, integer>  by belt letter
---@return integer
local function total_of(counts)
  local total = 0
  for _, inserters in pairs(counts) do
    total = total + inserters
  end
  return total
end

-- How many of the input inserters are long-handed: those of belt b when the belts are not woven. (With no limits every
-- inserter is a plain one, one on each belt.)
---@param counts table<string, integer>  by belt letter
---@param limits bpgen.InserterLimits|nil
---@return integer
local function long_count(counts, limits)
  if limits and counts.b and is_long_handed("b", limits) then
    return counts.b
  end
  return 0
end

-- What one machine does when it runs at `fraction` of its full speed, with the inserters in `counts`.
---@param inputs bpgen.PlanInput[]  what it eats at full speed
---@param output number  what it makes at full speed
---@param fraction number
---@param counts {input: table<string, integer>, input_fast: boolean, output: integer, output_fast: boolean}
---@param limits bpgen.InserterLimits|nil
---@return bpgen.MachineRates
local function machine_rates(inputs, output, fraction, counts, limits)
  for _, input in ipairs(inputs) do
    input.per_minute = input.per_minute * fraction
  end
  local long = long_count(counts.input, limits)
  return {
    output = output * fraction,
    inputs = inputs,
    input_inserters = total_of(counts.input) - long,
    input_fast = counts.input_fast,
    long_inserters = long,
    belt_inserters = counts.input.b and long == 0 and counts.input or nil,
    output_inserters = counts.output,
    output_fast = counts.output_fast,
  }
end

-- What ONE machine does each minute. When the inserters cannot keep up with it at
-- full speed, it simply waits for items, so every number shrinks by the same
-- fraction, and the inserters are counted for what it really moves. `share` is how
-- much of its full speed the busiest machine of the stage is used at. A machine that
-- is only partly used (`partial`: its share, and what it does at full use) gets only
-- the inserters that share needs. Returns nil when the machine has too few input slots
-- for its belts.
---@param request bpgen.StageRequest
---@param belts bpgen.Belts
---@param partial? {share: number, rates: bpgen.MachineRates}
---@return bpgen.MachineRates|nil
local function rates_per_machine(request, belts, partial)
  local inputs, output = full_speed(request)
  local limits = request.inserters
  local flows = flows_of(inputs, belts)
  local fraction, counts = 1, bare_counts(flows)
  if limits then
    local allotted = allotted_counts(flows, limits)
    if not allotted then
      return nil
    end
    fraction = served_fraction(flows, output, reference_of(partial, belts, flows, output), allotted, limits)
    counts = inserters_for(flows, output, fraction, limits)
  end
  return machine_rates(inputs, output, fraction, counts, limits)
end

-- How many whole machines it takes to do `machines_worth` of work: a fraction of a
-- machine still needs a whole one, and a stage always has at least one.
---@param machines_worth number
---@return integer
local function whole_machines(machines_worth)
  return math.max(1, math.ceil(machines_worth - EPSILON))
end

-- Whether the recipe takes one fluid and nothing else and makes the product (see `is_supported`): a row of machines makes a fluid
-- from it, or a plant of machines an item.
---@param recipe bpgen.Recipe
---@param product_name string
---@return boolean
function planner.is_fluid_recipe(recipe, product_name)
  return #recipe.ingredients == 0 and #recipe.fluids == 1 and is_supported(recipe, product_name)
end

-- Whether the recipe takes one fluid or two, or one fluid and one item, and nothing else and makes the product (see `is_supported`): a
-- plant of machines makes an item from it, from the fluid that machines of a row make and a second that comes in by a pipe, or an item
-- that comes in by a belt, if there is one.
---@param recipe bpgen.Recipe
---@param product_name string
---@return boolean
function planner.is_plant_recipe(recipe, product_name)
  local items, fluids = #recipe.ingredients, #recipe.fluids
  local fits = (items == 0 and (fluids == 1 or fluids == 2)) or (items == 1 and fluids == 1)
  return fits and is_supported(recipe, product_name)
end

-- How many crafts one machine of a row makes in a minute: a craft takes recipe.energy / machine_speed seconds.
---@param request bpgen.FluidRowRequest
---@return number
local function fluid_crafts_per_minute(request)
  return 60 * request.machine_speed / request.recipe.energy
end

-- How much of its fluid one machine of a row makes in a minute.
---@param request bpgen.FluidRowRequest
---@return number
local function fluid_output_per_machine(request)
  return fluid_crafts_per_minute(request) * planner.amount_made(request.recipe, request.product)
end

-- How many machines a row has at most: as many as stand in the length one run of pipes may have (a pipe carries all the fluid
-- the machines on it need, so there is no limit of its flow). A row always has one.
---@param request bpgen.FluidRowRequest
---@return integer
local function most_fluid_machines(request)
  return math.max(1, request.machines_that_fit)
end

-- The most a row of machines that make a fluid can make a minute: as much as the machines that fit in a run of pipes make. Nil and the
-- reason when the recipe is not one the planner handles.
---@param request bpgen.FluidRowRequest
---@return number|nil max_rate
---@return bpgen.PlanReason|nil reason
function planner.max_fluid_row_rate(request)
  if not planner.is_fluid_recipe(request.recipe, request.product) then
    return nil, "unsupported-recipe"
  end
  return most_fluid_machines(request) * fluid_output_per_machine(request), nil
end

-- How many machines a row needs for `request.rate_per_minute` units of the fluid a minute, and what they make in all (a whole
-- number of machines makes a little more than asked). Nil, the reason and the most a row can make when the rate is more
-- than the machines that fit make.
---@param request bpgen.FluidRowRequest
---@return bpgen.FluidRowPlan|nil plan
---@return bpgen.PlanReason|nil reason
---@return number|nil max_rate  given with "rate-too-high"
function planner.plan_fluid_row(request)
  local max_rate, reason = planner.max_fluid_row_rate(request)
  if not max_rate then
    return nil, reason
  end
  local per_machine = fluid_output_per_machine(request)
  local machines = whole_machines(request.rate_per_minute / per_machine)
  if machines > most_fluid_machines(request) then
    return nil, "rate-too-high", max_rate
  end
  return {machines = machines, output_per_minute = machines * per_machine, per_machine = per_machine}
end

-- What one machine of a plant makes a minute: what it makes at full speed, held down to what its output inserter moves and, when it
-- takes an item, to what its input inserter brings (`request.input_inserter_items_per_minute`, of that item).
---@param request bpgen.FluidPlantRequest
---@return number
local function plant_output_each(request)
  local made = planner.amount_made(request.recipe, request.product)
  local output = math.min(60 * request.machine_speed / request.recipe.energy * made, request.inserter_items_per_minute)
  local item = request.recipe.ingredients[1]
  if not item then
    return output
  end
  return math.min(output, assert(request.input_inserter_items_per_minute, "planner: no input inserter for the item of the plant") / item.amount * made)
end

-- How many crafts one machine of a plant makes in a minute, making `plant_output_each`.
---@param request bpgen.FluidPlantRequest
---@return number
local function plant_crafts_each(request)
  return plant_output_each(request) / planner.amount_made(request.recipe, request.product)
end

-- The fluid the machines of the row make that the recipe of the plant takes: the fluid ingredient named like their product. Nil when
-- the recipe takes none of that name.
---@param request bpgen.FluidPlantRequest
---@return bpgen.RecipeItem|nil
local function source_ingredient(request)
  local made = request.maker_recipe.products[1].name
  for _, fluid in ipairs(request.recipe.fluids) do
    if fluid.name == made then
      return fluid
    end
  end
  return nil
end

-- How much of the fluid the machines of the row make one machine of a plant takes in a minute.
---@param request bpgen.FluidPlantRequest
---@return number
local function plant_fluid_each(request)
  return plant_crafts_each(request) * assert(source_ingredient(request), "planner: the recipe takes no fluid that the machines of the row make").amount
end

-- What the planner is asked for the row of machines that make the fluid the plant takes.
---@param request bpgen.FluidPlantRequest
---@return bpgen.FluidRowRequest
local function fluid_source_request(request)
  return {
    product = request.maker_recipe.products[1].name, recipe = request.maker_recipe, machine_speed = request.maker_speed,
    rate_per_minute = 0, machines_that_fit = request.makers_that_fit,
  }
end

-- Whether the recipe of the plant and the recipe that makes its fluid are ones the planner handles.
---@param request bpgen.FluidPlantRequest
---@return boolean
local function fluid_plant_supported(request)
  return planner.is_plant_recipe(request.recipe, request.product)
    and planner.is_fluid_recipe(request.maker_recipe, request.maker_recipe.products[1].name)
    and source_ingredient(request) ~= nil
end

-- How many machines the plant has at most: as many as a lane of the output belt carries, as many as stand in the length one run of
-- pipes may have, as many as the fluid that the most machines that make it (and fit) make, and, when the plant takes an item, as many
-- as the belt that brings it in carries (`request.item_belt_items_per_minute`). At least one.
---@param request bpgen.FluidPlantRequest
---@return integer
local function most_plants(request)
  local source = fluid_source_request(request)
  local by_lane = request.lane_items_per_minute / plant_output_each(request)
  local by_fluid = most_fluid_machines(source) * fluid_output_per_machine(source) / plant_fluid_each(request)
  local item = request.recipe.ingredients[1]
  local by_item = item and request.item_belt_items_per_minute / (plant_crafts_each(request) * item.amount) or math.huge
  return math.max(1, math.floor(math.min(by_lane, by_fluid, by_item, request.plants_that_fit) + EPSILON))
end

-- The most a plant of machines that make an item from a fluid can make a minute. Nil and the reason when a recipe is not one the
-- planner handles.
---@param request bpgen.FluidPlantRequest
---@return number|nil max_rate
---@return bpgen.PlanReason|nil reason
function planner.max_fluid_plant_rate(request)
  if not fluid_plant_supported(request) then
    return nil, "unsupported-recipe"
  end
  return most_plants(request) * plant_output_each(request), nil
end

-- What `plants` machines take a minute of the fluids of the recipe that come in by a pipe (the ones the machines of the row do not make).
---@param request bpgen.FluidPlantRequest
---@param plants integer
---@return bpgen.RawAmount[]
local function supplied_amounts(request, plants)
  local supplied = {}
  for _, other in ipairs(request.recipe.fluids) do
    if other ~= source_ingredient(request) then
      supplied[#supplied + 1] = {name = other.name, amount = plants * plant_crafts_each(request) * other.amount}
    end
  end
  return supplied
end

-- What `plants` machines take a minute of the item of the recipe, which comes in by a belt: a list of one, or none.
---@param request bpgen.FluidPlantRequest
---@param plants integer
---@return bpgen.RawAmount[]
local function item_amounts(request, plants)
  local item = request.recipe.ingredients[1]
  return {item and {name = item.name, amount = plants * plant_crafts_each(request) * item.amount} or nil}
end

-- How many machines a plant needs for `request.rate_per_minute` of the item (a whole number makes a little more than asked), and
-- how many machines of the row that makes the fluid they take. Nil, the reason and the most a plant can make when the rate is more
-- than a lane carries or the fluid allows.
---@param request bpgen.FluidPlantRequest
---@return bpgen.FluidPlantPlan|nil plan
---@return bpgen.PlanReason|nil reason
---@return number|nil max_rate  given with "rate-too-high"
function planner.plan_fluid_plant(request)
  local max_rate, reason = planner.max_fluid_plant_rate(request)
  if not max_rate then
    return nil, reason
  end
  local each = plant_output_each(request)
  local plants = whole_machines(request.rate_per_minute / each)
  if plants > most_plants(request) then
    return nil, "rate-too-high", max_rate
  end
  local source = fluid_source_request(request)
  local fluid = plants * plant_fluid_each(request)
  local maker = request.maker_recipe
  return {
    plants = plants, makers = whole_machines(fluid / fluid_output_per_machine(source)), output_per_minute = plants * each,
    per_plant = each, fluid_per_minute = fluid,
    source_per_minute = fluid / planner.amount_made(maker, source.product) * maker.fluids[1].amount,
    supplied = supplied_amounts(request, plants), items = item_amounts(request, plants),
  }
end

-- How many ticks ONE INSERTER takes to bring the items of one craft, `amounts` of each of several items (the items of a belt that two
-- items share): it moves them in turn, each in swings of a hand of `stack_size` (the last swing of an item with what is left), each swing
-- taking what `planner.inserter_items_per_minute` says for a hand of its size: a turn there and back and a wait for each item after the
-- first.
---@param rotation_speed number
---@param stack_size integer
---@param belt_speed number
---@param amounts number[]
---@return number
function planner.inserter_ticks_for(rotation_speed, stack_size, belt_speed, amounts)
  local rotation_ticks, interval = 1 / rotation_speed, planner.item_interval_ticks(belt_speed)
  local ticks = 0
  for _, amount in ipairs(amounts) do
    local full = math.floor(amount / stack_size + EPSILON)
    local rest = amount - full * stack_size
    ticks = ticks + full * (rotation_ticks + (stack_size - 1) * interval)
    if rest > EPSILON then
      ticks = ticks + rotation_ticks + (rest - 1) * interval
    end
  end
  return ticks
end

-- Whether the recipe of plants that make a fluid from two items and a fluid is one the planner handles: two items, one fluid, one
-- product, which is the fluid.
---@param recipe bpgen.Recipe
---@param product_name string
---@return boolean
function planner.is_item_fluid_recipe(recipe, product_name)
  return #recipe.ingredients == 2 and #recipe.fluids == 1 and is_supported(recipe, product_name)
end

-- How many crafts one plant of `request` makes a minute: what its machine does at full speed, held down to what its one inserter brings
-- of the two items of a craft.
---@param request bpgen.ItemFluidPlantsRequest
---@return number
local function item_fluid_crafts_each(request)
  local machine = 60 * request.machine_speed / request.recipe.energy
  local amounts = {}
  for _, item in ipairs(request.recipe.ingredients) do
    amounts[#amounts + 1] = item.amount
  end
  local ticks = planner.inserter_ticks_for(request.inserter_rotation_speed, request.inserter_stack_size, request.belt_speed, amounts)
  return math.min(machine, TICKS_PER_SECOND * SECONDS_PER_MINUTE / ticks)
end

-- What `plants` plants take a minute of what their recipe takes, as a list of the amounts, from the item that comes first.
---@param request bpgen.ItemFluidPlantsRequest
---@param plants integer
---@return bpgen.RawAmount[] items
---@return bpgen.RawAmount[] fluids
local function item_fluid_amounts(request, plants)
  local crafts = plants * item_fluid_crafts_each(request)
  local items, fluids = {}, {}
  for _, item in ipairs(request.recipe.ingredients) do
    items[#items + 1] = {name = item.name, amount = crafts * item.amount}
  end
  for _, fluid in ipairs(request.recipe.fluids) do
    fluids[#fluids + 1] = {name = fluid.name, amount = crafts * fluid.amount}
  end
  return items, fluids
end

-- The most a plant of machines that make a fluid from two items and a fluid can make a minute: as many machines as stand in the length one
-- run of pipes may have, each making what its inserter brings the items of. Nil and the reason when the recipe is not one the planner
-- handles.
---@param request bpgen.ItemFluidPlantsRequest
---@return number|nil max_rate
---@return bpgen.PlanReason|nil reason
function planner.max_item_fluid_plants_rate(request)
  if not planner.is_item_fluid_recipe(request.recipe, request.product) then
    return nil, "unsupported-recipe"
  end
  return math.max(1, request.plants_that_fit) * item_fluid_crafts_each(request) * planner.amount_made(request.recipe, request.product), nil
end

-- How many machines make `request.rate_per_minute` of the fluid (a whole number makes a little more than asked), what each makes, and what
-- they take of the two items and the fluid. Nil, the reason and the most they can make when the rate is more than stand in the length of a
-- run of pipes.
---@param request bpgen.ItemFluidPlantsRequest
---@return bpgen.ItemFluidPlantsPlan|nil plan
---@return bpgen.PlanReason|nil reason
---@return number|nil max_rate  given with "rate-too-high"
function planner.plan_item_fluid_plants(request)
  local max_rate, reason = planner.max_item_fluid_plants_rate(request)
  if not max_rate then
    return nil, reason
  end
  local crafts = item_fluid_crafts_each(request)
  local each = crafts * planner.amount_made(request.recipe, request.product)
  local plants = whole_machines(request.rate_per_minute / each)
  if plants > math.max(1, request.plants_that_fit) then
    return nil, "rate-too-high", max_rate
  end
  local items, fluids = item_fluid_amounts(request, plants)
  return {plants = plants, crafts_each = crafts, per_plant = each, output_per_minute = plants * each, items = items, fluids = fluids}
end

-- Whether the sides of the machines leave room for a winding belt: they are 3x3 and neither side is full (the plain and the
-- long-handed inserters of the input side together). Not knowing the size (`limits.machine_size` nil) leaves the question
-- open and says yes. A side of woven belts is full and takes no row of poles, which stand beside the belts (see
-- scripts/weave.lua), so it does not count.
---@param limits bpgen.InserterLimits
---@param rates bpgen.MachineRates
---@return boolean
local function room_for_winding(limits, rates)
  local size = limits.machine_size
  if size == nil then
    return true
  end
  local input = rates.belt_inserters and 0 or rates.input_inserters + rates.long_inserters
  return size == WINDING_MACHINE_SIZE and math.max(input, rates.output_inserters) < size
end

-- The winding a machine's output inserters ask for when the belt can wind: "double" for two of them, which fill a lane
-- each, "paired" for one fast one, which fills a lane when the machines go in twos (nil when the caller does not give the
-- machine's size, which leaves out the paired belt), and nil for a plain belt.
---@param limits bpgen.InserterLimits
---@param rates bpgen.MachineRates
---@return "double"|"paired"|nil
local function winding_asked_for(limits, rates)
  if rates.output_inserters == WINDING_OUTPUT_INSERTERS then
    return "double"
  end
  if limits.machine_size ~= nil and rates.output_inserters == 1 and rates.output_fast then
    return "paired"
  end
  return nil
end

-- How the output belt of the stage takes the product of its machines (see layout.lua), as "double" when it winds so
-- that the two output inserters of a machine fill a lane each, "paired" when it winds so that machines side by side, each
-- with one output inserter, fill a lane each, and nil when it is a plain belt with the product on one lane. The belt of a
-- stage built wide is paired, for any machine and whatever it feeds. Otherwise only the root stage's belt winds, and only
-- on a 3x3 machine whose sides are not full: a full side takes a row of poles between the
-- machines (a machine fits a pole when an inserter does not take every tile beside it), and a winding belt has no room for
-- that. `limits.machine_size` is nil when the caller does not say, which leaves out the size and the rows of poles, and
-- the paired belt.
---@param stage bpgen.StageContext
---@return "double"|"paired"|nil
local function output_winding(stage)
  if stage.wide then
    return "paired"
  end
  local limits, rates = stage.request.inserters, stage.per_machine
  if stage.winds and limits and room_for_winding(limits, rates) then
    return winding_asked_for(limits, rates)
  end
  return nil
end

-- How many machines' worth of product the output belt can take. With one output
-- inserter per machine the product is on one lane, which carries all of it. With
-- two, the winding belt (only the last stage's output belt winds) gives each
-- inserter a lane, and the two lanes together carry all of it: an inserter that finds
-- its lane full waits, and the machine's other inserter, on the other lane, takes the rest
-- (owner, 2026-11-13; the game has not shown it), so the belt takes two lanes' worth, whichever of the lanes
-- fills first. (A machine whose outer lane is full is then held to what its one other
-- inserter moves, so near the most the belt carries the machines may make a little less than their full speed:
-- not counted.)
-- An output belt that does not wind carries everything on its one lane, whatever
-- the inserters. With the paired winding belt every machine has one inserter, which
-- fills one lane, and machines alternate lanes (outer, inner, inner, outer, ...): a lane
-- gets half the machines, and the lane that gets one more for an odd number is the one the last
-- machine is on, which is the only one that may run for part of the time. A lane that carries L
-- machines' worth (a fraction) takes floor(L) whole machines and, when it has the last one, the rest of L.
-- So an even number of machines is at most twice floor(L) and an odd number floor(L) + L, which is
-- the most the belt carries, in machines' worth: 48 for L = 24 (24 machines on each lane), and never
-- less than a plain belt does.
---@param stage bpgen.StageContext
---@return number
local function output_machines_worth(stage)
  local one_lane = stage.lane_items_per_minute / stage.per_machine.output
  local winding = output_winding(stage)
  if winding == "double" then
    return 2 * one_lane
  elseif winding == "paired" then
    return math.floor(one_lane + EPSILON) + one_lane
  end
  return one_lane
end

-- How many machines' worth of work the belts of one column can carry before a lane
-- is full: the output belt, and the lanes that carry each ingredient (two lanes for
-- an ingredient that has the belt to itself). It is not a whole number: the belts
-- set the limit, so a column whose belts carry 4.5 machines' worth gets 5 machines,
-- and the last works at half speed.
---@param stage bpgen.StageContext
---@return number
local function machines_per_belt(stage)
  local most = output_machines_worth(stage)
  for _, input in ipairs(stage.per_machine.inputs) do
    local lanes = lanes_carrying(stage.lanes, input.name)
    most = math.min(most, lanes * stage.lane_items_per_minute / input.per_minute)
  end
  return most
end

-- What one machine eats of `item` in a minute.
---@param inputs bpgen.PlanInput[]  what one machine eats, per ingredient
---@param item string  one of the ingredients
---@return number
local function eaten_of(inputs, item)
  local eaten = 0
  for _, input in ipairs(inputs) do
    if input.name == item then
      eaten = eaten + input.per_minute
    end
  end
  return eaten
end

-- What all the machines eat together, in the recipe's order.
---@param inputs_per_machine bpgen.PlanInput[]
---@param machines number
---@return bpgen.PlanInput[]
local function total_inputs(inputs_per_machine, machines)
  local totals = {}
  for _, input in ipairs(inputs_per_machine) do
    totals[#totals + 1] = {name = input.name, per_minute = machines * input.per_minute}
  end
  return totals
end

---@class bpgen.StageContext  what the planner works out about one stage before it is asked for a rate
---@field request bpgen.StageRequest
---@field suppliers bpgen.StageContext[]  the stages whose products it eats, in the order of the recipe's ingredients
---@field lane_items_per_minute number
---@field lanes string[]  the item on each lane of the belt that feeds the stage
---@field belts bpgen.Belts  which of its ingredients ride which input belt
---@field winds boolean  whether this stage's output belt may wind (only the root stage's can)
---@field per_machine bpgen.MachineRates
---@field wide boolean  whether the stage is built wide (see `bpgen.StageRequest.wide`)
---@field machines_worth number  how many machines' worth of work the belts of a column carry before a lane is full (not a whole number)

-- The lanes of a stage that burns fuel and is fed by another stage: the one ingredient that
-- stage makes on one lane (its products travel on one lane), the fuel on the other. Nil for
-- anything else: with a second ingredient, or a second stage feeding it, no lane is free.
---@param stage bpgen.StageRequest
---@param suppliers bpgen.StageContext[]
---@return string[]|nil lanes
---@return table<string, true>|nil raw  nothing: every ingredient is made
local function fuel_lanes(stage, suppliers)
  local ingredients = stage.recipe.ingredients
  if #ingredients ~= 1 or #suppliers ~= 1 or suppliers[1].request.product ~= ingredients[1].name then
    return nil
  end
  return {ingredients[1].name, stage.fuel}, {}
end

-- The lanes of a stage fed by one stage that is built wide: that stage's product rides both lanes of the belt between
-- them (see `takes_both_lanes`, which a stage that takes it so has), the lanes as they are for any other.
---@param lanes string[]  the ingredients, in the recipe's order
---@param suppliers bpgen.StageContext[]
---@return string[]
local function both_lanes_of_wide(lanes, suppliers)
  if suppliers[1] and suppliers[1].wide then
    lanes[2] = lanes[1]
  end
  return lanes
end

-- The most belts a stage takes from: three, unless the limits say fewer (the pole of the blueprint does not reach the
-- inserters of three woven belts, or the belts are not woven and a long-handed inserter reaches one belt over belt a).
---@param stage bpgen.StageRequest
---@return integer
local function most_belts(stage)
  return stage.inserters and stage.inserters.most_belts or MOST_BELTS
end

-- The items on the lanes of the belts that feed a stage, or nil when they do not
-- fit. A stage fed raw items shares the two lanes of its belt among them and its fuel
-- (see `assign_lanes`). Every other stage eats the products of the stages that feed it,
-- each on the one lane its product travels on, and at most one raw item, which has no
-- stage (nothing could put a fuel on those belts), so it has at most as many ingredients as its belts
-- have lanes: six for three belts.
-- The stages that feed it make ingredients of its recipe, in any order. The one exception
-- is a stage that burns fuel and eats one made ingredient (see `fuel_lanes`).
---@param stage bpgen.StageRequest
---@param suppliers bpgen.StageContext[]  the stages that feed it
---@return string[]|nil lanes  the ingredients, in the recipe's order
---@return table<string, true>|nil raw  the ingredients that no stage makes; nil for a stage fed raw items
local function stage_lanes(stage, suppliers)
  if #suppliers == 0 then
    return assign_lanes(stage.recipe.ingredients, stage.fuel)
  end
  local ingredients = stage.recipe.ingredients
  if stage.fuel then
    return fuel_lanes(stage, suppliers)
  end
  if #ingredients > most_belts(stage) * LANES_PER_BELT then
    return nil
  end
  local lanes, unmade = {}, {}
  for index, ingredient in ipairs(ingredients) do
    lanes[index] = ingredient.name
    unmade[ingredient.name] = true
  end
  for _, supplier in ipairs(suppliers) do
    if not unmade[supplier.request.product] then
      return nil
    end
    unmade[supplier.request.product] = nil
  end
  return both_lanes_of_wide(lanes, suppliers), unmade
end

-- The ways to put `count` ingredients on two belts, as the letter of the belt of each ingredient: those whose bit is set in
-- the number, from 1 up, go on belt b.
---@param count integer
---@return string[][]
local function two_belt_splits(count)
  local splits = {}
  for mask = 1, 2 ^ count - 1 do
    local letters = {}
    for index = 1, count do
      letters[index] = math.floor(mask / 2 ^ (index - 1)) % 2 == 1 and "b" or "a"
    end
    splits[#splits + 1] = letters
  end
  return splits
end

-- The belt of each of `count` ingredients that the digits of `number` in base three say (belt a is 0, b 1 and c 2, the first
-- ingredient being the lowest digit), and the place of the first ingredient on each belt.
---@param number integer
---@param count integer
---@return string[] letters
---@return table<string, integer> first
local function letters_of_number(number, count)
  local letters, first = {}, {}
  for index = 1, count do
    local letter = BELT_LETTERS[math.floor(number / 3 ^ (index - 1)) % 3 + 1]
    letters[index] = letter
    first[letter] = first[letter] or index
  end
  return letters, first
end

-- The ways to put `count` ingredients on three belts, all of them used. A split with belt c before belt b is another with the
-- two letters swapped, and is left out.
---@param count integer
---@return string[][]
local function three_belt_splits(count)
  local splits = {}
  for number = 0, 3 ^ count - 1 do
    local letters, first = letters_of_number(number, count)
    if first.a and first.b and first.c and first.b < first.c then
      splits[#splits + 1] = letters
    end
  end
  return splits
end

-- The ways to put `count` ingredients on belts, as the letter of the belt of each ingredient, for up to `belts` belts: first
-- those that use two belts, then those that use three.
---@param count integer
---@param belts integer  the most belts
---@return string[][]
local function splits_of(count, belts)
  local splits = two_belt_splits(count)
  if belts >= 3 then
    for _, letters in ipairs(three_belt_splits(count)) do
      splits[#splits + 1] = letters
    end
  end
  return splits
end

-- Whether no belt has more ingredients than it has lanes.
---@param belts bpgen.Belts
---@return boolean
local function fits_lanes(belts)
  for _, letter in ipairs(BELT_LETTERS) do
    if belts[letter] and #belts[letter] > LANES_PER_BELT then
      return false
    end
  end
  return true
end

-- The ingredients on the belts for one way of splitting them (see `splits_of`). Nil when a belt would have more than two, or
-- a raw ingredient would go on belt b or c (a belt of raw items fills both lanes, so it can only be side-loaded onto belt a).
-- Also gives how late in the recipe the ingredients of belt b and of belt c are, as the sums of their places.
---@param lanes string[]
---@param letters string[]  the belt of each ingredient
---@param raw table<string, true>
---@return bpgen.Belts|nil
---@return {b: integer, c: integer}|nil later
local function split_ingredients(lanes, letters, raw)
  local belts, later = {a = {}, b = {}}, {b = 0, c = 0}
  for index, name in ipairs(lanes) do
    local letter = letters[index]
    if letter ~= "a" and raw[name] then
      return nil
    end
    belts[letter] = belts[letter] or {}
    belts[letter][#belts[letter] + 1] = name
    later[letter] = (later[letter] or 0) + index
  end
  if not fits_lanes(belts) then
    return nil
  end
  return belts, later
end

-- How much of its full speed a machine can use for this split, or nil when its slots
-- cannot serve all the belts. Without an inserter limit every split is as good.
---@param inputs bpgen.PlanInput[]
---@param belts bpgen.Belts
---@param limits bpgen.InserterLimits|nil
---@return number|nil
local function split_fraction(inputs, belts, limits)
  if not limits then
    return 1
  end
  local flows = flows_of(inputs, belts)
  local counts = allotted_counts(flows, limits)
  return counts and input_fraction(flows, counts, limits)
end

-- What decides between two splits that run the machine equally fast, in order, the smaller number winning: how many
-- ingredients are on belt c (none when there are two belts, so fewer belts win) and on belt b, and how early in the recipe
-- the ingredients of belt c and then of belt b are (so the ingredients go on the belts in the recipe's order where nothing
-- else decides).
---@param split {belts: bpgen.Belts, later: {b: integer, c: integer}}
---@return integer[]
local function tie_breaks(split)
  return {#(split.belts.c or {}), #split.belts.b, -split.later.c, -split.later.b}
end

-- Whether a split beats the best so far: it runs the machine faster, or equally fast with a smaller number in the first
-- place that `tie_breaks` differs.
---@param candidate {fraction: number, belts: bpgen.Belts, later: {b: integer, c: integer}}
---@param best {fraction: number, belts: bpgen.Belts, later: {b: integer, c: integer}}|nil
---@return boolean
local function is_better(candidate, best)
  if not best then
    return true
  end
  if math.abs(candidate.fraction - best.fraction) > EPSILON then
    return candidate.fraction > best.fraction
  end
  local here, there = tie_breaks(candidate), tie_breaks(best)
  for index = 1, #here do
    if here[index] ~= there[index] then
      return here[index] < there[index]
    end
  end
  return false
end

-- Which ingredients ride which belt. A stage with up to two ingredients keeps them all on
-- belt a. With more, the split that lets a machine run fastest (see
-- `is_better`): it depends only on what one machine eats, not on the rate. Nil when no
-- split fits.
---@param stage bpgen.StageRequest
---@param lanes string[]
---@param raw table<string, true>
---@return bpgen.Belts|nil
local function choose_belts(stage, lanes, raw)
  if #lanes <= LANES_PER_BELT then
    return {a = lanes, b = {}}
  end
  local inputs = full_speed(stage)
  local best
  for _, letters in ipairs(splits_of(#lanes, most_belts(stage))) do
    local belts, later = split_ingredients(lanes, letters, raw)
    local fraction = belts and split_fraction(inputs, belts, stage.inserters)
    if belts and fraction then
      local candidate = {fraction = fraction, belts = belts, later = later}
      if is_better(candidate, best) then
        best = candidate
      end
    end
  end
  return best and best.belts
end

-- Whether a stage takes the product of the stage that feeds it on both lanes of one belt: it eats that product and
-- nothing else (no second ingredient, no fuel, whose lane the product would have to leave free), so a supplier built wide,
-- which puts its product on both lanes, can feed it. (A stage with one ingredient has one supplier at most.) A stage that
-- burns fuel takes plates on both lanes only when it is built wide too (it has a belt of its own for the fuel), which it is
-- when it asks for it and the tree allows it (`may_widen`): its supplier is not built wide for nothing otherwise.
---@param stage bpgen.StageRequest
---@param may_widen boolean  whether the tree allows `stage` itself to be built wide
---@return boolean
local function takes_both_lanes(stage, may_widen)
  return #stage.recipe.ingredients == 1 and (stage.fuel == nil or (stage.wide == true and may_widen))
end

-- Whether a stage is of the kind that is built wide (see `bpgen.StageRequest.wide`): it asks for it, burns fuel and eats
-- one ingredient, and it is fed raw items (its belt has a lane of each, and a second belt) or by a stage that is built wide
-- (the plates on both lanes of the belt, and a belt of its own for the fuel).
---@param stage bpgen.StageRequest
---@param suppliers bpgen.StageContext[]
---@return boolean
local function is_wide_kind(stage, suppliers)
  local fed_wide = #suppliers == 1 and suppliers[1].wide
  return stage.wide == true and stage.fuel ~= nil and #stage.recipe.ingredients == 1 and (#suppliers == 0 or fed_wide)
end

-- Whether the sides of a machine are what a stage built wide has: the layout knows the size of the machine, and a plain
-- inserter on each side moves what it needs (the second plain inserter, for belt b, then fills the input side).
---@param stage bpgen.StageRequest
---@param per_machine bpgen.MachineRates
---@return boolean
local function has_wide_sides(stage, per_machine)
  return stage.inserters ~= nil and stage.inserters.machine_size ~= nil
    and per_machine.input_inserters == 1 and per_machine.long_inserters == 0 and per_machine.output_inserters == 1
end

-- Whether a stage may be built wide.
---@param stage bpgen.StageRequest
---@param suppliers bpgen.StageContext[]
---@param per_machine bpgen.MachineRates
---@return boolean
local function can_be_wide(stage, suppliers, per_machine)
  return is_wide_kind(stage, suppliers) and has_wide_sides(stage, per_machine)
end

-- The four lanes of the two input belts of a stage built wide, from the two of the belt it would have. A stage fed raw
-- items keeps its ingredient and its fuel on belt a, and belt b carries the ingredient on both lanes. A stage fed by one
-- built wide has the ingredient on both lanes of the belt before it, and its fuel on both lanes of a belt of its own.
---@param lanes string[]  the ingredient and the fuel
---@param suppliers bpgen.StageContext[]
---@return string[]
local function wide_lanes(lanes, suppliers)
  if #suppliers == 0 then
    return {lanes[1], lanes[2], lanes[1], lanes[1]}
  end
  return {lanes[1], lanes[1], lanes[2], lanes[2]}
end

-- What one machine does when it has a second plain input inserter, for belt b.
---@param rates bpgen.MachineRates
---@return bpgen.MachineRates
local function with_second_inserter(rates)
  local wide = {}
  for key, value in pairs(rates) do
    wide[key] = value
  end
  wide.input_inserters = 2
  return wide
end

-- Whether a stage is built wide, with the lanes and the machine rates that go with it (as they were worked out when it is
-- not). `may_widen` is whether the tree asks for it of this stage (see `stage_context`). (A stage that burns fuel and
-- cannot be built wide after one that is, whose plates then fill both lanes of its belt and leave none for the fuel, is
-- planned with the lanes of a plain stage, so it makes no more than the plain design: the rate asked is refused.)
---@param stage bpgen.StageRequest
---@param suppliers bpgen.StageContext[]
---@param lanes string[]
---@param per_machine bpgen.MachineRates
---@param may_widen boolean
---@return boolean wide
---@return string[] lanes
---@return bpgen.MachineRates per_machine
local function widened(stage, suppliers, lanes, per_machine, may_widen)
  if not (may_widen and can_be_wide(stage, suppliers, per_machine)) then
    return false, lanes, per_machine
  end
  return true, wide_lanes(lanes, suppliers), with_second_inserter(per_machine)
end

-- The lanes, the belts and what one machine does for a stage fed by `suppliers`, before it is built wide, or nil when it
-- does not fit (see `stage_lanes`, `is_supported`).
---@param stage bpgen.StageRequest
---@param suppliers bpgen.StageContext[]
---@return string[]|nil lanes
---@return bpgen.Belts|nil belts
---@return bpgen.MachineRates|nil per_machine
local function machine_setup(stage, suppliers)
  local lanes, raw = stage_lanes(stage, suppliers)
  if not lanes or not is_supported(stage.recipe, stage.product) then
    return nil
  end
  local belts = choose_belts(stage, lanes, raw or {})
  local per_machine = belts and rates_per_machine(stage, belts)
  if not per_machine then
    return nil
  end
  return lanes, belts, per_machine
end

local stage_context -- defined below: a stage is worked out with the stages that feed it

-- The contexts of the stages that feed a stage, or nil when one of them does not fit. A stage that feeds a stage that takes
-- its product on both lanes (see `takes_both_lanes`) may be built wide where `widen` says so.
---@param tree bpgen.StageTree
---@param request bpgen.TreeRequest
---@param widen boolean
---@param may_widen boolean  whether the tree allows the stage itself to be built wide
---@return bpgen.StageContext[]|nil
local function supplier_contexts(tree, request, widen, may_widen)
  local suppliers = {}
  local suppliers_may_widen = widen and takes_both_lanes(tree.stage, may_widen)
  for index, supplier in ipairs(tree.suppliers) do
    suppliers[index] = stage_context(supplier, request, false, widen, suppliers_may_widen)
    if not suppliers[index] then
      return nil
    end
  end
  return suppliers
end

-- Everything the planner works out about a stage and the stages that feed it before
-- it is asked for a rate, or nil when one of them does not fit (see `stage_lanes`,
-- `is_supported`). Only the root stage may wind its output belt, but for the stages built wide: a stage is built wide when
-- `may_widen` (the tree is built that way, and the stage is the root or feeds a stage that takes its product on both
-- lanes) and it is of the kind that can be (see `can_be_wide`).
---@param tree bpgen.StageTree
---@param request bpgen.TreeRequest
---@param is_root boolean
---@param widen boolean  build the stages that can be built wide that way
---@param may_widen boolean  this stage may be one of them
---@return bpgen.StageContext|nil
function stage_context(tree, request, is_root, widen, may_widen)
  local suppliers = supplier_contexts(tree, request, widen, may_widen)
  if not suppliers then
    return nil
  end
  local stage = tree.stage
  local lanes, belts, per_machine = machine_setup(stage, suppliers)
  if not (lanes and belts and per_machine) then
    return nil
  end
  local wide
  wide, lanes, per_machine = widened(stage, suppliers, lanes, per_machine, may_widen)
  ---@type bpgen.StageContext
  local context = {
    request = stage, suppliers = suppliers, lane_items_per_minute = request.lane_items_per_minute,
    lanes = lanes, belts = belts, winds = is_root, wide = wide, per_machine = per_machine, machines_worth = 0,
  }
  context.machines_worth = machines_per_belt(context)
  return context
end

-- The context of the whole tree, whose root may be built wide when `widen` says the tree is.
---@param request bpgen.TreeRequest
---@param widen boolean
---@return bpgen.StageContext|nil
local function root_context(request, widen)
  return stage_context(request.root, request, true, widen, widen)
end

-- What the rate asks of every stage of a tree.
---@class bpgen.Sizes
---@field machines table<bpgen.StageContext, integer>
---@field loads table<bpgen.StageContext, number>  how many machines' worth of work the rate asks of the stage, a fraction
---@field rates table<bpgen.StageContext, bpgen.MachineRates>  what one machine of the stage does once its inserters fit its share

-- How many machines a stage gets for `wanted` items a minute of its product, and the
-- same for the stages that feed it. The root stage gets as many as the rate needs. A
-- stage that feeds another gets as many as make what the stage it feeds needs to make
-- its own share of the rate, not what all the machines of that stage could eat: asking
-- for 1 gear a minute takes 2 plates a minute, so one furnace, even though the
-- assembler could eat more. (The rate is at most what the belts carry, see
-- `planner.plan_tree`, so no stage gets more machines than its belts carry.) Also gives
-- each stage's load: how many machines' worth of work the rate asks of it, which is
-- not a whole number (1 gear a minute asks a fifth of a furnace's plates, say).
---@param stage bpgen.StageContext
---@param wanted number
---@param sizes bpgen.Sizes
local function size_stages(stage, wanted, sizes)
  local per_machine = stage.per_machine
  sizes.loads[stage] = wanted / per_machine.output
  sizes.machines[stage] = whole_machines(sizes.loads[stage])
  for _, supplier in ipairs(stage.suppliers) do
    size_stages(supplier, wanted * eaten_of(per_machine.inputs, supplier.request.product) / per_machine.output, sizes)
  end
end

-- What one machine of a stage does for the work the rate asks (`load`). A machine that
-- is used for less than a whole (the stage has one machine and its load is under 1)
-- needs only the inserters for the share it uses: a machine that takes two inserters
-- to run flat out takes one for 40%. With two or more machines the first ones run flat
-- out (the belt gives the machines at its start all they can take, and only the last
-- one runs part of the time), so they keep every inserter.
---@param stage bpgen.StageContext
---@param load number
---@return bpgen.MachineRates
local function stage_rates(stage, load)
  local limits = stage.request.inserters
  local used = math.min(load, 1) -- the share of its full speed the busiest machine runs at
  if not limits or used >= 1 - EPSILON or stage.wide then
    return stage.per_machine
  end
  return rates_per_machine(stage.request, stage.belts, {share = used, rates = stage.per_machine}) --[[@as bpgen.MachineRates]] -- it fitted once, at full speed
end

-- Fills in what one machine does for a stage and for the stages that feed it.
---@param stage bpgen.StageContext
---@param sizes bpgen.Sizes  with the loads filled in
local function size_rates(stage, sizes)
  sizes.rates[stage] = stage_rates(stage, sizes.loads[stage])
  for _, supplier in ipairs(stage.suppliers) do
    size_rates(supplier, sizes)
  end
end

---@param root bpgen.StageContext
---@param rate_per_minute number
---@return bpgen.Sizes
local function sizes_for(root, rate_per_minute)
  local sizes = {machines = {}, loads = {}, rates = {}}
  size_stages(root, rate_per_minute, sizes)
  size_rates(root, sizes)
  return sizes
end

-- The most of the root stage's product that a stage and the stages that feed it make
-- together, in items a minute. A stage makes what its machines make (`sizes` says how
-- many it has and what each does; nil for as many machines as its belts carry), but
-- no more than its belts carry, and the stage it feeds can only make as much as its
-- products allow. `needed` is how many items of the stage's product go into each item
-- of the root's.
---@param stage bpgen.StageContext
---@param needed number
---@param sizes? bpgen.Sizes
---@return number
local function final_output(stage, needed, sizes)
  local working = math.min(sizes and sizes.machines[stage] or math.huge, stage.machines_worth)
  local rates = sizes and sizes.rates[stage] or stage.per_machine
  local most = working * rates.output / needed
  for _, supplier in ipairs(stage.suppliers) do
    local supplier_needed = needed * eaten_of(stage.per_machine.inputs, supplier.request.product) / stage.per_machine.output
    most = math.min(most, final_output(supplier, supplier_needed, sizes))
  end
  return most
end

-- `machines` machines are built, but those past what the belts carry only wait, so
-- the stage makes and eats what its belts carry. A stage shown making less than that
-- (the root, when the stages before it cannot feed it fully) eats less as well.
---@param stage bpgen.StageContext
---@param machines integer
---@param load number  how many machines' worth of work the rate asks of the stage
---@param rates bpgen.MachineRates  what one machine of the stage does (see `stage_rates`)
---@param output? number  what the stage really makes a minute; all its machines can make by default
---@return bpgen.Plan
local function stage_plan(stage, machines, load, rates, output)
  local working = math.min(machines, stage.machines_worth)
  output = output or working * rates.output
  return {
    machines = machines,
    load = load,
    output_per_minute = output,
    inputs = total_inputs(stage.per_machine.inputs, output / stage.per_machine.output), -- the same fractions of its inputs and output, trimmed or not
    lanes = stage.lanes,
    belts = stage.belts,
    input_inserters = rates.input_inserters,
    input_fast = rates.input_fast,
    long_inserters = rates.long_inserters,
    belt_inserters = rates.belt_inserters,
    output_inserters = rates.output_inserters,
    output_fast = rates.output_fast,
    wide = stage.wide,
  }
end

-- The plans of a stage and of the stages that feed it. What the root stage makes is
-- what all the stages make together (`root_output`); an earlier stage shows what its
-- machines can make.
---@param stage bpgen.StageContext
---@param sizes bpgen.Sizes
---@param root_output? number  nil except for the root stage
---@return bpgen.PlanTree
local function plans_of(stage, sizes, root_output)
  local suppliers = {}
  for index, supplier in ipairs(stage.suppliers) do
    suppliers[index] = plans_of(supplier, sizes, nil)
  end
  local plan = stage_plan(stage, sizes.machines[stage], sizes.loads[stage], sizes.rates[stage], root_output)
  return {plan = plan, suppliers = suppliers}
end

-- request.rate_per_minute         how many of the root stage's product per minute
-- request.lane_items_per_minute   how many items one belt lane can carry per minute
-- request.root                    the stage that makes what the player wants, with
--                                 the stages that make its ingredients (see
--                                 `bpgen.StageTree`); each stage is
--   {product = item name, recipe = {energy = seconds,
--                                   ingredients = {{name = ..., amount = ...}},
--                                   products = {{name = ..., amount = ...}}},
--    machine_speed = the machine's crafting speed,
--    fuel = optional item the machine burns (a stage fed raw items, or one that eats
--           one made ingredient; it takes one lane of the input belt),
--    inserters = optional {items_per_minute, long_items_per_minute,
--           fast_items_per_minute, max_input, max_woven_input, most_belts,
--           max_output}: how much one inserter (a plain one, a long-handed one and a
--           fast one when the game has them) moves, and how many inserters the input
--           side (`max_woven_input` for a stage whose belts are woven, nil when they
--           are not) and the output side of a machine get. A machine that would need
--           more runs slower, at what they can move. Two output inserters put the
--           product on both lanes of the output belt, but only for the root stage}
--
-- A stage fed raw items shares the two lanes of its input belt among them and its
-- fuel: one item fills both lanes, two items get a lane each, and more are refused. A
-- stage that burns fuel and eats the one product of the stage before it (steel plate from
-- iron plates) has that product on one lane and the fuel on the other.
-- Any other stage eats the products of the stages that feed it, and at most one raw
-- item more, each on the one lane it travels on. With one or two ingredients they all
-- ride the belt next to the machines (belt a). With more there are a second belt (b), and
-- a third (c) for a stage whose belts are woven. Woven belts (b and c woven with belt a
-- so that plain inserters take from all of them: see scripts/weave.lua) are what the
-- layout draws when it has the splitters and underground belts for them
-- (`max_woven_input` is given); without them belt b is one column further out and
-- long-handed inserters take from it over belt a, and there are two belts. The planner
-- splits the ingredients between the belts, at most two on each and a raw one only on
-- belt a, so that a machine runs fastest (`choose_belts`), with as few belts as it takes.
--
-- On success returns a tree of plans in the shape of the request's: for each stage
--   {machines, output_per_minute, inputs, lanes, belts, input_inserters,
--    long_inserters, belt_inserters, output_inserters}
--   inputs   {{name, per_minute}, ...} what the machines eat in total, per ingredient
--   lanes    the item on each lane of the input belts (two entries for a stage fed raw
--            items, one for each ingredient of any other)
--   belts    {a = {...}, b = {...}, c = {...}} which ingredients ride which belt (c only
--            for a stage that takes from three woven belts)
--   *_inserters  inserters per machine: on the input side that take from the column in front of them (all
--            of them for woven belts, those for belt a with long-handed ones for belt b) and on the
--            output side; `long_inserters` is the long-handed ones for belt b, and `belt_inserters` how
--            many of the input ones take from each woven belt, for a stage with more than one
-- Each stage makes what the stages it feeds eat, and the root makes at least the rate
-- asked.
-- On failure returns nil, a reason string, and sometimes an extra value:
--   "unsupported-recipe"        a stage does not fit the belts, makes more than one
--                               product, or is not made by its product
--   "rate-too-high", max_rate   a belt lane cannot carry that rate, in some stage;
--                               max_rate is the most the root stage can make per
--                               minute in a single blueprint
--
-- Belt limits are counted in fractions of a machine (`machines_worth`): a lane that
-- carries 4.5 machines' worth feeds 5 machines, and the rate is limited by the lane.
---@param request bpgen.TreeRequest
---@return bpgen.PlanTree|nil plans
---@return bpgen.PlanReason|nil reason
---@return number|nil max_rate  only with "rate-too-high"
function planner.plan_tree(request)
  local root = root_context(request, false)
  if not root then
    return nil, "unsupported-recipe"
  end
  if request.rate_per_minute > final_output(root, 1) + EPSILON then
    root = root_context(request, true) --[[@as bpgen.StageContext]] -- it fits when the same stages do, narrow
  end
  local most = final_output(root, 1)
  if request.rate_per_minute > most + EPSILON then
    return nil, "rate-too-high", most
  end
  local sizes = sizes_for(root, request.rate_per_minute)
  return plans_of(root, sizes, final_output(root, 1, sizes))
end

-- The most the root stage of the request can make per minute in a single blueprint,
-- the same number `plan_tree` names with "rate-too-high". The request's rate is not
-- used. Returns nil and "unsupported-recipe" when some stage does not fit the belts.
---@param request bpgen.TreeRequest
---@return number|nil max_rate
---@return bpgen.PlanReason|nil reason
function planner.max_tree_rate(request)
  local root = root_context(request, true)
  if not root then
    return nil, "unsupported-recipe"
  end
  return final_output(root, 1), nil
end

-- A chain is a tree in which every stage is fed by the one before it. Nil for no stages.
---@param stages bpgen.StageRequest[]  from the stage fed raw items to the last
---@return bpgen.StageTree|nil
local function chain_tree(stages)
  local tree
  for _, stage in ipairs(stages) do
    tree = {stage = stage, suppliers = tree and {tree} or {}}
  end
  return tree
end

-- The plans of a chain's tree as a list, first stage first.
---@param plans bpgen.PlanTree
---@return bpgen.Plan[]
local function chain_plans(plans)
  local list = {}
  local tree = plans
  while tree do
    table.insert(list, 1, tree.plan)
    tree = tree.suppliers[1]
  end
  return list
end

-- request.rate_per_minute         how many of the last stage's product per minute
-- request.lane_items_per_minute   how many items one belt lane can carry per minute
-- request.stages                  the stages in order, from the one fed raw items to
--                                 the one that makes what the player wants (see
--                                 `planner.plan_tree` for what a stage is)
--
-- A later stage eats only the product of the stage before it, which travels on one lane.
-- On success returns one plan table per stage, in the same order, with the fields
-- `plan_tree` names. On failure returns the same as `plan_tree`.
---@param request bpgen.ChainRequest
---@return bpgen.Plan[]|nil plans
---@return bpgen.PlanReason|nil reason
---@return number|nil max_rate  only with "rate-too-high"
function planner.plan_chain(request)
  local root = chain_tree(request.stages)
  if not root then
    return nil, "unsupported-recipe"
  end
  local plans, reason, max_rate = planner.plan_tree{
    rate_per_minute = request.rate_per_minute,
    lane_items_per_minute = request.lane_items_per_minute,
    root = root,
  }
  if not plans then
    return nil, reason, max_rate
  end
  return chain_plans(plans)
end

-- The most the last stage of the request can make per minute in a single column, the
-- same number `plan_chain` names with "rate-too-high". The request's rate is not used.
-- Returns nil and "unsupported-recipe" when some stage does not fit the belts.
---@param request bpgen.ChainRequest
---@return number|nil max_rate
---@return bpgen.PlanReason|nil reason
function planner.max_rate(request)
  local root = chain_tree(request.stages)
  if not root then
    return nil, "unsupported-recipe"
  end
  return planner.max_tree_rate{
    rate_per_minute = request.rate_per_minute,
    lane_items_per_minute = request.lane_items_per_minute,
    root = root,
  }
end

-- One stage on its own: `plan_chain` with a single stage. The request has the
-- fields of a chain request's one stage, plus `rate_per_minute` and
-- `lane_items_per_minute`, and the answer is that stage's plan.
---@param request bpgen.PlanRequest
---@return bpgen.Plan|nil plan
---@return bpgen.PlanReason|nil reason
---@return number|nil max_rate  only with "rate-too-high"
function planner.plan(request)
  local plans, reason, max_rate = planner.plan_chain{
    rate_per_minute = request.rate_per_minute,
    lane_items_per_minute = request.lane_items_per_minute,
    stages = {request},
  }
  if not plans then
    return nil, reason, max_rate
  end
  return plans[1]
end

return planner
