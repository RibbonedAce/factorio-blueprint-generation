# Blueprint Generation

A Factorio 2.1 mod that builds blueprints for you. Pick an item and how many you want per minute, and the mod puts a ready-to-place blueprint on your cursor. The blueprint carries raw materials from a belt into machines, through every intermediate product on the way, and the finished product onto an output belt: ores in, final product out.

Status: early development.

## Using it

1. Click the "Generate blueprint" button in the shortcut bar.
2. Choose the item to produce (iron plate is already selected, if you can build it) and enter a rate in items per minute. The picker only offers the items whose recipe you have unlocked. Nothing else is looked at: the game never unlocks a recipe before those of its ingredients or before the crafting machine it needs, and the buildings of the blueprint (the long-handed inserter, transport belt, inserter and small electric pole) will be checked by a later feature. Research something new and the list grows the next time you open the window.
3. Click Generate. The blueprint appears on your cursor. It is temporary, like a blueprint taken from the library: it takes no inventory space, and it disappears if you put it away without placing it (generate it again if that happens). Place it, put the raw items on the input belts and connect the poles to your power network. The message says how much the blueprint makes a minute and how much of each raw item (and of the fuel) it uses a minute, for example `Ready: 75 Iron plate/min`, then `Raw/min: 75 Iron ore, 5.4 Coal`. If you have researched the splitter and the underground belt, it also names the belts to bring in, from the top of the blueprint down, for example `Belts in, top to bottom: Iron ore, Coal` (see "One belt of each material").

## What can be generated

The tables list the belts of raw items of the original design, a belt for every chain. With the splitter and the underground belt researched, a blueprint brings in one belt for each material instead (see "One belt of each material" below); the machines are the same.

