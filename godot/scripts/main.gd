class_name Main
extends Control
## CASE FILES: engine.
##
## Knows nothing about any particular case. It owns the screen (the place, the
## people standing in it, the desk, the dialogue), the case clock, hints, the
## notebook, sound, speech, saving and scoring. Cases are JSON files in
## res://cases; the scene types that play them are in scenes.gd.

const CASES := ["res://cases/missing_violinist.json"]
const COL_MAX := 560.0
const WORD_GROUPS := [
	["paraphrase", "Paraphrases", "What was said, and what the document says"],
	["trap", "Not Given traps", "Mentioned nearby, but never actually stated"],
	["chart", "Chart language", "For describing data"],
	["grammar", "Grammar traps", "Wrong, then right"],
	["linker", "Linking words", "The word and the job it does"],
]

class Wait:
	signal done(value)

var web := OS.has_feature("web")
## The game is running inside a mini game host (WeChat): no HTML page, no speech engine.
var mini := false
## The game is running in a browser page with this project's HTML shell.
var web_page := false
var sdk: Node = null
var test_mode := false
var voice_player: AudioStreamPlayer
var key_field := ""   # id of the answer field the mini game keyboard is typing into
var data: Dictionary = {}      # the case
var state: Dictionary = {}     # the player's progress in it
var scenes: Scenes
var hint_fn: Callable = Callable()
var hint_why := ""
var moods: Dictionary = {}

# screen
var desk: TextureRect
var col: Control
var scene_view: Control
var place: TextureRect
var actors_layer: Control
var prop_box: MarginContainer
var hud: PanelContainer
var clock_face: ClockFace
var clock_label: Label
var clock_sub: Label
var hint_btn: Button
var note_btn: Button
var head: VBoxContainer
var scroll: ScrollContainer
var work: VBoxContainer
var tray_panel: PanelContainer
var tray: VBoxContainer
var dlg_catch: Control
var dlg_panel: PanelContainer
var dlg_name: Label
var dlg_role: Label
var dlg_text: RichTextLabel
var dlg_next: Label
var toasts: VBoxContainer
var overlay: Control
var sheet: Control
var wipe: Control
var sheet_content: Control

var scene_h := 300.0
var scene_full := true
var in_case := false
var actors: Dictionary = {}    # who -> {holder, sprite, slot, mood}
var fields: Array = []         # typed-answer boxes on screen
var trauma := 0.0
var shake_t := 0.0
var sound_on := true
var shake_on := true
var tension := 0.0          # interrogation pressure, 0..1
var tension_who := ""
var beat_t := 0.0           # time until the next clock tick or heartbeat
var vignette: TextureRect
var wash: ColorRect         # brief red wash on mistakes and big moments
var outgoing: Control       # documents sliding off the desk
var pressure_player: AudioStreamPlayer
var doc_rise := 0.0         # documents land from slightly below
var band_mask: GradientTexture2D   # feathers the bottom of the scene into the desk
var band_fade := 0.22
var dust: CPUParticles2D
var ambient := Color.WHITE  # the room's light on the people in it
var idle_t := 0.0
var sfx_cache: Dictionary = {}
var players: Array = []
var publish_t := 0.0
var js_cb


