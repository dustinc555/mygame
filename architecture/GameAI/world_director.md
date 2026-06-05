# WorldDirector

WorldDirector decides what kind of pressure the world applies to the player. It does not know about rendering.

## Responsibility

```text
WorldDirector decides why and what.
PuppetMaster decides how to stage it.
GECS decides truth.
RenderProjection shows it.
```

## Inputs

- Player recent success or struggle.
- Player wounds, supplies, party size, and fatigue.
- Region danger.
- Faction reputation and heat.
- Road danger.
- Settlement state.
- Encounter cooldowns and pacing.
- Novelty and repetition limits.

## Outputs

- Create encounter objective.
- Increase or reduce pressure.
- Select faction, creature type, or event tone.
- Emit GECS records for squads, rumors, world events, or objective seeds.

## Examples

```text
Player has not struggled recently.
Region permits animal danger.
Director creates BullSquad pressure.
```

```text
Player is wounded and low on supplies.
Recent combat was high intensity.
Director creates neutral goats or a trader instead of a murder squad.
```

```text
Player stole from a faction.
Faction heat is high.
Director creates a retaliatory gang objective.
```

## Rule

Director output is abstract GECS intent. It never spawns visual actors directly.
