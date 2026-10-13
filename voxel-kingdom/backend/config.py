import os
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PRIVATE = Path(os.environ.get("VOXEL_DATA_DIR", str(Path(os.environ.get("LOCALAPPDATA", str(Path.home() / ".local/share"))) / "VoxelKingdom")))
PRIVATE.mkdir(parents=True, exist_ok=True)
config_path = Path(os.environ.get("VOXEL_ENV_FILE", str(PRIVATE / "server.env")))
if config_path.exists():
    for line in config_path.read_text(encoding="utf-8").splitlines():
        if "=" in line and not line.lstrip().startswith("#"):
            key, value = line.split("=", 1)
            os.environ.setdefault(key.strip(), value.strip())

API_KEY = os.environ.get("DEEPSEEK_API_KEY", "")
BASE_URL = os.environ.get("DEEPSEEK_BASE_URL", "https://api.deepseek.com").rstrip("/")
MODEL = os.environ.get("DEEPSEEK_MODEL", "deepseek-flash")
DATABASE = os.environ.get("VOXEL_DATABASE", str(PRIVATE / "world.sqlite3"))
