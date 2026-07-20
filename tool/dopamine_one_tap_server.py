#!/usr/bin/env python3
from __future__ import annotations

import base64
import hashlib
import html
import json
import os
import plistlib
import shutil
import subprocess
import tempfile
import threading
import time
import urllib.parse
import uuid
import zipfile
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any

import jwt
import requests

PORT = int(os.environ.get("PORT", "8080"))
SESSION = os.environ["INSTALLER_SESSION"]
CHALLENGE = os.environ["INSTALLER_CHALLENGE"]
UNSIGNED_IPA = Path(os.environ["UNSIGNED_IPA"]).resolve()
OUTPUT_DIR = Path(os.environ.get("OUTPUT_DIR", "installer-output")).resolve()
OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
SIGNED_IPA = OUTPUT_DIR / "Dopamine-iPad5-signed.ipa"
PROFILE_PATH = OUTPUT_DIR / "Dopamine-iPad5.mobileprovision"
BUNDLE_ID = os.environ.get("DOPAMINE_BUNDLE_ID", "com.nightvibes33.dopamine.ipad5")
PROFILE_NAME = os.environ.get("DOPAMINE_PROFILE_NAME", "Dopamine iPad 5 Ad Hoc")
SIGNING_IDENTITY = os.environ["APPLE_SIGNING_IDENTITY"]
CERTIFICATE_ID = os.environ["APPLE_CERTIFICATE_ID"]
P12_EXPORT_PATH = Path(os.environ["APPLE_P12_PATH"]).resolve()
P12_PASSWORD = os.environ.get("APPLE_P12_PASSWORD", "1")
API_KEY = os.environ["APP_STORE_CONNECT_API_KEY_P8"].replace("\\n", "\n")
API_KEY_ID = os.environ["APP_STORE_CONNECT_KEY_ID"]
API_ISSUER_ID = os.environ["APP_STORE_CONNECT_ISSUER_ID"]

STATE_LOCK = threading.Lock()
STATE: dict[str, Any] = {
    "status": "awaiting_device",
    "message": "Install the temporary device identification profile.",
    "udid_suffix": None,
    "product": None,
    "version": None,
    "error": None,
    "updated_at": time.time(),
}


def update_state(**changes: Any) -> None:
    with STATE_LOCK:
        STATE.update(changes)
        STATE["updated_at"] = time.time()


def state_copy() -> dict[str, Any]:
    with STATE_LOCK:
        return dict(STATE)


def apple_token() -> str:
    now = int(time.time())
    return jwt.encode(
        {"iss": API_ISSUER_ID, "iat": now, "exp": now + 900, "aud": "appstoreconnect-v1"},
        API_KEY,
        algorithm="ES256",
        headers={"kid": API_KEY_ID, "typ": "JWT"},
    )


def apple_request(method: str, path: str, *, params: dict[str, Any] | None = None,
                  body: dict[str, Any] | None = None, expected: tuple[int, ...] = (200,)) -> dict[str, Any]:
    response = requests.request(
        method,
        f"https://api.appstoreconnect.apple.com{path}",
        headers={"Authorization": f"Bearer {apple_token()}", "Content-Type": "application/json"},
        params=params,
        json=body,
        timeout=60,
    )
    if response.status_code not in expected:
        detail = response.text[:4000]
        raise RuntimeError(f"Apple API {method} {path} returned {response.status_code}: {detail}")
    if not response.content:
        return {}
    return response.json()


def ensure_device(udid: str, product: str) -> str:
    devices: list[dict[str, Any]] = []
    url = "/v1/devices"
    params: dict[str, Any] | None = {"limit": 200, "fields[devices]": "name,platform,udid,deviceClass,status,model"}
    while url:
        payload = apple_request("GET", url, params=params)
        devices.extend(payload.get("data", []))
        next_url = payload.get("links", {}).get("next")
        if next_url:
            parsed = urllib.parse.urlparse(next_url)
            url = parsed.path
            params = dict(urllib.parse.parse_qsl(parsed.query))
        else:
            url = ""
    for item in devices:
        if item.get("attributes", {}).get("udid") == udid:
            return item["id"]
    payload = {
        "data": {
            "type": "devices",
            "attributes": {
                "name": f"Dopamine Installer {product or 'iPad'}",
                "platform": "IOS",
                "udid": udid,
            },
        }
    }
    return apple_request("POST", "/v1/devices", body=payload, expected=(201,))["data"]["id"]