func _ready() -> void:
	UI.init_fonts()
	scenes = Scenes.new()
	scenes.g = self
	sdk = get_node_or_null("/root/MiniGameSDK")
	mini = web and sdk != null and bool(sdk.get("is_mini_game"))
	web_page = web and not mini
	if web:
		# Playtest hooks stay off unless a test page sets window.cfTestMode. Plain
		# property access only: a mini game host may not allow eval.
		var win = JavaScriptBridge.get_interface("window")
		test_mode = win != null and win.cfTestMode == true
	if mini:
		sdk.keyboard_event.connect(_on_keyboard)
	_build()
	var drift := place.create_tween().set_loops()
	drift.tween_property(place, "scale", Vector2(1.06, 1.06), 14.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	drift.tween_property(place, "scale", Vector2(1.01, 1.01), 14.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	voice_player = AudioStreamPlayer.new()
	add_child(voice_player)
	pressure_player = AudioStreamPlayer.new()
	add_child(pressure_player)
	for i in 8:
		var p := AudioStreamPlayer.new()
		add_child(p)
		players.append(p)
	var prefs = _read_json("user://prefs.json")
	if prefs is Dictionary:
		sound_on = prefs.get("sound", true)
		shake_on = prefs.get("shake", true)
	if web and test_mode:
		js_cb = JavaScriptBridge.create_callback(_js_show)
		JavaScriptBridge.get_interface("window").cfShow = js_cb
	home()


# ───────────────────────── building the screen ─────────────────────────

func _build() -> void:
	desk = UI.image("res://assets/ui/desk.png")
	desk.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	desk.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(desk)
	# a warm lamp pool on the desk and darker corners, under everything placed on it
	var lamp := StageFX.rect_image(StageFX.radial(Color(1.0, 0.8, 0.5, 0.22), Vector2(0.5, 0.3), Vector2(1.05, 0.95), 256), true)
	lamp.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(lamp)
	var corners := StageFX.rect_image(StageFX.radial(Color(0, 0, 0, 0), Vector2(0.5, 0.45), Vector2(1.15, 1.1), 256))
	corners.texture.gradient.set_color(1, Color(0.05, 0.025, 0.01, 0.55))
	corners.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(corners)

	col = Control.new()
	col.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(col)

	# The scene is drawn through a mask that fades its bottom edge, so the room
	# dissolves into the desk instead of ending at a line.
	band_mask = StageFX.fade_mask(0.22)
	var band := StageFX.rect_image(band_mask)
	band.clip_children = CanvasItem.CLIP_CHILDREN_ONLY
	band.clip_contents = true
	scene_view = band
	col.add_child(scene_view)
	place = UI.image("")
	place.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	place.set_anchors_preset(Control.PRESET_FULL_RECT)
	scene_view.add_child(place)
	dust = StageFX.dust()
	scene_view.add_child(dust)
	actors_layer = Control.new()
	actors_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	actors_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scene_view.add_child(actors_layer)
	vignette = TextureRect.new()
	var grad := Gradient.new()
	var shade := Color("1c1009")   # warm dark, matching the rendered rooms
	grad.set_color(0, Color(shade, 0.0))
	grad.set_color(1, Color(shade, 0.85))
	grad.add_point(0.55, Color(shade, 0.0))
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.55)
	gt.fill_to = Vector2(1.05, 1.05)
	vignette.texture = gt
	vignette.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	vignette.stretch_mode = TextureRect.STRETCH_SCALE
	vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vignette.modulate.a = 0.3
	scene_view.add_child(vignette)

	prop_box = MarginContainer.new()
	prop_box.mouse_filter = Control.MOUSE_FILTER_PASS
	for m in ["margin_left", "margin_right"]:
		prop_box.add_theme_constant_override(m, 10)
	col.add_child(prop_box)

	head = UI.vbox([], 6)
	col.add_child(head)

	scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	col.add_child(scroll)
	var pad := MarginContainer.new()
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pad.mouse_filter = Control.MOUSE_FILTER_PASS
	for m in ["margin_left", "margin_right", "margin_top"]:
		pad.add_theme_constant_override(m, 12)
	pad.add_theme_constant_override("margin_bottom", 28)
	scroll.add_child(pad)
	work = UI.vbox([], 12)
	pad.add_child(work)

	tray_panel = UI.panel(UI.box(Color(UI.PAPER, 0.97), 10, 0))
	tray = UI.vbox([], 8)
	tray_panel.add_child(tray)
	col.add_child(tray_panel)

	# HUD: the clock, hints and the notebook, always on screen during a case
	clock_face = ClockFace.new()
	clock_face.custom_minimum_size = Vector2(40, 40)
	clock_label = UI.label("", 20, UI.type_b)
	clock_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	clock_sub = UI.label("", 12, UI.type, UI.SOFT)
	clock_sub.autowrap_mode = TextServer.AUTOWRAP_OFF
	var clock_text := UI.vbox([clock_label, clock_sub], -2)
	var clock_box := UI.hbox([clock_face, clock_text], 6)
	UI.tappable(clock_box, "clock", func() -> void: toast("Leads and mistakes both cost time. Curtain is at %s." % clock_text_of(deadline()), ""))
	hint_btn = UI.button("Ask Sam", "paper", "hint")
	hint_btn.custom_minimum_size = Vector2(118, 44)
	hint_btn.size_flags_horizontal = Control.SIZE_SHRINK_END
	hint_btn.add_theme_font_size_override("font_size", 14)
	hint_btn.pressed.connect(ask_hint)
	note_btn = UI.button("Notes", "paper", "notebook")
	note_btn.custom_minimum_size = Vector2(74, 44)
	note_btn.size_flags_horizontal = Control.SIZE_SHRINK_END
	note_btn.add_theme_font_size_override("font_size", 14)
	note_btn.pressed.connect(func() -> void: open_notebook(""))
	hud = UI.panel(UI.box(Color(UI.MANILA, 0.96), 7, 0, 0), [UI.hbox([clock_box, hint_btn, note_btn], 6)])
	hud.get_theme_stylebox("panel").border_width_bottom = 2
	col.add_child(hud)

	toasts = UI.vbox([], 6)
	toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(toasts)

	# dialogue
	dlg_catch = Control.new()
	dlg_catch.visible = false
	UI.mark(dlg_catch, "dialogue")
	col.add_child(dlg_catch)
	dlg_name = UI.label("", 17, UI.type_b)
	dlg_name.autowrap_mode = TextServer.AUTOWRAP_OFF
	dlg_name.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	dlg_role = UI.label("", 13, UI.type, UI.SOFT)
	dlg_role.autowrap_mode = TextServer.AUTOWRAP_OFF
	dlg_text = UI.rich("", 22)
	dlg_text.custom_minimum_size = Vector2(0, 96)
	dlg_next = UI.label("tap", 12, UI.type, UI.SOFT)
	dlg_next.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var dstyle := UI.box(UI.PAPER, 14, 12, 0, UI.INK, 10)
	dstyle.border_width_left = 7
	dlg_panel = UI.panel(dstyle, [UI.vbox([UI.hbox([dlg_name, dlg_role], 8), dlg_text, dlg_next], 4)])
	dlg_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dlg_catch.add_child(dlg_panel)

	outgoing = Control.new()
	outgoing.mouse_filter = Control.MOUSE_FILTER_IGNORE
	outgoing.clip_contents = true
	col.add_child(outgoing)
	col.move_child(outgoing, col.get_children().find(scroll))
	wash = ColorRect.new()
	wash.color = Color(UI.RED, 0.0)
	wash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(wash)
	overlay = Control.new()
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(overlay)
	sheet = Control.new()
	sheet.visible = false
	col.add_child(sheet)
	wipe = Control.new()
	wipe.visible = false
	UI.mark(wipe, "wipe")
	col.add_child(wipe)
	_layout()


func _layout() -> void:
	var vp := get_viewport_rect().size
	var w: float = min(vp.x, COL_MAX)
	var off := Vector2.ZERO
	if trauma > 0.0:
		var s := trauma * trauma
		off = Vector2(11.0 * s * sin(shake_t * 1.7), 8.0 * s * sin(shake_t * 2.3))
	col.position = Vector2((vp.x - w) * 0.5, 0) + off
	col.size = Vector2(w, vp.y)
	col.rotation = 0.012 * trauma * trauma * sin(shake_t * 1.1) if trauma > 0.0 else 0.0
	col.pivot_offset = col.size * 0.5

	var sh: float = scene_h if in_case else 0.0
	scene_view.visible = in_case
	hud.visible = in_case
	scene_view.position = Vector2.ZERO
	scene_view.size = Vector2(w, sh)
	if sh > 0.0:
		var fade: float = clamp(46.0 / sh, 0.0, 0.45)
		if abs(band_fade - fade) > 0.004:
			band_fade = fade
			StageFX.set_fade(band_mask, fade)
	dust.position = Vector2(w * 0.5, sh * 0.5)
	dust.emission_rect_extents = Vector2(w * 0.5, sh * 0.5)
	place.pivot_offset = Vector2(w * (0.5 + 0.08 * sin(idle_t * 0.07)), sh * 0.5)
	hud.position = Vector2.ZERO
	hud.size = Vector2(w, 0)
	var hud_h: float = hud.get_combined_minimum_size().y
	hud.size.y = hud_h
	# people stand in the place
	for who in actors:
		var a: Dictionary = actors[who]
		var ah: float = clamp(sh * 0.86 - hud_h * 0.4, 60.0, 330.0)
		var aw := ah * 400.0 / 480.0
		var x: float = 6.0 if a.slot == "left" else w - aw - 6.0
		if a.slot == "mid":
			x = (w - aw) * 0.5
		a.holder.position = Vector2(x, sh - ah - 2.0)
		a.holder.size = Vector2(aw, ah)
		a.holder.pivot_offset = Vector2(aw * 0.5, ah)
		# a slow breath and a little sway, so nobody stands frozen
		a.breath.pivot_offset = Vector2(aw * 0.5, ah)
		a.breath.scale = Vector2(1.0, 1.0 + 0.009 * sin(idle_t * 1.7 + a.phase))
		a.breath.rotation = 0.006 * sin(idle_t * 0.6 + a.phase)
		if tension > 0.0 and who == tension_who:
			# the suspect trembles more as his composure goes
			a.holder.position.x += sin(shake_t * 3.1 + Time.get_ticks_msec() * 0.031) * 2.6 * tension
		a.sprite.pivot_offset = Vector2(aw * 0.5, ah)
	# an object standing in the scene, overlapping its lower edge
	var prop_h: float = prop_box.get_combined_minimum_size().y if prop_box.get_child_count() > 0 else 0.0
	prop_box.visible = prop_h > 0.0 and in_case and not scene_full
	prop_box.size = Vector2(w, prop_h)
	prop_box.position = Vector2(0, sh - prop_h * 0.45)
	var y: float = sh + (prop_h * 0.55 + 6.0 if prop_box.visible else 0.0)
	head.position = Vector2(12, y + (8.0 if head.get_child_count() > 0 else 0.0))
	head.size = Vector2(w - 24, 0)
	var head_h: float = head.get_combined_minimum_size().y if head.get_child_count() > 0 else 0.0
	head.size.y = head_h
	y += head_h + (8.0 if head_h > 0.0 else 0.0)
	var tray_h: float = tray_panel.get_combined_minimum_size().y if tray.get_child_count() > 0 else 0.0
	tray_panel.visible = tray_h > 0.0
	tray_panel.size = Vector2(w, tray_h)
	tray_panel.position = Vector2(0, vp.y - tray_h)
	scroll.position = Vector2(0, y + doc_rise)
	scroll.size = Vector2(w, max(0.0, vp.y - tray_h - y))
	toasts.position = Vector2(16, hud_h + 8.0)
	toasts.size = Vector2(w - 32, 0)
	dlg_catch.position = Vector2.ZERO
	dlg_catch.size = Vector2(w, vp.y)
	var dh: float = dlg_panel.get_combined_minimum_size().y
	dlg_panel.size = Vector2(w - 20, dh)
	dlg_panel.position = Vector2(10, vp.y - dh - 12)
	for c in [overlay, sheet, wipe, wash]:
		c.position = Vector2.ZERO
		c.size = Vector2(w, vp.y)
	outgoing.position = scroll.position
	outgoing.size = scroll.size
	if sheet.visible and is_instance_valid(sheet_content):
		sheet_content.size = Vector2(w, 0)
		var ch: float = min(sheet_content.get_combined_minimum_size().y, vp.y * 0.92)
		sheet_content.size = Vector2(w, ch)
		sheet_content.position = Vector2(0, vp.y - ch)


func _process(dt: float) -> void:
	if trauma > 0.0:
		trauma = max(0.0, trauma - 1.7 * dt)   # always decays back to rest
		shake_t += dt * 30.0
	idle_t += dt
	_layout()
	_pressure(dt)
	if web_page:
		_sync_fields()
	if web and test_mode:
		publish_t -= dt
		if publish_t <= 0.0:
			publish_t = 0.12
			_publish()


# ───────────────────────── small helpers ─────────────────────────

func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	return JSON.parse_string(f.get_as_text())


func _write_json(path: String, v: Variant) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(v))
		f.close()


func fmt(text: String, vars: Dictionary) -> String:
	for k in vars:
		text = text.replace("{" + str(k) + "}", str(vars[k]))
	return text


func to_min(hhmm: String) -> int:
	var p := hhmm.split(":")
	return int(p[0]) * 60 + int(p[1])


func clock_text_of(mins: int) -> String:
	var hr := (mins / 60) % 24
	var m := mins % 60
	return "%d:%02d %s" % [(hr + 11) % 12 + 1, m, "pm" if hr >= 12 else "am"]


