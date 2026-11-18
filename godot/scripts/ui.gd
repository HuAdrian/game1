class_name UI
## Small builders for the paper-and-ink interface. No game rules live here.

# Ink and watercolour: deep ink blue, warm parchment, one red accent.
const INK := Color("1e2c4a")
const SOFT := Color("56627a")
const PAPER := Color("faf3e1")
const PAPER2 := Color("efe3c6")
const MANILA := Color("e8d3a0")
const RULE := Color("d8c7a4")
const RED := Color("b3261e")
const RED_SOFT := Color("f3d9cf")
const BLUE := Color("2c4a7c")
const BLUE_SOFT := Color("e2e6ee")
const GREEN := Color("2c4a7c")   # "correct" marks use ink blue: red is the only accent
const YELLOW := Color("f6e7b0")

static var serif: Font
static var serif_b: Font
static var serif_i: Font
static var type: Font
static var type_b: Font
static var hand: Font
static var hand_b: Font
## Noto Sans SC subset (GB2312 + Latin + arrows): the mini game host has no system
## fonts, so every glyph the Latin fonts lack (typed Chinese, "→") comes from here.
static var cjk: Font
## Bold Noto Sans SC, cut down to the characters of the Chinese interface text, so
## Chinese labels on bold Latin fonts read as bold too.
static var cjk_b: Font
## The Chinese title on the home screen, in the heaviest weight.
static var cjk_title: Font


static func init_fonts() -> void:
	var d := "res://assets/fonts/"
	serif = load(d + "CrimsonText-Regular.ttf")
	serif_b = load(d + "CrimsonText-Bold.ttf")
	serif_i = load(d + "CrimsonText-Italic.ttf")
	type = load(d + "CourierPrime-Regular.ttf")
	type_b = load(d + "CourierPrime-Bold.ttf")
	hand = load(d + "Kalam-Regular.ttf")
	hand_b = load(d + "Kalam-Bold.ttf")
	cjk = load(d + "NotoSansSC-Subset.woff2")
	cjk_b = load(d + "NotoSansSC-Bold-Subset.woff2")
	cjk_title = load(d + "NotoSansSC-Title-Subset.woff2")
	for f in [serif, serif_i, type, hand]:
		f.fallbacks = [cjk]
	for f in [serif_b, type_b, hand_b]:
		f.fallbacks = [cjk_b, cjk]


static func label(text: String, size := 20, font: Font = null, color := INK) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_override("font", font if font else serif)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_constant_override("line_spacing", 2)
	return l


## A small heading in typewriter capitals.
static func tag(text: String, color := SOFT, size := 13) -> Label:
	var l := label(text.to_upper(), size, type_b, color)
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	return l


## Turns *stars* into red emphasis for RichTextLabel.
static func bb(text: String) -> String:
	var out := ""
	var open := false
	for ch in text:
		if ch == "*":
			out += "[/b][/color]" if open else "[color=#c2271c][b]"
			open = not open
		elif ch == "[":
			out += "[lb]"
		else:
			out += ch
	if open:
		out += "[/b][/color]"
	return out


static func rich(bbcode: String, size := 21, font: Font = null, color := INK) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.add_theme_font_override("normal_font", font if font else serif)
	r.add_theme_font_override("bold_font", serif_b)
	r.add_theme_font_override("italics_font", serif_i)
	r.add_theme_font_size_override("normal_font_size", size)
	r.add_theme_font_size_override("bold_font_size", size)
	r.add_theme_font_size_override("italics_font_size", size)
	r.add_theme_color_override("default_color", color)
	r.text = bbcode
	return r


static func box(bg: Color, pad := 14, radius := 4, border := 0, border_color := INK, shadow := 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	s.set_border_width_all(border)
	s.border_color = border_color
	s.set_content_margin_all(pad)
	if shadow > 0:
		# a warm, deep shadow, as paper casts on a dark wooden desk under a lamp
		s.shadow_color = Color(0.08, 0.04, 0.01, 0.5)
		s.shadow_size = shadow + 4
		s.shadow_offset = Vector2(0, 3 + shadow * 0.35)
	return s


static func panel(style: StyleBox, kids: Array = []) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", style)
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.mouse_filter = Control.MOUSE_FILTER_PASS
	if kids.size() == 1:
		p.add_child(kids[0])
	elif kids.size() > 1:
		p.add_child(vbox(kids, 6))
	return p


## A sheet of paper lying on the desk.
static func paper(kids: Array, pad := 16, bg := PAPER) -> PanelContainer:
	return panel(box(bg, pad, 3, 0, INK, 7), [vbox(kids, 6)])


static func vbox(kids: Array = [], sep := 8) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.mouse_filter = Control.MOUSE_FILTER_PASS
	for k in kids:
		if k != null:
			v.add_child(k)
	return v


static func hbox(kids: Array = [], sep := 8) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	h.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.mouse_filter = Control.MOUSE_FILTER_PASS
	for k in kids:
		if k != null:
			h.add_child(k)
	return h


static func gap(h := 8) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


static func rule(color := RULE) -> ColorRect:
	var c := ColorRect.new()
	c.color = color
	c.custom_minimum_size = Vector2(0, 1.5)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


## kind: primary (ink), danger (red), ghost (outlined), paper
static func button(text: String, kind := "primary", tid := "") -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 54)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.clip_text = true
	b.add_theme_font_override("font", type_b)
	b.add_theme_font_size_override("font_size", 18)
	var bg := INK
	var fg := PAPER
	var border := INK
	match kind:
		"danger":
			bg = RED
			border = RED
		"ghost":
			bg = Color(PAPER, 0.92)
			fg = INK
			border = Color(INK, 0.45)
		"paper":
			bg = PAPER
			fg = INK
		"blue":
			bg = PAPER
			fg = BLUE
			border = BLUE
	var normal := box(bg, 10, 10, 2, border)
	normal.border_width_bottom = 5
	var pressed := box(bg.darkened(0.12), 10, 10, 2, border)
	pressed.content_margin_top = 13
	var disabled := box(Color(bg, 0.35), 10, 10, 2, Color(border, 0.25))
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", normal)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("disabled", disabled)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(c, fg)
	b.add_theme_color_override("font_disabled_color", Color(fg, 0.6))
	# squash on press, spring back on release
	b.button_down.connect(func() -> void:
		b.pivot_offset = b.size * 0.5
		var tw := b.create_tween()
		tw.tween_property(b, "scale", Vector2(0.96, 0.93), 0.05))
	b.button_up.connect(func() -> void:
		var tw := b.create_tween()
		tw.tween_property(b, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT))
	if tid != "":
		mark(b, tid)
	return b


## Gives a control an id the automated playtest can find.
static func mark(c: Control, tid: String) -> void:
	c.set_meta("tid", tid)
	c.add_to_group("tid")


## Makes any control tappable without stealing scroll drags from its parent.
static func tappable(c: Control, tid: String, cb: Callable) -> void:
	c.mouse_filter = Control.MOUSE_FILTER_PASS
	c.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if tid != "":
		mark(c, tid)
	var st := {"down": Vector2.INF}
	c.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
			if e.pressed:
				st.down = e.global_position
			elif st.down != Vector2.INF:
				var moved: float = st.down.distance_to(e.global_position)
				st.down = Vector2.INF
				if moved < 14.0 and not c.has_meta("off"):
					cb.call())


static func texture(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		return load(path)
	return null


static func image(path: String, min_size := Vector2.ZERO) -> TextureRect:
	var t := TextureRect.new()
	t.texture = texture(path)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.custom_minimum_size = min_size
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return t
