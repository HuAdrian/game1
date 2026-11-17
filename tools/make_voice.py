"""
Generates the listening clips with ElevenLabs text-to-speech.

One mp3 per script line, named so audio[i] is script[i] spoken:
  soundcheck.mp3, wiretap_01..12, wiretap_retry_01..07, tail_01..09, tail_retry_01..05

  python3 tools/make_voice.py [name ...]     (no names: every clip)

The API key is never read from or written to any file. If ELEVENLABS_API_KEY is
set it is sent as the request header; otherwise the request goes out without
one, for a network proxy that adds it. Nothing here prints it.
"""
import json, os, sys, time, urllib.request, urllib.error

ROOT = os.path.join(os.path.dirname(__file__), '..', 'godot')
OUT = os.path.join(ROOT, 'assets', 'audio', 'voice')
MODEL = 'eleven_v4'
FORMAT = 'mp3_44100_128'
VOICES = {   # premade British voices available on every plan
    'female': 'Xb7hH8MSUJpSbSDYk0k2',  # Alice
    'male': 'onwK4e9ZLuTAKqWW03F9',    # Daniel
}
SETTINGS = {'stability': 0.5, 'similarity_boost': 0.75}


def clip_sets():
    case = json.load(open(os.path.join(ROOT, 'cases', 'missing_violinist.json'), encoding='utf-8'))
    leads = {l['id']: l['scene'] for l in case['leads']}
    w, t = leads['wiretap'], leads['tail']
    return [
        ('soundcheck', 'female', [case['soundCheck']]),
        ('wiretap', 'female', w['script']),
        ('wiretap_retry', 'female', w['retry']['script']),
        ('tail', 'male', t['script']),
        ('tail_retry', 'male', t['retry']['script']),
    ]


def clips():
    for prefix, voice, lines in clip_sets():
        for i, text in enumerate(lines):
            name = prefix if prefix == 'soundcheck' else '%s_%02d' % (prefix, i + 1)
            # neighbouring lines give the voice continuity across separate clips
            yield name, voice, text, lines[i - 1] if i > 0 else None, lines[i + 1] if i + 1 < len(lines) else None


def render(name, voice, text, prev, nxt):
    body = {'text': text, 'model_id': MODEL, 'voice_settings': SETTINGS, 'language_code': 'en'}
    if prev:
        body['previous_text'] = prev
    if nxt:
        body['next_text'] = nxt
    headers = {'Content-Type': 'application/json', 'Accept': 'audio/mpeg'}
    if os.environ.get('ELEVENLABS_API_KEY'):
        headers['xi-api-key'] = os.environ['ELEVENLABS_API_KEY']
    url = 'https://api.elevenlabs.io/v1/text-to-speech/%s?output_format=%s' % (VOICES[voice], FORMAT)
    req = urllib.request.Request(url, data=json.dumps(body).encode(), headers=headers, method='POST')
    with urllib.request.urlopen(req, timeout=120) as r:
        data = r.read()
        used = r.headers.get('x-character-count')
    if len(data) < 2000:
        raise RuntimeError('%s: response too small (%d bytes)' % (name, len(data)))
    with open(os.path.join(OUT, name + '.mp3'), 'wb') as f:
        f.write(data)
    return len(data), used


if __name__ == '__main__':
    want = set(sys.argv[1:])
    os.makedirs(OUT, exist_ok=True)
    for name, voice, text, prev, nxt in clips():
        if want and name not in want:
            continue
        try:
            size, used = render(name, voice, text, prev, nxt)
        except urllib.error.HTTPError as e:
            detail = e.read()[:300].decode('utf-8', 'replace')
            print('FAILED %s: HTTP %d %s' % (name, e.code, detail))
            sys.exit(1)
        print('%-18s %-6s %7d bytes  chars billed: %s' % (name, voice, size, used))
        time.sleep(0.4)
