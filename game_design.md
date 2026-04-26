# Game Design

## Core
- This is an open-world game.
- The player controls a party, not a single character.
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
- Only one character inventory window is open at a time.
- Right-clicking a character and choosing `Inventory` opens that character's inventory.
- If a backpack is equipped, an `Open Backpack` button opens its inventory.
- Items can be dragged between nearby inventories to transfer.

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

## Out Of Scope For Now
- Pathfinding details.
- Combat details.
- Most right-click actions beyond the currently defined ones.

## Tuning
- Global constants such as heal rate, encumbrance effect, bleed factor, and damage multipliers should live in one shared config file.
