"""Read-only checks for the team documentation; does not simulate the CPU."""
import hashlib
import json
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[2]
DOC = ROOT / 'document'


def check():
    abi = json.loads((DOC / 'interface-v1.json').read_text(encoding='utf-8'))
    base = json.loads((DOC / 'baseline.json').read_text(encoding='utf-8'))
    assert abi['version'] == 'TEAM-ABI-1.0'
    for key, total in [('exception_fields', 49), ('metadata_fields', 164)]:
        cursor = total
        for field in abi[key]:
            cursor -= field['width']
            assert field['lsb'] == cursor, field
            assert field['msb'] == cursor + field['width'] - 1, field
        assert cursor == 0
    for doc in DOC.rglob('*.md'):
        content = doc.read_text(encoding='utf-8')
        assert content.count('```') % 2 == 0, doc
        for target in re.findall(r'\]\(([^)]+)\)', content):
            if '://' in target or target.startswith('#'):
                continue
            assert (doc.parent / target.split('#')[0]).exists(), (doc, target)
    for item in base['repository_files']:
        raw = subprocess.check_output(
            ['git', 'show', f"{base['base_commit']}:{item['path']}"], cwd=ROOT)
        digest = hashlib.sha256(raw.replace(b'\r\n', b'\n')).hexdigest().upper()
        assert digest == item['sha256_git_lf'], item['path']
    print('PASS: documentation links/fences, ABI bit layout, fixed baseline hashes.')
    print('No RTL compile, functional simulation, bit build, or online test performed.')


if __name__ == '__main__':
    check()
