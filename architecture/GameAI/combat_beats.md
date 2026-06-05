# Combat Beats

Combat is outcome-first.

## Rule

```text
The sword swing does not cause damage.
GECS decides damage.
The sword swing visualizes that decision.
```

## Beat Record

```text
CombatBeat
  beat_id
  tick
  attacker_id
  defender_id
  action
  result
  damage
  wound_target
  stamina_delta
  position_hint
  animation_hint
  importance
```

## Results

- hit.
- block.
- dodge.
- miss.
- stagger.
- knockdown.
- death.

## Flow

```text
PuppetMaster assigns pairings.
GECS combat system resolves beats.
PuppetMaster stages beats.
RenderProjection plays animation, audio, VFX, and interpolation.
```

## Visible Fight

For a player-watched 5v5 fight, every important strike should map to a beat record.

```text
tick 120: bull_01 charges mira, result dodge
tick 132: mira slashes bull_01, result hit, damage 18
tick 150: bull_02 hits tomas, result block
```

The player should feel the fight, but the truth is still numbers first.

## Throttled Fight

When presentation cost is too high:

- Combine minor beats.
- Hide low-importance reactions.
- Show only decisive hits, blocks, wounds, and deaths.
- Collapse background actors into clusters.

The beat transcript and final GECS outcome do not change.
