# World Simulation Hooks

Future concept work for systems that make settlements, factions, roads, jobs, and NPCs feel connected. These ideas pair well with `ideas/settlement_food_pressure.md`.

## Settlement Job Board

Settlements can expose jobs based on their current state and problems.

Examples:

- Food shortage creates caravan, hunting, or grain-buying jobs.
- Bandit pressure creates guard, bounty, patrol, or rescue jobs.
- Injured workers create medicine delivery or healer escort jobs.
- Low labor creates mining, hauling, farming, or construction jobs.
- Debt or trade trouble creates negotiation, courier, or collection jobs.

This gives the player clear reasons to travel and lets local problems become gameplay instead of static quest text.

## Faction Reputation

Player actions can change local and faction-level trust.

Possible reputation effects:

- Better or worse prices.
- Access to better jobs.
- Permission to sleep, trade, recruit, or enter restricted areas.
- Guards becoming protective, suspicious, or hostile.
- Villagers volunteering information or refusing to help.

Reputation should respond to practical actions: guarding caravans, saving citizens, stealing, attacking locals, completing jobs, abandoning escorts, or delivering scarce supplies.

## Road Danger System

Routes between settlements can have danger levels.

Possible inputs:

- Bandit activity.
- Wildlife density.
- Patrol coverage.
- Recent caravan losses.
- Faction war or road blockades.
- Weather or environmental hazards later.

Road danger can drive ambushes, patrols, escort job value, caravan losses, rumor content, and settlement shortages.

## Rumors

Bars, travelers, guards, merchants, and refugees can surface world information through rumors.

Examples:

- "North village is running out of food."
- "A caravan vanished near the copper road."
- "The guard captain pays well for escorts."
- "Bandits are avoiding the old bridge since the patrols increased."
- "A miner found something strange in the hills."

Rumors make bars and social spaces useful without requiring every lead to be a formal quest.

## Prisoner And Rescue Gameplay

Characters can become gameplay objects after combat instead of only winning or dying.

Possible hooks:

- Capture downed enemies.
- Carry prisoners to a cell, bed, or town authority.
- Rescue captured allies or villagers.
- Ransom prisoners between factions.
- Recruit rescued or spared NPCs.
- Create consequences for mistreating prisoners.

This fits existing carry, downed, bed, faction, and job systems.

## Settlement State Changes

Settlements can move between visible states over time.

Example states:

- Well supplied.
- Hungry.
- Unsafe.
- Prosperous.
- Hostile.
- Occupied.
- Abandoned.
- Recovering.

State changes should affect dialogue, prices, jobs, guard behavior, services, and visual activity. This lets one location feel different over time without needing a new map.

## Named NPC Problems

Named NPCs can anchor local problems in human terms.

Examples:

- A barkeeper needs food delivered before the bar closes.
- A guard is worried about a missing patrol.
- A miner owes debt to a merchant.
- A refugee needs escort to a safer settlement.
- A healer lacks bandages or medicine.
- A farmer suspects someone is stealing from the storehouse.

These should connect to real systems where possible, such as food pressure, road danger, reputation, inventory, or faction conflict.

## Hauling And Logistics Jobs

The player can move useful goods between people, containers, settlements, and roads.

Possible cargo:

- Food.
- Ore.
- Medicine.
- Weapons.
- Building supplies.
- Trade goods.
- Prisoners or rescued NPCs.

Logistics jobs fit naturally with party movement, containers, jobs, trading, caravans, food pressure, and settlement state.

## Strong Combined Direction

The strongest near-term combination is settlement state plus a job board. Settlement state creates the reason jobs exist, and the job board gives the player a clean way to discover and act on those needs.

Food pressure, road danger, reputation, rumors, and logistics can then feed into that same loop instead of becoming isolated features.
