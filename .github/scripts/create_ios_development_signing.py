#!/usr/bin/env python3
import base64
import json
import os
import re
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
PRIVATE_KEY = os.environ["APP_STORE_CONNECT_API_KEY_P8"].strip()

SIGNING_MODE = os.environ.get("SIGNING_MODE", "apple_development").strip()
DEVICE_UDID = os.environ.get("DEVICE_UDID", "").strip()
BUNDLE_IDENTIFIER = os.environ.get("BUNDLE_IDENTIFIER", "").strip()
P12_PASSWORD = os.environ["P12_PASSWORD"]

OUTPUT = Path("output")
OUTPUT.mkdir(parents=True, exist_ok=True)

P12_PATH = OUTPUT / "signing-certificate.p12"
CERT_ID_PATH = OUTPUT / "certificate-id.txt"
PROFILE_PATH = OUTPUT / "profile.mobileprovision"
INFO_PATH = OUTPUT / "signing-info.json"

MODES = {
    "apple_development": {
        "label": "Apple Development",
        "certificate_type": "DEVELOPMENT",
        "profile_type": "IOS_APP_DEVELOPMENT",
        "requires_device": True,
        "requires_explicit_bundle": False,
        "kind": "development",
    },
    "ios_development_legacy": {
        "label": "Legacy iOS Development",
        "certificate_type": "IOS_DEVELOPMENT",
        "profile_type": "IOS_APP_DEVELOPMENT",
        "requires_device": True,
        "requires_explicit_bundle": False,
        "kind": "development",
    },
    "ad_hoc_apple_distribution": {
        "label": "Ad Hoc — Apple Distribution",
        "certificate_type": "DISTRIBUTION",
        "profile_type": "IOS_APP_ADHOC",
        "requires_device": True,
        "requires_explicit_bundle": False,
        "kind": "ad_hoc",
    },
    "ad_hoc_ios_distribution_legacy": {
        "label": "Ad Hoc — Legacy iOS Distribution",
        "certificate_type": "IOS_DISTRIBUTION",
        "profile_type": "IOS_APP_ADHOC",
        "requires_device": True,
        "requires_explicit_bundle": False,
        "kind": "ad_hoc",
    },
    "app_store_apple_distribution": {
        "label": "App Store Connect — Apple Distribution",
        "certificate_type": "DISTRIBUTION",
        "profile_type": "IOS_APP_STORE",
        "requires_device": False,
        "requires_explicit_bundle": True,
        "kind": "app_store",
    },
    "app_store_ios_distribution_legacy": {
        "label": "App Store Connect — Legacy iOS Distribution",
        "certificate_type": "IOS_DISTRIBUTION",
        "profile_type": "IOS_APP_STORE",
        "requires_device": False,
        "requires_explicit_bundle": True,
        "kind": "app_store",
    },
}


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


def validate_inputs(mode):
    if not re.fullmatch(r"[A-Z0-9]{10}", TEAM_ID, re.IGNORECASE):
        raise SystemExit("APPLE_TEAM_ID has an unexpected format")
    if not P12_PASSWORD:
        raise SystemExit("P12 password must not be empty")
    if len(P12_PASSWORD) > 256:
        raise SystemExit("P12 password is too long")

    if mode["requires_device"]:
        if not re.fullmatch(r"[A-Za-z0-9-]{20,64}", DEVICE_UDID):
            raise SystemExit(f"{mode['label']} requires a valid iPhone/iPad UDID")

    if mode["requires_explicit_bundle"] and not BUNDLE_IDENTIFIER:
        raise SystemExit(f"{mode['label']} requires an explicit bundle identifier")

    if BUNDLE_IDENTIFIER:
        if BUNDLE_IDENTIFIER == "*":
            if mode["requires_explicit_bundle"]:
                raise SystemExit(f"{mode['label']} cannot use a wildcard bundle identifier")
        elif not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9.-]{1,253}[A-Za-z0-9]", BUNDLE_IDENTIFIER):
            raise SystemExit("Bundle identifier has an unexpected format")


def get_or_register_device():
    rows = all_rows(query("/v1/devices", {"filter[udid]": DEVICE_UDID, "limit": "200"}))
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
                    f"Apple API response: {exc}"
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
                    "name": f"GitHub Signing Device {suffix}",
                    "platform": "IOS",
                    "udid": DEVICE_UDID,
                },
            }
        },
    )
    return created["data"], True


def find_or_create_bundle_id(identifier):
    rows = all_rows("/v1/bundleIds?limit=200")
    exact = []
    for row in rows:
        attrs = row.get("attributes", {})
        existing = (attrs.get("identifier") or "").strip()
        platform = attrs.get("platform")
        if existing == identifier and platform in ("IOS", "UNIVERSAL", None):
            exact.append(row)

    if exact:
        exact.sort(key=lambda row: 0 if row.get("attributes", {}).get("platform") == "IOS" else 1)
        return exact[0], False

    display_identifier = "Wildcard" if identifier == "*" else identifier
    payload = {
        "data": {
            "type": "bundleIds",
            "attributes": {
                "identifier": identifier,
                "name": f"GitHub Signing {display_identifier}"[:100],
                "platform": "IOS",
            },
        }
    }
    try:
        created = request("POST", "/v1/bundleIds", payload)["data"]
        return created, True
    except APIError as exc:
        if exc.status == 409:
            rows = all_rows("/v1/bundleIds?limit=200")
            for row in rows:
                attrs = row.get("attributes", {})
                if (attrs.get("identifier") or "").strip() == identifier:
                    return row, False
        raise SystemExit(
            f"Apple would not find or create App ID {identifier!r}. Apple API response: {exc}"
        ) from exc


