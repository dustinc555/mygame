# Problem: 50v50 Needs To Run Efficiently

This is the bottleneck document.

The game must support hundreds of NPCs and visible fights like 50v50 without treating every actor as an independent scene-node brain.

## Current Problem

```text
Per-node decision loops + per-actor target selection do not scale.
```

It creates three failures:

- CPU cost grows with every realized actor.
- Behavior becomes a ball of mud when projected nodes own decisions.
- Rendering and gameplay truth become tangled.

## Target Principle

```text
Simulate truth cheaply.
Show detail only where the player can perceive it.
```

For a 50v50 fight, the game should not need 100 independent scene-node decision loops every frame. It should have squad/objective state, pairing assignments, and combat beats produced from GECS truth.


## Reading Material

- https://generalistprogrammer.com/game-ai-development#overview
