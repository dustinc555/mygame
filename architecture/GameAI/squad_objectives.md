# Squad Objectives

Jobs, patrols, raids, guard duty, service work, and travel are squad objectives.

## Rule

```text
No actor-owned job slots.
Work is a squad objective.
```

Player accepting a job means temporarily joining the relevant squad or objective.

## Squad Record

```text
Squad
  squad_id
  faction_id
  member_ids
  objective_id
  location
  route
  morale
  supplies
  significance_tier
```

## Objective Record

```text
SquadObjective
  objective_id
  type
  owner_faction_id
  target_refs
  role_requirements
  reward_rules
  completion_rules
  failure_rules
  schedule_window
```

## Examples

- `guard_area`: hold a venue, road gate, jail, or camp.
- `mine_haul`: extract resources and move output.
- `serve_bar`: handle customer service as a venue objective.
- `patrol`: move between points and observe.
- `escort`: move with a protected squad or caravan.
- `raid`: travel, threaten, steal, fight, retreat.
- `defend`: respond to local pressure.

## Player Job Flow

```text
Player accepts bar work.
GECS adds player actor to TavernServiceSquad objective.
PuppetMaster respects explicit player commands.
If idle, PuppetMaster uses behavior policy to stage service work.
Rewards settle from objective state.
```

## Why This Scales

One squad objective can control many members. The simulation updates objective state and member summaries instead of ticking a separate brain per worker.
