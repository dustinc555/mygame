# Operator Instructions

This folder contains concise Godot editor workflows for human operators.

Use these docs when adding reusable content to towns, scenes, facilities, or future player/faction bases.

## Workflows

- `add-bar-to-town.md`: add a reusable `SettlementBar` to a town and place a building model under it.
- `add-barber-npc.md`: add a reusable barber NPC that opens the character appearance editor.
- `character-creation-demo.md`: test the dedicated character creation scene and starter-kit spawn flow.
- `add-road-path.md`: add an invisible road path that NPC squads can use between settlements.
- `add-population-capacity.md`: author housing or camp capacity that determines a town's max population.
- `add-population-appearance-profile.md`: configure generated settlement resident race, sex/body type, clothing, hair, skin, and body variation.
- `add-population-name-profile.md`: configure deterministic generated settlement resident display names.
- `add-faction-culture.md`: configure faction-level behavior, personality, law, and name defaults with local overrides.
- `add-world-conflict-event.md`: configure nearby local faction conflict choices and participation-based reputation/favor rewards.

## Documentation Rule

When reusable editor content changes, update the matching operator instruction in the same task.

Good instructions include the exact scene tree path to select, the exact Godot action to use, scene or resource paths to choose, exported fields to set, required renames, and a simple done check.
