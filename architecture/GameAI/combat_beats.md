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

## Engagement Group Fallback

#87 does not solve fighter pairing or engagement grouping.

Until #88 creates real engagement groups, BattleSim emits one deterministic fallback group per encounter:

```gdscript
engagement_group_id = "%s:group:main" % encounter_id
```

#88 replaces this fallback with real data-first pairings and engagement groups. Projection and scheduler code can still rely on every new beat having a stable group key now.

## Known #87 Gaps

BattleSim does not yet populate these optional projection fields with meaningful data:

- weapon/equipment hints
- wound target
- life-state result per beat
- slot, position, or facing hints
- real engagement group or fighter pairing assignments

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
