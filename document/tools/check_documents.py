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
    permissions = json.loads((DOC / 'csr-registers-v1.json').read_text(encoding='utf-8'))
    assert permissions['interface_version'] == abi['version']
    regs = {r['name']: r for r in permissions['registers']}
    expected = {
        'CRMD': (0x000, 0x7, 0), 'PRMD': (0x001, 0x7, 0),
        'ESTAT': (0x005, 0x3, 0), 'ERA': (0x006, 0xffffffff, 0),
        'EENTRY': (0x00c, 0xffffffc0, 0),
        'ECFG': (0x004, 0x1bff, 0), 'BADV': (0x007, 0xffffffff, 0),
        'TID': (0x040, 0xffffffff, 0), 'TCFG': (0x041, 0xffffffff, 0),
        'TVAL': (0x042, 0, 0), 'TICLR': (0x044, 0, 1),
    }
    expected.update({f'SAVE{i}': (0x030 + i, 0xffffffff, 0) for i in range(4)})
    assert set(regs) == set(expected)
    assert len(regs) == len(permissions['registers'])
    for name, values in expected.items():
        record = regs[name]
        assert tuple(int(record[k], 16) for k in (
            'address', 'software_rw_mask', 'software_w1_mask')) == values, name
    ex9 = (DOC / '04-ex9-design.md').read_text(encoding='utf-8')
    badv_row = next(line for line in ex9.splitlines() if line.startswith('| BADV |'))
    ecfg_row = next(line for line in ex9.splitlines() if line.startswith('| ECFG |'))
    assert '32位可读写' in badv_row and '只读' not in badv_row
    assert 'LIE[12:11]' in ecfg_row and '0x00001bff' in ecfg_row
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
    print('PASS: documentation links/fences, ABI bit layout, fixed baseline hashes, CSR permission regression checks.')
    print('No RTL compile, functional simulation, bit build, or online test performed.')


if __name__ == '__main__':
    check()
