# Open World Streaming

The game is targeting a seamless open world. Seamless does not mean every city, prop, NPC, and activity point should be authored inside one giant editable scene tree.

## Pattern

Use one persistent world scene for global systems, terrain, roads, streaming anchors, and always-on controllers.

Author each city, town, camp, dungeon entrance, or dense point of interest as its own scene. Example paths:

```text
scenes/world/towns/farmer_crossing.tscn
scenes/world/towns/raider_camp.tscn
scenes/world/camps/old_mill_bandits.tscn
```

The persistent world places or streams those scenes. Operators open the town scene directly when they need to edit children such as `Bars`, `Fields`, `Residents`, `Storage`, `ActivityPoints`, guard posts, furniture, and interiors.

## Industry Reference

Large open-world games generally split authored world content into streamable units. Unreal World Partition uses distance-based cells loaded by streaming sources. Unity projects often use additive scene loading. In Godot, use scene instances plus `ResourceLoader.load_threaded_request()` / `load_threaded_get()` for asynchronous loading.

The common idea is the same: keep global simulation data separate from near-player loaded gameplay scenes.

## Runtime Tiers

Use three mental tiers:

1. World data: settlement definitions, faction state, roads, diplomacy, supply, known positions, and simulation records that can exist while the visual town is unloaded.
2. Proxy content: far labels, map markers, HLOD/low-detail silhouettes, ambient smoke/lights, or other cheap markers.
3. Full content: the loaded town scene with buildings, collision, NPCs, inventories, activity points, beds, shops, and interaction logic.

The player should cross between these tiers without a loading screen. Full town scenes should be requested before the player reaches interaction distance and unloaded after the player is safely far away.

## Authoring Rule

Do not solve editor scale by filtering a giant tree. Solve it by making towns independent scenes.

The open world may use editable children for exceptional placement tweaks, but normal town customization belongs in the town scene itself. This keeps source files smaller, avoids accidental edits to unrelated towns, and lets multiple towns be edited independently.

## Coordinates

Godot single-precision worlds remain reliable for normal open-world sizes, but precision worsens far from origin. If the playable world grows beyond practical single-precision ranges, choose a deliberate strategy: origin shifting, chunk-local coordinates, or a double-precision Godot build. Do not mix very large coordinates into gameplay code casually.
