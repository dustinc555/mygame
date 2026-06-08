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
  attacker_slot_id
  defender_slot_id
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
- `attacker_slot_id`
- `defender_slot_id`
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

## #89 Combat Slots

BattleSim emits `battle_result["combat_slots"]` as top-level projection-only slot records keyed by `slot_id`.

Engagement groups reference slots without duplicating slot data:

```text
EngagementGroup
  combat_slot_ids
```

Combat beats reference slots for presentation lookup:

```text
CombatBeat
  attacker_slot_id
  defender_slot_id
```

Slot records use this shape:

```text
CombatSlot
  slot_id
  encounter_id
  engagement_group_id
  occupant_kind
  occupant_id
  member_id
  squad_id
  side
  formation_role
  group_center
  local_offset
  world_position_hint
  facing_yaw
  facing_target_slot_id
  presentation_only
```

`group_center` and `local_offset` are the canonical formation data. `world_position_hint` is derived as `group_center + local_offset` for convenience.

`occupant_kind` is `member` for member-level groups and `squad_proxy` for squad fallback groups. Squad fallback groups emit two proxy slots so projection/debug systems still have a place to show abstract combat.

Combat slots are presentation hints only. They do not decide combat outcomes, target selection, movement truth, or actor behavior.

Current slotting strategy:

- Place each engagement group on a deterministic encounter-local grid.
- Use face-off offsets for 1v1 groups.
- Use bounded surround offsets for 1v2 / 1v3 groups.
- Use separate group centers for 5v5 and 50v50 clusters.
- Use O(G + S) slot assignment over groups and slots, not all-pairs spacing.

## #90 Playback Schedule

`CombatBeatPlaybackScheduler` is a data-only presentation helper. It consumes BattleSim beats, engagement groups, and combat slots, then returns `battle_result["combat_schedule"]`.

BattleSim owns combat truth. The scheduler owns presentation timing only.

Schedule records use seconds for playback timing:

```text
CombatSchedule
  events
  summarized_beats
  detailed_beat_ids
  summarized_beat_ids
  detailed_beat_limit
  source_beat_count
  detailed_beat_count
  summarized_beat_count
  event_count
  presentation_only
```

Detailed event records use this shape:

```text
CombatScheduleEvent
  event_id
  beat_id
  encounter_id
  engagement_group_id
  event_type
  attacker_member_id
  defender_member_id
  attacker_squad_id
  defender_squad_id
  attacker_slot_id
  defender_slot_id
  start_time
  duration
  importance
  presentation_only
```

Default detailed sequence per beat:

- `move_to_slot`
- `face_target`
- `attack`
- `reaction`

Default scheduling policy:

- Use `detailed_beat_limit = 32` unless config overrides it.
- Select high/critical/important beats first.
- Fill remaining detail budget with earliest normal beats.
- Schedule selected beats on per-engagement-group presentation tracks so different groups can interleave.
- Summarize non-selected beats in `summarized_beats`; original beats remain in `battle_result["beats"]`.
- Use O(B log B + E) scheduling over beats and events, not per-frame queues or scene scans.

The schedule never changes combat outcomes. It is presentation-only timing data for later projection systems.

## #92 Performance Gates

Combat projection has explicit metrics and caps before full 50v50 projection work.

`CombatBeatPlaybackScheduler` reports scheduler gate data in `battle_result["combat_schedule"]`:

```text
CombatSchedule
  detailed_event_count
  skipped_event_count
  summarized_event_count
  detailed_beat_limit
  scheduled_event_count
  total_beat_count
```

`detailed_beat_limit` defaults to `32`. High/critical/important beats are prioritized first, then earliest normal beats fill remaining detail budget. Skipped/summarized beats remain in `battle_result["beats"]`; only detailed presentation events are capped.

`WorldActorProjectionController` exposes projection gate metrics through `get_projection_performance_metrics()`:

```text
ProjectionPerformanceMetrics
  projected_actor_count
  realized_actor_count
  visible_actor_count
  max_projected_actor_count
  projection_cap_active
  skipped_projection_count
  eligible_projection_count
  unsupported_projection_count
```

`max_projected_actor_count = 0` means unlimited and preserves current behavior. Values above `0` cap projected actors deterministically by stable actor ID. Hitting the cap skips/defer projection only; it does not mutate GECS truth.

These gates are inspectable guardrails, not a complete pooling/LOD implementation. Projection may simplify presentation, but GECS/BattleSim outcomes do not change.

## #91 Continuity Snapshot

`CombatProjectionContinuityBuilder` is a data-only helper for offscreen-to-onscreen continuity. It consumes stored encounter, BattleSim, CombatBeat, schedule, engagement group, combat slot, and current member/squad records, then returns `battle_result["combat_continuity"]`.

Continuity snapshots let projection join or inspect a fight without restarting, rerolling, or contradicting the stored combat result.

Continuity records use this shape:

```text
CombatContinuity
  encounter_id
  status
  projection_state
  member_states
  active_group_ids
  active_slot_ids
  replay_event_ids
  summarized_event_ids
  aftermath_member_ids
  recent_replay_event_limit
  source_event_count
  presentation_only
```

`projection_state` is:

- `active` for engaged/resolving fights.
- `aftermath` for resolved fights.
- `inactive` otherwise.

Resolved fights mostly show aftermath. They replay only recent high/critical/important schedule events, capped by `recent_replay_event_limit = 16`, and summarize the rest. Active/resolving fights expose active engagement groups, active slots, current member states, and replayable recent events so projection can join midstream later.

`member_states` are keyed by stable member IDs and contain member/actor/squad IDs plus current life/vital state. They must not contain `Node`, `NodePath`, scene actor references, or UI references.

Continuity is presentation-only. It does not mutate GECS, rerun BattleSim, choose targets, move actors, or spawn projections.

## Known #87 Gaps

BattleSim does not yet populate these optional projection fields with meaningful data:

- weapon/equipment hints
- wound target
- life-state result per beat
- projection movement or interpolation toward slots
- animation player or visual actor event consumption
- visual realization/unrealization driven from continuity snapshots
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
