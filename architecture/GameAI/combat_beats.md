# Combat Beats

Combat is outcome-first.

## Rule

```text
The sword swing does not cause damage.
GECS decides damage.
The sword swing visualizes that decision.
```

## Beat Record

```text
CombatBeat
  beat_id
  beat_index
  encounter_id
  engagement_group_id
  tick
  presentation_tick
  round
  attacker_id
  defender_id
  attacker_member_id
  defender_member_id
  attacker_actor_id
  defender_actor_id
  attacker_squad_id
  defender_squad_id
  action
  result
  damage
  wound_target
  stamina_delta
  position_hint
  animation_hint
  importance
```

`attacker_id` and `defender_id` are projection/display combatant IDs. When member data exists they match the member IDs. When BattleSim only has squad fallback data they fall back to squad IDs.

`attacker_member_id` and `defender_member_id` are optional. They are set only when the beat was generated from member-level combat profiles.

`tick` is the GECS/BattleSim tick that produced the result. `presentation_tick` is a stable ordering hint for playback. Projection may stretch or compress visual time, but it must not change the recorded result.

## #87 Projection Contract

New BattleSim-generated beats must include:

- `beat_id`
- `beat_index`
- `encounter_id`
- `engagement_group_id`
- `tick`
- `presentation_tick`
- `round`
- `attacker_squad_id`
- `defender_squad_id`
- `attacker_id`
- `defender_id`
- `action`
- `result`
- `damage`
- `importance`
- `summary`

Optional member-level fields:

- `attacker_member_id`
- `defender_member_id`
- `attacker_actor_id`
- `defender_actor_id`
- `attacker_stable_id`
- `defender_stable_id`

Missing optional member fields mean BattleSim used squad-level fallback data for that side. Projection must handle that without inventing member truth.

## #88 Engagement Groups

BattleSim emits `battle_result["engagement_groups"]` as data-first presentation grouping. Actors do not choose targets and projected actors do not scan for enemies.

Engagement group records use this shape:

```text
EngagementGroup
  engagement_group_id
  encounter_id
  group_index
  group_role
  strategy
  max_group_size
  side_a_squad_id
  side_b_squad_id
  side_a_primary_id
  side_b_primary_id
  side_a_member_ids
  side_b_member_ids
  support_member_ids
  reserve_member_ids
```

`side_a_member_ids` and `side_b_member_ids` are the side-owned assigned members for the group. `support_member_ids` and `reserve_member_ids` classify non-primary members inside those side assignments.

Group IDs are stable per encounter:

```gdscript
engagement_group_id = "%s:group:%03d" % [encounter_id, group_index]
```

New beats reference an existing `engagement_group_id`. Member-level fights use deterministic groups. Squad-fallback fights still emit one fallback group and keep member IDs empty.

Current grouping strategy:

- Sort living participants deterministically by combat score, then stable member ID.
- Create paired groups with one primary from each side when possible.
- Keep group size bounded by `max_group_size = 4`.
- Assign extras as support into existing groups while room remains.
- Assign remaining extras into reserve groups.
- Use O(N log N) sorting plus O(N) assignment, not all-vs-all matching.

## Known #87 Gaps

BattleSim does not yet populate these optional projection fields with meaningful data:

- weapon/equipment hints
- wound target
- life-state result per beat
- slot, position, or facing hints
- tactical target selection beyond deterministic engagement groups

Those fields remain optional until the relevant systems produce durable result data. Projection must not invent them as truth.

## Results

- hit.
- block.
- dodge.
- miss.
- stagger.
- knockdown.
- death.

## Flow

```text
PuppetMaster assigns pairings.
GECS combat system resolves beats.
PuppetMaster stages beats.
RenderProjection plays animation, audio, VFX, and interpolation.
```

## Visible Fight

For a player-watched 5v5 fight, every important strike should map to a beat record.

```text
tick 120: bull_01 charges mira, result dodge
tick 132: mira slashes bull_01, result hit, damage 18
tick 150: bull_02 hits tomas, result block
```

The player should feel the fight, but the truth is still numbers first.

## Throttled Fight

When presentation cost is too high:

- Combine minor beats.
- Hide low-importance reactions.
- Show only decisive hits, blocks, wounds, and deaths.
- Collapse background actors into clusters.

The beat transcript and final GECS outcome do not change.
