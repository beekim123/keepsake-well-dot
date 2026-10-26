extends RefCounted
## Conditional story sequencing only; StoryView renders layers and voice bleeps.
var pages: Array = []
var index: int = 0
var sequence: Dictionary = {}
var context: Dictionary = {}

func begin(definition: Dictionary, conditions: Dictionary = {}) -> void:
	sequence = definition.duplicate(true)
	context = conditions.duplicate(true)
	pages.clear()
	index = 0
	for page: Dictionary in sequence.get("pages", []):
		var when: Dictionary = page.get("when", {})
		if when.has("wish"):
			var wishes: Dictionary = context.get("wishes", {})
			if not bool(wishes.get(str(when["wish"]), false)):
				continue
		pages.append(page.duplicate(true))

func current() -> Dictionary:
	return pages[index].duplicate(true) if index < pages.size() else {}

func advance() -> bool:
	index = mini(index + 1, pages.size())
	return finished()

func skip() -> void:
	index = pages.size()

func finished() -> bool:
	return index >= pages.size()

func stamp() -> String:
	# Core, not presentation, selects the actual normal/plus unlock.
	return str(context.get("card_id", ""))
