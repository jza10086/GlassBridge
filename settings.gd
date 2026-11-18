extends RefCounted
const Definition = preload("definition.gd")
const KEYS: Dictionary[String, Key] = {"glass_bridge_left": KEY_A, "glass_bridge_right": KEY_D, "glass_bridge_forward": KEY_W, "glass_bridge_back": KEY_S, "glass_bridge_jump": KEY_SPACE, "glass_bridge_sprint": KEY_SHIFT}

static func schema() -> Dictionary:
	var titles: Dictionary = Definition.party_definition().controls
	var fields: Dictionary = {}
	var layout: Array[Dictionary] = []
	for action: String in KEYS:
		fields[action] = {"type": "array", "control": "binding", "action": action, "title": titles[action],
			"default": [{"kind": "key", "code": KEYS[action], "physical": true}],
			"audience": "local", "apply": "immediate", "items": {"type": "object", "format": "binding"},
			"max_items": 2, "combinations": false}
		layout.append({"field": action})
	return {"schema_format": 3, "settings_version": 1, "fields": fields, "layout": layout}
