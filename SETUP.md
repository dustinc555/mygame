# Setup

## Requirements

- Godot 4.6.x.
- Repository submodules initialized, including `addons/gecs/`.

## LimboAI

LimboAI is available as a local decision-tree/GDExtension tool. Its binaries are not versioned in this repository.

Run this from the project root before opening or validating the project if `addons/limboai/` is missing:

```bash
./setup_limboai.sh
```

The script downloads the official LimboAI `v1.7.0` Godot 4.6 GDExtension release, verifies its SHA256, and extracts only `addons/limboai/`.

Do not commit `addons/limboai/`; it is intentionally ignored.
