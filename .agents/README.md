# .agents

Persistent notes for the AI assistant (Claude) working on this repo. They exist so work can resume after a conversation runs out of context or restarts. Humans are welcome to read them too.

## Reading order

1. [instructions.md](instructions.md): how to work with the owner (roles, teaching style, git workflow, tooling gotchas).
2. [project-status.md](project-status.md): the goal, what exists, decisions made and still open, next steps.
3. [research/factorio-2.1.md](research/factorio-2.1.md): release facts, checklist status, and what is still unverified.
4. [research/mod-structure.md](research/mod-structure.md): folder naming, `info.json` rules, file layout.
5. [research/lua-environment.md](research/lua-environment.md): what differs from standard Lua (missing modules, `require` rules, determinism) and what that means for the design.
6. [research/data-lifecycle.md](research/data-lifecycle.md): the settings/prototype/control stages, load order, and the `storage` rules. Read before writing `control.lua`.
7. [research/modding-tutorial.md](research/modding-tutorial.md): practical setup, locale format, error shapes, and the multiplayer desync rules (Secondary, written for 2.0).
8. [research/api-reference-2.1.23.md](research/api-reference-2.1.23.md): the verified API names and signatures this mod needs, read from the official JSON files. Check it before writing any code that calls the game API.

9. [recipe-tree-plan.md](recipe-tree-plan.md): the proposed recursive block layout for recipes with two made ingredients, starting with the electronic circuit (a proposal until the owner approves it).
10. [multi-input-plan.md](multi-input-plan.md): the plan for recipes with 3 or 4 ingredients, starting with the inserter: a second input belt reached by long-handed inserters. Decisions confirmed by the owner 2026-11-07; implemented (its layout part is superseded by item 11).
11. [row-layout-plan.md](row-layout-plan.md): the layout of recipes with several made ingredients since 2026-11-08: one column per step, side by side, so the recipe fixes the width and the rate only the height. Replaces the stack of `blocks.lua`; has the reasons, the measurements and what was considered and not done (underground belts, stacking columns).
12. [inputs-plan.md](inputs-plan.md): the design that brings in one pure single-material belt per raw material instead of a mixed belt per chain, and makes the ore-and-coal belts inside a band along the top with splitters and underground belts, only when both are researched (built 2026-11-09, `scripts/feeds.lua`, `scripts/inputs.lua`, `scripts/poles.lua`, `rows.build_pure`; the original input design stays). Has the rules, the measurements and what is unverified in game.

## Maintenance rules

- Update `project-status.md` after every decision and at the end of each work session.
- Every researched fact gets a source link and a label: **Verified** (primary source read), **Secondary** (someone else's summary), or **Unverified** (memory or a lead). Do not code against anything that is not Verified.
- The repo is public. Never put personal information, credentials, or session links in these files.
- Keep each file short. Split a file when it grows past roughly 200 lines.
- Use absolute dates (for example 2026-10-24), never "yesterday" or "recently".
