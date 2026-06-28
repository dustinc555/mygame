# Combat Architecture — the standard

> What the combat layer **must be**, derived from the reference projects this codebase is
> modeled on. Like `cleanup.md`, this states the law, not a step list. The math rules live in
> the sibling spec files (`damage.md`, `hit.md`, `crit.md`, `block.md`, …); this file states the
> *structure* those rules live inside.

## The references (and the one rule they share)
- **Thrive** (`doc/architecture.md`) — gameplay is 100% ECS: *"only use Godot Nodes to display
  things, play sounds, and show the GUI."* Systems read/write entity data by **typed generic
  access** (`entity.Get<Health>()`, `ref var`). Damage is applied by **mutating a component or
  calling a typed helper** (`targetHealth.DealMicrobeDamage(...)`, `HealthHelpers.*`). A node, when
  a system needs one, is a **typed field on a component** — never a string `call()`.
- **Turbofat** (`creature.gd`) — the actor root is a **thin coordinator** holding typed child refs
  (`CreatureVisuals`, `CreatureSfx`); it drives them by **typed property/method calls**
  (`creature_visuals.fatness = x`) and listens to **signals** upward.
- **The shared rule: no reflection at any boundary.** Not `has_method`, not `call(name)`, not
  `get(prop)`. Sim is systems over typed components; presentation is a node reading sim via typed
  access. Reflection moves a compile-time dependency to runtime — it makes the dependency graph
  lie, kills type safety, and (measured here) ran **9389× slower**.

## The law for this codebase
1. **Combat scores are derived data owned by a system, never methods on the actor node.** There is
   no `actor.get_combat_hit_score()`. A system computes scores from source components via
   `CombatMath` and writes them into a component. (The 6 `get_combat_*` node getters are deleted,
   not rebuilt.)
2. **The node never gets reflected into.** Source data the node authors (loadout, stance, ranges)
   is **pushed** by the node into a typed component on an event (equip / skill change), not pulled
   by a system per candidate. This is the one legitimate node→component direction (Thrive allows
   nodes to author component data).
3. **`CombatMath` is the single owner of combat arithmetic.** Every formula in `architecture/
   combat/*.md` exists once, in `features/combat/sim/combat_math.gd`. Systems call it; no system
   reimplements a clamp or constant inline.
4. **Resolution mutates components, not nodes.** The resolution system applies final damage by
   mutating the target's `CGameActorVitals` (Thrive's `DealMicrobeDamage`), never
   `actor.call("receive_attack")`.
5. **Realization is one-way sim→node, Turbofat-style.** A thin node-side child observer
   (`CombatAnimator`) reads the resolved outcome off a component and plays clips/reactions via
   **typed** calls on the body projection + signals. No `actor.call("handle_system_combat_*")`.
6. **The hot path stays cheap and typed (standard #6).** Targeting is O(n²) over actors;
   per-candidate, per-frame work reads packed typed components — no `Dictionary` allocation and no
   node indirection inside those loops. `CombatMath`'s `Dictionary` returns are for per-*event*
   resolution and for the infrequent (dirty-gated) score derivation, never per-frame-per-actor.

## The shape

```
 SOURCE (node authors, on event)        SIM (systems, typed, no node)            NODE (one-way sim→node)
 ┌───────────────────────────┐  push    ┌──────────────────────────────┐        ┌──────────────────────┐
 │ WorldActor / capabilities │ ───────► │ CGameCombatLoadout (source)  │        │ CombatAnimator child │
 │  stats + equipment        │  typed   │           │ derive (CombatMath)         │  reads outcome cmpnt │
 └───────────────────────────┘  write   │           ▼                  │        │  → typed body calls  │
                                         │ CGameCombatConfig (scores)   │        └──────────▲───────────┘
                                         │           │ read                       reads CGameCombatAction
                                         │           ▼                  │ write outcome     │
                                         │ GameCombatResolutionSystem ──┼───────────────────┘
                                         │   → CombatMath, mutate CGameActorVitals
                                         │ GameCombatTargetingSystem (absorbs ai_targeting)
                                         └──────────────────────────────┘
```

## Component / system inventory (target)
- `CGameCombatLoadout` **(new)** — source stats the node authors: weapon skill level, str/dex/
  toughness, weapon blunt/cut base + parry bonus, shield skill/bonus/mult, `weapon_skill_id`,
  `dirty` flag.
- `CGameCombatConfig` (exists) — derived/packed scores the hot path reads. Now *written by*
  `GameCombatScoreSystem`, not by reflected getters.
- `GameCombatScoreSystem` **(new)** — dirty-gated: `CGameCombatLoadout` + `CombatMath` →
  `CGameCombatConfig`. Replaces the dead `get_combat_*` reflection in state-sync.
- `GameCombatResolutionSystem` (exists) — inline math → `CombatMath`; damage → `CGameActorVitals`.
- `GameCombatTargetingSystem` (exists) — absorbs `ai_targeting_capability` logic over spatial/
  faction/identity components.
- `CombatAnimator` **(new node child)** — realization observer; absorbs `combat_capability`'s
  reaction/clip half.
- **Retired:** `combat_capability.gd`, `ai_targeting_capability.gd`, all `get_combat_*` node
  getters, the score-reflection block in `game_combat_state_sync_system.gd`.

## Phased migration (each phase ships, holds the 40 FPS floor on `combat_skirmish_20v20_armory.tscn`,
baselined against clean-HEAD `main`)
1. `CGameCombatLoadout` + `GameCombatScoreSystem` (→ `CombatMath`); node authors the loadout;
   delete the dead score getters + their reflection in state-sync. **Fixes dormancy.**
2. Resolution inline math → `CombatMath`; final damage → `CGameActorVitals` mutation.
3. `GameCombatTargetingSystem` absorbs `ai_targeting_capability`; retire that capability.
4. `CombatAnimator` node observer replaces the realization bridge; retire `combat_capability`;
   unify quadbot onto the same component-driven pattern (sequenced last so quadbots keep working).

## Gates (non-negotiable, per `cleanup.md` + `AGENT.md`)
- Typed only, zero reflection — the win is deleting it, not relocating it.
- Behavioral baseline vs clean-HEAD `main` (combat-believability + law/jail validators, pass-rate).
- 40 FPS floor on `combat_skirmish_20v20_armory.tscn`; any dip below 40 is a failure.
