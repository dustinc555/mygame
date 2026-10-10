extends RefCounted

const LOCKPICKING := preload("res://features/lockpicking/sim/lockpicking_controller.gd")
const INTERACTION := preload("res://features/lockpicking/bridge/lockpick_interaction_controller.gd")
const AUDIO := preload("res://features/lockpicking/projection/unlock_audio_controller.gd")
const CORE := []
const PROJECTION := [{"name": "UnlockAudioController", "script": AUDIO, "service": AUDIO.SERVICE_ID}]
const SIM := [{"name": "LockpickingController", "script": LOCKPICKING, "service": LOCKPICKING.SERVICE_ID}]
const BRIDGE := [{"name": "LockpickInteractionController", "script": INTERACTION, "service": INTERACTION.SERVICE_ID}]
