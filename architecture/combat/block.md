# Block

Block is mitigation after a hit lands.

## Parry

Used when no shield is equipped.

```text
parry_score = weapon_skill + dexterity * 0.25 + weapon_parry_bonus
```

## Shield Block

Used when a shield is equipped.

```text
shield_block_score = combat.shields + strength * 0.25 + shield_block_bonus
```

## Chance

```text
defense_chance = clamp(
    0.15 + (defense_score - hit_score) / 220,
    0.02,
    0.75
)
```

## Mitigation

```text
blunt_damage *= block_damage_multiplier
cut_damage *= block_damage_multiplier
```

Most weapons have `weapon_parry_bonus = 0`.

Shields provide `shield_block_bonus` and `block_damage_multiplier`.

Shield dexterity penalties are equipment modifiers, not block formula terms.
