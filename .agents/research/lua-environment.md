# Factorio's Lua environment

Source: the "Libraries and functions" page (`lua-api.factorio.com/2.1.23/auxiliary/libraries.html`), pasted into the session by the owner on 2026-10-25 because the site refuses the assistant's fetch tool. Items marked **JSON** were also checked against the 2.1.23 runtime JSON. Items marked **General Lua** are the assistant's own knowledge of Lua 5.2, NOT from the page, and need testing in game.

## What the page says (Verified)

- The base language is a MODIFIED Lua 5.2.1 (not 5.1, and not stock 5.2): extra functions and libraries are added, some modules are removed, and several standard functions behave differently (`pairs`, `require`, `math.random`, the math functions, `load`, `debug`). Never assume stock Lua behavior without checking this page or testing in game. `string.pack`, `string.packsize` and `string.unpack` are backported from Lua 5.4.6.
- `serpent` is a global library. `serpent.block(t)` pretty-prints a table for debugging. It cannot print LuaObjects such as a `LuaEntity`. Combine it with `log`, for example `log(serpent.block(my_table))`.
- `log(LocalisedString)` writes to the Factorio log file. `localised_print` writes to stdout and is meant for external tools. `print()` also goes only to stdout, so it never appears in the log. For debugging use `log()` or `game.print` (chat message to all players; **JSON**: it takes `message` and optional `print_settings`, and skips an identical message sent in the last 60 ticks by default).
- `table_size(t)` counts entries of a table with gaps in its keys. It does NOT work on a `LuaCustomTable`. Use the length operator instead (**JSON**: `LuaCustomTable` has `index` and `length` operators, so `#prototypes.recipe` style access is the way; `prototypes.recipe`, `force.recipes` and similar are all `LuaCustomTable`s).
- Not available: `loadfile`, `dofile`, `coroutine`, `io` and `os`. Factorio supplies its own `package` and `debug` (only `debug.getinfo` and `debug.traceback` by default).
- `pairs()` and `next()` are deterministic: keys iterate in insertion order, and the first 1024 numbered keys always iterate 1 to 1024 regardless of insertion order. So `pairs` on an array-like table is fine.
- `require()`:
  - Absolute paths start at the mod root. `.` and `..` are disabled, so a mod cannot load files outside its own folder.
  - `require("util")` loads Factorio's `util` helper library from the core mod's `lualib` folder.
  - Another mod's file: `require("__mod-name__.file")`.
  - `require` cannot be used in the console, in event handlers, or during `remote.call()`. It expects files to end in `.lua`.
- `math.random()` is deterministic. It uses the map's shared generator, and cannot be used outside events or while loading. Non-integer arguments are floored. `math.randomseed()` does nothing. For an independent generator use `LuaRandomGenerator` (**JSON**: created by `game.create_random_generator`, called like a function, with a `re_seed` method).
- `load()` ignores its `mode` argument and does not load binary chunks. All trigonometric, exponential and logarithmic math functions are Factorio's own deterministic versions.

## What this means for the design

1. **Call `require` only at the top level of a file.** Do all requires at the top of `control.lua` (and `data.lua`), never inside a handler. Verified restriction.
2. **No file I/O, no clock.** `io` and `os` do not exist, so mod code cannot read or write files itself. Use `helpers.write_file` for file output (see the API reference), and do not use `os.time` or `os.clock`.
3. **Deterministic results.** Factorio multiplayer runs the same code on every player's machine, so the blueprint generator must give the same output for the same input. No randomness is needed here, and `pairs` iteration is already deterministic.
4. **Testing outside the game.** Planning-logic modules should stay plain Lua that avoids `io`, `os`, `coroutine`, `game`, `script`, `prototypes`, `storage` and `serpent`, so the same file loads both in the game and under a standalone Lua interpreter (reading the constant table `defines` is fine). The assistant has two: real Lua 5.2.3 (built from GitHub) and `texlua`, see "Running Lua outside the game" below. Mutation check, test and mock results are in `../project-status.md`.
5. **Debugging.** `log(serpent.block(t))` for plain tables; `game.print(...)` to show something in chat; `print()` is useless inside the game.
6. **Lua 5.2 base means older syntax (General Lua, not from the page).** For standalone tests, the closest match is a stock Lua 5.2 interpreter, but it will not reproduce Factorio's changes, so a passing standalone test is not proof the code works in game. No integer type or `//` operator (all numbers are floating point), no bitwise operators, and `goto` exists. `math.floor` and `math.ceil` are the way to round. This matters for the owner, who is new to Lua: a walkthrough should be explicit about it.
7. **`util` library.** It exists and loads with `require("util")`. Its contents are NOT documented in the pages we have; do not use any function from it without checking its source or docs first.

