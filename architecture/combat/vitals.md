# Vitals

Vitals decide KO, recovery coma, dying, and death.

These are default rules for a typical GECS combat entity.

Specific races, body plans, machines, animals, bosses, or undead actors may override parts, thresholds, blood, recovery, or death behavior.

## Body Plan

Each body defines its own parts.

```text
body_part:
    id
    max_health
    consciousness
    death_critical
```

`consciousness` parts can cause KO or coma.

`death_critical` parts can cause dying or death.

## Thresholds

```text
ko_point = 0

coma_point =
    -part_max_health
    * clamp(0.10 + toughness * 0.0075, 0.10, 0.85)

death_point = -part_max_health
```

## States

```text
if any consciousness part <= ko_point:
    unconscious

if any consciousness part <= coma_point:
    recovery_coma

if any death_critical part <= death_point:
    dying
```

Recovery coma ends only when all consciousness parts are above `0`.

## Dying

Dying is a rescue window before death.

```text
dying_seconds = 20 + toughness * 0.8
```

If the timer expires, the actor dies.

## Blood

```text
if blood <= 0:
    unconscious

if blood <= -max_blood:
    dying
```

## Recovery

```text
ground = 1x healing
camp_bed = 4x healing
bed = 8x healing
```

Open wounds keep bleeding until treated.