| Item | Made in | Inputs on the input belt |
|---|---|---|
| Iron plate | Stone furnaces | Iron ore on one lane, coal on the other |
| Copper plate | Stone furnaces | Copper ore on one lane, coal on the other |
| Stone brick | Stone furnaces | Stone on one lane, coal on the other |
| Iron gear wheel | Stone furnaces (plates), then assembling machines 1 (gears) | Iron ore on one lane, coal on the other. The assemblers are electric and take the plates straight from the furnaces |
| Copper cable | Stone furnaces (plates), then assembling machines 1 (cables) | Copper ore on one lane, coal on the other. One plate makes two cables, so each assembler has two output inserters and the cable belt winds; at most 900 per minute (24 furnaces, 9 assemblers), 780 with fast inserters (see "Fast inserters") |
| Wooden chest | Assembling machines 1 | Wood on both lanes |
| Iron chest | Stone furnaces (plates), then assembling machines 1 (chests) | Iron ore on one lane, coal on the other |
| Pipe | Stone furnaces (plates), then assembling machines 1 (pipes) | Iron ore on one lane, coal on the other |
| Stone furnace | Assembling machines 1 | Stone on both lanes |
| Firearm magazine | Stone furnaces (plates), then assembling machines 1 (magazines) | Iron ore on one lane, coal on the other |
| Light armor | Stone furnaces (plates), then assembling machines 1 (armor) | Iron ore on one lane, coal on the other |
| Electronic circuit | Stone furnaces (iron plates, copper plates), assembling machines 1 (copper cable), then assembling machines 1 (circuits) | Two belts, from the top down: copper ore on one lane and coal on the other, iron ore on one lane and coal on the other. At most 150 per minute |
| Transport belt | Stone furnaces (plates), assembling machines 1 (gears), then assembling machines 1 (belts) | Two belts, each with iron ore on one lane and coal on the other |
| Burner inserter | Stone furnaces (plates), assembling machines 1 (gears), then assembling machines 1 (inserters) | Two belts, each with iron ore on one lane and coal on the other |
| Pipe to ground | Stone furnaces (plates), assembling machines 1 (pipes), then assembling machines 1 (pipes to ground) | Two belts, each with iron ore on one lane and coal on the other |
| Boiler | Assembling machines 1 (stone furnaces), stone furnaces (plates), assembling machines 1 (pipes), then assembling machines 1 (boilers) | Two belts, from the top down: iron ore on one lane and coal on the other, then stone on both lanes |
| Offshore pump | Stone furnaces (plates), assembling machines 1 (pipes), stone furnaces (plates), assembling machines 1 (gears), then assembling machines 1 (pumps) | Two belts, each with iron ore on one lane and coal on the other |
| Automation science pack | Stone furnaces (copper plates), stone furnaces (iron plates), assembling machines 1 (gears), then assembling machines 1 (science packs) | Two belts, from the top down: iron ore and coal, then copper ore and coal |
| Logistic science pack | Stone furnaces (iron plates), stone furnaces (copper plates), assembling machines 1 (copper cable), assembling machines 1 (circuits), stone furnaces (iron plates), assembling machines 1 (gears), stone furnaces (iron plates), assembling machines 1 (inserters), stone furnaces (iron plates), stone furnaces (iron plates), assembling machines 1 (gears), assembling machines 1 (transport belts), then assembling machines 1 (science packs) | Six belts, one for each chain of furnaces: iron ore and coal on five, copper ore and coal on one. With one belt of each material, three. At most 150 per minute (the circuits, as for the electronic circuit) |
| Underground belt | Stone furnaces (plates), stone furnaces (plates), stone furnaces (plates), assembling machines 1 (gears), assembling machines 1 (transport belts), then assembling machines 1 (underground belts) | Three belts, each with iron ore on one lane and coal on the other |
| Repair pack | Stone furnaces (iron plates), stone furnaces (copper plates), assembling machines 1 (copper cable), assembling machines 1 (circuits), stone furnaces (iron plates), assembling machines 1 (gears), then assembling machines 1 (repair packs) | Three belts, from the top down: iron ore and coal, copper ore and coal, iron ore and coal |
| Shotgun shell | Stone furnaces (copper plates), stone furnaces (iron plates), then assembling machines 1 (shotgun shells) | Two belts, from the top down: iron ore and coal, then copper ore and coal |
| Small electric pole | Stone furnaces (copper plates), assembling machines 1 (cables), then assembling machines 1 (poles) | Two belts, from the top down: wood on both lanes, then copper ore and coal; at most 450 per minute (the lane of cables) |
| Steel plate | Stone furnaces (iron plates), then stone furnaces (steel plates) | Only with the splitter and the underground belt researched (see "Steel"). Two belts, from the top down: coal, then iron ore, each on both lanes; at most 90 per minute (the lane of plates: 5 for each) |
| Steel chest | Stone furnaces (iron plates), stone furnaces (steel plates), then assembling machines 1 (chests) | Only with the splitter and the underground belt researched (see "Steel"). Two belts, from the top down: coal, then iron ore, each on both lanes; at most 11 per minute (the lane of plates) |
| Heavy armor | Stone furnaces (copper plates), stone furnaces (iron plates), stone furnaces (steel plates), then assembling machines 1 (armor) | Only with the splitter and the underground belt researched (see "Steel"). Three belts, from the top down: coal, iron ore, copper ore, each on both lanes; at most 1 per minute (the lane of plates: 50 steel plates, 250 iron plates, an armor) |

The assembling machines come with their recipe already set; a furnace needs none. A blueprint is a row of columns of machines, one column per step from the raw items to the product, from left to right. A column is an input belt, inserters, the machines, output inserters and an output belt, and the output belt of one column is the input belt of the next. The belt between two columns runs toward the machines that still need its items, so none of the plates pass the second column by: up the page when the first column is the taller one, down when the second is. All the columns start on the same row. Iron plate, copper plate and stone brick take one column (furnaces fed with ore and coal). Iron gear wheel takes two: furnaces on the left make plates from iron ore, and assembling machines on the right make gear wheels from those plates. Small electric poles are placed and wired for you, and one wire joins each column to the next, so the whole blueprint needs one connection to your power network. The belts, inserters and poles are the first-tier ones (transport belt, inserter, small electric pole); there is no choice of tier yet.

### Recipes with two made ingredients

An electronic circuit is an iron plate and three copper cables, and the cables are made from copper plates. The mod builds a chain of columns for each ingredient (the row of columns above, with its own belt of raw items) and puts the machines that eat them in a column of their own. So every step of the recipe is a column, and the columns stand side by side from left to right: the ones that make the ingredients first, then the one that eats them. A step can have steps of its own, as deep as the recipe goes (a transport belt is an iron plate and a gear, and a gear is made from iron plates).

