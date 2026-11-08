# Three and four ingredient recipes: a second input belt reached by long-handed inserters (first use: inserter)

Status: IMPLEMENTED 2026-11-07 in one local commit, not yet run in game, nothing pushed. The owner confirmed the five decisions below the same day. "What changed from the plan" at the end lists what building it taught.

## Requirements (owner, 2026-11-07)

- Recipes with 3 or 4 different ingredients, starting with the inserter (1 electronic circuit, 1 iron gear wheel, 1 iron plate; 0.5 s). Still no undergrounds or splitters, so the extra items travel on "the next belt over", and long-handed inserters reach over the first belt to take from it.
- "Do not start coding yet": the plan comes first, and the owner reviews it.

## Decisions (owner, 2026-11-07)

1. The planner picks the best split of the ingredients between the two belts.
2. No third input slot per machine. A 3x3 machine keeps two input slots (one fewer than it is tall, one tile stays free for a pole), now shared between regular and long-handed inserters.
3. The final column F stands beside the bottom block, as in the two-block layout today.
4. The order of the recipes is free: inserter, then the batch of 3-ingredient products, then the nested ones, then the 4-ingredient ones.
5. Refuse nothing new. No check that the long-handed inserter exists or is unlocked, none for `ingredient_count`, none for research: the owner plans a separate "is it unlocked" feature for later. The player message does not change (it does not mention long-handed inserters).
   - Consequence found while planning: `all_entities_exist` in `scripts/generator.lua` loops over EVERY name in `shared_names()`, and a missing entity there already refuses everything with `error-missing-prototype`. So the long-handed inserter's name must be kept OUT of that loop (it is needed in `names` to name the entities, not to be checked), and its speed is read with a fallback to the basic inserter's speed, so that a game without it cannot crash the mod or refuse the one-belt recipes. The unlock feature owns that case later.

## Facts (Verified in the base 2.1.24 data files of the owner's install, 2026-11-07)

- `long-handed-inserter` (`entity/entities.lua`): `pickup_position = {0, -2}`, `insert_position = {0, 2.2}`, `rotation_speed = 0.02`, `extension_speed = 0.05`. The basic `inserter`: `rotation_speed = 0.014`. So a long-handed inserter picks up 2 tiles away and drops into the second tile column of a machine that stands next to it (a 3x3 or a 2x2), and moves 72 items a minute by our formula (`rotation_speed * 3600`) against 50.4. The real long-handed figure is about 69 a minute (chest to chest), 4% less than the model; the model ignores this for the basic inserter too.
- The recipe `long-handed-inserter` is unlocked by the same technology as `assembling-machine-1` (the one with the automation-1 icon), so anyone who can build our assemblers can build it.
- `assembling-machine-1`: `crafting_categories = {"crafting", "advanced-crafting"}`, speed 0.5, and NO `ingredient_count`, so it has no cap on item ingredients in 2.1. (The runtime property `LuaEntityPrototype.ingredient_count` still exists, optional; decision 5 says we do not look at it.)
- Recipes (`recipe.lua`): inserter = 1 electronic circuit + 1 iron gear wheel + 1 iron plate, 0.5 s.
- Runtime API names, if ever needed: `LuaEntityPrototype.inserter_pickup_position`, `inserter_drop_position`, `get_inserter_rotation_speed()` (local type library, Verified).

## Scope: what becomes buildable (computed from `recipe.lua`: solid ingredients only, crafting category, nothing that needs steel, plastic, engines or a furnace fed by plates)

- 3 ingredients (17): inserter, long-handed-inserter, fast-inserter, assembling-machine-1, electric-mining-drill, radar, rocket-launcher, gun-turret, submachine-gun, steam-engine, steam-turbine, burner-mining-drill, lab, splitter, fast-splitter, small-lamp, power-switch.
- 4 ingredients (2): programmable-speaker (all made), shotgun (3 made and raw wood).
- 68 more recipes with 3 or 4 ingredients need steel, plastic, engines or similar: a separate problem (only the first step of a branch may burn fuel).

## Belt rules the design rests on

1 to 4 are in `recipe-tree-plan.md` (far-lane drops, side-loading onto the near lane, a belt with one side feeder and nothing behind it is a curve and keeps each lane). New in this plan:

5. A lane keeps its identity through curves, so WHICH WAY a supplier's belt runs decides its lane at a curve join. Checked 2026-11-07 on a hand-built mock with `spec/support/belt_tracer.lua` (a throwaway script, not kept): a supplier whose belt runs NORTH and turns east into the head of a south-running belt B ends on B's west lane, and an inserter further down that drops on B fills the east lane, so the lanes stay apart. The same supplier with its belt running SOUTH ends on the east lane and the tracer reports "the left lane carries x-item and y-item". So the direction is part of the design, not a detail.

