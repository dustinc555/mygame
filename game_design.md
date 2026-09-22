# Game Design

## Core
- This is an open-world game.
- Humanoids share one common simulation base.
- The player controls a party, not a single character.
- A faction contains squads.
- The HUD shows the active squad of the player faction.
- Non-party characters cannot be selected.
- Group commands apply to all selected party members.

## Camera
- The camera is free by default.
- `WASD` moves the free camera, middle mouse orbits, and mouse wheel zooms.
- Double-clicking a party member or portrait focuses that character.
- Focus mode locks the camera to that character.
- Holding middle mouse orbits 360 around the focused character.
- If the focused character moves, the camera follows them.
- Pressing `W`, `A`, `S`, or `D` exits focus mode and returns to free camera.

## Party UI And Selection
- A row of square portraits sits at the bottom of the screen.
- Single-click selects one party member.
- `Alt` + click adds party members to the selection.
- Drag selection on the map selects only party members.
- Double-clicking a portrait or party member focuses that one character.
- Left-clicking empty ground clears selection.

## Movement And Actions
- Right-clicking the ground sends all selected party members to that spot.
- Selected characters stay selected after moving.
- Right-clicking a character opens a context menu.
- For now, right-click actions are `Inventory`, `Carry`, and `Heal` when valid.

## Inventory And Weight
- Each character has a small personal inventory.
- Each character has one backpack slot.
- Planned equipment slots are chest, legs, gloves, boots, helmet, and backpack.
- Equipped items count toward carry weight.
- Items use both carry weight and inventory space.
- Backpack items still take inventory space, but apply reduced carry weight by a configurable factor.
- Multiple inventory windows can be open at once.
- Right-clicking a character and choosing `Inventory` opens that character's inventory.
- If a backpack is equipped, an `Open Backpack` button opens its inventory.
- Items can be dragged between nearby inventories to transfer.
- Containers have configurable inventory shapes by type.
- Opening a container also opens the acting character's inventory unless it is already open.
- Currency is an item.
- `SILVER` is stackable up to `100` per stack.

## Containers
- Author the physical furniture first (barrel, dark barrel, chest, crate or sack), then choose its Container Type in the Inspector or Facility → Containers: General, Seeds, Tools, Food, Materials or Weapons. Purpose controls admission, not the mesh, inventory dimensions, identity or ownership. Changing it never discards existing contents.
- Purpose-specific legacy scenes remain loadable for authored worlds but are not separate furniture catalog entries. The old primitive Barrel Container now uses the real barrel mesh while retaining its original inventory capacity and stable references.
- Containers can be opened by any party member or NPC.
- Containers default to unlocked, but can be locked.
- Right-clicking an unlocked container shows `Open`.
- Right-clicking a locked container shows `Unlock`.
- If multiple selected party members are ordered to open a container, the first to reach it interacts.
- Locked containers show `Locked` when an open attempt fails.
- Lockpicking is stubbed for now.

## Health And Recovery
- Characters have HP and blood.
- HP damage and blood loss are separate.
- Blood loss comes from wounds and bleeding, not blunt damage alone.
- If blood gets too low, the character becomes unconscious.
- If all blood is lost, the character dies.
- Healing is intentionally slow.
- Sleeping heals at `x5`.
- Unconscious recovery heals at `x1.5`.
- Sleeping characters may wake on their own.
- Characters knocked unconscious in combat cannot wake until healed.

## Carry, Beds, And Healing
- `Carry` only applies to sleeping or unconscious targets.
- A carried character adds their weight to the carrier naturally.
- `Place in bed` only appears if a selected party member is carrying someone.
- If multiple selected carriers can do it, the first one to reach the bed does it.
- Placing a character in bed switches them to sleep-rate recovery.
- `Heal` appears for wounded or bleeding targets.
- `Heal` makes the acting character move into close range, about 1 meter / 3 feet, then use bandages.
- Bandages come from the acting character's inventory and stop bleeding.

## Skills
- Skills improve quickly at first, then progressively slower.
- Example skills include mining, blacksmithing, running, sneaking, swords, axes, maces, dexterity, and strength.

## Hunger
- Hunger is `0..100`.
- Hunger drains slowly when enabled for a character.
- Hunger drain rate is configurable per character.
- Food restores hunger when eaten.

