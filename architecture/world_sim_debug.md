# World Sim manual controls

## Use in game

With game debugging enabled, open **Esc → Debug - World Sim → Squads → Spawn Attack**. Choose **From camp**, **To town**, and **Fighters**, then click **Spawn Attack**. Close the Escape menu to resume simulation; the separate World Sim window can remain open.

The command creates additional warriors at the occupied source camp using that camp's faction race weights, appearance/name profiles and warrior equipment. It does not take existing residents or patrol members. Fighter count starts at 10, accepts positive integers and permits typing above 100 for larger workloads. **Refresh** reloads available destinations while retaining valid selections; reopening the form also refreshes it.

The target must belong to a hostile faction. This control never changes diplomacy. Cleared camps, missing towns and invalid counts are refused at the simulation boundary, including when a previously selected camp has since been cleared.

## Simulation ownership

`features/camps/sim/camp_controller.gd::spawn_attack_squad` creates ordinary population records and a GECS-backed world squad with an explicit `assault` objective and target settlement ID. The existing camp realization, AI patrol movement, navigation and combat systems execute it. Explicit destinations are not constrained to the camp's ordinary roaming radius.

Camera LOD retains the same identities and objective while switching between live actors and offscreen squad travel. World saves retain the roster, appearance, equipment, objective and per-camp command sequence. There is no debug-only movement or combat loop.

Additional fighters are not automatically replaced after death and do not enlarge the normal camp population target. Surviving members still count toward keeping their camp occupied. Offscreen encounters use the existing camp skirmish resolver; survivors return home and resume patrol rather than losing their population records. This control does not add town conquest or a new offscreen battle model. Realized attackers keep their destination and engage through ordinary hostility rules.

## Add another action

The generic browser is `features/world_sim/projection/world_sim_debug_menu.gd`: searchable categories on the left, one action panel in a bounded scroll area on the right. It owns only presentation, not simulation state. Register a unique action ID, category, label and feature-owned form through `add_action(...)` in `DebugMenu._build_world_sim_window()` (`features/ui/projection/debug_menu.gd`).

Keep each form in its feature's `projection/` directory and submit stable IDs to that feature's authoritative simulation API. Query lists on opening/refresh, not every frame. The camp example is `features/camps/projection/camp_attack_debug_panel.gd`.

## Verification

`./tests/run.sh` runs the full unit suite, including command refusal, generation, replacement, objective retention, UI submission, search and bounded-menu regressions.

`./tests/run.sh validation --filter validate_camp_squad_orders --jobs 1` drives the actual Escape entry and form, then verifies physical travel, combat, camera-driven destruction/recreation and the full world-save boundary in a controlled bootstrapped world. `validate_camp_runtime` covers the broader camp lifecycle. These functional checks are not large-battle framerate benchmarks.
