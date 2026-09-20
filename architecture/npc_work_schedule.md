# NPC employment and Home scheduling

## Ownership

```text
Population actor (stable ID)
├── employment slot → role → WorkSchedule
│   ├── town labor: ranked Farm/Haul offers
│   └── facility staff: ranked offers or specialized venue duty
└── residence slot → housing furniture (chair / bed)

WorldTime → shared schedule rules
          ├── population routine + offscreen farm labor (sim)
          └── bounded Jobs lifecycle → duty / Home handoff (bridge)
                                     → physical travel, work, seating, sleep
```

Employment and residence are independent relationships of the same person, not two NPC types. `uses_settlement_jobs` selects the work executor; it does not disable the employment schedule. Public door hours do not define employee shifts.

Jobs owns the employment duty grant for every role. Specialized bar, jail and contract executors require `JobSystemController.can_execute_assignment_duty(actor)`: an open shift alone is insufficient. The grant must match the actor's current assignment, and player/combat/law priorities must permit routine duty. Missing Jobs authority fails closed. These executors perform role-specific actions, not independent scheduling.

## Authoring

Default hours live in `features/settlements/resources/default_work_schedule.tres`: start 08:00 inclusive, end 20:00 exclusive. A role's `FacilityRoleDefinition.work_schedule` can reference another WorkSchedule for explicit exceptions. Start later than end means overnight; equal endpoints means all day. Slot records serialize only the schedule's numeric dictionary, never the Resource.

Guard, warden and barkeeper roles explicitly reference `features/settlements/resources/always_on_work_schedule.tres` (00:00–00:00). They remain on duty and default to their discovered post/counter/desk when there is no active task. Other roles retain the default shift unless authored otherwise. Change the role's resource reference to give it a different schedule; do not add role-name branches to Jobs.

Existing Home phases remain daytime seating, sleep 22:00–06:00. Active employment takes precedence over that default sleep phase, allowing authored night shifts. A residence must provide usable furniture and access; occupancy fallback is handled by HomeResidentProjection. This does not add a new inn facility type.

## Execution

```text
on hour boundary / worker realization / relevant work event:
    enqueue affected stable actor IDs, deduplicated

budgeted dispatch:
    if off shift:
        cancel provider work and release duty
        preserve player, combat and law orders
        reconcile actual residence when Home phase changes
    else:
        wake asynchronously if needed; requeue on life-state event
        Jobs grants the assignment's duty scope
        execute ranked work or authorized specialized facility duty
```

Revocation calls the generic `release_settlement_assignment_duty(actor)` hook on the employment owner before Home projection. Bar and jail release their own workstation/service claims and routine movements; actual custody, sentence delivery, combat and player orders survive. Routine warden desk travel is ordinary navigation, not a law order. Sentence completion clears the interaction capability's law flag so Jobs can resume desk duty.

Farm progress and automatic haul transfers also check current eligibility before producing consequences, so an actor waiting in the Home queue cannot finish work after closing. Manual party Jobs are not governed by NPC employment hours.

Offscreen farming integrates only overlapping shift minutes, including multi-day and overnight intervals. Hour replay uses each event's absolute boundary, not the clock's final catch-up time. The existing conservative rule suppressing aggregate settlement farming when any assigned farmer is realized remains unchanged.

Home phase deduplication must include the activity, not merely “already idle.” Sleeping state restored through LOD has no furniture claim: wake/reconcile, reacquire a real bed and retain an outside standing exit. A mattress origin is not a valid wake-up standing position.

## Cost and verification

The existing indexed offer cache remains. Assignment dispatch has an actor cap plus a soft 500-microsecond budget checked between actors; one actor operation may exceed it. This is not a frame-rate guarantee. Existing role executors check shared eligibility while acting; no separate per-NPC schedule timer or minute-by-minute aggregate catch-up was added.

Fast regression tests: `tests/unit/test_town_work_schedule.gd`, `test_farm_work_schedule.gd`, `test_haul_work_schedule.gd`, `test_staff_work_schedule.gd`, `test_jail_job_duty.gd`, `test_contract_job_duty.gd`.

Physical lifecycle: `tests/validation/validate_town_work_schedule_runtime.gd` proves generated town employment, real tilling, interruption and home seating at 20:00, bed sleep at 22:00, overnight body replacement, wake at 06:00 and productive return at 08:00. Existing granary, generic assignment, Home realization and population policy validators remain regression coverage. The generic assignment performance validator proves bounded matching/idle behavior, not rendered 50-NPC FPS.

`validate_reusable_bar_authoring.gd` also proves physical barber seating and waiter delivery through the shared contract path. `validate_law_jail_sentence.gd` proves custody, sentence delivery and subsequent desk return, including an elevated desk marker. These complement grant/refusal/priority unit tests rather than replacing them.
