# Body Weapons

Body weapons use the shared damage formula, but the body itself supplies the damage profile.

## Conditioning

```text
body_weapon_base_multiplier = 1 + toughness * 0.025

effective_blunt_base = blunt_base * body_weapon_base_multiplier
effective_cut_base = cut_base * body_weapon_base_multiplier
```

Feed `effective_blunt_base` and `effective_cut_base` into `damage.md`.

## Profiles

```text
human_body_weapon:
    weapon_skill = combat.unarmed
    blunt_base = 2.5
    cut_base = 0.0

wolf_body_weapon:
    weapon_skill = combat.unarmed
    blunt_base = 1.0
    cut_base = 4.0

rustdead_body_weapon:
    weapon_skill = combat.unarmed
    blunt_base = 2.5
    cut_base = 2.5
```
