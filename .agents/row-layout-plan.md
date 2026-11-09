# Row layout plan: the recipe fixes the width, the rate only the height

Decided by the owner 2026-11-08 and implemented the same day (`scripts/rows.lua` replaces `scripts/blocks.lua`). This file keeps the reasons and the measurements, because the code only shows the result.

## Why

The owner's rule (2026-11-08): **the rate dimension must be orthogonal to the recipe dimension.** The recipe fixes one axis of the blueprint, the rate only stretches the other. Which axis is which does not matter, a blueprint can be rotated when it is placed.

The old layout (`blocks.lua`, a vertical stack of blocks) broke that: a deeper recipe made it taller, and so did a higher rate, so it grew in the same direction for both reasons. The row layout puts every stage in a column of its own, side by side, so the width is the sum of the columns and does not depend on the rate at all (a column gets more machines, not more width).

## The layout

Every stage is one column, built by `layout.chain_block` exactly as before. The columns stand left to right in the order of a post-order walk of the recipe tree: the stages that make the ingredients of a stage, then the stage itself. The ingredients of belt a come first (the first one is the "head"), then those of belt b, each in the recipe's order. Example, the electronic circuit at 30 a minute (x from -1; `ii` and `cc` are furnaces, `O` the cable assemblers, `E` the circuit assemblers, `}` inserters, `+` poles):

```
      10123456789012345678901234
   0 |>>>>>>>v...........^}EEE}v|     raw belts: rows 0 and 1, from the west edge
   1 |>v.....v}cc}^}OOO}v^}EEE+v|     (the top row feeds the easternmost column)
   2 |.v}ii}vv+cc+^+OOO}v^+EEE.v|
   3 |.v+ii+vv}cc}^.OOO+v^}EEE}v|     belt a (x = 18) runs NORTH along the circuit column
   4 |.v}ii}vv.cc.^.....v^}EEE.v|
   5 |...ii.vv}cc}^.....v^.EEE.v|
   6 |......v.+cc+......>^......|     the cables turn east at row 6 and join belt a from the west
   7 |......v>>>>>>>>>>>>^......|     the iron plates run along row 7 (the "arc")
   8 |......>>^.................|     and reach it through the lane gadget in rows 7 and 8
```

1. **Raw belts** come in from the west edge, one row each at the top. The column furthest east has the top row, so no belt crosses another. A belt runs east along its row, turns south in the first column of its chain and goes on down the column. Every belt of raw items therefore enters at the top left, as it did before.
2. **Where a column starts.** A column starts in the row under the raw belts that pass over it (the rows of the columns east of it), not under all of them. A chain starts right under its own raw belt. A column that eats what others make keeps one more row free: its belts flow north, and the end of a belt that points into the side of another belt feeds it. Without the free row the circuit column fed iron plates and cables into the raw belt above it (found by the lane tracer on 2026-11-08).
3. **Products leave at the bottom.** A product belt goes down from the last output inserter of its column, turns east along its own row (an "arc") and goes up into belt a or belt b of the column that eats it. Belt a and belt b flow north.
4. **Arc rows** are assigned from the east. An arc runs under every column it passes and under its consumer, and deeper than the arcs it would cross (an arc of a column further west encloses the arcs of those east of it), so nothing crosses. A nested composite keeps its own arcs inside, and the arcs of the outer composite run deeper still.
5. **Two products on one belt** need a lane each. The second product (the "side") joins from the west by side-loading: everything lands on the west lane. The first (the "head") would curve into the belt and keep both lanes, so it goes through the **lane gadget**: its belt goes one row past its arc row, east two tiles, then north into the side of the arc, which has a stub belt behind it so it stays straight. A side-load puts everything on the near lane, the south lane, and after the east-to-north turn into belt a that is the east lane. The gadget takes two rows and needs two free columns east of the head's product column.
6. **A raw item that goes with a made one** (wood next to cables) has no machines: its column is two wide (one column for the belt, one spare for the gadget of the head before it) and its belt is the arc.
7. **Belt b** is one column west of belt a (reserved before the column that eats it) and starts at the first long-handed inserter. It is a belt of its own and its arcs end one column west of belt a's.
8. **Poles**: each column keeps its own poles; the groups are joined by the nearest pair of poles, one wire per group. No line of poles beside the product belt is needed any more.
9. **The root** draws its product belt along its east edge, from the first output row down, and may wind, which makes the blueprint one column wider: the only way the width changes with the rate (not before 60 a minute for the transport belt and the pole).

