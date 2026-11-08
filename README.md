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
| Copper cable | Stone furnaces (plates), then assembling machines 1 (cables) | Copper ore on one lane, coal on the other. One plate makes two cables, so each assembler has two output inserters and the cable belt winds; at most 900 per minute (24 furnaces, 9 assemblers) |
| Wooden chest | Assembling machines 1 | Wood on both lanes |
| Iron chest | Stone furnaces (plates), then assembling machines 1 (chests) | Iron ore on one lane, coal on the other |
| Pipe | Stone furnaces (plates), then assembling machines 1 (pipes) | Iron ore on one lane, coal on the other |
| Stone furnace | Assembling machines 1 | Stone on both lanes |
| Firearm magazine | Stone furnaces (plates), then assembling machines 1 (magazines) | Iron ore on one lane, coal on the other |
| Light armor | Stone furnaces (plates), then assembling machines 1 (armor) | Iron ore on one lane, coal on the other |
| Electronic circuit | Stone furnaces (iron plates, copper plates), assembling machines 1 (copper cable), then assembling machines 1 (circuits) | Two belts, from the top down as the message says: iron ore on one lane and coal on the other, copper ore on one lane and coal on the other. At most 150 per minute |
| Transport belt | Stone furnaces (plates), assembling machines 1 (gears), then assembling machines 1 (belts) | Two belts, each with iron ore on one lane and coal on the other |
| Burner inserter | Stone furnaces (plates), assembling machines 1 (gears), then assembling machines 1 (inserters) | Two belts, each with iron ore on one lane and coal on the other |
| Pipe to ground | Stone furnaces (plates), assembling machines 1 (pipes), then assembling machines 1 (pipes to ground) | Two belts, each with iron ore on one lane and coal on the other |
| Boiler | Assembling machines 1 (stone furnaces), stone furnaces (plates), assembling machines 1 (pipes), then assembling machines 1 (boilers) | Two belts: stone on both lanes of the first, iron ore on one lane and coal on the other of the second |
| Offshore pump | Stone furnaces (plates), assembling machines 1 (pipes), stone furnaces (plates), assembling machines 1 (gears), then assembling machines 1 (pumps) | Two belts, each with iron ore on one lane and coal on the other |
| Automation science pack | Stone furnaces (copper plates), stone furnaces (iron plates), assembling machines 1 (gears), then assembling machines 1 (science packs) | Two belts: copper ore and coal, then iron ore and coal |
| Small electric pole | Stone furnaces (copper plates), assembling machines 1 (cables), then assembling machines 1 (poles) | Two belts: copper ore and coal, then wood on both lanes; at most 450 per minute (the lane of cables) |

The assembling machines come with their recipe already set; a furnace needs none. A blueprint is a row of columns of machines, one column per step from the raw items to the product, from left to right. A column is an input belt, inserters, the machines, output inserters and an output belt, and the output belt of one column is the input belt of the next. The belt between two columns runs toward the machines that still need its items, so none of the plates pass the second column by: up the page when the first column is the taller one, down when the second is. All the columns start on the same row. Iron plate, copper plate and stone brick take one column (furnaces fed with ore and coal). Iron gear wheel takes two: furnaces on the left make plates from iron ore, and assembling machines on the right make gear wheels from those plates. Small electric poles are placed and wired for you, and one wire joins each column to the next, so the whole blueprint needs one connection to your power network. The belts, inserters and poles are the first-tier ones (transport belt, inserter, small electric pole); there is no choice of tier yet.

### Recipes with two made ingredients