## Running Lua outside the game (found 2026-10-25, updated 2026-10-28)

- Tests run with busted: `busted` from the repo root (config in `.busted`: specs in `spec/`, files ending `_spec`, `./?.lua` on the Lua path, `spec/helper.lua` loaded first). The assistant's environment has no package manager access, so on 2026-10-28 it built real Lua 5.2.3 and cloned busted 2.3.0 and its dependencies from GitHub into scratch; see `../instructions.md` (Tooling gotchas) for the recipe and the blocked routes. On the owner's machine: `luarocks install busted` (Linux, macOS; on Windows use WSL or Docker, native luarocks setup is painful).
- `texlua` (LuaTeX 1.17) is Lua 5.3 and also exists on the assistant's machine, but is no longer used for tests. Factorio is a modified 5.2.1, so 5.3 differences matter: integers and floats (`3 / 1` prints `3.0`, `math.ceil` returns an integer), `//` and bitwise operators, `utf8` and `table.move`. Code must not rely on any of that. Use `string.format` for any number that becomes text (`%d` for counts, `%.2f` for rates).
- Dotted `require("scripts.planner")` works under busted because `.busted` puts the repo root on `lpath`.
- `defines` is a constant table, so pure modules may read it. `spec/helper.lua` sets a fake `defines` for every spec; specs that need `prototypes` assign `_G.prototypes = builders.fake_prototypes{...}` (the `_G.` matters, busted sandboxes spec globals).
- `control.lua` can be loaded the same way against fake `script`, `game`, `prototypes`, a fake player and fake GUI elements; the key trick is a metatable on each fake element so `element[child_name]` finds a DIRECT child.

## Still unknown

- Whether `require` accepts dotted subpaths for files inside the mod in 2.1. The wiki tutorial (written for 2.0) uses `require("bar.foo")` for a file `bar/foo.lua`, see [modding-tutorial.md](modding-tutorial.md). Dotted paths are the form to use; confirm in game before building a folder of modules.
- The contents of `util` (for example `util.table.deepcopy`) and the `mod-gui` helper.
- Whether `bit32` is available (not mentioned).

## Type checking with the Factorio library (2026-11-03)

The owner supplied the Factorio Lua annotation library (1,163 files under `library/`: `runtime-api/` has one file per class, `prototype-api/` the data stage, plus `core`, `base` and others; generated for 2.1.24). It is plain EmmyLua text: grep it for a class or function to read its fields, types and descriptions. Its descriptions are the API docs, so they give no units and few edge cases.

`emmylua_check` finds the Factorio types when the library is added to the workspace, for example with a config file that copies `.emmyrc.json` and adds `"workspace": {"library": ["<path to library>"]}`. Without it the checker prints dozens of "type not found" and "undefined field" warnings for `LuaEntityPrototype`, `LocalisedString`, `defines.direction` and so on. The library path depends on the machine, so it is not in the repository's `.emmyrc.json`. With it, the production code shows three warnings (2026-11-03): `control.lua` reads `error_message` as possibly nil after `if not result` (the generator always gives one with no result; a `---@cast` would settle it), a `frame` test the checker thinks is always false (a `LuaGuiElement` lookup by name can be nil; checker limitation), and `bpgen.Entity[]` passed where `BlueprintEntity[]` is expected (the fields match the library's `BlueprintEntity.base`; the game's type is a union the checker cannot match against a plain entity). The spec files also report busted's `describe` and `it` as undefined unless busted's type stubs are added.
