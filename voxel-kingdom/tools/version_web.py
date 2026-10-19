"""Content-address Godot runtime assets; keep HTML current and URLs cacheable."""
import gzip
import hashlib
import json
from pathlib import Path
import re
import shutil

root=Path(__file__).resolve().parents[1]
folder=root/'build/client-web'
files=sorted(p for p in folder.glob('index.*') if p.suffix not in ('.html','.gz'))
digest=hashlib.sha256()
for path in files:
    digest.update(path.name.encode());digest.update(path.read_bytes())
version=digest.hexdigest()[:20]
target=folder/'assets'/version
target.mkdir(parents=True,exist_ok=True)
for path in files:
    shutil.copyfile(path,target/path.name)
    if path.suffix in ('.wasm','.pck','.js'):
        (target/(path.name+'.gz')).write_bytes(gzip.compress(path.read_bytes(),compresslevel=6,mtime=0))
html=(folder/'index.html').read_text(encoding='utf-8')
match=re.search(r'const GODOT_CONFIG=(\{.*?\});',html)
if not match:raise RuntimeError('Godot HTML configuration missing')
config=json.loads(match[1]);prefix='/assets/'+version+'/'
config['executable']=prefix+'index'
config['fileSizes']={prefix+Path(name).name:value for name,value in config['fileSizes'].items()}
html=html[:match.start(1)]+json.dumps(config,separators=(',',':'))+html[match.end(1):]
html=re.sub(r'<script src="(?:/assets/[^/]+/)?index.js"></script>',f'<script src="{prefix}index.js"></script>',html)
(folder/'index.html').write_text(html,encoding='utf-8')
(folder/'version.json').write_text(json.dumps({'client_asset_version':version,'protocol_version':2}),encoding='utf-8')
print('Client runtime asset version:',version)
