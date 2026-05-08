# Settlement Food Pressure

Future concept work for making hunger matter at the town/faction level without committing to full per-NPC hunger simulation everywhere.

## Core Idea

Hunger can exist as real world pressure before every NPC needs an individual hunger meter. Villages, towns, and factions can track aggregate food needs while individual NPCs stay scripted or ambient unless they become important to gameplay.

## Settlement-Level Hunger

Settlements could track values like:

- `food_stockpile`: available food supply.
- `daily_food_demand`: how much the population consumes over time.
- `food_pressure`: derived scarcity level, from well supplied to starving.
- `morale`: affected by food security, danger, work, and recent events.
- `trade_need`: whether the settlement is seeking food imports.

This lets a village be genuinely hungry without simulating breakfast for every background NPC.

## NPC Simulation Levels

NPC hunger can remain flexible:

- Background town NPCs can have scripted eating, sleeping, work, and idle routines.
- Important NPCs can have real individual hunger when the player can affect them directly.
- Recruits, prisoners, hired workers, companions, refugees, or story NPCs can be promoted to full needs simulation.
- Player faction members should keep visible, actionable hunger.

The design rule: if the player can meaningfully manage, feed, starve, recruit, rescue, employ, or imprison an NPC, individual hunger becomes worth simulating.

## Gameplay Hooks

Food pressure can create jobs and missions:

- Guard a food caravan to a hungry village.
- Buy grain from a surplus town and deliver it.
- Escort hunters or foragers.
- Recover stolen supplies.
- Defend a storehouse from raiders.
- Raid bandits who are blocking trade routes.
- Negotiate food shipments through trade or faction reputation.

Success should visibly improve the destination settlement. Failure should create consequences.

## Visible Consequences

Well supplied settlements could have:

- Better morale.
- Stable prices.
- More available recruits.
- More reliable guards and workers.
- Normal town schedules.

Food-starved settlements could show:

- Hungry dialogue.
- Higher food prices.
- Closed services or reduced production.
- Weaker guards.
- Theft, desertion, refugees, or desperation.
- More dangerous jobs and faction requests.

## Why This Works

This keeps the door open for fully simulated NPC towns later while still making hunger real now. Hunger becomes a source of world events and player decisions, not just a meter attached to every actor.
