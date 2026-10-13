"""Read only Web members from the official 1.2 GB template ZIP using HTTP ranges."""
import io
import os
from pathlib import Path
import urllib.request
import zipfile

URL = "https://github.com/godotengine/godot-builds/releases/download/4.7.2-stable/Godot_v4.7.2-stable_export_templates.tpz"
SIZE = 1281349702


class RemoteZip(io.RawIOBase):
    def __init__(self):
        request = urllib.request.Request(URL, method="HEAD")
        with urllib.request.urlopen(request, timeout=60) as r:
            self.url = r.url
        self.pos = 0

    def seekable(self):
        return True

    def seek(self, offset, whence=0):
        self.pos = offset if whence == 0 else self.pos + offset if whence == 1 else SIZE + offset
        return self.pos

    def tell(self):
        return self.pos

    def read(self, size=-1):
        if size < 0:
            size = SIZE - self.pos
        if not size:
            return b""
        req = urllib.request.Request(self.url, headers={"Range": f"bytes={self.pos}-{self.pos+size-1}"})
        with urllib.request.urlopen(req, timeout=120) as r:
            if r.status != 206:
                raise RuntimeError("Official download did not support partial requests; no full archive was downloaded.")
            data = r.read()
        if len(data) != size:
            raise RuntimeError("Incomplete range response")
        self.pos += len(data)
        return data


target = Path(os.environ["APPDATA"]) / "Godot/export_templates/4.7.2.stable"
target.mkdir(parents=True, exist_ok=True)
with zipfile.ZipFile(RemoteZip()) as archive:
    names = [n for n in archive.namelist() if "web" in n and n.endswith(".zip")]
    print("Available Web templates:", names, flush=True)
    for name in names:
        if "nothreads" in name and not "extension" in name:
            output = target / Path(name).name
            if not output.exists():
                print("Downloading", output.name, flush=True)
                output.write_bytes(archive.read(name))
            print(output.name, output.stat().st_size, flush=True)
print("Web templates installed", flush=True)
