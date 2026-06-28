# Vitals → GECS Ownership Migration (the plan)

> Epic: move durable actor vitals (hp, wounds, bleed, blood, life_state, dying timer) from the
> node-side `VitalsCapability` into GECS as the single source of truth, with a `GameVitalsSystem`
> owning the per-tick simulation and the node reduced to a one-way sim→node observer.
>
> **Why (on the merits, not because a doc says so):** Thrive — the only *shipped ECS* reference —
> makes health a component and a system owns death. hp/wounds/life_state here are durable (saved,
> read by law/jail, must persist across LOD where no scene node exists). State that must live
> without a node cannot be node-owned. The project already has the symptom of split ownership:
> `CGamePopulationRecord` holds a *second* `life_state`. Consolidating to one ECS truth removes a
> real duplication; it is not architecture for its own sake.

## What the blast-radius recon settled (verified)

- **Signal burden is small.** `WorldActor.died` and `WorldActor.life_state_changed` are emitted but
  have **no `.connect` consumers**; settlement death handling **polls** `life_state`
  (`settlement_controller._sync_settlement_resident_deaths`). The only consumed signal is
  `WorldActor.state_changed` → `WorldInteractionController._update_command_bar` (party command bar).
  → The node observer must keep `world_actor.life_state` readable and keep emitting `state_changed`.
  Re-emitting `died`/`life_state_changed` is kept for cleanliness but is not contract-critical.
- **Vitals must keep simulating for a bounded window after derealization (operator decision).** A
  wounded, bleeding actor who leaves LOD should keep bleeding — and may bleed out and die off-screen
  — for a while; only globally-distant NPCs are "don't care." This is the core reason ECS ownership
  is correct: a node-owned vitals model literally cannot sim without a node, but a GECS component +
  system can. → `GameVitalsSystem` reads its inputs (toughness, healing_rate) from a **GECS
  component**, never the live node, so off-node actors still tick. The node *authors* those inputs
  while realized (mirroring `CGameCombatLoadout`); they persist in the component after derealization.
  The system's query is: realized actors **plus** actors derealized within a bleed/dying window;
  beyond the window (and for globally-distant NPCs) vitals freeze — no per-tick sim. Stats stay
  node-side for now (toughness skill-derived + runtime-variable; healing_rate effectively static).
- **The #1 risk is the LOD/save reconcile gap.** `apply_record_to_actor` restores faction/skills/
  appearance/equipment but **not** life_state/hp/wounds; derealize syncs back only `life_state`.
  Today hp/wounds are lost across LOD (only life_state survives). Per the operator decision above,
  the flip makes the **GECS vitals component the durable truth** that survives derealization and
  keeps advancing for a bounded window. The reconcile path: derealize snapshots node→component is
  no longer needed for vitals (the component already *is* truth); realize restores node display from
  the component; and `CGamePopulationRecord.life_state` reconciles with the component's life_state on
  realize/derealize so a death that happens off-screen (bled out) is the one that wins — no
  resurrection, no double-death. Globally-distant NPCs (beyond the window) are not simulated.
- **Robot/Quadbot are the migration hot spot.** Different death model (no dying/recovery-coma),
  cut→blunt 0.5×, oil instead of blood, custom defaults, get-up. They directly write node
  `life_state` and emit signals themselves. → death-rule **profiles** on the component + node-side
  death/oil/get-up **FX observers**; sequence them **last**.
- **Rules are safe for a system to call.** All `NpcRules`/`SkillRules` symbols used by vitals are
  consts/static on `RefCounted` classes.

## Target shape

```
 NODE authors inputs (on event)     SIM = GECS truth (systems, typed)             NODE observer (one-way sim→node)
 ┌─────────────────────────┐ push   ┌──────────────────────────────────┐         ┌───────────────────────────┐
 │ StatsCapability         │ ─────► │ CGameActorVitalsInputs            │         │ VitalsCapability (observer)│
 │  toughness, healing     │ typed  │  (toughness, healing_rate)        │         │  reads CGameActorVitals    │
 └─────────────────────────┘        │ CGameActorVitals (TRUTH)          │         │  → updates display fields  │
 ┌─────────────────────────┐ mutate │  hp/max_hp, blood/max/base,       │         │  → emits state_changed     │
 │ GameCombatResolution    │ ─────► │  blunt/open_cut/bandaged wounds,  │         │  → keeps world_actor.life_ │
 │  wounds += dmg           │ typed  │  bleed_rate/burst, recovery_mult, │         │     state in sync          │
 └─────────────────────────┘        │  dying_timer, death_profile       │         │  robot/quadbot: oil/getup  │
                                     │            │ VitalsMath (pure)    │         │     FX as observers        │
                                     │            ▼                       │         └───────────────────────────┘
                                     │ GameVitalsSystem (fixed-tick)      │  reconcile on realize/derealize/save
                                     │  bleed/dying/recovery + life_state │◄────────── CGamePopulationRecord.life_state
                                     └──────────────────────────────────┘
```

