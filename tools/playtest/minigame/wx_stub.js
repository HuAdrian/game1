/*
 * A stand-in `wx` for testing the game's mini game mode in a desktop browser.
 *
 * The plugin's real sdk.js runs on top of it, so the real MiniGameSDK.gd finds a
 * host and the game takes its mini game paths. It records every call, keeps
 * storage in localStorage, and plays the host keyboard: the test types through
 * window.__kb.type(text) and closes it with window.__kb.done().
 */
(function () {
  'use strict';
  var calls = window.__wxCalls = [];
  var kb = { open: false, value: '', input: [], confirm: [], complete: [] };
  var lifecycle = { show: [], hide: [], error: [] };
  function fire(list, v) { list.slice().forEach(function (f) { try { f(v); } catch (e) { console.error(e); } }); }
  function done(o, res) { if (o && o.success) o.success(res || {}); if (o && o.complete) o.complete(res || {}); }
  var store = { get: function (k) { var v = localStorage.getItem('wx:' + k); return v == null ? '' : JSON.parse(v); },
                set: function (k, v) { localStorage.setItem('wx:' + k, JSON.stringify(v)); } };
  var known = {
    getSystemInfoSync: function () { return { platform: 'devtools', windowWidth: innerWidth, windowHeight: innerHeight, pixelRatio: 1, screenWidth: innerWidth, screenHeight: innerHeight, SDKVersion: '3.9.0', language: 'en' }; },
    getWindowInfo: function () { return { windowWidth: innerWidth, windowHeight: innerHeight, pixelRatio: 1, screenWidth: innerWidth, screenHeight: innerHeight }; },
    getDeviceInfo: function () { return { platform: 'devtools', brand: 'test', model: 'harness' }; },
    getAppBaseInfo: function () { return { SDKVersion: '3.9.0', language: 'en' }; },
    onShow: function (f) { lifecycle.show.push(f); }, offShow: function () {},
    onHide: function (f) { lifecycle.hide.push(f); }, offHide: function () {},
    onError: function (f) { lifecycle.error.push(f); }, offError: function () {},
    showKeyboard: function (o) { kb.open = true; kb.value = (o && o.defaultValue) || ''; done(o); },
    hideKeyboard: function (o) { kb.open = false; done(o); },
    onKeyboardInput: function (f) { kb.input.push(f); }, offKeyboardInput: function () { kb.input = []; },
    onKeyboardConfirm: function (f) { kb.confirm.push(f); }, offKeyboardConfirm: function () { kb.confirm = []; },
    onKeyboardComplete: function (f) { kb.complete.push(f); }, offKeyboardComplete: function () { kb.complete = []; },
    setClipboardData: function (o) { window.__clipboard = o.data; done(o); },
    getStorageSync: function (k) { return store.get(k); },
    setStorageSync: function (k, v) { store.set(k, v); },
    removeStorageSync: function (k) { localStorage.removeItem('wx:' + k); },
    getStorageInfoSync: function () { return { keys: Object.keys(localStorage).filter(function (k) { return k.indexOf('wx:') === 0; }).map(function (k) { return k.slice(3); }), currentSize: 1, limitSize: 10240 }; },
  };
  window.wx = new Proxy(known, {
    get: function (t, name) {
      if (typeof name !== 'string') return undefined;
      if (name in t) return function () { calls.push(name); return t[name].apply(null, arguments); };
      // anything else: a no-op that reports success
      return function (o) { calls.push(name); done(o); };
    },
    has: function () { return true; },
  });
  window.__kb = {
    get open() { return kb.open; },
    get value() { return kb.value; },
    type: function (text) { for (var i = 0; i < text.length; i++) { kb.value += text[i]; fire(kb.input, { value: kb.value }); } },
    clear: function () { kb.value = ''; fire(kb.input, { value: '' }); },
    done: function () { fire(kb.confirm, { value: kb.value }); fire(kb.complete, { value: kb.value }); kb.open = false; },
  };
  window.__hide = function () { fire(lifecycle.hide, {}); };
  window.GameGlobal = window;
  window.__platform = 'wechat';
  window.cfTestMode = true;
})();