## The design

Two input belts: A, next to F's inserters (regular inserters take from it), and B, one column further west (long-handed inserters take from it, over A). Two lanes each: at most 4 items, which is what "3-4 item recipes" needs.

Belts cannot cross, so the vertical order of the blocks decides which belt a block can feed: B (west of A) can be fed from the west anywhere, but an A-feeder would have to cross B, so every A-feeder sits ABOVE the row where B starts. Order from the top: the A group, then the B group.

```
              I-3  I-2  I-1   I   I+1
  T1           .    M    }    v    .     T1 (A's head): its inserters drop on A (east lane); M = machines
  T2 (top)     .    M    >    v    .     T2: its belt (^) turns east into the SIDE of A: west lane (as today)
  T2           .    }    ^    v    .
  Y  (top)     .    >    v    v    .     Y: its belt (^) turns east into the HEAD of B, a curve: B's west lane
  Y            }    ^    v    v    .
  X  (top)     .    }    v    v    }     X: its inserters drop on B (east lane); F: } takes from A
  X            .    .    v    v    L     and a long-handed L takes from B, over A
```

- Which items form the A group and the B group is the planner's choice (see below). A holds 1 or 2 items, B holds 1 or 2. With one item on A there is no T2; with one on B there is no Y (B then starts at the top of X, a plain belt start).
- Within a group the taller block goes first (T1 above T2; Y above X). So X, the bottom block, is the shorter of the B pair.
- B is drawn by the composite, running SOUTH from its head (Y's top row, or X's top row) down to the last long-handed inserter of F. T2's belt (north) and B's head (south) meet end to end but point away from each other, so they do not feed each other.
- Block columns: T1's product belt is A (column I, from row 0, as the input belt is today); T2's at I-1; Y's at I-2; X's is B at I-1. The blocks that are narrower than their target column move east; a wider one moves west (past column 0), as the lower block already does. The trail rule (`add_trails`) already copes.
- F stands beside X: its first row is X's first row, pushed down just far enough that its last long-handed inserter is at or below X's last output inserter (B flows south, so an item dropped below the last picker would never be picked). If F is taller than X, B simply goes on below X. Needs `Block` to say its first and last output row.
- Slot order in each machine: regular inserters in the upper slots, long-handed ones in the lower slots (B flows south, so the lower pickers see more of what X dropped). A's belt ends at the last regular inserter, B's at the last long one.
- A raw ingredient (wood for the shotgun) can only be T2, the side-loader: a raw belt fills both lanes, so as a head or a curve join it would take a whole belt.
- A stage with one supplier whose own stage has 2 or more inputs is still refused (`fork-in-chain`), counting the raw item and now up to 4 inputs.
- Nothing changes for stages with 1 or 2 inputs: all on A, the same blueprints as today (check with a differential run).

## Planner (pure maths, `scripts/planner.lua`)

- `StageContext.lanes` becomes, per ingredient, a belt (A or B) and a lane. Raw-fed stages are unchanged.
- The limits get a second figure, `long_items_per_minute`. A machine has S = `max_input` slots (2 for a 3x3), split into a regular and b long, a + b <= S, with at least one on each belt that carries something.
- For each way to split the ingredients (at most 2 per belt; a raw one on A) and each (a, b): usable fraction = min(1, a * regular / demand on A, b * long / demand on B, the output side). Take the best; ties: fewer items on B, then the recipe's order. The choice depends only on one machine's demands per craft, not on the rate or on block heights, so there is no circularity.
- The inserter recipe, per assembler (60 crafts a minute, 60 of each item): circuit on A, gear and plate on B gives 0.6 (B: 72/120), 36 inserters a minute; circuit and gear on A gives 0.42, 25.2 a minute. At 100 a minute: 3 assemblers against 4.
- A third slot was weighed and dropped (decision 2): 50.4 a minute per machine at 4 rows (pole rows) against 36 at 3 rows is 0.079 against 0.083 rows per item a minute, within 5%.
- Heavy recipes run at about a tenth of the machine's speed: assembling-machine-1 (17 items a craft) manages about 6 crafts a minute per assembler at its best split, so 30 a minute takes 5 machines. This follows from two inserters per machine, not from a bug. The inserter blueprint tops out at 150 a minute (the circuit block's cable lane).
- Trimmed inserter counts for a machine that is only partly used (`stage_rates`) are worked out per belt. `plan` gains `long_inserters` and the per-ingredient belt.

## Code by file