func now() -> int:
	return to_min(data.clock.start) + int(state.time)


func deadline() -> int:
	return to_min(data.clock.deadline)


func wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func _sfx_stream(name: String) -> Variant:
	if not sfx_cache.has(name):
		var path := "res://assets/audio/%s.wav" % name
		sfx_cache[name] = load(path) if ResourceLoader.exists(path) else null
	return sfx_cache[name]


func sfx(name: String) -> void:
	if not sound_on:
		return
	if not sfx_cache.has(name):
		var path := "res://assets/audio/%s.wav" % name
		sfx_cache[name] = load(path) if ResourceLoader.exists(path) else null
	var st = sfx_cache[name]
	if st == null:
		return
	for p in players:
		if not p.playing:
			p.stream = st
			p.play()
			return
	players[0].stream = st
	players[0].play()


func shake(amount: float) -> void:
	if shake_on:
		trauma = min(1.0, trauma + amount)


## One bundle per event size, so every moment stays in proportion.
##   small: a tap or a pick-up.  right / wrong: an answer.  medium: a pin or a stamp.
##   large: a contradiction, a deduction, a confession, a verdict.
func feedback(tier: String) -> void:
	match tier:
		"large":
			sfx("thud")
			shake(0.75)
			_punch(1.06)
			_wash(Color(UI.RED, 0.16))
		"medium":
			sfx("thud_soft")
			shake(0.35)
			_punch(1.025)
		"wrong":
			sfx("bad")
			shake(0.3)
			_wash(Color(UI.RED, 0.12))
		"right":
			sfx("good")
			shake(0.1)
			_wash(Color(UI.BLUE, 0.07))
		_:
			sfx("tick")


## A quick push in on the scene, then back: the camera leaning in on a big moment.
func _punch(amount: float) -> void:
	scene_view.pivot_offset = scene_view.size * Vector2(0.5, 0.6)
	var tw := scene_view.create_tween()
	tw.tween_property(scene_view, "scale", Vector2(amount, amount), 0.07).set_ease(Tween.EASE_OUT)
	tw.tween_property(scene_view, "scale", Vector2.ONE, 0.38).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## A brief tinted wash over everything (no bright flashes).
func _wash(c: Color) -> void:
	wash.color = c
	var tw := wash.create_tween()
	tw.tween_property(wash, "color:a", 0.0, 0.35).set_ease(Tween.EASE_OUT)


## Interrogation pressure, 0..1: the vignette closes in, the heartbeat speeds up and
## the suspect trembles. 0 lets it all go.
func set_tension(value: float, who := "") -> void:
	tension = clamp(value, 0.0, 1.0)
	tension_who = who
	var tw := vignette.create_tween()
	tw.tween_property(vignette, "modulate:a", 0.3 + 0.55 * tension, 0.5)


## Clock pressure near the deadline, and the heartbeat of an interrogation.
func _pressure(dt: float) -> void:
	var interval := 0.0
	var kind := ""
	var vol := -60.0
	if in_case and data.has("clock") and scenes.current != "report" and scenes.current != "":
		var left := deadline() - now()
		if left <= 0:
			interval = 1.25
			kind = "heart"
			vol = -16.0
		elif left <= 15:
			interval = 0.7
			kind = "tock"
			vol = -12.0
		elif left <= 30:
			interval = 1.0
			kind = "tock"
			vol = -17.0
		var pulse := 1.0 + (0.06 * sin(Time.get_ticks_msec() * 0.009) if left <= 15 else 0.0)
		clock_face.scale = Vector2(pulse, pulse) if clock_face.scale.x < 1.2 else clock_face.scale
	if tension > 0.0:
		interval = 1.3 - 0.6 * tension
		kind = "heart"
		vol = -14.0 + 8.0 * tension
	if kind == "":
		beat_t = 0.0
		return
	beat_t -= dt
	if beat_t <= 0.0:
		beat_t = interval
		if sound_on:
			var st = _sfx_stream(kind)
			if st:
				pressure_player.stream = st
				pressure_player.volume_db = vol
				pressure_player.play()
		if kind == "heart":
			_punch(1.0 + 0.012 * max(tension, 0.4))


func _input(event: InputEvent) -> void:
	# instant feedback: every tap leaves an ink ripple where it landed
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		InkRipple.at(overlay, col.get_global_transform().affine_inverse() * event.position)


func save() -> void:
	if in_case:
		_write_json("user://save_%s.json" % data.id, state)


func new_state() -> Dictionary:
	return {"phase": "briefing", "time": 0, "hints_left": int(data.hints), "marks": {}, "facts": [], "evidence": [],
		"flags": {}, "done": [], "deductions": [], "ending": null, "found_at": -1}


# ───────────────────────── the place and the people in it ─────────────────────────

func set_place(id: String, surface := "desk") -> void:
	var tex := UI.texture("res://assets/places/%s.png" % id)
	if tex:
		place.texture = tex
		ambient = StageFX.ambient_tint(tex)
		for who in actors:
			actors[who].holder.modulate = ambient
	var st := UI.texture("res://assets/ui/%s.png" % surface)
	desk.texture = st if st else UI.texture("res://assets/ui/desk.png")


## Opens the place out (people talking) or shrinks it to a strip above the document.
func set_scene_full(full: bool, instant := false) -> void:
	scene_full = full
	var vp := get_viewport_rect().size
	var w: float = min(vp.x, COL_MAX)
	var target: float = min(w * 0.75, vp.y * 0.44) if full else min(w * 0.42, vp.y * 0.22)
	if instant:
		scene_h = target
		return
	var tw := create_tween()
	tw.tween_property(self, "scene_h", target, 0.38).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _actor_texture(who: String, mood: String) -> Texture2D:
	var t := UI.texture("res://assets/characters/%s_%s.png" % [who, mood])
	return t if t else UI.texture("res://assets/characters/%s_neutral.png" % who)


## Puts a cast member in the scene (left, right or mid). Safe to call again to change mood.
func show_actor(who: String, mood := "neutral", slot := "") -> void:
	if _actor_texture(who, mood) == null:
		return
	if actors.has(who):
		set_mood(who, mood)
		return
	if slot == "":
		slot = "left" if who == "sam" else "right"
	for other in actors.keys():
		if actors[other].slot == slot:
			hide_actor(other)
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.modulate = ambient
	# a soft contact shadow behind the figure grounds it in the room
	var shadow := StageFX.rect_image(StageFX.radial(Color(0.06, 0.03, 0.01, 0.6), Vector2(0.5, 0.5), Vector2(1.0, 0.5), 64))
	shadow.anchor_left = -0.05
	shadow.anchor_right = 1.05
	shadow.anchor_top = 0.55
	shadow.anchor_bottom = 1.25
	holder.add_child(shadow)
	var breath := Control.new()
	breath.mouse_filter = Control.MOUSE_FILTER_IGNORE
	breath.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.add_child(breath)
	var sprite := TextureRect.new()
	sprite.texture = _actor_texture(who, mood)
	sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	sprite.set_anchors_preset(Control.PRESET_FULL_RECT)
	sprite.mouse_filter = Control.MOUSE_FILTER_IGNORE
	breath.add_child(sprite)
	actors_layer.add_child(holder)
	actors[who] = {"holder": holder, "sprite": sprite, "breath": breath, "slot": slot, "mood": mood, "phase": randf() * TAU}
	_layout()
	sprite.position.y = 70
	sprite.modulate.a = 0.0
	var tw := sprite.create_tween().set_parallel(true)
	tw.tween_property(sprite, "position:y", 0.0, 0.34).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(sprite, "modulate:a", 1.0, 0.2)


func hide_actor(who: String) -> void:
	if not actors.has(who):
		return
	var a: Dictionary = actors[who]
	actors.erase(who)
	var tw: Tween = a.sprite.create_tween()
	tw.tween_property(a.sprite, "modulate:a", 0.0, 0.18)
	tw.tween_callback(a.holder.queue_free)


func clear_actors() -> void:
	for who in actors.keys():
		actors[who].holder.queue_free()
	actors.clear()


