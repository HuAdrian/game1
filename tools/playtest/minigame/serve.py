"""
Serves a Web export of the MiniGame preset with the mini game test harness.

  python3 serve.py <web-export-dir> <port>

/index.html gets the wx stand-in and the plugin's real sdk.js (from the
project's addon) injected before the engine starts; /sdk/... serves the
plugin's JS modules, resolving their extensionless imports.
"""
import http.server, os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
SDK = os.path.join(HERE, '../../../godot/addons/godot_mini_game/templates/common/js')
ROOT = os.path.abspath(sys.argv[1])
INJECT = ('<script src="/harness/wx_stub.js"></script>\n'
          '<script>window.__bridgeReady = new Promise(r => window.__bridgeReadyResolve = r);</script>\n'
          '<script type="module" src="/harness/bridge.mjs"></script>\n')


class H(http.server.SimpleHTTPRequestHandler):
    def translate_path(self, path):
        path = path.split('?')[0]
        if path.startswith('/harness/'):
            return os.path.join(HERE, path[len('/harness/'):])
        if path.startswith('/harness/sdk/') or path.startswith('/sdk/'):
            rel = path.split('/sdk/', 1)[1]
            p = os.path.join(SDK, rel)
            return p if os.path.exists(p) or p.endswith('.js') else p + '.js'
        return os.path.join(ROOT, path.lstrip('/'))

    def end_headers(self):
        self.send_header('Cache-Control', 'no-store')
        super().end_headers()

    def do_GET(self):
        p = self.path.split('?')[0]
        if p.startswith('/harness/sdk/'):
            rel = p[len('/harness/sdk/'):]
            f = os.path.join(SDK, rel)
            if not os.path.exists(f):
                f += '.js'
            body = open(f, 'rb').read()
            self.send_response(200); self.send_header('Content-Type', 'text/javascript'); self.send_header('Content-Length', str(len(body))); self.end_headers()
            self.wfile.write(body); return
        if p in ('/', '/index.html'):
            html = open(os.path.join(ROOT, 'index.html'), encoding='utf-8').read()
            html = html.replace('<script src="index.js"></script>', INJECT + '<script src="index.js"></script>', 1)
            html = html.replace('engine.startGame({', 'window.__bridgeReady.then(() => engine.startGame({', 1)
            # close the wrapper after the startGame(...) call's own closing
            i = html.index('window.__bridgeReady.then(() => engine.startGame({')
            j = html.index('}).then(', i)
            html = html[:j] + '})).then(' + html[j + len('}).then('):]
            body = html.encode()
            self.send_response(200); self.send_header('Content-Type', 'text/html'); self.send_header('Content-Length', str(len(body))); self.end_headers()
            self.wfile.write(body); return
        return super().do_GET()


http.server.ThreadingHTTPServer(('127.0.0.1', int(sys.argv[2])), H).serve_forever()
