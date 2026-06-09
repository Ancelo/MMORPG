## Crafting system: recipes, resource gathering, and skill-based success chance.
## Skills: Fabbro (blacksmith), Cuoiaio (leatherworker), Erborista (herbalist), Cuoco.
class_name CraftingSystem
extends Node

const MAX_CRAFT_SKILL := 500

var _recipes: Dictionary = {}  # recipe_id -> recipe data

func _ready() -> void:
	add_to_group("crafting_system")
	_load_recipes()

func _load_recipes() -> void:
	var dir := DirAccess.open("res://data/crafting/")
	if not dir:
		return
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if fname.ends_with(".json"):
			var file := FileAccess.open("res://data/crafting/" + fname, FileAccess.READ)
			if file:
				var parsed: Variant = JSON.parse_string(file.get_as_text())
				if parsed is Array:
					for recipe in parsed:
						_recipes[recipe["id"]] = recipe
		fname = dir.get_next()

# ----- Crafting -----

func can_craft(recipe_id: String, crafter: Character) -> String:
	var recipe: Dictionary = _recipes.get(recipe_id, {})
	if recipe.is_empty():
		return "Ricetta non trovata"
	var required_skill: int = recipe.get("required_skill", 0)
	var skill_type: String = recipe.get("skill", "fabbro")
	var crafter_skill := _get_craft_skill(crafter, skill_type)
	if crafter_skill < required_skill:
		return "Abilità %s insufficiente (%d < %d)" % [skill_type, crafter_skill, required_skill]
	if not _has_ingredients(recipe, crafter):
		return "Ingredienti mancanti"
	return ""

func craft(recipe_id: String, crafter: Character) -> bool:
	var reason := can_craft(recipe_id, crafter)
	if reason != "":
		EventBus.notification_pushed.emit("Non puoi creare: %s" % reason, "crafting")
		return false

	var recipe: Dictionary = _recipes[recipe_id]
	var inventory := crafter.get_node_or_null("Inventory") as Inventory
	if not inventory:
		return false

	_consume_ingredients(recipe, inventory)
	var success := _roll_success(recipe, crafter)

	if success:
		var result_item: String = recipe.get("result_item", "")
		var result_count: int = recipe.get("result_count", 1)
		inventory.add_item(result_item, result_count)
		_gain_skill_xp(crafter, recipe.get("skill","fabbro"), recipe.get("skill_xp", 10))
		EventBus.notification_pushed.emit("Hai creato: %s!" % result_item, "crafting")
	else:
		# Partial failure: return some materials
		EventBus.notification_pushed.emit("La creazione è fallita. Alcuni materiali sono andati persi.", "crafting")

	return success

func _has_ingredients(recipe: Dictionary, crafter: Character) -> bool:
	var inventory := crafter.get_node_or_null("Inventory") as Inventory
	if not inventory:
		return false
	for ingredient in recipe.get("ingredients", []):
		var item_id: String = ingredient["item"]
		var needed: int = ingredient.get("count", 1)
		var found := 0
		for entry in inventory.bags:
			if entry != null and entry["item"].item_id == item_id:
				found += entry["count"]
		if found < needed:
			return false
	return true

func _consume_ingredients(recipe: Dictionary, inventory: Inventory) -> void:
	for ingredient in recipe.get("ingredients", []):
		var item_id: String = ingredient["item"]
		var needed: int = ingredient.get("count", 1)
		for i in range(inventory.bags.size()):
			if needed <= 0:
				break
			var entry: Dictionary = inventory.bags[i] if inventory.bags[i] != null else {}
			if entry.is_empty():
				continue
			if entry["item"].item_id != item_id:
				continue
			var take := min(needed, entry["count"])
			inventory.remove_item(i, take)
			needed -= take

func _roll_success(recipe: Dictionary, crafter: Character) -> bool:
	var required_skill: int = recipe.get("required_skill", 0)
	var crafter_skill := _get_craft_skill(crafter, recipe.get("skill","fabbro"))
	if crafter_skill >= required_skill + 100:
		return true  # guaranteed success if well above minimum
	var chance := 0.5 + (crafter_skill - required_skill) * 0.005
	return randf() < clampf(chance, 0.1, 0.98)

func _get_craft_skill(character: Character, skill: String) -> int:
	# Crafting skills stored in character data; default 0 for new characters
	return character.get_meta("craft_%s" % skill, 0)

func _gain_skill_xp(character: Character, skill: String, xp: int) -> void:
	var key := "craft_%s" % skill
	var current: int = character.get_meta(key, 0)
	character.set_meta(key, min(current + xp, MAX_CRAFT_SKILL))

func get_recipes_for_skill(skill: String, skill_level: int) -> Array:
	var result: Array = []
	for recipe in _recipes.values():
		if recipe.get("skill","") == skill and recipe.get("required_skill", 0) <= skill_level:
			result.append(recipe)
	return result
