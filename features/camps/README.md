# Faction camps

## Authoring

Open the map's editable zone scene and select its Zone root. In the **Zone → Camps** tab, click **Place Camp Marker**, click terrain, then configure the selected marker. Placement and marker fields use the editor's normal Undo/Redo; save the scene normally.

- **Faction Owner**: faction resource, independent of character race.
- **Camp Type**: population archetype, furnishing recipes and lifecycle settings.
- **Camp size** selects Small, Medium or Large: compact layouts with 8, 16 or 24 initial members, including the resident leader and patrols. Their footprint radii are 6, 8 and 10 metres, set by the size resources rather than a marker radius slider.
- **Squad roaming radius** sets the wandering area around the camp, in metres. Type any larger value; there is no upper cap. It never enlarges the camp itself.
- **Roaming squads**: 1–4; **Members per squad** is separate. Leave at least one resident after allocating patrols. Invalid allocations are capped at generation and produce an editor warning.
- **Generation seed** fixes initial layout, loot and population choices.
- **Camp ID** is assigned once by the placement tool. Do not change it after publishing saves or duplicate it between markers.

The small tent icon is editor-only and never serialized into the scene. Selecting a marker opens the Zone dock's Camps tab; the native Inspector exposes the same size and roaming settings. Markers are configuration, not buildings. Their positions remain an authoring choice.

## Human-editable data

All paths below are relative to the project root (`/home/dustin/mygame`).

| Setting | Resource |
| --- | --- |
| Race weights, hostile to all, rare town approach chance | `features/factions/resources/factions/roaming_desert_thugs.tres` |
| Camp furniture, replenishment, cleanup, watch fraction, guard rotation, patrol speed | `features/camps/resources/desert_thug_camp.tres` |
| Small / Medium / Large population, compact footprint, furnishing multiplier | `features/camps/resources/sizes/small.tres`, `medium.tres`, `large.tres` |
| Combat skill ranges and starting equipment | `features/camps/resources/desert_thug_warrior.tres` |
| Weighted loot choices and quantities | `features/camps/resources/desert_camp_stock.tres` |
| Desert skin colors/textures and supported equipment slots | `features/actors/resources/character_races/desert_puglin.tres` |

The Factions dock exposes race weights and **Hostile to all other factions**. Weights are relative probabilities, not a guaranteed composition in every small camp: human `0.7`, desert Puglin `0.3`. A zero weight excludes that race; an empty/all-zero map keeps the existing appearance-profile fallback. Race weights also apply to ordinary faction squad generation.

Desert Puglins have sand, ochre and clay skin options, not green. The original Puglin race and purchased source textures are unchanged. Desert Puglins use the original skeleton, animation and grip profiles; unsupported human clothing slots are excluded.

Duplicate resources to author a different faction or camp type. Do not add faction-specific code branches. Furnishing recipes reference real scenes, optional stock pools, min/max counts and an optional per-resident count. The center is a CampfireTripod; optional FirePits share the wall-torch lighting implementation. Sacks, pouches and satchels are real owned inventory containers. Stools form a circle with small seeded position variations and an access gap; each faces the nearest campfire (central or adjacent). Supplies sit farther out and guard posts form the perimeter. Seats are placed before optional props so decoration cannot crowd them out. Facing is resolved once after all fires are placed, not during idle updates. Existing circle layouts receive an orientation-only repair on load, preserving positions and loot. Crowded new layouts omit optional props that cannot fit after a bounded search instead of overlapping them.

To tune seating, select the marker's **Camp Type** resource in the Inspector. **Compact Camp Sizes → Seating Radius** sets the fire-circle distance in metres; **Furnishings** contains the stool recipe's minimum/maximum count. Count changes apply to new camp IDs. Layout spacing changes apply when generating a camp or applying a size migration, not every frame. Existing pre-circle saved layouts migrate once, preserving furniture identities and looted inventories.

