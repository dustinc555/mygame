# Bestiary — Dungeon Monsters Kit (Source)

Purchased Quaternius pack: https://quaternius.com/packs/bestiarydungeonmonsterskit.html

**License: bundled Quaternius Asset License (QAL) v1.0, not CC0.** See
`License_Source.txt`. Keep this family within the licensed product/collaborator
workflow; do not redistribute it as a standalone asset collection.

## Runtime models

`glb/{Hellwarden,Imp,Lycan,Puglin,Skeleton_A,Skeleton_B,Tidebreaker}.glb`
are the vendor's original Godot/Unreal exports, preserved byte-for-byte. Existing
repository `*.glb` Git LFS policy applies. No combat or gameplay wiring is added.

All **seven models have zero embedded animation clips**, and background Blender
inspection of **all seven source .blend files found zero actions** (including
unassigned action datablocks), no active object actions, and no NLA tracks.
These are rigged assets, not an animation library. An explorer must honestly
show no available clips; it must not present RESET, generated idle motion, or
unrelated retargeted animations as supplied clips.

`animation_inspection.json` records source/archive/GLB SHA-256 hashes, per-model
rigs, action counts, and embedded clip counts. Blender 5.2.1 LTS opened temporary
copies with factory settings, UI loading disabled, and embedded Python scripts
disabled. The downloaded archive was untouched. No source blends, FBX duplicates,
or archive were copied into the repository.

## Textures and import

Base textures remain embedded in each GLB. Godot import sidecars explicitly use
**Embed as Basis Universal** (`gltf/embedded_image_handling=2`) rather than
extracting duplicate loose maps. Animation import stays enabled, but importing
the rest pose as RESET is disabled. Scale remains 1.0.

Twenty original optional variation maps are retained in
`reference_texture_variants/`, with `.gdignore` so they are not silently imported
or applied. They include base-color variations and model-specific ORM/emission
maps; Skeleton_A and Skeleton_B share the Skeleton maps. For future runtime
variation support, move only the needed maps into a runtime texture directory,
explicitly configure 3D compression/mipmaps, and wire their matching materials.
Unreal normal-map duplicates were not retained.

Import was scoped to exactly seven GLBs in a temporary minimal Godot project at
the **same res:// paths**, with no project plugins or gameplay. The resulting
seven `.import` sidecars and corresponding `.godot/imported` cache files were
copied into this checkout; the cache is untracked. No production editor or game
was launched or restarted. `godot_verification.json` records a subsequent real
`load()` + instantiate check against this checkout for all seven models,
including mesh/skeleton counts, material texture paths, and actual clip lists.