def ensure_bundle_id() -> str:
    found = apple_request(
        "GET", "/v1/bundleIds",
        params={"filter[identifier]": BUNDLE_ID, "limit": 10, "fields[bundleIds]": "name,platform,identifier"},
    ).get("data", [])
    if found:
        return found[0]["id"]
    payload = {
        "data": {
            "type": "bundleIds",
            "attributes": {
                "identifier": BUNDLE_ID,
                "name": "Dopamine iPad 5 Installer",
                "platform": "IOS",
            },
        }
    }
    return apple_request("POST", "/v1/bundleIds", body=payload, expected=(201,))["data"]["id"]


def create_profile(bundle_id_resource: str, device_id: str) -> bytes:
    unique_name = f"{PROFILE_NAME} {int(time.time())}"
    payload = {
        "data": {
            "type": "profiles",
            "attributes": {"name": unique_name, "profileType": "IOS_APP_ADHOC"},
            "relationships": {
                "bundleId": {"data": {"type": "bundleIds", "id": bundle_id_resource}},
                "certificates": {"data": [{"type": "certificates", "id": CERTIFICATE_ID}]},
                "devices": {"data": [{"type": "devices", "id": device_id}]},
            },
        }
    }
    response = apple_request("POST", "/v1/profiles", body=payload, expected=(201,))
    return base64.b64decode(response["data"]["attributes"]["profileContent"])


def run(*args: str, cwd: Path | None = None, capture: bool = False) -> str:
    completed = subprocess.run(
        list(args), cwd=str(cwd) if cwd else None, check=True,
        stdout=subprocess.PIPE if capture else None,
        stderr=subprocess.STDOUT if capture else None,
        text=True,
    )
    return completed.stdout if capture else ""


def decode_mobileprovision(profile: Path, output: Path) -> dict[str, Any]:
    run("security", "cms", "-D", "-i", str(profile), "-o", str(output))
    with output.open("rb") as handle:
        return plistlib.load(handle)


def make_entitlements(profile_data: dict[str, Any], output: Path) -> None:
    allowed = dict(profile_data.get("Entitlements", {}))
    allowed["get-task-allow"] = False
    with output.open("wb") as handle:
        plistlib.dump(allowed, handle, fmt=plistlib.FMT_XML, sort_keys=True)


def sign_ipa(profile_bytes: bytes) -> None:
    PROFILE_PATH.write_bytes(profile_bytes)
    with tempfile.TemporaryDirectory(prefix="dopamine-sign-") as td:
        root = Path(td)
        payload = root / "Payload"
        with zipfile.ZipFile(UNSIGNED_IPA) as archive:
            archive.extractall(root)
        apps = list(payload.glob("*.app"))
        if len(apps) != 1:
            raise RuntimeError(f"Expected one app in IPA, found {len(apps)}")
        app = apps[0]
        info_path = app / "Info.plist"
        with info_path.open("rb") as handle:
            info = plistlib.load(handle)
        info["CFBundleIdentifier"] = BUNDLE_ID
        info["CFBundleDisplayName"] = "Dopamine iPad 5"
        info["CFBundleName"] = "Dopamine"
        with info_path.open("wb") as handle:
            plistlib.dump(info, handle, fmt=plistlib.FMT_BINARY, sort_keys=False)

        for stale in app.rglob("_CodeSignature"):
            if stale.is_dir():
                shutil.rmtree(stale, ignore_errors=True)
        for stale in app.rglob("CodeResources"):
            if stale.is_file():
                stale.unlink(missing_ok=True)
        shutil.copy2(PROFILE_PATH, app / "embedded.mobileprovision")

        decoded_profile = root / "profile.plist"
        profile_data = decode_mobileprovision(PROFILE_PATH, decoded_profile)
        entitlements = root / "entitlements.plist"
        make_entitlements(profile_data, entitlements)

        nested: list[Path] = []
        for pattern in ("*.framework", "*.dylib", "*.appex", "*.xpc"):
            nested.extend(app.rglob(pattern))
        nested.sort(key=lambda p: len(p.parts), reverse=True)
        for item in nested:
            run("codesign", "--force", "--sign", SIGNING_IDENTITY, "--timestamp=none", str(item))
        run(
            "codesign", "--force", "--deep", "--sign", SIGNING_IDENTITY,
            "--entitlements", str(entitlements), "--timestamp=none", str(app),
        )
        run("codesign", "--verify", "--deep", "--strict", "--verbose=2", str(app), capture=True)

        if SIGNED_IPA.exists():
            SIGNED_IPA.unlink()
        with zipfile.ZipFile(SIGNED_IPA, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=6) as out:
            for path in payload.rglob("*"):
                out.write(path, path.relative_to(root))


