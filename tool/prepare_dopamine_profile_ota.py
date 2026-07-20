#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path

path = Path("tool/dopamine_one_tap_server.py")
text = path.read_text(encoding="utf-8")

text = text.replace(
    '"profileType": "IOS_APP_ADHOC"',
    '"profileType": "IOS_APP_DEVELOPMENT"',
)
text = text.replace(
    'allowed["get-task-allow"] = False',
    'allowed["get-task-allow"] = True',
)

required = (
    '"profileType": "IOS_APP_DEVELOPMENT"',
    'allowed["get-task-allow"] = True',
    "Start iPad Registration",
    "Install Dopamine Build",
    "Automatic signing",
    "Waiting for this iPad.",
    "setInterval(poll,2500)",
)
missing = [item for item in required if item not in text]
if missing:
    raise SystemExit(f"Detailed installer verification failed: {missing}")

path.write_text(text, encoding="utf-8")
