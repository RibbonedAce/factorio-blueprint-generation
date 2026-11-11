# Types and how they fit together

The mod passes a lot of small tables between modules. This file draws them so you do not have to read every `---@class`. The declarations themselves stay the source of truth: `scripts/types.lua` for types that cross modules, and the module that owns a type for the rest (the last section lists where). The diagrams leave the `bpgen.` prefix off the names.

There are four views, from the widest to the narrowest. Start with the first.

1. **Data flow**: which module hands which type to which. Answers "where does this table come from and where does it go?"
2. **Module dependencies**: who `require`s whom.
3. **Class diagrams**, one per area: what a type is made of and how types contain or extend each other.
4. **Where each type is defined.**

A single class diagram of everything would have about 70 boxes and no readable layout, which is why the class diagrams are split by area.

How to read the class diagrams: `A *-- B` means A is made of B (it holds one or a list of them); `A o-- A` means a tree (a stage holds its supplier stages); `A --|> B` means A has all the fields of B plus its own; `A ..> B` means A is read or turned into B by some function; `A --> B` is a plain reference. Only the fields that carry meaning are listed, and the types in `types.lua` have the rest.

## 1. Data flow

```mermaid
flowchart LR
  player([player]) -->|"item, rate"| gui["gui.lua"]
  gui -->|"item, rate, force"| generator["generator.lua"]
  prototypes[("game prototypes")] -->|"recipes, machines, belt speed"| generator

  generator -->|"RecipeLookup"| chain["chain.lua"]
  chain -->|"ChainStage tree"| generator
  generator -->|"TreeRequest: StageTree of StageRequest"| planner["planner.lua"]
  planner -->|"PlanTree of Plan"| generator

  generator -->|"StageLayout tree with Feed, SharedNames, InputOptions"| rows["rows.lua"]
  rows -->|"StageLayout, Names"| layout["layout.lua"]
  layout -->|"Block"| rows
  rows -->|"FeedLeaf list, lane size"| feeds["feeds.lua"]
  feeds -->|"FeedPlan"| rows
  rows -->|"FeedPlan, SharedNames, reach"| inputs["inputs.lua"]
  inputs -->|"NewEntity list, Input list, row where each belt ends"| rows
  rows -->|"pole groups, PoleBridge"| poles["poles.lua"]
  poles -->|"wires on poles, bridge poles"| rows
  rows -->|"Entity list, Input list"| generator

  generator -->|"RawAmount, StepSummary, belts"| messages["messages.lua"]
  messages -->|"LocalisedString, description"| generator
  generator -->|"Generated"| gui
  gui -->|"blueprint on the cursor"| player
```

The generator is the only module that reads the game's prototypes; everything to its right is pure.

## 2. Module dependencies

```mermaid
flowchart TD
  control["control.lua"] --> gui["gui.lua"]
  gui --> generator
  gui --> config
  gui --> messages
  generator --> config
  generator --> chain
  generator --> planner
  generator --> layout
  generator --> inputs
  generator --> rows
  generator --> messages
  rows --> feeds
  rows --> inputs
  rows --> layout
  rows --> poles
  rows --> grid
  poles --> layout
  poles --> grid
  layout --> grid
  inputs --> grid
```

`chain`, `planner`, `feeds`, `messages` and `config` require nothing: they work on plain tables. `types.lua` is never required; it only feeds the editor.

## 3. Class diagrams

### 3a. From the recipe to the plan (generator, chain, planner)

