# Lockpicking

Cages, locking containers and doors use the same carried-tool work system. A
character needs a usable lockpick in their own inventory and sufficient skill
for the lock. They walk to the lock, face it, put away held equipment visually,
and work with the actual pick model. Picking is not a weapon equipment slot.

## Player behavior

- **Pick Lock (Careful)** takes longer with fewer setbacks.
- **Pick Lock (Rushed)** works faster but makes more mistakes and wears picks faster.
- The ordinary gray work bar times each pass/fail attempt, using the same HUD
  as mining. A brass lock symbol beside it sets and briefly lights a gold pin
  only after a pass; there is no second progress bar.
  Three passes unlock a fresh lock by default. A failed attempt leaves earned
  progress unchanged and damages the exact pick being used. The inventory
  tooltip shows that pick's remaining condition.
- Work cuts the existing `Fixing_Kneeling` repair animation into a one-time
  descent, a seamless kneeling hand-work loop and a one-time rise. Pass/fail
  updates never restart the animation. Move orders wait for the short rise;
  combat actions, incapacitation and custody can take over immediately.
  No procedural arm pose or vendor animation is modified.
- Quality is resilience, not an extra success roll: flimsy / standard / fine
  picks have 30 / 60 / 120 condition. The flimsy tool is a bare rusted strip;
  standard and fine tools have wrapped grips. All occupy one by two bag cells.
- At zero condition the used pick is removed. Work stops instead of silently
  consuming the next pick. A new order chooses the carried pick with the most
  remaining condition. Success does not consume the pick.
- Moving, fighting, losing the tool, being carried or losing the target cancels
  the action. Existing progress, partial check time and check sequence remain.
  Restarting cannot reroll an imminent check. Another character can resume.
- Pausing/speed changes follow the normal game clock. Only active sessions tick.
- Picking a cage releases its occupants; it does not pardon a warrant or return
  confiscated property. Tampering checks nearby witnesses throughout active work,
  using normal sight cones, wall occlusion, lighting and stealth. A witness arriving
  after work starts can report it before the next pass or slip. The existing law
  system records one crime per witnessed work session and dispatches its guard
  response. Authorized owners are exempt. Proximity or a slip without sight is
  not proof of the offender.
- Mira and Tomas's authored starting inventories each contain a standard pick.
  This seeds new characters, not extra copies every time a save is loaded.

## Designer controls

### Successful unlock sound

In Godot's FileSystem, open
`res://features/lockpicking/resources/unlock_success_sound.tres`.
**Paths** lists the five adopted vendor recordings whose names contain `unlock`
or `open` (including `opening`). **Volume Db** sets their shared gain (default
-6 dB); pitch is fixed at 1.0. **Playback → Max Distance M** (45 m) and
**Unit Size M** (6 m) control positional cutoff and attenuation; **Max Voices**
(8) caps simultaneous unlock sounds, replacing the oldest when full.
Saved edits apply on the next game launch. Runtime resource edits apply to the
next unlock, not an already-playing voice.

One random recording plays at the lock contact point after a real locked-to-
unlocked success. Immediate repeats are avoided. This covers key/authorized
door use, free exit, scheduled door unlocking, and completed picking of doors,
containers, prisoner lockers and cages. Failed/partial/cancelled work, ordinary
opening, registration, initial business-hours configuration and save restoration
do not play it. Door movement sounds remain separate and unchanged.

`DoorController.door_unlocked` owns door success; `LockpickingController.object_unlocked`
owns non-door success. The module-installed `UnlockAudioController` consumes both
without double-playing picked doors. It resolves the bridge's existing weak target
index only on an event and retains only a stream and position, not an actor/target.
Missing licensed files or unrealized/distant targets stay silent without blocking
the unlock. Pausing stops current voices and never replays them on resume.

### Work and animation

Animation cuts and loop blending are editable in the Inspector on
`res://features/actors/resources/characters/kneeling_work_animation.tres`:
**Work Start/End Seconds** select the kneeling segment, **Loop Blend Seconds**
smooths its wrap, and **Rise Start Seconds** selects the stand-up section.
These are seconds in the authored repair clip; reload the character/game to
apply changes. The original repair animation used by other work is unchanged.

In Godot's FileSystem, open
`res://features/lockpicking/resources/lockpicking_settings.tres` and edit its
Inspector properties. Defaults are defined by the attached resource script:

