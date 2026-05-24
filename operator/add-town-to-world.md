# Add Town To World

Use this after a town has its own scene file.

1. Open the persistent world scene.

2. Select the world root or the intended streamed-town container.

3. Instance the town scene, such as:

```text
res://scenes/world/towns/farmer_crossing.tscn
```

4. Move the town instance to its world position.

5. Keep per-town customization in the town scene itself. Avoid editing town children as local overrides in the persistent world unless the override is truly world-placement-specific.

6. If the town will stream at runtime, add or configure the streaming metadata/anchor used by the open-world streamer when that system exists.

Done check: the persistent world should show a town instance, while opening the town scene directly should show editable children like `Bars`, `Residents`, `Storage`, and `ActivityPoints`.
