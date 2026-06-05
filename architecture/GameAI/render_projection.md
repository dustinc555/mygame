# Render Projection

RenderProjection turns GECS state into visuals. It does not own truth.

## Rule

```text
Visual actors follow GECS.
Visual actors do not own GECS.
```

## Visual Actor

```text
VisualActor
  follows entity_id
  interpolates transform
  plays animation state
  displays equipment and appearance
  emits audio/VFX for combat beats
```

## Projection Inputs

- GECS actor records.
- GECS squad records.
- GECS transform snapshots.
- GECS animation/action state.
- CombatBeat records.
- Significance tier.
- Camera and player focus.

## Projection Outputs

- Full character projection.
- Simplified actor.
- Cluster proxy.
- Map dot.
- Sound, smoke, marker, or UI event.
- Nothing visible.

## Interpolation

Rendering may interpolate between GECS snapshots:

```text
visual_position = interpolate(previous_sim_position, current_sim_position, alpha)
visual_rotation = interpolate(previous_sim_facing, current_sim_facing, alpha)
animation = choose_from(action_state, velocity, combat_beat)
```

Interpolation is presentation only. It must not feed back into GECS truth.

## Pooling

Visual actors should be pooled and reused. Promotion and demotion should not create game truth, only views of truth.

## Collapse

If cost is too high, RenderProjection can collapse visuals:

```text
10 actors -> 4 visible actors + cluster motion
4 visible duels -> 1 highlighted duel + background fake motion
full actors -> map dots
```

The GECS state remains unchanged.
