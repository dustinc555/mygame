# New-game start scenarios

World1's **Game Start → Default Start Scenario** Inspector property points to
`miras_gang.tres`. This is currently the only production start. Expand the resource
in the Inspector to edit its squad name, character records, faction, world-local
spawn position, spacing and starting behavior. Character equipment, skills and
appearance remain authored in the referenced `CharacterRecordDefinition` resources.
The Rustwash Basin standalone launch references the same resource, not another roster.

## Launch contract

- A new game uses `WorldRoot.get_start_scenario()`: `selected_start_scenario` when
  supplied, otherwise `default_start_scenario`.
- A future start-selection menu sets `selected_start_scenario` **before** adding the
  world to the scene tree. It does not edit the world's default resource.
- Loading sets `saved_game_path` before scene entry instead. GameBootstrap loads
  through `WorldSimulationController` before notifying scene consumers. A failed
  load stops startup; it never silently creates a new game.
- `PlayerPartyController` validates and applies starting records once. The GECS
  party-state component saves the start receipt and explicitly named squads.
  Subsequent loads use saved population, including departures, deaths and renames;
  changing a scenario resource does not reset a campaign. Older saves without a
  receipt are still treated as saves, not fresh starts.
- `CharacterRecordPartySpawner` requests creation after bootstrap, then uses the
  shared `PopulationCharacterRealizer` to project the authoritative roster. Its
  node transform does not define placement; the scenario resource does.
- Squad and faction are separate fields. A squad is not a faction, and the HUD is
  not allowed to assign either while displaying portraits.

The HUD derives each count and its visible cards from the same live membership.
An unassigned actor appears under **All** without creating a placeholder squad.
The **+** control requests a name; only confirmed, valid names create saved empty
squads. Rename updates durable membership as well as live actors.

Generic regressions live in `tests/unit/test_start_scenarios.gd`,
`test_party_startup.gd`, `test_party_squad_hud.gd`, `test_player_party_controller.gd`
and `test_party_restore.gd`. The separate authored-world smoke is
`tests/validation/validate_start_scenarios.gd`; it checks real World1 startup, HUD
input, and both retained-body and cold-session loading. Its optional
`PARTY_CAPTURE_DIR` capture disables terrain drawing only, while rendering the
actual HUD and independent character portrait viewports.
