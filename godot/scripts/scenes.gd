class_name Scenes
extends RefCounted
## CASE FILES: scene types.
##
## Each function plays one kind of scene from case data, so a new case reuses them:
##   story          dialogue and documents (the briefing)
##   hub            choose which lead to follow next; every lead costs time
##   wiretap        Listening Part 1: type what you hear into a form
##   tail           Listening Part 2: follow directions on a map
##   interrogation  Reading T/F/NG, proved from a document or with an evidence card
##   chart          Writing Task 1: find and fix the sentence that misreads the data
##   forgery        Grammar: find the mistakes and choose the corrections
##   torn           Linking words: rebuild a note so its logic works
##   scan           Reading: find the line that answers a question
##   board          combine two evidence cards into a deduction
##   accusation     a suspect and three proofs; three endings
##   report         bands, result code, comparison

var g: Main
var current := ""

const HAND_FONT := "res://assets/fonts/Kalam-Regular.ttf"


# ───────────────────────── documents ─────────────────────────

func render_doc(d: Dictionary) -> Control:
	match d.kind:
		"receipt":
			var rows: Array = [_center(UI.label(d.shop, 24, UI.type_b)), _center(UI.label(d.address, 16, UI.type)), _center(UI.label(d.ref, 16, UI.type)), UI.rule(UI.INK)]
			for i in d.lines.size():
				var l: Array = d.lines[i]
				var hot: bool = str(l[0]).begins_with("EXTENDED")
				var a := UI.label(l[0], 16, UI.type, UI.RED if hot else UI.INK)
				var b := UI.label(l[1], 16, UI.type_b, UI.RED if hot else UI.INK)
				b.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
				rows.append(UI.hbox([a, b], 6))
			rows.append(UI.rule(UI.INK))
			var t := UI.label(d.total[1], 17, UI.type_b)
			t.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			rows.append(UI.hbox([UI.label(d.total[0], 17, UI.type_b), t], 6))
			if d.has("note"):
				rows.append(_center(UI.label(d.note, 20, UI.hand, UI.BLUE)))
			rows.append(_center(UI.label("* * * THANK YOU * * *", 14, UI.type)))
			return UI.paper(rows, 20)
		"newspaper":
			var kids: Array = [_center(UI.label(d.paper, 32, UI.serif_b)), UI.rule(UI.INK), _center(UI.tag(d.get("edition", "Late edition"), UI.INK, 12)), UI.rule(UI.INK),
				UI.label(str(d.headline), 38, UI.serif_b), UI.label(d.sub, 22, UI.serif_i), UI.rule(UI.INK)]
			for para in d.body:
				kids.append(UI.label(para, 19))
			return UI.paper(kids, 18, Color("f3e8cc"))
		_:
			var grid := GridContainer.new()
			grid.columns = 2
			grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			grid.add_theme_constant_override("h_separation", 10)
			grid.add_theme_constant_override("v_separation", 10)
			for r in d.rows:
				var k := UI.tag(r[0], UI.SOFT, 12)
				k.custom_minimum_size = Vector2(98, 0)
				k.size_flags_horizontal = Control.SIZE_FILL
				grid.add_child(k)
				grid.add_child(UI.label(r[1], 17, UI.type))
			var top: Array = [UI.tag(d.get("ref", ""), UI.SOFT, 12)]
			if d.has("stamp"):
				var st := UI.label(d.stamp, 15, UI.type_b, UI.RED)
				st.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
				top = [UI.hbox([UI.tag(d.get("ref", ""), UI.SOFT, 12), st])]
			var p := UI.paper(top + [UI.label(d.title, 28, UI.serif_b), UI.rule(UI.INK), grid], 18)
			return p


func _center(l: Label) -> Label:
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


func evidence_card(e: Dictionary, selectable := true) -> PanelContainer:
	var pin := UI.image("res://assets/ui/pin.png", Vector2(22, 24))
	pin.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	pin.modulate.a = 0.35 if selectable else 1.0
	var p := UI.panel(UI.box(UI.PAPER, 10, 3, 3, Color(UI.PAPER, 1.0), 6), [UI.vbox([pin, UI.tag(e.title, UI.INK, 14), UI.label(e.text, 16)], 3)])
	p.set_meta("pin", pin)
	return p


func deduction(id: String) -> Dictionary:
	for d in g.data.board.deductions:
		if d.id == id:
			return d
	return {}


func deduction_card(d: Dictionary) -> PanelContainer:
	var strong: bool = d.get("strong", false)
	var p := UI.panel(UI.box(UI.RED_SOFT if strong else UI.BLUE_SOFT, 10, 3, 3, UI.RED if strong else UI.BLUE, 6),
		[UI.vbox([UI.tag(Shell.t("Deduction"), UI.RED if strong else UI.BLUE, 11), UI.label(d.title, 20, UI.serif_b), UI.label(d.text, 16)], 2)])
	return p


