# Blueprint Generation

A Factorio 2.1 mod that builds blueprints for you. Pick an item and how many you want per minute, and the mod puts a ready-to-place blueprint on your cursor. The blueprint carries raw materials from a belt into machines, through every intermediate product on the way, and the finished product onto an output belt: ores in, final product out.

Status: early development.

## Using it

1. Click the "Generate blueprint" button in the shortcut bar.
2. Choose the item to produce (iron plate is already selected) and enter a rate in items per minute.
3. Click Generate. The blueprint appears on your cursor. It is temporary, like a blueprint taken from the library: it takes no inventory space, and it disappears if you put it away without placing it (generate it again if that happens). Place it, put the inputs on the input belt (the message says which item goes on which lane) and connect the poles to your power network.

## What can be generated

| Item | Made in | Inputs on the input belt |
|---|---|---|
| Iron plate | Stone furnaces | Iron ore on one lane, coal on the other |
| Copper plate | Stone furnaces | Copper ore on one lane, coal on the other |
| Stone brick | Stone furnaces | Stone on one lane, coal on the other |
| Iron gear wheel | Stone furnaces (plates), then assembling machines 1 (gears) | Iron ore on one lane, coal on the other. The assemblers are electric and take the plates straight from the furnaces |

A blueprint is a row of columns of machines, one column per step from the raw items to the product, from left to right. A column is an input belt, inserters, the machines, output inserters and an output belt, and the output belt of one column is the input belt of the next. The belt between two columns runs toward the machines that still need its items, so none of the plates pass the second column by: up the page when the first column is the taller one, down when the second is. All the columns start on the same row. Iron plate, copper plate and stone brick take one column (furnaces fed with ore and coal). Iron gear wheel takes two: furnaces on the left make plates from iron ore, and assembling machines on the right make gear wheels from those plates. Small electric poles are placed and wired for you, and one wire joins each column to the next, so the whole blueprint needs one connection to your power network. The belts, inserters and poles are the first-tier ones (transport belt, inserter, small electric pole); there is no choice of tier yet.

### How the columns are found

The table only says which items you can ask for. The steps come from the game's recipes: the mod looks up the recipe that makes the item, then the recipe for the ingredient that is itself made, and so on until the ingredients are raw (no recipe it can build makes them, like ores and stone). The machine of each step comes from the recipe's category, set in `scripts/config.lua` (smelting: stone furnace burning coal; crafting: assembling machine 1). A request is refused, with a message, when:

- no recipe the mod can build makes the item, or more than one does (it cannot choose between them yet);
- a step has more than one ingredient that is itself made (a tree, such as a recipe that needs both gears and pipes). Only a straight line of steps is built;
- a step after the first mixes the product of the step before with other ingredients, or needs fuel. The raw items and the fuel ride on the first belt only, and the belt between two columns carries one item;
- a recipe has a fluid among its ingredients, or makes more than one product.

### Lanes and inserters

The first input belt has two lanes, and the message says which item goes where: an ingredient and the fuel get a lane each (furnaces), an ingredient with no fuel gets both lanes, and a recipe with two ingredients and no fuel gets one lane each. A first step that needs more items than two lanes hold (two ingredients and a fuel, or three ingredients) is refused. An inserter drops items on the far lane of a belt, so a plain output belt carries the product on one lane only. That is the case for every belt between two columns, and the next column picks the product up from it. The output belt of the last column can wind and fill both lanes: a 3 x 3 machine with two output inserters gets a winding output belt (see below).

Each side of a machine gets as many inserters as the machine needs, up to one fewer than it is wide: one beside a 2 x 2 furnace, two beside a 3 x 3 assembling machine (output side: at most 2, whatever the size). That keeps one tile beside every machine free for a pole, so the machines sit side by side with no gaps. A machine that would need more inserters than that simply runs slower, and the blueprint is sized for it: an assembling machine 1 making gear wheels would eat 120 plates per minute and make 60 gears, but two basic inserters move about 100 plates, so each machine makes about 50 gears per minute. The message shows the real total. The inserter's speed comes from the game data.

### The winding output belt

When a 3 x 3 machine in the last column needs two output inserters, the output belt is two tiles from the machine side and winds in and out. Its path, going down, is `DDLDRDDLDR...` (U/D/L/R = up/down/left/right): the first inserter drops onto the tile after the `L`, and the second inserter drops onto a short side belt (`R`) that side-loads the inner lane of the main belt, which the first inserter cannot reach. Both lanes end up carrying the product. It uses one more column than a plain belt and six belt tiles per machine. Machines with one output inserter keep the plain belt, and so does every column that feeds another one.

## Limits

