#!/usr/bin/env python3
import base64
import datetime as dt
import json
import os
import re
import secrets
import shutil
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

import jwt
from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.serialization import pkcs12
from cryptography.x509.oid import NameOID

BASE = "https://api.appstoreconnect.apple.com"
KEY_ID = os.environ["APP_STORE_CONNECT_KEY_ID"].strip()
ISSUER_ID = os.environ["APP_STORE_CONNECT_ISSUER_ID"].strip()
TEAM_ID = os.environ["APPLE_TEAM_ID"].strip()
DEVICE_UDID = os.environ["DEVICE_UDID"].strip()
BUNDLE_IDENTIFIER = os.environ.get(
    "DEV_BUNDLE_IDENTIFIER", "app.mo1.player.39A8Q3T3TR"
).strip()
PRIVATE_KEY = os.environ["APP_STORE_CONNECT_API_KEY_P8"].strip()

OUTPUT = Path("output")
OUTPUT.mkdir(parents=True, exist_ok=True)

P12_PATH = OUTPUT / "apple-development.p12"
PASSWORD_PATH = OUTPUT / "p12-password.txt"
CERT_ID_PATH = OUTPUT / "certificate-id.txt"
PROFILE_PATH = OUTPUT / "development.mobileprovision"
INFO_PATH = OUTPUT / "signing-info.json"

EXISTING_CERTIFICATE_ID = os.environ.get("EXISTING_CERTIFICATE_ID", "").strip()
EXISTING_P12_PATH = os.environ.get("EXISTING_P12_PATH", "").strip()
EXISTING_PASSWORD_PATH = os.environ.get("EXISTING_PASSWORD_PATH", "").strip()


class APIError(RuntimeError):
    def __init__(self, method, path, status, body):
        self.method = method
        self.path = path
        self.status = status
        self.body = body
        detail = ""
        try:
            payload = json.loads(body)
            errors = payload.get("errors", [])
            if errors:
                detail = errors[0].get("detail") or errors[0].get("title") or ""
        except Exception:
            pass
        super().__init__(f"{method} {path} -> HTTP {status}: {detail or body[:500]}")


def normalize_private_key(value: str) -> str:
    value = value.replace("\\n", "\n").strip()
    if "BEGIN PRIVATE KEY" in value or "BEGIN EC PRIVATE KEY" in value:
        return value
    compact = "".join(value.split())
    try:
        decoded = base64.b64decode(compact + "=" * (-len(compact) % 4)).decode()
    except Exception as exc:
        raise SystemExit("APP_STORE_CONNECT_API_KEY_P8 is neither PEM nor valid base64") from exc
    if "BEGIN" not in decoded:
        raise SystemExit("Decoded APP_STORE_CONNECT_API_KEY_P8 is not a PEM key")
    return decoded


PRIVATE_KEY = normalize_private_key(PRIVATE_KEY)


def token():
    now = int(time.time())
    return jwt.encode(
        {"iss": ISSUER_ID, "iat": now, "exp": now + 900, "aud": "appstoreconnect-v1"},
        PRIVATE_KEY,
        algorithm="ES256",
        headers={"kid": KEY_ID, "typ": "JWT"},
    )


def request(method, path, payload=None):
    data = json.dumps(payload).encode() if payload is not None else None
    headers = {
        "Authorization": f"Bearer {token()}",
        "Accept": "application/json",
    }
    if data is not None:
        headers["Content-Type"] = "application/json"
    req = urllib.request.Request(BASE + path, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=60) as response:
            raw = response.read()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8", "replace")
        raise APIError(method, path, exc.code, body) from exc


def all_rows(path):
    rows = []
    while path:
        response = request("GET", path)
        rows.extend(response.get("data", []))
        next_url = response.get("links", {}).get("next")
        if not next_url:
            break
        parsed = urllib.parse.urlsplit(next_url)
        path = parsed.path + (f"?{parsed.query}" if parsed.query else "")
    return rows


