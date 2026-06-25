# Add World Conflict Event

Use this for nearby player choices in raids, ambushes, caravan attacks, survivor rescues, or similar faction conflicts.

1. Add or spawn a `WorldConflictEvent` node with `res://src/world_sim/sim/world_conflict_event.gd`.
2. Set `event_id` to a stable unique event instance ID.
3. Set `side_a_faction_id`, `side_a_label`, `side_b_faction_id`, and `side_b_label`.
4. Place the node at the conflict location and set `event_radius` to the distance where the player should be offered the choice.
5. Set `participation_seconds_required`, `reputation_gain`, `favor_gain`, and `opposed_reputation_loss`.
6. Fill `side_a_actor_paths` and `side_b_actor_paths` when temporary event hostility should be applied to specific actors.
7. Register it with `WorldEventChoiceController.register_conflict_event`, or create it through `WorldEventChoiceController.create_conflict_event`.

The popup appears only once per event instance and only when a player party member is inside the event radius. Choosing a side creates temporary event hostility, but reputation and favors are awarded only after the player contributes enough time or combat presence. Leaving immediately after choosing gives no reward and no opposing penalty.

Done check: enter the event radius, choose a side, confirm the game pauses for the prompt, and confirm reputation/favor changes only after participation is satisfied.
