#!/usr/bin/env python3
import concurrent.futures
import json
import os
from pathlib import Path
import struct
import subprocess
import sys
import tempfile

binary = str(Path(sys.argv[1]).resolve())
origin = "chrome-extension://dmapmjjnmecefkegcdlglnncnfjnnddp/"

with tempfile.TemporaryDirectory(prefix="tabshelf-bridge-") as directory:
    env = {**os.environ, "TABSHELF_DATA_DIR": directory, "TABSHELF_SKIP_APP_LAUNCH": "1"}

    def send(message=None, raw=None, caller=origin):
        if raw is None:
            payload = json.dumps(message).encode()
            raw = struct.pack("=I", len(payload)) + payload
        result = subprocess.run([binary, caller], input=raw, capture_output=True, env=env, timeout=10)
        assert len(result.stdout) >= 4, result.stderr.decode()
        size = struct.unpack("=I", result.stdout[:4])[0]
        assert size == len(result.stdout) - 4
        return json.loads(result.stdout[4:])

    message = {"type": "save", "url": "https://example.com/", "title": "Hello 🌎"}
    assert send(message) == {"ok": True, "inserted": True}
    shelf_file = Path(directory) / "shelf.json"
    initial = json.loads(shelf_file.read_text())
    group_id = "A16A14DD-F4BE-44D1-9A03-CB3F03EF8BEF"
    initial["groups"] = [{"id": group_id, "name": "Work"}]
    initial["sites"][0]["groupID"] = group_id
    initial["sites"][0]["pinnedAt"] = 100
    shelf_file.write_text(json.dumps(initial))
    assert send(message) == {"ok": True, "inserted": False}
    assert not send(message, caller="chrome-extension://not-allowed/")["ok"]
    assert not send({**message, "url": "javascript:alert(1)"})["ok"]
    assert not send({**message, "type": "delete"})["ok"]
    assert not send(raw=b"\x01\x00")["ok"]
    assert not send(raw=struct.pack("=I", 1024 * 1024))["ok"]
    assert not send(raw=struct.pack("=I", 8) + b"{}")["ok"]
    assert not send(raw=struct.pack("=I", 3) + b"bad")["ok"]

    def concurrent_save(index):
        return send({**message, "url": f"https://example.com/{index}"})

    with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
        assert all(result["ok"] for result in pool.map(concurrent_save, range(30)))
    stored = json.loads((Path(directory) / "shelf.json").read_text())
    assert len(stored["sites"]) == 31
    assert any(site["title"] == "Hello 🌎" for site in stored["sites"])
    saved = next(site for site in stored["sites"] if site["url"] == "https://example.com/")
    assert saved["groupID"] == group_id and saved["pinnedAt"] == 100
    assert stored["groups"] == initial["groups"]
    print("Native bridge: framing, validation, origin, Unicode, duplicates, groups/pins, and 30 concurrent saves passed.")
