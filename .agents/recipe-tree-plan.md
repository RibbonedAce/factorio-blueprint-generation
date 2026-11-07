# Recipe trees: a recursive block layout (first use: electronic circuit)

Status: IMPLEMENTED on 2026-11-07, not yet run in game. APPROVED by the owner on 2026-11-07 ("not 100% what I had in mind but it satisfies my requirements and works until we can get more sophisticated layouts with splitters and underground belts"). Implementation follows the order under "Work needed"; the progress is in `project-status.md`. This replaces the first design of the same day (the "fork", see the end), which the owner rejected. The layout was prototyped in a throwaway script (scratchpad, not in the repo, lost with the session) that builds the entities, runs `spec/support/blueprint_validator.lua` on them, and follows the items lane by lane with a small belt tracer.

## Requirements (owner, 2026-11-07)

- Electronic circuit = 1 iron plate + 3 copper cable (0.5 s, category `crafting`; Verified: base 2.1.24 `recipe.lua`). It is the first recipe with TWO made ingredients. No underground belts or splitters; each step has at most one input belt, so each ingredient gets one lane.
- The design must be RECURSIVE: "drop down" the blueprint of each ingredient, then put the final machines in a separate column to the right of all of that ("the E to the right of the I"). It must scale to recipes like the offshore pump (3 pipes + 2 iron gear wheels: each ingredient needs a furnace column and an assembler column; Verified, base 2.1.24) and to an ingredient that is itself a tree (underground belt = 10 iron plates + 5 transport belts, and a transport belt = 1 plate + 1 gear).
- Four raw items cannot share two lanes, so a blueprint with two raw materials has several raw belts. "One input belt per step" holds; "one raw belt per blueprint" cannot.

## Belt rules the design rests on

