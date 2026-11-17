"""
ASR check for the listening clips: transcribes each clip with ElevenLabs Scribe
and compares it with its source line after normalising numbers, letters that
are spelled out, and punctuation. Prints every clip that differs, with the diff.

  python3 tools/check_voice.py [name ...]

The API key is handled as in make_voice.py: never read from or written to a file.
"""
import difflib, json, os, re, subprocess, sys
sys.path.insert(0, os.path.dirname(__file__))
from make_voice import clips, OUT

ONES = 'zero one two three four five six seven eight nine ten eleven twelve thirteen fourteen fifteen sixteen seventeen eighteen nineteen'.split()
TENS = 'twenty thirty forty fifty sixty seventy eighty ninety'.split()


def num2words(n):
    """English words for 0..999999, enough for the numbers in these scripts."""
    if n < 20:
        return ONES[n]
    if n < 100:
        return TENS[n // 10 - 2] + ('' if n % 10 == 0 else ' ' + ONES[n % 10])
    if n < 1000:
        return ONES[n // 100] + ' hundred' + ('' if n % 100 == 0 else ' and ' + num2words(n % 100))
    return num2words(n // 1000) + ' thousand' + ('' if n % 1000 == 0 else ' ' + num2words(n % 1000))


def transcribe(path):
    cmd = ['curl', '-sS', '-X', 'POST', 'https://api.elevenlabs.io/v1/speech-to-text',
           '-F', 'model_id=scribe_v1', '-F', 'language_code=en', '-F', 'tag_audio_events=false', '-F', 'file=@' + path]
    if os.environ.get('ELEVENLABS_API_KEY'):
        cmd[3:3] = ['-H', 'xi-api-key: ' + os.environ['ELEVENLABS_API_KEY']]
    return json.loads(subprocess.run(cmd, capture_output=True, text=True, check=True).stdout)['text']


def norm(s):
    s = s.lower().replace('’', "'").replace('£', ' pounds ')
    s = re.sub(r'\bp\.?\s?m\b\.?', ' pm ', s)
    s = re.sub(r'\bdouble[- ]u\b', ' w ', s)
    s = re.sub(r'(\d+):(\d\d)', lambda m: ' %s %s ' % (m.group(1), 'o clock' if m.group(2) == '00' else m.group(2)), s)
    s = re.sub(r'\d+', lambda m: ' ' + num2words(int(m.group())) + ' ', s)
    s = re.sub(r"[^a-z0-9' ]", ' ', s).replace("'", '')
    return ''.join(s.split())   # compare as one letter stream: spelling and spacing no longer matter


if __name__ == '__main__':
    want = set(sys.argv[1:])
    bad = 0
    for name, _, text, _, _ in clips():
        if want and name not in want:
            continue
        heard = transcribe(os.path.join(OUT, name + '.mp3'))
        a, b = norm(text), norm(heard)
        if a == b:
            print('ok   ', name)
            continue
        bad += 1
        sm = difflib.SequenceMatcher(None, a, b)
        diffs = ['%s %r -> %r' % (op, a[i1:i2], b[j1:j2]) for op, i1, i2, j1, j2 in sm.get_opcodes() if op != 'equal']
        print('DIFF ', name, '| similarity %.3f' % sm.ratio())
        print('      line :', text)
        print('      heard:', heard)
        print('      ', '; '.join(diffs))
    print('clips differing:', bad)
