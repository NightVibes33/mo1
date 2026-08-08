from pathlib import Path

p = Path('signer/tools/dopamine_registration_server.py')
s = p.read_text()
old = '''            body = self.rfile.read(int(self.headers.get("Content-Length", "0")))
            values = plistlib.loads(body)
            if not isinstance(values, dict):
                raise RuntimeError("Invalid registration callback")
            self.server.state.register(values)
            self.send_response(HTTPStatus.SEE_OTHER)
            self.send_header("Location", f"{self.server.state.base_url()}/complete/?registered=1")
            self.send_header("Content-Length", "0")
            self.end_headers()
'''
new = '''            body = self.rfile.read(int(self.headers.get("Content-Length", "0")))
            try:
                values = plistlib.loads(body)
            except Exception:
                with tempfile.TemporaryDirectory(prefix="dopamine-profile-post-") as temp_name:
                    temp = Path(temp_name)
                    signed = temp / "device-response.cms"
                    decoded = temp / "device-response.plist"
                    signed.write_bytes(body)
                    decoded.write_text(run(["security", "cms", "-D", "-i", str(signed)]))
                    values = plistlib.loads(decoded.read_bytes())
            if not isinstance(values, dict):
                raise RuntimeError("Invalid registration callback")
            self.server.state.register(values)
            response_profile = {
                "PayloadContent": [],
                "PayloadOrganization": "NightVibes33",
                "PayloadDisplayName": "Dopamine iPad Registration Complete",
                "PayloadDescription": "Device registration completed for Dopamine OTA installation.",
                "PayloadVersion": 1,
                "PayloadUUID": str(uuid.uuid4()).upper(),
                "PayloadIdentifier": "com.nightvibes33.dopamine.registration.complete",
                "PayloadType": "Configuration",
            }
            content = plistlib.dumps(response_profile, fmt=plistlib.FMT_XML, sort_keys=False)
            self.send_response(HTTPStatus.OK)
            self.send_header("Content-Type", "application/x-apple-aspen-config")
            self.send_header("Content-Length", str(len(content)))
            self.end_headers()
            self.wfile.write(content)
'''
if old not in s:
    raise SystemExit('profile callback block not found')
p.write_text(s.replace(old, new, 1))
print('patched Profile Service callback')
