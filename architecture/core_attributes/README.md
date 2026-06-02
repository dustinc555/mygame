# Core Attributes

Core attributes and skills start as raw actor values, then resolve into final effective values through fixed layers.

## Layers

```text
raw stat
-> racial performance modifiers
-> body and cybernetic modifiers
-> item and equipment modifiers
-> injury and condition modifiers
-> final effective stat
```

Each layer sums its modifiers before applying them:

```text
value_after_layer = value_before_layer * (1 + sum(layer_modifiers))
```

## Progression

Stats and skills are mostly linear and are not capped.

Final outputs may clamp when the output itself requires it, such as chances from `0%` to `100%`.

## Learning

Learning modifiers affect XP only. They do not change effective stats.

```text
xp_gained = base_xp * learning_modifiers
```

## Toughness Training

Toughness XP comes from:

```text
taking damage
being knocked out
entering recovery coma
forcing yourself up while threatened
```

Forcing yourself up while wounded gives the largest reward.
