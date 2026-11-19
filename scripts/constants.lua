-- scripts/constants.lua
-- Numbers that two or more modules have to agree on, each written once. Pure: no game access.

local constants = {}

-- Two numbers this close are equal. Amounts are sums of fractions (3.2 cannot be stored exactly), so what should be
-- 1 can come out as 1.0000000000000002 and round up to a whole extra machine, or a lane that is exactly full can add up
-- to a hair more than it carries. The planner, the feeds, the layout and the lamps read their numbers with it.
constants.EPSILON = 1e-9

-- A belt has two lanes, and one item rides each.
constants.LANES_PER_BELT = 2

-- An inserter drops items on the far lane of a belt that runs across its line, so the output inserters of a machine fill
-- only one lane of a plain output belt. The layout winds the belt for a machine of this size with exactly this many
-- output inserters, so that each fills a different lane and the product travels on both; the planner counts on it.
constants.WINDING_MACHINE_SIZE = 3
constants.WINDING_OUTPUT_INSERTERS = 2

return constants
