"""Budowa natywnego .app Universal, bez pobierania bibliotek: python3 tools/build.py.
Wymaga macOS i Xcode Command Line Tools ze Swift 5.10 / SDK macOS 14 lub nowszym.
"""
from pathlib import Path
import os
import plistlib
import shutil
import subprocess
import sys

BASE = Path(__file__).resolve().parents[1]
VERSION = '1.0.1'
BUILD = BASE / 'build' / VERSION
APP = BASE / 'dist' / f'Pstryk-{VERSION}' / 'Pstryk.app'
BUILD.mkdir(parents=True, exist_ok=True)
env = os.environ.copy()
env['CLANG_MODULE_CACHE_PATH'] = str(BUILD / 'module-cache')
env['SWIFT_MODULECACHE_PATH'] = str(BUILD / 'module-cache')

def run(*args):
    subprocess.run([str(x) for x in args], cwd=BASE, env=env, check=True)

sdk = subprocess.check_output(['xcrun', '--show-sdk-path'], text=True).strip()
resume = '--resume' in sys.argv
if APP.exists() and (not resume or (APP/'Contents/Info.plist').exists()):
    raise SystemExit('Ta .app już istnieje. Zachowaj ją i zmień wersję przed kolejnym wydaniem.')
sources = sorted((BASE / 'src').glob('*.swift'))
for arch in ('arm64', 'x86_64'):
    binary = BUILD/f'Pstryk-{arch}'
    if not resume or not binary.exists() or binary.stat().st_mtime < max(p.stat().st_mtime for p in sources):
        run('xcrun', 'swiftc', '-O', '-whole-module-optimization', '-sdk', sdk,
            '-target', f'{arch}-apple-macos14.0', '-module-cache-path', BUILD/'module-cache',
            *sources, '-o', binary)
(APP/'Contents/MacOS').mkdir(parents=True, exist_ok=True)
(APP/'Contents/Resources').mkdir(exist_ok=True)
run('lipo', '-create', BUILD/'Pstryk-arm64', BUILD/'Pstryk-x86_64',
    '-output', APP/'Contents/MacOS/Pstryk')
run('xcrun', 'swiftc', '-parse-as-library', '-O', '-module-cache-path', BUILD/'module-cache',
    BASE/'src/CameraIcon.swift', BASE/'tools/make_icon.swift', '-o', BUILD/'make-icon')
iconset = BASE/'assets/Pstryk.iconset'
run(BUILD/'make-icon', iconset)
if not resume or not (BASE/'assets/Pstryk.icns').exists():
    run('iconutil', '-c', 'icns', iconset, '-o', BASE/'assets/Pstryk.icns')
shutil.copy2(iconset/'icon_512x512@2x.png', BASE/'assets/Pstryk.png')
shutil.copy2(BASE/'assets/Pstryk.icns', APP/'Contents/Resources/Pstryk.icns')
info = {
    'CFBundleName': 'Pstryk', 'CFBundleDisplayName': 'Pstryk',
    'CFBundleIdentifier': 'local.pstryk.menubar', 'CFBundleExecutable': 'Pstryk',
    'CFBundlePackageType': 'APPL', 'CFBundleVersion': VERSION,
    'CFBundleShortVersionString': VERSION, 'LSMinimumSystemVersion': '14.0',
    'LSUIElement': True, 'LSMultipleInstancesProhibited': True,
    'NSHighResolutionCapable': True, 'CFBundleIconFile': 'Pstryk',
    'NSScreenCaptureUsageDescription': 'Pstryk zapisuje cały ekran jako PNG w folderze Pobrane po kliknięciu aparatu.',
    'NSDownloadsFolderUsageDescription': 'Zapisywanie zrzutów ekranu w folderze Pobrane.',
    'LSApplicationCategoryType': 'public.app-category.utilities',
}
(APP/'Contents/Info.plist').write_bytes(plistlib.dumps(info))
for name in ('INSTALACJA.txt', 'LICENSE.txt'):
    shutil.copy2(BASE/name, APP/'Contents/Resources'/name)
identity = os.environ.get('PSTRYK_SIGN_IDENTITY', '-')
options = ['--options', 'runtime', '--timestamp'] if identity != '-' else []
run('codesign', '--force', '--sign', identity, *options, '--identifier', 'local.pstryk.menubar', APP)
run('codesign', '--verify', '--deep', '--strict', APP)
print('Gotowa aplikacja:', APP)