An electronic circuit is an iron plate and three copper cables, and the cables are made from copper plates. The mod builds the blueprint for each ingredient (a block: the row of columns above, with its own belt of raw items) and puts the machines that eat them in a column of their own to the right. The two blocks are stacked, the taller one on top. The upper block stays in the corner and its product belt goes on straight down beside the lower block, as the input belt of the new column. The lower block is moved until its product belt, which runs north, is beside it: east when the lower block is narrower, west (past the corner) when it is as wide or wider, in which case its belt of raw items is simply the longer for it. The lower block starts in the row where its product belt turns east into the side of the input belt. An inserter drops on the far lane and a belt that feeds the side of another puts everything on the near lane, so the two ingredients ride different lanes, and the inserters of the new column take both. A block can contain blocks, as deep as the recipe goes (a transport belt is an iron plate and a gear, and a gear is made from iron plates). Each block has its own belt of raw items, so the circuit takes two (iron ore and coal, copper ore and coal). They all enter at the top left, side by side: a belt that does not start in the corner gets a trail of belts down the west side of the blueprint, from its top row, and east into its first tile, so you only have to lay the belts in from one corner. The message lists them starting with the one next to the blueprint and going west. A line of poles runs beside the product belt of each block, so the blocks are wired together too.

### A raw item next to a made one

A small electric pole is a wood and two copper cables. The cables get a block, as above. The wood has no recipe, so it needs no machines: it is a block of its own that is only a belt, one row tall, which always goes below the other block. Its belt is a trail from the top left like the others, so it runs along the bottom of the cables' block, and its first tile turns east into the side of the input belt, where the wood lands on the near lane while the cables are on the far one. The pole machines take both. The wood is the last of the belts of raw items the message lists.

### Recipes with three or four ingredients

A belt has only two lanes, so a machine that eats three or four items takes them from two belts side by side: belt a, next to its inserters, and belt b, one column further west. A plain inserter takes from belt a, and a long-handed inserter, standing in the same column of inserters, reaches over belt a to take from belt b. Each machine gets one plain and one long-handed inserter (a machine has room for two inserters on its input side). Which ingredients go on which belt is decided for speed: a long-handed inserter moves 72 items a minute against 50.4 for a plain one, so the mod tries every split (at most two ingredients on a belt, a raw item only on belt a) and takes the one that lets a machine run fastest. An inserter, for example, wants 60 circuits, 60 gears and 60 plates a minute at full speed: with the circuits alone on belt a and the other two on belt b, an assembler makes 36 a minute; the other splits make 25.

The blocks that make the ingredients stand one above the other. The ingredients of belt a come first from the top, the first one's product belt becoming belt a and the second one's turning into its side, as with two ingredients. Then come the ingredients of belt b: the first one's product belt turns east into the head of belt b, and the last one drops its product on belt b as it runs south past it. The final column stands beside that last block. Belt b runs south, so an inserter sees only what was dropped north of it: the final column is moved down just far enough for its first long-handed inserter to see its machine's share of the drops and its last one to see all of them. Belts cannot cross, which is why the order is fixed.

Two blocks are never stacked with a belt of one right under a belt of the other (the belt between two columns can run north up to the first row of a block, and would feed the belt above): there is an empty row between them then.

The long-handed inserter is unlocked by the same research as the assembling machine. The mod does not check that you have it. It uses the speed of the game's long-handed inserter (the plain inserter's if the game has none), and the blueprint places long-handed inserters whatever the research.