## Decisions of the owner (2026-11-08)

- Replace the stack design entirely; no option to keep both.
- Raw belts enter on the west edge (the top row for the easternmost column), the product leaves at the bottom right: fine.
- Wide blueprints are fine (the circuit is 26 wide, the inserter 52, the fast inserter 91, the fast splitter 110); a low rate gives a flat strip, and a blueprint can be turned.
- A test blueprint string for the lane gadget was not worth the effort. **The gadget is therefore not verified in game.**

## Measurements (scratch harness in %TEMP%\bpgen-work, not in the repo)

Survey of 41 products at 3 rates each (the most the product can make, half, a fifth), 123 blueprints; area in tiles of the bounding box.

| Layout | Total area | vs the stack of 2026-11-08 |
|---|---|---|
| Stack, as it was | 134,753 | |
| Stack with the order search and the final column under the stack (round 1, never merged) | 117,896 | -12.5% |
| Row layout, plain (all columns start below all raw belts) | 138,377 | +2.7% |
| **Row layout with the rules above** | **120,259** | **-10.8%** |

The fast inserter at 60 a minute: stack 36 x 92 = 3,312 tiles, round 1 28 x 100 = 2,800, row layout 91 x 28 = 2,548.

All 6,741 whole-rate blueprints of the 41 products (every rate from 1 up to the most a blueprint can make) pass the repo's validator and lane tracer, and the width is the same at every rate (except the +1 column when the root winds).

Where the empty space is in the row layout (54.0% of the box is used): 24.9% under the columns shorter than the tallest (the "shadow": a constant share of the box at every rate, because column heights grow in step with the rate), 12.8% inside the frames of the chains, 4.0% in the rows under the tallest column that the arcs need, 2.3% over the columns, 2.0% between them.

## Considered and not done

- **Underground belts** (asked 2026-11-08). They cannot compact this layout: a hop hides at most 4 tiles (`max_distance = 5`, `transport-belts.lua`), the arcs under one column overlap in x and need a row each whether or not they can cross (with free crossing none of 90 multi-column blueprints got a row shorter), and the empty space is mostly the shadow and the chain frames. They matter for something else, the owner's input pattern with four lanes and plain inserters (parked until fast inserters). The tracer and the validator would have to learn undergrounds first.
- **Stacking neighbouring short columns** in one slot to win back the shadow: estimated -5.3% with a generous cost model (two free columns and a free row per extra chain in a slot). Not worth the complexity now.
- **Chains facing each other across one product belt** put their products on different lanes of it (an inserter drops on the far lane), which would save the gadget for a pair. Needs a mirrored chain; an idea only.
- **Lowering a chain that is shorter than the column that eats it** (tried and removed 2026-11-09). At 60 science packs a minute the belt of copper plates runs from the furnaces at the top down to the bottom of the 30-row assembler column, because belt a runs north and every product must enter below the last input inserter. Lowering the chains until their bottoms were level with the column's made the belt of plates short and the belts of raw items long, with no change in area and no failure in the 6,741-blueprint sweep, but the owner did not like how the rows were arranged. The long belt of plates stays. If it is tried again: a chain can only sink while all the columns' poles can still be wired (a one-furnace chain lost its only neighbour in reach), and the final column cannot float up instead because the blueprint would grow taller.
- Sharing one raw belt between chains that use the same ore (fewer belts for the player to lay): a later feature, not compaction.

## Unverified in game

- The lane gadget (a belt side-loading a straight belt from the south, then the east-to-north turn keeping the lane). It is the same rule family as the west side-load the owner verified, and the tracer models it that way, but nobody has seen it run.
- The south-to-north belt a with its inputs from the west and the free row under the raw belts.

## Where it lives

`scripts/rows.lua` (`rows.build(root, names)`, same arguments and results as `blocks.build`), tests in `spec/rows_spec.lua`, called from `scripts/generator.lua`. `blocks.lua` and `blocks_spec.lua` are gone; their stacking rules (`tallest_first`, `belt_under_belt`, `final_first_row`, the trails and the lines of poles) have no use here.