def query(path, params):
    return f"{path}?{urllib.parse.urlencode(params)}"


def validate_inputs():
    if not re.fullmatch(r"[A-Za-z0-9-]{20,64}", DEVICE_UDID):
        raise SystemExit("Device UDID has an unexpected format")
    if not BUNDLE_IDENTIFIER or "." not in BUNDLE_IDENTIFIER:
        raise SystemExit("DEV_BUNDLE_IDENTIFIER is invalid")


def get_or_register_device():
    rows = all_rows(
        query(
            "/v1/devices",
            {
                "filter[udid]": DEVICE_UDID,
                "limit": "200",
            },
        )
    )
    if rows:
        device = rows[0]
        status = device.get("attributes", {}).get("status")
        if status == "DISABLED":
            try:
                device = request(
                    "PATCH",
                    f"/v1/devices/{device['id']}",
                    {
                        "data": {
                            "type": "devices",
                            "id": device["id"],
                            "attributes": {"status": "ENABLED"},
                        }
                    },
                )["data"]
            except APIError as exc:
                raise SystemExit(
                    "The supplied device exists but is disabled and Apple would not re-enable it. "
                    "Enable it in Certificates, Identifiers & Profiles, then rerun."
                ) from exc
        return device, False

    suffix = DEVICE_UDID[-8:]
    created = request(
        "POST",
        "/v1/devices",
        {
            "data": {
                "type": "devices",
                "attributes": {
                    "name": f"GitHub Development Device {suffix}",
                    "platform": "IOS",
                    "udid": DEVICE_UDID,
                },
            }
        },
    )
    return created["data"], True


def find_bundle_id():
    rows = all_rows(
        query(
            "/v1/bundleIds",
            {
                "filter[identifier]": BUNDLE_IDENTIFIER,
                "limit": "200",
            },
        )
    )
    if not rows:
        raise SystemExit(
            f"Bundle ID {BUNDLE_IDENTIFIER!r} is not registered in the Apple Developer account"
        )
    return rows[0]


def existing_identity_is_usable():
    if not (
        EXISTING_CERTIFICATE_ID
        and EXISTING_P12_PATH
        and EXISTING_PASSWORD_PATH
        and Path(EXISTING_P12_PATH).is_file()
        and Path(EXISTING_PASSWORD_PATH).is_file()
    ):
        return None
    try:
        response = request("GET", f"/v1/certificates/{EXISTING_CERTIFICATE_ID}")
    except APIError as exc:
        if exc.status in (404, 410):
            return None
        raise

    cert = response.get("data", {})
    attrs = cert.get("attributes", {})
    if attrs.get("certificateType") != "IOS_DEVELOPMENT":
        return None
    if attrs.get("activated") is False:
        return None

    expiration = attrs.get("expirationDate")
    if expiration:
        try:
            expires = dt.datetime.fromisoformat(expiration.replace("Z", "+00:00"))
            if expires <= dt.datetime.now(dt.timezone.utc) + dt.timedelta(days=1):
                return None
        except ValueError:
            pass

    shutil.copy2(EXISTING_P12_PATH, P12_PATH)
    shutil.copy2(EXISTING_PASSWORD_PATH, PASSWORD_PATH)
    CERT_ID_PATH.write_text(EXISTING_CERTIFICATE_ID + "\n")
    os.chmod(PASSWORD_PATH, 0o600)
    return cert


