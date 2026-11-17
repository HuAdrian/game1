/*
 * CASE FILES — scene types and document renderers
 *
 * Each scene type is one kind of IELTS task turned into a detective action.
 * They read everything they show from the case data, so a new case reuses
 * them with new content.
 *
 *   story          dialogue + documents            (briefing, cut-scenes)
 *   wiretap        Listening Part 1: type what you hear into a form
 *   tail           Listening Part 2: follow directions on a map
 *   interrogation  Reading T/F/NG: prove each verdict by tapping a line
 *   chart          Writing Task 1: find and fix the sentence that misreads the data
 *   forgery        Grammar: find the mistakes and choose the corrections
 *   torn           Linking words: rebuild a note so its logic works
 *   accusation     Pick a suspect and three proofs; three endings
 *   report         Bands, result code, comparison
 */
(function () {
  'use strict';
  var CF = window.CaseFiles, h = CF.h, svg = CF.svg, rich = CF.rich, fmt = CF.fmt, wait = CF.wait;

  /* ═════════════ documents ═════════════ */

  CF.registerDoc('sheet', function (d) {
    return h('div', { class: 'paper sheet' },
      d.stamp ? h('span', { class: 'stamp small red' }, d.stamp) : null,
      h('p', { class: 'doc-ref' }, d.ref || ''),
      h('h2', {}, d.title),
      h('dl', {}, d.rows.map(function (r) { return [h('dt', {}, r[0]), h('dd', {}, r[1])]; })));
  });

  CF.registerDoc('receipt', function (d) {
    return h('div', { class: 'paper receipt' },
      h('h2', {}, d.shop), h('p', { class: 'r-addr' }, d.address), h('p', { class: 'r-ref' }, d.ref),
      h('div', { class: 'r-lines' }, d.lines.map(function (l) { return h('p', {}, h('span', {}, l[0]), h('b', {}, l[1])); })),
      h('p', { class: 'r-total' }, h('span', {}, d.total[0]), h('b', {}, d.total[1])),
      d.note ? h('p', { class: 'r-note' }, d.note) : null,
      h('p', { class: 'r-thanks' }, '* * * THANK YOU * * *'));
  });

  CF.registerDoc('newspaper', function (d) {
    return h('div', { class: 'paper newspaper' },
      h('p', { class: 'np-name' }, d.paper),
      h('p', { class: 'np-rule' }, d.edition || 'Late edition'),
      h('h2', {}, d.headline), h('p', { class: 'np-sub' }, d.sub),
      h('div', { class: 'np-body' }, d.body.map(function (p) { return h('p', {}, p); })));
  });

  /* ═════════════ shared: the tape player ═════════════ */

  function makeTape(label, who) {
    var bar = h('div', { class: 'tape-bar' }, h('i'));
    var status = h('span', { class: 'tape-status' }, 'Plays once only');
    var el = h('div', { class: 'tape' },
      h('div', { class: 'reels', 'aria-hidden': 'true' }, h('i'), h('i')),
      h('div', { class: 'tape-info' }, h('b', {}, label), h('small', {}, who || ''), bar, status));
    return {
      el: el,
      status: function (t) { status.textContent = t; },
      progress: function (i, n) { bar.firstChild.style.width = Math.round(((i + 1) / n) * 100) + '%'; },
      playing: function (on) { el.classList.toggle('playing', on); }
    };
  }

  /** Plays a script through the tape. If the device has no voice, shows the transcript to read once. */
  async function playTape(ctx, tape, lines, voice) {
    tape.playing(true); tape.status('Playing…');
    var ok = await ctx.speech.play(lines, Object.assign({}, voice, { onLine: function (i) { tape.progress(i, lines.length); } }));
    tape.playing(false);
    if (!ok) {
      tape.status('No voice on this device');
      await new Promise(function (resolve) {
        var box = h('div', { class: 'transcript' },
          h('p', { class: 'transcript-note' }, 'This device has no speech voice, so here is the transcript instead. Read it once, then put it away.'),
          lines.map(function (l) { return h('p', {}, l); }),
          h('button', { class: 'btn', onclick: function () { box.remove(); resolve(); } }, 'I’ve read it. Put it away'));
        var stage = document.getElementById('stage'); stage.insertBefore(box, stage.firstChild); stage.scrollTop = 0;
      });
    }
    tape.progress(lines.length - 1, lines.length);
    tape.status('Tape finished');
    return ok;
  }

  /** Replays a few lines as a hint (audio, or as quoted text when there is no voice). */
  async function replay(ctx, speakerId, lines, lead) {
    var who = ctx.case.cast[speakerId] || {};
    if (lead) await ctx.say([lead]);
    var ok = await ctx.speech.play(lines, who.voice || {});
    if (!ok) await ctx.say(lines.map(function (l) { return '@' + speakerId + ' ' + l; }));
    return true;
  }

  /* ═════════════ story ═════════════ */

  CF.registerScene('story', async function (sc, ctx) {
    await ctx.titleCard(sc);
    await ctx.play(sc.beats);
  });

  /* ═════════════ wiretap: Listening Part 1 ═════════════ */

  function norm(s) {
    return String(s || '').toLowerCase().replace(/[,;!]/g, ' ').replace(/\s+/g, ' ').trim().replace(/\.$/, '');
  }
  function fieldRight(f, value) {
    var n = norm(value);
    if (f.kind === 'time') n = n.replace(/^at /, '').replace(/\s*p\.?\s?m\.?$/, '').trim();
    (f.strip || []).forEach(function (p) { if (n.indexOf(p) === 0) n = n.slice(p.length).trim(); });
    return f.accept.indexOf(n) >= 0;
  }

  CF.registerScene('wiretap', async function (sc, ctx) {
    await ctx.titleCard(sc);
    CF.Sound.play('ring');
    await ctx.play(sc.intro);
    var cast = ctx.case.cast, fields = sc.form.fields, values = {}, right = {};

    /** One listening round: play once, fill the open fields, submit. */
    function round(roundId, speakerId, script, lineMap, open) {
      var who = cast[speakerId], playedKey = sc.id + '.' + roundId + '.played';
      var tape = makeTape(roundId === 'first' ? 'Voicemail' : 'Phone call', who.name + ' · ' + who.role);
      var inputs = {}, lastFocus = null, played = !!ctx.flag(playedKey);

      var page = h('div', { class: 'paper notebook-page' },
        h('h2', {}, sc.form.title), h('p', { class: 'doc-ref' }, sc.form.sub),
        sc.form.given.map(function (g) { return h('div', { class: 'field given' }, h('label', {}, g[0]), h('span', { class: 'hand' }, g[1])); }),
        fields.map(function (f) {
          var isOpen = open.indexOf(f.id) >= 0;
          var input = h('input', {
            type: 'text', id: 'f-' + f.id, value: isOpen ? '' : values[f.id] || '', disabled: !isOpen,
            autocomplete: 'off', autocapitalize: 'off', autocorrect: 'off', spellcheck: 'false', enterkeyhint: 'next',
            'aria-label': f.label, onfocus: function () { lastFocus = f.id; }, oninput: function () { CF.Sound.play('key'); }
          });
          inputs[f.id] = input;
          return h('div', { class: 'field' + (isOpen ? '' : ' locked'), id: 'row-' + f.id },
            h('label', { for: 'f-' + f.id }, f.label), f.prefix ? h('span', { class: 'hand prefix' }, f.prefix) : null, input,
            h('span', { class: 'mark' }, isOpen ? '' : '✓'));
        }));

      var playBtn = ctx.button(played ? 'Played' : '▶ Play', 'tape-play', async function () {
        if (played) return;
        played = true; ctx.flag(playedKey, true);
        playBtn.disabled = true; playBtn.textContent = 'Listening…';
        CF.Sound.play('clunk');
        await playTape(ctx, tape, script, who.voice);
        CF.Sound.play('clunk');
        playBtn.textContent = 'Played'; submit.disabled = false; armHint();
      });
      playBtn.disabled = played;
      var submit = ctx.button('Hand notes to Sam', 'primary');
      submit.disabled = !played;
      if (played) tape.status('Tape finished');

      tape.el.appendChild(playBtn);
      ctx.setProp(tape.el);
      ctx.setStage(page);
      ctx.setTray(submit);

      function armHint() {
        ctx.setHint(async function () {
          var empty = open.filter(function (id) { return !inputs[id].value.trim(); });
          var target = open.indexOf(lastFocus) >= 0 ? lastFocus : (empty[0] || open[0]);
          var label = fields.filter(function (f) { return f.id === target; })[0].label;
          await replay(ctx, speakerId, lineMap[target].map(function (i) { return script[i]; }),
            sc.hintLine + ' This is the bit about “' + label + '”.');
          return true;
        });
      }
      if (played) armHint(); else ctx.setHint(null, 'Play the tape first. Sam can’t wind back what you haven’t heard.');

      return new Promise(function (resolve) {
        submit.onclick = async function () {
          ctx.setHint(null); ctx.setTray();
          var wrong = [];
          open.forEach(function (id) {
            var f = fields.filter(function (x) { return x.id === id; })[0];
            values[id] = inputs[id].value.trim();
            right[id] = fieldRight(f, values[id]);
            inputs[id].disabled = true;
            var row = document.getElementById('row-' + id);
            row.classList.add(right[id] ? 'ok' : 'bad');
            row.querySelector('.mark').textContent = right[id] ? '✓' : '✗';
            if (!right[id]) wrong.push(f);
          });
          CF.Sound.play(wrong.length ? 'pen' : 'good');
          await wait(900);
          resolve(wrong);
        };
      });
    }

    var firstMap = {};
    fields.forEach(function (f) { firstMap[f.id] = f.lines; });
    var wrong = await round('first', sc.speaker, sc.script, firstMap, fields.map(function (f) { return f.id; }));
    fields.forEach(function (f) { ctx.mark('L', sc.id + '.' + f.id, right[f.id]); });

    if (!wrong.length) {
      await ctx.play(sc.success);
    } else {
      // The lead goes cold: the same facts must be won again from a harder call.
      await ctx.say([sc.coldIntro].concat(wrong.map(function (f) { return fmt(f.cold, { value: values[f.id] || 'nothing at all' }); })));
      ctx.lose(sc.coldCost);
      await ctx.play(sc.cold);
      var still = await round('retry', sc.retry.speaker, sc.retry.script, sc.retry.lines, wrong.map(function (f) { return f.id; }));
      if (still.length) {
        ctx.lose(sc.retry.failCost);
        still.forEach(function (f) {
          var input = document.getElementById('f-' + f.id);
          input.value = f.answer; var row = document.getElementById('row-' + f.id); row.className = 'field fixed'; row.querySelector('.mark').textContent = '';
        });
        await ctx.play(sc.retry.fail);
      } else {
        await ctx.play(sc.retry.success);
      }
    }
    await ctx.play(sc.outro);
  });

  /* ═════════════ tail: Listening Part 2 ═════════════ */

  function drawMap(m, onPick) {
    var root = svg('svg', { class: 'map', viewBox: '0 0 ' + m.w + ' ' + m.h, role: 'group', 'aria-label': 'Street map' });
    root.appendChild(svg('rect', { class: 'map-ground', x: 0, y: 0, width: m.w, height: m.h }));
    m.roads.forEach(function (r) { root.appendChild(svg('rect', { class: 'map-road', x: r.x, y: r.y, width: r.w, height: r.h })); });
    m.labels.forEach(function (l) {
      root.appendChild(svg('text', {
        class: 'map-street', x: l.x, y: l.y, 'text-anchor': l.anchor || 'start',
        transform: l.rot ? 'rotate(' + l.rot + ' ' + l.x + ' ' + l.y + ')' : null, dy: l.rot ? 4 : 0
      }, l.text));
    });
    var nodes = {};
    m.blocks.forEach(function (b) {
      var cx = b.x + b.w / 2, cy = b.y + b.h / 2;
      var g = svg('g', { class: 'map-block ' + (b.id ? 'pick' : 'named') + (b.kind ? ' ' + b.kind : '') });
      g.appendChild(svg('rect', { x: b.x + 2, y: b.y + 2, width: b.w - 4, height: b.h - 4, rx: 3 }));
      if (b.id) {
        g.appendChild(svg('circle', { cx: cx, cy: cy, r: 15 }));
        g.appendChild(svg('text', { class: 'map-letter', x: cx, y: cy + 6, 'text-anchor': 'middle' }, b.id));
        g.setAttribute('role', 'button'); g.setAttribute('tabindex', '0'); g.setAttribute('aria-label', 'Building ' + b.id);
        g.addEventListener('click', function () { onPick(b); });
        nodes[b.id] = g;
      } else {
        b.name.forEach(function (line, i) {
          g.appendChild(svg('text', { class: 'map-name', x: cx, y: cy + 4 + (i - (b.name.length - 1) / 2) * 13, 'text-anchor': 'middle' }, line));
        });
      }
      root.appendChild(g);
    });
    (m.marks || []).forEach(function (k) {
      var g = svg('g', { class: 'map-mark ' + k.type });
      if (k.type === 'bus') {
        g.appendChild(svg('rect', { x: k.x - 26, y: k.y - 8, width: 52, height: 15, rx: 7 }));
        g.appendChild(svg('text', { x: k.x, y: k.y + 3, 'text-anchor': 'middle' }, k.text));
      } else {
        g.appendChild(svg('path', { d: 'M' + (k.x - 7) + ' ' + (k.y + 2) + 'h14l-7 -9z' }));
        g.appendChild(svg('text', { x: k.x, y: k.y + 15, 'text-anchor': 'middle' }, k.text));
      }
      root.appendChild(g);
    });
    // A walker the player moves from junction to junction, leaving a trail, the way
    // a candidate traces the route with a pencil. It never moves by itself.
    var reset = function () {};
    if (m.nodes) {
      var pos, path, trail = svg('polyline', { class: 'map-trail' });
      var walker = svg('g', { class: 'map-walker' }, svg('circle', { class: 'ring', r: 10 }), svg('circle', { class: 'core', r: 5.5 }));
      var draw = function () {
        walker.style.transform = 'translate(' + pos[0] + 'px,' + pos[1] + 'px)';
        trail.setAttribute('points', path.map(function (q) { return q.join(','); }).join(' '));
      };
      reset = function () { pos = m.nodes[m.start]; path = [pos]; draw(); };
      root.appendChild(trail);
      m.nodes.forEach(function (nd) {
        var g = svg('g', { class: 'map-node', role: 'button', 'aria-label': 'Walk to this corner' },
          svg('circle', { class: 'hit', cx: nd[0], cy: nd[1], r: 15 }), svg('circle', { class: 'dot', cx: nd[0], cy: nd[1], r: 3.4 }));
        g.addEventListener('click', function () {
          if (nd === pos) return;
          if (nd[0] !== pos[0] && nd[1] !== pos[1]) { // not along one street
            g.classList.add('no'); setTimeout(function () { g.classList.remove('no'); }, 350);
            return;
          }
          pos = nd; path.push(nd); draw(); CF.Sound.play('step');
        });
        root.appendChild(g);
      });
      root.appendChild(walker);
      reset();
    }
    return { el: root, nodes: nodes, reset: reset };
  }

  CF.registerScene('tail', async function (sc, ctx) {
    await ctx.titleCard(sc);
    await ctx.play(sc.intro);
    var who = ctx.case.cast[sc.speaker], tried = [];

    function round(roundId, script, hintLines) {
      var playedKey = sc.id + '.' + roundId + '.played', played = !!ctx.flag(playedKey), picked = null;
      var tape = makeTape('Police radio', who.name + ' · ' + who.role);
      var map = drawMap(sc.map, function (b) {
        if (tried.indexOf(b.id) >= 0) return;
        picked = b;
        Object.keys(map.nodes).forEach(function (id) { map.nodes[id].classList.toggle('sel', id === b.id); });
        CF.Sound.play('pin');
        go.textContent = 'Send the team to building ' + b.id;
        go.disabled = !played;
      });
      tried.forEach(function (id) { map.nodes[id].classList.add('dead'); });
      var playBtn = ctx.button(played ? 'Played' : '▶ Play', 'tape-play', async function () {
        if (played) return;
        played = true; ctx.flag(playedKey, true);
        playBtn.disabled = true; playBtn.textContent = 'Listening…';
        CF.Sound.play('static');
        await playTape(ctx, tape, script, who.voice);
        CF.Sound.play('static');
        playBtn.textContent = 'Played'; armHint();
        if (picked) go.disabled = false;
      });
      playBtn.disabled = played;
      if (played) tape.status('Tape finished');
      var go = ctx.button('Tap a building on the map', 'primary');
      go.disabled = true;
      tape.el.appendChild(playBtn);
      ctx.setProp(tape.el);
      ctx.setStage(h('div', { class: 'paper map-paper' }, map.el,
        sc.map.nodes ? h('div', { class: 'map-help' }, h('span', {}, 'Tap the corners to walk the marker along his route.'),
          ctx.button('Back to the hall', 'ghost small', function () { map.reset(); })) : null));
      ctx.setTray(go);
      function armHint() {
        ctx.setHint(async function () {
          await replay(ctx, sc.speaker, hintLines.map(function (i) { return script[i]; }), sc.hintLine);
          return true;
        });
      }
      if (played) armHint(); else ctx.setHint(null, 'Play the radio first. Then Sam can help.');
      return new Promise(function (resolve) {
        go.onclick = function () { ctx.setHint(null); ctx.setTray(); resolve(picked); };
      });
    }

    var pick = await round('first', sc.script, sc.hintLines);
    var ok = pick.id === sc.answer;
    ctx.mark('L', sc.id, ok, 2);
    if (!ok) {
      tried.push(pick.id);
      ctx.lose(sc.wrongCost);
      await ctx.say(sc.wrong, { id: pick.id, what: pick.what });
      await ctx.play(sc.retry.intro);
      pick = await round('retry', sc.retry.script, sc.retry.hintLines);
      if (pick.id !== sc.answer) {
        ctx.lose(sc.retry.wrongCost);
        await ctx.say(sc.retry.wrong);
      }
    }
    await ctx.stamp('LOCATED', 'ink');
    await ctx.play(sc.success);
    await ctx.play(sc.outro);
  });

  /* ═════════════ interrogation: True / False / Not Given ═════════════ */

  var VERDICT_NAME = { T: 'TRUE', F: 'LIE', NG: 'NOT GIVEN' };

  CF.registerScene('interrogation', async function (sc, ctx) {
    await ctx.titleCard(sc);
    await ctx.play(sc.intro);
    var suspect = ctx.case.cast[sc.suspect], cost = ctx.case.mistakeCost;
    var pressure = 0, lineEls = {}, sectionEls = {};

    var meter = h('div', { class: 'pressure' }, h('span', {}, 'Pressure'));
    for (var i = 0; i < sc.need; i++) meter.appendChild(h('i'));
    var chips = h('div', { class: 'chips' }, sc.statements.map(function () { return h('i'); }));
    var quote = h('div', { class: 'quote' });
    var top = h('div', { class: 'interro-top' }, quote);
    var face = h('div', { class: 'interro-face' });
    var LEVELS = ['Calm', 'Nervous', 'Sweating', 'Cracking'], FACES = ['neutral', 'nervous', 'sweating', 'cracked'];
    /** Redraws the suspect across the desk; `jolt` makes him flinch or preen. */
    function setFace(mood, jolt) {
      face.innerHTML = CF.art.portrait(sc.suspect, mood);
      ctx.mood(sc.suspect, mood);
      face.className = 'interro-face'; void face.offsetWidth;
      if (jolt) face.classList.add(jolt);
    }
    setFace('neutral');
    ctx.setProp(h('div', { class: 'interro-band' }, face, h('div', { class: 'interro-meta' }, meter, chips)));

    var doc = h('div', { class: 'paper schedule' },
      h('div', { class: 'sch-head' }, h('b', {}, sc.doc.head), h('span', {}, sc.doc.title), h('span', {}, sc.doc.date)),
      h('p', { class: 'sch-sub' }, sc.doc.sub),
      sc.doc.sections.map(function (sec) {
        var el = h('section', {}, h('h3', {}, sec.title), sec.lines.map(function (l) {
          var line = h('button', { class: 'line', type: 'button', onclick: function () { tapLine(l.id); } },
            l.time ? h('span', { class: 'line-time' }, l.time) : null, h('span', { class: 'line-text' }, l.text), h('span', { class: 'line-tag' }));
          lineEls[l.id] = line;
          return line;
        }));
        sectionEls[sec.id] = el;
        return el;
      }));
    ctx.setStage(top, doc);

    var armed = null; // function(lineId) while waiting for a proof tap
    function tapLine(id) {
      if (armed) armed(id);
      else ctx.toast('First decide: True, Lie or Not Given.');
    }
    function setPressure() {
      [].forEach.call(meter.querySelectorAll('i'), function (el, i) { el.classList.toggle('on', i < pressure); });
      meter.classList.toggle('full', pressure >= sc.need);
      meter.firstChild.textContent = 'Pressure: ' + LEVELS[Math.min(pressure, LEVELS.length - 1)];
      meter.classList.remove('bump'); void meter.offsetWidth; meter.classList.add('bump');
    }

    /** Verdict first; for True or Lie the player must then tap the proving line. */
    function ask() {
      return new Promise(function (resolve) {
        function verdicts() {
          armed = null; doc.classList.remove('armed');
          ctx.setTray(h('div', { class: 'verdicts' },
            ctx.button('True', 'verdict v-t', function () { prove('T'); }),
            ctx.button('Lie', 'verdict v-f', function () { prove('F'); }),
            ctx.button('Not Given', 'verdict v-ng', function () { ctx.setTray(); resolve({ verdict: 'NG' }); })));
        }
        function prove(v) {
          doc.classList.add('armed');
          ctx.setTray(h('div', { class: 'prove' },
            h('p', { html: v === 'F' ? 'Tap the line that <b>proves he’s lying</b>.' : 'Tap the line that <b>proves it’s true</b>.' }),
            ctx.button('Back', 'ghost small', verdicts)));
          armed = function (id) { armed = null; doc.classList.remove('armed'); ctx.setTray(); resolve({ verdict: v, line: id }); };
        }
        verdicts();
      });
    }

    for (var n = 0; n < sc.statements.length; n++) {
      var st = sc.statements[n], solved = false;
      for (var attempt = 0; attempt < 2 && !solved; attempt++) {
        var proof = attempt === 1 && st.harderProof ? st.harderProof : st.proof;
        quote.textContent = '';
        quote.appendChild(h('div', { class: 'quote-who' }, h('span', { class: 'avatar tone-red' }, suspect.initials),
          h('b', {}, suspect.name), h('small', {}, 'Statement ' + (n + 1) + ' of ' + sc.statements.length + (attempt ? ' · again' : ''))));
        quote.appendChild(h('p', {}, '“' + (attempt ? st.harder : st.text) + '”'));
        quote.classList.remove('in'); void quote.offsetWidth; quote.classList.add('in');
        ctx.setHint((function (st) {
          return async function () {
            var sec = sectionEls[st.hint.section];
            sec.classList.add('hl'); sec.scrollIntoView({ block: 'center', behavior: 'smooth' });
            await ctx.say([st.hint.text]);
            setTimeout(function () { sec.classList.remove('hl'); }, 6000);
            return true;
          };
        })(st));

        var ans = await ask();
        ctx.setHint(null);
        var rightVerdict = ans.verdict === st.verdict;
        var ok = rightVerdict && (st.verdict === 'NG' || proof.indexOf(ans.line) >= 0);
        if (attempt === 0) ctx.mark('R', sc.id + '.' + st.id, ok);

        if (ok) {
          solved = true;
          if (st.verdict === 'F') {
            lineEls[ans.line].classList.add('proved');
            lineEls[ans.line].querySelector('.line-tag').textContent = 'proves lie ' + (n + 1);
            CF.fx.pen(lineEls[ans.line].querySelector('.line-text'), 'underline', 'red');
            pressure++; setPressure();
            setTimeout(function () { setFace(FACES[Math.min(pressure, FACES.length - 1)], 'flinch'); }, 210);
            await ctx.stamp('CONTRADICTION', 'red');
          } else if (st.verdict === 'T') {
            lineEls[ans.line].classList.add('confirmed');
            CF.fx.pen(lineEls[ans.line], 'tick', 'blue');
            await ctx.stamp('CONFIRMED', 'ink');
          } else {
            await ctx.stamp('NOT GIVEN', 'grey');
          }
          chips.children[n].className = 'c-' + st.verdict;
          await ctx.say(st.right);
        } else {
          ctx.lose(cost);
          setFace('smug', 'preen');
          var key = rightVerdict ? 'line' : ans.verdict + '>' + st.verdict;
          await ctx.say(sc.reactions[key]);
          if (attempt === 0) await ctx.say(sc.reactions.again);
          setFace(FACES[Math.min(pressure, FACES.length - 1)]);
        }
      }
      if (!solved) {
        // Two misses: Sam settles it, but a lie settled by Sam puts no pressure on the suspect.
        st.proof.forEach(function (id) { lineEls[id].classList.add(st.verdict === 'F' ? 'proved' : 'confirmed'); });
        if (st.proof[0]) lineEls[st.proof[0]].scrollIntoView({ block: 'center', behavior: 'smooth' });
        chips.children[n].className = 'c-' + st.verdict + ' by-sam';
        await ctx.say(['It’s ' + VERDICT_NAME[st.verdict] + '. ' + st.explain].concat(st.verdict === 'F' ? sc.reactions.resolvedLie : []));
      }
      ctx.word(st.word);
    }

    quote.textContent = ''; top.hidden = true;
    ctx.setTray();
    if (pressure < sc.need) setFace('smug');
    await ctx.play(pressure >= sc.need ? sc.crack : sc.noCrack);
    ctx.mood(sc.suspect, null);
    await ctx.play(sc.outro);
  });

  /* ═════════════ chart: Writing Task 1 skills ═════════════ */

  function drawChart(c) {
    var W = 340, H = 230, L = 40, R = 8, T = 26, B = 30, pw = W - L - R, ph = H - T - B;
    var root = svg('svg', { class: 'chart', viewBox: '0 0 ' + W + ' ' + H, role: 'img', 'aria-label': c.title });
    var y = function (v) { return T + ph - (v / c.max) * ph; };
    c.ticks.forEach(function (t) {
      root.appendChild(svg('line', { class: 'grid' + (t === c.capacity ? ' cap' : ''), x1: L, x2: W - R, y1: y(t), y2: y(t) }));
      root.appendChild(svg('text', { class: 'tick', x: L - 5, y: y(t) + 3.5, 'text-anchor': 'end' }, t.toLocaleString('en-GB')));
    });
    var slot = pw / c.bars.length, bw = slot * 0.56, bars = [];
    c.bars.forEach(function (b, i) {
      var x = L + slot * i + (slot - bw) / 2, g = svg('g', { class: 'bar' });
      g.appendChild(svg('rect', { x: x, y: y(b.value), width: bw, height: T + ph - y(b.value) }));
      g.appendChild(svg('text', { class: 'val', x: x + bw / 2, y: y(b.value) - 5, 'text-anchor': 'middle' }, b.value.toLocaleString('en-GB')));
      g.appendChild(svg('text', { class: 'lab', x: x + bw / 2, y: H - B + 14, 'text-anchor': 'middle' }, b.label));
      if (b.tag) g.appendChild(svg('text', { class: 'tag', x: x + bw / 2, y: H - B + 25, 'text-anchor': 'middle' }, b.tag));
      root.appendChild(g); bars.push(g);
    });
    root.appendChild(svg('line', { class: 'axis', x1: L, x2: W - R, y1: T + ph, y2: T + ph }));
    return { el: root, bars: bars };
  }

  /** Shows a prompt and options in the tray; wrong options cost time and are crossed out. */
  function chooseFix(ctx, prompt, options, onWrong, allowBack) {
    return new Promise(function (resolve) {
      var buttons = options.map(function (o) {
        var b = ctx.button(o.text, 'option', async function () {
          if (o.correct) { CF.Sound.play('good'); ctx.setTray(); resolve(true); return; }
          b.disabled = true; b.classList.add('struck');
          await onWrong(o);
        });
        return b;
      });
      ctx.setTray(h('div', { class: 'options' }, h('p', { class: 'options-prompt' }, prompt), buttons,
        allowBack ? ctx.button('Leave this sentence', 'ghost small', function () { ctx.setTray(); resolve(false); }) : null));
    });
  }

  CF.registerScene('chart', async function (sc, ctx) {
    await ctx.titleCard(sc);
    await ctx.play(sc.intro);
    var cost = ctx.case.mistakeCost, chart = drawChart(sc.chart), els = {}, firstTry = true;

    var memo = h('div', { class: 'paper memo' },
      h('div', { class: 'memo-head' },
        h('p', {}, h('span', {}, 'To'), sc.memo.to), h('p', {}, h('span', {}, 'From'), sc.memo.from), h('p', {}, h('span', {}, 'Subject'), sc.memo.subject)),
      sc.sentences.map(function (s) {
        var b = h('button', { class: 'sentence', type: 'button' }, h('span', { class: 's-text' }, s.text), h('span', { class: 's-tag' }));
        els[s.id] = b; return b;
      }));
    ctx.setStage(
      h('div', { class: 'paper chart-paper' }, h('i', { class: 'pin' }), h('h2', {}, sc.chart.title), h('p', { class: 'doc-ref' }, sc.chart.note), chart.el),
      memo);
    ctx.setTray(h('p', { class: 'tray-note', html: 'Tap the sentence that <b>gets the chart wrong</b>.' }));
    ctx.setHint(async function () {
      sc.chart.hintBars.forEach(function (i) { chart.bars[i].classList.add('hl'); });
      chart.el.scrollIntoView({ block: 'center', behavior: 'smooth' });
      await ctx.say([sc.hint]);
      return true;
    });

    var target = await new Promise(function (resolve) {
      sc.sentences.forEach(function (s) {
        els[s.id].onclick = async function () {
          if (els[s.id].disabled) return;
          if (s.false) { resolve(s); return; }
          firstTry = false;
          els[s.id].disabled = true; els[s.id].classList.add('checked');
          els[s.id].querySelector('.s-tag').textContent = 'matches the chart';
          CF.fx.pen(els[s.id], 'tick', 'blue');
          ctx.lose(cost);
          await ctx.say([s.wrong]);
        };
      });
    });
    ctx.mark('W', sc.id + '.find', firstTry);
    sc.sentences.forEach(function (s) { els[s.id].onclick = null; });
    els[target.id].classList.add('circled');
    CF.fx.pen(els[target.id], 'circle', 'red');
    await ctx.stamp('FALSE', 'red');
    await ctx.say(sc.found);

    var fixFirst = true;
    ctx.setHint(async function () { await ctx.say([sc.rewrite.hint]); return true; });
    await chooseFix(ctx, sc.rewrite.prompt, sc.rewrite.options, async function (o) {
      fixFirst = false; ctx.lose(cost); await ctx.say([o.wrong]);
    });
    ctx.setHint(null);
    ctx.mark('W', sc.id + '.fix', fixFirst);
    var good = sc.rewrite.options.filter(function (o) { return o.correct; })[0];
    els[target.id].innerHTML = '<span class="s-text"><del>' + CF.rich(target.text) + '</del><ins>' + CF.rich(good.text) + '</ins></span>';
    CF.fx.pen(els[target.id].querySelector('del'), 'strike', 'red');
    els[target.id].scrollIntoView({ block: 'center', behavior: 'smooth' });
    (sc.words || []).forEach(function (w) { ctx.word(w); });
    await wait(700);
    await ctx.play(sc.outro);
  });

  /* ═════════════ forgery: grammar ═════════════ */

  CF.registerScene('forgery', async function (sc, ctx) {
    await ctx.titleCard(sc);
    await ctx.play(sc.intro);
    var cost = ctx.case.mistakeCost, L = sc.letter, els = {}, paraEls = [], busy = false;
    var all = [].concat.apply([], L.paragraphs);
    var errors = all.filter(function (s) { return s.error; }), found = [], falseAlarms = 0, fixMisses = {};
    var counter = h('p', { class: 'tray-note' });
    function count() { counter.innerHTML = 'Tap a sentence Mira would never write. Mistakes found: <b>' + found.length + ' of ' + errors.length + '</b>'; }

    var letter = h('div', { class: 'paper letter' },
      h('div', { class: 'letter-from' }, L.from.map(function (x) { return h('span', {}, x); })),
      h('p', { class: 'letter-greet' }, L.greeting),
      L.paragraphs.map(function (p) {
        var el = h('p', { class: 'letter-para' }, p.map(function (s) {
          var span = h('span', { class: 'sent', role: 'button', tabindex: '0', onclick: function () { tap(s); } }, s.text);
          els[s.id] = span;
          return [span, ' '];
        }));
        paraEls.push(el); return el;
      }),
      h('p', { class: 'letter-close' }, L.close), h('p', { class: 'letter-sign' }, L.signature));
    ctx.setStage(letter);

    function searchMode() {
      count(); ctx.setTray(counter);
      ctx.setHint(async function () {
        var next = errors.filter(function (e) { return found.indexOf(e.id) < 0; })[0];
        var para = paraEls[L.paragraphs.findIndex(function (p) { return p.indexOf(next) >= 0; })];
        para.classList.add('hl'); para.scrollIntoView({ block: 'center', behavior: 'smooth' });
        await ctx.say([sc.hint]);
        setTimeout(function () { para.classList.remove('hl'); }, 6000);
        return true;
      });
    }

    var finished;
    var done = new Promise(function (r) { finished = r; });

    async function tap(s) {
      if (busy || els[s.id].classList.contains('fine') || found.indexOf(s.id) >= 0) return;
      busy = true;
      if (!s.error) {
        falseAlarms++;
        els[s.id].classList.add('fine');
        CF.fx.pen(els[s.id], 'underline', 'blue');
        ctx.lose(cost);
        await ctx.say([s.fine || sc.fineGeneric[0]]);
        busy = false; return;
      }
      els[s.id].classList.add('querying');
      ctx.setHint(async function () { await ctx.say([sc.fixHint]); return true; });
      var fixed = await chooseFix(ctx, sc.fixPrompt, s.error.options, async function (o) {
        fixMisses[s.id] = true; ctx.lose(cost); await ctx.say([o.wrong]);
      }, true);
      els[s.id].classList.remove('querying');
      if (fixed) {
        found.push(s.id);
        els[s.id].classList.add('caught');
        els[s.id].innerHTML = CF.rich(s.text).replace(CF.rich(s.error.bad), '<del>' + CF.rich(s.error.bad) + '</del><ins>' + CF.rich(s.error.good) + '</ins>');
        CF.fx.pen(els[s.id].querySelector('del'), 'strike', 'red');
        CF.fx.shake(0.15);
        ctx.word(s.error.word);
      }
      busy = false;
      if (found.length === errors.length) finished(); else searchMode();
    }

    searchMode();
    await done;
    ctx.setHint(null); ctx.setTray();
    // Each false alarm spoils one "find"; each wrong correction spoils that "fix".
    errors.forEach(function (e, i) {
      ctx.mark('W', sc.id + '.find' + i, i >= falseAlarms);
      ctx.mark('W', sc.id + '.fix.' + e.id, !fixMisses[e.id]);
    });
    await ctx.stamp(sc.stamp, 'red');
    await ctx.play(sc.outro);
  });

  /* ═════════════ torn note: linking words ═════════════ */

  CF.registerScene('torn', async function (sc, ctx) {
    await ctx.titleCard(sc);
    await ctx.play(sc.intro);
    var cost = ctx.case.mistakeCost, gaps = {}, strips = {}, solved = {}, missed = {}, struck = {}, current = null;
    function cap(w) { return w.charAt(0).toUpperCase() + w.slice(1); }

    var note = h('div', { class: 'torn' },
      h('div', { class: 'strip plain' }, sc.opening),
      sc.pieces.map(function (p, i) {
        var gap = h('button', { class: 'gap', type: 'button', onclick: function () { select(p); } }, '______');
        gaps[p.id] = gap;
        var strip = h('div', { class: 'strip loose tilt' + (i % 3) }, p.before ? p.before + ' ' : '', gap, (p.comma ? ', ' : ' ') + p.after);
        strips[p.id] = strip;
        return strip;
      }),
      h('div', { class: 'strip plain' }, sc.closing));
    ctx.setStage(h('div', { class: 'torn-wrap' }, note));

    var finished;
    var done = new Promise(function (r) { finished = r; });

    function select(p) {
      if (solved[p.id]) return;
      current = p;
      sc.pieces.forEach(function (x) { gaps[x.id].classList.toggle('sel', x.id === p.id); });
      var busy = false;
      ctx.setTray(h('div', { class: 'linkers' },
        h('p', { class: 'options-prompt' }, 'Which word mends this piece?'),
        h('div', { class: 'linker-row' }, p.options.map(function (o) {
          var b = ctx.button(p.capital ? cap(o) : o, 'linker', async function () {
            if (busy) return;
            if (o === p.answer) { await fill(p, o); return; }
            busy = true; missed[p.id] = true; (struck[p.id] = struck[p.id] || {})[o] = true;
            b.disabled = true; b.classList.add('struck');
            ctx.lose(cost);
            await ctx.say([p.why[o]]);
            busy = false;
          });
          if (struck[p.id] && struck[p.id][o]) { b.disabled = true; b.classList.add('struck'); }
          return b;
        }))));
      ctx.setHint(async function () {
        strips[p.id].scrollIntoView({ block: 'center', behavior: 'smooth' });
        await ctx.say([p.hint]);
        return true;
      });
    }

    async function fill(p, o) {
      solved[p.id] = true;
      gaps[p.id].textContent = p.capital ? cap(o) : o;
      gaps[p.id].className = 'gap filled'; gaps[p.id].disabled = true;
      strips[p.id].classList.remove('loose'); strips[p.id].classList.add('mended');
      strips[p.id].appendChild(h('i', { class: 'sticky-tape' }));
      CF.Sound.play('tape'); CF.fx.shake(0.12);
      ctx.word(p.word);
      var next = sc.pieces.filter(function (x) { return !solved[x.id]; })[0];
      if (next) { select(next); strips[next.id].scrollIntoView({ block: 'center', behavior: 'smooth' }); }
      else { ctx.setTray(); ctx.setHint(null); finished(); }
    }

    select(sc.pieces[0]);
    await done;
    sc.pieces.forEach(function (p) { ctx.mark('W', sc.id + '.' + p.id, !missed[p.id]); });
    note.classList.add('whole');
    await ctx.stamp('PLAN REVEALED', 'red');
    await ctx.play(sc.outro);
  });

  /* ═════════════ accusation ═════════════ */

  CF.registerScene('accusation', async function (sc, ctx) {
    await ctx.titleCard(sc);
    await ctx.play(sc.intro);
    var c = ctx.case, held = c.evidence, suspect = null, cards = [];

    var go = ctx.button('Choose a suspect and 3 cards', 'primary danger');
    go.disabled = true;
    var strings = svg('svg', { class: 'strings', 'aria-hidden': 'true' }), board;
    /** Red string from the chosen suspect to each chosen card. */
    function drawStrings() {
      strings.textContent = '';
      if (!suspect || !board) return;
      var box = board.getBoundingClientRect();
      var from = susEls[sc.suspects.indexOf(suspect)].querySelector('.mug').getBoundingClientRect();
      var x1 = from.left + from.width / 2 - box.left, y1 = from.bottom - box.top;
      cards.forEach(function (e) {
        var pin = cardEls[held.indexOf(e)].querySelector('.pin').getBoundingClientRect();
        var x2 = pin.left + pin.width / 2 - box.left, y2 = pin.top + pin.height / 2 - box.top;
        strings.appendChild(svg('path', { d: 'M' + x1 + ' ' + y1 + ' Q' + (x1 + x2) / 2 + ' ' + ((y1 + y2) / 2 + 26) + ' ' + x2 + ' ' + y2, pathLength: 1 }));
      });
    }
    function refresh() {
      drawStrings();
      go.disabled = !(suspect && cards.length === 3);
      go.textContent = !suspect ? 'Choose a suspect' : cards.length < 3 ? 'Choose ' + (3 - cards.length) + ' more card' + (cards.length === 2 ? '' : 's') : 'Arrest ' + suspect.name;
    }
    var susEls = sc.suspects.map(function (s) {
      var el = h('button', { class: 'suspect', type: 'button', onclick: function () {
        suspect = s; susEls.forEach(function (x) { x.classList.toggle('sel', x === el); }); CF.Sound.play('pin'); refresh();
      } }, h('span', { class: 'mug', html: CF.art.hasPortrait(s.id) ? CF.art.portrait(s.id, 'neutral') : s.initials }), h('b', {}, s.name), h('small', {}, s.role), h('p', {}, s.line));
      return el;
    });
    var cardEls = held.map(function (e) {
      var el = h('button', { class: 'ev-card', type: 'button', onclick: function () {
        var i = cards.indexOf(e);
        if (i >= 0) cards.splice(i, 1);
        else if (cards.length < 3) cards.push(e);
        else { ctx.toast('Three cards only. Tap one to put it back.'); return; }
        el.classList.toggle('sel', cards.indexOf(e) >= 0); CF.Sound.play('pin'); refresh();
      } }, h('i', { class: 'pin' }), h('b', {}, e.title), h('p', {}, e.text));
      return el;
    });
    board = h('div', { class: 'accuse' },
      h('h2', {}, 'Who did it?'), h('div', { class: 'suspects' }, susEls),
      h('h2', {}, 'Which three cards prove it?'), h('p', { class: 'accuse-note' }, 'Choose what shows what the suspect did.'),
      h('div', { class: 'ev-grid' }, cardEls), strings);
    ctx.setStage(board);
    ctx.setTray(go);
    ctx.setHint(async function () { await ctx.say([sc.hint]); return true; });

    await new Promise(function (resolve) { go.onclick = resolve; });
    ctx.setHint(null); ctx.setTray();

    var verdict = suspect.id !== sc.culprit ? 'R' : cards.every(function (e) { return e.proves; }) ? 'C' : 'W';
    var now = ctx.now, clock = c.clock, toM = function (t) { var p = t.split(':'); return +p[0] * 60 + +p[1]; };
    var tier = now <= toM(clock.comfortable) ? 'early' : now <= toM(clock.deadline) ? 'close' : 'late';
    ctx.state.ending = { verdict: verdict, suspect: suspect.id, cards: cards.map(function (e) { return e.id; }), tier: tier };
    ctx.save();

    var end = verdict === 'R' ? sc.endings.R[suspect.id] : sc.endings[verdict];
    var timeLine = fmt(sc.timeLines[tier], { late: now - toM(clock.deadline) });
    ctx.setStage(CF.docs.newspaper({ paper: sc.paper, headline: end.headline, sub: end.sub, body: end.body.concat([timeLine]) }));
    await ctx.stamp(sc.verdictStamps[verdict], verdict === 'C' ? 'red' : 'ink');
    var lines = [];
    end.sam.forEach(function (l) {
      if (l === '{weak}') cards.filter(function (e) { return !e.proves; }).forEach(function (e) { lines.push(e.weak); });
      else lines.push(l);
    });
    await ctx.say(lines);
    await ctx.proceed('See the case report');
  });

  /* ═════════════ case report ═════════════ */

  CF.registerScene('report', async function (sc, ctx) {
    var c = ctx.case, s = ctx.state, end = s.ending || { verdict: 'R' };
    ctx.setHint(null); ctx.setTray(); ctx.setProp(null);
    ctx.setPlace(sc.place, sc.surface);
    var bands = {};
    sc.skills.forEach(function (k) { bands[k.key] = CF.bandFor(s.marks[k.key]); });
    var hintsUsed = c.hints - s.hintsLeft;
    var code = CF.encodeResult(c, { ending: end.verdict, L: bands.L.band, R: bands.R.band, W: bands.W.band, hints: hintsUsed, lost: s.lost });
    var show = function (b) { return b == null ? '–' : b.toFixed(1); };
    var startMin = ctx.now - s.lost;
    var weakest = sc.skills.slice().sort(function (a, b) { return (bands[a.key].band || 9) - (bands[b.key].band || 9); })[0];

    function resultRows(r, who) {
      return h('div', { class: 'cmp-col' }, h('b', {}, who),
        h('span', {}, sc.endingNames[r.ending]),
        h('span', {}, 'L ' + show(r.L) + ' · R ' + show(r.R) + ' · W ' + show(r.W)),
        h('span', {}, 'Closed at ' + CF.clockText(startMin + r.lost)),
        h('span', {}, r.hints + ' hint' + (r.hints === 1 ? '' : 's')));
    }
    var mine = { ending: end.verdict, L: bands.L.band, R: bands.R.band, W: bands.W.band, lost: s.lost, hints: hintsUsed };

    var codeBox = h('output', { class: 'code' }, code);
    var cmpOut = h('div', { class: 'cmp-out' });
    var cmpIn = h('input', { type: 'text', placeholder: 'Paste a friend’s code', autocomplete: 'off', autocapitalize: 'characters', spellcheck: 'false', 'aria-label': 'Friend’s result code' });

    ctx.setStage(h('div', { class: 'paper report' },
      h('span', { class: 'stamp small ' + (end.verdict === 'C' ? 'red' : 'ink') }, sc.endingNames[end.verdict]),
      h('p', { class: 'doc-ref' }, 'Unit 9 · Case ' + c.number), h('h2', {}, 'Case Report'), h('p', { class: 'rep-title' }, c.title),
      h('dl', {},
        h('dt', {}, 'Case closed at'), h('dd', {}, CF.clockText(ctx.now) + (s.lost ? ' (' + s.lost + ' min lost)' : ' (no time lost)')),
        h('dt', {}, 'Hints used'), h('dd', {}, hintsUsed + ' of ' + c.hints)),
      h('h3', {}, 'Estimated band'),
      sc.skills.map(function (k) {
        var b = bands[k.key];
        return h('div', { class: 'band' },
          h('div', { class: 'band-top' }, h('b', {}, k.name), h('span', { class: 'band-num' }, show(b.band))),
          h('div', { class: 'band-bar' }, h('i', { style: 'width:' + (b.total ? Math.round((b.got / b.total) * 100) : 0) + '%' })),
          h('small', {}, b.got + ' of ' + b.total + ' right first time, from ' + k.from));
      }),
      h('p', { class: 'rep-note' }, 'A rough guide from one short case, not an official score. To work on next: ' + weakest.name + '.'),
      h('h3', {}, 'Result code'),
      h('div', { class: 'code-row' }, codeBox,
        ctx.button('Copy', 'small', function (ev) {
          var btn = ev.currentTarget, okay = function () { btn.textContent = 'Copied'; };
          if (navigator.clipboard && navigator.clipboard.writeText) navigator.clipboard.writeText(code).then(okay, function () { ctx.toast('Press and hold the code to copy it.'); });
          else ctx.toast('Press and hold the code to copy it.');
        })),
      h('p', { class: 'rep-note' }, 'Send it to someone who played this case. Paste theirs here to compare.'),
      h('div', { class: 'code-row' }, cmpIn,
        ctx.button('Compare', 'small', function () {
          var r = CF.decodeResult(cmpIn.value);
          cmpOut.textContent = '';
          if (!r) { cmpOut.appendChild(h('p', { class: 'rep-note bad' }, 'That doesn’t look like a result code. Check for a missing letter.')); return; }
          if (r.code + r.number !== c.code + c.number) { cmpOut.appendChild(h('p', { class: 'rep-note bad' }, 'That code is from a different case.')); return; }
          cmpOut.appendChild(h('div', { class: 'cmp' }, resultRows(mine, 'You'), resultRows(r, 'Them')));
        })),
      cmpOut,
      h('button', { class: 'btn primary', onclick: function () { CF.restart(); } }, 'Play the case again')));
    document.getElementById('btn-notebook').classList.add('ping');
    await new Promise(function () {}); // the report is the last screen
  });
})();
