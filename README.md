# Blueprint Generation

A Factorio 2.1 mod that builds blueprints for you. Pick an item and how many you want per minute, and the mod puts a ready-to-place blueprint on your cursor. The blueprint carries raw materials from belts into machines and the finished product onto an output belt.

Status: early development.

## Using it

1. Click the "Generate blueprint" button in the shortcut bar.
2. Choose the item to produce (iron plate is already selected) and enter a rate in items per minute.
3. Click Generate. The blueprint appears on your cursor. It is temporary, like a blueprint taken from the library: it takes no inventory space, and it disappears if you put it away without placing it (generate it again if that happens). Place it, put the inputs on the input belt (the message says which item goes on which lane) and connect the poles to your power network.

## What can be generated

| Item | Made in | Inputs on the input belt |
|---|---|---|
| Iron plate | Stone furnace | Iron ore on one lane, coal on the other |
| Copper plate | Stone furnace | Copper ore on one lane, coal on the other |
| Stone brick | Stone furnace | Stone on one lane, coal on the other |
| Iron gear wheel | Assembling machine 1 | Iron plates on one lane (the machine is electric, so no coal) |

Every blueprint is one column of machines: an input belt on the left, inserters, the machines, output inserters, and an output belt on the right. Small electric poles are placed and wired for you. The belts, inserters and poles are the first-tier ones (transport belt, inserter, small electric pole); there is no choice of tier yet.

A machine that needs more items than one inserter can move gets several inserters on each side. The number comes from the inserter's rotation speed in the game data: an assembling machine 1 making gear wheels eats 120 plates per minute and makes 60 gears, and a basic inserter moves about 50, so each machine gets three input inserters and two output inserters.

## Limits

- **One belt lane per flow.** The input (ore, stone or plates) and the output each travel on a single lane of a transport belt. A lane carries 450 items per minute, and a stone furnace makes 18.75 plates or bricks per minute, so one blueprint can have at most 24 furnaces and make at most 450 per minute. A higher rate is refused with a message that names the most one blueprint can make. Splitting a bigger request into several blueprints is not supported.
- **Recipes that eat a lot hit the limit sooner.** A brick takes two stone, so each furnace eats 37.5 stone per minute and the input lane fills first: at most 12 furnaces and 225 bricks per minute. Gear wheels are tighter still: each assembling machine eats 120 plates per minute, so one lane feeds 3 machines and at most 180 gears per minute.
- **The rate is rounded up to whole machines.** Asking for 100 plates per minute builds 6 furnaces, which make 112.5 per minute. The message shows both numbers.
- **Machines are 2 x 2 or 3 x 3.** Any other size, or a machine that is not square, is refused. So is a recipe that would need more inserters beside one machine than fit (three per side on a 3 x 3 machine).
- **You supply the inputs.** The blueprint contains no mining, no ore sources and no coal supply, only the column itself.
- **You supply the power.** The poles are connected to each other, not to your network.
- **Only the items in the table above.** Other items are refused. Recipes that need more than one ingredient are not supported yet.
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
