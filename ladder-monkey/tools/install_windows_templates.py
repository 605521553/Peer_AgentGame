"""Fetch only Windows x64 entries from the official matching template ZIP.

HTTP ranges avoid downloading the 1.28 GB of unrelated platform templates.
zipfile validates each decompressed entry's CRC before installation.
"""
import io
import os
from pathlib import Path
import urllib.request
import zipfile

URL = "https://github.com/godotengine/godot-builds/releases/download/4.7.2-stable/Godot_v4.7.2-stable_export_templates.tpz"


class RemoteZip(io.RawIOBase):
    def __init__(self):
        # Archive size is from the official GitHub 4.7.2 release asset API.
        archive_size = 1281349702
        request = urllib.request.Request(URL, headers={"Range": f"bytes={archive_size - 131072}-{archive_size - 1}", "User-Agent": "LadderMonkey-Build"})
        with urllib.request.urlopen(request, timeout=60) as response:
            if response.status != 206:
                raise RuntimeError("Server does not support partial template downloads")
            self.url = response.url
            self.size = int(response.headers["Content-Range"].split("/")[-1])
            self.tail = response.read()
        self.position = 0
        print(f"Official template archive: {self.size:,} bytes", flush=True)

    def seekable(self):
        return True

    def readable(self):
        return True

    def tell(self):
        return self.position

    def seek(self, offset, whence=0):
        self.position = offset if whence == 0 else self.position + offset if whence == 1 else self.size + offset
        return self.position

    def read(self, size=-1):
        count = self.size - self.position if size < 0 else min(size, self.size - self.position)
        if count <= 0:
            return b""
        start = self.position
        end = start + count - 1
        if start >= self.size - len(self.tail):
            data = self.tail[start - (self.size - len(self.tail)):start - (self.size - len(self.tail)) + count]
        else:
            request = urllib.request.Request(self.url, headers={"Range": f"bytes={start}-{end}", "User-Agent": "LadderMonkey-Build"})
            with urllib.request.urlopen(request, timeout=120) as response:
                if response.status != 206 or not response.headers["Content-Range"].startswith(f"bytes {start}-{end}/"):
                    raise RuntimeError("Unexpected response range from template server")
                data = response.read()
            if len(data) != count:
                raise RuntimeError("Incomplete template range download")
        self.position += len(data)
        return data


destination = Path(os.environ["APPDATA"]) / "Godot" / "export_templates" / "4.7.2.stable"
destination.mkdir(parents=True, exist_ok=True)
with zipfile.ZipFile(RemoteZip()) as archive:
    for filename in ("windows_debug_x86_64.exe", "windows_release_x86_64.exe"):
        entry = next(item for item in archive.infolist() if item.filename.rsplit("/", 1)[-1] == filename)
        print(f"Fetching {filename}: compressed {entry.compress_size:,} bytes", flush=True)
        binary = archive.read(entry)
        if binary[:2] != b"MZ":
            raise RuntimeError("Template is not a Windows executable")
        path = destination / filename
        path.write_bytes(binary)
        print(f"Installed {filename}: {len(binary):,} bytes (CRC verified)", flush=True)
