#!/usr/bin/env python3
from __future__ import annotations

import re
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

page_function = r'''def page(base_url: str) -> bytes:
    install_manifest = urllib.parse.quote(
        f"{base_url}/manifest.plist?session={SESSION}", safe=""
    )
    install_url = f"itms-services://?action=download-manifest&url={install_manifest}"
    safe_session = html.escape(SESSION)
    return f"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
<meta name="theme-color" content="#09090b">
<title>Dopamine iPad 5</title>
<style>
:root{{color-scheme:dark;font-family:-apple-system,BlinkMacSystemFont,"SF Pro Display",sans-serif}}
*{{box-sizing:border-box}}
body{{margin:0;min-height:100vh;display:grid;place-items:center;padding:22px;background:radial-gradient(circle at 50% -10%,#4b285f 0,#111522 38%,#07090e 72%);color:#f7f8fb}}
main{{width:min(100%,500px);padding:28px;border:1px solid rgba(255,255,255,.12);border-radius:28px;background:rgba(12,15,22,.92);box-shadow:0 30px 90px rgba(0,0,0,.5)}}
h1{{margin:0 0 24px;font-size:clamp(32px,8vw,44px);letter-spacing:-.045em}}
.actions{{display:grid;gap:13px}}
a.button{{display:block;padding:18px 19px;border-radius:15px;text-align:center;text-decoration:none;font-size:17px;font-weight:900}}
a.profile{{color:#f3f6ff;border:1px solid rgba(255,255,255,.2);background:rgba(255,255,255,.07)}}
a.install{{color:#071009;background:linear-gradient(135deg,#92ffb9,#6ee7ff)}}
a.disabled{{pointer-events:none;opacity:.42}}
</style>
</head>
<body>
<main>
<h1>Dopamine iPad 5</h1>
<div class="actions">
<a class="button profile" href="/enroll.mobileconfig?session={safe_session}">Install Registration Profile</a>
<a id="install" class="button install disabled" href="{html.escape(install_url)}" aria-disabled="true">Preparing Latest Signed IPA…</a>
</div>
</main>
<script>
const s={json.dumps(SESSION)};
const install=document.getElementById('install');
async function poll(){{
  try{{
    const r=await fetch('/status?session='+encodeURIComponent(s),{{cache:'no-store'}});
    const j=await r.json();
    if(j.status==='ready'){{
      install.classList.remove('disabled');
      install.removeAttribute('aria-disabled');
      install.textContent='Install Latest Signed IPA';
    }}else if(j.status==='error'){{
      install.textContent='Registration Failed — Reinstall Profile';
    }}else{{
      install.textContent='Preparing Latest Signed IPA…';
    }}
  }}catch(e){{
    install.textContent='Preparing Latest Signed IPA…';
  }}
}}
poll();setInterval(poll,2000);
</script>
</body>
</html>""".encode()
'''

pattern = re.compile(
    r"def page\(base_url: str\) -> bytes:\n.*?\n\n\nclass Handler",
    re.DOTALL,
)
text, count = pattern.subn(lambda _: page_function + "\n\nclass Handler", text, count=1)
if count != 1:
    raise SystemExit(f"Could not replace installer page function: matches={count}")

required = (
    '"profileType": "IOS_APP_DEVELOPMENT"',
    'allowed["get-task-allow"] = True',
    "Install Registration Profile",
    "Install Latest Signed IPA",
)
missing = [item for item in required if item not in text]
if missing:
    raise SystemExit(f"Patch verification failed: {missing}")

path.write_text(text, encoding="utf-8")