**The recipe fixes the width of the blueprint, and the rate only makes it taller.** More items a minute means more machines in a column, never another column. The circuit is 26 tiles wide, the inserter 52, the fast inserter 91 and the fast splitter 110, whatever the rate; a low rate gives a flat strip, and you can turn a blueprint when you place it.

The belts of raw items come in from the west edge at the top, one row each, and the belt of the chain furthest east has the top row, so no belt crosses another. Each chain starts right under its own belt, so the columns do not start on one row. The product of a column leaves at its bottom, runs east along a row of its own and goes up into the input belt of the column that eats it, which runs north. An inserter drops on the far lane and a belt that feeds the side of another puts everything on the near lane, so the two ingredients ride different lanes, and the inserters of the new column take both: the second product joins the input belt from the west (the west lane), and the first goes through a small lane gadget, a belt that comes up into the side of its own row from the south (the south lane, which is the east lane of the input belt after the turn). The lane gadget is checked by the specs but has not been seen running in game yet. A column that eats what others make starts one row lower than the belts of raw items that pass over it, so its input belt does not end pointing into one of them. The poles of each column are wired to the nearest column, so the whole blueprint is one network.

### A raw item next to a made one

A small electric pole is a wood and two copper cables. The cables get a chain, as above. The wood has no recipe, so it needs no machines: its column is only a belt, with a spare column beside it for the lane gadget of the product before it. The belt comes in from the west edge on a row of its own like the others, runs down its column and along the bottom to the input belt, where the wood and the cables share the two lanes. The pole machines take both.

### Recipes with three or four ingredients

A belt has only two lanes, so a machine that eats three or four items takes them from two belts side by side: belt a, next to its inserters, and belt b, one column further west. A plain inserter takes from belt a, and a long-handed inserter, standing in the same column of inserters, reaches over belt a to take from belt b. Each machine gets one plain and one long-handed inserter (a machine has room for two inserters on its input side). Which ingredients go on which belt is decided for speed: a long-handed inserter moves 72 items a minute against 50.4 for a plain one, so the mod tries every split (at most two ingredients on a belt, a raw item only on belt a) and takes the one that lets a machine run fastest. An inserter, for example, wants 60 circuits, 60 gears and 60 plates a minute at full speed: with the circuits alone on belt a and the other two on belt b, an assembler makes 36 a minute; the other splits make 25.

The columns that make the ingredients stand from left to right: first those of belt a, then those of belt b, each in the recipe's order, then the final column, with a column of its own for belt b just west of it. Both belts run north and the products reach them from below, the first product of a belt through the lane gadget when a second one shares the belt. Belt b starts at the first long-handed inserter, so every inserter sees everything that comes up the belt. An arc of a column further west runs deeper than the arcs of the columns east of it, so belts never cross.

The long-handed inserter is unlocked by the same research as the assembling machine. The mod does not check that you have it. It uses the speed of the game's long-handed inserter (the plain inserter's if the game has none).

