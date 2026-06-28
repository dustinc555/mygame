# cleanup.md — actor architecture standard + transfer context

> A context dump for continuing on another machine, and a definition of what the actor
> layer **must be**. This is not a step list and not a sequence of "slices to do." It states
> the law the code must satisfy, the hard facts about where it is now, and the constraints
> that are non-negotiable. *How* to get there is implementer judgment; *what counts as
> correct* is fixed here and is not negotiable down.

---

## THE STANDARD — what the actor layer MUST be

These are invariants. A change that violates one is wrong even if it imports, boots, and
holds FPS.

1. **Actors stay THIN — no god-classes. Thin type-subclasses are FINE.** (Revised 2026-07-01
   after reading the ToF2 source in `../tanks`.) The reference project we cite DOES use actor
   inheritance: `tile.gd → BaseUnit (494 LOC) → tank.gd (9 LOC) / heli.gd (21) / …` — thin type
   subclasses that override 1–3 hooks, with variance driven by DATA (`modifiers` dict, `can_fly`
   flags, a `get_stats_with_modifiers()`) and behavior COMPOSED (`active_abilities = []` of separate
   ability objects). So "composition only / kill all inheritance" was STRICTER THAN THE PROS and is
   retired. The real invariant: an actor owns **no foreign concern** (its size problem is solved by
   moving logic into capabilities/child-nodes, not by deleting `extends`). Our `HumanoidCharacter`
   (214) / quadbot (470) already match the ToF2 shape. **Dependency cycles are a SEPARATE issue from
   inheritance** — the actor SCC is `WorldActor ↔ BodyProjection/CarryCapability/combat_coordinator`
   (mutual refs), NOT the subclass chain (which isn't even in the cycle). Cycles are killed by making
   sim→visual **one-way** (ToF2/Thrive: the sim drives the visual; the visual never calls back), not
   by removing inheritance.
2. **An actor node is a thin coordinator + actuator — never a god-class.** It legitimately
   owns: lifecycle, movement actuation (navigation + `move_and_slide`), physics/animation
   triggering, and a registry of the capabilities/child-nodes it delegates to. It owns
   nothing else.
3. **One concern, exactly one owner.** Combat math, AI target selection, presentation/
   animation, carry, custody, needs/vitals — each is owned by exactly ONE unit (a GECS-style
   `ActorCapability` for sim logic, or a child node for projection) and reached by a typed
   handle. The same logic must not exist in two places (today it does — see the override map).
4. **Sim truth never depends on live nodes.** GECS systems/components stay node-free
   (the "truth rule"). Durable state lives in controllers/components keyed by stable
   `actor_id`, not on the actor node.
5. **Typed access only — reflection is forbidden.** Never shed coupling with `get()`,
   `has_method()`, or `get_property_list()`. That is not decoupling; it moves the dependency
   compile-time → run-time (so the graph *lies*), removes type safety, and measured **9389×
   slower** on these classes (froze the demo). Move the *logic*; keep *typed* calls.
6. **The combat path stays cheap.** Combat targeting is O(n²) over actors; dispatch per actor
   per frame must stay O(1) and typed. No new per-frame cross-node indirection on that path.
7. **Movement stays in the node.** It is the actuator's job (per AGENT.md). The goal is NOT a
   line-count target — Turbofat's ~650-line coordinator is a *direction*, not a spec. Our
   actor does more (3D nav, ragdoll); "thin" means "owns no foreign concern," not "short."

### Done means ALL of these hold (not "the model decided it's enough")
- No single-concern logic block (combat math, AI target selection, presentation, carry,
  custody, vitals) lives inline in `world_actor.gd` or `humanoid_character.gd`.
- **Zero dependency cycles** in the graph (user bar: "all cycles gone at a minimum"). Killed by
  one-way sim→visual + capability signal inversion — NOT by deleting inheritance.
- The dependency-graph truth-rule violations (`GameCombat*System → WorldActor` `as`-casts) are **0**
  (invert the system→node bridge pushes into node→component observer reads).
- `WorldActor` / `GameBootstrap` are no longer giant red hub nodes in the dep graph.
- **Behavior is provably preserved** — validator pass-*rate* against a stashed clean-HEAD
  baseline, not a single green run. Import/boot/FPS are necessary, never sufficient.
- (RETIRED as a goal: "zero extends-based override pairs" — thin type-subclasses are fine per ToF2.)

---

## WHY THIS STANDARD — the reference projects (context)

- **Thrive** — https://github.com/Revolutionary-Games/Thrive — gameplay is **ECS**
  (components + systems); Godot nodes only display/sound/GUI. They adopted it specifically
  because their old `Microbe` class was a "behemoth." That is the `WorldActor` situation
  exactly. Precedent for the sim-side standard.
- **Turbofat** — https://github.com/Poobslag/turbofat — actor root `creature.gd` is a thin
  coordinator that delegates visuals/animation/sfx to ~40 small one-concern child scripts.
  Precedent for the projection-side standard.
- **Tanks of Freedom II** — https://github.com/P1X-in/tanks-of-freedom-ii — data-driven /
  service-organized. Secondary reference.
- **Godot docs** — minimal scene dependencies; parents inject via signals + method calls;
  **composition over inheritance**.

### Cross-reference verdict
This project matches the pros on every axis **except** actor composition:

| Axis | Pros | Us | Verdict |
|---|---|---|---|
| Sim vs visuals split | Thrive: ECS sim, nodes only display | GECS sim-truth + node projection | MATCH |
| Folder organization | feature-first, scene+script co-located | `features/<f>/{sim,bridge,projection}` | MATCH |
| Data-driven defs | resources/definitions | `.tres` | MATCH |
| Loose coupling / DI | parent injects via signals/methods | `BootstrapContext` DI | MATCH |
| **Actor composition** | small ECS components / thin coordinator + child nodes | two monoliths, 64 override pairs | **DRIFT** |

---

## WHERE IT IS NOW — hard facts (context)

- `features/actors/projection/humanoid/humanoid_character.gd` — **5403 LOC, 541 funcs**.
  By real inventory: ~25% presentation/animation, ~40% AI behavior + combat decisions,
  ~35% life-state / carry / custody / needs. It is **not** "mostly presentation."
- `features/actors/bridge/world_actor.gd` — **2373 LOC, 269 funcs, 145 vars**.
- The capability scaffolding **already exists and is partly wired**: `world_actor.gd`
  `_create_actor_capabilities()` builds `[INVENTORY, EQUIPMENT, COMBAT, AI_TARGETING,
  INTERACTION, CUSTODY]`; inventory/equipment/custody already delegate. Combat/targeting
  logic (~65 funcs + `COMBAT_*` constants) is still inline in WorldActor **and** overridden
  in HumanoidCharacter — that overlap is the knot.
- Base class to extend for sim capabilities:
  `features/actors/bridge/capabilities/actor_capability.gd` (RefCounted; `setup/ready/process/
  physics_process/teardown` + `actor` handle).

### The entanglement — 64 override pairs (the central fact)
`HumanoidCharacter` redefines 64 of `WorldActor`'s methods. For these, combat/stats/custody/
vitals/movement exist in BOTH files. This is why relocating any of them is a **two-file
reconciliation**, not an independent move — and why a wrong move here fails **silently**
(wrong damage/targets, no crash, green import/boot/FPS):

```
assign_attack_target  can_receive_bandage  _collect_stat_modifiers  _create_actor_capabilities
enter_cell_custody  exit_cell_custody  _enter_tree  _exit_tree  _get_actor_move_speed
get_attack_range  get_bandaged_cut_damage  _get_base_stat_value  get_bleed_rate
get_blunt_damage  get_body_weapon_damage_profile  get_character_visual_root
get_combat_offhand_item  get_combat_weapon_item  get_combat_weapon_skill_id
get_current_combat_target  get_equipment_slot_label  get_equipment_slot_names
get_fatigue_stage  get_fatigue_stage_label  get_follow_anchor_position  get_hunger_stage
get_hunger_stage_label  get_life_state_label  _get_move_target_arrival_distance
_get_navigation_stuck_arrival_distance  get_open_cut_damage  get_perception_eye_position
get_stat_value  get_stealth_indicator_position  get_stealth_light_sample_position
get_stealth_sample_positions  get_total_wound_damage  get_vital_fluid_bar_color
get_vital_fluid_glow_color  get_vital_fluid_label  has_combat_shield
_is_actor_protected_from_combat  is_in_combat  _is_navigation_final_position_close_enough
is_ragdoll_active  is_ready_for_combat_exchange  is_running_enabled  _on_actor_equipment_changed
_on_actor_move_target_reached  _on_actor_move_target_unreachable  _on_actor_skill_level_changed
_on_enter_custody  _on_exit_custody  _ready  set_combat_stance  set_focused  set_move_target
set_running_enabled  set_selected  set_sneaking_enabled  shows_inventory_equipment
show_world_notice  show_world_speech  _sync_active_combat_actor_group
```

Regenerate this map any time:
```bash
comm -12 \
  <(grep -oE '^[[:space:]]*func [a-z_0-9]+' features/actors/bridge/world_actor.gd | awk '{print $NF}' | sort -u) \
  <(grep -oE '^[[:space:]]*func [a-z_0-9]+' features/actors/projection/humanoid/humanoid_character.gd | awk '{print $NF}' | sort -u)
```
Intersection = entangled (reconcile both bodies, collapse to one owner). Non-intersection =
single implementation.

### What is independent vs entangled (facts, not an order of operations)
- **Independent (no override twin):** the presentation/visual cluster (`_setup_character_visual`,
  `_update_character_animation` + animation helpers, nameplate/inspect/markers, `_spawn_bleed_*`
  splotches, appearance resolution, grip sockets, mesh-bounds math) and the carry cluster
  (`_attach/_detach/_update_carried_transform`, all `_get_carry_*` pose/bone math, carry
  assignment). These belong in child nodes / owned helpers; moving them does not require
  touching WorldActor.
- **Entangled (override pairs):** combat math, stat resolution, custody, vitals. These span
  both files and must be collapsed to a single owner before any relocation. The combat
  *animation* state machine (`_process_combat_animation_state`, `_choose_combat_attack`,
  `_play_combat_action_clip`, reaction clips) is presentation-shaped but combat-coupled — it
  belongs with the combat untangling, not the clean visual cluster.

---

## NON-NEGOTIABLE CONSTRAINTS (the guardrails, as law)

- **Typed only. No reflection.** (See standard #5 — the 9389× regression.)
- **Override-pair changes require a behavioral baseline.** Import + boot + FPS do NOT prove
  behavior preserved. Stash clean-HEAD; run the combat-believability + law/jail validators;
  compare pass-**rate**, because `validate_law_order_jail.gd` is ~50% flaky and
  `validate_world_actor_skills` count=2 is a pre-existing condition, not a regression.
- **40 FPS floor** on `scenes/test_levels/combat_skirmish_20v20_armory.tscn` for any
  combat/actor change. Average FPS is not a pass criterion; any dip below 40 is a failure.
- **One concern, one owner. Movement stays in the node.** (Standard #3 and #7.)

---

## VERIFICATION ALREADY DONE (so the migration's "good" call is real)

Godot **4.6.3.stable**, this machine:
- `grep res://src/` repo-wide (minus vendored addons) → **0 dangling refs**; `src/` gone.
- main-scene uid → `scenes/worlds/demo_world/demo_world.tscn` (exists); autoloads + plugins valid.
- Full editor import `godot --headless --editor --path . --quit` → **exit 0, zero parse/
  script/missing-file errors** (only cosmetic RID/resource leak-at-exit noise).

The 912-file feature-first migration is structurally sound — commit it. **Not** verified:
runtime gameplay + the 20v20 FPS floor (import proves structure, not behavior).

### To re-establish context on the other machine
```bash
godot --headless --editor --path . --quit          # structure resolves (exit 0)
timeout 5s godot --headless --path .               # runtime boots
cd architecture/dependency-graph && node extract_deps.js && node serve.js   # http://localhost:3031
```

---

## ⏯️ MIGRATION PROGRESS — RESUME HERE (tracked record; `/plans/` is gitignored)

Detailed step log + handoff prompts live in `plans/migration.md` (gitignored — does NOT travel via
git; this section is the durable summary that does).

**Tree state at last checkpoint:** import exits 0 errors; all 6 capability validators pass
(`tools/validation/validate_{stats,vitals,carry,custody,equipment,inventory}_capability.gd`);
`scenes/test_levels/movement_controls_test.tscn` boots clean — humanoids render on live skeletons and
walk on right-click (user visually verified). Safe commit point.

**The new shape:** `WorldActor` (`CharacterBody3D`) is a thin coordinator + movement actuator holding a
capability registry. `HumanoidCharacter extends WorldActor` is a thin humanoid config layer (NOT a god
class). Sim/state concerns are `ActorCapability` (RefCounted) units reached by typed `get_<cap>()`
accessors; presentation lives in `HumanoidBodyProjection` (a child node that now self-owns its
constants/state/appearance). Capability template to copy: `stats_capability.gd` / `vitals_capability.gd`
— state in the capability, one typed handle to a sibling acquired in `ready()`, cross-capability
reactions via signals (never direct back-calls), no reflection.

**Done:**
- Phase 0–3: thin actor stubs; reflection removed from `game_actor_sync_system.gd` + `needs_capability.gd`.
- Phase 1–2: `StatsCapability`, `VitalsCapability`.
- Phase 4a `CarryCapability`; 4b `HumanoidBodyProjection` self-owning (the 106-member `actor.X` coupling
  is gone, down to ~13 typed reads); 4c movement actuator + locomotion animation ported from clean-HEAD.
- Phase 4d `CustodyCapability` (ChatGPT), `EquipmentCapability`, `InventoryCapability` — wired + de-reflected.
- **Capabilities wired: 6 of 9.** Each is registered in `WorldActor._create_actor_capabilities()`.

**NEXT — Phase 5 (Combat, the endgame knot):**
- `combat_capability.gd` (446 LOC, **122 reflection hits**) + `ai_targeting_capability.gd`
  (543 LOC, **54 hits**) are the most reflection-coupled files; they reflect ~26 actor methods, many
  of which are combat math/animation routines that died with the god class and must be REBUILT from
  `architecture/combat/*.md`, not just de-reflected. Hard gates: behavioral baseline (combat is
  currently dormant → reference is clean-HEAD `main`) + **40 FPS floor on `combat_skirmish_20v20_armory.tscn`**.
- **5.1 = pure `combat_math.gd` helper from the combat specs + a validator** — isolated, spec-driven,
  the ChatGPT-safe slice (handoff prompt drafted). 5.2+ (de-reflect the two capabilities, wire the
  `set_system_*_bridge` hooks, perf) are owner-driven. None started yet.

**Also pending (long tail):** rebuild gutted `rustdead_humanoid_character.gd` (now an 8-line stub);
`InteractionCapability` (1502 LOC) + AI/LimboAI wiring (Phase 6); deferred `ai_utility_adapter.gd`
combat/job reflection; vendor scene updates.

---

## 🔱 COMBAT REBUILD — RESUME HERE (2026-06-29, branch `shitty-second-attempt`)

> Phase 5 was re-scoped after research. We are NOT de-reflecting the two combat capabilities —
> they are the WRONG shape. We are building the **pro ECS architecture** (Thrive + Turbofat), no
> reflection at any boundary. The full standard is in **`architecture/combat/ARCHITECTURE.md`** — read it.

### The architecture (decided, validated against the reference repos)
- **Thrive** = sim is systems over typed components; nodes only display. Damage = mutate a component /
  typed helper, never reflect into a node. **Turbofat** = node root is a thin coordinator driving typed
  child nodes + signals. Shared rule: **zero reflection** (`has_method`/`call(name)`/`get(prop)`).
- Your bones already match; the rot was reflection at 3 boundaries. The fix finishes the split:
  - **Combat scores = derived data owned by a SYSTEM**, never `actor.get_combat_*()` getters. A system
    derives them from source components via `CombatMath` into `CGameCombatConfig`.
  - **Node authors source stats** into a component on an event (push), systems only read (typed).
  - **Resolution mutates `CGameActorVitals`** (Thrive `DealMicrobeDamage`), not `actor.receive_attack()`.
  - **Realization = node child observer** (`CombatAnimator`) reading the outcome component, Turbofat-style.
  - `combat_capability.gd` + `ai_targeting_capability.gd` are quadbot-only legacy → **retired**, not rebuilt.

### Key diagnosis (so the plan is grounded, not guessed)
- Combat is dormant on this branch for THREE independent reasons: (a) the 6 `get_combat_*` score getters
  the state-sync reflected are **dead** → humanoids fought at 0 scores (50% hit, no crit) [**Phase 1 fixed**];
  (b) humanoid **realization is gutted** — the resolution system calls typed `*_system_*` bridge methods
  (`handle_system_combat_resolution`, `transform_system_incoming_damage`, `get_system_combat_attack_spec`,
  `prepare_system_combat_receive_attack`, `clamp_system_final_combat_damage`, `on_system_combat_attack_started`)
  that **`robot_actor` implements and humanoids do NOT** [Phase 4]; (c) the live damage isn't applied to
  vitals yet [Phase 2].
- **Canonical reference = clean-HEAD `main`** (pre-migration paths): `scripts/actors/world_actor.gd`
  (base combat: `get_combat_damage_bases`, `get_combat_hit_score`, scores, `_get_combat_damage_stat_multiplier`)
  and `scripts/characters/humanoid_character.gd` (`_get_current_weapon_skill_id`, `_has_equipped_shield`,
  body-weapon profile). **VERIFIED**: `CombatMath` constants are byte-identical to both the specs AND the
  shipping `main` game (`/220`, grit `0.0045/0.45/0.20`, crit `0.00303/0.00190`, dex assist `0.25`,
  body toughness `0.025`). No spec drift — `CombatMath` is correct for live combat.

### ✅ PHASE 1 — DONE & VALIDATED (commit-ready)
Loadout→score→config pipeline, typed, no reflection. Files:
- `architecture/combat/ARCHITECTURE.md` (the standard) · `features/combat/sim/combat_math.gd` (+ `tools/validation/validate_combat_math.gd`)
- `features/combat/sim/c_game_combat_loadout.gd` (NEW source component) · `features/combat/sim/game_combat_score_system.gd` (NEW derive system)
- `WorldActor.write_combat_loadout()` + helpers (faithful `main` port, typed via `get_stats()`/`get_equipment()`, grip-based shield)
- `game_combat_state_sync_system.gd`: dead score-getter block deleted; calls `_author_loadout()` (typed `as WorldActor`)
- `gecs_world_controller.gd`: `C_COMBAT_LOADOUT` added to actor entity set + `_ensure` + `_component_scripts_loaded`; `GameCombatScoreSystem` registered AFTER state-sync, BEFORE targeting/resolution
- `tools/validation/validate_combat_score_pipeline.gd` (NEW behavioral gate)

**Validation (all green):** `validate_combat_score_pipeline` PASS(13) · `validate_combat_math` PASS ·
`validate_visible_gecs_slot_combat` OK (didn't break it) · editor import + boot clean · 20v20 FPS no
regression vs clean-HEAD (avg 120/120, min 106→116).

### ✅ PHASE 2 (resolution math-dedup) — DONE & VALIDATED
- `features/combat/sim/game_combat_resolution_system.gd`: inline hit/block/crit/grit math swapped for
  `CombatMath.hit_chance/defense_chance/apply_crit/apply_block_mitigation/apply_toughness_grit`; deleted local
  `_apply_toughness_grit` + 4 now-unused consts (+9/−31). Behavior-preserving (constants verified identical).
  **Done by gpt-5.5 via opencode** (`opencode run --model openai/gpt-5.5`), I reviewed+gated. Validators green,
  editor import clean. (Workflow: orchestrate gpt-5.5 for mechanical slices/recon — see mem0 feedback memory.)

### ▶ ACTIVE EPIC — VITALS → GECS OWNERSHIP FLIP (full plan in `architecture/combat/VITALS_GECS_MIGRATION.md`)
- **Why we pivoted here:** verified combat is FULLY DORMANT — GECS resolution computes damage then calls
  `handle_system_combat_resolution`, which **no runtime class implements** (only 2 test doubles) → damage
  discarded. Old `combat_capability` path is orphaned (not registered in `_create_actor_capabilities`). hp is
  **wound-derived** (`hp = max_hp − get_total_wound_damage()`) and **node-owned** by `VitalsCapability`; the
  `CGameActorVitals` component is a one-way node→component mirror. So "mutate the component" needs the whole
  vitals model to BE the component.
- **USER CHOSE Option A** (full vitals→GECS flip, the pro/Thrive way — NOT a typed-node shim). Reasoning must be
  first-principles, not AGENT.md-as-authority (mem0 feedback memory).
- **Operator LOD decision:** a wounded/bleeding actor who leaves LOD must KEEP bleeding (can bleed out & die
  off-screen) for a bounded window; globally-distant NPCs don't matter. → `GameVitalsSystem` reads inputs from
  the GECS **component**, never the node, so off-node sim works. The vitals component becomes durable far truth.
- **Recon-verified facts:** `died`/`life_state_changed` have NO signal consumers (death is poll-based via
  `settlement_controller._sync_settlement_resident_deaths`); only `state_changed` is consumed (party command bar).
  `apply_record_to_actor` does NOT restore vitals (the LOD reconcile gap = #1 risk). Robot/quadbot = hot spot
  (different death model, oil-not-blood, get-up) → death-rule profiles + node FX observers, sequenced LAST.
- **Staged: S1** extract pure `VitalsMath` + repoint `VitalsCapability` (behavior-preserving, like `CombatMath`;
  oracle = existing `tools/validation/validate_vitals_capability.gd` + new `validate_vitals_math.gd`) →
  **S2** expand `CGameActorVitals` + node-authored inputs component → **S3** add `GameVitalsSystem` (calls
  `VitalsMath`; register after resolution, before state_sync; parity by construction) → **S4 (DANGEROUS, gated,
  owner-only)** the flip: system authoritative, capability→observer, resolution mutates wounds, delete reflected
  `handle_system_combat_resolution`, reverse vitals sync, add reconcile path → **S5** robot/quadbot profiles +
  retire `combat_capability`/reflected bridge + save-load round-trip.
- **✅ S1 DONE & VALIDATED.** `features/actors/sim/vitals_math.gd` (NEW, pure, mine — thresholds/hp/precedence/
  bleed/recovery/dying math). `vitals_capability.gd` repointed at it (gpt-5.5 mechanical + my fix: restored the
  `process_recovery` `healing_step<=0` early-return gpt-5.5 dropped — it skips recalculate, matters for downed+
  zero-heal edge). `tools/validation/validate_vitals_math.gd` (NEW) PASS(20). Oracle
  `validate_vitals_capability.gd` PASS(8) EXIT=0 → behavior preserved. Editor import clean; graph regen'd.
  NOTE: `validate_vitals_capability` emits pre-existing `Identifier not found: ECS` stderr noise (standalone
  isolation via c_game_combat_loadout→component→entity chain; NOT from S1; non-fatal, cached bytecode runs to PASS).
- **✅ S2 DONE & VALIDATED.** `CGameActorVitals` expanded (wounds blunt/open_cut/bandaged, bleed_rate/burst,
  recovery_multiplier, dying_timer_remaining, base_max_blood, `DeathProfile` enum HUMANOID/ROBOT). NEW
  `features/actors/sim/c_game_actor_vitals_inputs.gd` (`CGameActorVitalsInputs`: toughness, healing_rate, dirty).
  Registered C_VITALS_INPUTS in `gecs_world_controller` (5 sites mirroring C_VITALS: const/var/add_entity/load/
  _component_scripts_loaded — NOT _ensure, matching C_VITALS). `game_actor_sync_system`: query +C_VITALS_INPUTS,
  `_sync_vitals` mirrors the new fields from `actor.get_vitals()`, new `_sync_vitals_inputs` authors toughness/
  healing from `actor.get_stats().get_stat_value(...)`. Still a one-way mirror — NOTHING reads the new fields yet
  → zero behavior change. Editor import + 12s runtime boot both clean. PERF-WATCH for S4: inputs authored per-tick
  via get_stat_value ×2/actor; if the 40 FPS gate shows it hot, switch to dirty-gated event authoring.
- **✅ S3 DONE & VALIDATED.** Two new files under `features/actors/sim/`:
  - **`vitals_state_machine.gd`** (`class_name VitalsStateMachine`, static, signal-free) — the SHARED life-state
    machine: `recalculate(v,toughness)` (= the capability setters' recalc) + `tick(v,toughness,healing,delta)`
    (= `VitalsCapability.process()` bleeding→dying→recovery) + `process_bleeding/process_dying/process_recovery`
    + `enter_dying`. Faithful port of the capability MINUS signal emission, operating on a duck-typed vitals target
    (the component now; the node capability can be repointed here in S5). This makes ORCHESTRATION parity
    by-construction (advisor's key point: VitalsMath only made the *formulas* shared; the 3-phase sequence + the
    dying-timer-arms-only-on-edge logic is where divergence hides, so it's now shared too).
  - **`game_vitals_system.gd`** (`class_name GameVitalsSystem`) — thin: query `CGameActorVitals`+`CGameActorVitalsInputs`,
    per entity gated by `vitals_sim_remaining > 0`, call `VitalsStateMachine.tick(...)`, decrement the window.
  - Component shape finalized so **S4 touches ZERO component definitions** (advisor: S4 must be purely behavioral):
    added `CGameActorVitals.vitals_sim_remaining` (the LOD-bleed TTL gate); defaulted
    `CGameActorVitalsInputs.healing_rate := NpcRules.BASE_HEAL_RATE` (matches the node's null-stats fallback).
    **No death-transition marker field needed** — recon: NO consumer of `died`/`life_state_changed`; only
    `state_changed`→command-bar (idempotent), and death is poll-based on `life_state==DEAD`. The S4 observer
    re-derives signals by diffing `life_state`.
  - **NOT registered** in `gecs_world_controller` (advisor: don't register inert — it costs a per-tick query on
    the FPS-floor axis + gives false "wiring proven" confidence). Registration is bundled into S4 (one
    `world.add_system()` line, AFTER `combat_resolution`@1522, BEFORE `ai_job`@1525 — note: `game_ai_job_system`
    does NOT read `life_state`, so the order is clean but not load-bearing).
  - Gate `validate_vitals_system.gd` PASS (21 checks, exit 0): every life-state edge (wound→unconscious/coma/dying,
    timer-armed-once, bleed→DYING, dying-countdown→DEAD, dying-not-lethal→coma, recovery→ALIVE-only-if-downed,
    no-heal/nothing-to-do early-outs) + the LOD gate (skip at ≤0) + window decrement. Capability oracle still
    PASS(8), vitals_math PASS(20). Editor import registered all 4 globals clean; runtime boot clean. Dep graph
    regenerated — no new cross-cutting edges (VitalsStateMachine→VitalsMath+NpcRules only).
- **✅ S4 SAFETY NET GREEN (user authorized "flip realized path only").** `validate_vitals_parity.gd` runs
  identical scenarios through a REAL `VitalsCapability` and the `CGameActorVitals`+`VitalsStateMachine` path and
  asserts every field matches: **PASS, 129 field-parity assertions, exit 0** (fatal-blunt→DYING→DEAD,
  bleed→DYING→DEAD, KO→recovery over 60 ticks, interleaved mixed damage). Parity is now proven against the oracle
  CODE, not just hand-computed checks. **Confirmed flip sites:** resolution apply contract =
  `apply_resolved_damage(b,c)` → `blunt_damage += max(b,0); open_cut_damage += max(c,0); recalculate` (so S4
  resolution does `v.blunt_damage += max(b,0); v.open_cut_damage += max(c,0); VitalsStateMachine.recalculate(v,
  inputs.toughness)`); node-side vitals drivers to NEUTRALIZE = `world_actor.gd:1246 process_bleeding /
  :1252 process_dying / :1258 process_recovery` (+ confirm the generic `c.process(delta)` capability loop @ ~:213
  doesn't double-drive vitals); system registration = add a `_vitals_system_script` load + one `world.add_system`
  after `combat_resolution`@1522 in `gecs_world_controller._try_initialize`.
- **⚠ FLIP PRE-FLIGHT (advisor pre-flip review + driver recon, this session) — read before editing:**
  - **Parity test validates the ISLAND, not the BRIDGES.** Green parity (129 asserts) proves component-math ==
    capability-math in isolation; it exercises NONE of the flip seams. The **live 20v20 combat run is the
    load-bearing gate**, not parity. Sequence edits so a failing live test localizes to one bridge.
  - **Seam 1 — seed on realize.** `add_entity@223` makes `C_VITALS.new()` = defaults (hp=100, ALIVE). Reverse the
    sync and an actor realizing pre-wounded / non-default max_hp / loaded-from-save gets clobbered to defaults on
    tick 1 (`configure_initial_values` exists because they aren't all default). FIX: seed component from the actor's
    vitals ONCE at register/add_entity, then component→node thereafter.
  - **Seam 2 — field direction is NOT uniform; `max_blood`/`blood` is the trap.** `refresh_max_blood_from_toughness`
    (vitals_capability ~403, via `_on_skill_level_changed`) writes `max_blood` AND adjusts `blood` node-side. Keep
    `max_hp/max_blood/base_max_blood` node→component; only `life_state/hp/blood/wounds/bleed/dying_timer` reverse.
    `blood` is the genuine conflict (toughness-refresh adjusts it, sim drains it) — route the refresh's blood change
    through the component. Parity NEVER hit this (static toughness) — add a live mid-fight toughness-change case.
  - **Seam 3 — driver neutralization (SETTLED):** node vitals tick = `world_actor.gd:209 _process` → `c.process()`
    gated by `process_enabled`; `VitalsCapability` opts in at `:56 process_enabled = true` (base default false). So
    observer mode = set `process_enabled = false`. BUT `world_actor.gd:1243-1258` wrappers `_process_bleeding/
    _dying/_recovery` delegate to `vitals.process_*` and are called DIRECTLY by **quadbot** (`quadbot_character.gd:
    123/130 _process_recovery`), bypassing `process_enabled`. → see ROBOT ENTANGLEMENT below.
  - **Seam 4 — drop the realized gate.** `vitals_sim_remaining > 0` with nothing topping it = `tick` skips every
    live actor → resolution flips them DYING but the countdown (in `tick`) never runs → **DYING actors never die.**
    Drop the gate + decrement for the realized path AND update `validate_vitals_system.gd`'s 2 gate checks in the
    SAME edit. (The LOD window is S4b on the record, not this gate.)
  - **Signals:** emit in the reverse-sync diff by calling the capability's existing `_set_life_state` (compare→set→
    emit `state_changed`/`died`). Don't build a separate observer loop.
  - **Damage is NEW behavior** (old `handle_system_combat_resolution` was dormant — no baseline). Eyeball magnitudes
    in the live test; parity only covers vitals-given-damage, not the damage numbers themselves.
- **⚠ ROBOT ENTANGLEMENT — S4 must scope to HUMANOID death profile.** Quadbots/robots are `WorldActor`s → they get
  a `CGameActorVitals` entity AND node-drive `_process_recovery` directly. If `GameVitalsSystem` ticks them →
  double-sim. `CGameActorVitals.death_profile` (default HUMANOID) is the gate: add `if v.death_profile != HUMANOID:
  continue` to the system, and the reverse-sync/observer-mode must skip robots too. But nothing SETS death_profile=
  ROBOT yet (that's S5). MINIMAL S4 prereq: stamp robot/quadbot actors' `CGameActorVitals.death_profile = ROBOT` at
  setup so the system + observer skip them and they keep their current node path until S5. (This is the override-pair
  hazard from the actor-godclass notes — robots keep node authority; do NOT flip them in S4.)
- **⚠ LIVE-VALIDATION SCENE — unresolved.** Advisor's mandatory gate = a LIVE run that deals damage + kills + updates
  command bar + holds 40 FPS. Only `validate_visible_gecs_slot_combat.gd` is known to actually RUN GECS combat;
  the 20v20 benchmark scene historically did NOT register actors (combat never ran). BEFORE validating the flip:
  confirm `combat_skirmish_20v20_armory.tscn` registers actors + runs GECS combat (if not, that's the real gate to
  fix/use), and that it's the right scene for the AGENT.md 40-FPS-floor requirement.
- **✅ S4 FLIP DONE & VALIDATED (realized HUMANOID path).** Edits landed across 5 files (system registration
  by gpt-5.5, reviewed; design seams by Claude):
  - `gecs_world_controller`: `GameVitalsSystem` registered AFTER combat_resolution, BEFORE ai_job (6 mirror sites).
  - `game_combat_resolution_system`: humanoid hits now mutate `target_vit.blunt/open_cut_damage += final` then
    `VitalsStateMachine.recalculate(target_vit, target_cfg.toughness)`; robots keep the reflected path (elif).
  - `game_vitals_system`: LOD-window gate dropped; gated to `death_profile == HUMANOID` (robots skipped).
  - `game_actor_sync_system._sync_vitals`: direction-aware — node→component for max/base/profile + seed-once
    (`vitals_seeded`), then component→node onto the capability's RAW fields (not WorldActor.* setters, which would
    re-recalc) + `vitals._set_life_state(component.life_state)` for signals. Robots stay node→component mirror.
  - `vitals_capability`: `_system_owned = not (actor is RobotActor)`; `process()` early-returns when owned (observer).
  - Components: `CGameActorVitals.vitals_seeded` added.
  - **VALIDATION:** parity `validate_vitals_parity` **137 asserts** (129 field-parity, re-tied to per-phase calls
    since process() is observer-gated; + 8 SYNC-BRIDGE asserts proving the reverse path: seeded component DEAD ->
    `actor.life_state`/`actor.hp` getters reflect it + `died`/`state_changed` fire = the settlement-poll + command-bar
    consumers; seed-once; robot stays node-owned); `validate_vitals_system` 20; `validate_vitals_capability` 8;
    **LIVE end-to-end death gate**
    `validate_visible_gecs_slot_combat` GREEN — added `_test_humanoid_dies_from_resolution_damage` proving
    resolution→component→DYING→GameVitalsSystem countdown→DEAD (250 dmg = one-hit-lethal because the symmetric duel
    token stalls once a fighter is downed). Editor import clean (all globals); game runtime boot clean.
  - **⚠ PERF GATE — USER VERIFIES VIA RENDERED RUN (decided 2026-06-30).** Headless can't measure GPU FPS, so the
    user runs a real combat scene interactively to confirm the 40-FPS floor. Flip is expected perf-NEUTRAL (moves
    per-tick vitals work node→system: observer `process()` no-ops, `GameVitalsSystem.tick` early-outs for healthy
    actors) — but that's reasoning, NOT a measurement; do NOT mark perf-validated until the user confirms.
    CAVEAT for the run: the mandated `combat_skirmish_20v20_armory.tscn` has a PRE-EXISTING crash-spam bug
    (`...20v20_armory.gd:107,128` assign `base_attack_damage`, a property the actor no longer has — NOT mine, NOT in
    my diff). Either fix that one stale assignment first, or measure on a combat scene that actually registers actors.
  - **Known deferred:** non-combat direct writes to `actor.hp`/etc. are now clobbered by the reverse-sync (component
    is authoritative) — audit/migrate them in S5. Toughness-refresh's cosmetic blood-refill not preserved for live
    humanoids (blood is component-owned). Robots fully deferred to S5 (still take NO combat damage — dormant as before).
  - **✅ CLOBBER AUDIT (this session) — no live regression.** Grepped every non-combat vitals writer:
    - `nest_world_sim_plugin.gd:895` (`actor.hp = max_hp`) and `gecs_world_controller.gd:1593/1597` (realize-restore)
      are SPAWN/REALIZE-time, BEFORE the first sync → captured by seed-once into the component. **Fine.**
    - `force_kill`/`force_unconscious` (`world_actor.gd:1219-1228`) are the only authoritative node-side death writes
      that WOULD be clobbered — but they have **NO production callers** (grep: only `humanoid_character.gd:154`
      super-override + `ragdoll_pyramid_test.gd:77`). So the clobber is **LATENT/dormant, not an active bug.**
      ⚠ WHEN force_kill gets wired (executions/jail/story), it must write the COMPONENT for system-owned humanoids
      (e.g. a one-shot node→component override flag the reverse-sync honors), else the kill reverts next tick.
  - **S5 robot scope (confirmed entangled):** robots take damage via `RobotActor.receive_attack` (`robot_actor.gd:23`)
    → `combat_capability.receive_attack` (the ORPHANED capability slated for retirement). So robot combat damage +
    the ROBOT death profile (oil/get-up/direct-death, `robot_actor.gd:136-236`) + retiring the dead reflected
    `handle_system_combat_resolution` branch + retiring `combat_capability` are ONE interlocked S5 unit. NOT a quick
    increment — needs its own plan (the override-pair hazard from the actor-godclass notes).
- **🧨 BREAKUP BLOCKER DISCOVERED (2026-06-30) — `quadbot_character.gd` is DEEPLY STALE against the current base,
  masked by Godot's incremental import cache.** While trying to make `actor is RobotActor` polymorphic (a virtual
  `WorldActor.get_death_profile()`) to kill the lone `GameActorSyncSystem → RobotActor` truth-rule violation I'd
  added, editing `WorldActor` forced a recompile of its subclasses and surfaced a CASCADE of pre-existing parse
  errors in `quadbot_character.gd` (NONE of which are mine):
    1. it re-declares `_downed_collision_applied` / `_stored_collision_*` / `_stored_navigation_avoidance_enabled`
       (now owned by `WorldActor:705-711`) — shadow/“already exists in parent”;
    2. it calls `_process_actor_capabilities()` which `WorldActor` doesn't expose (its capability loop is inline @`_process`);
    3. deeper still: `process_system_combat_movement()`, `_current_order_type`, `_order_was_player_issued`,
       `AI_JOB_SCRIPT`, `can_see_actor_for_combat()`, `_ai_brain` — quadbot references a removed/renamed AI/combat/order API.
  Fixing (1)+(2) is bounded (drop the shadow vars — quadbot's SPECIAL ragdoll death methods keep working via the
  inherited fields, per user; add `_process_actor_capabilities` to WorldActor), but (3) is a full quadbot rebuild
  against the current actor API — a real unit of THIS epic, like the gutted `rustdead_humanoid_character.gd` stub.
  **CONSEQUENCE: you cannot touch `WorldActor` without surfacing this.** It was cache-dormant (quadbot only recompiles
  when it or `WorldActor` changes), so the tree LOOKED green. Reverting my edits restored the content but the cache is
  already invalidated. The vitals flip is unaffected (it doesn't depend on quadbot; all its validators pass + boot is
  clean). I reverted the `get_death_profile` attempt — `GameActorSyncSystem → RobotActor` stays as the documented
  minor violation until quadbot is de-staled. **Recommended next breakup step: rebuild `quadbot_character.gd` against
  the current base API (unblocks all WorldActor-touching work).**

- **▶ S5 EXECUTION — QUADBOT → THIN GECS ACTUATOR (2026-06-30, in progress; USER chose "robots onto GECS path").**
  Re-scoped with advisor: the breakup epic's "done" is ARCHITECTURAL — quadbot matters ONLY because its staleness
  makes `WorldActor` uneditable. The unblock target is **quadbot COMPILES as a thin actuator**, NOT robots fully
  functional in GECS combat. Robot vitals-profile + the combat-actuation last-mile are FOLLOW-ON functionality
  (ungated per-slice; the 40-FPS floor is deferred to the END of the breakup per user). quadbot's cache is already
  invalidated → there is no working robot runtime to preserve; just make quadbot correct.
  - **Class-B reference inventory (verdict per symbol):** the slim base provides NONE of quadbot's missing combat/
    AI/faction/needs API (all moved to components read by the GECS systems). So:
    - **DELETE (self-AI — target selection is now `GameCombatTargetingSystem`'s job, pushed via
      `set_system_target_bridge` → `_system_target_id`):** `_ai_brain`, `AI_JOB_SCRIPT`, `_current_order_type`,
      `_order_was_player_issued`, `assign_attack_target`/`_assign_combat_target`/`stop_attack_assignment`,
      `notify_incoming_attack`, the whole `_process_ai` cluster (`_should_run_ai_decision_tick`, `_clear_invalid_ai_job`,
      `_get_active_combat_target`, `_is_valid_combat_target`/`_is_valid_active_combat_target`, `_find_ai_target`,
      `_get_system_combat_target`, `_try_reconfigure_*`, `should_run_close_combat_retarget`, `_tick_active_ai_job`),
      self-defense + ally response (`_try_start_self_defense`, `_notify_defensive_allies_*`, `_respond_to_ally_*`,
      `_should_help_against`, `_find_humanoid_by_instance_id`, `_is_alive_combat_actor`, `_actors_have_hostility`,
      `_are_party_allies`/`_are_squad_allies`), `_sync_active_combat_actor_group` (+ `ACTIVE_COMBAT_ACTOR_GROUP`),
      `_get_effective_combat_attack_range`, `mark_hostile`/`has_hostility_with`/`can_see_actor_for_combat`/
      `_is_actor_protected_from_combat`/`get_attack_range`/`get_actor_squad_id`/`_get_runtime_controller`/
      `_last_direct_attacker_id`, `combat_state_changed` emits, `roll_combat_attack_damage` (damage roll is
      system-owned). Order-tracking (`OrderType`) goes with it.
    - **FIX-IN-PLACE (actuation → base):** `_process` `_process_actor_capabilities(delta)` → `super._process(delta)`
      (base loops capabilities inline); `_physics_process` drop `process_system_combat_movement` (unbuilt combat-move
      actuation) → use base `process_world_actor_movement` + face `_system_combat_focus_id` when engaged; read
      `_system_target_id`/`_system_combat_*` (base state) for facing/animation only.
    - **DROP config for removed props:** `base_attack_damage`, `attack_range`, `combat_attack_forgiveness_buffer`,
      `hunger_enabled`, `fatigue_enabled` (needs unwired; robots have none). Skills stay via `starting_skill_levels`
      (now a StatsCapability concept). Hull/oil stay via `max_hp`/`max_blood` (base vitals props still exist).
    - **KEEP (robot presentation/actuation the base lacks):** body projection, selection ring, combat/attack ANIMATION
      state machine (it reads base `_system_combat_*` — this is the actuation half), the SPECIAL ragdoll death +
      downed-collision + get-up + oil bleed (via robot_actor `_process_recovery`/`_recalculate_vitals`), world notices.
  - **RELOCATE-DON'T-DESTROY (advisor):** the deleted self-AI semantics (retarget cadence, self-defense trigger, ally
    response, player-order semantics, AI-job creation) are NOT replicated by the targeting system yet. They are
    preserved in git (the pre-reshape `quadbot_character.gd`) and clean-HEAD `main`; when the GECS AI/targeting layer
    is built out for robots, rebuild those behaviors there. This reshape only severs quadbot's LOCAL copy so
    `WorldActor` becomes editable.
  - **Milestone:** quadbot compiles as a thin actuator; editor import + boot + `validate_visible_gecs_slot_combat` +
    `validate_combat_score_pipeline` still green → **reopens WorldActor.** Robot vitals death-profile (resolution
    damages robots via component) + combat-move/anim actuation last-mile = follow-on, after.
  - **✅ Class A done:** 7 duplicate shadow vars removed (base owns them at `world_actor.gd:705-711`); ragdoll methods
    rebind to inherited fields. Zero behavior change.
  - **✅ RESHAPE DONE & VALIDATED (2026-06-30).** `quadbot_character.gd` rewritten as a thin GECS actuator
    (~1052 → ~470 LOC). DELETED the entire self-AI/targeting/order block (per the inventory above); KEPT robot
    presentation (body projection, combat-animation state machine reading `_system_combat_*`, selection ring),
    the SPECIAL ragdoll death/downed/get-up/oil model, and config. FIXED: `_process` now calls `super._process`
    (the base capability loop — so robots run their capabilities for the FIRST time; the old broken
    `_process_actor_capabilities` call meant they never did); `_physics_process` uses base
    `process_world_actor_movement` + faces `_system_combat_focus_id` when engaged; skills authored INTO
    `StatsCapability.starting_skill_levels` post-`super._ready()` (not the removed node prop); dropped config for
    removed props (`base_attack_damage`/`attack_range`/`hunger_enabled`/`fatigue_enabled`).
    **VALIDATION:** standalone parse clean (only the ECS-singleton artifact); full editor import clean; runtime boot
    clean; `validate_visible_gecs_slot_combat` OK; `validate_combat_score_pipeline` PASS(13). Dep graph regenerated —
    quadbot's outgoing edges dropped (no more CombatCapability/AiTargetingCapability/AI_JOB_SCRIPT refs).
    **⇒ `WorldActor` IS NOW EDITABLE — the breakup blocker is cleared.**
  - **✅ TRUTH-RULE: `is RobotActor` subclass-branching ELIMINATED (2026-06-30, first WorldActor edit post-unblock).**
    Added virtual `WorldActor.get_death_profile() -> int` (HUMANOID) + `RobotActor` override (ROBOT);
    `game_actor_sync_system.gd:118` now branches on `actor.get_death_profile()` (typed data) instead of
    `actor is RobotActor` (system→live-subclass ref). No sim system branches on a live subclass anymore (grep of
    `features/{combat,actors}/sim` for `is/as RobotActor|HumanoidCharacter` = only a comment). PROVED the unblock:
    editor import clean AFTER adding a WorldActor method (cascaded quadbot last session). Vitals validators still
    green (parity 137, system 20). Remaining truth-rule count = the 6 `as WorldActor` base-node BRIDGE casts
    (`game_combat_{resolution,targeting,movement,state_sync}_system` + `game_actor_sync_system._resolve_actor`) —
    those are the "invert system→node push into node→component observer read" job, a separate larger unit.
  - **FOLLOW-ON (functionality, not unblock; gate FPS at end):** (a) robot vitals death-profile — resolution must
    damage robots (currently dormant; robots take no combat damage) + reconcile the robot oil model
    (`robot_actor._recalculate_vitals`/`_process_recovery`) with the now-running VitalsCapability process loop
    (potential double-drive when a robot is actually wounded); (b) combat-move + combat-anim actuation last-mile
    (the system-movement bridge `_system_desired_velocity` is still consumed by NOBODY — humanoids lack it too);
    (c) retire `combat_capability`/`ai_targeting_capability` + the reflected `handle_system_combat_resolution` bridge,
    AND repoint the DORMANT node-combat-API callers off the deleted node methods (already broken for humanoids):
    direct/unguarded = `conversation_controller.gd:340` (`assign_attack_target`), `nest_world_sim_plugin.gd:197/950/1083`
    (`assign_attack_target`/`get_current_combat_target`), `combat_coordinator.gd:395` (`is_ready_for_combat_exchange`);
    guarded-with-`has_method` (degrade gracefully, lower priority) = `settlement_population_spawner`,
    `law_order_controller`, `combat_coordinator:597/603`. These should route through the GECS combat systems;
    (d) rebuild the deleted robot self-AI semantics in the GECS AI/targeting layer (git + clean-HEAD `main` = spec).
- **(superseded) original S4 flip edit list:** Mostly behavioral:
  (1) register `GameVitalsSystem` after resolution; (2) resolution mutates `vitals.blunt_damage/open_cut_damage`
  directly then calls `VitalsStateMachine.recalculate(v, inputs.toughness)` (= the setter), and the reflected
  `handle_system_combat_resolution` is deleted; (3) REVERSE the vitals sync in `game_actor_sync_system`
  (component→node observer); (4) `VitalsCapability` → read-only observer that diffs `life_state` and emits
  `state_changed`/`died`. Gate: combat deals damage + death + party-UI command bar + law/jail death poll +
  **40 FPS floor on the 20v20 armory scene** (PERF-WATCH: per-tick `get_stat_value` ×2 in `_sync_vitals_inputs` —
  if hot, switch to dirty-gated event authoring).
- **✅ RESOLVED (recon, this session) — the LOD-bleed window does NOT belong on `CGameActorVitals`.** Verified
  chain: derealize → `population_controller.gd:569 unregister_actor(live_actor)` → `:570 queue_free()`, and
  `unregister_actor` → `world.remove_entity(entity)` (`gecs_world_controller.gd:223` creates the actor entity with
  `C_VITALS`+`C_VITALS_INPUTS`; `:242/:253` removes it). So **the `C_VITALS` entity is DESTROYED at derealize** —
  a `vitals_sim_remaining` window on it can never fire off-screen. The durable survivor is the SEPARATE population
  record entity (`add_entity(..., [C_POPULATION_RECORD.new()])` `:480`), which today carries only `life_state`.
  - **Therefore LOD-bleed = its own staged step (call it S4b), NOT part of the flip:** widen `CGamePopulationRecord`
    with blunt/open_cut/blood/bleed + a window TTL, and add a cheap `LedgerSimulationController` (or a dedicated
    ledger system) bleed/dying tick that reuses **the same `VitalsStateMachine`** (it ticks any vitals-shaped
    target — that's exactly why the state machine is duck-typed). On realize, seed the live `C_VITALS` from the
    record; on derealize, copy `C_VITALS`→record + stamp the window. Component-shape change ⇒ do it S3-style
    (add fields inert + validate) before wiring. User intent: 30–60s window; globally-distant NPCs left unsimmed.
  - **Field caveat:** `CGameActorVitals.vitals_sim_remaining` (added in S3) is now on the WRONG entity for the
    window. For REALIZED actors you likely don't want a window gate at all (they should always sim while live), so
    in S4 either drop the gate for the realized path or repurpose the field. It is harmless until S4 wires it.
  - **S4 proper (the flip) stays purely behavioral for the REALIZED path** (register system, resolution→recalculate,
    reverse sync, observer). LOD-bleed (S4b) is sequenced after — don't let "the flip" pull the ledger-widening in.
- **Parity caveat (advisor):** orchestration is currently parity-**by-test**, not by-construction — the capability
  still owns its own copy until S5 repoints it at `VitalsStateMachine`. The 21 checks encode what I *think* the
  capability does. Cheapest hardening before the S4 flip: a **differential test** running identical scenarios
  through a real `VitalsCapability` and `VitalsStateMachine`, asserting identical fields.
- **S5** = robot/quadbot death profiles + node FX observers; repoint `VitalsCapability` at `VitalsStateMachine`
  (true single owner); retire `combat_capability` + the reflected bridge; save/load round-trip the new fields.

## 🔗 CYCLE REDUCTION — ToF2 service-oriented / dependency-inversion (2026-07-01, in progress)

> Goal (user): "do what the pros do." Reference = **Tanks of Freedom II** `scripts/services/` — leaf services,
> ONE-WAY deps (callers→service, never service→gameplay), reference by DATA (scene paths, ids), not typed classes
> (verified in `scene_switcher.gd`: `extends Node`, no gameplay refs). Our hairball is the actor↔capability SCC:
> `WorldActor → capabilities` is fine/necessary; the cycle is the capability→up BACK-edges.
> Method (advisor): work from the REAL `cycle:true` links in `graphdata.js` (NOT the printed SCC-membership path,
> which is Tarjan stack-order, not edges). ELIMINATE back-edges (don't abstract them behind a shared base — that
> just relocates the cycle down a layer AND adds inheritance, the opposite of the endgame). Re-run extract_deps per
> cut; let the graph confirm. Combat_capability edges are S5-coupled (defer). `RobotActor extends WorldActor` +
> `GecsWorldController↔WorldTimeController` need the composition refactor.

- **✅ CUT 1 — equipment/inventory → GecsWorldController INVERTED (DONE & VALIDATED).** The capabilities used to
  fetch the controller by group and call `bridge.sync_actor_inventory(actor)` (the back-edge). Now they only EMIT
  their existing `inventory_changed`/`equipment_changed` signals; `GecsWorldController._connect_actor_gecs_sync`
  (called in `register_actor`) OBSERVES those signals and runs the sync itself (Signal grabbed inline, no typed
  capability local → no new edge; `is_connected`-guarded). Removed the now-dead `_gecs_world_controller` field,
  `_get_gecs_world_controller()`, `sync_to_gecs()`, AND the dead `const GECS_WORLD_CONTROLLER = preload(...)` in
  BOTH capabilities (the preload PATH was the real remaining edge — a class token in a comment is stripped by
  extract_deps, but a dead preload is a live edge). **Result: big SCC 12→7 nodes** (Inventory/Equipment/Stats fell
  out of the cycle entirely); cycle-edges 30→21. Import+boot clean; `validate_inventory_capability` PASS(9),
  `validate_equipment_capability` PASS(10).
- **✅ CUT 2 — VitalsCapability → WorldActor/RobotActor INVERTED (DONE & VALIDATED).** Two back-edges: (a) `:67
  _system_owned = not (actor is RobotActor)` → the actor PUSHES `vitals.death_profile = get_death_profile()` as DATA
  in `_create_actor_capabilities`; ready() reads its own field (`death_profile == HUMANOID`). Data beats a virtual
  here — a `get_death_profile()` call would need a WorldActor-typed handle and RECREATE the edge. (b) `:336
  _set_life_state` reached up via `actor as WorldActor` to emit the node's `life_state_changed/died/state_changed` →
  now the capability emits only its own signal; `WorldActor._on_vitals_life_state_changed` (connected in
  `_create_actor_capabilities`) OBSERVES + re-emits the node signals. **Result: big SCC 7→4 nodes** — cutting Vitals'
  return path also dropped CombatCapability + RobotActor out (their only inbound cycle edge was
  `VitalsCapability → RobotActor`). Import+boot clean; validate_vitals_parity 137, _system 20, _capability 8 all PASS.
- **Remaining 4-node SCC:** `BodyProjection → CarryCapability → combat_coordinator → WorldActor` — WorldActor
  mutually coupled with {BodyProjection, CarryCapability, combat_coordinator}. **These are HARD RESIDUE, not clean
  inversions** (verified): body-projection subclasses call WorldActor-typed methods (`actor.get_equipped_item()`,
  `actor.life_state`, `actor._apply_downed_collision_shape()`), and CarryCapability's whole public API is
  `WorldActor`-typed (it carries actors) — retyping to `Node3D` just scatters `as WorldActor` casts into callers
  (moves the edge, doesn't remove it). combat_coordinator→WorldActor is combat. So this SCC dissolves with **S5**
  (combat) + the **kill-actor-inheritance composition refactor**, NOT a quick cut.
- **The other two cycles are also real dependencies, not signal-flips (defer to focused units):**
  - `GecsWorldController ↔ WorldTimeController` (2): mutual DI via each other's `SERVICE_ID`. Honest fix = invert
    time-sync so TIME is a leaf (gecs observes time; time never calls gecs). Shedding the edge via a string-literal
    id would HIDE a real runtime dependency (= the reflection anti-pattern). Core-time change → own unit.
  - `ConversationController ↔ BarServiceArea → MerchantRole → JobProvider → BarServiceArea` (4): BarServiceArea
    starts conversations (DI); ConversationController resolves its venue via `is BarServiceArea` + `serves_actor()`.
    Clean fix = pass the venue context INTO conversation-start (invert the `_resolve_bar_service_area` type-probe).
    Bounded venue/conversation-API refactor → own unit.
- **✅ CUT 3 — GecsWorldController ↔ WorldTimeController ELIMINATED (DONE & VALIDATED).** The cycle hinged on ONE
  back-edge: gecs's `_world_brain_time_stamp()` reached into WorldTimeController for `format_time()` (every other
  sim controller pushes to gecs one-way — no cycle). Fix: extracted pure time math into a LEAF
  `features/core/world_time_format.gd` (`class_name WorldTimeFormat`, zero deps); gecs now formats its OWN
  world-time component (`get_world_time_state().total_world_minutes`) via the leaf; WorldTimeController's
  get_hour/get_minute/get_weekday_name/get_day_index/format_time delegate to the leaf (single source; removed the
  now-dead local WEEKDAYS). **Result: time cycle GONE — down to 2 cycles.** Import+boot clean. NOTE:
  `validate_gecs_save_load_roundtrip` + `validate_world_simulation_save_load_authority` fail `count=1` standalone,
  but PROVEN PRE-EXISTING (stash-reverted both changed files to HEAD → still count=1; it's the standalone-`--script`
  ECS-entity `.new()` artifact — the validators need full boot, not my change).
- **✅ CUT 4 — BodyProjection → WorldActor DECOUPLED (DONE & VALIDATED).** The cycle was between the BASE
  `body_projection.gd` and WorldActor — but the base only STORES the actor (zero `actor.*` calls), so typing it
  `WorldActor` was needless coupling. Fix: base is now `var actor: Node3D` + `bind_actor(owner_actor: Node3D)`
  (sim-agnostic); each concrete subclass (humanoid/rustdead/quadbot body projection) caches a TYPED
  `var _actor: WorldActor` in its bind override and all `actor.X` calls were redirected to `_actor.X` (kept TYPED,
  not unsafe Node3D access — that would hide the coupling + cost perf). Subclass→WorldActor edges are one-way
  (acyclic). **Result: actor SCC 4→3** (BodyProjection dropped out; the 2244-line humanoid projection decoupled from
  the base cycle). Import+boot clean.
- **This validates the ToF2/standard-#1 finding:** the god-class breakup goal is thin actors + one-way sim→visual,
  NOT killing inheritance. BodyProjection came out of the cycle with zero inheritance changes.
- **✅ FIXED (regression from my earlier quadbot reshape, caught by validate_quadbot_character):** quadbot skills seeded
  as 1 not ~40 — `_apply_quadbot_skill_defaults()` set `stats.starting_skill_levels` AFTER `StatsCapability.ready()`
  ran its one-shot apply (empty). Added `StatsCapability.apply_starting_skill_levels(levels)` (merge + re-apply);
  quadbot calls it. Validator failures 31→3. The remaining 3 = the validator testing REMOVED god-class API
  (`base_block_chance`, `WALK_ANIMATION_NAME`, `get_combat_damage_bases`) my reshape deleted — STALE-VALIDATOR
  maintenance (update it to the thin-actuator API when robots come back for S5), not a code bug.
- **✅ CUT 5 — combat_coordinator → WorldActor RELOCATED (DONE & VALIDATED).** WorldActor held a dead
  `const COMBAT_COORDINATOR = preload(...)` it never used; robots (RobotActor) are the only users
  (`release_character` on death/unconscious). Moved the preload down to `robot_actor.gd` (quadbot inherits it).
  **Result: actor cycle 3→2** (WorldActor dropped its combat_coordinator edge; the coordinator↔actor loop now
  only closes through S5 combat, not carry).
- **✅ CUT 6 — CarryCapability ↔ WorldActor SPLIT BY LAYER (DONE & VALIDATED). LAST ACTOR CYCLE GONE.** This one
  was genuine mutual coupling (carry CALLED actor methods), so the base-retype trick alone didn't apply — user
  chose "split carry by layer" over a narrow-contract inversion. Three moves, all TYPED (no reflection, no Node
  downcast): (a) the ~230 lines of skeleton/bone/bounds pose math (which the file's OWN docstring said didn't
  belong there — "body-projection setup stays out of this capability") extracted to a NEW leaf
  `features/actors/projection/carry_pose_solver.gd` (`class_name CarryPoseSolver`, stateless statics; names only
  BodyProjection/CharacterBody3D/Skeleton3D/AABB/HumanoidCarryPoseProfile). (b) CarryCapability shrank to
  relationship state + eligibility + collision only: `_owner/_carried/_carrier` retyped `WorldActor`→
  `CharacterBody3D`, partner held as `CarryCapability` (self-type, no edge), sibling `VitalsCapability` wired in
  by the actor (`bind_vitals`), faction eligibility passed in as a `bool` (faction is a mutable node property —
  resolved at the HumanoidCharacter facade), and `state_changed` INVERTED to a `carry_changed` signal the actor
  observes. (c) per-frame positioning DRIVE moved from the carried capability's `physics_process` (deleted — was a
  no-op tick on every actor) to `HumanoidCharacter._physics_process` on the CARRIER (owns the anchor skeleton;
  runs after `super()` movement → carried reads carrier's post-move transform, no one-frame lag). Zero live
  `WorldActor` tokens in carry (5 remaining = docstrings, zero graph weight). **KNOWN BOUND (intentional):** the
  drive is humanoid-only — base `WorldActor.get_body_projection()` is a null stub, so a non-humanoid carrier
  positions nothing. Fine: no gameplay `begin_carry` caller exists (only the validator), so carry init is
  currently gameplay-dormant → low behavioral risk. Validator updated to bool/partner-cap signatures AND given a
  new `_validate_pose_solver` smoke (the solver runs in-game only on the carrier's projection node, unreachable by
  the bare-WorldActor relationship test, so it exercises the no-skeleton FALLBACK path directly — finite/above-feet/
  det≈1 — catching null deref + the Variant `is Vector3` branch + transform-compose typos): `validate_carry_capability`
  PASS (18/18, exit 0). Editor import exit 0, zero script/parse errors project-wide. NOTE: the pose math is a
  verbatim port of the pre-split live path (5 provably-unreachable helpers dropped); it had zero test coverage
  before the move, so the smoke is net-new safety, not a regression backstop.
- **✅ CUT 7 — SETTLEMENT 4-CYCLE ELIMINATED (DONE & VALIDATED). PROJECT NOW AT ZERO CYCLES.** The printed
  "4-cycle" was really TWO interlocking loops sharing the `BarServiceArea` hub: (i) **Conv↔Bar** 2-cycle
  (`Conv→Bar` + `Bar→Conv`), (ii) **Bar→Merchant→Job→Bar** 3-cycle. Both are scene-composition coupling
  (`get_node_or_null("X") as X` sibling lookups + a `BootstrapContext.service()` up-reach), NOT the actor pattern —
  fixed differently per the advisor. **Loop (ii) cut = DEAD CODE:** `MerchantRole.get_job_provider()` was the ONLY
  source of the `Merchant→Job` edge (`as JobProvider`) and had ZERO callers — all 3 `.get_job_provider()` sites are
  `active_target.get_job_provider()` on the merchant CHARACTER, which owns its own copy (`merchant_humanoid.gd:66`;
  proven `active_target` is the character, not the role, because the same sites read `active_target.member_name`
  which `MerchantRole extends Node` lacks). Deleted it → edge vanished, zero behavior change. **Loop (i) cut =
  SIGNAL INVERSION:** the back-edge was `Bar→Conv` (a venue node reaching UP into the ConversationController service
  at `bar.gd:766` to call `begin_conversation` when a waiter serves a customer). Replaced the up-call + the
  `_get_conversation_controller()` accessor (which held the `ConversationController.SERVICE_ID` token) with a new
  `signal service_conversation_requested(customer, waiter)` the venue EMITS. Wired at `SettlementBar._ready()`
  (`_connect_service_conversation`, deferred, `not Engine.is_editor_hint()`): connects the signal to SettlementBar's
  OWN handler `_on_service_conversation_requested`, which resolves ConversationController via the leaf service-locator
  and calls `begin_conversation` LAZILY at emit time. **This lazy shape is required, not incidental** (advisor catch,
  proven by a boot trace): bars spawn BEFORE core services register, so resolving+connecting to `begin_conversation`
  directly at `_ready` got `cc==null` and SILENTLY skipped (3/3 bars) — the once-at-ready version was a real, error-free
  regression. Connecting to our own handler (needs only the always-present service area) + resolving lazily matches the
  original per-event lookup, which fires long after bootstrap when a waiter serves a customer. `Conv→Bar` (intrinsic typed
  manipulation — `serves_actor`/`set_trade_proxy_position`/`open_inventory_pair`) is the correct-direction edge and
  stays. **Wiring host chosen by the advisor's 3-condition test:** SettlementBar (a) creates the BarServiceArea,
  (b) can reach ConversationController (leaf scene node), (c) has `in=0` in the graph — NOTHING points into it, so a
  new `SettlementBar→ConversationController` edge cannot close a loop. Verified no cycle member references
  SettlementBar. **NO cheap tricks:** did not dodge the ConversationController token via a bare string ID — the
  honest coupling (`BootstrapContext.service(ConversationController.SERVICE_ID)`) lives on the host, visible in the
  graph; the signal is the honest inversion.
  - **Validation:** `DEPENDENCY CYCLES: 0` (extract_deps). Editor import exit 0, zero script/parse errors
    project-wide. Real runtime boot (`godot --headless --path .`, main scene `demo_world.tscn` = full GameBootstrap +
    services + towns with SettlementBars): a temp boot trace POSITIVELY confirmed the connection is made —
    `service_conversation_requested.is_connected(_on_service_conversation_requested) == true` for all 3 bars, 0 SCRIPT
    ERROR (trace since removed). Note: 0-error boot ALONE was insufficient here (advisor catch) — `BootstrapContext.service`
    returns null silently, so "connected" and "silently skipped" logged identically; only the `is_connected` trace
    distinguished them, and it caught the once-at-ready race before it shipped. **HONEST COVERAGE CAVEAT:** the full live
    waiter→customer conversation gameplay path (emit → lazy cc resolve → `begin_conversation`) has NO clean standalone
    gate — `validate_reusable_bar_authoring.gd` loads the entire `two_towns` world and is PRE-EXISTING-BROKEN under
    `--script` (GECS entities can't instantiate → `entity.id`/`Invalid call` artifact cascade across every world-sim
    controller; PROVEN via `git stash` → pristine HEAD also fails `count=3`). So the cut is graph-clean + compile-clean +
    connection-positively-verified-at-boot, but the emit→conversation round trip is not integration-gated.
- **🏁 EPIC BAR MET: `DEPENDENCY CYCLES: 0` — every cycle removed from the project.** SEVEN clean dependency
  inversions landed + validated this arc (equipment/inventory→controller, vitals→actor, gecs→time,
  bodyprojection→actor, combat_coordinator→robot, carry→projection-split, settlement→dead-code+signal). Actor SCC
  12→0; total cycles 3→0. The user's minimum bar ("all cycles gone at a minimum") is satisfied. The dep graph is a
  DAG. Remaining god-class breakup work (S5 robot combat, the 64 override pairs, the truth-rule casts) is now
  cycle-free groundwork, not cycle-entangled.

### (superseded) old Phase 3/4 plan
- Phase 3 (targeting capability → `game_combat_targeting_system`) and Phase 4 (`CombatAnimator` observer) still
  stand as later work, but are folded into / sequenced after the vitals epic (S5 retires `combat_capability`).

### VALIDATION GOTCHAS (don't re-learn the hard way)
- **The 20v20 benchmark scene does NOT register its actors** (`add_child` without `register_actor`) →
  `groups=0`, combat never runs → benchmark = NOT a real combat gate (it measures an idle scene at 120fps,
  same on clean HEAD). Validate combat at the **system level** instead (Thrive-style): see
  `validate_visible_gecs_slot_combat.gd` and `validate_combat_score_pipeline.gd` as the templates.
- `validate_system_combat_correctness.gd` is **stale** (parse error line 76, references gutted god-class API) —
  pre-existing, not ours. Fix it (or delete) when Phase 2/4 restore the API it expects.
- Standalone GECS validators must register an `ECS` singleton placeholder and `load()` (NOT `preload`)
  the GECS-derived scripts, or you get `Identifier not found: ECS`. Pattern in `validate_combat_score_pipeline.gd`.
- Workflow: leave raw diffs on `main`/branch for the USER to commit (never branch/commit). Do NOT save this
  combat work to mem0 (user may discard the branch).
