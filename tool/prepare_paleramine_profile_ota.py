#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path

SOURCE = Path("tool/dopamine_one_tap_server.py")
TARGET = Path("tool/paleramine_one_tap_server.py")

text = SOURCE.read_text(encoding="utf-8")

# Rebrand every user-facing and runtime identifier in the generated server.
text = text.replace("DOPAMINE_", "PALERAMINE_")
text = text.replace("Dopamine", "Paleramine")
text = text.replace("dopamine", "paleramine")

# Research builds use the existing development certificate so get-task-allow
# remains available for diagnostics and symbolication.
text = text.replace(
    '"profileType": "IOS_APP_ADHOC"',
    '"profileType": "IOS_APP_DEVELOPMENT"',
)
text = text.replace(
    'allowed["get-task-allow"] = False',
    'allowed["get-task-allow"] = True',
)

# The app target itself is versioned as Paleramine 0.1.0.
text = text.replace(
    'info["CFBundleShortVersionString"] = "2.4.99"',
    'info["CFBundleShortVersionString"] = "0.1.0"',
)

required = (
    '"profileType": "IOS_APP_DEVELOPMENT"',
    'allowed["get-task-allow"] = True',
    'PALERAMINE_BUNDLE_ID',
    'PALERAMINE_PROFILE_NAME',
    'PALERAMINE_BUILD_NUMBER',
    'Paleramine iPad 5 Installer',
    'Install Paleramine Build',
    'Paleramine iPad Registration',
    'Paleramine-iPad5-signed.ipa',
    'setInterval(poll,2500)',
)
missing = [item for item in required if item not in text]
if missing:
    raise SystemExit(f"Paleramine installer verification failed: {missing}")

TARGET.write_text(text, encoding="utf-8")
print(f"Prepared {TARGET}")

# Safe calibration rebuild trigger: 2026-07-21T01:59:43Z
