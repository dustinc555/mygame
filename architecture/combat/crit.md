# Crit

Crit is shared by weapon attacks.

## Formula

```text
crit_chance = clamp(
    0.05
    + max(0, weapon_skill - 1) * 0.00303
    + max(0, dexterity - 1) * 0.00190,
    0.0,
    1.0
)
```

`weapon_skill` is the active weapon type skill.

## Damage

```text
if crit:
    crit_multiplier = random(2.0, 3.0)
    blunt_damage *= crit_multiplier
    cut_damage *= crit_multiplier
```