| Item | Ingredients | Belts of raw items, from the top down |
|---|---|---|
| Inserter | 1 electronic circuit, 1 iron gear wheel, 1 iron plate | 2 x iron ore and coal; copper ore and coal; iron ore and coal |
| Long-handed inserter | 1 iron gear wheel, 1 iron plate, 1 inserter | 2 x iron ore and coal; copper ore and coal; 3 x iron ore and coal |
| Fast inserter | 2 electronic circuit, 2 iron plate, 1 inserter | 2 x iron ore and coal; copper ore and coal; 2 x iron ore and coal; copper ore and coal; iron ore and coal |
| Assembling machine 1 | 3 electronic circuit, 5 iron gear wheel, 9 iron plate | 2 x iron ore and coal; copper ore and coal; iron ore and coal |
| Electric mining drill | 3 electronic circuit, 5 iron gear wheel, 10 iron plate | 2 x iron ore and coal; copper ore and coal; iron ore and coal |
| Burner mining drill | 3 iron gear wheel, 1 stone furnace, 3 iron plate | iron ore and coal; stone on both lanes; iron ore and coal |
| Radar | 5 electronic circuit, 5 iron gear wheel, 10 iron plate | 2 x iron ore and coal; copper ore and coal; iron ore and coal |
| Rocket launcher | 5 iron plate, 5 iron gear wheel, 5 electronic circuit | copper ore and coal; 3 x iron ore and coal |
| Gun turret | 10 iron gear wheel, 10 copper plate, 20 iron plate | iron ore and coal; copper ore and coal; iron ore and coal |
| Submachine gun | 10 iron gear wheel, 5 copper plate, 10 iron plate | iron ore and coal; copper ore and coal; iron ore and coal |
| Steam engine | 8 iron gear wheel, 5 pipe, 10 iron plate | 3 x iron ore and coal |
| Steam turbine | 50 iron gear wheel, 50 copper plate, 20 pipe | iron ore and coal; copper ore and coal; iron ore and coal |
| Lab | 10 electronic circuit, 10 iron gear wheel, 4 transport belt | 3 x iron ore and coal; copper ore and coal; iron ore and coal |
| Splitter | 5 electronic circuit, 5 iron plate, 4 transport belt | 3 x iron ore and coal; copper ore and coal; iron ore and coal |
| Fast splitter | 1 splitter, 10 iron gear wheel, 10 electronic circuit | copper ore and coal; 4 x iron ore and coal; copper ore and coal; 2 x iron ore and coal |
| Small lamp | 1 electronic circuit, 3 copper cable, 1 iron plate | 2 x (copper ore and coal; iron ore and coal) |
| Power switch | 5 iron plate, 5 copper cable, 2 electronic circuit | 2 x (copper ore and coal; iron ore and coal) |
| Programmable speaker | 3 iron plate, 4 iron stick, 5 copper cable, 4 electronic circuit | 2 x (copper ore and coal; iron ore and coal); iron ore and coal |
| Shotgun | 15 iron plate, 5 iron gear wheel, 10 copper plate, 5 wood | 2 x iron ore and coal; wood on both lanes; copper ore and coal |

Heavy recipes run slowly: with two inserters per machine, an assembling machine 1 making assembling machines (17 items a craft) manages about 6 a minute, so 30 a minute takes 5 machines. The most a blueprint can make is shown under the rate field; the inserter, for instance, tops out at 150 a minute, the circuit block's limit.

### One belt of each material

If your force has researched the splitter and the underground belt, a blueprint does not ask for a belt of raw items for every chain. It asks for **one belt for each material**, with the material on both lanes: a belt of iron ore, a belt of copper ore, a belt of coal, a belt of wood, a belt of stone, whatever the recipe needs. The blueprint divides them itself, in a band along its top:

- A furnace takes its ore on one lane and its coal on the other. Where a chain needs both, a *mixer* brings them together: a belt with nothing behind it that is fed from both sides puts the belt from the north on one lane and the one from the south on the other.
- The ore (and the wood or stone) runs along the top on *trunks*, each as full as a lane allows (450 ore a minute on a trunk that also carries coal; a trunk with one item uses both lanes). A *splitter* in front of every chain sends it its share, and the belt comes down to the chain.
- The coal, which every furnace needs, is a *bus*: one belt that comes down at the west edge and a splitter for each trunk. A second belt of the same material comes in when the trunks need more than the two lanes of one belt carry (900 a minute).
- A belt that has to cross another goes under it with an *underground belt*.

This is for every blueprint, a lone chain included: iron plates ask for a belt of iron ore and a belt of coal, where the original design asks for one belt with the ore on one lane and the coal on the other. The message names the belts that come in, from the top down, and each starts at the west edge of the blueprint in the row of its own.

The chains start under the band, which takes room: the first column starts 4 tiles from the west edge plus 4 more for each bus, and each trunk adds about 3 rows at the top. The recipe still fixes the width and the rate the height. Measured over every item at a fifth, a half and the most it can make, the blueprint takes about 38% more area than the original (41% at the most each can make), with at most 8 splitters and 12 underground belts.

The design is used only when your force has unlocked the recipes of **both** the splitter and the underground belt, both exist in the game, and the underground belt spans at least 3 tiles (the basic one spans 5). Otherwise, and when no force is known, the blueprint is built the original way, as described above, and nothing is refused because of it.

### Steel

Steel plate is five iron plates smelted in a furnace, so it is a furnace that eats what other furnaces make and burns coal. Its coal cannot come from a belt of raw items, so the belt of plates that runs from the iron furnaces to the steel furnaces carries it: the iron furnaces' inserters put the plates on one lane of that belt, and the coal rides the other. The coal comes down from the band beside the output inserters of the iron furnaces and turns east into the tile above the head of the belt, which has a stub of belt behind it so that it stays straight and the side-load puts the coal on the lane the plates leave free. The belt of plates runs south, so that its head, where the coal comes in, is at the top. The coal is one more feed for the band, a trunk of its own that carries only coal.