1. `spec/support/blueprint_validator.lua`, `spec/support/belt_tracer.lua`, `spec/support/builders.lua`: a long-handed inserter reaches 2 tiles (the catalog or an option says which names are long); it picks up over a belt and drops 2 tiles into the machine.
2. `scripts/planner.lua`: the above.
3. `scripts/layout.lua`: `Shape.long_inserters`, `Names.long_inserter`; the column places regular then long inserters; poles after the last slot; `Block` gains the first and last output row (and F's last long row); `layout.max_input_inserters` stays `size - 1`, now shared.
4. `scripts/blocks.lua`: `composite_block` takes the groups instead of `upper` and `lower` (this also removes the mutual recursion between `block_of` and `ordered_blocks`): columns, join kinds, B drawn, F's start row, heights, pole groups joined as now.
5. `scripts/chain.lua`, `scripts/types.lua`: up to 4 inputs (`MOST_MADE_INGREDIENTS`, `MOST_INGREDIENTS`), the fork rule; `scripts/generator.lua`: pass the long figure, tell the layout which supplier is on which belt, the long name kept out of the existence check; `scripts/config.lua`: `entities.long_inserter = "long-handed-inserter"` and the products; `locale/en/blueprint-generation.cfg`: the `error-chain-too-complex` text says "more than two" and needs updating.
6. README table rows and these notes.

## Verification

- Specs for every new rule, written to fail first: planner numbers worked out by hand (the table above), column placement, composites of every shape (A1+B1, A2+B1, A1+B2, A2+B2, nested, with a raw item) swept over counts with the validator and the tracer, as for the circuit.
- The real-recipe harness (the 2.1 `recipe.lua` through `generator.generate`, then validator and tracer at every whole rate up to the maximum) for every new product.
- Mutation lists for the new code, the matrix of which tests catch which mutations (the owner's redundancy rule: no group of tests that together catch only one mutation), and the function size count.
- A differential run of all existing products before and after, which must be identical.
- Unverified until the owner tests in game: that the long-handed inserter's `direction` follows the same "side it picks up from" rule; the lanes at the curve join; roughly 36 inserters a minute per assembler; that a belt-end pointing away from another belt end does not interact.

## What changed from the plan (found while building, 2026-11-07)

- The planner chooses the belts in `choose_belts`; ties go to the fewest ingredients on belt b, then to the later ones in the recipe (so the inserter gets the circuit alone on belt a). Trimming a partly used machine reads the machine's own slowed rates (as the old code did), not the full-speed ones: `rates_per_machine(request, belts, partial)`. A raw ingredient may be alone on belt a (the heaviest raw item can make that the best split); then the raw block is the head of belt a and sits in the corner.
- Placing the final column beside the source needs TWO conditions, not one: the last long-handed inserter must be level with the last drop of the source (as planned), and the first one must see at least its machine's share of the drops (`final_first_row`). Found by a gadget block inside a gadget block, whose only output inserter is in its last rows: the first machines of the outer column would have starved. `Block` therefore has `output_rows` (first and last row where its output inserters drop) and `long_rows`.
- The tracer's rule changed: between them, the input inserters of a machine see everything it eats (a plain one sees belt a, a long-handed one belt b). Before, each had to see everything.
- The real-recipe sweep found a leak no hand-built test had: the belt between two columns of the lower block runs north up to its first row, and when the block above has a belt in that column (the cable belt of a circuit block), the plates run into it. Fix: `place_stack` leaves an empty row when a belt in the first row of a block has a belt right above it (`belt_under_belt`). It never fires for the earlier recipes (their blueprints are identical to before).
- `input_belt_rows_above` is gone from the layout: the composite draws the top of belt a itself ("whoever uses a block draws its product belt"). `block_of` is the one recursive function now (no more `ordered_blocks`).
- A raw ingredient: `ChainStage.raw_item` allows exactly one next to up to three made ones.
- The no-refusal decision: the long-handed inserter's name travels in `names.long_inserter` but is not in `all_entities_exist`; its speed falls back to the plain inserter's. Tested.
- Verified before the commit: the 19 new products pass the validator and the lane tracer at every whole rate up to their maximum with the real 2.1 recipes (1,028 blueprints); every product of the earlier iterations is identical to the committed code at 133 sampled rates and cases (canonical dump, entity order ignored); about 100 breakages of the new code are caught; 1009 busted examples pass.
- Unverified in game: see the list above; also that a belt end pointing away from another belt end does not interact (T2's tail and the head of belt b), and that long-handed inserters really take from a belt over another belt that carries other items.

## Not in scope

Steel, plastic and fluid recipes; a raw item as a head of A or B; using B to speed up 2-ingredient recipes; stack inserter bonuses; mentioning long-handed inserters in the player message; any check of what is unlocked (the owner's later feature).
