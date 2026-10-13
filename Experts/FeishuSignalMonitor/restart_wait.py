"""Wait for the monitor service to finish its graceful shutdown."""
from __future__ import annotations

import json
import os
from pathlib import Path
import time


home = Path(os.environ.get("LOCALAPPDATA", "")) / "FeishuMT5SignalMonitor"
status = home / "service.json"
deadline = time.time() + 60

while time.time() < deadline:
    try:
        value = json.loads(status.read_text(encoding="utf-8"))
        if value.get("stopped"):
            raise SystemExit(0)
    except (OSError, ValueError, TypeError):
        pass
    time.sleep(1)

raise SystemExit("monitor service did not stop within 60 seconds")