| Control | Meaning |
| --- | --- |
| Successes Required | Successful full attempts to unlock a fresh lock (default 3) |
| Novice Attempt Seconds | Seconds per careful attempt at skill 1 (default 20) |
| Expert Attempt Seconds | Seconds per careful attempt at the expert level (default 2) |
| Expert Skill Level | Level reaching the fastest base duration (default 100); intermediate levels interpolate between durations |
| Setback Wear | Condition lost on a mistake, varied from 75% to 125% |
| Careful / Rushed Speed | Work-rate multipliers (1 and 1.5); durations above assume Careful Speed 1 |
| Careful / Rushed Risk | Mistake-risk multipliers |
| Rushed Wear | Extra condition-loss multiplier when rushing |
| Witness Check Interval Seconds | Time between sight checks during active work (default 0.25 at normal game speed); stops after a report or cancellation |
| Approach Tolerance | Horizontal distance in meters required to begin work |
| Approach Timeout Seconds | Maximum game time allowed to reach the lock |

For quality, open `res://features/inventory/resources/items/lockpick.tres`,
`lockpick_flimsy.tres` or `lockpick_fine.tres` and edit **Lockpick Durability**.
Wear is stored as an absolute amount in the inventory entry's `lockpick_wear`
metadata; increasing durability also improves the remaining condition of
already-worn picks. Tool data is never written into the shared item resource.

Skill/dexterity assistance and door difficulty tiers use
`res://features/skills/resources/checks/lockpicking_check.tres`. These controls
shape pass/fail risk, not attempt speed. Only lockpicking skill and work mode
set the timer rate. Unlock progress is earned only by passes.

Saved defaults are read on the next game launch. Editor changes are not a live
remote tuning interface. Existing locks retain their saved difficulty; use a
new game/new stable lock ID to test changed authored difficulty. A deliberate
relock resets progress and partial check time, but not the check sequence.
Saved partial attempts retain their completed fraction when timing is edited;
the remaining fraction runs at the new rate. Seconds refer to normal game speed;
pausing stops work and the regular game speed controls scale it.

## Authoring targets

- **JailCell:** use a stable **Cell Id**, **Lock Difficulty**, **Lock Contact
  Offset** and **Lock Stand Offset**. Offsets are local meters. The existing
  cage defaults place the tool at its front ring latch. Facility identity
  scopes reusable local cell IDs.
- **WorldContainer / PrisonerLocker:** use a stable **Container Id**, enable
  **Supports Locking**, and author **Is Locked** and **Lock Difficulty**.
  **Lock Contact Offset** identifies the visible lock. Optional child markers
  `LockPoint` and `LockWorkPoint` override tool contact and standing position.
  Otherwise the actor stands 0.6 meters along the container's local +Z from
  the contact, at the container's floor height.
- **WorldDoor:** retain its stable door ID, definition and interaction sides.
  **Lock Contact Offset** (or child `LockPoint`) identifies the lock; the actor
  works from the nearer authored side. DoorController still owns door state.

Keep standing points on reachable floors and contacts within a natural arm's
reach. Test the actual actor and model, not just a path query. Generic contact
defaults are not a substitute for placing the lock marker on custom artwork.
Unregistered targets and containers with locking disabled cannot be picked.

## Ownership and persistence

`LockpickTarget` (leaf adapter) -> `LockpickInteractionController` (approach,
physical eligibility, cancellation and presentation) -> `LockpickingController`
(GECS work, exact-stack wear and completion). `LockpickWorkPose` only mounts a
temporary prop while the shared repair clip animates the hands; it never changes
equipment ownership or overrides the animated bones.

`CGameLockWork` owns stable lock ID, difficulty, progress, partial check time
and sequence. Cages/containers mirror its lock state; doors delegate to their
existing GECS door record. Door revisions invalidate old work claims. Scene
registration cannot overwrite loaded progress or unlocks. Live actor/target
references and exclusive work claims are not saved. World reload cancels live
sessions and reprojects loaded lock state.

## Art

Authored meshes and Blender sources live under `assets/items/tools/lockpick/`.
Each item has a ground wrapper under `features/world/projection/items/` and a
held wrapper under `features/world/projection/equipment/`. `GripPoint_Primary`
uses the shared humanoid grip pipeline; `ToolTip` supplies the contact point.
Icons under `assets/items/icons/` are transparent renders of these real models.
See that directory's README for picture replacement settings.

## Verification

- `./tests/run.sh` — full fast unit suite, including inventory wear, work
  persistence, skill/tool refusal, door revision changes and cage escape.
- `./tests/run.sh validation --filter validate_lockpicking.gd` — real bootstrap,
  physical approach, active HUD/prop, interruption, custody release, prisoner
  storage, door work and GECS reload. No actor teleportation after spawn.
- `./tests/run.sh validation --filter validate_lockpicking_law` — real jail
  services: initially unseen work, delayed actual sight, one charge, visible
  alarm and the registered guard physically engaging the picker. Test-owned
  starting positions isolate sight; the guard response uses normal movement.
- `./tests/run.sh validation --filter validate_gecs_door_system` — existing
  access, scheduling and door policies plus the shared lock-work gate.

## Future note

Different lock families, specialized pick shapes and familiarity with specific
mechanisms are intentionally deferred. Current difficulty tiers are not
separate physical lock types. No unused family/familiarity framework is added.