This needs the design that brings in one belt of each material, so steel plate, steel chests and heavy armor are refused, with a message, when the splitter and the underground belt are not researched. A furnace in the middle of a chain can eat only one made ingredient (the plates), because the coal takes the other lane.

**Not seen in game yet.** The specs trace every lane of every blueprint, for every item at every whole rate, but a trace follows the rules assumed below, which only the game can confirm: a splitter keeps the lanes of what goes through it and divides each lane evenly; a belt that is fed from both sides and has nothing behind it puts what comes from each side on its own lane; a belt tile fed from the side by the output of a splitter bends and keeps the lanes; an underground belt keeps the lanes of what goes through it, even with an entrance right after a belt, an exit right before the next entrance, or a hop under the output of a splitter. The coal of the steel furnaces side-loading the near lane of a belt that already carries plates on its far lane, from a tile with a stub behind it, is assumed the same way, and so is the steel furnaces' inserters taking both items from that belt. The lane gadget of the columns (described above) has not been seen running in game either.

### How the columns are found

The table only says which items you can ask for. The steps come from the game's recipes: the mod looks up the recipe that makes the item, then the recipes for the ingredients that are themselves made, and so on until the ingredients are raw (no recipe it can build makes them, like ores and stone). The machine of each step comes from the recipe's category, set in `scripts/config.lua` (smelting: stone furnace burning coal; crafting: assembling machine 1). A request is refused, with a message, when:

- no recipe the mod can build makes the item, or more than one does (it cannot choose between them yet);
- a step has more than four ingredients that are themselves made (two belts have four lanes, one for each);
- a step has made ingredients and more than four ingredients in all, or more than one raw item (a belt of raw items fills both lanes, so it takes a lane of its own and only one is laid out), or has one made ingredient that itself comes from two or more inputs (a column on top of a block with several inputs is not laid out yet);
- a step that is fed by other steps needs fuel. The raw items and the fuel ride on the belts of the steps that are fed raw items, with one exception: a furnace that eats the one product of the step before it (steel plate from iron plates) takes its fuel on the free lane of that belt, when the splitter and the underground belt are researched (see "Steel");
- a recipe has a fluid among its ingredients, or makes more than one product.

### Lanes and inserters

(This describes the original design, with a belt of raw items for every chain. In the design that brings in one belt of each material, the lanes are made inside the blueprint: see "One belt of each material".) Each belt of raw items has two lanes (the belts come in from the west edge, one row each at the top, in the order of the tables above, the first one on the top row): an ingredient and the fuel get a lane each (furnaces), an ingredient with no fuel gets both lanes, and a recipe with two ingredients and no fuel gets one lane each. A step fed raw items that needs more items than two lanes hold (two ingredients and a fuel, or three ingredients) is refused. An inserter drops items on the far lane of a belt, so a plain output belt carries the product on one lane only. That is the case for every belt between two columns, and the next column picks the product up from it. The output belt of the last column can wind and fill both lanes: a 3 x 3 machine with two output inserters gets a winding output belt (see below).

(With the fast inserter researched a side may use fast ones: see "Fast inserters".) Each side of a machine gets as many inserters as the machine needs, up to one fewer than it is wide: one beside a 2 x 2 furnace, two beside a 3 x 3 assembling machine (output side: at most 2, whatever the size). That keeps one tile beside every machine free for a pole, so the machines sit side by side with no gaps. A machine that would need more inserters than that simply runs slower, and the blueprint is sized for it: an assembling machine 1 making gear wheels would eat 120 plates per minute and make 60 gears, but two basic inserters move about 100 plates, so each machine makes about 50 gears per minute. The message shows the real total. A column with a single machine that is used for only part of its speed gets only the inserters that share needs: asking for 1 copper cable per minute builds an assembling machine with one input and one output inserter (and no winding belt), not two output inserters. With two or more machines the first ones run flat out and keep every inserter. The inserter's speed comes from the game data.

### The winding output belt