def register_and_sign(udid: str, product: str, version: str) -> None:
    try:
        update_state(status="registering", message="Registering this iPad with Apple Developer…")
        device_id = ensure_device(udid, product)
        update_state(status="provisioning", message="Generating an Ad Hoc provisioning profile…")
        bundle_id_resource = ensure_bundle_id()
        profile = create_profile(bundle_id_resource, device_id)
        update_state(status="signing", message="Signing the Dopamine IPA for this iPad…")
        sign_ipa(profile)
        update_state(
            status="ready",
            message="Dopamine is signed and ready to install.",
            signed_sha256=hashlib.sha256(SIGNED_IPA.read_bytes()).hexdigest(),
            signed_size=SIGNED_IPA.stat().st_size,
        )
    except Exception as exc:
        update_state(status="error", message="Signing failed.", error=str(exc))
        print(f"INSTALLER_ERROR: {exc}", flush=True)


def parse_device_payload(body: bytes) -> dict[str, Any]:
    try:
        return plistlib.loads(body)
    except Exception:
        pass
    with tempfile.TemporaryDirectory(prefix="profile-post-") as td:
        source = Path(td) / "request.cms"
        decoded = Path(td) / "request.plist"
        source.write_bytes(body)
        run("security", "cms", "-D", "-i", str(source), "-o", str(decoded))
        with decoded.open("rb") as handle:
            return plistlib.load(handle)


def host_base(handler: BaseHTTPRequestHandler) -> str:
    forwarded = handler.headers.get("x-forwarded-host") or handler.headers.get("host") or "127.0.0.1"
    proto = handler.headers.get("x-forwarded-proto") or ("https" if "trycloudflare.com" in forwarded else "http")
    return f"{proto}://{forwarded}"


def enrollment_profile(base_url: str) -> bytes:
    payload = {
        "PayloadContent": {
            "URL": f"{base_url}/profile?session={urllib.parse.quote(SESSION)}",
            "DeviceAttributes": ["UDID", "VERSION", "PRODUCT", "DEVICE_NAME"],
            "Challenge": CHALLENGE,
        },
        "PayloadOrganization": "NightVibes33",
        "PayloadDisplayName": "Dopamine iPad Registration",
        "PayloadVersion": 1,
        "PayloadUUID": str(uuid.uuid5(uuid.NAMESPACE_URL, f"{base_url}/{SESSION}")).upper(),
        "PayloadIdentifier": f"com.nightvibes33.dopamine.enroll.{SESSION[:12]}",
        "PayloadDescription": "Temporarily identifies this iPad by UDID so it can be registered to your Apple Developer account and receive a device-specific Dopamine build.",
        "PayloadType": "Profile Service",
    }
    return plistlib.dumps(payload, fmt=plistlib.FMT_XML, sort_keys=False)


def manifest(base_url: str) -> bytes:
    payload = {
        "items": [{
            "assets": [{"kind": "software-package", "url": f"{base_url}/download.ipa?session={SESSION}"}],
            "metadata": {
                "bundle-identifier": BUNDLE_ID,
                "bundle-version": "2.5.0",
                "kind": "software",
                "title": "Dopamine iPad 5",
            },
        }]
    }
    return plistlib.dumps(payload, fmt=plistlib.FMT_XML, sort_keys=False)


