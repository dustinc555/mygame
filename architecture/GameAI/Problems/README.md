# GameAI Architecture

This folder defines the AI and simulation-presentation architecture. The root project architecture only states that GECS owns truth and rendering is a side effect.

## Primary Problem

The bottleneck is documented in `Problem 50v50 needs to run efficently.md`.

The target is a ground-up GECS-driven architecture where hundreds of NPCs can exist because most of them are numbers until the player can perceive detail.

## Core Stack

```text
WorldDirector
  decides world pressure and encounter tone

PuppetMaster
  controls simulation complexity and believable staging

Squad Objectives
  express work, travel, combat, guard duty, service, patrol, and encounters

GECS Fixed Tick
  resolves truth deterministically

Render Projection
  shows the subset of GECS state worth showing
```

## Hard Rules

- GECS is truth.
- Director decisions do not know or care about rendering.
- PuppetMaster may choose how much detail to simulate or show, but it must not change truth because of frame rate.
- Combat outcomes are decided before animation.
- Visuals follow GECS state and combat beats.
- Player commands override PuppetMaster control for those actors.
- If the player gives no command, player-party behavior policy lets PuppetMaster control them.
- Jobs are not actor-owned slots. Work is expressed as squad objectives.

## Documents

- `Problem 50v50 needs to run efficently.md` states the bottleneck and success criteria.
- `world_director.md` defines world pressure and encounter selection.
- `puppet_master.md` defines believable staging, pairing, and throttling.
- `squad_objectives.md` defines work and jobs as squad objectives.
- `combat_beats.md` defines outcome-first combat presentation.
- `render_projection.md` defines how visuals follow GECS state.
- `fixed_tick_and_lod.md` defines fixed logic tick and complexity tiers.

## One Sentence

```text
The game is GECS numbers first, PuppetMaster illusion second, rendered nodes last.
```
