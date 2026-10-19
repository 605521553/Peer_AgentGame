#!/usr/bin/env bash
set -euo pipefail
stage="$1"
release="$2"
component="${3:-all}"
[[ "$stage" == /home/ubuntu/.cache/voxel-* && "$release" =~ ^[0-9]{8}-[0-9]{6}$ ]] || exit 2
[[ "$component" == all || "$component" == client || "$component" == server ]] || exit 2
base=/opt/voxel-kingdom
version="$base/releases/$release"
if [[ "$component" != all ]]; then
    test -L "$base/server-current" && test -L "$base/client-current" || { echo 'First migration requires --component all'; exit 1; }
fi
install -d -m 755 "$version"
tar --no-same-owner -xzf "$stage/release.tar.gz" -C "$version"
chmod -R a+rX "$version"
if [[ "$component" != client ]]; then
    export DEBIAN_FRONTEND=noninteractive
    if ! dpkg-query -W -f='${Status}' python3-venv 2>/dev/null | grep -q 'install ok installed'; then
        apt-get update -qq
        apt-get install -y -qq python3-venv
    fi
    id voxel-kingdom >/dev/null 2>&1 || useradd --system --home-dir /var/lib/voxel-kingdom --shell /usr/sbin/nologin voxel-kingdom
    install -d -o voxel-kingdom -g voxel-kingdom -m 700 /var/lib/voxel-kingdom
    install -d -o root -g voxel-kingdom -m 750 /etc/voxel-kingdom
    test -x "$base/venv/bin/python" || python3 -m venv "$base/venv"
    "$base/venv/bin/python" -m pip install --disable-pip-version-check -r "$version/server/requirements.txt"
    install -o root -g voxel-kingdom -m 640 "$stage/server.env" /etc/voxel-kingdom/server.env
    if systemctl is-active --quiet voxel-kingdom; then systemctl start voxel-kingdom-backup.service; fi
    if [ -L "$base/server-current" ]; then readlink "$base/server-current" > "$base/previous-server-release"; fi
    ln -sfn "$version" "$base/server-current"
    install -m 644 "$version/deploy/voxel-kingdom.service" /etc/systemd/system/
    install -m 644 "$version/deploy/voxel-kingdom-backup.service" /etc/systemd/system/
    install -m 644 "$version/deploy/voxel-kingdom-backup.timer" /etc/systemd/system/
    systemctl daemon-reload
    systemctl enable voxel-kingdom.service
    systemctl restart voxel-kingdom.service
    for attempt in $(seq 1 30); do
        if curl -fsS http://127.0.0.1:8765/api/health >/dev/null 2>&1; then break; fi
        sleep 1
    done
    curl -fsS http://127.0.0.1:8765/api/health
    systemctl enable --now voxel-kingdom-backup.timer
    systemctl start voxel-kingdom-backup.service
fi
if [[ "$component" != server ]]; then
    # Keep content-addressed assets for pages loading the preceding release.
    if [ -L "$base/client-current" ]; then
        readlink "$base/client-current" > "$base/previous-client-release"
        if [ -d "$base/client-current/build/client-web/assets" ]; then
            cp -an "$base/client-current/build/client-web/assets/." "$version/build/client-web/assets/"
        fi
    fi
    ln -sfn "$version" "$base/client-current"
    install -d -o root -g root -m 700 /etc/voxel-kingdom/tls
    if [ ! -f /etc/voxel-kingdom/tls/server.crt ]; then
        openssl req -x509 -newkey rsa:2048 -sha256 -nodes -days 365 \
          -keyout /etc/voxel-kingdom/tls/server.key -out /etc/voxel-kingdom/tls/server.crt \
          -subj '/CN=140.143.163.231' -addext 'subjectAltName=IP:140.143.163.231' >/dev/null 2>&1
        chmod 600 /etc/voxel-kingdom/tls/server.key
    fi
    if [ -f /etc/nginx/sites-available/voxel-kingdom ]; then cp /etc/nginx/sites-available/voxel-kingdom "$version/deploy/nginx-previous.conf"; fi
    install -m 644 "$version/deploy/nginx-ip.conf" /etc/nginx/sites-available/voxel-kingdom
    ln -sfn /etc/nginx/sites-available/voxel-kingdom /etc/nginx/sites-enabled/voxel-kingdom
    if ! nginx -t; then
        if [ -f "$version/deploy/nginx-previous.conf" ]; then
            cp "$version/deploy/nginx-previous.conf" /etc/nginx/sites-available/voxel-kingdom
        else
            unlink /etc/nginx/sites-enabled/voxel-kingdom
        fi
        echo 'Nginx validation failed; existing Nginx was NOT reloaded.' >&2
        exit 1
    fi
    systemctl reload nginx
fi
curl --cacert /etc/voxel-kingdom/tls/server.crt --resolve 140.143.163.231:443:127.0.0.1 -fsS https://140.143.163.231/api/health
printf '\nExisting site HTTP: '
curl --resolve api.patelender.cn:443:127.0.0.1 -s -o /dev/null -w '%{http_code}\n' https://api.patelender.cn/
systemctl show voxel-kingdom.service -p ActiveState -p MemoryCurrent -p MainPID
printf '\nComponent deployed: %s / %s\n' "$component" "$release"