| Item | Ingredients | Belts of raw items |
|---|---|---|
| Inserter | 1 electronic circuit, 1 iron gear wheel, 1 iron plate | copper ore and coal; 3 x iron ore and coal |
| Long-handed inserter | 1 iron gear wheel, 1 iron plate, 1 inserter | 5 x iron ore and coal; copper ore and coal |
| Fast inserter | 2 electronic circuit, 2 iron plate, 1 inserter | 2 x copper ore and coal; 5 x iron ore and coal |
| Assembling machine 1 | 3 electronic circuit, 5 iron gear wheel, 9 iron plate | copper ore and coal; 3 x iron ore and coal |
| Electric mining drill | 3 electronic circuit, 5 iron gear wheel, 10 iron plate | copper ore and coal; 3 x iron ore and coal |
| Burner mining drill | 3 iron gear wheel, 1 stone furnace, 3 iron plate | 2 x iron ore and coal; stone on both lanes |
| Radar | 5 electronic circuit, 5 iron gear wheel, 10 iron plate | copper ore and coal; 3 x iron ore and coal |
| Rocket launcher | 5 iron plate, 5 iron gear wheel, 5 electronic circuit | 3 x iron ore and coal; copper ore and coal |
| Gun turret | 10 iron gear wheel, 10 copper plate, 20 iron plate | 2 x iron ore and coal; copper ore and coal |
| Submachine gun | 10 iron gear wheel, 5 copper plate, 10 iron plate | 2 x iron ore and coal; copper ore and coal |
| Steam engine | 8 iron gear wheel, 5 pipe, 10 iron plate | 3 x iron ore and coal |
| Steam turbine | 50 iron gear wheel, 50 copper plate, 20 pipe | 2 x iron ore and coal; copper ore and coal |
| Lab | 10 electronic circuit, 10 iron gear wheel, 4 transport belt | copper ore and coal; 4 x iron ore and coal |
| Splitter | 5 electronic circuit, 5 iron plate, 4 transport belt | copper ore and coal; 4 x iron ore and coal |
| Fast splitter | 1 splitter, 10 iron gear wheel, 10 electronic circuit | 6 x iron ore and coal; 2 x copper ore and coal |
| Small lamp | 1 electronic circuit, 3 copper cable, 1 iron plate | 2 x copper ore and coal; 2 x iron ore and coal |
| Power switch | 5 iron plate, 5 copper cable, 2 electronic circuit | 2 x iron ore and coal; 2 x copper ore and coal |
| Programmable speaker | 3 iron plate, 4 iron stick, 5 copper cable, 4 electronic circuit | 3 x iron ore and coal; 2 x copper ore and coal |
| Shotgun | 15 iron plate, 5 iron gear wheel, 10 copper plate, 5 wood | copper ore and coal; wood on both lanes; 2 x iron ore and coal |

Heavy recipes run slowly: with two inserters per machine, an assembling machine 1 making assembling machines (17 items a craft) manages about 6 a minute, so 30 a minute takes 5 machines. The most a blueprint can make is shown under the rate field; the inserter, for instance, tops out at 150 a minute, the circuit block's limit.

### How the columns are found

The table only says which items you can ask for. The steps come from the game's recipes: the mod looks up the recipe that makes the item, then the recipes for the ingredients that are themselves made, and so on until the ingredients are raw (no recipe it can build makes them, like ores and stone). The machine of each step comes from the recipe's category, set in `scripts/config.lua` (smelting: stone furnace burning coal; crafting: assembling machine 1). A request is refused, with a message, when:

- no recipe the mod can build makes the item, or more than one does (it cannot choose between them yet);
- a step has more than four ingredients that are themselves made (two belts have four lanes, one for each);
- a step has made ingredients and more than four ingredients in all, or more than one raw item (a belt of raw items fills both lanes, so it takes a lane of its own and only one is laid out), or has one made ingredient that itself comes from two or more inputs (a column on top of a block with several inputs is not laid out yet);
- a step that is fed by other steps needs fuel. The raw items and the fuel ride on the belts of the steps that are fed raw items;
- a recipe has a fluid among its ingredients, or makes more than one product.

### Lanes and inserters

Each belt of raw items has two lanes, and the message says which item goes where (the first belt of the message is the one next to the blueprint): an ingredient and the fuel get a lane each (furnaces), an ingredient with no fuel gets both lanes, and a recipe with two ingredients and no fuel gets one lane each. A step fed raw items that needs more items than two lanes hold (two ingredients and a fuel, or three ingredients) is refused. An inserter drops items on the far lane of a belt, so a plain output belt carries the product on one lane only. That is the case for every belt between two columns, and the next column picks the product up from it. The output belt of the last column can wind and fill both lanes: a 3 x 3 machine with two output inserters gets a winding output belt (see below).

Each side of a machine gets as many inserters as the machine needs, up to one fewer than it is wide: one beside a 2 x 2 furnace, two beside a 3 x 3 assembling machine (output side: at most 2, whatever the size). That keeps one tile beside every machine free for a pole, so the machines sit side by side with no gaps. A machine that would need more inserters than that simply runs slower, and the blueprint is sized for it: an assembling machine 1 making gear wheels would eat 120 plates per minute and make 60 gears, but two basic inserters move about 100 plates, so each machine makes about 50 gears per minute. The message shows the real total. A column with a single machine that is used for only part of its speed gets only the inserters that share needs: asking for 1 copper cable per minute builds an assembling machine with one input and one output inserter (and no winding belt), not two output inserters. With two or more machines the first ones run flat out and keep every inserter. The inserter's speed comes from the game data.