## NPCs And Trade
- Player-controlled party members are humanoids in the player faction's active squad.
- Other humanoids use the same base simulation, but can act through AI or role logic.
- Merchants are humanoid NPCs with trade rules and finite inventory space.
- Right-clicking a merchant shows `Attack` and `Trade`.
- `Attack` is stubbed for now.
- `Trade` is resolved by the first selected party member to reach the merchant.
- Party-to-party transfer is normal item transfer.
- Merchant trade uses configured buy and sell prices per merchant.

### General Trader And Shop Authoring
- Facility Sign is one placeable object with a Sign Type dropdown: Auto, Tavern, Food, Weapons, Armor, Potions or Blacksmith. Auto resolves from the owning facility when mounted (shops use Food); a Sign Scene Override takes precedence. Inspector changes update only that sign, work with undo, and persist into the game.
- Rugs preserve the vendor geometry and combine the cloth atlas's UV1 fabric with its UV2 motif. Shared fabric/pattern colors are editable in `features/world/projection/props/materials/rug.tres`; vendor originals remain untouched.
- Add Facility → Shop places a reusable shop; it is not automatically added to any town. The bar's neutral building shell is reused, not its inn services.
- The trader works at a discovered counter from 08:00 to 20:00 and lives upstairs. Employment and residence are separate relationships of the same persistent GECS character. Missing furniture must not spawn hidden replacements.
- General traders buy any tradable non-currency item. Initial stock focuses on scrap, materials, ore, tools, seeds, and eggplants. Other presets specialize in scrap, weapons, armor, or clothing.
- The Facility dock's Shop tab selects a preset and provides searchable per-item target quantity and Replenishes controls. Overrides are local to the placed shop, not edits to shared presets. Prices and defaults remain editable resources.
- Preset resources live under `features/settlements/resources/merchants/`. Their default buy/sell prices currently start at 1/2 silver per item; stock entries may override those prices. These are explicit balance settings, not an item-value simulation. Scheduled shops recheck Jobs duty at transaction time, so leaving a trade window open cannot extend opening hours.
- Stock, silver, and the initialized business policy belong to the character. Changing town, workplace, or scene projection does not create a new person or grant stock again. A different replacement merchant does not inherit the previous merchant's goods automatically.
- World simulation currently supplies replenishing goods every three game days at 08:00, with editable cadence. Refill only deficits up to target; preserve player-sold excess goods and unique non-replenishing items. Saved empty inventory is initialized, not an invitation to seed again. Goods replenishment never resets silver.
- Authoring defaults apply when a business is first initialized; existing saved traders retain their inventory and durable policy.
- Furniture catalog props reuse the original vendor models through scenes in `features/world/projection/props/furniture/`. Cabinet, Dresser 1, Workbench Drawers, both Nightstands, both Bookcases, Shelf Small, Shelf Arch, Metal Crate and Empty Farm Crate are real containers. Cabinet defaults to an 8×5 inventory, Dresser 1 to 7×5, and Nightstand Drawer to 4×3; capacity and accepted container type remain Inspector-editable. Open shelving cannot lock. Empty containers do not create merchant stock.
- Rope 1/2/3 are editor-placeable item displays backed by collectible, persistent inventory items, not uncollectible scenery. Desk books and candles use the same existing item-slot system. Peg Rack is wall decoration. Canyon's authored shop separates its downstairs counter/storage/display space from the proprietor's upstairs bed, nightstand, dresser, cabinet and writing desk; loose goods retain Canyonite ownership. The shop furnishing recipe also includes cabinets and small shelves in its ground-floor container pool.

### Intended Economy And Property Direction (Not In Current Shop Scope)
- Significant characters are independent world entities, not disposable roles owned by a town. A canyonite may travel, move home, establish a different shop, offer jobs, or organize a caravan while retaining identity and property.
- Trader NPCs will do business with each other and dispatch caravans carrying real inventory. Those deliveries should replace abstract cadence supply at the same character-owned inventory boundary, not introduce another wallet or trade system. Caravan simulation is not part of the initial shop implementation.
- Characters/entities own buildings within towns; town jurisdiction is distinct from ownership. A renewable lease functions as tax paid to the ruler. The ruler can revoke the holding even during a lease.
- NPC lease renewal and taxation are handwaved for now. Do not add lease expiry, taxation, revocation, or autonomous relocation merely to ship a placeable shop. Money-replenishment policy remains undecided.

## Out Of Scope For Now
- Pathfinding details.
- Combat details.
- Most right-click actions beyond the currently defined ones.

## Tuning
- Global constants such as heal rate, encumbrance effect, bleed factor, and damage multipliers should live in one shared config file.
