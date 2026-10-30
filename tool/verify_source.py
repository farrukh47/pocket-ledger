"""Available-environment checks; this does not compile or run Flutter."""
from pathlib import Path
import re
import sqlite3
import xml.etree.ElementTree as ET
import yaml

root = Path(__file__).resolve().parents[1]
source = (root / 'lib/data/ledger_repository.dart').read_text()
schema = re.search(r"await db.execute\('''(CREATE TABLE.*?)'''\)", source, re.S).group(1)
with sqlite3.connect(':memory:') as db:
    db.execute(schema)
    for statement in re.findall(r"await db.execute\('(CREATE INDEX.*?)'\)", source):
        db.execute(statement)
    insert = 'INSERT INTO entries(kind,amount_minor,category,date,note) VALUES(?,?,?,?,?)'
    for day in ['2026-09-30', '2026-10-01', '2026-10-31', '2026-11-01']:
        db.execute(insert, ('expense', 100, 'Food', day, ''))
    result = db.execute('SELECT SUM(amount_minor) FROM entries WHERE date >= ? AND date < ?',
                        ('2026-10-01', '2026-11-01')).fetchone()[0]
    assert result == 200
    for invalid in [-1, 0, 1000000000000, 1.1]:
        try:
            db.execute(insert, ('expense', invalid, 'Food', '2026-10-30', ''))
        except sqlite3.IntegrityError:
            pass
        else:
            raise AssertionError(f'Invalid amount accepted: {invalid}')
    history = re.search(r"db.rawQuery\('''(.*?)'''", source, re.S).group(1)
    rows = db.execute(history, ('2026-05-01', '2026-11-01')).fetchall()
    assert rows == [('2026-10', 0, 200), ('2026-09', 0, 100)]
for file in root.rglob('*.yaml'):
    yaml.safe_load(file.read_text())
for file in root.rglob('*.yml'):
    yaml.safe_load(file.read_text())
ET.parse(root / 'android/app/src/main/AndroidManifest.xml')
print('PASS: embedded SQLite schema, constraints, month bounds/history, YAML and XML')
try:
    from tree_sitter import Language, Parser
    import tree_sitter_dart
except ImportError:
    print('SKIP: Dart grammar parser unavailable')
else:
    parser = Parser(Language(tree_sitter_dart.language()))
    for file in root.rglob('*.dart'):
        tree = parser.parse(file.read_bytes())
        assert not tree.root_node.has_error, str(file)
    print('PASS: all Dart source/test files parse (not a Dart type check)')
