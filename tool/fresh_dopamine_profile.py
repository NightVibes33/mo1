#!/usr/bin/env python3
import base64, hashlib, json, os, time, urllib.parse, urllib.request
from pathlib import Path
import jwt

KEY_ID=os.environ['APP_STORE_CONNECT_KEY_ID']
ISSUER_ID=os.environ['APP_STORE_CONNECT_ISSUER_ID']
PRIVATE_KEY=os.environ['APP_STORE_CONNECT_API_KEY_P8'].strip().replace('\\n','\n')
if 'BEGIN PRIVATE KEY' not in PRIVATE_KEY:
    PRIVATE_KEY=base64.b64decode(''.join(PRIVATE_KEY.split())).decode()
BASE='https://api.appstoreconnect.apple.com'

def token():
    now=int(time.time())
    return jwt.encode({'iss':ISSUER_ID,'iat':now,'exp':now+900,'aud':'appstoreconnect-v1'},PRIVATE_KEY,algorithm='ES256',headers={'kid':KEY_ID,'typ':'JWT'})

def req(method,path,payload=None):
    data=json.dumps(payload).encode() if payload is not None else None
    h={'Authorization':'Bearer '+token(),'Accept':'application/json'}
    if data is not None: h['Content-Type']='application/json'
    r=urllib.request.Request(BASE+path,data=data,headers=h,method=method)
    with urllib.request.urlopen(r,timeout=60) as resp:
        raw=resp.read()
        return json.loads(raw) if raw else {}

def all_rows(path):
    out=[]
    while path:
        j=req('GET',path)
        out.extend(j.get('data',[]))
        nxt=j.get('links',{}).get('next')
        if nxt:
            p=urllib.parse.urlsplit(nxt); path=p.path+(('?'+p.query) if p.query else '')
        else: path=None
    return out

bundle_id=os.environ['DOPAMINE_BUNDLE_ID']
cert_sha1=os.environ['DOPAMINE_CERT_SHA1'].replace(' ','').upper()
rows=all_rows('/v1/bundleIds?'+urllib.parse.urlencode({'filter[identifier]':bundle_id,'limit':'200'}))
if not rows: raise SystemExit('bundle ID not found: '+bundle_id)
bundle_res=rows[0]['id']
cert_res=None
for row in all_rows('/v1/certificates?'+urllib.parse.urlencode({'filter[certificateType]':'IOS_DEVELOPMENT','limit':'200'})):
    c=row.get('attributes',{}).get('certificateContent')
    if c and hashlib.sha1(base64.b64decode(c)).hexdigest().upper()==cert_sha1:
        cert_res=row['id']; break
if not cert_res: raise SystemExit('matching development certificate not found in App Store Connect')
devices=[r['id'] for r in all_rows('/v1/devices?'+urllib.parse.urlencode({'filter[platform]':'IOS','filter[status]':'ENABLED','limit':'200'}))]
if not devices: raise SystemExit('no enabled iOS devices found')
payload={'data':{'type':'profiles','attributes':{'name':f'Dopamine iPad5 Fresh {int(time.time())}','profileType':'IOS_APP_DEVELOPMENT'},'relationships':{'bundleId':{'data':{'type':'bundleIds','id':bundle_res}},'certificates':{'data':[{'type':'certificates','id':cert_res}]},'devices':{'data':[{'type':'devices','id':d} for d in devices]}}}}
created=req('POST','/v1/profiles',payload)
profile=base64.b64decode(created['data']['attributes']['profileContent'])
Path('work/profile.mobileprovision').write_bytes(profile)
print(f'fresh profile generated with {len(devices)} enabled device(s)')
