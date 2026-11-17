extends SceneTree
## Exports the WeChat Mini Game package without opening the editor, the same way
## the Mini Game Export dock does (and the plugin's own CI).
##
##   cd godot && godot --headless --path . --script ../tools/export_wechat.gd
const APPID := "wxd74107578cbd5867"
const ORIENTATION := "portrait"
const PRESET := "Web"   # thread support off

func _init() -> void:
	var out := ProjectSettings.globalize_path("res://").path_join("../minigame/wechat").simplify_path()
	var Exporter := load("res://addons/godot_mini_game/exporter.gd")
	var exporter = Exporter.new()
	exporter.log_callback = func(message: String) -> void: print("[export] ", message)
	var error = await exporter.export_mini_game("wechat", APPID, ORIENTATION, PRESET, out)
	print("[export] result: ", error_string(error), " -> ", out)
	quit(0 if error == OK else 1)