def page(base_url: str) -> bytes:
    install_manifest = urllib.parse.quote(f"{base_url}/manifest.plist?session={SESSION}", safe="")
    install_url = f"itms-services://?action=download-manifest&url={install_manifest}"
    safe_session = html.escape(SESSION)
    return f"""<!doctype html>
<html lang=\"en\"><head><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width,initial-scale=1,viewport-fit=cover\">
<title>Dopamine iPad 5 Installer</title><style>
:root{{color-scheme:dark}}*{{box-sizing:border-box}}body{{margin:0;background:#09090b;color:#fafafa;font:16px -apple-system,BlinkMacSystemFont,Segoe UI,sans-serif;min-height:100vh;display:grid;place-items:center;padding:22px}}.card{{width:min(620px,100%);background:linear-gradient(145deg,#18181b,#101012);border:1px solid #2a2a30;border-radius:28px;padding:26px;box-shadow:0 24px 80px #0008}}h1{{font-size:30px;margin:0 0 8px}}p{{color:#b4b4bd;line-height:1.5}}.steps{{display:grid;gap:10px;margin:22px 0}}.step{{padding:15px;border-radius:16px;background:#202024;border:1px solid #303036}}.step b{{display:block;margin-bottom:4px}}button,a.button{{width:100%;display:block;text-align:center;border:0;border-radius:15px;padding:15px 18px;background:#fff;color:#08080a;font-weight:750;font-size:17px;text-decoration:none;margin-top:12px}}a.secondary{{background:#29292f;color:#fff}}.status{{padding:14px;border-radius:14px;background:#101014;border:1px solid #29292f;margin-top:18px;white-space:pre-wrap}}.hidden{{display:none}}small{{color:#777782;display:block;margin-top:16px}}code{{word-break:break-all;color:#ddd}}</style></head>
<body><main class=\"card\"><h1>Dopamine iPad 5 Installer</h1><p>One guided flow: identify this iPad, register it with your Apple Developer team, sign the experimental DarkSword build, then install it.</p>
<div class=\"steps\"><div class=\"step\"><b>1. Identify this iPad</b>Apple requires its UDID for Ad Hoc signing.</div><div class=\"step\"><b>2. Automatic signing</b>The server registers the device and creates its provisioning profile.</div><div class=\"step\"><b>3. Install</b>Return here after Settings finishes installing the temporary identification profile.</div></div>
<a class=\"button\" href=\"/enroll.mobileconfig?session={safe_session}\">Start iPad Registration</a>
<a id=\"install\" class=\"button hidden\" href=\"{html.escape(install_url)}\">Install Dopamine</a>
<div id=\"status\" class=\"status\">Waiting for this iPad.</div><small>The profile requests UDID, product model and OS version only. Apple requires confirmation for both the profile and app installation; those prompts cannot be bypassed.</small></main>
<script>const s={json.dumps(SESSION)};const box=document.getElementById('status');const install=document.getElementById('install');async function poll(){{try{{const r=await fetch('/status?session='+encodeURIComponent(s),{{cache:'no-store'}});const j=await r.json();box.textContent=j.message+(j.error?'\\n'+j.error:'');if(j.status==='ready')install.classList.remove('hidden');}}catch(e){{box.textContent='Connection interrupted. Reload this page.'}}}}poll();setInterval(poll,2500);</script></body></html>""".encode()