func _select(p: PanelContainer, on: bool, color := UI.RED) -> void:
	var s: StyleBoxFlat = p.get_theme_stylebox("panel")
	s.border_color = color if on else Color(UI.PAPER, 1.0)
	if p.has_meta("pin"):
		p.get_meta("pin").modulate.a = 1.0 if on else 0.35
	p.pivot_offset = p.size * 0.5
	s.shadow_size = 14 if on else 6
	s.shadow_offset = Vector2(0, 9) if on else Vector2(0, 3)
	g.sfx("card")
	var tw := p.create_tween().set_parallel(true)
	tw.tween_property(p, "scale", Vector2(1.06, 1.06) if on else Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(p, "rotation", (0.03 if randf() < 0.5 else -0.03) if on else 0.0, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## A document made of tappable lines (the schedule, the logs). Returns {paper, lines, sections}.
func _line_doc(doc: Dictionary, on_tap: Callable) -> Dictionary:
	var lines := {}
	var sections := {}
	var hd := UI.label(doc.head, 22, UI.type_b, UI.PAPER)
	var sub := UI.label("%s   %s" % [doc.title, doc.date], 14, UI.type, Color(UI.PAPER, 0.85))
	var kids: Array = [UI.panel(UI.box(UI.INK, 12, 2), [UI.vbox([hd, sub], 0)]), UI.label(doc.sub, 16, UI.serif_i)]
	var secs: Array = doc.get("sections", [{"id": "all", "title": "", "lines": doc.get("lines", [])}])
	for sec in secs:
		var box := UI.vbox([], 0)
		if sec.title != "":
			box.add_child(UI.tag(sec.title, UI.RED, 13))
		for l in sec.lines:
			var time := UI.label(l.get("time", ""), 15, UI.type_b)
			time.custom_minimum_size = Vector2(104, 0)
			time.size_flags_horizontal = Control.SIZE_FILL
			time.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			var text := UI.label(l.text, 18)
			var note := UI.tag("", UI.RED, 11)
			note.visible = false
			var inner: Control = UI.vbox([UI.hbox([time, text], 8) if l.has("time") else text, note], 2)
			var st := UI.box(Color(UI.PAPER, 0.0), 9, 0)
			st.border_width_top = 1
			st.border_color = UI.RULE
			var row := UI.panel(st, [inner])
			row.custom_minimum_size = Vector2(0, 50)
			row.set_meta("note", note)
			var id: String = l.id
			UI.tappable(row, "line-" + id, func() -> void: on_tap.call(id))
			lines[id] = row
			box.add_child(row)
		var wrap := UI.panel(UI.box(Color(UI.YELLOW, 0.0), 2, 2), [box])
		sections[sec.id] = wrap
		kids.append(wrap)
	return {"paper": UI.paper(kids, 14), "lines": lines, "sections": sections}


func _tint(p: PanelContainer, c: Color) -> void:
	p.get_theme_stylebox("panel").bg_color = c


func _flash_section(p: PanelContainer) -> void:
	_tint(p, UI.YELLOW)
	g.ensure_visible(p)
	var tw := p.create_tween()   # bound to the panel, so it ends if the panel goes
	tw.tween_interval(6.0)
	tw.tween_callback(func() -> void: _tint(p, Color(UI.YELLOW, 0.0)))


## Options in the tray. Wrong options cost time and are crossed out. Returns true when
## the right one is chosen, false if the player backs out.
func _choose_fix(prompt: String, options: Array, on_wrong: Callable, allow_back := false) -> bool:
	var w := Main.Wait.new()
	var kids: Array = [_center(UI.label(prompt, 16, UI.type, UI.SOFT))]
	for i in options.size():
		var o: Dictionary = options[i]
		var lab := UI.label(o.text, 18)
		var row := UI.panel(UI.box(UI.PAPER, 12, 10, 2, UI.INK), [lab])
		var st := {"busy": false}
		UI.tappable(row, "opt-%d" % i, func() -> void:
			if st.busy:
				return
			if o.get("correct", false):
				g.sfx("good")
				w.done.emit(true)
				return
			st.busy = true
			row.set_meta("off", true)
			row.modulate.a = 0.45
			PenMark.draw_on(row, "strike", UI.RED)
			await on_wrong.call(o)
			st.busy = false)
		kids.append(row)
	if allow_back:
		var back := UI.button(Shell.t("Leave this sentence"), "ghost", "opt-back")
		back.pressed.connect(func() -> void: w.done.emit(false))
		kids.append(back)
	g.set_tray(kids)
	var v = await w.done
	g.set_tray([])
	return v


# ───────────────────────── tape recorder and radio ─────────────────────────

func _make_tape(label: String, who: String) -> Dictionary:
	var reels: Array = []
	for i in 2:
		var r := UI.image("res://assets/ui/reel.png", Vector2(36, 36))
		r.pivot_offset = Vector2(18, 18)
		r.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		reels.append(r)
	var status := UI.label(Shell.t("Plays once only"), 13, UI.type, Color("f0b9b2"))
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 5)
	bar.add_theme_stylebox_override("background", UI.box(Color(1, 1, 1, 0.25), 0, 2))
	bar.add_theme_stylebox_override("fill", UI.box(UI.RED, 0, 2))
	var name := UI.label(label.to_upper(), 15, UI.type_b, UI.PAPER2)
	var sub := UI.label(who, 13, UI.type, Color(UI.PAPER2, 0.75))
	sub.autowrap_mode = TextServer.AUTOWRAP_OFF
	sub.clip_text = true
	var play := UI.button(Shell.t("Play"), "danger", "tape-play")
	play.custom_minimum_size = Vector2(104, 56)
	play.size_flags_horizontal = Control.SIZE_SHRINK_END
	var panel := UI.panel(UI.box(Color("22345a"), 12, 10, 2, Color("16213a"), 8), [UI.hbox([reels[0], reels[1], UI.vbox([name, sub, bar, status], 2), play], 8)])
	return {"panel": panel, "reels": reels, "status": status, "bar": bar, "play": play}


## Plays a script through the tape. If the device has no voice, shows the transcript to read once.
func _play_tape(tape: Dictionary, lines: Array, speaker: String, clips: Array = []) -> void:
	var cast: Dictionary = g.data.cast[speaker]
	tape.status.text = Shell.t("Playing…")
	g.show_actor(speaker, "neutral", "right")
	var spin: Tween = g.create_tween().set_loops()
	spin.tween_method(func(a: float) -> void:
		for r in tape.reels:
			r.rotation = a, 0.0, TAU, 1.6)
	var ok: bool = await g.speak(lines, cast.get("voice", {}), func(i: int) -> void:
		tape.bar.value = 100.0 * float(i + 1) / lines.size()
		g.react(speaker, "nod"), clips)
	spin.kill()
	if not ok:
		tape.status.text = Shell.t("No voice on this device")
		var w := Main.Wait.new()
		var kids: Array = [UI.label(Shell.t("This device has no speech voice, so here is the transcript instead. Read it once, then put it away."), 15, UI.type_b, UI.RED)]
		for l in lines:
			kids.append(UI.label(l, 17, UI.type))
		var b := UI.button(Shell.t("I’ve read it. Put it away"), "paper", "transcript-done")
		b.pressed.connect(func() -> void: w.done.emit(true))
		kids.append(b)
		var box := UI.panel(UI.box(UI.PAPER, 12, 8, 2, UI.RED), [UI.vbox(kids, 6)])
		g.work.add_child(box)
		g.work.move_child(box, 0)
		g.scroll.scroll_vertical = 0
		await w.done
		box.queue_free()
	tape.bar.value = 100.0
	tape.status.text = Shell.t("Tape finished")
	g.hide_actor(speaker)


## The recorded clips for a listening round: audio[i] is script[i] spoken.
func _round_audio(sc: Dictionary, round_id: String) -> Array:
	var src: Dictionary = sc if round_id == "first" else sc.get("retry", {})
	return src.get("audio", [])


## Replays a few lines as a hint (audio, or as quoted text when there is no voice).
func _replay(speaker: String, lines: Array, lead: String, clips: Array = []) -> void:
	if lead != "":
		await g.say([lead])
	g.show_actor(speaker, "neutral", "right")
	var ok: bool = await g.speak(lines, g.data.cast[speaker].get("voice", {}), Callable(), clips)
	if not ok:
		var quoted: Array = []
		for l in lines:
			quoted.append("@%s %s" % [speaker, l])
		await g.say(quoted)
	g.hide_actor(speaker)


# ───────────────────────── story ─────────────────────────

func story(sc: Dictionary) -> void:
	current = sc.id
	await g.transition(sc)
	g.show_actor("sam")
	await g.play(sc.beats)


# ───────────────────────── hub: which lead next? ─────────────────────────

func _lead(id: String) -> Dictionary:
	for l in g.data.leads:
		if l.id == id:
			return l
	return {}


func hub() -> String:
	current = "hub"
	var hubd: Dictionary = g.data.hub
	await g.transition(hubd)
	g.show_actor("sam")
	if g.flag("hub_seen") == null:
		g.flag("hub_seen", true)
		await g.say(hubd.intro)
	else:
		await g.say([hubd.back[g.state.done.size() % hubd.back.size()]])
	if g.now() > g.deadline() and g.flag("late_said") == null:
		g.flag("late_said", true)
		await g.say(hubd.late)
	var w := Main.Wait.new()
	var left: int = g.deadline() - g.now()
	var kids: Array = []
	var open_cost := 0
	for l in g.data.leads:
		var sc: Dictionary = l.scene
		var done: bool = g.state.done.has(l.id)
		var locked := false
		for req in l.get("requires", []):
			if not g.state.done.has(req):
				locked = true
		if not done:
			open_cost += int(l.cost)
		var cost := UI.label(Shell.t("%d min") % int(l.cost), 20, UI.type_b, UI.RED)
		cost.autowrap_mode = TextServer.AUTOWRAP_OFF
		cost.size_flags_horizontal = Control.SIZE_SHRINK_END
		var status := ""
		if done:
			status = Shell.t(hubd.doneTag)
		elif locked:
			status = Shell.t(l.get("locked", "Locked"))
		elif l.get("optional", false):
			status = Shell.t(hubd.optionalTag)
		var title := UI.label(Shell.t(sc.title), 24, UI.serif_b)
		var rows: Array = [UI.hbox([title, cost if not done else null], 6), UI.label(Shell.t(l.teaser), 17), UI.label((Shell.t(sc.skill) + ("   " + status if status != "" else "")).to_upper(), 12, UI.type_b, UI.RED if status != "" and not done else UI.SOFT)]
		var card := UI.panel(UI.box(UI.PAPER if not (done or locked) else Color(UI.PAPER2, 0.75), 12, 4, 2, UI.INK if not (done or locked) else UI.RULE, 0 if done or locked else 6), [UI.vbox(rows, 3)])
		if done:
			PenMark.draw_on(card, "tick", UI.BLUE)
			card.modulate.a = 0.75
		elif locked:
			card.modulate.a = 0.6
		else:
			var id: String = l.id
			UI.tappable(card, "lead-" + id, func() -> void: w.done.emit(id))
		kids.append(card)
	var info: String = (Shell.t("%s left before the curtain. The leads still open would take %d minutes.") % [Shell.t("%d minutes") % left, open_cost]) if left > 0 else (Shell.t("No time left before the curtain. The leads still open would take %d minutes.") % open_cost)
	g.set_head([UI.panel(UI.box(Color(UI.MANILA, 0.95), 10, 6, 2, UI.INK), [UI.label(info, 16, UI.type_b)])])
	g.set_work(kids)
	var leave := UI.button(Shell.t(hubd.leave), "danger", "hub-leave")
	leave.disabled = g.state.done.is_empty()
	leave.pressed.connect(func() -> void: w.done.emit(""))
	g.set_tray([leave])
	g.set_hint(func() -> bool:
		await g.say([hubd.hint])
		return true)
	while true:
		var pick: String = await w.done
		if pick != "":
			return pick
		if open_cost == 0 or await g.confirm(Shell.t("Build the case?"), Shell.t(hubd.leaveConfirm), Shell.t("Build the case"), Shell.t("Keep investigating")):
			return ""
	return ""


func run_lead(id: String) -> void:
	var l := _lead(id)
	var sc: Dictionary = l.scene
	current = id
	await g.transition(sc)
	if g.flag("paid_" + id) == null:   # reloading in the middle of a lead does not charge for it twice
		g.flag("paid_" + id, true)
		g.spend(int(l.cost))
	g.show_actor("sam")
	match sc.type:
		"wiretap":
			await wiretap(sc)
		"tail":
			await tail(sc)
		"interrogation":
			await interrogation(sc)
		"chart":
			await chart(sc)
		"forgery":
			await forgery(sc)
		"torn":
			await torn(sc)
		"scan":
			await scan(sc)
	g.set_hint()
	g.set_work([])
	g.set_head([])
	g.set_tray([])
	g.set_prop(null)


# ───────────────────────── wiretap: Listening Part 1 ─────────────────────────

func _norm(s: String) -> String:
	var n := s.to_lower()
	for ch in [",", ";", "!"]:
		n = n.replace(ch, " ")
	while n.find("  ") >= 0:
		n = n.replace("  ", " ")
	n = n.strip_edges()
	if n.ends_with("."):
		n = n.substr(0, n.length() - 1)
	return n


func _field_right(f: Dictionary, value: String) -> bool:
	var n := _norm(value)
	if f.get("kind", "") == "time":
		if n.begins_with("at "):
			n = n.substr(3)
		for suffix in [" p.m", " pm", "p.m", "pm", " p m"]:
			if n.ends_with(suffix):
				n = n.substr(0, n.length() - suffix.length())
				break
		n = n.strip_edges()
	for p in f.get("strip", []):
		if n.begins_with(p):
			n = n.substr(p.length()).strip_edges()
	return f.accept.has(n)


func wiretap(sc: Dictionary) -> void:
	g.sfx("ring")
	await g.play(sc.intro)
	var all: Array = sc.form.fields
	var values := {}
	var right := {}
	var first_map := {}
	var ids: Array = []
	for f in all:
		first_map[f.id] = f.lines
		ids.append(f.id)
	var wrong: Array = await _wiretap_round(sc, "first", sc.speaker, sc.script, first_map, ids, values, right)
	for f in all:
		g.mark("L", sc.id + "." + f.id, right[f.id])
	if wrong.is_empty():
		await g.play(sc.success)
	else:
		# The lead goes cold: the same facts must be won again from a harder call.
		var lines: Array = [sc.coldIntro]
		for f in wrong:
			lines.append(g.fmt(f.cold, {"value": values[f.id] if values[f.id] != "" else "nothing at all"}))
		await g.say(lines)
		g.lose(int(sc.coldCost))
		await g.play(sc.cold)
		var again: Array = []
		for f in wrong:
			again.append(f.id)
		var still: Array = await _wiretap_round(sc, "retry", sc.retry.speaker, sc.retry.script, sc.retry.lines, again, values, right)
		if still.is_empty():
			await g.play(sc.retry.success)
		else:
			g.lose(int(sc.retry.failCost))
			for f in still:
				g.lock_field(f.id, UI.RED, f.answer)
			await g.play(sc.retry.fail)
	await g.play(sc.outro)


## One listening round: play once, fill the open fields, hand the notes over.
func _wiretap_round(sc: Dictionary, round_id: String, speaker: String, script: Array, line_map: Dictionary, open: Array, values: Dictionary, right: Dictionary) -> Array:
	var cast: Dictionary = g.data.cast[speaker]
	var audio: Array = _round_audio(sc, round_id)
	var played_key: String = "%s.%s.played" % [sc.id, round_id]
	var st := {"played": g.flag(played_key) != null, "busy": false}
	var tape := _make_tape(Shell.t("Voicemail") if round_id == "first" else Shell.t("Phone call"), "%s, %s" % [cast.name, cast.role])
	g.fields.clear()
	var rows: Array = [UI.label(str(sc.form.title).to_upper(), 24, UI.type_b), UI.tag(sc.form.sub, UI.SOFT, 12)]
	for gv in sc.form.given:
		var lab := UI.tag(gv[0], UI.SOFT, 13)
		lab.size_flags_horizontal = Control.SIZE_FILL
		rows.append(UI.hbox([lab, UI.label(gv[1], 24, UI.hand, UI.BLUE)], 8))
		rows.append(UI.rule(Color("c9d1de")))
	var marks := {}
	for f in sc.form.fields:
		var lab2 := UI.tag(f.label, UI.SOFT, 13)
		lab2.size_flags_horizontal = Control.SIZE_FILL
		lab2.autowrap_mode = TextServer.AUTOWRAP_OFF
		var pre: Label = null
		if f.has("prefix"):
			pre = UI.label(f.prefix, 24, UI.hand, UI.BLUE)
			pre.size_flags_horizontal = Control.SIZE_FILL
			pre.autowrap_mode = TextServer.AUTOWRAP_OFF
		var le: LineEdit = g.add_field(f.id, f.label)
		var mk := UI.label("", 20, UI.type_b, UI.GREEN)
		mk.custom_minimum_size = Vector2(52, 0)
		mk.size_flags_horizontal = Control.SIZE_FILL
		mk.autowrap_mode = TextServer.AUTOWRAP_OFF
		marks[f.id] = mk
		if not open.has(f.id):
			le.text = values.get(f.id, "")
			g.lock_field(f.id, UI.BLUE, le.text)
			mk.text = "ok"
		rows.append(UI.hbox([lab2, pre, le, mk], 8))
	var page := UI.paper(rows, 16)
	var submit := UI.button(Shell.t("Hand notes to Sam"), "primary", "submit-notes")
	submit.disabled = not st.played
	var arm_hint := func() -> void:
		g.set_hint(func() -> bool:
			var target: String = open[0]
			for id in open:
				if g.field_value(id) == "":
					target = id
					break
			var label := ""
			for f in sc.form.fields:
				if f.id == target:
					label = f.label
			var lines: Array = []
			var clips: Array = []
			for i in line_map[target]:
				lines.append(script[int(i)])
				clips.append(audio[int(i)] if int(i) < audio.size() else "")
			await _replay(speaker, lines, "%s This is the bit about “%s”." % [sc.hintLine, label], clips)
			return true)
	tape.play.pressed.connect(func() -> void:
		if st.played or st.busy:
			return
		st.played = true
		st.busy = true
		g.flag(played_key, true)
		tape.play.disabled = true
		tape.play.text = "…"
		g.sfx("clunk")
		await _play_tape(tape, script, speaker, audio)
		g.sfx("clunk")
		st.busy = false
		tape.play.text = Shell.t("Played")
		submit.disabled = false
		arm_hint.call())
	if st.played:
		tape.play.disabled = true
		tape.play.text = Shell.t("Played")
		tape.status.text = Shell.t("Tape finished")
		arm_hint.call()
	else:
		g.set_hint(Callable(), Shell.t("Play the tape first. Sam can’t wind back what you haven’t heard."))
	g.set_prop(tape.panel)
	g.set_work([page])
	g.set_tray([submit])
	await submit.pressed
	g.set_hint()
	g.set_tray([])
	var wrong: Array = []
	for f in sc.form.fields:
		if not open.has(f.id):
			continue
		values[f.id] = g.field_value(f.id)
		right[f.id] = _field_right(f, values[f.id])
		g.lock_field(f.id, UI.BLUE if right[f.id] else UI.RED, values[f.id])
		marks[f.id].text = "ok" if right[f.id] else "no"
		marks[f.id].add_theme_color_override("font_color", UI.GREEN if right[f.id] else UI.RED)
		if not right[f.id]:
			wrong.append(f)
	g.sfx("good" if wrong.is_empty() else "bad")
	await g.wait(1.0)
	return wrong


# ───────────────────────── tail: Listening Part 2 ─────────────────────────

func tail(sc: Dictionary) -> void:
	await g.play(sc.intro)
	var tried: Array = []
	var pick: Dictionary = await _tail_round(sc, "first", sc.script, sc.hintLines, tried)
	var ok: bool = pick.id == sc.answer
	g.mark("L", sc.id, ok, 2)
	if not ok:
		tried.append(pick.id)
		g.lose(int(sc.wrongCost))
		g.set_mood(sc.speaker, "annoyed")
		await g.say(sc.wrong, {"id": pick.id, "what": pick.get("what", "the wrong place")})
		await g.play(sc.retry.intro)
		pick = await _tail_round(sc, "retry", sc.retry.script, sc.retry.hintLines, tried)
		if pick.id != sc.answer:
			g.lose(int(sc.retry.wrongCost))
			await g.say(sc.retry.wrong)
	g.set_work([])
	g.set_prop(null)
	g.set_scene_full(true)
	await g.stamp("LOCATED", "ink")
	await g.play(sc.success)
	await g.play(sc.outro)


func _tail_round(sc: Dictionary, round_id: String, script: Array, hint_lines: Array, tried: Array) -> Dictionary:
	var cast: Dictionary = g.data.cast[sc.speaker]
	var audio: Array = _round_audio(sc, round_id)
	var played_key: String = "%s.%s.played" % [sc.id, round_id]
	var st := {"played": g.flag(played_key) != null, "busy": false, "pick": null}
	var tape := _make_tape(Shell.t("Police radio"), "%s, %s" % [cast.name, cast.role])
	var map := MapView.new()
	map.setup(sc.map, g.sfx)
	map.dead = tried.duplicate()
	var go := UI.button(Shell.t("Tap a building on the map"), "primary", "send-team")
	go.disabled = true
	map.picked.connect(func(b: Dictionary) -> void:
		st.pick = b
		g.sfx("pin")
		go.text = Shell.t("Send the team to building %s") % b.id
		go.disabled = not st.played or st.busy)
	var arm_hint := func() -> void:
		g.set_hint(func() -> bool:
			var lines: Array = []
			var clips: Array = []
			for i in hint_lines:
				lines.append(script[int(i)])
				clips.append(audio[int(i)] if int(i) < audio.size() else "")
			await _replay(sc.speaker, lines, sc.hintLine, clips)
			return true)
	tape.play.pressed.connect(func() -> void:
		if st.played or st.busy:
			return
		st.played = true
		st.busy = true
		g.flag(played_key, true)
		tape.play.disabled = true
		tape.play.text = "…"
		g.sfx("static")
		await _play_tape(tape, script, sc.speaker, audio)
		g.sfx("static")
		st.busy = false
		tape.play.text = Shell.t("Played")
		if st.pick != null:
			go.disabled = false
		arm_hint.call())
	if st.played:
		tape.play.disabled = true
		tape.play.text = Shell.t("Played")
		tape.status.text = Shell.t("Tape finished")
		arm_hint.call()
	else:
		g.set_hint(Callable(), Shell.t("Play the radio first. Then Sam can help."))
	var back := UI.button(Shell.t("Back to the hall"), "ghost", "map-reset")
	back.custom_minimum_size = Vector2(170, 44)
	back.size_flags_horizontal = Control.SIZE_SHRINK_END
	back.add_theme_font_size_override("font_size", 14)
	back.pressed.connect(map.reset)
	var help := UI.hbox([UI.label(Shell.t("Tap the corners to walk the marker along his route."), 15, UI.serif_i, UI.SOFT), back], 8)
	g.set_prop(tape.panel)
	g.set_work([UI.paper([map, help], 8)])
	g.set_tray([go])
	await go.pressed
	g.set_hint()
	g.set_tray([])
	return st.pick


# ───────────────────────── interrogation ─────────────────────────

const VERDICT_NAME := {"T": "TRUE", "F": "LIE", "NG": "NOT GIVEN"}
const FACES := ["neutral", "nervous", "sweating", "cracked"]

func _pips(box: HBoxContainer, total: int, filled: int, color: Color, round := false) -> void:
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()
	for i in total:
		var p := Panel.new()
		p.custom_minimum_size = Vector2(16, 16) if round else Vector2(26, 14)
		p.size_flags_horizontal = Control.SIZE_EXPAND_FILL if not round else Control.SIZE_FILL
		p.add_theme_stylebox_override("panel", UI.box(color if i < filled else UI.PAPER, 0, 8 if round else 3, 2, color if i < filled else UI.INK))
		p.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(p)


func interrogation(sc: Dictionary) -> void:
	var who: String = sc.suspect
	var cast: Dictionary = g.data.cast[who]
	g.show_actor(who, "neutral", "right")
	await g.play(sc.intro)
	var cost := int(g.data.mistakeCost)
	var st := {"hits": 0, "cred": int(sc.get("credibility", 3)), "armed": Callable(), "ended": false}
	var total_comp := int(sc.get("composure", 5))

	# meters stand in the scene, under the suspect
	var comp_label := UI.tag(Shell.t("His composure"), UI.INK, 12)
	var comp_box := UI.hbox([], 4)
	var cred_label := UI.tag(Shell.t("Your credibility"), UI.INK, 12)
	cred_label.size_flags_horizontal = Control.SIZE_FILL
	var cred_box := UI.hbox([], 4)
	cred_box.size_flags_horizontal = Control.SIZE_SHRINK_END
	var meters := UI.panel(UI.box(Color(UI.PAPER, 0.96), 9, 8, 2, UI.INK, 6), [UI.vbox([comp_label, comp_box, UI.hbox([cred_label, cred_box], 6)], 4)])
	UI.mark(meters, "meters")
	var draw_meters := func() -> void:
		_pips(comp_box, total_comp, total_comp - st.hits, UI.RED)
		_pips(cred_box, int(sc.get("credibility", 3)), st.cred, UI.BLUE, true)
		comp_label.text = (Shell.t("His composure: ") + Shell.t(["steady", "shaken", "sweating", "cracking", "gone", "gone"][min(st.hits, 5)])).to_upper()
		meters.pivot_offset = meters.size * 0.5
		var tw := meters.create_tween()
		tw.tween_property(meters, "scale", Vector2(1.06, 1.06), 0.08)
		tw.tween_property(meters, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	draw_meters.call()
	g.set_prop(meters)

	var quote_name := UI.tag(cast.name, UI.RED, 13)
	var quote_text := UI.label("", 21, UI.serif)
	var qs := UI.box(UI.PAPER, 12, 10, 0, UI.RED, 5)
	qs.border_width_left = 7
	var quote := UI.panel(qs, [UI.vbox([quote_name, quote_text], 2)])
	g.set_head([quote])

	var doc := _line_doc(sc.doc, func(id: String) -> void:
		if st.armed.is_valid():
			st.armed.call(id)
		else:
			g.toast(Shell.t("First decide: True, Lie or Not Given."), ""))
	g.set_work([doc.paper])

	var face := func() -> void:
		g.set_mood(who, FACES[min(st.hits, FACES.size() - 1)])
	var hit := func() -> void:
		st.hits += 1
		draw_meters.call()
		face.call()
		g.react(who, "flinch")
		g.sfx("gasp")
		g.set_tension(float(st.hits) / float(total_comp), who)
	var lose_cred := func() -> void:
		st.cred -= 1
		draw_meters.call()
		g.feedback("wrong")
		g.sfx("snap")
		g.set_mood(who, "smug")
		g.react(who, "hop")
		g.toast(Shell.t("Credibility lost"), "bad")

	var show_statement := func(label: String, text: String) -> void:
		quote_name.text = ("%s   %s" % [cast.name, label]).to_upper()
		quote_text.text = "“%s”" % text
		quote.modulate.a = 0.0
		var tw := quote.create_tween()
		tw.tween_property(quote, "modulate:a", 1.0, 0.25)
		g.react(who, "nod")

	# What does the player do with this statement? Returns {verdict, line} or {card}.
	var ask := func(card_only: bool) -> Dictionary:
		var w := Main.Wait.new()
		var verdicts := func() -> void:
			st.armed = Callable()
			var present := UI.button(Shell.t("Present an evidence card"), "paper", "present")
			present.pressed.connect(func() -> void: w.done.emit({"verdict": "CARD"}))
			if card_only:
				var pass_b := UI.button(Shell.t("Let it pass"), "ghost", "pass")
				pass_b.pressed.connect(func() -> void: w.done.emit({"verdict": "PASS"}))
				g.set_tray([present, pass_b])
				return
			var t := UI.button(Shell.t("TRUE"), "blue", "v-T")
			var f := UI.button(Shell.t("LIE"), "danger", "v-F")
			var n := UI.button(Shell.t("NOT GIVEN"), "ghost", "v-NG")
			n.pressed.connect(func() -> void: w.done.emit({"verdict": "NG"}))
			var prove := func(v: String) -> void:
				var msg := UI.label(Shell.t("Tap the line that proves he’s lying.") if v == "F" else Shell.t("Tap the line that proves it’s true."), 17, UI.type_b, UI.RED if v == "F" else UI.BLUE)
				var back := UI.button(Shell.t("Back"), "ghost", "v-back")
				back.custom_minimum_size = Vector2(90, 48)
				back.size_flags_horizontal = Control.SIZE_SHRINK_END
				back.pressed.connect(func() -> void: w.done.emit({"verdict": "BACK"}))
				g.set_tray([UI.hbox([msg, back], 8)])
				st.armed = func(id: String) -> void:
					st.armed = Callable()
					w.done.emit({"verdict": v, "line": id})
			t.pressed.connect(func() -> void: prove.call("T"))
			f.pressed.connect(func() -> void: prove.call("F"))
			g.set_tray([UI.hbox([t, f, n], 8), present])
		while true:
			verdicts.call()
			var ans: Dictionary = await w.done
			if ans.verdict == "BACK":
				continue
			if ans.verdict == "CARD":
				if g.state.evidence.is_empty():
					await g.say(sc.cardLines.none)
					continue
				g.set_tray([])
				var id: String = await g.pick_card(Shell.t("Which card do you put on the table?"), g.state.evidence)
				if id == "":
					continue
				ans["card"] = id
			g.set_tray([])
			st.armed = Callable()
			return ans
		return {}

	var out_of_cred := func() -> bool:
		if st.cred > 0:
			return false
		st.ended = true
		return true

	# ── statements checked against the document
	var chips_done := 0
	for n in sc.statements.size():
		if st.ended:
			break
		var s: Dictionary = sc.statements[n]
		var solved := false
		var attempt := 0
		while attempt < 2 and not solved and not st.ended:
			var proof: Array = s.harderProof if attempt == 1 and s.has("harderProof") else s.proof
			show_statement.call(Shell.t("statement %d of %d%s") % [n + 1, sc.statements.size(), Shell.t(", again") if attempt == 1 else ""], s.harder if attempt == 1 else s.text)
			g.set_hint(func() -> bool:
				_flash_section(doc.sections[s.hint.section])
				await g.say([s.hint.text])
				return true)
			var ans: Dictionary = await ask.call(false)
			g.set_hint()
			if ans.verdict == "CARD":
				# a card cannot settle a statement that the schedule settles
				lose_cred.call()
				await g.say(sc.cardLines.wrong + sc.cardLines.onDoc)
				face.call()
				if out_of_cred.call():
					break
				continue
			var right_verdict: bool = ans.verdict == s.verdict
			var ok: bool = right_verdict and (s.verdict == "NG" or proof.has(ans.get("line", "")))
			if attempt == 0:
				g.mark("R", sc.id + "." + s.id, ok)
			if ok:
				solved = true
				if s.verdict == "F":
					var row: PanelContainer = doc.lines[ans.line]
					_tint(row, UI.RED_SOFT)
					PenMark.draw_on(row, "underline", UI.RED)
					g.sfx("pen")
					row.get_meta("note").text = "PROVES LIE %d" % (n + 1)
					row.get_meta("note").visible = true
					hit.call()
					await g.stamp("CONTRADICTION", "red")
				elif s.verdict == "T":
					_tint(doc.lines[ans.line], UI.BLUE_SOFT)
					PenMark.draw_on(doc.lines[ans.line], "tick", UI.BLUE)
					g.sfx("pen")
					g.sfx("good")
					await g.stamp("CONFIRMED", "ink")
				else:
					g.sfx("good")
					await g.stamp("NOT GIVEN", "grey")
				await g.say(s.right)
			else:
				g.lose(cost)
				g.set_mood(who, "smug")
				g.react(who, "hop")
				var key: String = "line" if right_verdict else "%s>%s" % [ans.verdict, s.verdict]
				await g.say(sc.reactions[key])
				if attempt == 0:
					await g.say(sc.reactions.again)
				face.call()
				attempt += 1
		if st.ended:
			break
		if not solved:
			# Two misses: Sam settles it, but a lie settled by Sam does not shake the suspect.
			for id in s.proof:
				_tint(doc.lines[id], UI.RED_SOFT if s.verdict == "F" else UI.BLUE_SOFT)
			if not s.proof.is_empty():
				g.ensure_visible(doc.lines[s.proof[0]])
			var lines: Array = ["It’s %s. %s" % [VERDICT_NAME[s.verdict], s.explain]]
			if s.verdict == "F":
				lines += sc.reactions.resolvedLie
			await g.say(lines)
		g.word(s.get("word"))
		chips_done += 1

	# ── statements only an evidence card can break
	if not st.ended and sc.has("cardStatements"):
		g.set_work([])
		g.set_scene_full(true)
		await g.say(sc.cardIntro)
		for k in sc.cardStatements.size():
			if st.ended:
				break
			var cs: Dictionary = sc.cardStatements[k]
			show_statement.call(Shell.t("and another thing"), cs.text)
			g.set_hint(func() -> bool:
				await g.say([cs.hint])
				return true)
			while not st.ended:
				var ans2: Dictionary = await ask.call(true)
				if ans2.verdict == "PASS":
					await g.say(sc.cardLines.pass)
					break
				if ans2.card == cs.card:
					hit.call()
					await g.stamp("CONTRADICTION", "red")
					await g.say(cs.right)
					break
				lose_cred.call()
				await g.say(sc.cardLines.wrong)
				face.call()
				out_of_cred.call()
			g.set_hint()

	g.set_head([])
	g.set_tray([])
	g.set_work([])
	g.set_prop(null)
	g.set_scene_full(true)
	g.flag("interview_hits", st.hits)
	g.set_tension(0.0)
	if st.ended:
		g.flag("interview_lost", true)
		g.set_mood(who, "smug")
		await g.play(sc.cardLines.noCred)
	else:
		if st.hits >= int(sc.need):
			g.set_tension(1.0, who)
			g.set_mood(who, "cracked")
			g.sfx("crack")
			g.feedback("large")
			g.react(who, "slump")
			await g.play(sc.crack)
			g.set_tension(0.0)
		else:
			g.set_mood(who, "smug")
			await g.play(sc.noCrack)
		await g.play(sc.alibi)
	g.moods.erase(who)
	await g.play(sc.outro)


# ───────────────────────── chart: Writing Task 1 skills ─────────────────────────

func chart(sc: Dictionary) -> void:
	await g.play(sc.intro)
	var cost := int(g.data.mistakeCost)
	var view := ChartView.new()
	view.chart = sc.chart
	var pin := UI.image("res://assets/ui/pin.png", Vector2(22, 24))
	var chart_paper := UI.paper([pin, UI.label(sc.chart.title, 19, UI.type_b), UI.tag(sc.chart.note, UI.SOFT, 11), view], 12)
	var rows := {}
	var st := {"first": true, "target": null}
	var w := Main.Wait.new()
	var kids: Array = []
	for pair in [["To", sc.memo.to], ["From", sc.memo.from], ["Subject", sc.memo.subject]]:
		var k := UI.tag(pair[0], UI.SOFT, 12)
		k.custom_minimum_size = Vector2(76, 0)
		k.size_flags_horizontal = Control.SIZE_FILL
		kids.append(UI.hbox([k, UI.label(pair[1], 16, UI.type)], 6))
	kids.append(UI.rule(UI.INK))
	for s in sc.sentences:
		var note := UI.tag("", UI.GREEN, 11)
		note.visible = false
		var sb := UI.box(Color(UI.PAPER, 0.0), 10, 3)
		sb.border_width_bottom = 1
		sb.border_color = UI.RULE
		var row := UI.panel(sb, [UI.vbox([UI.label(s.text, 17, UI.type), note], 2)])
		row.custom_minimum_size = Vector2(0, 50)
		rows[s.id] = row
		kids.append(row)
		UI.tappable(row, "sent-" + s.id, func() -> void:
			if row.has_meta("checked") or st.target != null:
				return
			if s.get("false", false):
				st.target = s
				w.done.emit(true)
				return
			st.first = false
			row.set_meta("checked", true)
			note.text = "MATCHES THE CHART"
			note.visible = true
			PenMark.draw_on(row, "tick", UI.BLUE)
			g.sfx("pen")
			g.lose(cost)
			await g.say([s.wrong]))
	g.set_work([chart_paper, UI.paper(kids, 14)])
	g.set_tray([_center(UI.label(Shell.t("Tap the sentence that gets the chart wrong."), 17, UI.type_b))])
	g.set_hint(func() -> bool:
		var hl: Array = []
		for i in sc.chart.hintBars:
			hl.append(int(i))
		view.highlight = hl
		g.scroll.scroll_vertical = 0
		await g.say([sc.hint])
		return true)
	await w.done
	g.mark("W", sc.id + ".find", st.first)
	var target: Dictionary = st.target
	var trow: PanelContainer = rows[target.id]
	_tint(trow, UI.RED_SOFT)
	PenMark.draw_on(trow, "circle", UI.RED)
	g.sfx("pen")
	await g.stamp("FALSE", "red")
	await g.say(sc.found)
	var fix := {"first": true}
	g.set_hint(func() -> bool:
		await g.say([sc.rewrite.hint])
		return true)
	await _choose_fix(Shell.t(sc.rewrite.prompt), sc.rewrite.options, func(o: Dictionary) -> void:
		fix.first = false
		g.lose(cost)
		await g.say([o.wrong]))
	g.set_hint()
	g.mark("W", sc.id + ".fix", fix.first)
	var good := ""
	for o in sc.rewrite.options:
		if o.get("correct", false):
			good = o.text
	for c in trow.get_children():
		trow.remove_child(c)
		c.queue_free()
	trow.add_child(UI.vbox([UI.rich("[color=#c2271c][s]%s[/s][/color]" % target.text, 16, UI.type), UI.label(good, 21, UI.hand, UI.BLUE)], 4))
	g.sfx("pen")
	g.ensure_visible(trow)
	for wd in sc.get("words", []):
		g.word(wd)
	await g.wait(0.8)
	await g.play(sc.outro)


# ───────────────────────── forgery: grammar ─────────────────────────

func forgery(sc: Dictionary) -> void:
	await g.play(sc.intro)
	var cost := int(g.data.mistakeCost)
	var L: Dictionary = sc.letter
	var errors: Array = []
	var rows := {}
	var paras: Array = []
	var st := {"busy": false, "alarms": 0, "found": [], "miss": {}}
	var done := Main.Wait.new()
	var kids: Array = []
	for line in L.from:
		var fl := UI.label(line, 16, UI.serif, UI.SOFT)
		fl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		kids.append(fl)
	kids.append(UI.gap(4))
	kids.append(UI.label(L.greeting, 20))
	var search := func() -> void:
		# the tray is rebuilt each time, so the counter is a fresh label
		g.set_tray([_center(UI.label(Shell.t("Tap a sentence Mira would never write.\nMistakes found: %d of %d") % [st.found.size(), errors.size()], 17, UI.type_b))])
		g.set_hint(func() -> bool:
			for i in L.paragraphs.size():
				for s in L.paragraphs[i]:
					if s.has("error") and not st.found.has(s.id):
						_flash_section(paras[i])
						await g.say([sc.hint])
						return true
			return false)
	for para in L.paragraphs:
		var box := UI.vbox([], 0)
		for s in para:
			if s.has("error"):
				errors.append(s)
			var lab := UI.label(s.text, 20)
			var row := UI.panel(UI.box(Color(UI.YELLOW, 0.0), 6, 3), [lab])
			row.custom_minimum_size = Vector2(0, 46)
			rows[s.id] = row
			box.add_child(row)
			UI.tappable(row, "sent-" + s.id, func() -> void:
				if st.busy or row.has_meta("settled"):
					return
				st.busy = true
				if not s.has("error"):
					st.alarms += 1
					row.set_meta("settled", true)
					lab.add_theme_color_override("font_color", UI.SOFT)
					PenMark.draw_on(row, "tick", UI.BLUE)
					g.sfx("pen")
					g.lose(cost)
					await g.say([s.get("fine", sc.fineGeneric[0])])
					st.busy = false
					return
				_tint(row, UI.YELLOW)
				g.sfx("pen")
				g.set_hint(func() -> bool:
					await g.say([sc.fixHint])
					return true)
				var fixed: bool = await _choose_fix(Shell.t(sc.fixPrompt), s.error.options, func(o: Dictionary) -> void:
					st.miss[s.id] = true
					g.lose(cost)
					await g.say([o.wrong]), true)
				if fixed:
					st.found.append(s.id)
					row.set_meta("settled", true)
					_tint(row, UI.RED_SOFT)
					var parts: PackedStringArray = str(s.text).split(s.error.bad, true, 1)
					var bbcode := "%s[color=#c2271c][s]%s[/s][/color] [font=%s][color=#23447c]%s[/color][/font]%s" % [parts[0], s.error.bad, HAND_FONT, s.error.good, parts[1] if parts.size() > 1 else ""]
					row.remove_child(lab)
					lab.queue_free()
					row.add_child(UI.rich(bbcode, 20))
					g.sfx("pen")
					g.shake(0.15)
					g.word(s.error.word)
				else:
					_tint(row, Color(UI.YELLOW, 0.0))
				st.busy = false
				if st.found.size() == errors.size():
					done.done.emit(true)
				else:
					search.call())
		var wrap := UI.panel(UI.box(Color(UI.YELLOW, 0.0), 2, 3), [box])
		paras.append(wrap)
		kids.append(wrap)
	kids.append(UI.gap(6))
	kids.append(UI.label(L.close, 20))
	kids.append(UI.label(L.signature, 34, UI.hand, UI.BLUE))
	g.set_work([UI.paper(kids, 20)])
	search.call()
	await done.done
	g.set_hint()
	g.set_tray([])
	# Each false alarm spoils one "find"; each wrong correction spoils that "fix".
	for i in errors.size():
		g.mark("W", "%s.find%d" % [sc.id, i], i >= st.alarms)
		g.mark("W", "%s.fix.%s" % [sc.id, errors[i].id], not st.miss.has(errors[i].id))
	await g.stamp(sc.stamp, "red")
	await g.play(sc.outro)


# ───────────────────────── torn note: linking words ─────────────────────────

func torn(sc: Dictionary) -> void:
	await g.play(sc.intro)
	var cost := int(g.data.mistakeCost)
	var strips := {}
	var labels := {}
	var st := {"solved": {}, "missed": {}, "struck": {}, "busy": false}
	var done := Main.Wait.new()
	var cap := func(s: String) -> String: return s.substr(0, 1).to_upper() + s.substr(1)
	var text_of := func(p: Dictionary, word: String) -> String:
		var mid := "[color=#c2271c][b]%s[/b][/color]" % word
		return "%s%s%s%s" % [p.before + " " if p.before != "" else "", mid, ", " if p.get("comma", false) else " ", p.after]
	var strip_style := func() -> StyleBoxFlat: return UI.box(Color("f5ead0"), 14, 2, 3, Color("f5ead0"), 6)
	var kids: Array = [UI.panel(strip_style.call(), [UI.label(sc.opening, 21, UI.hand)])]
	var fn := {}   # filled in below; lambdas capture locals by value, so late-bound calls go through this
	var fill := func(p: Dictionary, o: String) -> void:
		st.solved[p.id] = true
		labels[p.id].text = text_of.call(p, cap.call(o) if p.get("capital", false) else o)
		var strip: PanelContainer = strips[p.id]
		strip.get_theme_stylebox("panel").border_color = Color("f5ead0")
		PenMark.draw_on(strip, "tape")
		var tw := strip.create_tween().set_parallel(true)
		tw.tween_property(strip, "rotation", 0.0, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(strip, "scale", Vector2.ONE, 0.3).from(Vector2(1.04, 1.04))
		g.sfx("tape")
		g.shake(0.12)
		g.word(p.word)
		for q in sc.pieces:
			if not st.solved.has(q.id):
				fn.select.call(q)
				g.ensure_visible(strips[q.id])
				return
		g.set_tray([])
		g.set_hint()
		done.done.emit(true)
	fn.select = func(p: Dictionary) -> void:
		if st.solved.has(p.id):
			return
		for q in sc.pieces:
			if not st.solved.has(q.id):
				strips[q.id].get_theme_stylebox("panel").border_color = UI.RED if q.id == p.id else Color("f5ead0")
		var row := UI.hbox([], 8)
		for i in p.options.size():
			var o: String = p.options[i]
			var b := UI.button(cap.call(o) if p.get("capital", false) else o, "paper", "link-%d" % i)
			b.add_theme_font_override("font", UI.hand_b)
			b.add_theme_font_size_override("font_size", 21)
			if st.struck.get(p.id, {}).has(o):
				b.disabled = true
			b.pressed.connect(func() -> void:
				if st.busy:
					return
				if o == p.answer:
					g.feedback("right")
					fill.call(p, o)
					return
				st.busy = true
				st.missed[p.id] = true
				if not st.struck.has(p.id):
					st.struck[p.id] = {}
				st.struck[p.id][o] = true
				b.disabled = true
				g.lose(cost)
				await g.say([p.why[o]])
				st.busy = false)
			row.add_child(b)
		g.set_tray([_center(UI.label(Shell.t("Which word mends this piece?"), 16, UI.type, UI.SOFT)), row])
		g.set_hint(func() -> bool:
			g.ensure_visible(strips[p.id])
			await g.say([p.hint])
			return true)
	for i in sc.pieces.size():
		var p: Dictionary = sc.pieces[i]
		var lab := UI.rich(text_of.call(p, "______"), 21, UI.hand)
		labels[p.id] = lab
		var strip := UI.panel(strip_style.call(), [lab])
		strip.rotation = [-0.022, 0.018, -0.01][i % 3]
		strips[p.id] = strip
		UI.tappable(strip, "strip-" + p.id, func() -> void: fn.select.call(p))
		kids.append(strip)
	kids.append(UI.panel(strip_style.call(), [UI.label(sc.closing, 21, UI.hand)]))
	g.set_work(kids)
	await g.get_tree().process_frame
	for id in strips:
		strips[id].pivot_offset = strips[id].size * 0.5
	fn.select.call(sc.pieces[0])
	await done.done
	for p in sc.pieces:
		g.mark("W", sc.id + "." + p.id, not st.missed.has(p.id))
	await g.stamp("PLAN REVEALED", "red")
	g.set_work([])
	g.set_scene_full(true)
	await g.play(sc.outro)
	# Finding Mira is quick only if we have the number of the car.
	if g.has_card("receipt"):
		await g.play(sc.get("outroReceipt", []))
	else:
		await g.play(sc.get("outroNoReceipt", []))
	g.state.found_at = g.now()
	g.save()
	g.sfx("sting")
	await g.play(sc.get("outroAfter", []))


# ───────────────────────── scan: find the line that answers the question ─────────────────────────

func scan(sc: Dictionary) -> void:
	var who: String = sc.get("actor", "")
	if who != "":
		g.show_actor(who, "neutral", "right")
	await g.play(sc.intro)
	var cost := int(g.data.mistakeCost)
	var st := {"armed": Callable()}
	var doc := _line_doc(sc.doc, func(id: String) -> void:
		if st.armed.is_valid():
			st.armed.call(id))
	var q_text := UI.label("", 21, UI.serif)
	var qs := UI.box(UI.PAPER, 12, 10, 0, UI.INK, 5)
	qs.border_width_left = 7
	var q_tag := UI.tag("", UI.SOFT, 13)
	g.set_head([UI.panel(qs, [UI.vbox([q_tag, q_text], 2)])])
	g.set_work([doc.paper])
	g.set_tray([_center(UI.label(Shell.t("Tap the line that answers Sam’s question."), 17, UI.type_b))])
	for n in sc.questions.size():
		var q: Dictionary = sc.questions[n]
		q_tag.text = (Shell.t("Sam asks   %d of %d") % [n + 1, sc.questions.size()]).to_upper()
		q_text.text = q.text
		g.set_hint(func() -> bool:
			await g.say([q.hint])
			return true)
		var first := true
		while true:
			var w := Main.Wait.new()
			st.armed = func(id: String) -> void: w.done.emit(id)
			var id: String = await w.done
			st.armed = Callable()
			if q.answer.has(id):
				g.mark("R", "%s.%s" % [sc.id, q.id], first)
				_tint(doc.lines[id], UI.BLUE_SOFT)
				PenMark.draw_on(doc.lines[id], "underline", UI.BLUE)
				g.sfx("pen")
				g.feedback("right")
				await g.stamp("FOUND", "ink")
				if who != "":
					g.react(who, "nod")
				await g.say(q.right)
				g.word(q.get("word"))
				break
			first = false
			g.lose(cost)
			await g.say([q.wrong])
	g.set_hint()
	g.set_head([])
	g.set_tray([])
	g.set_work([])
	g.set_scene_full(true)
	await g.play(sc.outro)


# ───────────────────────── the evidence board: deductions ─────────────────────────

func _made(d: Dictionary) -> bool:
	return g.state.deductions.has(d.get("same", d.id)) or g.state.deductions.has(d.id)


func board() -> void:
	current = "board"
	var bd: Dictionary = g.data.board
	await g.transition(bd)
	g.show_actor("sam")
	await g.say(bd.intro)
	var done := Main.Wait.new()
	var st := {"sel": [], "busy": false, "wrongs": 0}
	var cards := {}
	var ded_box := UI.vbox([], 8)
	var count := UI.tag("", UI.INK, 13)
	var connect := UI.button(Shell.t("Tap two cards to connect them"), "primary", "connect")
	connect.disabled = true
	var finish := UI.button(Shell.t(bd.done), "danger", "board-done")
	var refresh := func() -> void:
		count.text = Shell.t("DEDUCTIONS MADE: %d") % g.state.deductions.size()
		connect.disabled = st.sel.size() != 2
		connect.text = Shell.t("Connect these two cards") if st.sel.size() == 2 else Shell.t("Tap two cards to connect them")
	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 12)
	for eid in g.state.evidence:
		var e: Dictionary = g.card(eid)
		var c := evidence_card(e)
		cards[eid] = c
		grid.add_child(c)
		UI.tappable(c, "card-" + eid, func() -> void:
			if st.busy:
				return
			if st.sel.has(eid):
				st.sel.erase(eid)
				_select(c, false)
			elif st.sel.size() < 2:
				st.sel.append(eid)
				_select(c, true)
				g.sfx("pin")
			else:
				g.toast(Shell.t("Two cards at a time. Tap one to put it back."), "")
			refresh.call())
	for did in g.state.deductions:
		ded_box.add_child(deduction_card(deduction(did)))
	connect.pressed.connect(func() -> void:
		if st.busy or st.sel.size() != 2:
			return
		st.busy = true
		var a: String = st.sel[0]
		var b: String = st.sel[1]
		var found := {}
		for d in bd.deductions:
			if d.cards.has(a) and d.cards.has(b):
				found = d
		# red string between the two cards
		var line := Line2D.new()
		line.width = 4.0
		line.default_color = UI.RED
		var pa: Vector2 = cards[a].get_global_rect().get_center() - g.overlay.global_position
		var pb: Vector2 = cards[b].get_global_rect().get_center() - g.overlay.global_position
		line.points = PackedVector2Array([pa, pa])
		g.overlay.add_child(line)
		g.sfx("tape")
		var tw := g.create_tween()
		tw.tween_method(func(t: float) -> void: line.set_point_position(1, pa.lerp(pb, t)), 0.0, 1.0, 0.3)
		await tw.finished
		if found.is_empty():
			st.wrongs += 1
			g.sfx("snap")
			for id in [a, b]:
				var c: Control = cards[id]
				var sh := c.create_tween()
				for k in 4:
					sh.tween_property(c, "position:x", c.position.x + (6.0 if k % 2 == 0 else -6.0), 0.04)
				sh.tween_property(c, "position:x", c.position.x, 0.04)
			g.lose(int(g.data.mistakeCost))
			var snap := g.create_tween()
			snap.tween_property(line, "modulate:a", 0.0, 0.25)
			snap.tween_callback(line.queue_free)
			await g.say([bd.wrong[(st.wrongs - 1) % bd.wrong.size()]])
		elif _made(found):
			line.queue_free()
			await g.say([bd.again])
		else:
			g.state.deductions.append(found.get("same", found.id))
			g.save()
			# the pair is drawn together along the string, then the conclusion lands
			g.sfx("deduce")
			line.width = 7.0
			for id in [a, b]:
				var c: Control = cards[id]
				var toward: Vector2 = ((pa + pb) * 0.5 - (c.get_global_rect().get_center() - g.overlay.global_position)) * 0.18
				var pull := c.create_tween()
				pull.tween_property(c, "position", c.position + toward, 0.16).set_ease(Tween.EASE_OUT)
				pull.tween_property(c, "position", c.position, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			await g.wait(0.18)
			await g.stamp("DEDUCTION", "red" if found.get("strong", false) else "ink")
			line.queue_free()
			var dc := deduction_card(found)
			ded_box.add_child(dc)
			dc.modulate.a = 0.0
			dc.pivot_offset = Vector2(160, 40)
			dc.scale = Vector2(1.15, 1.15)
			var drop := dc.create_tween().set_parallel(true)
			drop.tween_property(dc, "modulate:a", 1.0, 0.18)
			drop.tween_property(dc, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			g.sfx("pin")
			await g.say([found.sam])
			g.ensure_visible(dc)
		for id in st.sel:
			_select(cards[id], false)
		st.sel.clear()
		st.busy = false
		refresh.call())
	finish.pressed.connect(func() -> void:
		if not st.busy:
			done.done.emit(true))
	g.set_head([UI.panel(UI.box(Color(UI.PAPER, 0.95), 8, 3, 0), [count])])
	g.set_work([grid, ded_box])
	g.set_tray([connect, finish])
	g.set_hint(func() -> bool:
		await g.say([bd.hint])
		return true)
	refresh.call()
	while true:
		await done.done
		var n: int = g.state.deductions.size()
		if await g.confirm(Shell.t("Make the accusation?"), (Shell.t("You have made %d deductions. You can’t come back to the board.") % n) if Shell.active else ("You have made %d deduction%s. You can’t come back to the board." % [n, "" if n == 1 else "s"]), Shell.t("Accuse"), Shell.t("Keep working")):
			break
	g.set_hint()
	g.set_head([])
	g.set_tray([])
	g.set_work([])


# ───────────────────────── accusation and endings ─────────────────────────

func accusation() -> void:
	current = "accusation"
	var sc: Dictionary = g.data.accusation
	await g.transition(sc)
	g.show_actor("sam")
	await g.play(sc.intro)
	var st := {"suspect": null, "proofs": [], "need": 3}
	var go := UI.button(Shell.t("Choose a suspect"), "danger", "arrest")
	go.disabled = true
	var sus_cards := {}
	var refresh := func() -> void:
		go.disabled = st.suspect == null or st.proofs.size() != st.need
		if st.suspect == null:
			go.text = Shell.t("Choose a suspect")
		elif st.proofs.size() < st.need:
			go.text = Shell.t("Choose %d more") % (st.need - st.proofs.size())
		else:
			go.text = Shell.t("Arrest %s") % st.suspect.name
	var sus_row := UI.hbox([], 8)
	for s in sc.suspects:
		var face := UI.image("res://assets/characters/%s_neutral.png" % s.id, Vector2(0, 96))
		# the suspects are printed photographs: a dark studio ground inside a cream border
		var img := UI.panel(UI.box(Color("2a1c13"), 0, 1, 4, Color("f4ead4"), 4), [face])
		var nm := UI.label(s.name, 17, UI.serif_b)
		nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var role := _center(UI.tag(s.role, UI.SOFT, 10))
		var line := UI.label(s.line, 13, UI.serif, UI.SOFT)
		line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var c := UI.panel(UI.box(UI.PAPER, 8, 4, 3, Color(UI.PAPER, 1.0), 6), [UI.vbox([img, nm, role, line], 2)])
		sus_cards[s.id] = c
		sus_row.add_child(c)
		UI.tappable(c, "suspect-" + s.id, func() -> void:
			st.suspect = s
			for id in sus_cards:
				_select(sus_cards[id], id == s.id)
			g.sfx("pin")
			refresh.call())
	var proofs: Array = []   # {kind, id, strong, title, weak}
	for did in g.state.deductions:
		var d := deduction(did)
		proofs.append({"key": "d-" + did, "strong": d.get("strong", false), "title": d.title, "node": deduction_card(d), "weak": g.fmt(sc.weakClear, {"title": d.title})})
	for eid in g.state.evidence:
		var e: Dictionary = g.card(eid)
		proofs.append({"key": "e-" + eid, "strong": false, "title": e.title, "node": evidence_card(e), "weak": e.get("weak", g.fmt(sc.weakCard, {"title": e.title}))})
	st.need = min(3, proofs.size())
	var list := UI.vbox([], 10)
	for p in proofs:
		list.add_child(p.node)
		UI.tappable(p.node, "proof-" + p.key, func() -> void:
			if st.proofs.has(p):
				st.proofs.erase(p)
				_select(p.node, false, UI.INK)
			elif st.proofs.size() < st.need:
				st.proofs.append(p)
				_select(p.node, true, UI.INK)
				g.sfx("pin")
			else:
				g.toast(Shell.t("Three proofs only. Tap one to put it back."), "")
			refresh.call())
	var h1 := UI.panel(UI.box(UI.PAPER, 8, 2), [UI.tag(Shell.t("Who did it?"), UI.INK, 15)])
	var h2 := UI.panel(UI.box(UI.PAPER, 8, 2), [UI.vbox([UI.tag(Shell.t("Which three prove it?"), UI.INK, 15), UI.label(Shell.t(sc.proofNote), 16, UI.serif_i, UI.SOFT)], 2)])
	g.set_work([h1, sus_row, h2, list])
	g.set_tray([go])
	g.set_hint(func() -> bool:
		await g.say([sc.hint])
		return true)
	refresh.call()
	await go.pressed
	g.set_hint()
	g.set_tray([])

	var strong := 0
	for p in st.proofs:
		if p.strong:
			strong += 1
	var verdict := "R"
	if st.suspect.id == sc.culprit:
		verdict = "C" if strong >= 3 else "W"
	var found: int = int(g.state.found_at)
	var tier := "never"
	if found >= 0:
		tier = "early" if found <= g.to_min(g.data.clock.comfortable) else ("close" if found <= g.deadline() else "late")
	var keys: Array = []
	for p in st.proofs:
		keys.append(p.key)
	g.state.ending = {"verdict": verdict, "suspect": st.suspect.id, "proofs": keys, "tier": tier}
	g.save()

	# the arrest, played out in the hall
	g.set_work([])
	g.set_scene_full(true)
	var arrested: String = st.suspect.id
	g.show_actor(arrested, "cracked" if verdict == "C" else ("smug" if verdict == "W" else "nervous"), "right")
	g.sfx("sting")
	await g.wait(0.5)
	g.react(arrested, "slump" if verdict == "C" else ("hop" if verdict == "W" else "flinch"))
	await g.stamp(sc.verdictStamps[verdict], "red" if verdict == "C" else "ink")
	var end: Dictionary = sc.endings.R[arrested] if verdict == "R" else sc.endings[verdict]
	var time_line: String = g.fmt(sc.timeLines[tier], {"late": found - g.deadline()})
	g.set_work([render_doc({"kind": "newspaper", "paper": sc.paper, "headline": end.headline, "sub": end.sub, "body": end.body + [time_line]})])
	g.moods["sam"] = "pleased" if verdict == "C" else "annoyed"
	await g.proceed("Put the paper down")
	g.set_work([])
	g.set_scene_full(true)
	var lines: Array = []
	for l in end.sam:
		if l == "{weak}":
			var shown := 0
			for p in st.proofs:
				if not p.strong and shown < 2:
					lines.append(p.weak)
					shown += 1
		else:
			lines.append(l)
	g.set_mood("sam", "pleased" if verdict == "C" else "annoyed")
	await g.say(lines)
	await g.proceed("See the case report")


# ───────────────────────── case report ─────────────────────────

func report() -> void:
	current = "report"
	var sc: Dictionary = g.data.report
	var end: Dictionary = g.state.ending if g.state.ending is Dictionary else {"verdict": "R"}
	g.set_hint()
	g.clear_actors()
	g.set_prop(null)
	g.set_head([])
	g.set_tray([])
	g.set_place("unit9", "desk")
	g.show_actor("sam", "pleased" if end.verdict == "C" else "neutral")
	var bands := {}
	for k in sc.skills:
		bands[k.key] = g.band_for(g.state.marks.get(k.key))
	var hints_used: int = int(g.data.hints) - int(g.state.hints_left)
	var mine := {"ending": end.verdict, "L": bands.L.band, "R": bands.R.band, "W": bands.W.band, "hints": hints_used, "time": int(g.state.time)}
	var code: String = g.encode_result(mine)
	var show := func(b: float) -> String: return "–" if b < 0.0 else "%.1f" % b
	var stamp_l := UI.label(Shell.t(str(sc.endingNames[end.verdict])).to_upper(), 15, UI.type_b, UI.RED if end.verdict == "C" else UI.BLUE)
	stamp_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var kids: Array = [UI.hbox([UI.tag(Shell.t("Unit 9, Case ") + g.data.number, UI.SOFT, 12), stamp_l]), UI.label(Shell.t("Case Report"), 30, UI.serif_b), UI.label(g.data.title, 19, UI.serif_i), UI.rule(UI.INK)]
	var leads_done: int = g.state.done.size()
	for pair in [[Shell.t("Case closed at"), g.clock_text_of(g.now())], [Shell.t("Leads followed"), Shell.t("%d of %d") % [leads_done, g.data.leads.size()]],
			[Shell.t("Deductions"), str(g.state.deductions.size())], [Shell.t("Hints used"), Shell.t("%d of %d") % [hints_used, int(g.data.hints)]]]:
		var k2 := UI.tag(pair[0], UI.SOFT, 12)
		k2.custom_minimum_size = Vector2(150, 0)
		k2.size_flags_horizontal = Control.SIZE_FILL
		kids.append(UI.hbox([k2, UI.label(pair[1], 17, UI.type)], 6))
	kids.append(UI.gap(4))
	kids.append(UI.tag(Shell.t("Estimated band"), UI.RED, 13))
	var weakest: Dictionary = sc.skills[0]
	for k in sc.skills:
		var b: Dictionary = bands[k.key]
		if b.band >= 0.0 and (bands[weakest.key].band < 0.0 or b.band < bands[weakest.key].band):
			weakest = k
		var num := UI.label(show.call(b.band), 30, UI.type_b)
		num.autowrap_mode = TextServer.AUTOWRAP_OFF
		num.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		num.size_flags_horizontal = Control.SIZE_SHRINK_END
		var bar := ProgressBar.new()
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(0, 9)
		bar.value = 100.0 * b.got / b.total if b.total > 0 else 0.0
		bar.add_theme_stylebox_override("background", UI.box(UI.PAPER2, 0, 4, 1, UI.RULE))
		bar.add_theme_stylebox_override("fill", UI.box(UI.INK, 0, 4))
		kids.append(UI.hbox([UI.label(Shell.t(k.name), 21, UI.serif_b), num]))
		kids.append(bar)
		kids.append(UI.label((Shell.t("%d of %d right first time, from %s") % [b.got, b.total, Shell.t(k.from)]) if b.total > 0 else Shell.t("Not tested: you skipped these leads"), 14, UI.type, UI.SOFT))
	kids.append(UI.label(Shell.t("A rough guide from one short case, not an official score. To work on next: %s.") % Shell.t(weakest.name), 15, UI.serif_i, UI.SOFT))
	kids.append(UI.gap(4))
	kids.append(UI.tag(Shell.t("Result code"), UI.RED, 13))
	var code_l := UI.label(code, 26, UI.type_b, UI.RED)
	code_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UI.mark(code_l, "code")
	var copy := UI.button(Shell.t("Copy"), "paper", "copy")
	copy.custom_minimum_size = Vector2(96, 48)
	copy.size_flags_horizontal = Control.SIZE_SHRINK_END
	copy.pressed.connect(func() -> void:
		DisplayServer.clipboard_set(code)
		if g.web_page:
			JavaScriptBridge.get_interface("window").cfCopy(code)
		elif g.mini:
			g.sdk.set_clipboard(code)
		copy.text = Shell.t("Copied"))
	kids.append(UI.hbox([UI.panel(UI.box(UI.PAPER, 8, 8, 2, UI.RED), [code_l]), copy], 8))
	kids.append(UI.label(Shell.t("Send it to someone who played this case. Type theirs here to compare."), 15, UI.serif_i, UI.SOFT))
	g.fields.clear()
	var entry: LineEdit = g.add_field("friend", Shell.t("Friend’s result code"), true)
	var cmp := UI.button(Shell.t("Compare"), "paper", "compare")
	cmp.custom_minimum_size = Vector2(120, 48)
	cmp.size_flags_horizontal = Control.SIZE_SHRINK_END
	var out := UI.vbox([], 6)
	UI.mark(out, "compare-out")
	var col := func(r: Dictionary, who: String) -> Control:
		return UI.panel(UI.box(UI.PAPER, 8, 6, 1, UI.RULE), [UI.vbox([UI.tag(who, UI.RED, 12), UI.label(Shell.t(sc.endingNames[r.ending]), 16, UI.type_b),
			UI.label(Shell.t("L %s  R %s  W %s") % [show.call(r.L), show.call(r.R), show.call(r.W)], 15, UI.type),
			UI.label(Shell.t("Closed at ") + g.clock_text_of(g.to_min(g.data.clock.start) + int(r.time)), 15, UI.type), UI.label((Shell.t("%d hints") % int(r.hints)) if Shell.active else ("%d hint%s" % [int(r.hints), "" if int(r.hints) == 1 else "s"]), 15, UI.type)], 1)])
	cmp.pressed.connect(func() -> void:
		for c in out.get_children():
			c.queue_free()
		var r = g.decode_result(g.field_value("friend"))
		if r == null:
			out.add_child(UI.label(Shell.t("That doesn’t look like a result code. Check for a missing letter."), 15, UI.type_b, UI.RED))
		elif r.case != g.data.code + g.data.number:
			out.add_child(UI.label(Shell.t("That code is from a different case."), 15, UI.type_b, UI.RED))
		else:
			out.add_child(UI.hbox([col.call(mine, Shell.t("You")), col.call(r, Shell.t("Them"))], 8))
		g.ensure_visible(out))
	kids.append(UI.hbox([entry, cmp], 8))
	kids.append(out)
	var again := UI.button(Shell.t("Play the case again"), "primary", "play-again")
	again.pressed.connect(g.restart)
	kids.append(again)
	g.set_work([UI.paper(kids, 18)])
	var forever := Main.Wait.new()   # the report is the last screen
	await forever.done
