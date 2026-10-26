extends Node
## Reads only registered, synchronized content. Player-facing strings live in ui.json.

const REGISTRY_PATH: String = "res://data/registry.json"
var _entries: Dictionary = {}
var _tables: Dictionary = {}
var valid: bool = false

func _ready() -> void:
	valid = reload_content()

func reload_content() -> bool:
	_entries.clear()
	_tables.clear()
	var registry: Variant = _read_json(REGISTRY_PATH)
	if not registry is Dictionary or registry.get("format", "") != "content/1":
		push_error("ContentCatalog: invalid content/1 registry")
		return false
	for item: Dictionary in registry.get("files", []):
		var target: String = str(item.get("target", ""))
		if target.is_empty() or target.contains("..") or target.is_absolute_path():
			push_error("ContentCatalog: unsafe registry target")
			return false
		var table: Variant = _read_json("res://data/" + target)
		if not table is Array:
			push_error("ContentCatalog: expected array at " + target)
			return false
		_tables[str(item.get("id", ""))] = table
		for entry: Dictionary in table:
			var key: String = str(entry.get("id", ""))
			if key.is_empty() or _entries.has(key):
				push_error("ContentCatalog: duplicate or empty content id: " + key)
				return false
			_entries[key] = entry
	return true

func definitions() -> Dictionary:
	# Return parsed data only; pure rules never know the filesystem.
	return _tables.duplicate(true)

func has_entry(key: String) -> bool:
	return _entries.has(key)

func format_text(key: String, values: Dictionary = {}) -> String:
	# JSON parses whole numbers as floats; presentation should still say 40/40.
	var display: Dictionary = values.duplicate()
	for token: Variant in display:
		var value: Variant = display[token]
		if value is float and is_finite(value) and value == floor(value):
			display[token] = int(value)
	return text(key).format(display)

func text(key: String) -> String:
	var entry: Dictionary = _entries.get(key, {})
	if not entry.has("text"):
		push_error("ContentCatalog: missing text id " + key)
		return ""
	return str(entry["text"])

func entry(key: String) -> Dictionary:
	return _entries.get(key, {}).duplicate(true)

func table(key: String) -> Array:
	return _tables.get(key, []).duplicate(true)

func _read_json(path: String) -> Variant:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var parser: JSON = JSON.new()
	if parser.parse(file.get_as_text()) != OK:
		return null
	return parser.data