```mermaid
classDiagram
  direction LR

  class Production {
    machine
    fuel
  }
  class ChainStage {
    item
    raw_item
  }
  class StageData {
    item
    machine
    machine_size
    fuel_use
  }
  class EnergySource {
    kind
  }
  class Recipe {
    name
    energy
  }
  class RecipeItem {
    name
    amount
  }

  Production *-- Recipe : recipe
  Recipe *-- RecipeItem : ingredients and products
  ChainStage --|> Production
  ChainStage o-- ChainStage : suppliers
  ChainStage ..> StageData : read_stage adds game numbers
  StageData o-- StageData : suppliers
  StageData *-- Recipe
  StageData *-- EnergySource

  class StageRequest {
    product
    machine_speed
    fuel
  }
  class InserterLimits {
    items_per_minute
    fast_items_per_minute
    max_input
    max_output
    machine_size
  }
  class StageTree
  class TreeRequest {
    rate_per_minute
    lane_items_per_minute
  }
  class ChainRequest
  class PlanRequest

  StageRequest *-- Recipe
  StageRequest *-- InserterLimits : inserters
  PlanRequest --|> StageRequest
  ChainRequest o-- StageRequest : stages
  StageTree *-- StageRequest : stage
  StageTree o-- StageTree : suppliers
  TreeRequest *-- StageTree : root
  StageData ..> StageRequest : stage_request

  class Plan {
    machines
    load
    output_per_minute
    lanes
    input_inserters
    input_fast
    long_inserters
    output_inserters
    output_fast
  }
  class PlanInput {
    name
    per_minute
  }
  class Belts {
    a
    b
  }
  class PlanTree
  class PlannedStage
  class Demand {
    name
    amount
    is_fuel
  }
  class Job {
    item_name
    rate_per_minute
    belt_speed
    fast_inserter_rotation_speed
  }
  class InputOptions {
    lane_items_per_minute
    underground_reach
  }

  Plan *-- PlanInput : inputs
  Plan *-- Belts : belts
  PlanTree *-- Plan
  PlanTree o-- PlanTree : suppliers
  PlannedStage *-- StageData : stage
  PlannedStage *-- Plan : plan
  PlannedStage *-- Demand : demand
  PlannedStage o-- PlannedStage : suppliers
  Job *-- StageData : root
  Job *-- InputOptions : inputs, only for the new design
  TreeRequest ..> PlanTree : planner.plan_tree
  PlanTree ..> PlannedStage : planned_tree
```

### 3b. What the layout is told, and what it builds (layout, rows, generator)

```mermaid
classDiagram
  direction LR

  class StageLayout {
    machine_count
    load
    machine
    belt
    recipe
  }
  class Shape {
    machine_size
    input_inserters
    input_fast
    long_inserters
    output_inserters
    output_fast
  }
  class RawSupplier {
    raw_item
  }
  class Feed
  class FeedItem {
    name
    amount
  }

  StageLayout *-- Shape
  StageLayout o-- StageLayout : suppliers
  StageLayout o-- RawSupplier : suppliers
  StageLayout *-- Feed : feed, only a stage fed raw items
  StageLayout *-- Feed : fuel_feed, only a stage that burns fuel from the belt before it
  RawSupplier *-- Feed
  Feed *-- FeedItem : items

  class SharedNames {
    belt
    inserter
    pole
    long_inserter
    fast_inserter
    splitter
    underground
  }
  class Names {
    machine
    recipe
  }
  Names --|> SharedNames

  class Block {
    product_column
    height
  }
  class FuelFeed {
    belt_column
    row
  }
  class RawBelt {
    column
    row
  }
  class NewEntity {
    name
    direction
    recipe
    type
  }
  class Entity {
    entity_number
  }
  class Position {
    x
    y
  }
  class Tile {
    x
    y
  }
  class Generated {
    description
    message
  }

  Entity --|> NewEntity
  NewEntity *-- Position
  Entity ..> Tile : grid.top_left_tile
  Block *-- Entity : entities and poles
  Block *-- RawBelt : raw_belts
  Block *-- FuelFeed : fuel_feeds
  FuelFeed --> StageLayout : stage
  RawBelt --> StageLayout : stage
  RawBelt --> RawSupplier : stage
  Generated *-- Entity : entities
  StageLayout ..> Block : layout.chain_block

  class Builder
  class Geometry {
    size
    input_belt_column
    machine_column
    output_belt_column
    output_winds
    has_pole_rows
  }
  class Place {
    origin
    first_row
    feeds_next
  }
  class Poles
  class SharedBelt {
    end_row
    direction
  }

  Builder *-- Geometry
  Builder *-- Names
  Builder *-- Poles
  Builder *-- SharedBelt
  Builder *-- Entity : entities
  Poles o-- Entity : input and output
  Place ..> Geometry : geometry_of
  Shape ..> Geometry : geometry_of
```

