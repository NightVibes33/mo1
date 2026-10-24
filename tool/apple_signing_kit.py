#!/usr/bin/env python3
"""Generate an Apple Distribution certificate and Ad Hoc provisioning profile.

The script uses a Team App Store Connect API key from environment variables.
It never prints the private API key and writes all generated material to the
requested output directory for the GitHub Actions workflow to encrypt.
"""

from __future__ import annotations

import argparse
import base64
import json
import os
import sys
import time
from pathlib import Path
from typing import Any
from urllib.parse import urljoin

import jwt
import requests

API_ROOT = "https://api.appstoreconnect.apple.com"


class AppleAPIError(RuntimeError):
    pass


def required_env(name: str) -> str:
    value = os.environ.get(name, "").strip()
    if not value:
        raise AppleAPIError(f"Missing required environment variable: {name}")
    return value


def normalize_private_key(value: str) -> str:
    # GitHub secrets may contain real newlines or escaped newlines.
    value = value.strip().replace("\\n", "\n")
    if "BEGIN PRIVATE KEY" not in value:
        raise AppleAPIError("APP_STORE_CONNECT_API_KEY_P8 is not a valid .p8 private key")
    return value + ("\n" if not value.endswith("\n") else "")


def make_token() -> str:
    key_id = required_env("APP_STORE_CONNECT_KEY_ID")
    issuer_id = required_env("APP_STORE_CONNECT_ISSUER_ID")
    private_key = normalize_private_key(required_env("APP_STORE_CONNECT_API_KEY_P8"))
    now = int(time.time())
    return jwt.encode(
        {"iss": issuer_id, "iat": now, "exp": now + 1200, "aud": "appstoreconnect-v1"},
        private_key,
        algorithm="ES256",
        headers={"kid": key_id, "typ": "JWT"},
    )


class AppleClient:
    def __init__(self) -> None:
        self.session = requests.Session()
        self.session.headers.update(
            {
                "Authorization": f"Bearer {make_token()}",
                "Accept": "application/json",
                "Content-Type": "application/json",
            }
        )

    def request(
        self,
        method: str,
        path_or_url: str,
        *,
        params: dict[str, Any] | None = None,
        payload: dict[str, Any] | None = None,
        expected: tuple[int, ...] = (200,),
    ) -> dict[str, Any]:
        url = path_or_url if path_or_url.startswith("http") else urljoin(API_ROOT, path_or_url)
        last_response: requests.Response | None = None
        for attempt in range(5):
            response = self.session.request(
                method,
                url,
                params=params,
                json=payload,
                timeout=60,
            )
            last_response = response
            if response.status_code in expected:
                if response.status_code == 204 or not response.content:
                    return {}
                return response.json()
            if response.status_code == 429 or 500 <= response.status_code < 600:
                wait_seconds = min(2**attempt, 16)
                time.sleep(wait_seconds)
                continue
            break

        assert last_response is not None
        try:
            details = last_response.json()
        except ValueError:
            details = last_response.text[:1000]
        raise AppleAPIError(
            f"Apple API {method} {url} failed with HTTP {last_response.status_code}: "
            f"{json.dumps(details, ensure_ascii=False)}"
        )

    def all_pages(
        self, path: str, *, params: dict[str, Any] | None = None
    ) -> list[dict[str, Any]]:
        items: list[dict[str, Any]] = []
        next_url: str | None = path
        next_params = params
        while next_url:
            response = self.request("GET", next_url, params=next_params)
            items.extend(response.get("data", []))
            next_url = response.get("links", {}).get("next")
            next_params = None
        return items


def ensure_bundle_id(client: AppleClient, identifier: str, name: str) -> dict[str, Any]:
    response = client.request(
        "GET",
        "/v1/bundleIds",
        params={"filter[identifier]": identifier, "limit": 10},
    )
    matches = response.get("data", [])
    if matches:
        bundle = matches[0]
        print(f"Using existing Bundle ID: {identifier} ({bundle['id']})")
        return bundle

    payload = {
        "data": {
            "type": "bundleIds",
            "attributes": {
                "identifier": identifier,
                "name": name,
                "platform": "IOS",
            },
        }
    }
    response = client.request(
        "POST", "/v1/bundleIds", payload=payload, expected=(201,)
    )
    bundle = response["data"]
    print(f"Created Bundle ID: {identifier} ({bundle['id']})")
    return bundle


