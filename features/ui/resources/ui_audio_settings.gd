@tool
extends Resource
class_name UIAudioSettings

const SoundCue := preload("res://features/audio/resources/game_sound_cue.gd")

@export_group("UI Audio")
## Disabling takes effect on the next interaction; reinitialize to stop current tails.
@export var enabled := true
## Overall screen-space UI gain, added to each cue's gain (decibels).
@export_range(-60.0, 0.0, 0.5) var volume_db := -18.0
## Maximum simultaneous UI voices. Oldest voice is replaced when full.
@export_range(1, 8, 1) var polyphony := 3

@export_group("Accepted Actions")
@export var click: SoundCue
## Explicit menu-close actions only, never ordinary toggles changing state.
@export var menu_close: SoundCue

@export_group("Merchant Trade")
## Successful settlement that pays or receives silver.
@export var trade_money: SoundCue
## Successful goods exchange with no silver changing hands.
@export var trade_barter: SoundCue
