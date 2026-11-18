class_name StageFX
## Builders that make the art sit in one lit space instead of reading as pasted
## images: alpha masks that feather an edge into the desk, soft glows and
## shadows, and dust drifting in the light. Visual only.


## A vertical alpha mask: opaque from the top, fading to clear over the last
## `fade` (0..1) of its height. Used with clip_children to feather a picture's
## bottom edge into whatever lies behind it.
static func fade_mask(fade: float) -> GradientTexture2D:
	var g := Gradient.new()
	_shape(g, fade)
	var t := GradientTexture2D.new()
	t.gradient = g
	t.width = 4
	t.height = 256
	t.fill_from = Vector2(0, 0)
	t.fill_to = Vector2(0, 1)
	return t


## Moves the fade of a mask made by fade_mask().
static func set_fade(t: GradientTexture2D, fade: float) -> void:
	_shape(t.gradient, fade)


## Writes all three points in order every time. Moving a single point by index
## is unsafe: Gradient re-sorts its points, so an index can end up naming the
## transparent end and drag it into the middle of the picture.
static func _shape(g: Gradient, fade: float) -> void:
	var f := clampf(fade, 0.0, 1.0)
	g.offsets = PackedFloat32Array([0.0, 1.0 - f, 1.0])
	g.colors = PackedColorArray([Color.WHITE, Color.WHITE, Color(1, 1, 1, 0)])


## A soft radial blob: `inner` colour at the centre, clear at the rim.
static func radial(inner: Color, from := Vector2(0.5, 0.5), to := Vector2(1.0, 0.5), size := 128) -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, inner)
	g.set_color(1, Color(inner, 0.0))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = from
	t.fill_to = to
	t.width = size
	t.height = size
	return t


static func rect_image(tex: Texture2D, blend_add := false) -> TextureRect:
	var r := TextureRect.new()
	r.texture = tex
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if blend_add:
		var m := CanvasItemMaterial.new()
		m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		r.material = m
	return r


## Specks of dust drifting slowly up through the light.
static func dust() -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.amount = 22
	p.lifetime = 7.0
	p.preprocess = 7.0
	p.texture = radial(Color(1.0, 0.92, 0.75, 1.0), Vector2(0.5, 0.5), Vector2(1.0, 0.5), 16)
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.direction = Vector2(0.2, -1.0)
	p.spread = 35.0
	p.gravity = Vector2(0, -1.5)
	p.initial_velocity_min = 3.0
	p.initial_velocity_max = 9.0
	p.scale_amount_min = 0.12
	p.scale_amount_max = 0.3
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 0))
	ramp.set_color(1, Color(1, 1, 1, 0))
	ramp.add_point(0.25, Color(1, 1, 1, 0.45))
	ramp.add_point(0.75, Color(1, 1, 1, 0.35))
	p.color_ramp = ramp
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	p.material = m
	return p


## The average colour of a picture, as the light it casts on whoever stands in it.
## Returns a gentle tint (mostly white) so people take on the room's colour.
static func ambient_tint(tex: Texture2D) -> Color:
	if tex == null:
		return Color.WHITE
	var img := tex.get_image()
	if img == null:
		return Color.WHITE
	if img.is_compressed():
		img.decompress()
	img.resize(6, 4, Image.INTERPOLATE_BILINEAR)
	var sum := Color(0, 0, 0)
	for y in 4:
		for x in 6:
			sum += img.get_pixel(x, y)
	var avg := sum / 24.0
	var peak: float = max(avg.r, max(avg.g, avg.b), 0.001)
	var hue := Color(avg.r / peak, avg.g / peak, avg.b / peak)
	return Color.WHITE.lerp(hue, 0.2).darkened(0.04)
