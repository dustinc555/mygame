# Add Barber NPC

Use this to add a reusable barber who can edit hair, beard, and hair/beard colors through the bootstrapped character appearance editor. Eyebrow style is assigned automatically from body type, and eyebrow color follows hair color.

1. Select the scene root or the town/NPC container where the barber should live.

2. Right-click the selected node.

3. Click `Instantiate Child Scene...`.

4. Choose `res://scenes/characters/vendors/barber_npc.tscn`.

5. Rename the instance for the location, such as `FarmerCrossingBarber`.

6. Move the barber to the intended world position.

7. Set these inspector fields on the barber if the defaults are not right for the location:

```text
member_name = Barber
faction_name = Town
conversation_definition = res://resources/conversations/barber_services.tres
barber_service_price = 1
starting_equipment = noble doublet, noble trousers, noble shoes or another outfit
```

8. Keep the barber in a bootstrapped scene with `GameHUD`; `GameBootstrap` creates `CharacterAppearanceController` and owns the editor window.

9. Done: talking to the barber shows the barber service response, charges the speaking actor `barber_service_price` silver up front, pauses the world, opens the opaque full-screen draft editor, and applies changes only when `Save` is pressed.

The preview shows the actor's current clothes, supports full-body and compact Face-toggle views, supports mouse-drag yaw/pitch rotation, and filters body-specific options such as hair styles and beards.

Barber update mode does not expose Race, Sex, body adjusters, or skin color. Use the dedicated character creation flow for those controls.

Cancel check: open the barber editor, change a style, press `Cancel`, and confirm the actor's live appearance did not change.
