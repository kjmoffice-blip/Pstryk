"""Pakowanie: python3 tools/package.py; po testach DMG: --sources.
Nie nadpisuje wcześniejszych wydań. ZIP dla użytkownika zawiera .app i instrukcję.
"""
from pathlib import Path
import hashlib
import json
import shutil
import subprocess
import sys
import zipfile

BASE = Path(__file__).resolve().parents[1]
VERSION = '1.0.1'
DIST = BASE/'dist'
APP = DIST/f'Pstryk-{VERSION}/Pstryk.app'
BUILD = BASE/'build'/VERSION
def run(*args):
    subprocess.run([str(a) for a in args], check=True)

if '--sources' in sys.argv:
    archive = DIST/f'Pstryk-{VERSION}-zrodla.zip'
    paths = [p for p in BASE.rglob('*') if p.is_file()
             and p.relative_to(BASE).parts[0] in ('src', 'tools', 'assets')
             and '__pycache__' not in p.parts and p.suffix != '.pyc']
    paths += [BASE/n for n in ('README.md', 'INSTALACJA.txt', 'LICENSE.txt', 'RIGHTS.md', 'LICENSE', '.gitignore')]
    manifest = {str(p.relative_to(BASE)):hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(set(paths))}
    with zipfile.ZipFile(archive,'x',compression=zipfile.ZIP_DEFLATED) as z:
        for relative in manifest:
            z.write(BASE/relative,f'Pstryk-{VERSION}/{relative}')
        z.writestr(f'Pstryk-{VERSION}/MANIFEST_SHA256.json',json.dumps(manifest,indent=2)+'\n')
    with zipfile.ZipFile(archive) as z:
        assert z.testzip() is None
        for relative,digest in manifest.items():
            assert hashlib.sha256(z.read(f'Pstryk-{VERSION}/{relative}')).hexdigest() == digest
    print('Źródła i manifest sprawdzone:', archive)
else:
    zip_path = DIST/f'Pstryk-{VERSION}-Mac-Universal.zip'
    dmg = DIST/f'Pstryk-{VERSION}-Universal.dmg'
    if dmg.exists():
        raise SystemExit('To wydanie już istnieje. Zachowaj je i zmień numer wersji.')
    stage = BUILD/'package-zip'
    stage.mkdir(parents=True,exist_ok=True)
    run('ditto',APP,stage/'Pstryk.app')
    shutil.copy2(BASE/'INSTALACJA.txt',stage/'INSTALACJA.txt')
    run('ditto','-c','-k','--sequesterRsrc',stage,zip_path)
    from dmgbuild import build_dmg
    build_dmg(str(dmg), f'Pstryk {VERSION} Installer', settings={
        'files':[str(APP)],'symlinks':{'Applications':'/Applications'},
        'background':str(BASE/'assets/installer-background.png'),
        'window_rect':((200,160),(620,380)),
        'icon_locations':{'Pstryk.app':(150,150),'Applications':(460,150)},
        'icon_size':96,'text_size':14,'show_status_bar':False,'show_tab_view':False,
        'show_pathbar':False,'show_toolbar':False,'show_sidebar':False,
        'default_view':'icon-view','format':'UDZO','filesystem':'HFS+'})
    import os
    identity = os.environ.get('PSTRYK_SIGN_IDENTITY')
    if identity:
        run('codesign','--sign',identity,'--timestamp',dmg)
        run('codesign','--verify','--strict',dmg)
    print('ZIP aplikacji oraz DMG gotowe.')

checksums = {p.name:hashlib.sha256(p.read_bytes()).hexdigest()
             for p in DIST.iterdir() if p.is_file() and p.suffix in ('.zip','.dmg')}
(DIST/f'SHA256-{VERSION}.txt').write_text(''.join(f'{digest}  {name}\n' for name,digest in sorted(checksums.items())))