func set_mood(who: String, mood: String) -> void:
	moods[who] = mood
	if actors.has(who) and actors[who].mood != mood:
		actors[who].mood = mood
		var sp: TextureRect = actors[who].sprite
		sp.texture = _actor_texture(who, mood)
		var tw := sp.create_tween()
		tw.tween_property(sp, "scale", Vector2(1.06, 0.95), 0.06)
		tw.tween_property(sp, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## A physical reaction: flinch (caught out), hop (pleased), nod (speaking), slump.
func react(who: String, kind: String) -> void:
	if not actors.has(who):
		return
	var s: TextureRect = actors[who].sprite
	var tw := s.create_tween()
	match kind:
		"flinch":
			tw.tween_property(s, "rotation", -0.09, 0.05)
			tw.parallel().tween_property(s, "position:x", -12.0, 0.05)
			tw.tween_property(s, "rotation", 0.07, 0.08)
			tw.parallel().tween_property(s, "position:x", 10.0, 0.08)
			tw.tween_property(s, "rotation", -0.03, 0.08)
			tw.parallel().tween_property(s, "position:x", -5.0, 0.08)
			tw.tween_property(s, "rotation", 0.0, 0.12)
			tw.parallel().tween_property(s, "position:x", 0.0, 0.12)
		"hop":
			tw.tween_property(s, "position:y", -16.0, 0.12).set_ease(Tween.EASE_OUT)
			tw.tween_property(s, "position:y", 0.0, 0.2).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
		"slump":
			tw.tween_property(s, "scale", Vector2(1.04, 0.93), 0.18)
			tw.tween_property(s, "scale", Vector2.ONE, 0.5).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
		_:
			tw.tween_property(s, "scale", Vector2(1.02, 1.035), 0.08)
			tw.tween_property(s, "scale", Vector2.ONE, 0.16)


func _spotlight(who: String) -> void:
	for other in actors:
		var lit: bool = other == who or not actors.has(who)
		var a: Dictionary = actors[other]
		a.sprite.self_modulate = Color.WHITE if lit else Color(0.66, 0.68, 0.76)
		var target := Vector2(1.04, 1.04) if (lit and actors.has(who)) else (Vector2.ONE if lit else Vector2(0.96, 0.96))
		var tw: Tween = a.holder.create_tween()
		tw.tween_property(a.holder, "scale", target, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


# ───────────────────────── desk: documents, tray, props ─────────────────────────

func _clear(box: Node) -> void:
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()


## Deals documents onto the desk. An empty list clears it and opens the place out.
func set_work(nodes: Array) -> void:
	var had := work.get_child_count() > 0
	if had:
		_send_off(work)
	scroll.scroll_vertical = 0
	for n in nodes:
		if n != null:
			work.add_child(n)
	if work.get_child_count() > 0:
		set_scene_full(false)
		sfx("paper")
		scroll.modulate.a = 0.0
		scroll.pivot_offset = Vector2(scroll.size.x * 0.5, 0)
		scroll.rotation = 0.03
		var tw := create_tween().set_parallel(true)
		tw.tween_property(scroll, "modulate:a", 1.0, 0.2)
		tw.tween_property(scroll, "rotation", 0.0, 0.34).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		doc_rise = 28.0
		var rise := create_tween()
		rise.tween_property(self, "doc_rise", 0.0, 0.32).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	elif had:
		sfx("close")


## Moves the documents on the desk into a layer that slides them away and frees them.
## They stop taking input at once and are no longer seen by the playtest hooks.
func _send_off(box: Node) -> void:
	var holder := VBoxContainer.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_theme_constant_override("separation", 12)
	holder.position = Vector2(12, 12 - scroll.scroll_vertical)
	holder.size = Vector2(scroll.size.x - 24, 0)
	outgoing.add_child(holder)
	for c in box.get_children():
		box.remove_child(c)
		holder.add_child(c)
		_disarm(c)
	var tw := holder.create_tween().set_parallel(true)
	tw.tween_property(holder, "position:y", holder.position.y + 70.0, 0.24).set_ease(Tween.EASE_IN)
	tw.tween_property(holder, "modulate:a", 0.0, 0.24)
	tw.chain().tween_callback(holder.queue_free)


func _disarm(n: Node) -> void:
	if n is Control:
		n.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if n.is_in_group("tid"):
		n.remove_from_group("tid")
	for c in n.get_children():
		_disarm(c)


func set_head(nodes: Array) -> void:
	_clear(head)
	for n in nodes:
		if n != null:
			head.add_child(n)


func set_tray(nodes: Array) -> void:
	_clear(tray)
	for n in nodes:
		if n != null:
			tray.add_child(n)


func set_prop(node: Control) -> void:
	_clear(prop_box)
	if node:
		prop_box.add_child(node)


func ensure_visible(c: Control) -> void:
	await get_tree().process_frame
	if is_instance_valid(c) and scroll.is_ancestor_of(c):
		scroll.ensure_control_visible(c)


## One big button in the tray; resolves when it is tapped.
func proceed(text := "Continue") -> void:
	var w := Wait.new()
	var b := UI.button(text, "primary", "proceed")
	b.pressed.connect(func() -> void: w.done.emit(true))
	set_tray([b])
	await w.done
	sfx("tick")
	set_tray([])


# ───────────────────────── dialogue ─────────────────────────

func _parse_line(line: Variant) -> Dictionary:
	if line is Dictionary:
		return line
	var s: String = line
	if s.begins_with("@"):
		var i := s.find(" ")
		return {"who": s.substr(1, i - 1), "text": s.substr(i + 1)}
	return {"who": "sam", "text": s}


## Shows lines one at a time; the speaker stands in the scene and is lit while talking.
func say(lines: Variant, vars := {}) -> void:
	var list: Array = lines if lines is Array else [lines]
	if list.is_empty():
		return
	for raw in list:
		if raw == null:
			continue
		var l := _parse_line(raw)
		var who: String = l.who
		var cast: Dictionary = data.cast.get(who, {"name": who, "role": ""})
		show_actor(who, moods.get(who, "neutral"))
		_spotlight(who)
		react(who, "nod")
		if who == "sam":
			moods.erase("sam")   # Sam's reaction to the last action shows once
		dlg_name.text = cast.name
		dlg_role.text = cast.get("role", "")
		var tone: Color = UI.INK if who == "sam" else (UI.RED if cast.get("tone", "") == "red" else UI.SOFT)
		dlg_panel.get_theme_stylebox("panel").border_color = tone
		dlg_text.text = UI.bb(fmt(l.text, vars))
		dlg_text.visible_ratio = 0.0
		dlg_catch.visible = true
		var chars: int = max(1, dlg_text.get_total_character_count())
		var typing := create_tween()
		typing.tween_property(dlg_text, "visible_ratio", 1.0, min(1.6, chars * 0.014))
		sfx("blip")
		var w := Wait.new()
		var st := {"at": Time.get_ticks_msec()}
		var on_tap := func(e: InputEvent) -> void:
			if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT and not e.pressed:
				if Time.get_ticks_msec() - st.at < 180:
					return
				if dlg_text.visible_ratio < 1.0:
					typing.kill()
					dlg_text.visible_ratio = 1.0
					st.at = Time.get_ticks_msec()
				else:
					w.done.emit(true)
		dlg_catch.gui_input.connect(on_tap)
		await w.done
		dlg_catch.gui_input.disconnect(on_tap)
		if typing.is_valid():
			typing.kill()
	dlg_catch.visible = false
	_spotlight("")


## Plays story beats: dialogue, documents, notebook facts, evidence cards, lost time.
func play(beats: Variant, vars := {}) -> void:
	if beats == null:
		return
	var talk: Array = []
	for b in beats:
		if b is String or (b is Dictionary and b.has("who")):
			talk.append(b)
			continue
		if not talk.is_empty():
			await say(talk, vars)
			talk = []
		if b.has("doc"):
			set_work([scenes.render_doc(b.doc)])
			await proceed(b.get("button", "Continue"))
			set_work([])
			set_scene_full(true)
		elif b.has("fact"):
			fact(b.fact)
		elif b.has("evidence"):
			give(b.evidence)
		elif b.has("word"):
			word(b.word)
		elif b.has("lose"):
			lose(int(b.lose))
	if not talk.is_empty():
		await say(talk, vars)


# ───────────────────────── clock, hints, notebook entries ─────────────────────────

func update_hud() -> void:
	if not in_case:
		return
	var t := now()
	clock_face.minutes = t
	clock_label.text = clock_text_of(t)
	var late := t > deadline()
	clock_sub.text = ("past %s!" % data.clock.deadlineName) if late else "%s %s" % [data.clock.deadlineName, clock_text_of(deadline()).replace(" pm", "")]
	clock_label.add_theme_color_override("font_color", UI.RED if late else UI.INK)
	clock_face.late = late
	hint_btn.text = "Ask Sam (%d)" % int(state.hints_left)


func _bump_clock() -> void:
	clock_face.pivot_offset = clock_face.size * 0.5
	var tw := create_tween()
	tw.tween_property(clock_face, "scale", Vector2(1.5, 1.5), 0.1)
	tw.tween_property(clock_face, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Time spent on purpose: following a lead.
func spend(mins: int) -> void:
	var before := now()
	state.time = int(state.time) + mins
	save()
	update_hud()
	_bump_clock()
	sfx("clock")
	toast("%d minutes spent" % mins, "")
	if before <= deadline() and now() > deadline():
		toast("Past %s time!" % data.clock.deadlineName, "bad")


## Time lost to a mistake or a hint.
func lose(mins: int) -> void:
	if mins <= 0:
		return
	var before := now()
	state.time = int(state.time) + mins
	save()
	update_hud()
	_bump_clock()
	feedback("wrong")
	sfx("clock")
	moods["sam"] = "annoyed"
	set_mood("sam", "annoyed")
	toast("+%d min on the case clock" % mins, "bad")
	if before <= deadline() and now() > deadline():
		toast("Past %s time!" % data.clock.deadlineName, "bad")


## Records a first-try result for the band estimate. The first write wins.
func mark(skill: String, id: String, ok: bool, weight := 1) -> void:
	if not state.marks.has(skill):
		state.marks[skill] = {}
	if state.marks[skill].has(id):
		return
	state.marks[skill][id] = {"ok": ok, "w": weight}
	save()


const WORDS_KEY := "casefiles.words"

func words() -> Array:
	var v = _read_json("user://words.json")
	if mini and not (v is Array and not v.is_empty()):
		# The host writes user:// back to its storage every few seconds and when the
		# game is hidden; the copy in its synchronous storage covers the gap.
		v = JSON.parse_string(sdk.storage_get(WORDS_KEY, "[]"))
	return v if v is Array else []


func word(entry: Variant) -> void:
	if entry == null:
		return
	var list := words()
	for w in list:
		if w.t == entry.t and w.a == entry.a and w.b == entry.b:
			return
	list.append({"t": entry.t, "a": entry.a, "b": entry.b, "n": entry.get("n", ""), "c": data.title})
	_write_json("user://words.json", list)
	if mini:
		sdk.storage_set(WORDS_KEY, JSON.stringify(list))
	toast("Saved to notebook: " + (entry.b if entry.t == "grammar" else entry.a), "note")
	sfx("pen")


func fact(f: Dictionary) -> void:
	for x in state.facts:
		if x.title == f.title:
			return
	state.facts.append(f)
	save()


func has_card(id: String) -> bool:
	return state.evidence.has(id)


func card(id: String) -> Dictionary:
	for e in data.evidence:
		if e.id == id:
			return e
	return {}


## Hands the player an evidence card: it drops onto the screen with a pin.
func give(id: String) -> void:
	if has_card(id):
		return
	state.evidence.append(id)
	save()
	var e := card(id)
	if e.is_empty():
		return
	toast("New evidence card: " + e.title, "ev")
	sfx("pin")


func flag(k: String, v: Variant = null) -> Variant:
	if v != null:
		state.flags[k] = v
		save()
	return state.flags.get(k)


func set_hint(fn: Callable = Callable(), why := "") -> void:
	hint_fn = fn
	hint_why = why


func ask_hint() -> void:
	if not in_case or dlg_catch.visible or sheet.visible:
		return
	if not hint_fn.is_valid():
		toast(hint_why if hint_why != "" else "Nothing to ask Sam about right now.", "")
		return
	if int(state.hints_left) <= 0:
		await say(["No hints left. All I’ve got now is biscuits, and you can’t have those."])
		return
	var ok = await confirm("Ask Sam?", "Sam will show you where to look, not what the answer is. It costs %d minutes on the case clock. %d of %d hints left." % [int(data.hintCost), int(state.hints_left), int(data.hints)], "Ask Sam", "Not yet")
	if not ok:
		return
	sfx("hint")
	hint_btn.pivot_offset = hint_btn.size * 0.5
	var tw := hint_btn.create_tween()
	tw.tween_property(hint_btn, "modulate", Color(1.0, 0.55, 0.5), 0.12)
	tw.parallel().tween_property(hint_btn, "scale", Vector2(1.12, 1.12), 0.12)
	tw.tween_property(hint_btn, "modulate", Color.WHITE, 0.4)
	tw.parallel().tween_property(hint_btn, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	react("sam", "hop")
	var used = await hint_fn.call()
	if used is bool and used == false:
		return
	state.hints_left = int(state.hints_left) - 1
	lose(int(data.hintCost))
	update_hud()


# ───────────────────────── toasts, stamps, sheets, transitions ─────────────────────────

func toast(text: String, kind: String) -> void:
	while toasts.get_child_count() >= 2:
		var old := toasts.get_child(0)
		toasts.remove_child(old)
		old.queue_free()
	var bg := UI.INK
	var fg := UI.PAPER
	if kind == "bad":
		bg = UI.RED
	elif kind == "note":
		bg = UI.BLUE
	elif kind == "ev":
		bg = UI.PAPER
		fg = UI.RED
	var l := UI.label(text, 15, UI.type_b, fg)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var p := UI.panel(UI.box(bg, 9, 16 if kind != "ev" else 3, 2 if kind == "ev" else 0, UI.RED, 5), [l])
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toasts.add_child(p)
	p.modulate.a = 0.0
	var tw := p.create_tween()   # bound to the toast, so it ends if the toast is removed early
	tw.tween_property(p, "modulate:a", 1.0, 0.15)
	tw.tween_interval(2.3)
	tw.tween_property(p, "modulate:a", 0.0, 0.4)
	tw.tween_callback(p.queue_free)


## A rubber stamp. Red stamps are the big moments: slam, thud, shake, ink flecks.
func stamp(text: String, tone := "red") -> void:
	var color := UI.RED
	if tone == "ink":
		color = UI.BLUE
	elif tone == "grey":
		color = UI.SOFT
	var big := tone == "red"
	var l := UI.label(text, 34 if text.length() > 11 else 42, UI.type_b, color)
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var p := UI.panel(UI.box(Color(UI.PAPER, 0.93), 16, 12, 6, color, 12), [l])
	p.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(p)
	await get_tree().process_frame
	var sz := p.get_combined_minimum_size()
	p.size = sz
	p.position = (overlay.size - sz) * 0.5
	p.pivot_offset = sz * 0.5
	p.rotation = -0.3
	p.scale = Vector2(3.4, 3.4)
	p.modulate.a = 0.0
	moods["sam"] = "pleased"
	set_mood("sam", "pleased")
	var tw := create_tween().set_parallel(true)
	tw.tween_property(p, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(p, "rotation", -0.12, 0.2)
	tw.tween_property(p, "modulate:a", 1.0, 0.12)
	await tw.finished
	feedback("large" if big else "medium")
	react("sam", "hop")
	var flecks := 10 if big else 4
	for i in flecks:
		var d := ColorRect.new()
		d.color = color
		d.size = Vector2(randf_range(4, 9), randf_range(4, 8))
		d.mouse_filter = Control.MOUSE_FILTER_IGNORE
		d.position = p.position + sz * 0.5
		overlay.add_child(d)
		var ang := randf() * TAU
		var dist := randf_range(70, 150)
		var ft := d.create_tween()
		ft.tween_property(d, "position", d.position + Vector2(cos(ang) * dist * 1.3, sin(ang) * dist * 0.6), 0.35).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
		ft.tween_interval(0.7)
		ft.tween_property(d, "modulate:a", 0.0, 0.25)
		ft.tween_callback(d.queue_free)
	var settle := create_tween()
	settle.tween_property(p, "scale", Vector2(1.08, 1.08), 0.06)
	settle.tween_property(p, "scale", Vector2.ONE, 0.12)
	await wait(1.05)
	var out := create_tween()
	out.tween_property(p, "modulate:a", 0.0, 0.25)
	await out.finished
	p.queue_free()


func _open_sheet(content: Control, tid := "sheet-close") -> Wait:
	_clear(sheet)
	var w := Wait.new()
	var dim := ColorRect.new()
	dim.color = Color(0.16, 0.11, 0.03, 0.5)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	UI.tappable(dim, tid, func() -> void: w.done.emit(null))
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	sheet.add_child(dim)
	sheet.add_child(content)
	sheet_content = content
	sheet.visible = true
	_layout()
	sfx("open")
	content.modulate.a = 0.0
	var tw := content.create_tween()
	tw.tween_property(content, "modulate:a", 1.0, 0.16)
	return w


func _close_sheet() -> void:
	sheet.visible = false
	_clear(sheet)


func confirm(title: String, body: String, yes: String, no: String) -> bool:
	var a := UI.button(no, "ghost", "confirm-no")
	var b := UI.button(yes, "primary", "confirm-yes")
	var p := UI.panel(UI.box(UI.PAPER, 18, 16), [UI.vbox([UI.label(title, 28, UI.serif_b), UI.label(body, 18), UI.gap(4), UI.hbox([a, b], 8)], 8)])
	var w := _open_sheet(p, "confirm-dim")
	a.pressed.connect(func() -> void: w.done.emit(false))
	b.pressed.connect(func() -> void: w.done.emit(true))
	var v = await w.done
	_close_sheet()
	return v == true


## Lets the player choose one of their evidence cards. Returns the id, or "" if they back out.
func pick_card(title: String, ids: Array) -> String:
	var list := UI.vbox([], 8)
	var w: Wait
	var rows: Array = []
	for id in ids:
		var e := card(id)
		var row := UI.panel(UI.box(UI.PAPER, 12, 3, 2, UI.RULE, 4), [UI.vbox([UI.tag(e.title, UI.RED, 14), UI.label(e.text, 17)], 2)])
		rows.append([row, id])
		list.add_child(row)
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.custom_minimum_size = Vector2(0, min(420.0, get_viewport_rect().size.y * 0.5))
	sc.add_child(list)
	var back := UI.button("Put the cards away", "ghost", "pick-back")
	var p := UI.panel(UI.box(UI.MANILA, 16, 16), [UI.vbox([UI.label(title, 24, UI.serif_b), sc, back], 10)])
	w = _open_sheet(p, "pick-dim")
	for r in rows:
		var id: String = r[1]
		UI.tappable(r[0], "pick-" + id, func() -> void: w.done.emit(id))
	back.pressed.connect(func() -> void: w.done.emit(""))
	var v = await w.done
	_close_sheet()
	return v if v is String else ""


## Scene change: a case folder slides over the desk, then lifts away onto the new place.
func transition(sc: Dictionary) -> void:
	set_hint()
	_clear(wipe)
	var folder := UI.image("res://assets/ui/folder.png")
	folder.stretch_mode = TextureRect.STRETCH_SCALE
	wipe.add_child(folder)
	var title := UI.label(str(sc.get("title", "")).to_upper(), 38, UI.type_b)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var plate := UI.panel(UI.box(UI.PAPER, 16, 2, 4, UI.INK, 8), [title])
	var skill := UI.label(sc.get("skill", ""), 17, UI.type_b, UI.RED)
	skill.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var blurb := UI.label(sc.get("blurb", ""), 21, UI.serif_i)
	blurb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var box := UI.vbox([plate, UI.gap(6), skill, blurb], 10)
	wipe.add_child(box)
	wipe.visible = true
	wipe.mouse_filter = Control.MOUSE_FILTER_STOP
	_layout()
	var h := wipe.size.y
	var bw := wipe.size.x - 72.0
	box.size = Vector2(bw, 0)
	await get_tree().process_frame
	var bh: float = box.get_combined_minimum_size().y
	box.size = Vector2(bw, bh)
	var box_y := (h - bh) * 0.5
	folder.size = wipe.size
	folder.position = Vector2(0, h)
	box.position = Vector2(36, box_y + h)
	plate.pivot_offset = Vector2(bw * 0.5, 30)
	plate.rotation = -0.035
	sfx("wipe")
	var tin := create_tween().set_parallel(true)
	tin.tween_property(folder, "position:y", 0.0, 0.34).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tin.tween_property(box, "position:y", box_y, 0.34).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	await tin.finished
	# swap the world behind the folder
	set_work([])
	set_head([])
	set_tray([])
	set_prop(null)
	clear_actors()
	fields.clear()
	set_place(sc.get("place", "unit9"), sc.get("surface", "desk"))
	set_scene_full(true, true)
	update_hud()
	var w := Wait.new()
	var on_tap := func(e: InputEvent) -> void:
		if e is InputEventMouseButton and not e.pressed:
			w.done.emit(true)
	wipe.gui_input.connect(on_tap)
	get_tree().create_timer(1.7).timeout.connect(func() -> void: w.done.emit(true))
	await w.done
	wipe.gui_input.disconnect(on_tap)
	sfx("open")
	var tout := create_tween().set_parallel(true)
	tout.tween_property(folder, "position:y", -h * 1.05, 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tout.tween_property(box, "position:y", box_y - h * 1.05, 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	await tout.finished
	wipe.visible = false
	_clear(wipe)


# ───────────────────────── speech (calls and radio) ─────────────────────────

## Speaks the lines aloud. In the mini game it plays the recorded clips (clips[i] is
## lines[i] spoken); in a browser it uses the browser's British voice. on_line(i) is
## called as line i starts. Returns false when nothing could be played, so the caller
## can show a transcript instead.
func speak(lines: Array, voice: Dictionary, on_line: Callable = Callable(), clips: Array = []) -> bool:
	if mini:
		return await _play_clips(clips, lines.size(), on_line)
	if not web_page:
		return false
	var payload := {"lines": lines, "prefer": voice.get("prefer", "female"), "rate": voice.get("rate", 0.95), "pitch": voice.get("pitch", 1.0)}
	JavaScriptBridge.get_interface("window").cfSpeech.speak(JSON.stringify(payload))
	while true:
		await wait(0.15)
		var st = JavaScriptBridge.eval("window.cfSpeech.state")
		if on_line.is_valid():
			on_line.call(int(JavaScriptBridge.eval("window.cfSpeech.line")))
		if st == "done":
			return true
		if st != "playing":
			return false
	return false


const VOICE_DIR := "res://assets/audio/voice/"

## Plays recorded clips one after another, as one recording.
func _play_clips(clips: Array, count: int, on_line: Callable) -> bool:
	if clips.size() != count or count == 0:
		return false
	var streams: Array = []
	for name in clips:
		var path: String = VOICE_DIR + str(name)
		if not ResourceLoader.exists(path):
			return false
		streams.append(load(path))
	for i in streams.size():
		if on_line.is_valid():
			on_line.call(i)
		voice_player.stream = streams[i]
		voice_player.play()
		await voice_player.finished
		if voice_player.has_meta("stopped"):
			voice_player.remove_meta("stopped")
			return true
	return true


func stop_speech() -> void:
	if mini and voice_player.playing:
		voice_player.set_meta("stopped", true)
		voice_player.stop()
		voice_player.finished.emit()
	elif web_page:
		JavaScriptBridge.eval("window.cfSpeech.stop()")


# ───────────────────────── typed answers ─────────────────────────

## A text box for a typed answer. In the browser a real HTML input is laid over it, so
## the phone's own keyboard opens; in the mini game a tap opens the host's keyboard
## through MiniGameSDK; on desktop it is an ordinary LineEdit.
func add_field(id: String, label: String, caps := false) -> LineEdit:
	var le := LineEdit.new()
	le.custom_minimum_size = Vector2(0, 44)
	le.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	le.add_theme_font_override("font", UI.type_b if caps else UI.hand)
	le.add_theme_font_size_override("font_size", 24)
	le.add_theme_color_override("font_color", UI.BLUE)
	le.add_theme_color_override("font_uneditable_color", UI.BLUE)
	var line := StyleBoxFlat.new()
	line.bg_color = Color(1, 1, 1, 0.0)
	line.border_width_bottom = 2
	line.border_color = UI.INK
	line.content_margin_left = 4
	for s in ["normal", "focus", "read_only"]:
		le.add_theme_stylebox_override(s, line)
	UI.mark(le, "field-" + id)
	le.text_changed.connect(func(_t: String) -> void: sfx("key"))
	# A new field starts empty. The page keeps one HTML box per field id, so on the Web
	# the box is told to clear once, or a retry call would show the earlier answer.
	var f := {"id": id, "le": le, "label": label, "caps": caps, "locked": false, "force": "" if web_page else null, "last": ""}
	if web_page:
		le.editable = false
		le.mouse_filter = Control.MOUSE_FILTER_IGNORE
		le.add_theme_color_override("font_uneditable_color", Color(UI.BLUE, 0.0))
	elif mini:
		le.editable = false
		UI.tappable(le, "", func() -> void: _open_keyboard(id))
	fields.append(f)
	return le


func _open_keyboard(id: String) -> void:
	for f in fields:
		if f.id == id and not f.locked and is_instance_valid(f.le):
			key_field = id
			_mark_typing()
			sdk.show_keyboard(f.le.text, 60, false)
			return


## The mini game keyboard reports each change ("input") and when it closes.
func _on_keyboard(kind: String, value: String) -> void:
	for f in fields:
		if f.id == key_field and not f.locked and is_instance_valid(f.le):
			if f.le.text != value:
				f.le.text = value
				sfx("key")
	if kind != "input":
		sdk.hide_keyboard()
		key_field = ""
		_mark_typing()


## Underlines the field being typed into in red.
func _mark_typing() -> void:
	for f in fields:
		if is_instance_valid(f.le):
			var st: StyleBoxFlat = f.le.get_theme_stylebox("read_only")
			st.border_color = UI.RED if f.id == key_field else UI.INK
			st.border_width_bottom = 3 if f.id == key_field else 2


func field_value(id: String) -> String:
	if web_page:
		_sync_fields()   # read the text boxes now, not as they were last frame
	for f in fields:
		if f.id == id:
			return f.le.text.strip_edges()
	return ""


## Stops typing in a field and shows its final text on the paper, in the given colour.
func lock_field(id: String, color: Color, text := "") -> void:
	for f in fields:
		if f.id == id:
			f.locked = true
			if key_field == id:
				sdk.hide_keyboard()
				key_field = ""
			if text != "":
				f.le.text = text
				f.force = text
			f.le.editable = false
			f.le.add_theme_color_override("font_uneditable_color", color)


func _sync_fields() -> void:
	var vp := get_viewport_rect().size
	var covered := dlg_catch.visible or sheet.visible or wipe.visible
	var list: Array = []
	var clip := scroll.get_global_rect()
	fields = fields.filter(func(x: Dictionary) -> bool: return is_instance_valid(x.le) and x.le.is_inside_tree() and not outgoing.is_ancestor_of(x.le))
	for f in fields:
		var le: LineEdit = f.le
		var r := le.get_global_rect()
		var show: bool = le.is_visible_in_tree() and not covered and not f.locked and clip.encloses(r.grow(-2))
		list.append({"id": f.id, "label": f.label, "caps": f.caps, "x": r.position.x / vp.x, "y": r.position.y / vp.y, "w": r.size.x / vp.x,
			"h": r.size.y / vp.y, "size": 24.0 / vp.y, "show": show, "locked": f.locked, "force": f.force, "value": le.text})
		f.force = null
	if list.is_empty() and not _had_fields:
		return
	_had_fields = not list.is_empty()
	var out = JavaScriptBridge.get_interface("window").cfInput.sync(JSON.stringify(list))
	var vals = JSON.parse_string(str(out))
	if vals is Dictionary:
		for f in fields:
			if vals.has(f.id) and not f.locked and is_instance_valid(f.le):
				var v: String = vals[f.id]
				if v != f.le.text:
					f.le.text = v
					sfx("key")

var _had_fields := false


# ───────────────────────── notebook ─────────────────────────

func open_notebook(tab: String) -> void:
	if dlg_catch.visible:
		return
	var tabs: Array = []
	if in_case:
		tabs = [["notes", "Notes"], ["board", "Board"]]
	tabs.append(["words", "Words"])
	if tab == "":
		tab = tabs[0][0]
	var body := UI.vbox([], 10)
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.custom_minimum_size = Vector2(0, get_viewport_rect().size.y * 0.58)
	sc.add_child(body)
	var tab_row := UI.hbox([], 4)
	var close := UI.button("Close", "ghost", "nb-close")
	close.custom_minimum_size = Vector2(90, 44)
	close.size_flags_horizontal = Control.SIZE_SHRINK_END
	var title := UI.label("Notebook", 32, UI.hand_b, UI.BLUE)
	var style := UI.box(UI.PAPER, 16, 6)
	style.border_width_top = 12
	style.border_color = Color("22345a")
	var p := UI.panel(style, [UI.vbox([UI.hbox([title, close]), tab_row, sc], 8)])
	var w := _open_sheet(p, "nb-dim")
	var fill := func(id: String) -> void:
		_clear(body)
		sfx("paper")
		for b in tab_row.get_children():
			b.modulate = Color.WHITE if b.get_meta("tab") == id else Color(1, 1, 1, 0.55)
		if id == "words":
			var list := words()
			if list.is_empty():
				body.add_child(UI.label("Nothing here yet. Every paraphrase, linking word and grammar trap you meet in a case is saved here automatically.", 18, UI.serif_i, UI.SOFT))
			for g in WORD_GROUPS:
				var items := list.filter(func(x: Dictionary) -> bool: return x.t == g[0])
				if items.is_empty():
					continue
				body.add_child(UI.tag("%s  %d" % [g[1], items.size()], UI.RED, 15))
				body.add_child(UI.label(g[2], 15, UI.serif_i, UI.SOFT))
				for it in items:
					var row := UI.vbox([UI.label(it.a, 18, UI.serif_b), UI.label("→ " + it.b, 19, UI.hand, UI.BLUE)], 0)
					if it.get("n", "") != "":
						row.add_child(UI.label(it.n, 15, UI.serif_i, UI.SOFT))
					body.add_child(row)
					body.add_child(UI.rule())
		elif id == "board":
			if state.evidence.is_empty():
				body.add_child(UI.label("The board is empty. Evidence is pinned here as you find it.", 18, UI.serif_i, UI.SOFT))
			for eid in state.evidence:
				body.add_child(scenes.evidence_card(card(eid), false))
			for did in state.deductions:
				body.add_child(scenes.deduction_card(scenes.deduction(did)))
		else:
			if state.facts.is_empty():
				body.add_child(UI.label("No notes yet. Facts appear here as you find them.", 18, UI.serif_i, UI.SOFT))
			for f in state.facts:
				body.add_child(UI.tag(f.title, UI.RED, 14))
				body.add_child(UI.label(f.text, 20, UI.hand, UI.BLUE))
				body.add_child(UI.rule(Color("c9d1de")))
			if in_case:
				var leave := UI.button("Leave case (progress is saved)", "ghost", "nb-leave")
				leave.pressed.connect(func() -> void:
					save()
					stop_speech()
					get_tree().reload_current_scene())
				body.add_child(leave)
	for t in tabs:
		var b := UI.button(t[1], "paper", "nb-tab-" + t[0])
		b.custom_minimum_size = Vector2(0, 44)
		b.set_meta("tab", t[0])
		var id: String = t[0]
		b.pressed.connect(func() -> void: fill.call(id))
		tab_row.add_child(b)
	fill.call(tab)
	close.pressed.connect(func() -> void: w.done.emit(null))
	await w.done
	_close_sheet()


# ───────────────────────── scoring and result codes ─────────────────────────

## Share of first-try correct answers gives a rough band. One short case is a small sample.
func band_for(marks: Variant) -> Dictionary:
	var got := 0
	var total := 0
	if marks is Dictionary:
		for k in marks:
			total += int(marks[k].w)
			if marks[k].ok:
				got += int(marks[k].w)
	if total == 0:
		return {"band": -1.0, "got": 0, "total": 0}
	var p := float(got) / float(total)
	var band := 4.5
	if p >= 0.92:
		band = 7.0
	elif p >= 0.8:
		band = 6.5
	elif p >= 0.66:
		band = 6.0
	elif p >= 0.5:
		band = 5.5
	elif p >= 0.34:
		band = 5.0
	return {"band": band, "got": got, "total": total}

const ALPHA := "ABCDEFGHJKMNPQRSTVWXYZ23456789"
const ENDINGS := ["C", "W", "R"]

func _band_idx(b: float) -> int:
	return clampi(roundi(((b if b > 0.0 else 4.0) - 4.0) * 2.0), 0, 10)


## Packs ending, three bands, hints used and the finishing time into a short code.
func encode_result(r: Dictionary) -> String:
	var n: int = ENDINGS.find(r.ending)
	n = n * 11 + _band_idx(r.L)
	n = n * 11 + _band_idx(r.R)
	n = n * 11 + _band_idx(r.W)
	n = n * 4 + mini(3, int(r.hints))
	n = n * 400 + mini(399, int(r.time))
	var body := ""
	var sum := 0
	for i in 5:
		var d := n % 30
		body = ALPHA[d] + body
		sum += d * (i + 1)
		n /= 30
	return "%s%s-%s%s" % [data.code, data.number, body, ALPHA[sum % 30]]


func decode_result(text: String) -> Variant:
	var t := text.strip_edges().to_upper().replace(" ", "")
	var dash := t.find("-")
	if dash < 0 or t.length() - dash - 1 != 6:
		return null
	var body := t.substr(dash + 1)
	var n := 0
	var sum := 0
	for i in 5:
		var d := ALPHA.find(body[i])
		if d < 0:
			return null
		n = n * 30 + d
		sum += d * (5 - i)
	if ALPHA[sum % 30] != body[5]:
		return null
	var r := {"case": t.substr(0, dash)}
	r.time = n % 400
	n /= 400
	r.hints = n % 4
	n /= 4
	r.W = 4.0 + (n % 11) / 2.0
	n /= 11
	r.R = 4.0 + (n % 11) / 2.0
	n /= 11
	r.L = 4.0 + (n % 11) / 2.0
	n /= 11
	if n > 2:
		return null
	r.ending = ENDINGS[n]
	return r


# ───────────────────────── home screen and the case runner ─────────────────────────

func home() -> void:
	in_case = false
	clear_actors()
	set_head([])
	set_tray([])
	set_prop(null)
	desk.texture = UI.texture("res://assets/ui/desk.png")
	var kids: Array = []
	var art_mask := StageFX.rect_image(StageFX.fade_mask(0.3))
	art_mask.clip_children = CanvasItem.CLIP_CHILDREN_ONLY
	art_mask.clip_contents = true
	art_mask.custom_minimum_size = Vector2(0, 250)
	var art := UI.image("res://assets/places/unit9.png")
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.set_anchors_preset(Control.PRESET_FULL_RECT)
	art_mask.add_child(art)
	var sam := UI.image("res://assets/characters/sam_neutral.png")
	sam.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	sam.offset_top = -210
	sam.offset_right = 175
	sam.offset_left = 8
	sam.modulate = StageFX.ambient_tint(art.texture)
	art_mask.add_child(sam)
	kids.append(art_mask)
	var title := UI.label("CASE\nFILES", 70, UI.type_b)
	title.add_theme_constant_override("line_spacing", -16)
	var bar := ColorRect.new()
	bar.color = UI.RED
	bar.custom_minimum_size = Vector2(84, 8)
	bar.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var pin := UI.image("res://assets/ui/pin.png", Vector2(26, 28))
	pin.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var label := UI.paper([pin, UI.tag("Unit 9, Language Crimes", UI.SOFT, 14), title, bar,
		UI.label("Detective work where the evidence is English. Every answer you give does a job in the case.", 19)], 18)
	label.resized.connect(func() -> void: label.pivot_offset = label.size * 0.5)
	label.rotation = -0.018
	kids.append(label)
	for path in CASES:
		var c = _read_json(path)
		if not (c is Dictionary):
			continue
		var saved = _read_json("user://save_%s.json" % c.id)
		var resume: bool = saved is Dictionary and saved.get("phase", "briefing") != "briefing"
		var open := UI.button("Continue the case" if resume else "Open the case", "primary", "open-case")
		open.pressed.connect(func() -> void: start(c, saved if resume else null))
		var rows: Array = [UI.tag("Case " + c.number, UI.SOFT, 14), UI.label(c.title, 30, UI.serif_b), UI.label(c.tagline, 19),
			UI.label("About %d minutes. %s." % [int(c.minutes), ", ".join(c.skills)], 15, UI.type, UI.SOFT), open]
		if resume:
			var again := UI.button("Start again from the beginning", "ghost", "restart-case")
			again.pressed.connect(func() -> void: start(c, null))
			rows.append(again)
		kids.append(UI.panel(UI.box(UI.MANILA, 18, 8, 2, Color("8a6a35"), 7), [UI.vbox(rows, 8)]))
	var check := UI.button("Sound check", "ghost", "sound-check")
	check.pressed.connect(sound_check)
	var bank := UI.button("My word bank", "ghost", "word-bank")
	bank.pressed.connect(func() -> void: open_notebook("words"))
	kids.append(UI.hbox([check, bank], 8))
	var snd := UI.button("", "ghost", "toggle-sound")
	snd.text = "Sound effects: " + ("on" if sound_on else "off")
	snd.pressed.connect(func() -> void:
		sound_on = not sound_on
		_write_json("user://prefs.json", {"sound": sound_on, "shake": shake_on})
		snd.text = "Sound effects: " + ("on" if sound_on else "off")
		sfx("good"))
	kids.append(snd)
	var shk := UI.button("", "ghost", "toggle-shake")
	shk.text = "Screen shake: " + ("on" if shake_on else "off")
	shk.pressed.connect(func() -> void:
		shake_on = not shake_on
		_write_json("user://prefs.json", {"sound": sound_on, "shake": shake_on})
		shk.text = "Screen shake: " + ("on" if shake_on else "off")
		shake(0.4))
	kids.append(shk)
	var note := UI.label("Calls and radio messages are spoken aloud. Turn your sound on, or use headphones.", 15, UI.serif_i, UI.SOFT)
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	kids.append(note)
	_clear(work)
	for k in kids:
		work.add_child(k)


func sound_check() -> void:
	sfx("ring")
	toast("Playing a test message…", "")
	var c = _read_json(CASES[0])
	var ok := await speak([c.get("soundCheck", "This is a sound check.")], {"prefer": "female"}, Callable(), [c.get("soundCheckAudio", "")])
	toast("If you heard a voice, you’re ready." if ok else "No voice found on this device. Calls will be shown as text instead.", "" if ok else "bad")


func start(c: Dictionary, saved: Variant) -> void:
	data = c
	state = saved if saved is Dictionary else new_state()
	in_case = true
	moods.clear()
	_clear(work)
	update_hud()
	run_case()


func run_case() -> void:
	if state.phase == "briefing":
		await scenes.story(data.briefing)
		state.phase = "hub"
		save()
	while state.phase == "hub":
		var pick: String = await scenes.hub()
		if pick == "":
			state.phase = "board"
			save()
			break
		await scenes.run_lead(pick)
		if not state.done.has(pick):
			state.done.append(pick)
		save()
	if state.phase == "board":
		await scenes.board()
		state.phase = "accusation"
		save()
	if state.phase == "accusation":
		await scenes.accusation()
		state.phase = "report"
		save()
	await scenes.report()


func restart() -> void:
	DirAccess.remove_absolute("user://save_%s.json" % data.id)
	stop_speech()
	get_tree().reload_current_scene()


# ───────────────────────── hooks for the automated playtest ─────────────────────────

func _publish() -> void:
	var vp := get_viewport_rect().size
	var items := {}
	for n in get_tree().get_nodes_in_group("tid"):
		if n is Control and n.is_visible_in_tree():
			var r: Rect2 = n.get_global_rect()
			var off: bool = n is BaseButton and n.disabled
			items[n.get_meta("tid")] = [r.position.x / vp.x, r.position.y / vp.y, r.size.x / vp.x, r.size.y / vp.y, 1 if off else 0]
	var st := {"items": items, "dlg": dlg_catch.visible, "wipe": wipe.visible, "sheet": sheet.visible, "in_case": in_case,
		"clock": clock_label.text, "phase": state.get("phase", "home"), "scene": scenes.current, "evidence": state.get("evidence", []),
		"deductions": state.get("deductions", []), "ending": state.get("ending"), "tick": Engine.get_process_frames(), "marks": state.get("marks", {}), "trauma": trauma,
		"scroll": [scroll.position.y / vp.y, (scroll.position.y + scroll.size.y) / vp.y],
		"mini": mini, "voice": voice_player.stream.resource_path.get_file() if voice_player.playing and voice_player.stream else "",
		"typing": key_field, "words": words().size()}
	JavaScriptBridge.get_interface("window").cfTJson = JSON.stringify(st)


## Lets the playtest ask for an off-screen control to be scrolled into view.
func _js_show(args: Array) -> void:
	var want: String = str(args[0])
	for n in get_tree().get_nodes_in_group("tid"):
		if n.get_meta("tid") == want and n is Control and scroll.is_ancestor_of(n):
			scroll.ensure_control_visible(n)
