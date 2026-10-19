"""Consistent online SQLite backup; retain seven daily copies in the private data directory."""
from datetime import datetime, timezone
from pathlib import Path
import sqlite3

data = Path('/var/lib/voxel-kingdom')
folder = data / 'backups'
folder.mkdir(mode=0o700, exist_ok=True)
destination = folder / ('world-' + datetime.now(timezone.utc).strftime('%Y%m%d-%H%M%S') + '.sqlite3')
source = sqlite3.connect(f'file:{data / "world.sqlite3"}?mode=ro', uri=True)
target = sqlite3.connect(destination)
try:
    source.backup(target)
    assert target.execute('PRAGMA integrity_check').fetchone()[0] == 'ok'
finally:
    target.close()
    source.close()
for old in sorted(folder.glob('world-*.sqlite3'), reverse=True)[7:]:
    old.unlink()
print('Backup completed:', destination.name)
