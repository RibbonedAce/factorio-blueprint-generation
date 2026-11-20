# Verification

How a change to the generator is checked against real recipes, and how many blueprints that takes. The owner chose this policy on 2026-11-19, after sweeps of every product at every rate (61,982 blueprints for one comparison, 100,404 for the inserter capacity bonus) had grown too big.

## What is known

- **The same plan gives the same blueprint.** Of 61,982 blueprints (every product at every whole rate, in the default environment and with every upgrade, in both designs), 8,841 had different plans and exactly 8,841 had different entity hashes: no rate with the same plan (machine counts, inserters, belts of every step) gave another blueprint. Keeping the first rate of each plan loses nothing for a hash comparison or for the validator and the tracer. A feature that makes the layout depend on more than the plan (the exact flows, say) breaks this, and the comparison has to be made once more over all rates.
- **A cover of the classes is enough in practice.** A class is a plan with the item names left out, the machine counts 1 to 6 as they are and the bigger ones by parity, and the belts that come in of each material. A set of blueprints that has every column configuration, every pair of neighbouring columns (kind and count class), every shape of tree and every band of incoming belts of each environment at least once is 786 blueprints.
- **The boundaries are not in the plans.** The most one blueprint makes, and the rate above it (which has to be refused), are checked by their own cases: for each product and design the maximum and the maximum plus one (rate 1 for a product a design cannot make). They are 621 cases, 340 of them refusals.
- **How well it works.** 360 of the 2,779 mutants (operator and number changes) of `layout`, `rows`, `weave`, `inputs`, `feeds`, `poles`, `lights`, `labels`, `planner`, `generator`, `chain`, `grid` and `entity_list` were put in one at a time: 55 change no blueprint at a rate up to the maximum, and the 304 that do were all noticed by the cover; random sets of the same size noticed 300 to 302, the rates 1 to 8 and the maximum (2,475 blueprints) 303, log-spaced rates (2,267) 303. The maximum and the rate above it noticed 2 of the 55. The cover only works whole: a part of it smaller than about 400 blueprints is worse than a random set of the same size.
- **What it can miss.** A fault that shows only at one bigger count of a configuration the cover has at a smaller count (exactly 17 furnaces, say).

## The policy

| Change | Run |
|---|---|
| Any change | `busted` |
| Comments, documents | Compare the code with the commit before; run nothing else |
| Logic in `scripts/` | The standard set: the cover and the boundaries, 1,394 cases (666 in the default environment, 728 with every upgrade), about 12 seconds in each environment with the validator and the tracer. For a refactor, every blueprint is compared with the base; for a feature, the validator and the tracer judge, and the set is made again for the environment of the feature (the plans of that environment) |
| Layout, planner or rows work, before it is handed over | The 8,841 different plans once, in each environment that matters |
| A new product | The standard set made again with it (its classes join the cover) |

The sweeps of every rate are not run any more.

## How the sets are made

1. For every product and design, at every whole rate up to its maximum, the planner's decision is written down as text without any check: for every step, its kind (furnace or assembler, size, fluid, built wide), its machine count, its input and output inserters (count, fast, long-handed), the items on each belt and how many belts of each material come in. A plan with the names and every count is the plan; the class has the names left out and the counts above 6 as parity.
2. The first rate of every different plan is the set of all plans (8,841 now).
3. The cover is chosen greedily from the plans: each pick is the plan with the most elements (column configuration, pair of neighbouring columns, shape of tree, band) not yet in the set, the smallest rate among equals, until every element is in.
4. The boundaries are added for every product and design.
5. The base hashes of the commit before a refactor are made once for the set; the unmutated tree has to equal them.

The scripts that did this (the planner's decisions, the cover, a set runner with a hash comparison and the validator and tracer, and a mutant runner with a memory guard) were written for the scratch folder and read the game's recipes from the owner's install; they are not in the repository.
