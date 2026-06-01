# Initiative

Initiative decides which ready melee attacker acts next.

## Formula

```text
initiative_weight = max(1, dexterity) + initiative_credit

winner = weighted_random(ready_attackers, initiative_weight)
```

Winner credit resets to `0`.

Losers gain initiative credit so low-dex fighters can still eventually act.
