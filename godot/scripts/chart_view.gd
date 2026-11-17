class_name ChartView
extends Control
## A bar chart drawn in ink from case data.

var chart: Dictionary = {}
var highlight: Array = []:
	set(v):
		highlight = v
		queue_redraw()


func _ready() -> void:
	custom_minimum_size = Vector2(0, 250)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var left := 48.0
	var right := 8.0
	var top := 26.0
	var bottom := 40.0
	var pw := size.x - left - right
	var ph := size.y - top - bottom
	var maxv: float = chart.max
	var f := UI.type_b
	for t in chart.ticks:
		var y := top + ph - float(t) / maxv * ph
		var cap: bool = int(t) == int(chart.get("capacity", -1))
		if cap:
			draw_dashed_line(Vector2(left, y), Vector2(size.x - right, y), UI.SOFT, 1.5, 5.0)
		else:
			draw_line(Vector2(left, y), Vector2(size.x - right, y), UI.RULE, 1.0)
		draw_string(f, Vector2(0, y + 4), _num(int(t)), HORIZONTAL_ALIGNMENT_RIGHT, left - 6, 12, UI.SOFT)
	var bars: Array = chart.bars
	var slot := pw / bars.size()
	var bw := slot * 0.56
	for i in bars.size():
		var b: Dictionary = bars[i]
		var x := left + slot * i + (slot - bw) * 0.5
		var y2 := top + ph - float(b.value) / maxv * ph
		draw_rect(Rect2(x, y2, bw, top + ph - y2), UI.RED if highlight.has(i) else UI.INK)
		draw_string(f, Vector2(x - 10, y2 - 6), _num(int(b.value)), HORIZONTAL_ALIGNMENT_CENTER, bw + 20, 14, UI.INK)
		draw_string(f, Vector2(x - 10, top + ph + 17), b.label, HORIZONTAL_ALIGNMENT_CENTER, bw + 20, 15, UI.INK)
		if b.has("tag"):
			draw_string(UI.type, Vector2(x - 14, top + ph + 32), b.tag, HORIZONTAL_ALIGNMENT_CENTER, bw + 28, 12, UI.RED)
	draw_line(Vector2(left, top + ph), Vector2(size.x - right, top + ph), UI.INK, 2.0)


func _num(v: int) -> String:
	var s := str(v)
	return s if s.length() < 4 else s.substr(0, s.length() - 3) + "," + s.substr(s.length() - 3)
