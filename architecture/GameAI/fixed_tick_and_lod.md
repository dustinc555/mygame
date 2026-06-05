# Fixed Tick And LOD

Game logic runs on a fixed GECS tick. Rendering runs whenever it can.

## Rule

```text
Variable frame rate must not change gameplay truth.
```

## Tick Model

Target starting point:

```text
logic_tick_hz = 30
logic_dt = 1.0 / 30.0
```

This value can change after profiling, but the model stays fixed tick.

## Runtime Loop

```text
accumulate render delta
while accumulator >= logic_dt:
  consume command buffer
  run GECS systems
  write snapshot
  accumulator -= logic_dt

render:
  read snapshots
  interpolate visuals
```

## Complexity Tiers

```text
Tier 0: player party explicit commands
  full detail

Tier 1: player-watched combat or interaction
  actor-level sim and full beats

Tier 2: nearby but not focused
  reduced updates and simplified presentation

Tier 3: region-level squads
  squad sim, sparse actor realization

Tier 4: far world
  ledger numbers, map dots, no actors
```

## Significance Inputs

- Distance to player.
- Camera viewport visibility.
- Player attention or selection.
- Combat danger.
- Story/event importance.
- Squad/objective importance.
- Current frame cost.

## FPS Throttling

```text
FPS >= 30:
  normal presentation

FPS 20-30:
  reduce secondary visuals

FPS < 20:
  collapse low-importance presentation aggressively
```

Throttling changes display, not GECS outcome.
