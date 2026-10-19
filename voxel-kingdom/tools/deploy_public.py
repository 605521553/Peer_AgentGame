"""Deploy the IP test server. Password is prompted, never stored. Requires local paramiko."""
import argparse
from datetime import datetime, timedelta, timezone
import getpass
import gzip
import hashlib
import json
import os
from pathlib import Path
import secrets
import shlex
import sys
import tarfile
import time
import paramiko

ROOT = Path(__file__).resolve().parents[1]
PRIVATE = Path(os.environ['LOCALAPPDATA']) / 'VoxelKingdom'
OUT = ROOT / 'artifacts/public-deployment'
OUT.mkdir(parents=True, exist_ok=True)
sys.stdout.reconfigure(encoding='utf-8')


def connect():
    client = paramiko.SSHClient()
    client.load_host_keys(str(Path.home() / '.ssh/known_hosts'))
    client.set_missing_host_key_policy(paramiko.RejectPolicy())
    client.connect('140.143.163.231', username='ubuntu', password=getpass.getpass('SSH password: '),
                   timeout=15, auth_timeout=20, look_for_keys=False, allow_agent=False)
    return client


def run(client, command):
    channel = client.get_transport().open_session()
    channel.set_combine_stderr(True)
    channel.exec_command(command)
    content = []
    while not channel.exit_status_ready() or channel.recv_ready():
        if channel.recv_ready():
            chunk = channel.recv(65536).decode('utf-8', errors='replace')
            content.append(chunk)
            print(chunk, end='', flush=True)
        else:
            time.sleep(.1)
    code = channel.recv_exit_status()
    if code:
        raise RuntimeError(f'Remote command failed (exit {code})')
    return ''.join(content)


def deploy(client, component="all"):
    before_pid = client.exec_command('systemctl show voxel-kingdom -p MainPID --value')[1].read().decode().strip()
    before_client = client.exec_command('readlink /opt/voxel-kingdom/client-current')[1].read().decode().strip()
    release = datetime.now(timezone(timedelta(hours=8))).strftime('%Y%m%d-%H%M%S')
    stage = '/home/ubuntu/.cache/voxel-' + release
    # No source/config directories outside this allowlist enter the release archive.
    archive = OUT / ('release-' + release + '.tar.gz')
    manifest = {}
    client_version = json.loads((ROOT / "build/client-web/version.json").read_text())["client_asset_version"] if component != "server" else None
    with tarfile.open(archive, 'w:gz') as bundle:
        for folder in (['server/backend', 'server/requirements.txt', 'protocol', 'deploy'] if component == 'server' else ['client/web', 'build/client-web', 'deploy'] if component == 'client' else ['server/backend', 'server/requirements.txt', 'protocol', 'client/web', 'build/client-web', 'deploy']):
            for path in ([ROOT / folder] if (ROOT / folder).is_file() else sorted((ROOT / folder).rglob('*'))):
                if not path.is_file() or '__pycache__' in path.parts or path.suffix in ('.pyc', '.env', '.sqlite3'):
                    continue
                if path.parent == ROOT / 'build/client-web' and path.suffix in ('.wasm', '.pck', '.js', '.gz'):
                    continue
                if path.is_relative_to(ROOT / 'build/client-web/assets') and path.relative_to(ROOT / 'build/client-web/assets').parts[0] != client_version:
                    continue
                relative = path.relative_to(ROOT).as_posix()
                manifest[relative] = hashlib.sha256(path.read_bytes()).hexdigest()
                bundle.add(path, arcname=relative)
    (OUT / ('manifest-' + release + '.json')).write_text(json.dumps(manifest, indent=2), encoding='utf-8')
    access_file = PRIVATE / 'public-access.json'
    env = None
    if component != 'client':
        access_file = PRIVATE / 'public-access.json'
        if access_file.exists():
            access = json.loads(access_file.read_text(encoding='utf-8'))
        else:
            access = {'url': 'https://140.143.163.231', 'invite_code': secrets.token_urlsafe(9)}
            access_file.write_text(json.dumps(access, indent=2), encoding='utf-8')
        # Read only these provider settings; no Windows paths or unrelated secrets are uploaded.
        settings = {}
        for line in (PRIVATE / 'server.env').read_text(encoding='utf-8-sig').splitlines():
            if '=' in line and not line.lstrip().startswith('#'):
                key, value = line.split('=', 1)
                if key.strip() in ('DEEPSEEK_API_KEY', 'DEEPSEEK_MODEL', 'DEEPSEEK_BASE_URL'):
                    settings[key.strip()] = value.strip()
        assert settings.get('DEEPSEEK_API_KEY'), 'Private provider configuration missing'
        settings['VOXEL_JOIN_CODE'] = access['invite_code']
        env = '\n'.join(f'{key}={value}' for key, value in settings.items()) + '\n'
    sftp = client.open_sftp()
    sftp.mkdir(stage, mode=0o700)
    log = ''
    try:
        print('Uploading release', release, f'({archive.stat().st_size // 1024 // 1024} MiB)', flush=True)
        sftp.put(str(archive), stage + '/release.tar.gz')
        sftp.put(str(ROOT / 'deploy/install.sh'), stage + '/install.sh')
        if env is not None:
            with sftp.open(stage + '/server.env', 'w') as stream:
                stream.write(env)
            sftp.chmod(stage + '/server.env', 0o600)
        log = run(client, f'sudo -n bash {shlex.quote(stage + "/install.sh")} {shlex.quote(stage)} {release} {component}')
        after_pid = client.exec_command('systemctl show voxel-kingdom -p MainPID --value')[1].read().decode().strip()
        after_client = client.exec_command('readlink /opt/voxel-kingdom/client-current')[1].read().decode().strip()
        if component == 'client':
            assert before_pid == after_pid and after_pid != '0', 'Client deployment must not restart backend'
        if component == 'server':
            assert before_client == after_client, 'Server deployment must not change client release'
        evidence = {'release':release,'component':component,'backend_pid_before':before_pid,'backend_pid_after':after_pid,'client_release_before':before_client,'client_release_after':after_client}
        (OUT / ('release-' + release + '.json')).write_text(json.dumps(evidence,indent=2),encoding='utf-8')
        print(json.dumps(evidence),flush=True)
        cert = client.exec_command('sudo -n cat /etc/voxel-kingdom/tls/server.crt')[1].read()
        (PRIVATE / 'public-server.crt').write_bytes(cert)
        (OUT / ('deploy-' + release + '.log')).write_text(log, encoding='utf-8')
        print('\nRelease deployed. Private invitation file:', access_file, flush=True)
    finally:
        # Remove only the three known upload files, then the empty staging directory.
        for name in ('server.env', 'release.tar.gz', 'install.sh'):
            try:
                sftp.remove(stage + '/' + name)
            except OSError:
                pass
        try:
            sftp.rmdir(stage)
        except OSError:
            pass
        sftp.close()


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--component', choices=['all','client','server'], default='all')
    parser.add_argument('--command', help='Run a specific administration command instead of deployment')
    args = parser.parse_args()
    ssh = connect()
    try:
        if args.command:
            run(ssh, args.command)
        else:
            deploy(ssh, args.component)
    finally:
        ssh.close()
