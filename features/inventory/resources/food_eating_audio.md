# Eating audio

Every successful food-item consumption in `inventory_item_actions.gd` triggers
`FoodEatingAudio` on the eater, after the inventory transaction succeeds. Manual
inventory actions and automatic food sharing use this same path. Party membership,
race and the source inventory do not select different sounds. Failed attempts,
digestion ticks and restored hunger state do not play a meal.

The shared cue randomly chooses one of the eight adopted `FOODEat` recordings,
without immediately repeating the same clip for that actor. No drinking or combat
bite sounds are included. Playback is positional and follows the actor. Each actor
lazily creates one reusable voice; it is freed with that actor. An accepted meal
can play while the world is paused, just as its inventory action can succeed.

## Tune in Godot

- Open `res://features/inventory/resources/food_eating_sound.tres` in the Inspector.
  **Volume Db** changes the shared eating gain; **Paths** edits the clip selection.
  **Pitch Min/Max** are both `1.0`, preserving the recordings' original pitch.
- Open `res://features/inventory/projection/food_eating_audio.tscn`, select its root
  **FoodEatingAudio**, and edit the native **Max Distance** (meters) and **Unit Size**
  (attenuation scale, meters). Defaults are 45 m and 6 m respectively. The listener
  is the viewport's 3D listener, normally the gameplay camera, not the selected actor.
- Live cue edits apply to the next successful meal. Saved cue/scene edits take
  effect after restarting an already-running game; existing voices retain their
  instantiated distance controls.

The purchased WAV files and import sidecars stay local and Git-ignored under
`assets/vendor/gfxsounds-studios/fantasy-game-bundle/audio/Foley Interactions/Food Drink/`.
Missing licensed files leave gameplay functional but silent; see the vendor's
README and selected manifest for rehydrating an owner's checkout.