def enabled_ios_devices(client: AppleClient) -> list[dict[str, Any]]:
    devices = client.all_pages("/v1/devices", params={"limit": 200})
    result = []
    for device in devices:
        attributes = device.get("attributes", {})
        if attributes.get("status") != "ENABLED":
            continue
        if attributes.get("platform") not in ("IOS", None):
            continue
        result.append(device)
    if not result:
        raise AppleAPIError(
            "No enabled iOS/iPadOS devices are registered in the Apple Developer account"
        )
    print(f"Found {len(result)} enabled iOS/iPadOS device(s)")
    return result


def create_certificate(
    client: AppleClient, csr_path: Path, output_dir: Path
) -> dict[str, Any]:
    csr_content = csr_path.read_text(encoding="utf-8").strip()
    payload = {
        "data": {
            "type": "certificates",
            "attributes": {
                "certificateType": "IOS_DISTRIBUTION",
                "csrContent": csr_content,
            },
        }
    }
    response = client.request(
        "POST", "/v1/certificates", payload=payload, expected=(201,)
    )
    certificate = response["data"]
    attributes = certificate["attributes"]
    certificate_bytes = base64.b64decode(attributes["certificateContent"])
    (output_dir / "AppleDistribution.cer").write_bytes(certificate_bytes)
    print(
        "Created Apple Distribution certificate "
        f"{certificate['id']} expiring {attributes.get('expirationDate', 'unknown')}"
    )
    return certificate


def create_profile(
    client: AppleClient,
    *,
    bundle: dict[str, Any],
    certificate: dict[str, Any],
    devices: list[dict[str, Any]],
    profile_name: str,
    output_dir: Path,
) -> dict[str, Any]:
    unique_name = f"{profile_name} {time.strftime('%Y%m%d-%H%M%S', time.gmtime())}"
    payload = {
        "data": {
            "type": "profiles",
            "attributes": {
                "name": unique_name,
                "profileType": "IOS_APP_ADHOC",
            },
            "relationships": {
                "bundleId": {
                    "data": {"type": "bundleIds", "id": bundle["id"]}
                },
                "certificates": {
                    "data": [
                        {"type": "certificates", "id": certificate["id"]}
                    ]
                },
                "devices": {
                    "data": [
                        {"type": "devices", "id": device["id"]}
                        for device in devices
                    ]
                },
            },
        }
    }
    response = client.request(
        "POST", "/v1/profiles", payload=payload, expected=(201,)
    )
    profile = response["data"]
    attributes = profile["attributes"]
    profile_bytes = base64.b64decode(attributes["profileContent"])
    profile_path = output_dir / "NightVibes33-AdHoc.mobileprovision"
    profile_path.write_bytes(profile_bytes)
    print(
        f"Created Ad Hoc profile {attributes.get('uuid', profile['id'])} "
        f"for {len(devices)} device(s)"
    )
    return profile


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--bundle-id", required=True)
    parser.add_argument("--bundle-name", required=True)
    parser.add_argument("--profile-name", required=True)
    parser.add_argument("--csr-path", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    args.output_dir.mkdir(parents=True, exist_ok=True)
    if not args.csr_path.is_file():
        raise AppleAPIError(f"CSR file does not exist: {args.csr_path}")

    client = AppleClient()
    bundle = ensure_bundle_id(client, args.bundle_id, args.bundle_name)
    devices = enabled_ios_devices(client)
    certificate = create_certificate(client, args.csr_path, args.output_dir)
    profile = create_profile(
        client,
        bundle=bundle,
        certificate=certificate,
        devices=devices,
        profile_name=args.profile_name,
        output_dir=args.output_dir,
    )

    certificate_attributes = certificate.get("attributes", {})
    profile_attributes = profile.get("attributes", {})
    metadata = {
        "bundle_identifier": args.bundle_id,
        "certificate_id": certificate["id"],
        "certificate_serial_number": certificate_attributes.get("serialNumber"),
        "certificate_expiration": certificate_attributes.get("expirationDate"),
        "profile_id": profile["id"],
        "profile_uuid": profile_attributes.get("uuid"),
        "profile_name": profile_attributes.get("name"),
        "profile_expiration": profile_attributes.get("expirationDate"),
        "included_device_count": len(devices),
    }
    (args.output_dir / "signing-metadata.json").write_text(
        json.dumps(metadata, indent=2) + "\n", encoding="utf-8"
    )
    print("Apple signing material generated successfully")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except AppleAPIError as error:
        print(f"ERROR: {error}", file=sys.stderr)
        raise SystemExit(1)
