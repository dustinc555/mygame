# Hit

Hit is shared by weapon attacks.

## Formula

```text
hit_score = weapon_skill + dexterity * 0.25

hit_chance = clamp(
    0.50 + (hit_score - dodge_score) / 220,
    0.05,
    0.95
)
```

`weapon_skill` is the active weapon type skill.
