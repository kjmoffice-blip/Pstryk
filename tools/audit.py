"""Kontrola binariów i podpisu .app. Nie wymaga modułów pip."""
from pathlib import Path
import json
import plistlib
import re
import subprocess
import sys

BASE = Path(__file__).resolve().parents[1]
app = Path(sys.argv[1]).resolve()
output = Path(sys.argv[2])
binary = app/'Contents/MacOS/Pstryk'
def read(*args):
    return subprocess.check_output([str(a) for a in args], text=True, stderr=subprocess.STDOUT)
archs = read('lipo', '-archs', binary).split()
load = read('otool', '-l', binary)
minimum = re.findall(r'\bminos (\S+)', load)
deps = read('otool', '-L', binary)
libraries = re.findall(r'^\s+(.*?) \(compatibility', deps, re.M)
unexpected = [name for name in libraries if not name.startswith(('/usr/lib/', '/System/Library/', '@rpath/libswift'))]
signature = subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], capture_output=True, text=True)
info = plistlib.loads((app/'Contents/Info.plist').read_bytes())
resources = [str(p.relative_to(app)) for p in app.rglob('*') if p.is_file()]
report = {'app': str(app), 'architectures': archs, 'minos': minimum,
          'libraries': libraries, 'unexpectedDependencies': unexpected,
          'signatureValid': signature.returncode == 0,
          'signatureDetails': subprocess.run(['codesign', '-dv', '--verbose=4', str(app)], capture_output=True, text=True).stderr,
          'bundle': info, 'files': resources}
report['passed'] = (set(archs) == {'arm64', 'x86_64'} and minimum == ['14.0', '14.0']
                    and not unexpected and signature.returncode == 0
                    and info['LSUIElement'] and info['LSMinimumSystemVersion'] == '14.0')
output.parent.mkdir(parents=True, exist_ok=True)
output.write_text(json.dumps(report, ensure_ascii=False, indent=2)+'\n')
print('Universal:', archs, 'minimum:', minimum, 'podpis:', signature.returncode == 0,
      'zewnętrzne zależności:', unexpected)
raise SystemExit(0 if report['passed'] else 1)