Loot uses weighted draws from the referenced stock table. `weighted_draws = 0` preserves the existing independent-chance behavior for other stock tables. Camp generation uses the container scene's actual dimensions and the shared inventory packing rules: exclude item kinds that cannot fit, and reduce quantities to available capacity. The camp pool draws one item kind per container by default. Pools and quantities remain editable; an entirely incompatible pool produces no stock. Capacity checks happen only during generation, never by rerolling a visited or looted container.

## Runtime and persistence

`CampMarker → CampController → CGameCampState / population records / world squads → CampRealizationController → ordinary actor jobs and furniture`

GECS owns the generated roster, live ownership, furnishing layout, rolled stock, patrol destinations and lifecycle deadlines. Nodes are disposable projections. Initial marker values generate once for a new camp ID. Roaming-radius edits update existing squads; size edits and legacy oversized layouts reposition existing furnishings without replacing their identities or inventories. Resident positions are corrected when loading an old save. Existing population, casualties, stock and replenishment deadlines are not reset by changing size. Type resources still own live schedule and patrol tuning.

- Patrols remain outside overnight. Their position, destination, identity, equipment and damage survive LOD transitions.
- Town buffers bias complete patrol segments away from settlements. The faction's settlement approach chance rarely relaxes that buffer toward the outskirts, not the town center. Abstract encounters use the existing raid resolver and persist casualties; realized actors use normal combat.
- Residents rotate guard/sitting jobs during the day. From 20:00 until 06:00, roughly 10% remain on watch and the rest sleep on the ground. A resident blocked from a preferred sleeping point can settle at its current position inside camp instead of repathing all night. Surviving residents replace dead watch members.
- Any surviving member, including an away patrol, keeps the camp occupied. Missing members replenish at a capped rate of one per seven game days by default; there is no immediate refill on LOD or load.
- After the last member dies, the camp is cleared. Seven game days later, furnishings and their remaining contents disappear. Items already looted are unaffected. No faction or player reclamation is implemented, so the site stays empty.
- Use the normal `WorldSimulationController.save_world_to_file` / `load_world_from_file` path. It restores the clock and other controllers around the GECS snapshot; raw GECS loading alone is not the full session-load API.

Lifecycle deadlines and death signals avoid per-frame population scans. Shared world-squad cadence drives LOD and routines; projection creation is capped at four actors per update. Navigation and combat remain in the existing shared systems. A sitting job claims its seat when execution starts and uses the shared safe-approach actuator, not the stool's collision center. Cancelled jobs release claims. Missing, occupied or unreachable seats fall back to quiet standing. Settled guards and seated residents retain their position without issuing repeated movement orders; only failed patrol navigation gets a slow retry. Schedule changes and combat still interrupt normally.

## Verification

- Full fast suite: `./tests/run.sh`
- Focused camp tests: `./tests/run.sh unit -gselect=test_camp`
- Real boot, navigation, patrol, sleep/watch, lighting, actor unload/reload, loot persistence, save/load, hostility and cleanup: `./tests/run.sh validation --filter camp_runtime`
- Original Puglin/shared human appearance regression: `./tests/run.sh validation --filter puglin_runtime_projection`
- Controller wiring boundary: `./tests/run.sh validation --filter controller_no_service_locator`

The camp runtime validator uses production bootstrap, actors, navigation, furniture and jobs in a controlled flat world. It proves actual sitting, stable seated idle and seat reacquisition after full actor/furniture destruction. It is not proof of every placement on the authored map. Rendered runs also save seating/day/night screenshots under `.test-results/`. Its `CAMP_IDLE_COST` measures only settled camp routine execution on real actors, not rendering, shared actor systems or whole-map FPS.

The separate 40-actor headless combat benchmark failed its minimum-40-FPS gate in both the feature checkout and an unchanged HEAD archive. This is an unresolved performance gate, not a camp test pass or evidence of rendered gameplay FPS. See `.test-results/benchmarks/latest/` for the feature result.
