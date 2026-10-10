# UI audio

## Designer controls

In Godot's **FileSystem**, select
`res://features/ui/resources/ui_audio_settings.tres`, then edit its **Inspector**:

- **UI Audio → Enabled**: gates new UI sounds; default on.
- **Volume Db**: overall gain in decibels; default **−18 dB**, Inspector range −60 to 0 dB. Each cue's gain is added to this.
- **Polyphony**: simultaneous non-positional `AudioStreamPlayer` voices; default **3**, runtime limit **1–8**. An idle voice is reused, otherwise the oldest voice is replaced.
- **Accepted Actions → Click / Menu Close**: expand the authored `GameSoundCue` to edit its recording and gain. Each uses exactly one audition-approved file and fixed pitch **1.0**. Do not reintroduce alternating variants or random pitch.
- **Merchant Trade → Trade Money / Trade Barter**: the coin recording when silver is paid or received, or the cloth shuffle when the settled exchange moves no silver. Expand either cue to change its recording or **Volume Db**; both use fixed pitch **1.0** and share the UI gain and voice budget.

Saved edits apply when the game next loads this resource. Editing the running
controller's resource takes effect on the next accepted interaction; shrinking
polyphony releases excess players on that interaction. Existing tails keep their
current gain. Disabling blocks new starts, not existing tails. Reinitializing or
removing the controller stops all its voices. Runtime edits are not a saved player
preferences system.

## Scope and ownership

`ui_module.gd` registers one `UIAudioController` projection service. It observes
only the injected `BootstrapContext.root_scene` at runtime: one initial traversal
(including internal controls), then `SceneTree.node_added` / `node_removed` events.
There is no per-frame tree scan or global autoload. Close controls explicitly
declare their audio action in metadata; the shared controller owns playback.

- `BaseButton.pressed`: the same click for ordinary buttons and both toggle states.
  Controls with **Metadata → ui_audio_action = "close"** use Menu Close instead.
  This is assigned to inventory, jobs, skills, factions, facility-people, ledger,
  atlas, debug-panel and character-editor cancel controls, plus pause-menu Resume.
  It does **not**
  observe `toggled`, so startup state, programmatic setters and radio-group
  deselection stay silent. Mouse and keyboard activation use the same path.
- `PopupMenu.index_pressed`: one ordinary choice cue, including the internal
  popup of `OptionButton`. Opening the button and choosing an item are separate
  actions. `OptionButton.item_selected` is deliberately not connected as well.
- `TabBar.tab_clicked`: one mouse tab cue; programmatic selection and keyboard
  selection changes do not produce extra sounds through `tab_changed`.
- Merchant **Trade** opts out of ordinary button clicks. After a successful
  settlement, `PartyInventoryController` calls the injected UI audio service with
  the deal's net silver captured before commit clears its offers. Nonzero payment
  in either direction uses Trade Money; zero uses Trade Barter. Failed or empty
  trades are silent and retain their existing error feedback. Reset remains an
  ordinary button. Missing trade recordings never fall back to the click.
- Hover, focus, cancellation, disabled/hidden controls, and missing audio are
  silent. No inventory-drag, reward, quest, door, footstep or ambience events are
  wired here.
- Character portrait cards opt out with `ui_audio_disabled = true`: selecting
  or switching characters remains silent, without disabling selection itself.
- Keyboard activation of a close button follows the same close cue. Global
  menu hotkeys and automatic visibility changes are not observed by this service;
  hiding/replacing a menu programmatically does not cause an extra sound.

Buttons capture input eligibility before existing action handlers run, so a
Resume/Close button can hide, disable or remove itself without losing its accepted
click. Popup closing eligibility survives only the synchronous selection because
Godot hides a popup before emitting its selection signal. Weak references,
explicit disconnection and generation-checked deferred cleanup prevent stale
bindings across removal, re-addition, reinitialization and controller teardown.
The controller and its voices process while paused; a paused menu must itself be
configured to accept input while paused.

To silence a control **or an entire UI subtree**, select that node in the
Inspector, add boolean **Metadata → ui_audio_disabled**, and set it to `true`.
This is checked at interaction time and requires no signal code. Do not manually
emit accepted-action signals for programmatic refreshes; use the controls' state
setters instead.

## Recordings and verification

The authored cues refer by file path (not audio preloads) to Dustin's exact
selected recordings:

- Click: `UIClick_Button click_GfxSounds_FantasyGameBundle.wav`.
- Menu Close only: `UIClick_Switch off 2_GfxSounds_FantasyGameBundle.wav`.
- Trade with silver: `OBJCoin_Coin pickup handling 2_GfxSounds_FantasyGameBundle.wav`.
- Trade without silver: `CLOTHHndl_Inventory clothes shuffle_GfxSounds_FantasyGameBundle.wav`.

The other click/switch variants are not used. No long Toggle switch sequences or
Adventure/Fantasy/Classic tonal cues are selected. Native playback tests verify
routing, not subjective sound quality or the in-game mix.
Licensed audio import and provenance remain with the vendor asset family under
`assets/vendor/gfxsounds-studios/fantasy-game-bundle/`.

`tests/unit/test_ui_audio.gd` loads the production settings and uses real controls
with viewport mouse/keyboard input. Synthetic PCM is injected only at the shared
cue's stream-cache boundary, allowing player starts, pooling and tuning to be
verified without requiring licensed audio on a fresh checkout. Missing paths
remain silent rather than preventing the UI module from loading.

`tests/unit/test_trading_grid.gd` also drives the production Trade button with
mouse/keyboard input and checks payment, barter, refusal, rollback, gain/muting,
missing recordings and no duplicate click. It exercises both imported trade
recordings through native players when available locally.

Focused verification: `./tests/run.sh unit -gselect=test_ui_audio.gd` and
`./tests/run.sh unit -gselect=test_trading_grid.gd`.