### The winding output belt

When a 3 x 3 machine in the last column needs two output inserters, the output belt is two tiles from the machine side and winds in and out. Its path, going down, is `DDLDRDDLDR...` (U/D/L/R = up/down/left/right): the first inserter drops onto the tile after the `L`, and the second inserter drops onto a short side belt (`R`) that side-loads the inner lane of the main belt, which the first inserter cannot reach. Both lanes end up carrying the product. It uses one more column than a plain belt and six belt tiles per machine, plus one empty belt tile above the first one: without a belt behind the first outer tile Factorio bends it into a curve and the first inserter's lane does not work, so that tile runs south, carries nothing, and keeps the outer belt straight. Machines with one output inserter keep the plain belt, and so does every column that feeds another one.

## Limits

- **A lane carries 450 items per minute.** The product travels on one lane (plain belt) or two (winding belt, two output inserters), so one blueprint makes at most 450 or 900 per minute, depending on what the machines can move, and the ingredients get one lane each, or both lanes (900 per minute) when one ingredient has the belt to itself. A stone furnace makes 18.75 plates or bricks per minute, so a plate blueprint has at most 24 furnaces. A higher rate is refused with a message that names the most one blueprint can make. Splitting a bigger request into several blueprints is not supported.
- **Every column has its own limit.** Each column must make what the next one needs for the rate asked (asking for 1 gear wheel per minute builds 1 furnace and 1 assembling machine, since 2 plates are all it takes), and the belt between two columns is a plain belt that carries one item on one lane, so the limit of every column counts and the lowest one wins. Gear wheels: each assembling machine eats about 100.8 plates per minute (two basic inserters move that much, see above), so one lane of plates carries about 4.5 machines' worth. The limit follows the belts, not whole machines: a lane that carries 4.5 machines' worth feeds 5 machines, and the 5th simply runs part of the time. One blueprint makes at most 225 gears per minute (24 furnaces and 5 assemblers; the message names the exact number). Asking for 100 gears per minute builds 11 furnaces and 2 assemblers. Before columns were chained, a belt of plates on both lanes allowed twice that.
- **Electronic circuits: at most 150 per minute.** A circuit takes three cables, and the cables ride one lane (450 a minute). Two input inserters move 100.8 items a minute, and a circuit eats four, so a circuit assembler makes 25.2 per minute (6 assemblers for 150).
- **Recipes that eat a lot hit the limit sooner.** A brick takes two stone, so each furnace eats 37.5 stone per minute and the stone lane fills first: at most 12 furnaces and 225 bricks per minute. With two output inserters the winding belt is limited per lane: a machine's first inserter takes all it can, so the machines are capped at the number whose first inserters fit in one lane (450 / 50.4 = 8). That rule is a conservative assumption, not yet checked in game.
- **The rate is rounded up to whole machines.** Asking for 100 plates per minute builds 6 furnaces, which make 112.5 per minute. The message shows both numbers.
- **The winding belt needs a 3 x 3 machine, in the last column.** A 2 x 2 machine has room for one output inserter only, and a column that feeds another one keeps a plain belt.
- **Machines run on electricity or burn fuel.** The mod reads which from the machine in the game, so a machine from another mod works if it fits. The fuel the mod puts on the input belt is still set in `scripts/config.lua`; the mod checks that the machine can burn it (and that an electric machine has none set), and refuses with a message if not. A machine that runs on heat or a fluid is refused.
- **Machines are 2 x 2 or 3 x 3.** Any other size, or a machine that is not square, is refused.
- **You supply the inputs.** The blueprint contains no mining, no ore sources and no coal supply, only the machines and belts themselves. Two steps that need the same ore (a pipe and a gear for an offshore pump) each take a belt of their own.
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
