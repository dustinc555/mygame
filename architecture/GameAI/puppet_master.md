# PuppetMaster

PuppetMaster makes GECS numbers feel real while controlling cost.

## Responsibility

```text
PuppetMaster pulls the strings.
Actors do not decide targets by themselves.
Rendering never changes truth.
```

PuppetMaster owns staging, pairing, realization detail, throttling, and believable behavior projection.

## What It Does

- Converts abstract squad/objective state into believable actor-level intent when needed.
- Pairs fighters in visible squad combat.
- Respects explicit player commands.
- Uses player-party behavior policy when the player is not issuing commands.
- Chooses when to promote squad records into individual actor simulation.
- Chooses when to collapse individual visuals back into squad/cluster presentation.
- Throttles animation and presentation if frame rate drops.

## What It Does Not Do

- It does not change combat outcomes because FPS dropped.
- It does not let visual nodes own game truth.
- It does not replace GECS as source of truth.
- It does not decide world pressure. That is WorldDirector.

## Player Command Priority

```text
1. Explicit player command
2. Player-party behavior policy
3. PuppetMaster squad objective
4. Far-sim approximation
```

If the player orders Mira to attack a bull, PuppetMaster adapts the battle around that order.

If the player gives no order, PuppetMaster can control Mira according to her behavior policy:

- aggressive: engage.
- defensive: protect, hold, counter.
- passive: avoid, retreat, stay behind.
- follow: stay near leader.

## Fight Presentation

For a visible 5v5 fight:

```text
PuppetMaster assigns pairs.
GECS resolves combat beats.
PuppetMaster stages movement and animation for those beats.
RenderProjection shows the result.
```

For a far fight:

```text
PuppetMaster keeps it as squad numbers.
RenderProjection may show a map dot, smoke, sound, or event text.
```

## Throttling

```text
FPS >= 30:
  show full detail

FPS 20-30:
  reduce secondary reactions and background motion

FPS < 20:
  collapse pairs or clusters, show only important beats
```

Truth stays the same in every tier.
