# Consolidated inputs: pure single-material belts in, mixed belts made inside

Status 2026-11-09: IMPLEMENTED, NOT RUN IN GAME. The owner approved the direction, asked to plan it on paper first (a scratchpad prototype did that), then said "Sounds good. Implement". It is in the repo as `scripts/feeds.lua`, `scripts/inputs.lua`, `scripts/poles.lua` and `rows.build_pure`, behind the gate below; the original design is unchanged. The real modules reproduce the prototype's numbers exactly: all 6,741 whole-rate blueprints of the 41 products pass the repo's validator and the lane tracer (taught splitters and underground belts), and the area is +37.9% over the 123 sampled blueprints (+40.8% at the most each makes) with at most 8 splitters, 12 underground belts and 4 belts in. The text below is the plan; where the code differs, the notes in "What was built" say how.

## Requirements (owner, 2026-11-09)

1. Fewest input belts per raw material. Today every chain fed raw items has a belt of its own (the fast inserter has 7).
2. The belts that come in carry ONE material on BOTH lanes (the owner's factory sends belts like that), "even if it's more complicated". The blueprint makes the ore-lane/coal-lane belts its furnaces need itself.
3. They enter on the left; the top of the layout is where they are divided. The north-most belts (today's staircase) may be rewritten.
4. Splitters and underground belts are fine; the height may grow with the rate; the size increase is acceptable.
5. KEEP the original design; use the new one only when both the splitter and the underground belt are researched (recipes enabled).
6. Apply it to EVERY blueprint, single-chain ones too (iron plate takes an iron belt and a coal belt).

## What the player supplies

One pure belt per material (coal too), `ceil(total / 900)` of them for a material over one belt (900 = both lanes, from the game's `belt_speed`). Measured with the real recipes at the most each product makes (`belts` today -> `pure` belts now; splitters and underground belts the blueprint needs):

| Product | Rate | Belts today | Pure belts | Splitters | Undergrounds |
|---|---|---|---|---|---|
| Fast inserter | 75 | 7 | 3 (coal, iron, copper) | 7 | 10 |
| Fast splitter | 15 | 8 | 3 | 8 | 12 |
| Lab / splitter / inserter | 15 / 30 / 150 | 5 / 5 / 4 | 3 | 5 / 5 / 4 | 8 |
| Long-handed inserter | 150 | 6 | 4 (iron needs two: 1,050) | 6 | 10 |
| Electronic circuit, science pack | 150, 225 | 2 | 3 | 1 | 4 |
| Iron plate, gear, pipe, copper plate | most | 1 | 2 (ore, coal) | 0 | 0 |
| Wooden chest, stone furnace | most | 1 | 1 | 0 | 0 |

Three products need a second iron belt at their maximum (assembling machine 45, electric mining drill 45, long-handed inserter 150). A recipe with one chain per ore, and every single chain that burns fuel, gets MORE belts (2 or 3 against 1 or 2) but each is pure.

## The structure

Words: PURE belt (one material, both lanes); MIXED trunk (a long belt along the band: ore on one lane, fuel on the other); MIXER (the trunk's first tile, fed from both sides); BUS (a pure belt with 2 or more feeders: a vertical belt with a splitter above every feeder but the last); DIRECT feeder (a pure belt with one feeder: it comes in at the feeder's row); TAP (a splitter that sends a trunk's descent to a leaf); LEAF (a chain fed raw items, or a raw column such as the wood).

Circuits from iron plates and cables with one machine in each column, 33 x 11 (the electronic circuit at 30 a minute is 33 x 13 here and 26 x 9 in the original design). `S` splitter, `(` `)` underground belt in and out, `v ^ > <` belts, `}` `+` inserter and pole, `i` `c` furnaces, `O` cable assemblers, `E` circuit assemblers (the same picture is at the top of `scripts/inputs.lua`, drawn by the real code and checked by `spec/rows_spec.lua`):

```
      012345678901234567890123456789012
   0 |>>v.......................^}EEE}v|   row 0: coal comes in, runs to its bus (column 2)
   1 |..v.......................^}EEE+v|
   2 |>(v.)v....................^+EEE.v|   row 2: copper ore, under the bus, turns south into the copper mixer
   3 |..SS.>>>>>>>>>v...........^......|   the bus splitter sends coal out at row 4; the copper trunk starts at (5,3)
   4 |..v>>^........v...........^......|   coal turns north into the mixer's south side
   5 |>(v.)v........v}cc}v}OOO}v^......|   row 5: iron ore, under the bus, into the iron mixer
   6 |..v..>>>v......+cc+.+OOO}v^......|   the iron trunk starts at (5,6) and turns south at its chain (column 8)
   7 |..>>>^..v............OOO+>^......|   the last coal feeder (the bus ends here)
   8 |........v}ii}v............^......|
   9 |.........+ii+v>>>>>>>>>>>>^......|   the iron plates reach belt a through the lane gadget of rows 9 and 10
  10 |.............>>^.................|
```

Rules, as built in the prototype (N = number of buses; x and y from the top left of the blueprint):

1. **Trunks.** Leaves with the same feed (ore + fuel, or one item) are taken in order from the west and put in a trunk until the next would pass a lane (450 for each of the two items of a mixed trunk, 900 for a pure one): "contiguous first fit". Trunks are ordered with the one whose last leaf is furthest east on top, so a descent only crosses the trunks below it that reach further east. A trunk's row is `y1 + 3 * (number - 1)`, `y1 = N + 2` (1 when N = 0): three rows each, the ore feeder above, the fuel feeder below.
2. **Pure belts.** For each item the feeders it must supply (a mixed trunk's ore, a mixed trunk's fuel, a pure trunk's whole demand) are packed in the order of the trunks into belts of 900. A belt with 2 or more feeders is a bus. Buses are ordered with the most feeders first (the coal), bus `b` (0 = furthest east) enters at row `b`, runs east to column `B = 4N - 2 - 4b` and down it. A direct feeder enters at x = 0 on the row of its feeder.
3. **Bus.** A splitter facing south at `(B, r) (B+1, r)` where `r` is the feeder's row minus 1; its second output `(B+1, r+1)` faces east and is the feeder. The last feeder is the end of the bus: `(B, row)` faces east.
4. **Feeder.** East along its row to the column before the mixer. Where a bus stands in that row it goes under it: underground in at `B - 1`, out at `B + 2`. Buses are 4 columns apart so that an exit and the next entrance can be side by side.
5. **Mixer** at `x_m = 4N + 1`: the trunk's first tile `P = (x_m, y)` faces east with nothing behind it; `(x_m, y-1)` faces south (the ore feeder turns into P's north side) and `(x_m, y+1)` faces north (the fuel into its south side). A belt fed from both sides stays straight, so each side-loads one lane. A pure trunk has no mixer: its feeder row is the trunk.
6. **Taps.** The leaves start at x = `4N + 4`. At every leaf of a trunk but the last, a splitter facing east at `(x-1, y) (x-1, y+1)` (x = the leaf's descent column: the chain's first column, or the raw column's belt): its top output carries the trunk on, its bottom output `(x, y+1)` faces south. The trunk turns south at the last leaf.
7. **Descents.** South from `y+1`. Under every trunk below that reaches further east than the leaf: underground in at row-1, out at row+1. A chain's top is the row after the last descent tile minus its own first row; a raw column's belt starts there; a final column starts two rows under the lowest trunk that passes over it (none: row 0).
8. **Power.** The columns' poles are joined by the nearest pair as before; when the nearest pair is further apart than a wire (7 tiles used, the pole reaches 7.5) poles are put on free tiles along the way (bridge poles). The chains hang lower than a short final column now, which opens a gap: 119 of the 6,741 blueprints (shotgun at 1 and 2 a minute, the small electric pole at 117 rates).
9. **Invariants the code asserts** (none fired in 6,741 blueprints): feeder rows of one bus at least 3 apart; room for an underground entrance under each tap.

## Measured

Over the 123 sampled blueprints (41 products x a fifth, a half and the most): total area 120,259 -> 165,855 tiles (+37.9%), at the most each product makes 63,618 -> 89,559 (+40.8%). Large recipes grow 30 to 55% (fast inserter 75: 91 x 32 -> 102 x 38; lab 15: 71 x 36 -> 82 x 42); tiny ones more than double (iron plate 90: 6 x 10 -> 10 x 13) because of the fixed mixer block. The left block (`4N + 4` columns) stands empty under the band; by a rough count that is a quarter to a third of the growth (not measured exactly).

## What changes in the code

- `config.lua`, `generator.lua`: names `splitter`, `underground-belt`; read `max_underground_distance` (needs 3 or more: a feeder under a bus is a distance of 3); `consolidated_available(force)` = both recipes enabled, both prototypes exist, reach is enough; with no `force` the original design (every existing spec unchanged).
- Demands: `add_demand` records what each step takes; a chain's first stage carries `feed = {items = {{name, amount}, ...}}` (ore then fuel, or the raw items), a raw column carries its item. The prototype did this with three text patches to the generator; the same data raw_amounts already works out.
- `scripts/feeds.lua` (pure: trunks, pure belts, buses; rules 1 and 2) and `scripts/inputs.lua` (geometry: rules 3 to 8, as small functions); `rows.build(root, names, options)` takes the new path for every root, single chains included, and returns the input belts top to bottom (`{x, y, item}`), the original path unchanged. `place_across` takes its start column as an argument (the prototype used a global).
- Entities: splitter `{name, position, direction}` (centre between its two tiles: `grid.position(col, row, 2, 1)` facing south, `(1, 2)` facing east); underground belt `{name, position, direction, type = "input"|"output"}`.
- Test tooling (`spec/support`): the prototype tracer (`tracer3.lua`) is the repo's with splitters (each output tile carries what its two input tiles bring, lane for lane), underground belts (an entrance meets the first underground piece in line within reach, which must be an exit facing the same way), problems for a belt that feeds the side of one of those, `raw_lanes` (the belt of a furnace's inserters holds the ore on one lane and the fuel on the other, a lone item on both) and supplied items allowed on belts of raw items. The validator learns that a splitter's size depends on its direction. The tracer does not model rates: `feeds.lua` is tested for the 450 and 900 limits.
- `messages.lua`, README, `project-status.md`: the message names the belts that come in and in what order; README documents both designs.

## Verification

Done in the prototype: the sweep above (0 problems; the first run found only the power gaps, which bridge poles fixed); negative controls, all reported: a mixer's fuel feeder missing, an underground exit missing, a splitter turned the wrong way, an entrance turned into an exit, an ore feeder running straight on. Done in the repo (2026-11-09): diagram specs per piece (`spec/inputs_spec.lua`: a single chain, a tap, a bus with two feeders, a hop, a double hop, a pure trunk; `spec/rows_spec.lua`: the circuit, wood next to cables, the bridge pole, a second iron belt), the sweeps as specs (every tree of the old sweeps is built in both designs), one negative control as a spec in `rows_spec.lua`, to show that the tracer as the sweeps set it up does report a broken band (the rules the other controls broke, an underground belt with no exit, an entrance turned into an exit, lanes of a furnace's belt, are tested in `belt_tracer_spec.lua`, and a splitter turned the wrong way in the validator spec), and the real-module sweep of all 6,741 blueprints (a scratchpad harness, 0 problems). The mutation run is in `project-status.md`.

## Milestones (one feature, squashed to one commit at the end)

1. Plumbing without a change in behaviour: names, `max_underground_distance`, the gate, `feed` on the layout stages, `options` on `rows.build`, `place_across(columns, start)`; tests.
2. Test tooling for splitters and undergrounds, with its own specs and negative controls.
3. `feeds.lua` with its spec.
4. `inputs.lua` and the new path of `rows.lua` behind the gate; diagram specs and the sweep.
5. Messages, README, status; mutation run.

## Fuel in the middle of a chain: steel (2026-11-10)

Steel plate (5 iron plates, 16 s, smelting) is a furnace that eats another furnace's plates and burns coal, which the original design refused (`error-chain-fuel`). The owner chose to bring the coal on the free lane of the belt between the two furnace columns. The output inserters of the iron furnaces drop plates on the far (east) lane of that belt, so the near (west) lane is free.

- **Geometry.** The belt between the two columns runs south (`share_belt` forces it when the next column `takes_fuel`: the plates of two equal columns would otherwise run it north), so its head is its first tile, in the first row of the columns. The coal is a leaf like any other, a fraction past its chain (`FeedLeaf.index` = the chain's + `position / (count + 1)`) with a pure coal trunk; it comes down the column of the output inserters of the first furnaces (`drop_x` = `belt_column - 1`), and `inputs.fuel_tail` finishes it: down to the row before the head's row, east into the tile above the head (`belt_column`, head row - 1), which runs south with a stub belt (head row - 2) behind it so that it stays straight and the side-load lands on the near lane. The chain starts low enough for that: `rows.chain_top` takes the later of the row under its raw belt and the row two under the end of the coal's descent.
- **Planner.** A stage that burns fuel and eats one made ingredient has that product on one lane and the fuel on the other (`planner.fuel_lanes`); any other stage fed by stages with fuel is still refused.
- **Gate.** Only `rows.build_pure` can do it, so `generator.fuel_problem` refuses the step with `error-fuel-needs-inputs` when the design is not available, and keeps `error-chain-fuel` for a step with a second ingredient.
- **A bus feeder gap of 2.** Heavy armor with the steel chain first put the coal trunk right under a trunk of ore and coal, which made two coal feeders 2 rows apart; the assertion asked for 3 and was relaxed to 2 (`inputs.MIN_FEEDER_GAP`), the sweeps showing the layout holds.
- **Measured.** Steel plate 1 to 90 a minute, steel chest 1 to 11 a minute and heavy armor 1 a minute (the lane of plates: 450 a minute) pass the validator and the tracer, and so do all the other 6,741 blueprints with the same areas as before. The original design is byte for byte unchanged.
- The coal on the free lane is unverified in game, like the other lane rules.

## Unverified in game (to check on the first run)

- A splitter keeps the lanes of both its inputs and balances each lane on its own (a full coal lane must not stop the ore).
- A belt fed from both sides with nothing behind it puts one item on each lane (the mixer).
- A belt tile fed by a splitter output from the side turns into a curve and keeps both lanes (the tap, the peel).
- An underground belt keeps both lanes; an entrance right after a plain belt, an exit right before an entrance, and a hop under a splitter all work.
- Nothing in the row layout has been run in game either, the lane gadget included.

## Considered and not done

- Mirroring the design (mixers above the final column, trunks flowing west): no extra columns, no empty corner, but the final column starts under the band, so the blueprint is taller. Not measured.
- Every pure belt entering at the top (a bus for each): tidier, 4 more columns per direct belt. The rows now are, for the fast inserter at 60, coal 0, iron 1, copper 9.
- Mixed trunks packed by plain bin packing instead of contiguous first fit: fewer trunks sometimes, more crossings.
- Dropping the original design: no, the owner wants it kept.

## What was built (2026-11-09), and where it differs from the plan above

- The entry point is `rows.build_pure(root, names, options)`, a separate function next to the unchanged `rows.build`, not an `options` argument of `rows.build`. `options` is `bpgen.InputOptions` (`lane_items_per_minute`, `underground_reach`); `generator.lua` builds it in `input_options` (the gate: `force` known, both recipes enabled, both prototypes exist, `max_underground_distance` at least `inputs.MIN_REACH`, 3) and calls `build_pure` when `job.inputs` is set. `build_pure` returns the entities and the belts that come in (`{x, y, item}`, top to bottom); the message lists the items (`messages.ready` takes them as a fourth argument and uses the locale key `generated-with-belts`).
- The leaves are the columns of `rows.lua` themselves (`index`, `feed`, `drop_x`); `scripts/feeds.lua` never sees tiles. `scripts/inputs.lua` draws the band as a `Band` of small methods and tells `rows.lua` the row where each leaf's belt ends; `rows.lua` derives the chains' first rows and the raw columns' rows from that, and the final column's from `inputs.first_row_under`.
- `scripts/poles.lua` is the pole joining of `rows.lua` moved out (`poles.join`, behaviour unchanged for `rows.build`) plus the bridge poles (`poles.taken_tiles`, a `bpgen.PoleBridge`); `WIRE_REACH` is 7 where the small pole reaches 7.5.
- `generator.lua` writes each step's `demand` as it adds up the raw items (`own_demand`, `add_to_totals`), and `layout_stage` turns it into a `feed` on the stages that eat only raw items and on the raw supplier (`feed_of`).
- A dead `or 0` found by the mutation run was removed from `feeds.fits` (every leaf of a trunk takes the same items); the 1e-9 tolerance is a named constant with a spec for the rounding noise it absorbs.
- Specs: `spec/feeds_spec.lua`, `spec/inputs_spec.lua` (diagrams of the band per piece, drawn by `spec/support/picture.lua`), `spec/poles_spec.lua`, `spec/rows_spec.lua` (diagram specs of the new design, every sweep tree built in both designs through the validator and the tracer, the four negative controls as specs, the bridge pole), `spec/generator_spec.lua` (the gate case by case, the message), `spec/messages_spec.lua`, and the tracer and validator specs for splitters, underground belts, `raw_lanes` and `turns`.
- Not copied into the repo: the scratchpad harness that sweeps all 41 products at every whole rate (it needs the game's `recipe.lua`); the numbers it gave are in this file and in `project-status.md`.
