# Setup

## LimboAI

LimboAI is required for realized actor behavior execution, but its GDExtension binaries are not versioned in this repository.

Run this from the project root before opening or validating the project if `addons/limboai/` is missing:

```bash
./setup_limboai.sh
```

The script downloads the official LimboAI `v1.7.0` Godot 4.6 GDExtension release, verifies its SHA256, and extracts only `addons/limboai/`.

Do not commit `addons/limboai/`; it is intentionally ignored.

## Tests / GUT

GUT v9.6.1 is vendored at `addons/gut/` and enabled in the project's Plugins list. It needs no package manager or separate download after checkout. Let Godot finish its first import so its script classes and addon resources are registered.

`./tests/run.sh` runs the complete fast GUT unit suite in `tests/unit/`. Validation scenarios and benchmarks are run separately when relevant. See [tests/TESTING.md](tests/TESTING.md) for commands, editor configuration, and pre-commit hook setup.
