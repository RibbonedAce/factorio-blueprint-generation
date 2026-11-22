# Blueprint Generation

A Factorio 2.1 mod that builds blueprints for you. Pick an item and how many you want per minute, and the mod puts a ready-to-place blueprint on your cursor. The blueprint carries raw materials from a belt into machines, through every intermediate product on the way, and the finished product onto an output belt: ores in, final product out.

Status: early development.

## How to use it

1. Click the "Generate blueprint" button in the shortcut bar.
2. Choose a recipe in the game's own picker, which offers the recipes you have unlocked that the mod builds, and enter a rate: items per minute, or units of the fluid per minute.
3. Click Generate. The blueprint appears on your cursor. It is temporary, like a blueprint taken from the library: it takes no inventory space, and it disappears if you put it away without placing it. Place it, put the raw items on the input belts (and connect the pipes for any fluid), and connect its poles to your power network.

The message tells you what the blueprint makes a minute and how much of each raw item it uses. With the splitter and the underground belt researched, it also names the belts to bring in, from the top of the blueprint down.

## Recipes

- Arithmetic combinator
- Assembling machine 1
- Assembling machine 2
- Automation science pack
- Barrel
- Basic oil processing
- Battery
- Big electric pole
- Boiler
- Burner inserter
- Burner mining drill
- Car
- Cargo wagon
- Chemical plant
- Concrete
- Constant combinator
- Copper cable
- Copper plate
- Decider combinator
- Defender capsule
- Display panel
- Electric mining drill
- Electronic circuit
- Engine unit
- Explosives
- Fast inserter
- Fast splitter
- Fast transport belt
- Fast underground belt
- Firearm magazine
- Flamethrower
- Flamethrower turret
- Fluid wagon
- Gate
- Grenade
- Gun turret
- Hazard concrete
- Heavy armor
- Inserter
- Iron chest
- Iron gear wheel
- Iron plate
- Iron stick
- Lab
- Landfill
- Light armor
- Locomotive
- Logistic science pack
- Long handed inserter
- Medium electric pole
- Military science pack
- Offshore pump
- Oil refinery
- Piercing rounds magazine
- Pipe
- Pipe to ground
- Plastic bar
- Power switch
- Programmable speaker
- Pump
- Pumpjack
- Radar
- Rail
- Rail chain signal
- Rail signal
- Refined concrete
- Refined hazard concrete
- Repair pack
- Rocket launcher
- Shotgun
- Shotgun shell
- Small electric pole
- Small lamp
- Solar panel
- Solid fuel from petroleum gas
- Splitter
- Steam engine
- Steam turbine
- Steel chest
- Steel furnace
- Steel plate
- Stone brick
- Stone furnace
- Stone wall
- Storage tank
- Submachine gun
- Sulfur
- Sulfuric acid
- Train stop
- Transport belt
- Underground belt
- Wooden chest

## Current limitations

- A belt lane carries 450 items a minute, so the rate of a blueprint is capped. Ask for more and the message tells you the most it makes.
- The rate is rounded up to whole machines, so a blueprint can make a little more than you asked for.
- You supply the inputs (raw items on belts, crude oil and water by pipe) and the power: the blueprint contains no mining and no power plant, and its poles are not connected to your network.
- Machines are 2 x 2 or 3 x 3, and run on electricity or burn fuel. A machine that runs on heat or a fluid is refused.
- Only the recipes in the list above, and only those you have unlocked.
- Machines are chosen for each recipe category, not for each item.
- Most layouts are checked by the tests, not yet in the game.

## More

How the blueprints are laid out and what limits each recipe: [DEVELOPMENT.md](DEVELOPMENT.md). What has been built and what is still open: [.agents/project-status.md](.agents/project-status.md) and [.agents/feature-log.md](.agents/feature-log.md).