System order (fixed tick): score → targeting → slot → **resolution (writes wounds)** →
**vitals (recompute hp + life_state)** → state_sync. Resolution must write wounds *before* vitals
recomputes in the same tick, or death lands a frame late.

## Staged migration (each stage ships, validates, holds the 40 FPS floor)

- **S1 — Extract `VitalsMath` (pure), repoint existing `VitalsCapability` at it.** Behavior-
  preserving dedup (the `CombatMath` pattern). Pure functions: `total_wound_damage`,
  `hp_from_wounds`, thresholds (`coma_point`/`death_point`/`blood_death_point`/`dying_seconds`),
  `resolve_life_state` (the recalculate precedence), `bleed_step`, `dying_step`, `recovery_step`.
  The capability keeps the side-effecting `_set_life_state` (signals); VitalsMath stays pure.
  **Oracle:** existing `tools/validation/validate_vitals_capability.gd` (behavior preservation) +
  new `validate_vitals_math.gd`. *(gpt-5.5 does the mechanical extraction; I spec + own the gate.)*
- **S2 — Expand `CGameActorVitals`** to all durable fields + add node-authored
  `CGameActorVitalsInputs`. Node authors both on event (mirror the `CGameCombatLoadout` pattern).
  No behavior change yet (component still a mirror). Validate import.
- **S3 — Add `GameVitalsSystem` + the shared `VitalsStateMachine`. ✅ DONE & VALIDATED.** The
  refinement vs the original plan: `VitalsMath` only made the *formulas* shared, but the **3-phase
  orchestration** (bleeding→dying→recovery) and the **dying-timer-arms-only-on-edge** logic is where
  divergence actually hides — so that was extracted too into `vitals_state_machine.gd` (static,
  signal-free, duck-typed target). Both `GameVitalsSystem.tick` and (in S4) the resolution apply-path
  call it → the *system↔resolution* orchestration is shared **by construction**. (Caveat: parity with
  the *node capability* is still **by test** — the capability keeps its own copy until S5 repoints it at
  `VitalsStateMachine`; the 21 checks encode the intended behavior. Add a differential
  capability-vs-state-machine test before the S4 flip.) `GameVitalsSystem` is a thin gated loop over
  `VitalsStateMachine.tick`. Component shape was **finalized here** so S4 is (mostly) behavioral:
  `vitals_sim_remaining` (LOD-bleed gate) added, `healing_rate` defaulted to `BASE_HEAL_RATE` — but see
  the OPEN LOD-bleed fork in `cleanup.md` (the window only works if the vitals entity survives derealize). **No death-transition marker field** — recon found no `died`/`life_state_changed`
  consumer (only `state_changed`→command-bar, idempotent; death is poll-based), so the S4 observer
  re-derives signals by diffing `life_state`. `GameVitalsSystem` is **deliberately NOT registered** in
  S3 (registering inert costs a per-tick query on the FPS axis + false "wiring proven" confidence) —
  registration is bundled into S4. Gate `validate_vitals_system.gd` PASS (21 edge checks).
- **S4 — The flip (dangerous; I do this, gated). PAUSE FOR EXPLICIT USER GO.** Purely behavioral, zero
  component-shape change: register `GameVitalsSystem` **after** resolution (`@1522`), **before**
  `ai_job` (`@1525`; ai_job does not read `life_state`, so order is clean but not load-bearing);
  resolution mutates `vitals.blunt_damage/open_cut_damage` directly then calls
  `VitalsStateMachine.recalculate(v, inputs.toughness)` (= the old setter) and the reflected
  `handle_system_combat_resolution` call is **deleted**; reverse the vitals sync in
  `game_actor_sync_system` (component→node observer); the realization controller stamps
  `vitals_sim_remaining = WINDOW` while realized / on derealize (bounded off-screen bleed; far NPCs
  left at 0); `VitalsCapability` becomes a read-only observer that diffs `life_state` and re-emits
  `state_changed`/`died`. **Gate:** combat deals damage + actors die + party command bar updates +
  law/jail death poll still fires + 40 FPS floor on `combat_skirmish_20v20_armory.tscn`.
- **S5 — Robot/Quadbot profiles + cleanup.** Port robot/quadbot death models as component profiles;
  keep oil/ragdoll/get-up as node-side FX observers; retire `combat_capability` + the reflected
  `*_system_*` bridge; expand save/load to round-trip the new fields and seed the live actor on load.

## Gates (every stage)
- Typed only, zero reflection (the win is deleting it).
- Behavior-preserving vs the stage's oracle; `validate_vitals_capability.gd` must stay green.
- 40 FPS floor on `combat_skirmish_20v20_armory.tscn`; any dip below 40 is a failure.
- No silent change to LOD/save vitals behavior until S5 deliberately adds durable-across-LOD vitals.
