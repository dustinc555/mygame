# AI And Population

NPC identity, realization, and autonomous behavior are shared runtime systems.

## Ownership

- `PopulationController` owns persistent actor records. Every persistent citizen, generated resident, and authored humanoid should have an `actor_id`/`stable_id` record before relying on long-lived behavior.
- `PopulationRealizationController` decides whether an actor record should have a live scene actor for the current town policy.
- `LedgerSimulationController` advances non-realized actor records from world time without instantiating NPC scenes.
- `ActorQueryController` is the shared lookup/index for live actors. Broad systems should query it instead of scanning every humanoid each frame.
- `AiSchedulerController` staggers decision ticks. Autonomous decision code must not make every actor think every frame.
- `AiBrain` is the live actor job runtime. `HumanoidCharacter` remains the actuator for movement, combat, interaction, equipment, needs, and animation.

## Actor Records

An `ActorRecord` is the persistent identity and snapshot for an NPC.

Expected record data includes stable ID, settlement ID, generation source, role, faction, squad, hostile factions, combat stance, appearance snapshot, equipment paths, inventory entries, skills, life state, realization state, ledger elapsed time, and last known world position.

Generated citizens are created record-first. Name, appearance, clothing, and skill rolls use deterministic seeds from actor ID plus purpose. After the record exists, later edits to population profiles must not rewrite that citizen unless an explicit migration/tool action is added.

Authored humanoids are also registered into population records. Missing stable IDs are generated from settlement-relative paths so editor-authored NPCs can become persistent without hand-written IDs everywhere.

## Realization Policies

`SettlementTown.actor_realization_policy` controls how actor records become live nodes:

- `full_town`: realize the whole town. This is the current default and safest gameplay behavior.
- `important_plus_near`: realize important roles plus actors near the player party.
- `near_player`: realize only actors near the player party.

Large cities should lower realization policy only after their ledger behavior covers the unloaded activities they need. Realized actors run `AiBrain`; ledger actors advance through controller-owned records.

## AI Jobs

The canonical live behavior path is:

```text
AiBrain -> AiJob -> AiJobDriver -> AiTaskStep -> HumanoidCharacter actuator methods
```

Use `AiJob` for autonomous behavior packages, combat/law jobs, assigned work, guard posts, ambient activity, and new player-command overrides as they are migrated. Current player movement still uses the existing `HumanoidCharacter` order actuator path, while player combat participates in AI priority. Jobs carry type, priority, source ID, target ID, debug label, interrupt policy, and task steps. Player-issued jobs should have higher priority than ambient or work jobs.

`AiTaskStep` should call existing actuator methods such as `set_move_target`, `assign_seat_target`, `assign_mining_resource`, or facility contracts. Do not duplicate movement, seating, combat, mining, or inventory algorithms inside AI steps.

Current bridges:

- `SettlementActivityController` issues `AMBIENT_ACTIVITY` jobs with start/wait/release steps.
- `SettlementActivityPoint` exposes `begin_ai_activity()` and `end_ai_activity()` as smart-object contracts.
- `JobProvider` owns slots, wages, and reusable work algorithms. Accepted assignments create `ASSIGNED_WORK` AI jobs, and `AiAssignedWorkStep` calls back into the provider to execute the assigned work.
- Combat targeting uses AI job priority while preserving the current humanoid combat actuator path.

## Performance Rules

- Do not add per-frame all-NPC scans.
- Use `ActorQueryController` for live actor lookup; indexed settlement/role/faction queries should stay bucket-local instead of rebuilding global indexes per query.
- Use spatialized `ActorQueryController.get_nearby_humanoids()` for local combat/perception/assist searches instead of filtering every live humanoid per actor.
- Use `AiSchedulerController.should_tick_actor()` for decision cadence.
- Budget settlement-wide assignment work across ticks; dense live town clusters should not process every resident for ambient activity in one controller tick.
- Full-town realization should happen at startup or on explicit state changes, not via recurring all-record resyncs every second.
- Keep far or unloaded population in `PopulationController`/ledger records instead of instantiated scene actors.
- Keep task steps small and actuator-driven; do not create parallel behavior implementations.

## Debugging

Use `HumanoidCharacter.get_ai_debug_snapshot()` to inspect active job type, source, priority, driver step, blocker, blackboard facts, and last completed job. If an actor is idle unexpectedly, first check realization state, active AI job source, active order type, job provider assignment, and whether the scheduler has ticked that actor.