When a 3 x 3 machine in the last column needs two output inserters, the output belt is two tiles from the machine side and winds between two columns, the inner one beside the inserters and the outer one beside it. The belt has one seam for every two output inserters in adjacent rows (a machine's two inserters, with plain ones), in two rows: at a seam the belt comes down in the inner column and curves east, where the first inserter drops on the curve (one lane); it runs on in the outer column, which a short stub from the second inserter side-loads (the other lane). The next seam does the same the other way round: the stub of the first inserter side-loads the belt coming down in the outer column, and in the second row the belt turns west into the inner column, where the second inserter drops on the curve. So each machine fills both lanes. The belt starts in the inner column one tile above the first curve: without a belt behind it Factorio would bend the first stub into a curve and its lane would not work. Machines with one output inserter keep the plain belt (unless it is a fast one, see "Fast inserters"), and so does every column that feeds another one.

### Machines in pairs

The machines of a column go in twos: the inserters of the first, third, ... machine stand in its top rows, those of the second, fourth, ... machine in its bottom rows, so that the second machine of a pair and the first of the next have theirs together. A machine with no partner, the last of an odd number, is arranged like the first (in a column of five, machines 1 and 5 look alike). The long-handed inserters are part of the pattern: a machine with one fast and one long-handed input inserter has them as fast, long in its top rows and as long, fast in its bottom rows, so the rows read fast, long, long, fast for a pair. It is the same on every belt, the belt between two columns included, so the inserters of two columns that share a belt agree. The winding belt is drawn around the output inserters standing together. The poles follow the inserters: the machines go from the top down, each with a pole in the free tile under its inserters (above them for a machine whose inserters are in its bottom rows) unless a pole above it reaches them, which a small pole does two rows each way.

The belt between two columns runs south unless the first column is the longer one for the work it does, as before, and now also only when its last drop is at or below the next column's last pickup: items flow only the way the belt runs, so on a northbound belt a pickup below the last drop would never see a plate. In that rare case (one furnace and one assembler with two input inserters, for example) the belt runs south, whatever the load rule says.

### Lights

Once your force has researched the small lamp, every blueprint gets lamps. They stand on free tiles inside the supply area of a pole, so each one is powered by the poles that power the machines, with no wire of its own. Two rules place them:

- **Hard: no two lamps are closer than 10 tiles.**
- **Soft: every tile a pole powers has a lamp within 10 tiles.**

The tiles a pole powers are taken from the top row down, left to right. Where a tile has no lamp within 10 tiles, one is put on the closest free tile that is at least 10 tiles from every lamp so far, which is the tile itself when it is free. So the hard rule holds for every blueprint, and the soft rule fails only where no free tile is left near a powered tile (a few tiles in a thousand between crowded machines, in the sweep of every recipe at every rate). A tile with something on it is not free, and neither is the tile a belt runs on to, so that you can go on with the belts that leave the blueprint. Without the small lamp researched, or in a game that does not have it, blueprints have no lamps.

### Fast inserters

Once your force has researched the fast inserter, a machine side that one plain inserter cannot serve gets fast ones. A side goes up a ladder as the machine's flow grows: one plain inserter (50.4 items a minute), one fast inserter (144), two fast inserters (288), never two plain ones, since one fast inserter moves nearly three. Each side climbs on its own, so a machine can eat through two fast inserters and empty through one plain one. The long-handed inserters of the second input belt stay as they are.

A side still takes at most one fewer inserter than the machine is wide, two on a 3x3 machine, which keeps a tile beside it free for a pole; a machine that needs more than two fast inserters move runs slower. The planner counts what the best inserter moves when it decides which ingredients ride belt a (the fast inserter, 144 a minute) and which ride belt b (the long-handed one, 72): the inserter's assembler used to take its circuits alone on belt a (50.4 a minute) and the gears and plates on belt b; with a fast inserter it takes circuits and gears on belt a (120 of the 144) and the plates on belt b, and runs at full speed. A machine runs at full speed more often, so fewer machines are built.

A machine that makes more than one plain inserter moves used to get two output inserters and the winding belt, so the product rode both lanes (900 a minute). One fast inserter moves all of it, so the last column winds its belt with one fast output inserter on each 3x3 machine. The first machine's inserter stands alone in its top rows and drops on a curve of the belt (the outer lane); after it, the second machine's inserter and the third's stand side by side, one dropping on a stub that side-loads the belt (the inner lane) and the other on the curve where the belt turns west (the outer lane); the belt hops back to the outer column between the seams, so every machine takes the other lane than the one before: outer, inner, outer, inner and so on. The product keeps both lanes with half the inserters. A lane may carry one machine more than the other, so the belt counts for one machine's worth less than two lanes: copper cable tops out at 780 a minute with fast inserters, and at 900 without them.

Without the fast inserter researched (or when the game does not have it), every blueprint is built with plain inserters exactly as before.

## Limits

- **A lane carries 450 items per minute.** The product travels on one lane (plain belt) or two (winding belt, two output inserters), so one blueprint makes at most 450 or 900 per minute, depending on what the machines can move, and the ingredients get one lane each, or both lanes (900 per minute) when one ingredient has the belt to itself. A stone furnace makes 18.75 plates or bricks per minute, so a plate blueprint has at most 24 furnaces. A higher rate is refused with a message that names the most one blueprint can make. Splitting a bigger request into several blueprints is not supported.
- **Every column has its own limit.** Each column must make what the next one needs for the rate asked (asking for 1 gear wheel per minute builds 1 furnace and 1 assembling machine, since 2 plates are all it takes), and the belt between two columns is a plain belt that carries one item on one lane, so the limit of every column counts and the lowest one wins. Gear wheels: each assembling machine eats about 100.8 plates per minute (two basic inserters move that much, see above), so one lane of plates carries about 4.5 machines' worth. The limit follows the belts, not whole machines: a lane that carries 4.5 machines' worth feeds 5 machines, and the 5th simply runs part of the time. One blueprint makes at most 225 gears per minute (24 furnaces and 5 assemblers; the message names the exact number). Asking for 100 gears per minute builds 11 furnaces and 2 assemblers. Before columns were chained, a belt of plates on both lanes allowed twice that.
- **Electronic circuits: at most 150 per minute.** A circuit takes three cables, and the cables ride one lane (450 a minute). Two input inserters move 100.8 items a minute, and a circuit eats four, so a circuit assembler makes 25.2 per minute (6 assemblers for 150).
- **Recipes that eat a lot hit the limit sooner.** A brick takes two stone, so each furnace eats 37.5 stone per minute and the stone lane fills first: at most 12 furnaces and 225 bricks per minute. With two output inserters the winding belt is limited per lane: a machine's first inserter takes all it can, so the machines are capped at the number whose first inserters fit in one lane (450 / 50.4 = 8). That rule is a conservative assumption, not yet checked in game.
- **The rate is rounded up to whole machines.** Asking for 100 plates per minute builds 6 furnaces, which make 112.5 per minute. The message shows the 112.5, what the machines make, and the raw items it needs for that.
- **The winding belt needs a 3 x 3 machine, in the last column.** A 2 x 2 machine has room for one output inserter only, and a column that feeds another one keeps a plain belt.
- **Machines run on electricity or burn fuel.** The mod reads which from the machine in the game, so a machine from another mod works if it fits. The fuel the mod puts on the input belt is still set in `scripts/config.lua`; the mod checks that the machine can burn it (and that an electric machine has none set), and refuses with a message if not. A machine that runs on heat or a fluid is refused.
- **Machines are 2 x 2 or 3 x 3.** Any other size, or a machine that is not square, is refused.
- **You supply the inputs.** The blueprint contains no mining, no ore sources and no coal supply, only the machines and belts themselves. Two steps that need the same ore (a pipe and a gear for an offshore pump) each take a belt of their own (in the design that brings in one belt of each material they share the belt of that ore, up to two lanes of it).
- **You supply the power.** The poles are connected to each other, not to your network.
- **Only the items you have unlocked.** The picker leaves out an item when its own recipe is not unlocked yet for your force, and a request for one anyway (it cannot be made from the window, but the generator checks) is refused with the name of the recipe that is missing. A recipe the game does not have at all is not held against you.
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

Where things are: `control.lua` only registers the events; `scripts/gui.lua` is the window; `scripts/generator.lua` is the one place that reads the game's recipes and machines and connects them to the planner and the layout; `scripts/layout.lua` builds the columns of one chain and `scripts/rows.lua` puts the columns of a whole recipe side by side; `scripts/messages.lua` holds all the wording (with the texts themselves in `locale/en/blueprint-generation.cfg`), so a change to what the player reads can be reviewed apart from a change to what the mod builds.
