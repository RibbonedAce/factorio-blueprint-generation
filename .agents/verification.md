# Verification

How a change to the generator is checked against the game's real recipes, besides the specs. The owner chose this on 2026-11-19 and 2026-11-20, after sweeps of every product at every rate (61,982 blueprints for one comparison, 100,404 for the inserter capacity bonus) had grown too big.

## The suite

`verify/` is a fixed set of cases, run on request and not by `busted`:

- `verify/cases.txt`: 1,329 cases, one a line: environment, design, product, rate, and whether the blueprint is built (`ok`, 989 of them) or refused (`refused`, 340). The environment `a` has the basic belts, the stone furnace and the assembling machine 1; `b` has the fast belts, the steel furnace and the assembling machine 2 as well. The design `new` is a force that has researched everything (one belt of each material); `old` is no force (the original design).
- `verify/recipes.lua`: the 85 recipes those products need (every recipe that makes an item they need), copied once from the game's `data/base/prototypes/recipe.lua` (Factorio 2.1). The suite reads nothing from the game's install.
- `verify/harness.lua` and `verify/run.lua`: each case generates a blueprint with the repo's own modules from those recipes and checks it with the validator and the belt tracer of `spec/support/`; a `refused` case has to be refused. From the repo root, with Lua 5.2: `lua52 verify/run.lua` (or `lua52 verify/run.lua a` for one environment). It prints each wrong case and `N cases, M wrong, S seconds`, and exits with 1 when any is wrong. It takes about 13 seconds.

The suite checks that blueprints are sound, not that they are the same as before: there are no stored hashes, so a feature that changes blueprints does not break it.

## What the cases are

The cases were chosen once, from every product at every whole rate in both environments and both designs:

- **The same plan gave the same blueprint.** The 61,982 blueprints had 8,841 different plans and exactly 8,841 different entity hashes: no rate with the same plan (machine counts, inserters, belts of every step) gave another blueprint. So the rates of one plan are one case.
- **A cover of the classes.** A class is a plan with the item names left out, the machine counts 1 to 6 as they are and the bigger ones by parity, and the belts that come in of each material. The cases have every column configuration, every shape of tree and every band of incoming belts of each environment at least once: 723 blueprints, with the first rate that has it.
- **The boundaries.** For each product and design the maximum rate (built) and the maximum plus one (refused); rate 1 (refused) for a product a design cannot make. They are 621 of the cases (some are also in the cover), 340 of the refusals.

How well it works: 360 of the 2,779 mutants (operator and number changes) of `layout`, `rows`, `weave`, `inputs`, `feeds`, `poles`, `lights`, `labels`, `planner`, `generator`, `chain`, `grid` and `entity_list` were put in one at a time. 55 changed no blueprint at a rate up to the maximum; the 304 that did were all noticed by the cover of 723 blueprints used here (and by the 786 of the cover that also has every pair of neighbouring columns), where random sets of the same size noticed 300 to 302, the rates 1 to 8 and the maximum (2,475 blueprints) 303 and log-spaced rates (2,267) 303. The maximum and the rate above it noticed 2 of the 55. A part of the cover smaller than about 400 blueprints is worse than a random set of the same size, so the cases are not trimmed further. (That was judged by comparing hashes with the base; the suite itself judges validity, and a lane capacity that is wrong, or a weave that reaches one tile less, fail it.)

What it can miss: a fault that shows only at one bigger count of a configuration the cases have at a smaller count (exactly 17 furnaces, say); and a regime that came after the cases were chosen (below).

## The policy

| Change | Run |
|---|---|
| Any change | `busted` |
| Comments, documents | Compare the code with the commit before; run nothing else |
| Logic in `scripts/` | `lua52 verify/run.lua` |
| A new product | Add cases for it (below), then `lua52 verify/run.lua` |
| A feature that makes a new regime (a new design, a new building that changes the layout, a new kind of step) | Add cases for the regime (below), then `lua52 verify/run.lua` |

The sweeps of every rate are not run any more, and the cases are not made again by a program: new ones are added by hand.

## Adding cases by hand

The cases do not follow the code. When a change adds a product or a regime, add lines to `verify/cases.txt`, and the recipes of a new product to `verify/recipes.lua` (copy them from the game's `recipe.lua`, with every recipe that makes an item they need):

- **A new product:** the product at rate 1, at 2 and 3, at a rate that gives 4 or 5 machines in its last step (odd and even), at its maximum (built) and at its maximum plus one (refused); in each environment and each design that can build it, and rate 1 refused in a design that cannot. The maximum is the highest rate the generator accepts (`generator.max_rate_message`, or the highest rate that is not refused).
- **A new regime:** the products that take it, at the smallest rate that takes it, at 2 to 5 machines in the step that has it (odd and even), and at its maximum; and one product that does not take it, at a rate the old cases already had, to see that nothing else changed. A research that changes the numbers (the inserter capacity bonus) needs its own environment in `verify/harness.lua` and cases in it.
- Write the expected outcome the way the game's rules say it, not the way the generator answers; run the suite; then look at a blueprint of each new case in a picture (`spec/support/picture.lua`) before trusting it.
- A case is shown to be needed the way a test is: break the code on purpose in a copy of the repo and see that some case fails.

If a layout feature is large (it touches `layout`, `rows`, `weave` or `inputs`), compare the blueprints of the cases with the commit before as well: a hash of the entities of each case, made on both trees (the cases that should not change must not).
