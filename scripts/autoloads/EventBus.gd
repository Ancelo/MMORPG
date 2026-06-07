## Global event bus for decoupled communication between systems.
extends Node

# --- Network ---
signal player_connected(peer_id: int)
signal player_disconnected(peer_id: int)
signal connection_failed()
signal server_disconnected()

# --- Character lifecycle ---
signal character_spawned(character: Node, peer_id: int)
signal character_despawned(peer_id: int)
signal character_died(character: Node)
signal character_respawned(character: Node)

# --- Combat ---
signal damage_dealt(attacker: Node, target: Node, amount: int, damage_type: String)
signal heal_applied(healer: Node, target: Node, amount: int)
signal ability_used(caster: Node, ability_id: String)
signal ability_cooldown_changed(ability_id: String, remaining: float)
signal status_effect_applied(target: Node, effect_id: String, duration: float)
signal status_effect_removed(target: Node, effect_id: String)

# --- Targeting ---
signal target_changed(new_target)

# --- Zone ---
signal zone_loaded(zone_id: String)
signal zone_enter_requested(zone_id: String, entry_point: String)

# --- UI ---
signal chat_message_received(sender: String, message: String, channel: String, faction: int)
signal notification_pushed(text: String, category: String)
signal quest_updated(quest_id: String)
signal inventory_changed()
signal xp_gained(amount: int, total: int, level: int)
signal level_up(new_level: int, character_class: String)

# --- RvR (Realm vs Realm) ---
signal rvr_objective_captured(objective_id: String, faction: int)
signal rvr_score_updated(roman: int, galli: int, germani: int)
signal rvr_kill_announced(killer: String, victim: String, killer_faction: int, victim_faction: int)
