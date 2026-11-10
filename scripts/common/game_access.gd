extends RefCounted
## How a screen reaches the game (docs/leader/13 design, section 5).
##
## A screen uses the autoload "Game" unless another object was given to it
## before it entered the tree (tests do that). The object is only used through
## the contract; this script checks that the contract is there and reads the
## core and its state without holding on to them.

const AUTOLOAD_PATH: NodePath = ^"/root/Game"
const CORE_PROPERTY: StringName = &"core"
const STATE_PROPERTY: StringName = &"state"
const REQUIRED_SIGNALS: Array[StringName] = [&"game_started", &"game_ended"]
const REQUIRED_METHODS: Array[StringName] = [
	&"has_save", &"new_game", &"continue_game", &"end_game",
	&"set_time_blocked", &"is_time_blocked",
]


## The game object for the node: the given one, or the autoload "Game".
## Returns null and reports an engine error that names what is missing when
## there is none or when it does not follow the contract.
static func resolve(node: Node, given: Object, who: String) -> Object:
	var game: Object = given
	if game == null or not is_instance_valid(game):
		game = node.get_node_or_null(AUTOLOAD_PATH)
	if game == null:
		push_error("%s: 게임 객체가 없습니다. 전역 객체 Game이 등록되지 않았고 set_game()으로 지정한 객체도 없습니다." % who)
		return null
	var missing: PackedStringArray = PackedStringArray()
	if not CORE_PROPERTY in game:
		missing.append(String(CORE_PROPERTY))
	for signal_name: StringName in REQUIRED_SIGNALS:
		if not game.has_signal(signal_name):
			missing.append("signal " + String(signal_name))
	for method: StringName in REQUIRED_METHODS:
		if not game.has_method(method):
			missing.append(String(method) + "()")
	if not missing.is_empty():
		push_error("%s: 게임 객체가 계약을 따르지 않습니다. 없는 것: %s" % [who, ", ".join(missing)])
		return null
	return game


## The game in progress, or null. Read it again each time; do not keep it.
static func core_of(game: Object) -> Object:
	if game == null or not is_instance_valid(game):
		return null
	var core: Variant = game.get(CORE_PROPERTY)
	if core is Object and is_instance_valid(core):
		return core
	return null


## The state of the game in progress, or null. Screens only read it.
static func state_of(game: Object) -> Object:
	var core: Object = core_of(game)
	if core == null:
		return null
	var state: Variant = core.get(STATE_PROPERTY)
	if state is Object and is_instance_valid(state):
		return state
	return null


## True when a command of the core succeeded: {"ok": true}.
static func succeeded(result: Variant) -> bool:
	return result is Dictionary and (result as Dictionary).get("ok", false) == true
