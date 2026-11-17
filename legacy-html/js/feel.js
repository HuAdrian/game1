/*
 * CASE FILES — feel
 *
 * The visual and tactile layer. Nothing in here knows about questions or
 * answers; it only makes actions look, sound and feel like something.
 *
 *   CF.Sound     small synthesised sounds (Web Audio, no audio files)
 *   CF.fx        screen shake, pen marks, ink splats, feedback bundles
 *   CF.art       illustrated places and ink portraits (inline SVG)
 */
(function () {
  'use strict';
  var CF = window.CaseFiles;

  var prefs = {
    get: function (k, d) { try { var v = localStorage.getItem('casefiles.' + k); return v == null ? d : v === '1'; } catch (e) { return d; } },
    set: function (k, v) { try { localStorage.setItem('casefiles.' + k, v ? '1' : '0'); } catch (e) {} }
  };
  var reducedMotion = !!(window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches);

  /* ═════════════ sound ═════════════ */

  var Sound = {
    on: prefs.get('sound', true),
    ac: null, noiseBuf: null,
    setOn: function (v) { this.on = v; prefs.set('sound', v); },
    /** Call from a tap: browsers only allow audio after a user gesture. */
    unlock: function () {
      if (!this.on) return;
      try {
        if (!this.ac) {
          var AC = window.AudioContext || window.webkitAudioContext;
          if (!AC) return;
          this.ac = new AC();
          var len = this.ac.sampleRate, buf = this.ac.createBuffer(1, len, len), d = buf.getChannelData(0);
          for (var i = 0; i < len; i++) d[i] = Math.random() * 2 - 1;
          this.noiseBuf = buf;
        }
        if (this.ac.state === 'suspended') this.ac.resume();
      } catch (e) { this.ac = null; }
    },
    tone: function (type, f0, f1, dur, gain, delay) {
      var ac = this.ac, t = ac.currentTime + (delay || 0), o = ac.createOscillator(), g = ac.createGain();
      o.type = type; o.frequency.setValueAtTime(f0, t);
      if (f1 !== f0) o.frequency.exponentialRampToValueAtTime(Math.max(20, f1), t + dur);
      g.gain.setValueAtTime(0.0001, t); g.gain.exponentialRampToValueAtTime(gain, t + 0.006);
      g.gain.exponentialRampToValueAtTime(0.0001, t + dur);
      o.connect(g); g.connect(ac.destination); o.start(t); o.stop(t + dur + 0.02);
    },
    burst: function (dur, gain, ftype, f0, f1, q, delay) {
      var ac = this.ac, t = ac.currentTime + (delay || 0), s = ac.createBufferSource(), f = ac.createBiquadFilter(), g = ac.createGain();
      s.buffer = this.noiseBuf; s.loop = true;
      f.type = ftype; f.Q.value = q || 0.8; f.frequency.setValueAtTime(f0, t);
      if (f1 && f1 !== f0) f.frequency.exponentialRampToValueAtTime(f1, t + dur);
      g.gain.setValueAtTime(0.0001, t); g.gain.exponentialRampToValueAtTime(gain, t + Math.min(0.02, dur / 3));
      g.gain.exponentialRampToValueAtTime(0.0001, t + dur);
      s.connect(f); f.connect(g); g.connect(ac.destination);
      s.start(t, Math.random() * 0.5); s.stop(t + dur + 0.02);
    },
    play: function (name) {
      if (!this.on || !this.ac || this.ac.state !== 'running') return;
      var S = this;
      try {
        switch (name) {
          case 'tick': S.burst(0.014, 0.09, 'highpass', 2600); break;
          case 'blip': S.tone('sine', 540, 420, 0.035, 0.035); break;
          case 'paper': S.burst(0.2, 0.1, 'bandpass', 1100, 3600, 0.7); break;
          case 'wipe': S.burst(0.34, 0.11, 'bandpass', 700, 2800, 0.6); S.burst(0.05, 0.12, 'lowpass', 500, 0, 1, 0.3); break;
          case 'pen': S.burst(0.07, 0.07, 'bandpass', 2700, 3400, 2.5); S.burst(0.09, 0.07, 'bandpass', 3200, 2400, 2.5, 0.08); break;
          case 'key': S.burst(0.012, 0.05, 'highpass', 3500); break;
          case 'thud': S.tone('sine', 120, 36, 0.26, 0.85); S.burst(0.07, 0.5, 'lowpass', 520); S.burst(0.2, 0.05, 'bandpass', 1500, 600, 1, 0.03); break;
          case 'thudSoft': S.tone('sine', 150, 60, 0.16, 0.4); S.burst(0.04, 0.22, 'lowpass', 700); break;
          case 'pin': S.tone('triangle', 1700, 800, 0.025, 0.12); S.tone('sine', 170, 90, 0.07, 0.3, 0.01); break;
          case 'good': S.tone('triangle', 660, 660, 0.09, 0.06); S.tone('triangle', 880, 880, 0.14, 0.06, 0.09); break;
          case 'bad': S.tone('sine', 170, 95, 0.22, 0.3); S.burst(0.09, 0.14, 'lowpass', 380); break;
          case 'clock': S.tone('sine', 1250, 1250, 0.018, 0.12); S.tone('sine', 1000, 1000, 0.018, 0.12, 0.11); S.tone('sine', 1250, 1250, 0.018, 0.12, 0.22); break;
          case 'ring':
            [0, 0.5].forEach(function (d) { S.tone('sine', 400, 400, 0.36, 0.035, d); S.tone('sine', 450, 450, 0.36, 0.035, d); });
            break;
          case 'clunk': S.burst(0.05, 0.3, 'lowpass', 900); S.tone('sine', 95, 70, 0.07, 0.3, 0.01); break;
          case 'static': S.burst(0.16, 0.09, 'bandpass', 1900, 1500, 0.6); break;
          case 'tape': S.burst(0.17, 0.11, 'highpass', 3200, 900, 1.5); break;
          case 'step': S.burst(0.03, 0.12, 'lowpass', 420); break;
          case 'open': S.burst(0.26, 0.1, 'bandpass', 2400, 900, 0.7); break;
        }
      } catch (e) { /* sound is a nicety; never let it break the game */ }
    }
  };
  CF.Sound = Sound;

  /* ═════════════ fx: shake, pen, splats, bundles ═════════════ */

  var fx = {
    shakeOn: prefs.get('shake', true),
    setShake: function (v) { this.shakeOn = v; prefs.set('shake', v); },
    trauma: 0, t: 0, raf: 0, last: 0,
    /** Trauma-based shake on the whole desk: shake = trauma², decays in real time. */
    shake: function (amount) {
      if (!this.shakeOn || reducedMotion) return;
      this.trauma = Math.min(1, this.trauma + amount);
      if (this.raf) return;
      var self = this, el = document.getElementById('app');
      self.last = performance.now();
      (function step(now) {
        var dt = Math.min(0.05, (now - self.last) / 1000); self.last = now;
        self.trauma = Math.max(0, self.trauma - 1.7 * dt);
        if (self.trauma === 0) { el.style.transform = ''; self.raf = 0; return; } // always return to rest
        var s = self.trauma * self.trauma; self.t += dt * 30;
        el.style.transform = 'translate(' + (11 * s * Math.sin(self.t * 1.7)).toFixed(2) + 'px,' + (8 * s * Math.sin(self.t * 2.3)).toFixed(2) + 'px) rotate(' + (0.7 * s * Math.sin(self.t * 1.1)).toFixed(3) + 'deg)';
        self.raf = requestAnimationFrame(step);
      })(self.last);
    },
    vibrate: function (p) { if (navigator.vibrate) { try { navigator.vibrate(p); } catch (e) {} } },
    /** One call per event tier keeps the whole game proportional. */
    feedback: function (tier) {
      if (tier === 'large') { Sound.play('thud'); this.shake(0.75); this.vibrate([20, 30, 90]); }
      else if (tier === 'medium') { Sound.play('thudSoft'); this.shake(0.35); this.vibrate(40); }
      else if (tier === 'wrong') { Sound.play('bad'); this.shake(0.3); this.vibrate(60); }
      else if (tier === 'right') { Sound.play('good'); }
      else Sound.play('tick');
    },
    /** Ink flecks around a stamp. */
    splat: function (host) {
      for (var i = 0; i < 9; i++) {
        var a = Math.random() * Math.PI * 2, d = 38 + Math.random() * 30, dot = document.createElement('i');
        dot.className = 'splat';
        dot.style.cssText = 'left:50%;top:50%;width:' + (3 + Math.random() * 6).toFixed(1) + 'px;height:' + (3 + Math.random() * 5).toFixed(1) +
          'px;--dx:' + (Math.cos(a) * d * 2.4).toFixed(0) + 'px;--dy:' + (Math.sin(a) * d).toFixed(0) + 'px';
        host.appendChild(dot);
      }
    },
    /**
     * Marks an element as if with a pen.
     *   underline / strike  a line drawn across the text (works on wrapped inline text)
     *   circle              a rough loop drawn around a block
     *   tick / cross        a mark drawn in the margin of a block
     */
    pen: function (el, kind, colour) {
      Sound.play('pen');
      colour = colour || 'red';
      if (kind === 'underline' || kind === 'strike' || kind === 'highlight') {
        el.classList.add('pen-' + kind, 'pen-' + colour);
        void el.offsetWidth; el.classList.add('pen-drawn');
        return;
      }
      var paths = {
        circle: 'M7 55 C3 22 28 5 54 6 C82 7 98 26 95 52 C92 80 70 95 45 94 C19 93 4 77 8 47 C11 28 24 13 43 9',
        tick: 'M10 55 L38 86 L92 12',
        cross: 'M14 14 L86 86 M86 14 L14 86'
      };
      var ns = 'http://www.w3.org/2000/svg', s = document.createElementNS(ns, 'svg'), p = document.createElementNS(ns, 'path');
      s.setAttribute('viewBox', '0 0 100 100'); s.setAttribute('preserveAspectRatio', 'none');
      s.setAttribute('class', 'pen-svg pen-' + kind + ' pen-' + colour); s.setAttribute('aria-hidden', 'true');
      p.setAttribute('d', paths[kind]); p.setAttribute('pathLength', '1');
      s.appendChild(p); el.classList.add('pen-host'); el.appendChild(s);
    }
  };
  CF.fx = fx;

  /* ═════════════ art: places ═════════════ */

  var INK = '#1c2530', RED = '#c2271c', COOL = '#cdd7de', COOL2 = '#aebbc5', WARM = '#e9dcc0', WARM2 = '#d2bd94', PAPER = '#fcf9f0';
  var L = 'fill="none" stroke="' + INK + '" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"';
  var T = 'fill="none" stroke="' + INK + '" stroke-width="1.1" stroke-linecap="round" opacity=".55"';
  function rep(n, fn) { var s = ''; for (var i = 0; i < n; i++) s += fn(i); return s; }
  function bricks(x0, y0, w, hgt, rows) {
    return rep(rows, function (r) {
      var y = y0 + r * (hgt / rows), off = r % 2 ? 22 : 0;
      return rep(4, function (i) { var x = x0 + off + i * (w / 4) + (r * 37 % 30); return '<path d="M' + x + ' ' + y + 'h' + (16 + (i * r * 7) % 14) + '" ' + T + '/>'; });
    });
  }

  var places = {
    /* Unit 9: a basement office. Daylight comes down from a pavement-level window. */
    unit9: function () {
      return '<rect width="400" height="300" fill="#dfe2dc"/>' + bricks(0, 20, 400, 250, 9) +
        '<path d="M0 34h400M0 44h400" ' + L + '/><path d="M150 30v18M156 30v18M300 30v18" ' + L + '/>' +
        '<polygon points="236,122 352,122 300,300 90,300" fill="#fff" opacity=".42"/>' +
        '<rect x="232" y="62" width="124" height="62" fill="#f6f1d8" stroke="' + INK + '" stroke-width="2.5"/>' +
        '<path d="M263 62v62M294 62v62M325 62v62" ' + L + '/>' +
        '<path d="M244 62v20q0 8 9 8h9v-7h-8v-21zM300 62v14q0 9 10 9h10v-7h-9v-16z" fill="' + INK + '"/>' +
        '<rect x="28" y="128" width="78" height="172" fill="' + COOL + '" stroke="' + INK + '" stroke-width="2.5"/>' +
        '<path d="M28 186h78M28 244h78M56 156h22M56 214h22M56 272h22" ' + L + '/>' +
        '<rect x="40" y="102" width="48" height="26" rx="5" fill="' + WARM + '" stroke="' + INK + '" stroke-width="2"/>' +
        '<rect x="48" y="109" width="32" height="12" fill="' + RED + '"/><path d="M38 102h52" ' + L + '/>' +
        '<circle cx="158" cy="98" r="19" fill="' + PAPER + '" stroke="' + INK + '" stroke-width="2.5"/><path d="M158 98v-11M158 98l8 5" ' + L + '/>' +
        '<path d="M196 300V118M182 130q14-16 28 0" ' + L + '/>' +
        '<path d="M184 134q12-8 24 0l12 96q-24 12-48 0z" fill="' + WARM2 + '" stroke="' + INK + '" stroke-width="2"/><path d="M196 140v84M188 176h16" ' + L + '/>' +
        '<rect x="118" y="150" width="46" height="34" fill="' + PAPER + '" stroke="' + INK + '" stroke-width="1.5" transform="rotate(-4 141 167)"/>' +
        '<path d="M126 162h28M126 170h20" ' + T + ' transform="rotate(-4 141 167)"/><circle cx="141" cy="152" r="3.5" fill="' + RED + '"/>' +
        '<path d="M346 300v-58l-26-30" ' + L + '/><path d="M306 204l22 2 -8 20z" fill="' + INK + '"/>';
    },
    /* The street outside the hall. */
    street: function () {
      return '<rect width="400" height="300" fill="#dbe6ea"/>' +
        '<path d="M40 70q14-14 30-4q16-10 28 4zM250 50q16-16 34-4q14-8 26 4z" fill="#fff" opacity=".8"/>' +
        '<path d="M52 232V96l10-22 10 22v136z" fill="' + COOL2 + '" stroke="' + INK + '" stroke-width="1.5" opacity=".6"/><circle cx="62" cy="112" r="6" fill="' + PAPER + '" stroke="' + INK + '" opacity=".6"/>' +
        '<path d="M0 232V150h70v-18h14v18h60v-26h80v26h46v-16h14v16h116v82z" fill="' + WARM + '" stroke="' + INK + '" stroke-width="2.5" stroke-linejoin="round"/>' +
        rep(9, function (i) { var x = 12 + i * 43; return '<rect x="' + x + '" y="168" width="16" height="24" fill="' + COOL + '" stroke="' + INK + '" stroke-width="1.5"/><path d="M' + x + ' 180h16" ' + T + '/>'; }) +
        '<path d="M166 124h36v-12h8v12" ' + L + '/><rect x="172" y="134" width="24" height="20" fill="' + COOL + '" stroke="' + INK + '" stroke-width="1.5"/>' +
        '<rect x="112" y="156" width="36" height="78" fill="' + RED + '" stroke="' + INK + '" stroke-width="2.5"/><path d="M108 156q22-14 44 0" fill="' + RED + '" stroke="' + INK + '" stroke-width="2.5"/>' +
        '<path d="M118 168h24v52h-24zM130 168v52M118 185h24M118 202h24" fill="' + PAPER + '" stroke="' + INK + '" stroke-width="1.3"/>' +
        '<path d="M306 300V96M306 96q0-14 14-14" ' + L + '/><path d="M312 82h20l-4 16h-12z" fill="#fff6c8" stroke="' + INK + '" stroke-width="2"/>' +
        '<rect x="0" y="232" width="400" height="68" fill="#c9cdc9"/><path d="M0 232h400M0 250h400" ' + L + '/>' +
        rep(6, function (i) { return '<path d="M' + (20 + i * 70) + ' 276h34" stroke="' + PAPER + '" stroke-width="4" stroke-linecap="round"/>'; });
    },
    /* Victor Hale's office at the hall. */
    office: function () {
      return '<rect width="400" height="300" fill="#ebe2cf"/><path d="M0 58h400" ' + L + '/>' +
        rep(10, function (i) { return '<path d="M' + (i * 44 + 10) + ' 58v242" ' + T + ' opacity=".18"/>'; }) +
        '<rect x="30" y="82" width="72" height="98" fill="' + PAPER + '" stroke="' + INK + '" stroke-width="3"/>' +
        '<path d="M66 100v30" ' + L + '/><path d="M66 128c-12 0-14 12-8 17c-8 6-4 20 8 20s16-14 8-20c6-5 4-17-8-17z" fill="' + WARM2 + '" stroke="' + INK + '" stroke-width="2"/><path d="M61 148h10" ' + L + '/>' +
        '<rect x="118" y="96" width="58" height="76" fill="' + PAPER + '" stroke="' + INK + '" stroke-width="3"/><rect x="124" y="102" width="46" height="16" fill="' + RED + '"/><path d="M128 130h38M128 140h38M128 150h24" ' + T + '/>' +
        '<rect x="222" y="74" width="140" height="124" fill="#f8f3dc" stroke="' + INK + '" stroke-width="3"/>' +
        rep(9, function (i) { return '<path d="M222 ' + (86 + i * 12) + 'h140" stroke="' + INK + '" stroke-width="1.6" opacity=".7"/>'; }) +
        '<path d="M354 74v150" ' + L + '/><circle cx="354" cy="226" r="3" fill="' + INK + '"/>' +
        '<rect x="0" y="236" width="400" height="64" fill="' + WARM2 + '"/><path d="M0 236h400" ' + L + '/>' +
        '<path d="M300 236v-10h56v10" ' + L + '/><path d="M296 226q32-26 64 0z" fill="' + INK + '"/><circle cx="328" cy="216" r="7" fill="' + PAPER + '" stroke="' + INK + '" stroke-width="2"/><path d="M292 206q36-20 72 0" ' + L + ' stroke-width="5"/>' +
        '<path d="M40 236l6-18h56l6 18z" fill="' + PAPER + '" stroke="' + INK + '" stroke-width="2"/><text x="74" y="232" text-anchor="middle" font-family="Courier New,monospace" font-weight="700" font-size="11" fill="' + INK + '">V. HALE</text>' +
        '<path d="M150 236v-8h50v8M154 228v-6h42v6M150 222h50" fill="' + PAPER + '" stroke="' + INK + '" stroke-width="1.6"/>';
    },
    /* The forgery lab. */
    lab: function () {
      return '<rect width="400" height="300" fill="#e3e9ea"/>' +
        rep(9, function (i) { return '<path d="M' + (i * 50) + ' 0v236" ' + T + ' opacity=".22"/>'; }) + rep(5, function (i) { return '<path d="M0 ' + (i * 50 + 36) + 'h400" ' + T + ' opacity=".22"/>'; }) +
        '<path d="M20 132h200" ' + L + ' stroke-width="3"/><path d="M34 132v14M206 132v14" ' + L + '/>' +
        '<path d="M40 132v-32h-5v-8h22v8h-5v32z" fill="' + COOL + '" stroke="' + INK + '" stroke-width="2"/>' +
        '<path d="M72 132l10-26v-16h-4v-6h20v6h-4v16l10 26z" fill="' + WARM + '" stroke="' + INK + '" stroke-width="2"/>' +
        '<rect x="116" y="96" width="26" height="36" rx="3" fill="' + PAPER + '" stroke="' + INK + '" stroke-width="2"/><rect x="116" y="108" width="26" height="12" fill="' + RED + '"/><path d="M122 96v-8h14v8" ' + L + '/>' +
        '<circle cx="176" cy="112" r="20" fill="' + COOL + '" stroke="' + INK + '" stroke-width="2"/><path d="M170 92v-12h12v12" ' + L + '/>' +
        '<path d="M300 0v52" ' + L + '/><path d="M270 82q30-44 60 0z" fill="' + INK + '"/><polygon points="276,82 324,82 372,236 228,236" fill="#fff" opacity=".4"/>' +
        '<rect x="0" y="236" width="400" height="64" fill="#cfd6d8"/><path d="M0 236h400" ' + L + ' stroke-width="3"/>' +
        '<path d="M286 236h68M296 236v-8h48v8M320 228v-22" ' + L + ' stroke-width="3"/>' +
        '<path d="M314 206l28-52 12 6-28 52z" fill="' + COOL2 + '" stroke="' + INK + '" stroke-width="2.5"/><path d="M300 206h40" ' + L + ' stroke-width="4"/><path d="M344 150l10-18 10 5-10 18z" fill="' + INK + '"/>' +
        '<circle cx="84" cy="204" r="24" fill="#fff" opacity=".6" stroke="' + INK + '" stroke-width="3"/><path d="M102 220l30 22" ' + L + ' stroke-width="6"/>';
    },
    /* The alley by the stage door. */
    stagedoor: function () {
      return '<rect width="400" height="300" fill="#dcd3c2"/>' + bricks(0, 14, 400, 240, 12) +
        '<path d="M22 0v262M30 0v262M18 90h16M18 180h16" ' + L + '/>' +
        '<rect x="146" y="78" width="96" height="184" fill="' + COOL2 + '" stroke="' + INK + '" stroke-width="3"/><path d="M158 92h72v70h-72zM158 176h72v72h-72z" ' + L + '/><circle cx="228" cy="170" r="4" fill="' + INK + '"/>' +
        '<rect x="150" y="48" width="88" height="22" fill="' + INK + '"/><text x="194" y="64" text-anchor="middle" font-family="Courier New,monospace" font-weight="700" font-size="12" fill="' + PAPER + '">STAGE DOOR</text>' +
        '<path d="M262 60h16" ' + L + '/><path d="M270 60l-12 16h24z" fill="' + INK + '"/><polygon points="258,76 282,76 318,262 222,262" fill="#fff6c8" opacity=".4"/>' +
        '<rect x="50" y="96" width="70" height="98" fill="' + PAPER + '" stroke="' + INK + '" stroke-width="2" transform="rotate(-2 85 145)"/>' +
        '<g transform="rotate(-2 85 145)"><rect x="50" y="96" width="70" height="22" fill="' + RED + '"/><text x="85" y="112" text-anchor="middle" font-family="Courier New,monospace" font-weight="700" font-size="11" fill="#fff">TONIGHT</text>' +
        '<text x="85" y="140" text-anchor="middle" font-family="Georgia,serif" font-weight="700" font-size="13" fill="' + INK + '">MIRA</text><text x="85" y="156" text-anchor="middle" font-family="Georgia,serif" font-size="9" fill="' + INK + '">CASTELLAN</text><path d="M62 170h46M70 180h30" ' + T + '/></g>' +
        '<path d="M292 200h60l-6 62h-48z" fill="' + COOL + '" stroke="' + INK + '" stroke-width="2.5"/><path d="M286 192l70-12 2 10-70 12z" fill="' + COOL2 + '" stroke="' + INK + '" stroke-width="2.5"/><path d="M306 212v40M322 212v40M338 212v40" ' + T + '/>' +
        '<path d="M300 198q10-16 26-8q-8 2-12 10q10-6 20 0q-16 0-22 8z" fill="#f1dc8c" stroke="' + INK + '" stroke-width="1.6"/>' +
        '<rect x="0" y="262" width="400" height="38" fill="#b9b3a6"/><path d="M0 262h400" ' + L + '/>';
    },
    /* The concert hall stage. */
    hall: function () {
      return '<rect width="400" height="300" fill="#e7dcc4"/>' +
        '<path d="M0 34h400" ' + L + ' stroke-width="3"/><path d="M0 0h400v34q-200 34-400 0z" fill="' + WARM2 + '" stroke="' + INK + '" stroke-width="2"/>' +
        rep(13, function (i) { var x = 124 + i * 12.6, top = 96 - Math.abs(6 - i) * -6; return '<path d="M' + x + ' 206V' + (70 + Math.abs(6 - i) * 7) + '" stroke="' + INK + '" stroke-width="5" stroke-linecap="round" opacity=".5"/>'; }) +
        '<polygon points="186,34 214,34 262,214 138,214" fill="#fff" opacity=".45"/>' +
        '<path d="M0 34h84q10 90-6 180H0z" fill="' + RED + '" stroke="' + INK + '" stroke-width="2.5"/><path d="M22 40q8 90-2 172M48 40q10 90 0 172M70 40q8 90-4 172" fill="none" stroke="#7c150e" stroke-width="2"/>' +
        '<path d="M400 34h-84q-10 90 6 180h78z" fill="' + RED + '" stroke="' + INK + '" stroke-width="2.5"/><path d="M378 40q-8 90 2 172M352 40q-10 90 0 172M330 40q-8 90 4 172" fill="none" stroke="#7c150e" stroke-width="2"/>' +
        '<rect x="0" y="214" width="400" height="28" fill="' + WARM2 + '"/><path d="M0 214h400M0 242h400" ' + L + '/>' +
        '<path d="M200 214v-52M184 214l16-14 16 14" ' + L + '/><path d="M180 132h40l-4 30h-32z" fill="' + PAPER + '" stroke="' + INK + '" stroke-width="2"/><path d="M188 142h24M188 150h24" ' + T + '/>' +
        '<path d="M244 214v-26h26v26M244 188v-26" ' + L + '/><path d="M250 186q-6-10 4-14q-4-8 6-10q8 2 6 10q8 4 2 14z" fill="' + WARM2 + '" stroke="' + INK + '" stroke-width="1.8"/><path d="M260 162v-18" ' + L + '/>' +
        '<rect x="0" y="242" width="400" height="58" fill="#3a4654"/>' +
        rep(9, function (i) { return '<path d="M' + (4 + i * 46) + ' 300v-30q0-14 16-14t16 14v30z" fill="' + INK + '" stroke="#5b6876" stroke-width="1.5"/>'; });
    }
  };

  /* ═════════════ art: ink portraits ═════════════ */

  var HEAD = 'M27 46C27 25 38 17 50 17S73 25 73 46C73 62 65 76 50 78C35 76 27 62 27 46Z';
  function sweat(x, y) { return '<path d="M' + x + ' ' + y + 'q-4 7 0 9.5q4-2.5 0-9.5z" fill="' + COOL + '" stroke="' + INK + '" stroke-width="1.2"/>'; }

  var people = {
    sam: {
      body: '<path d="M6 120Q8 94 34 88L50 100 66 88Q92 94 94 120Z" fill="' + WARM2 + '" stroke="' + INK + '" stroke-width="2.5" stroke-linejoin="round"/>' +
            '<path d="M34 88l-6-10 14 4M66 88l6-10-14 4M50 100v20M40 108l-8 12M60 108l8 12" ' + L + '/>',
      hair: '<path d="M25 44C21 25 34 11 50 12C67 11 79 25 75 44C73 36 70 31 65 28C60 32 53 27 47 30C41 27 35 31 31 35C28 38 27 41 25 44Z" fill="' + INK + '"/>' +
            '<path d="M44 12l-3-6M52 11l2-7M60 13l5-5" ' + L + '/>',
      extra: '<path d="M38 70q12 9 24 0" ' + T + '/><path d="M36 52q5 3 10 0M54 52q5 3 10 0" ' + T + '/>'
    },
    victor: {
      body: '<path d="M6 120Q8 94 36 88H64Q92 94 94 120Z" fill="' + INK + '" stroke="' + INK + '" stroke-width="2.5"/>' +
            '<path d="M40 88L50 108 60 88Z" fill="' + PAPER + '" stroke="' + INK + '" stroke-width="1.5"/>' +
            '<path d="M50 91L38 85V97ZM50 91L62 85V97Z" fill="' + RED + '" stroke="' + INK + '" stroke-width="1.5" stroke-linejoin="round"/><circle cx="50" cy="91" r="3" fill="' + RED + '" stroke="' + INK + '" stroke-width="1.5"/>',
      hair: '<path d="M26 43C23 24 36 12 52 12C67 12 77 24 74 43C70 30 62 23 52 24C42 23 34 26 30 32C28 36 27 39 26 43Z" fill="' + INK + '"/><path d="M40 17q10-4 22 2" fill="none" stroke="' + PAPER + '" stroke-width="1.6" stroke-linecap="round"/>',
      extra: '<path d="M50 62C44 59 38 61 35 65C41 65 46 66 50 64C54 66 59 65 65 65C62 61 56 59 50 62Z" fill="' + INK + '"/>',
      mouthY: 3
    },
    whitlock: {
      back: '<path d="M21 74C16 40 26 11 50 11S84 40 79 74H68C74 52 70 30 50 28C30 30 26 52 32 74Z" fill="' + INK + '"/>',
      body: '<path d="M6 120Q8 94 36 88H64Q92 94 94 120Z" fill="' + COOL + '" stroke="' + INK + '" stroke-width="2.5"/><path d="M38 88L50 106 62 88" ' + L + '/>',
      hair: '<path d="M27 42C32 25 60 22 73 40C62 32 40 32 27 42Z" fill="' + INK + '"/>',
      extra: '<circle cx="41" cy="48" r="7.500" fill="none" stroke="' + INK + '" stroke-width="2"/><circle cx="59" cy="48" r="7.500" fill="none" stroke="' + INK + '" stroke-width="2"/><path d="M48.500 48h3" ' + L + '/>'
    },
    desk: {
      body: '<path d="M6 120Q8 94 36 88H64Q92 94 94 120Z" fill="' + WARM + '" stroke="' + INK + '" stroke-width="2.5"/><path d="M40 88q10 12 20 0" ' + L + '/>',
      hair: '<circle cx="50" cy="9" r="8" fill="' + INK + '"/><path d="M26 44C23 24 36 13 50 13S77 24 74 44C70 32 62 26 50 26S30 32 26 44Z" fill="' + INK + '"/>',
      extra: '<path d="M25 46C25 12 75 12 75 46" fill="none" stroke="' + INK + '" stroke-width="3.5"/><rect x="20" y="42" width="8" height="14" rx="3" fill="' + INK + '"/><path d="M24 56Q26 72 42 71" ' + L + '/><circle cx="43" cy="71" r="2.500" fill="' + INK + '"/>'
    },
    nair: {
      body: '<path d="M6 120Q8 94 36 88H64Q92 94 94 120Z" fill="' + INK + '" stroke="' + INK + '" stroke-width="2.5"/><path d="M42 88L50 100 58 88" fill="none" stroke="' + PAPER + '" stroke-width="1.6"/>' +
            '<path d="M14 100l16-6M86 100l-16-6" stroke="' + PAPER + '" stroke-width="2" stroke-linecap="round"/><circle cx="50" cy="110" r="2" fill="' + PAPER + '"/>',
      hair: '<path d="M24 40C22 6 78 6 76 40Z" fill="' + INK + '"/><path d="M19 40H81" stroke="' + INK + '" stroke-width="4.5" stroke-linecap="round"/><circle cx="50" cy="8" r="3.500" fill="' + INK + '"/>' +
            '<path d="M50 20l2.600 5.500 6 .7-4.500 4 1.300 6-5.400-3.100-5.400 3.100 1.300-6-4.500-4 6-.7z" fill="' + PAPER + '"/>',
      extra: '<path d="M28 44Q30 76 50 80Q70 76 72 44" ' + T + '/>'
    },
    dominic: {
      back: '<path d="M22 66C18 34 30 10 52 11C74 11 82 34 78 66L70 70C72 52 70 36 50 30C34 36 30 52 30 68Z" fill="' + INK + '"/>',
      body: '<path d="M6 120Q8 94 36 88H64Q92 94 94 120Z" fill="' + INK + '" stroke="' + INK + '" stroke-width="2.5"/><path d="M40 88L50 104 60 88Z" fill="' + PAPER + '"/>' +
            '<path d="M50 91L40 86V96ZM50 91L60 86V96Z" fill="' + PAPER + '" stroke="' + INK + '" stroke-width="1.4"/>',
      hair: '<path d="M26 44C24 21 44 10 58 14C72 17 78 31 75 50C73 40 68 34 60 31C52 40 38 44 31 56C28 52 26 48 26 44Z" fill="' + INK + '"/>',
      extra: ''
    },
    beatrice: {
      body: '<path d="M6 120Q8 94 36 88H64Q92 94 94 120Z" fill="' + WARM + '" stroke="' + INK + '" stroke-width="2.5"/><path d="M38 88L50 102 62 88" ' + L + '/>' +
            '<path d="M42 92L52 112M58 92L52 112" stroke="' + RED + '" stroke-width="1.8" fill="none"/><rect x="45" y="108" width="14" height="10" fill="' + PAPER + '" stroke="' + INK + '" stroke-width="1.5"/>',
      hair: '<circle cx="50" cy="9" r="9" fill="' + INK + '"/><path d="M26 44C22 24 36 12 50 12S78 24 74 44C71 32 62 24 50 24S29 32 26 44Z" fill="' + INK + '"/>',
      extra: '<rect x="33" y="43" width="15" height="10" rx="2" fill="none" stroke="' + INK + '" stroke-width="2"/><rect x="52" y="43" width="15" height="10" rx="2" fill="none" stroke="' + INK + '" stroke-width="2"/><path d="M48 47h4" ' + L + '/>'
    }
  };

  var moods = {
    neutral: { brows: 'M35 41L46 40M54 40L65 41', eyes: 'dot', mouth: 'M43 67q7 3 14 0' },
    pleased: { brows: 'M35 39L46 38M54 38L65 39', eyes: 'arc', mouth: 'M41 65q9 8 18 0' },
    annoyed: { brows: 'M35 38L46 42M54 42L65 38', eyes: 'lid', mouth: 'M44 69L57 67' },
    smug: { brows: 'M35 41L46 41M54 37L65 39', eyes: 'lid', mouth: 'M43 68q8 4 15-4' },
    nervous: { brows: 'M35 42L46 38M54 38L65 42', eyes: 'wide', mouth: 'M42 68q3.500-3 7 0t7 0', sweat: 1 },
    sweating: { brows: 'M35 43L46 37M54 37L65 43', eyes: 'wide', mouth: 'M42 69q3.500-4 7 0t7 0', sweat: 2 },
    cracked: { brows: 'M34 40L45 33M55 33L66 40', eyes: 'pop', mouth: 'open', sweat: 3 }
  };

  function eyes(kind) {
    var out = '';
    [41, 59].forEach(function (x) {
      if (kind === 'arc') out += '<path d="M' + (x - 4) + ' 49q4-5 8 0" ' + L + '/>';
      else if (kind === 'lid') out += '<circle cx="' + x + '" cy="49" r="2.200" fill="' + INK + '"/><path d="M' + (x - 5) + ' 46.500h10" ' + L + '/>';
      else if (kind === 'wide') out += '<circle cx="' + x + '" cy="48" r="4" fill="' + PAPER + '" stroke="' + INK + '" stroke-width="1.5"/><circle cx="' + x + '" cy="48.500" r="1.800" fill="' + INK + '"/>';
      else if (kind === 'pop') out += '<circle cx="' + x + '" cy="47" r="5.500" fill="' + PAPER + '" stroke="' + INK + '" stroke-width="1.8"/><circle cx="' + x + '" cy="47" r="1.600" fill="' + INK + '"/>';
      else out += '<circle cx="' + x + '" cy="48" r="2.300" fill="' + INK + '"/>';
    });
    return out;
  }

  /** An ink bust of a cast member. `mood` changes brows, eyes, mouth and sweat. */
  function portrait(id, mood) {
    var p = people[id] || people.sam, m = moods[mood] || moods.neutral, dy = p.mouthY || 0;
    var mouth = m.mouth === 'open'
      ? '<ellipse cx="50" cy="' + (69 + dy) + '" rx="6" ry="5" fill="' + INK + '"/>'
      : '<path d="' + m.mouth + '" ' + L + ' transform="translate(0 ' + dy + ')"/>';
    var drops = '';
    if (m.sweat >= 1) drops += sweat(78, 30);
    if (m.sweat >= 2) drops += sweat(21, 36);
    if (m.sweat >= 3) drops += sweat(84, 46) + sweat(14, 52);
    return '<svg class="portrait mood-' + (mood || 'neutral') + '" viewBox="0 0 100 120" aria-hidden="true">' +
      (p.back || '') + p.body +
      '<rect x="42" y="72" width="16" height="20" fill="' + PAPER + '" stroke="' + INK + '" stroke-width="2.2"/>' +
      '<ellipse cx="26" cy="50" rx="4" ry="6" fill="' + PAPER + '" stroke="' + INK + '" stroke-width="2"/><ellipse cx="74" cy="50" rx="4" ry="6" fill="' + PAPER + '" stroke="' + INK + '" stroke-width="2"/>' +
      '<path d="' + HEAD + '" fill="' + PAPER + '" stroke="' + INK + '" stroke-width="2.5"/>' +
      '<path d="M58 22C70 28 73 40 72 50C71 62 64 73 52 77C62 68 66 56 65 44C64 34 62 28 58 22Z" fill="' + COOL + '" opacity=".7"/>' +
      p.hair + '<path d="' + m.brows + '" ' + L + ' stroke-width="2.4"/>' + eyes(m.eyes) +
      '<path d="M50 51q-3 8-1 10q2 1 4 0" ' + L + ' stroke-width="1.8"/>' + mouth + (p.extra || '') + drops + '</svg>';
  }

  CF.art = {
    place: function (id) {
      var fn = places[id] || places.unit9;
      return '<svg viewBox="0 0 400 300" preserveAspectRatio="xMidYMid slice" aria-hidden="true">' + fn() + '</svg>';
    },
    hasPortrait: function (id) { return !!people[id]; },
    portrait: portrait
  };
})();