1. "Inserters place the item on the furthest lane." (Secondary: official wiki, https://wiki.factorio.com/Inserters, read 2026-11-07.) So a column's output inserters on the west of a belt fill its east lane.
2. From a belt perpendicular to it, an inserter takes from the nearest lane first and from the far lane when the near one is empty (same page). So one belt with a different item on each lane feeds a machine.
2b. Verified in game by the owner, 2026-11-07: across the inserter's line the item goes on the far lane; on a curve it goes on the INSIDE lane of the curve, whichever way the inserter or the curve faces; on a belt in line with the inserter (running away from it or toward it) it goes on the belt's right-hand lane, looking along the way the belt runs (the wiki's wording was right; a first note of this session that said otherwise was wrong). The layout only uses the first rule. The third will matter once there are underground belts and splitters, where an inserter can stand in line with a belt; `spec/support/belt_tracer.lua` already models all three.
3. A belt that is fed from behind AND from the side stays straight, and the side feeder puts everything on the near lane (side-loading). The repo already relies on this for the winding output belt (owner's report of Factorio's belt rules, 2026-11-06). The wiki pages I could fetch (Belt_transport_system, Transport_belts) do not cover side-loading or curves: Unverified by a source here.
4. A belt with ONE side feeder and nothing behind it becomes a curve and keeps each lane's identity (same status as 3).

## The model: blocks

A block is the blueprint of one item at one rate: a rectangle with
- raw belts entering from the WEST, each at its own first row (items on one lane, fuel on the other);
- ONE product belt in its rightmost column, full height. The block does not draw that belt; whoever uses the block does, and picks the direction it runs.

A leaf block is a straight chain of columns (today's `build_chain`, same rules). A composite block is two blocks plus one final column.

## The recursive step

`first` (upper) and `second` (lower) are blocks, w and h their widths and heights, R = max(w1 - 2, w2 - 1), X = R + 1:

- `first` is placed so that its product belt is column X; that belt IS the final column's input belt: it runs south from row 0 to the final column's last input row.
- `second` is placed one row below `first` (row h1 stays empty: the join row), with its product belt in column R. That belt runs NORTH, up to the join row.
- Join tile: a belt at (R, h1) facing east. It curves `second`'s product into the west side of X. X has a belt behind it and one from the side there, so the product of `second` is side-loaded onto X's west lane, while `first`'s product (dropped by inserters west of its belt) rides X's east lane. Different lanes, no mirroring, no flipping.
- The final column is the existing standard column with its input belt = X, starting on row h1 + 1, i.e. beside `second`.
- The composite's product belt is the final column's output belt (its rightmost column); its height is max(h1 + 1 + h2, end row of the final column).
- Poles: every block keeps its own wiring; the three groups (upper block, lower block, final column) are joined, nearest group first, by the nearest pair of poles. FOUND WHILE BUILDING (2026-11-07): the prototype only swept small counts. With a tree inside a tree and tall furnace columns (6 furnaces or more) the nearest pair was 10 tiles apart, out of a small pole's 7.5 reach: a wide block has its tall column of furnaces on the left, and the join is on the right. So a block that has neighbours also keeps a LINE of poles in the column beside its product belt (its last column's output inserters), a pole every 6 rows, from within 2 rows of its top to within 2 rows of its bottom (`extend_pole_line` in `scripts/blocks.lua`); every join is then at most about 6 tiles. The last block of the blueprint has no neighbours and gets none.
- Which block goes upper is free. Default: the shorter block lower, beside the final column, so the circuit assemblers sit right of the iron furnaces. At most 2 rows taller than the other order at 150 a minute.

Circuit, 50 a minute (C copper furnace, K cable assembler, I iron furnace, E circuit assembler, `}` inserter moving east, `+` pole, `v ^ >` belts; 18 wide, 15 tall, 104 entities; prototype output):

```
    |012345678901234567|
 0  |v}CC}^}KKK}v.....v|     x=0   copper ore + coal enters from the west
 1  |v+CC+^+KKK}v.....v|     x=5   copper plate belt (north)
 2  |v}CC}^.KKK+v.....v|     x=11  X: cables on its east lane
 3  |v.CC.^}KKK}v.....v|            (cable assemblers drop on it),
 4  |v}CC}^.KKK}v.....v|            iron plates on its west lane
 5  |v+CC+^.KKK.v.....v|     row 8 the join row: the turn tile at x=10
 6  |v}CC}^.....v.....v|     x=5 (row 9)  iron ore + coal enters from the west
 7  |..CC.......v.....v|     x=10 iron plate belt (north, rows 9-14)
 8  |..........>v.....v|     x=17 circuit belt, full height
 9  |.....v}II}^v}EEE}v|
10  |.....v+II+^v}EEE+v|
11  |.....v}II}^v+EEE.v|
12  |.....v.II.^v}EEE}v|
13  |.....v}II}^v}EEE.v|
14  |......+II+^..EEE.v|
```

Offshore pump, 10 a minute (I iron furnace, G gear assembler, p pipe assembler, O pump assembler; 19 wide, 11 tall): the gear block is upper, the pipe block lower.

```
 0  |.v}II}^}GGG}v.....v|
 1  |.v+II+^+GGG+v.....v|
 2  |.v}II}^.GGG.v.....v|
 3  |.v.II.^.....v.....v|
 4  |.v}II}^.....v.....v|
 5  |..+II+......v.....v|
 6  |...........>v.....v|
 7  |v}II}^}ppp}^v}OOO}v|
 8  |v+II+^+ppp+^.+OOO+v|
 9  |v}II}^.ppp.^..OOO.v|
10  |..II.......^......v|
```

Recursion: the underground belt is the circuit step applied twice (iron plate block + transport-belt block, where the transport-belt block is itself iron plate block + gear block + belt assemblers): 24 wide, 15 tall at 10 a minute.

## Checked in the prototype

- Every shape passes the validator (overlaps, inserter ends, power, one wire network) and the tracer (no lane carries two items, every input inserter sees everything its machine eats, everything made is eaten, the root belt carries only the product, every raw belt can be fed from the west).
- Circuit at 10, 50, 100 and 150 a minute, offshore pump at 5 to 40, underground belt at 4 to 20 (sizes from the real planner), plus 4,096 two-level builds (1 to 4 machines per column, inserter variants, both block orders) and 3,888 three-level nested builds (all four order combinations): 0 problems.
- The tracer was mutation-tested: a missing or reversed turn tile, a product belt running away from the join, a cut shared belt, a mixed lane, an inserter dropping on a curve and a blocked raw feed are all reported.
- Sizes (width x height): circuit 18x7 at 10 a minute, 19x9 at 25, 18x15 at 50, 18x29 at 100, 18x43 at 150 (the maximum: the cable lane carries 450 cables, 3 per circuit; 151 is refused). The first (fork) design was 18 wide and 6, 7, 12, 24, 34 tall: the recursive one is about 25% taller at the same width.

## Costs and limits

- Height grows with the number of leaf blocks (all stacked in one column); width grows by about 8 columns per level.
- Every leaf has its own raw belt and furnace column: the offshore pump has two separate iron ore belts. Sharing one needs splitters.
- A circuit assembler makes 25.2 a minute, not the 60 its speed allows: its 2 input inserters (size - 1) move 100.8 items a minute and a circuit eats 4. With a third input inserter it would make 37.8; that breaks the `size - 1` rule and is not assumed here.
- Not covered: three or more made ingredients (inserter), a made plus a raw ingredient (small electric pole), and the final column needing a pole row. A single made ingredient that is itself a composite (a block followed by one more column) uses the existing chain geometry with the block's product belt as the input belt.
- The root's output belt may still wind (3x3 machine, 2 output inserters); inside a tree every product belt is plain.

## Work needed, in the order proposed (each a reviewable commit)

1. `planner.lua`: stages become a tree (`StageContext.previous` -> `inputs`). Demand per ingredient (ingredient amount / product amount), one lane per made ingredient, maximum rate by recursion. A chain is a tree where every node has one input. Check with a differential dump over many chain requests (the earlier throwaway scripts are gone; recreate one).
2. `layout.lua`: a block does not draw its product belt (a `Place` option); `compose` as above; the final column's own first row; wiring of groups. Check with a dump of `build_chain` over many shapes, identical before and after.
3. `chain.lua`, `generator.lua`, `config.lua`, locale, README: resolve a step with two made ingredients (and no raw one) into a tree; the fuel rule becomes "only the first step of each leaf"; the message lists every raw belt from top to bottom; add `electronic-circuit` (then offshore pump, underground belt).
4. Specs: the tracer and the sweeps from the prototype move to `spec/support/` and `spec/`; planner tree tests; chain tests (a made plus a raw ingredient refused, three made ingredients refused).

## Raw belts at the top left (owner, 2026-11-07, after trying the circuit in game)

All belts of raw items enter at the top left. A belt that does not start in the corner (column 0, the top row of the blueprint) gets a trail added by `blocks.build`: from the top row of the blueprint (level with the top of the first belt) down a column west of it, then east along the row of the belt into its first tile. The belts are taken from the top down; each trail gets the next column to the west (-1, -2, ...), so a lower belt's trail turns east below the trails above it and none crosses another. A chain, and the belt of a wide upper block, are already in the corner and get nothing. The message lists the belts starting with the one next to the blueprint and going west.

## Decisions (owner, 2026-11-07)

- The picture is accepted. The owner's own idea was "longer recipe to the left, shorter to the right of that, final product to the right of that"; this layout is kept instead.
- Which block goes lower: the shorter one, by the rows of the two built blocks, ties in recipe order. "The metric for shorter might get messy, don't look too much into it for now": it is one comparison in one place and easy to change later.
- The message wording is fine for now ("raw belts enter from the left, from top to bottom"); it can be improved later.

## Unverified (check in game once built)

1. The join: the curve into X and the side-load onto its west lane (3 and 4 above).
2. The final column's inserters fetch both items from X.
3. The long full-height product belts and first-pick fairness at the maximum rate (6 circuit assemblers).
4. A raw belt fed from the west at its first tile (it becomes a curve) takes ore and fuel on the lanes the player chose.
5. Wires between blocks (nearest poles) and one connection powering everything.

## The first design (rejected 2026-11-07)

The "fork": cable chain west, the iron furnaces as a MIRRORED column east of the shared belt, circuit assemblers below both. It built the circuit and could build the offshore pump, but each branch had to be a straight chain (not a tree), one branch needed mirroring, and a composite's product belt was not at an edge of its box, so it did not nest. Prototype result for the record: 18 wide, 6/7/12/24/34 tall at 10/25/50/100/150 a minute, 4,802 shapes clean.