def create_development_identity():
    from cryptography.hazmat.primitives.asymmetric import rsa

    key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    common_name = f"GitHub iOS Development {os.environ.get('GITHUB_RUN_ID', int(time.time()))}"
    csr = (
        x509.CertificateSigningRequestBuilder()
        .subject_name(
            x509.Name(
                [
                    x509.NameAttribute(NameOID.COMMON_NAME, common_name),
                    x509.NameAttribute(NameOID.ORGANIZATION_NAME, TEAM_ID),
                ]
            )
        )
        .sign(key, hashes.SHA256())
    )
    csr_pem = csr.public_bytes(serialization.Encoding.PEM).decode("ascii")

    created = request(
        "POST",
        "/v1/certificates",
        {
            "data": {
                "type": "certificates",
                "attributes": {
                    "certificateType": "IOS_DEVELOPMENT",
                    "csrContent": csr_pem,
                },
            }
        },
    )["data"]

    cert_der = base64.b64decode(created["attributes"]["certificateContent"])
    certificate = x509.load_der_x509_certificate(cert_der)
    password = secrets.token_urlsafe(24)

    p12_bytes = pkcs12.serialize_key_and_certificates(
        name=b"Apple Development",
        key=key,
        cert=certificate,
        cas=None,
        encryption_algorithm=serialization.BestAvailableEncryption(password.encode()),
    )

    P12_PATH.write_bytes(p12_bytes)
    PASSWORD_PATH.write_text(password + "\n")
    CERT_ID_PATH.write_text(created["id"] + "\n")
    os.chmod(P12_PATH, 0o600)
    os.chmod(PASSWORD_PATH, 0o600)
    return created


def create_profile(bundle_resource_id, certificate_id, device_id):
    profile_name = f"GitHub Development {int(time.time())}"
    created = request(
        "POST",
        "/v1/profiles",
        {
            "data": {
                "type": "profiles",
                "attributes": {
                    "name": profile_name,
                    "profileType": "IOS_APP_DEVELOPMENT",
                },
                "relationships": {
                    "bundleId": {
                        "data": {"type": "bundleIds", "id": bundle_resource_id}
                    },
                    "certificates": {
                        "data": [{"type": "certificates", "id": certificate_id}]
                    },
                    "devices": {
                        "data": [{"type": "devices", "id": device_id}]
                    },
                },
            }
        },
    )["data"]
    PROFILE_PATH.write_bytes(base64.b64decode(created["attributes"]["profileContent"]))
    return created


def main():
    validate_inputs()
    device, registered_now = get_or_register_device()
    bundle = find_bundle_id()

    certificate = existing_identity_is_usable()
    identity_created_now = certificate is None
    if identity_created_now:
        try:
            certificate = create_development_identity()
        except APIError as exc:
            if exc.status in (403, 409):
                raise SystemExit(
                    "Apple refused creation of a new iOS development certificate. "
                    "Check the API key role/access and your active development-certificate limit."
                ) from exc
            raise

    profile = create_profile(bundle["id"], certificate["id"], device["id"])

    cert_attrs = certificate.get("attributes", {})
    profile_attrs = profile.get("attributes", {})
    info = {
        "bundleIdentifier": BUNDLE_IDENTIFIER,
        "certificateId": certificate["id"],
        "certificateType": cert_attrs.get("certificateType", "IOS_DEVELOPMENT"),
        "certificateExpirationDate": cert_attrs.get("expirationDate"),
        "deviceId": device["id"],
        "deviceName": device.get("attributes", {}).get("name"),
        "deviceRegisteredByThisRun": registered_now,
        "identityCreatedByThisRun": identity_created_now,
        "profileId": profile["id"],
        "profileName": profile_attrs.get("name"),
        "profileType": profile_attrs.get("profileType", "IOS_APP_DEVELOPMENT"),
        "profileExpirationDate": profile_attrs.get("expirationDate"),
    }
    INFO_PATH.write_text(json.dumps(info, indent=2) + "\n")

    print("Development signing assets generated successfully.")
    print(f"Bundle ID: {BUNDLE_IDENTIFIER}")
    print(f"Certificate ID: {certificate['id']}")
    print(f"Profile ID: {profile['id']}")
    print(f"Registered device this run: {registered_now}")
    print(f"Created certificate this run: {identity_created_now}")


if __name__ == "__main__":
    main()
