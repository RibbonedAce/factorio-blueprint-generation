# Consistency

How the code and the tests are written, so that a new piece looks like the old ones. The rules are what a read-through of `scripts/` and `spec/` on 2026-11-18 found done two ways and made one. `spec/conventions_spec.lua` checks the ones a script can; review keeps the rest.

## Rules for the code (scripts/)

- **Tiles.** A position becomes a tile only through `grid.top_left_tile` and a tile becomes a position only through `grid.position`: no `+ 0.5` or `- 0.5` on a position anywhere else. A set of tiles is named with `grid.key(x, y)` and filled with `grid.taken_tiles(entities, size_of)`; no module writes a key or a loop over the tiles an entity covers of its own. `lights.taken_tiles` adds to that set the tile ahead of each belt and the tile behind each inlet.
- **Directions.** The four directions are named once at the top of a file (`local north, east, south, west = defines.direction.north, ...`), never `defines.direction.north` in the middle of the code.
- **Entity numbers.** `entity_list.append(list, entity)` adds an entity and gives it its number. The one other place that touches numbers is `rows.lua`, which shifts the numbers and the wires of a block by an offset when it takes the block into the blueprint.
- **Numbers two modules share** are written once: `scripts/constants.lua` (`EPSILON`, `LANES_PER_BELT`, `WINDING_MACHINE_SIZE`, `WINDING_OUTPUT_INSERTERS`), and the widths of the woven and piped columns (`weave.WIDTH`, `weave.PIPED_WIDTH`, `layout.PIPE_COLUMNS`). `chain.input_count` counts what a stage takes from other stages and belts, for the chain and for the generator.
- **Buildings.** `can_build(force, name)` in `generator.lua` says whether a force can build something, and says no without a force or a name. The lamp, the display panel, the fast inserter, the splitter and the underground belt are checked with it.
- **Lists.** Append with `list[#list + 1] = item`; `table.insert` only to put an item at a place (`table.insert(list, 1, item)`).
- **Names.**
  - "stage" in code, "step" where the player reads it (the README, the locale file, the wording of `messages.lua`).
  - A belt the player brings in is a `bpgen.Supply`; the options of the design that takes them are `job.input_options`.
  - "trunk" alone is a trunk of belts (`feeds.lua`, `inputs.lua`); the pipes' is a pipe trunk (`pipe_trunks_of` in `rows.lua`, `Block.pipe_trunk`).
  - A method that puts things in a list is `add_*` (`Band`, `Builder`); the helpers of `rows.lua` take `names` (the shared names), not the name of the belt.
  - The functions of `messages.lua` for the texts of the window are named like their keys in the locale file.
  - `bridge_reach` in `poles.lua` is the reach of a wire less the margin a bridge keeps; "wire reach" in the validator's catalog is the length of wire a pole holds.
- **Types.** A type of a value passed between modules is declared in `types.lua` and listed in `TYPES.md`.
- **Functions.** About 25 lines and complexity 8 (see `instructions.md`). The two builders of the window in `gui.lua` are over the limits: a long run of widgets with no branching, and no spec to show that a change there is safe.
- **Files.** The first line of a file is `-- scripts/<name>.lua`.

## Rules for the tests (spec/)

- Helpers that two or more specs need are in `spec/support/builders.lua`: `entities_named`, `count_named`, `numbered`, `belt_rows`, `belt_directions`, `merged`, `closest_pair`, `with_replaced`. A helper that makes a fake game hands on every option it is given (`builders.merged(base, options)`), so no option is quietly dropped.
- Entity numbers: `assert.has_consecutive_numbers(entities)`.
- A loop never holds an assertion: it makes named tests, or the cases that fail are put in a list of problems that is compared with `{}`.
- A title says `refuses ...` (not `is refused ...`) and leaves the numbers that are computed to the body of the test.
- A position in a test is a tile (`grid.top_left_tile`), never `x == 1.5`.
- A function of a module is swapped for one run with `builders.with_replaced`, which puts it back also when the run fails.

## What the read-through found, and what was done

Each change to `scripts/` was checked by hashing every blueprint of every product at every rate, in two environments (about 61,700), against the tree before it: all identical. The suite passed after each.

| Found | Done |
|---|---|
| Tile keys in six spellings; the tiles an entity covers marked in three loops | `grid.key`, `grid.taken_tiles` |
| `+ 0.5` on positions in `rows.lua` and `poles.lua`, against the header of `grid.lua` | `grid.top_left_tile` |
| The tolerance under four names, the lanes of a belt under three, the winding belt's numbers in two modules, the widths of the woven and piped columns in two | `constants.lua`, `weave.WIDTH`, `layout.PIPE_COLUMNS` |
| `chain.input_count` copied in `generator.lua` | `chain.input_count` |
| Directions written five ways, four of them in `layout.lua` | File-level names |
| Entity numbers given at eight places in two ways | `entity_list.append` |
| Five spellings of "may this building be used" | `can_build` takes no force or name |
| `table.insert` appends in `feeds.lua`; `belt_name` against `names` in `rows.lua`; `draw_*` against `add_*` in `inputs.lua`; two `most_belts` | One way each; `most_input_belts` |
| `Belts`, `WeavePlan`, `WeaveTile`, `RawAmount`, `StepSummary` declared outside `types.lua` | Moved |
| 11 functions over the size or complexity limit | Split (the two of `gui.lua` stay) |
| Copied spec helpers (three different `count_named`), a loop pasted six times, loops over assertions, "is refused" titles, numbers in titles, centre positions written by hand, three hand-made module swaps | `builders.lua`, `assert.has_consecutive_numbers`, generated tests, new titles, tiles, `builders.with_replaced` |
| "step" and "stage", five meanings of "input", two trunks, two wire reaches, captions against labels | The names above |
| Stale README: no choice of tier, one ingredient per later step, figures measured once ("38% more area", "26 of the 75 products"), "as before" | Rewritten; the figures that go stale with every product removed |
| `project-status.md` at 314 lines with the ladder in two orders | Ladder in `feature-log.md` (oldest first), checklists in `unverified.md` |

## Left as it is

- The two builders of the window in `gui.lua` (see Functions above).
- The validator, the belt tracer and the picture of `spec/support/` have their own tile keys and convert positions themselves: they are an independent check of the layout and do not use `scripts/grid.lua`.
- The validator's catalog says `supply_radius` and `wire_reach` where `scripts/` says `supply_distance` and `wire_distance` (and the game `supply_area_distance` and `max_wire_distance`): the catalog is the validator's own description of an entity, and `builders.lua` translates.
- `inputs.footprint` takes any entity that is not a splitter, a pump or a machine for one tile: belts, inserters, poles, pipes, lamps and panels.
- About a fifth of the `it`s hold two or more assertions about one behaviour (mostly `planner_spec.lua` and `layout_spec.lua`), which the test style allows.
- The line length, and the tracked files that are CRLF in the working tree (git stores LF).
- The plan documents name functions that no longer exist (`place_stack`, `composite_block`); they are history, and two of them say so at the top.

## Open decisions

- Whether the pump and the pipes are checked against the research of the force like the lamp and the panel. A recipe that takes a fluid needs them, so a force without the pump would get a blueprint it cannot build yet; whether the game places ghosts of entities that are not researched is not checked.
- A cap for the length of a line (there are about 100 lines over 140 characters in `scripts/` and 380 in `spec/`; some `---@field` descriptions in `types.lua` run to hundreds).
- Whether to normalize the line endings with `.gitattributes` (`* text=auto eol=lf`).