class Handler(BaseHTTPRequestHandler):
    server_version = "DopamineInstaller/1.0"

    def log_message(self, fmt: str, *args: Any) -> None:
        print(f"HTTP {self.address_string()} {fmt % args}", flush=True)

    def send_bytes(self, status: int, content_type: str, body: bytes, **headers: str) -> None:
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        for key, value in headers.items():
            self.send_header(key.replace("_", "-"), value)
        self.end_headers()
        self.wfile.write(body)

    def valid_session(self, query: dict[str, list[str]]) -> bool:
        return query.get("session", [""])[0] == SESSION

    def do_GET(self) -> None:
        parsed = urllib.parse.urlparse(self.path)
        query = urllib.parse.parse_qs(parsed.query)
        base = host_base(self)
        if parsed.path == "/health":
            self.send_bytes(200, "application/json", b'{"ok":true}')
        elif parsed.path in ("/", "/complete"):
            self.send_bytes(200, "text/html; charset=utf-8", page(base))
        elif parsed.path == "/enroll.mobileconfig" and self.valid_session(query):
            self.send_bytes(200, "application/x-apple-aspen-config", enrollment_profile(base), Content_Disposition='attachment; filename="Dopamine-iPad-Registration.mobileconfig"')
        elif parsed.path == "/status" and self.valid_session(query):
            visible = state_copy()
            visible.pop("udid", None)
            self.send_bytes(200, "application/json", json.dumps(visible).encode())
        elif parsed.path == "/manifest.plist" and self.valid_session(query) and state_copy().get("status") == "ready":
            self.send_bytes(200, "application/xml", manifest(base))
        elif parsed.path == "/download.ipa" and self.valid_session(query) and SIGNED_IPA.exists():
            data = SIGNED_IPA.read_bytes()
            self.send_bytes(200, "application/octet-stream", data, Content_Disposition='attachment; filename="Dopamine-iPad5-signed.ipa"')
        elif parsed.path == "/signing-assets" and self.valid_session(query) and state_copy().get("status") == "ready":
            with tempfile.TemporaryDirectory(prefix="assets-") as td:
                archive = Path(td) / "Dopamine-Signing-Assets.zip"
                with zipfile.ZipFile(archive, "w", zipfile.ZIP_DEFLATED) as out:
                    out.write(P12_EXPORT_PATH, "Dopamine-Distribution.p12")
                    out.write(PROFILE_PATH, "Dopamine-iPad5.mobileprovision")
                self.send_bytes(200, "application/zip", archive.read_bytes(), Content_Disposition='attachment; filename="Dopamine-Signing-Assets.zip"')
        else:
            self.send_bytes(404, "text/plain", b"Not found")

    def do_POST(self) -> None:
        parsed = urllib.parse.urlparse(self.path)
        query = urllib.parse.parse_qs(parsed.query)
        if parsed.path != "/profile" or not self.valid_session(query):
            self.send_bytes(404, "text/plain", b"Not found")
            return
        length = int(self.headers.get("Content-Length", "0"))
        if length <= 0 or length > 2_000_000:
            self.send_bytes(400, "text/plain", b"Invalid profile response")
            return
        try:
            device = parse_device_payload(self.rfile.read(length))
            challenge = device.get("CHALLENGE") or device.get("Challenge")
            if isinstance(challenge, bytes):
                challenge = challenge.decode(errors="ignore")
            if challenge != CHALLENGE:
                raise RuntimeError("The profile challenge did not match this installer session.")
            udid = str(device.get("UDID") or "").strip()
            product = str(device.get("PRODUCT") or device.get("Product") or "iPad").strip()
            version = str(device.get("VERSION") or device.get("Version") or "unknown").strip()
            if len(udid) < 16:
                raise RuntimeError("The iPad did not return a valid UDID.")
            update_state(status="received", message="iPad identified. Starting Apple registration…", udid=udid, udid_suffix=udid[-4:], product=product, version=version)
            threading.Thread(target=register_and_sign, args=(udid, product, version), daemon=True).start()
            location = f"{host_base(self)}/complete?session={urllib.parse.quote(SESSION)}"
            self.send_response(HTTPStatus.MOVED_PERMANENTLY)
            self.send_header("Location", location)
            self.send_header("Content-Length", "0")
            self.end_headers()
        except Exception as exc:
            update_state(status="error", message="Could not identify this iPad.", error=str(exc))
            self.send_bytes(400, "text/plain", str(exc).encode())


if __name__ == "__main__":
    if not UNSIGNED_IPA.exists():
        raise SystemExit(f"Unsigned IPA not found: {UNSIGNED_IPA}")
    print(f"INSTALLER_SESSION={SESSION}", flush=True)
    print(f"Listening on http://127.0.0.1:{PORT}", flush=True)
    ThreadingHTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