`Builder`, `Geometry`, `Place`, `Poles` and `SharedBelt` live inside `layout.lua`: one `Builder` lays out one column, and `rows.lua` calls it once per column.

### 3c. The columns, and the belts that come in (rows, feeds, inputs, poles)

```mermaid
classDiagram
  direction LR

  class Column {
    kind
    belt
    index
    x0
    x_source
    top
    bottom
    drop_x
  }
  class Arc {
    head
    gadget
    rows
    row
  }
  class RawRun {
    x
    row
  }

  Column o-- Column : children
  Column --> Column : parent
  Column *-- Arc : arc
  Column --> Block : block
  Column o-- StageLayout : stages
  Column o-- FeedLeaf : fuel_leaves
  Column --> Feed : feed, a chain or a raw column
  RawRun --> Column

  class FeedLeaf {
    index
    drop_x
  }
  class Trunk {
    items
    mixed
    demand
    first
    last
    number
    row
    east
  }
  class Feeder {
    role
    flow
    row
  }
  class PureBelt {
    item
    bus
    column
    entry
    last
  }
  class FeedPlan

  FeedLeaf <|.. Column : a leaf column plays this role
  FeedLeaf *-- Feed
  FeedLeaf --> Column : owner, for the fuel of a stage in a chain
  FeedLeaf --> FuelFeed : fuel
  Trunk o-- FeedLeaf : leaves
  Feeder --> Trunk
  PureBelt o-- Feeder : feeders
  FeedPlan *-- Trunk : trunks
  FeedPlan *-- PureBelt : belts and buses

  class Band
  class Input {
    x
    y
    item
  }

  Band ..> FeedPlan : inputs.lay
  Band o-- NewEntity : entities
  Band o-- Input : supplies

  class PolePair {
    distance
  }
  class PoleBridge {
    taken
    pole
  }

  PolePair --> Entity : from and to
  PoleBridge o-- Entity : entities
```

The order of the work in `rows.build_pure` is: columns are made (`Column`), the leaves are handed to `feeds.plan` (`FeedPlan`), the columns are placed after the band, `inputs.lay` draws the band (`Band`) and says where each leaf's belt ends, the columns get their rows from that, and `poles.join` wires the poles with a `PoleBridge` for the gaps.

## 4. Where each type is defined

| Where | Types |
|---|---|
| `scripts/types.lua` (cross module) | SharedNames, Names, MachineChoice, Production, ChainStage, RecipeItem, Recipe, InserterLimits, StageRequest, ChainRequest, StageTree, TreeRequest, PlanTree, PlanRequest, PlanInput, Plan, Position, Tile, Wire, Shape, StageLayout, RawSupplier, Feed, FeedItem, BlockOptions, Block, FuelFeed, RawBelt, NewEntity, Entity, InputOptions, Input, PoleBridge, FeedLeaf, Trunk, Feeder, PureBelt, FeedPlan, Generated; the aliases ChainReason, RecipeLookup, PlanReason |
| `scripts/config.lua` | Config |
| `scripts/generator.lua` | EnergySource, Candidate, StageData, Job, PlannedStage, Demand |
| `scripts/planner.lua` | Belts, InputInserters, MachineRates, StageContext, Sizes |
| `scripts/chain.lua` | MadeIngredient |
| `scripts/layout.lua` | Geometry, Place, Poles, SharedBelt, Builder |
| `scripts/rows.lua` | Arc, Column, RawRun |
| `scripts/inputs.lua` | Band |
| `scripts/poles.lua` | PolePair |
| `scripts/messages.lua` | RawAmount, StepSummary |