- **A lane carries 450 items per minute.** The product travels on one lane (plain belt) or two (winding belt, two output inserters), so one blueprint makes at most 450 or 900 per minute, depending on what the machines can move, and the ingredients get one lane each, or both lanes (900 per minute) when one ingredient has the belt to itself. A stone furnace makes 18.75 plates or bricks per minute, so a plate blueprint has at most 24 furnaces. A higher rate is refused with a message that names the most one blueprint can make. Splitting a bigger request into several blueprints is not supported.
- **Every column has its own limit.** Each column must make what the next one eats, and the belt between two columns is a plain belt that carries one item on one lane, so the limit of every column counts and the lowest one wins. Gear wheels: each assembling machine eats about 100.8 plates per minute (two basic inserters move that much, see above), so one lane of plates feeds 4 machines, and one blueprint makes at most 201.6 gears per minute (22 furnaces and 4 assemblers; the message names the exact number). Asking for 100 gears per minute builds 11 furnaces and 2 assemblers. Before columns were chained, a belt of plates on both lanes allowed twice that.
- **Recipes that eat a lot hit the limit sooner.** A brick takes two stone, so each furnace eats 37.5 stone per minute and the stone lane fills first: at most 12 furnaces and 225 bricks per minute. With two output inserters the winding belt is limited per lane: a machine's first inserter takes all it can, so the machines are capped at the number whose first inserters fit in one lane (450 / 50.4 = 8). That rule is a conservative assumption, not yet checked in game.
- **The rate is rounded up to whole machines.** Asking for 100 plates per minute builds 6 furnaces, which make 112.5 per minute. The message shows both numbers.
- **The winding belt needs a 3 x 3 machine, in the last column.** A 2 x 2 machine has room for one output inserter only, and a column that feeds another one keeps a plain belt.
- **Machines run on electricity or burn fuel.** The mod reads which from the machine in the game, so a machine from another mod works if it fits. The fuel the mod puts on the input belt is still set in `scripts/config.lua`; the mod checks that the machine can burn it (and that an electric machine has none set), and refuses with a message if not. A machine that runs on heat or a fluid is refused.
- **Machines are 2 x 2 or 3 x 3.** Any other size, or a machine that is not square, is refused.
- **You supply the inputs.** The blueprint contains no mining, no ore sources and no coal supply, only the columns themselves.
- **You supply the power.** The poles are connected to each other, not to your network.
- **Only the items in the table above.** Other items are refused, and so is an item whose recipes the mod cannot chain (see "How the columns are found"). The first step has one product and either one ingredient (with or without fuel) or two ingredients (when the machine burns no fuel); every later step has one ingredient, the product of the step before, and burns no fuel.
- **Machines are chosen per recipe category, not per item.** `scripts/config.lua` names one machine for each category (smelting and crafting for now), and an intermediate step uses the machine of its own recipe's category. Picking better machines from the player's research is a later feature.
- **The limits follow the game.** The belt limit, the machine speed and the number of inserters are worked out from the current game data, so a mod that changes the transport belt, the machine or the inserter changes the blueprint.

## Running the tests

The tests run outside the game with [busted](https://lunarmodules.github.io/busted/), a Lua testing tool. They check that the generator's logic is consistent. They cannot show that Factorio accepts a blueprint; only loading it in the game does that.

1. Install Lua and LuaRocks (Lua 5.2 is the closest match to Factorio's Lua), then run `luarocks install busted`. On Windows, WSL or Docker is the easy route.
2. From the repository root, run `busted`.

The settings are in `.busted`: specs are the `spec/*_spec.lua` files, and `spec/helper.lua` provides stand-ins for the game's `defines` table before they run. Specs for modules that read the game's `prototypes` table assign a fake one first.

## Editor setup (VS Code)

The code carries type annotations (`---@param`, `---@class`, ...) so the editor can flag a wrong argument or a misspelled field as you type. They are plain comments: Factorio ignores them and nothing is checked while the game runs.

1. Install the [EmmyLua](https://marketplace.visualstudio.com/items?itemName=tangzx.emmylua) extension (`tangzx.emmylua`) and, if you have the other popular Lua extension (sumneko), disable it for this workspace.
2. Install the [Factorio Modding Toolkit](https://marketplace.visualstudio.com/items?itemName=justarandomgeek.factoriomod-debug) and pick your Factorio version when it asks. It supplies the types of Factorio's own API (`game`, `LuaPlayer`, `defines`, ...).
3. `.emmyrc.json` in this repository sets the Lua version. If the editor shows problems the code should not have, run `Factorio: Check Config` from the command palette.

The shared types of this mod are in `scripts/types.lua`; their names start with `bpgen.`.