def create_identity(mode):
    from cryptography.hazmat.primitives.asymmetric import rsa

    key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    run_id = os.environ.get("GITHUB_RUN_ID", str(int(time.time())))
    common_name = f"GitHub {mode['label']} {run_id}"
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
                    "certificateType": mode["certificate_type"],
                    "csrContent": csr_pem,
                },
            }
        },
    )["data"]

    cert_der = base64.b64decode(created["attributes"]["certificateContent"])
    certificate = x509.load_der_x509_certificate(cert_der)

    p12_name = mode["label"].encode("utf-8")
    p12_bytes = pkcs12.serialize_key_and_certificates(
        name=p12_name,
        key=key,
        cert=certificate,
        cas=None,
        encryption_algorithm=serialization.BestAvailableEncryption(P12_PASSWORD.encode("utf-8")),
    )

    P12_PATH.write_bytes(p12_bytes)
    CERT_ID_PATH.write_text(created["id"] + "\n")
    os.chmod(P12_PATH, 0o600)
    return created


def create_profile(mode, bundle_resource_id, certificate_id, device_id=None):
    run_id = os.environ.get("GITHUB_RUN_ID", str(int(time.time())))
    profile_name = f"GitHub {mode['label']} {run_id}"[:100]

    relationships = {
        "bundleId": {"data": {"type": "bundleIds", "id": bundle_resource_id}},
        "certificates": {"data": [{"type": "certificates", "id": certificate_id}]},
    }
    if mode["requires_device"]:
        relationships["devices"] = {"data": [{"type": "devices", "id": device_id}]}

    created = request(
        "POST",
        "/v1/profiles",
        {
            "data": {
                "type": "profiles",
                "attributes": {
                    "name": profile_name,
                    "profileType": mode["profile_type"],
                },
                "relationships": relationships,
            }
        },
    )["data"]
    PROFILE_PATH.write_bytes(base64.b64decode(created["attributes"]["profileContent"]))
    return created


def main():
    mode = MODES.get(SIGNING_MODE)
    if not mode:
        raise SystemExit(f"Unknown SIGNING_MODE: {SIGNING_MODE}")
    validate_inputs(mode)

    device = None
    registered_now = False
    if mode["requires_device"]:
        device, registered_now = get_or_register_device()

    effective_bundle_id = BUNDLE_IDENTIFIER or "*"
    bundle, bundle_created_now = find_or_create_bundle_id(effective_bundle_id)

    try:
        certificate = create_identity(mode)
    except APIError as exc:
        if exc.status in (403, 409):
            raise SystemExit(
                f"Apple refused creation of a fresh {mode['label']} certificate. "
                f"Apple API response: {exc}. Existing certificate limits are tracked separately by certificate type."
            ) from exc
        raise

    try:
        profile = create_profile(
            mode,
            bundle["id"],
            certificate["id"],
            device["id"] if device else None,
        )
    except APIError as exc:
        raise SystemExit(
            f"The {mode['label']} certificate was created, but Apple refused the {mode['profile_type']} profile. "
            f"Apple API response: {exc}"
        ) from exc

    cert_attrs = certificate.get("attributes", {})
    profile_attrs = profile.get("attributes", {})
    bundle_attrs = bundle.get("attributes", {})
    info = {
        "signingMode": SIGNING_MODE,
        "signingModeLabel": mode["label"],
        "signingKind": mode["kind"],
        "bundleIdentifier": bundle_attrs.get("identifier", effective_bundle_id),
        "bundleResourceId": bundle["id"],
        "bundleCreatedByThisRun": bundle_created_now,
        "wildcard": effective_bundle_id == "*",
        "certificateId": certificate["id"],
        "certificateType": cert_attrs.get("certificateType", mode["certificate_type"]),
        "certificateExpirationDate": cert_attrs.get("expirationDate"),
        "identityCreatedByThisRun": True,
        "profileId": profile["id"],
        "profileName": profile_attrs.get("name"),
        "profileType": profile_attrs.get("profileType", mode["profile_type"]),
        "profileExpirationDate": profile_attrs.get("expirationDate"),
        "deviceRequired": mode["requires_device"],
        "deviceId": device["id"] if device else None,
        "deviceName": device.get("attributes", {}).get("name") if device else None,
        "deviceRegisteredByThisRun": registered_now,
        "notes": (
            "Wildcard profiles work only for entitlements allowed by wildcard App IDs. "
            "Capabilities that require an explicit App ID need a matching explicit bundle identifier/profile."
            if effective_bundle_id == "*"
            else "Explicit App ID signing profile."
        ),
    }
    INFO_PATH.write_text(json.dumps(info, indent=2) + "\n")

    print("iOS signing assets generated successfully.")
    print(f"Mode: {mode['label']} ({SIGNING_MODE})")
    print(f"Certificate type: {mode['certificate_type']}")
    print(f"Profile type: {mode['profile_type']}")
    print(f"Bundle ID: {effective_bundle_id}")
    print(f"Certificate ID: {certificate['id']}")
    print(f"Profile ID: {profile['id']}")
    print(f"Device required: {mode['requires_device']}")
    if device:
        print(f"Registered device this run: {registered_now}")
    print("Created certificate this run: True")


if __name__ == "__main__":
    main()
