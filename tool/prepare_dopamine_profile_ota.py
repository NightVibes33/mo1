#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path

path = Path("tool/dopamine_one_tap_server.py")
text = path.read_text(encoding="utf-8")

# Development signing is required for the device-specific research build.
text = text.replace(
    '"profileType": "IOS_APP_ADHOC"',
    '"profileType": "IOS_APP_DEVELOPMENT"',
)
text = text.replace(
    'allowed["get-task-allow"] = False',
    'allowed["get-task-allow"] = True',
)

# Brand the complete OTA flow. Internal repository filenames remain unchanged.
text = text.replace("DOPAMINE_", "PALERAMINE_")
text = text.replace("Dopamine", "Paleramine")
text = text.replace("dopamine", "paleramine")
text = text.replace('"2.4.99"', '"0.1.0"')
text = text.replace(
    "sign the experimental DarkSword build, then install it.",
    "sign the Paleramine iPad5 research build, then install it. This build includes exact-device safety checks and Files-visible diagnostics in Files → Paleramine → Paleramine-Diagnostics.log.",
)
text = text.replace(
    "The profile requests UDID, product model and OS version only.",
    "The profile requests UDID, product model and OS version only. Paleramine is locked to iPad6,11/iPad6,12 on iPadOS 16.7.11 (20H360).",
)

required = (
    '"profileType": "IOS_APP_DEVELOPMENT"',
    'allowed["get-task-allow"] = True',
    "Paleramine iPad 5 Installer",
    "Install Paleramine Build",
    "Paleramine-Diagnostics.log",
    "PALERAMINE_BUNDLE_ID",
    "PALERAMINE_BUILD_NUMBER",
    "com.nightvibes33.paleramine.enroll",
    "setInterval(poll,2500)",
)
missing = [item for item in required if item not in text]
if missing:
    raise SystemExit(f"Paleramine installer verification failed: {missing}")

path.write_text(text, encoding="utf-8")
