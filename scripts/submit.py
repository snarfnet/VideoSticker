import jwt, time, requests, sys

KEY_ID       = 'WDXGY9WX55'
ISSUER       = '2be0734f-943a-4d61-9dc9-5d9045c46fec'
APP_ID       = '6782303634'
BUILD_NUMBER = sys.argv[1]

if APP_ID.startswith('TODO'):
    print('APP_ID 未設定。ASCでアプリ作成後に scripts/submit.py を更新してください。')
    sys.exit(0)

p8 = open('/tmp/asc_key.p8').read()

def make_token():
    return jwt.encode(
        {'iss': ISSUER, 'iat': int(time.time()), 'exp': int(time.time()) + 1200, 'aud': 'appstoreconnect-v1'},
        p8, algorithm='ES256', headers={'kid': KEY_ID}
    )

def headers():
    return {'Authorization': f'Bearer {make_token()}', 'Content-Type': 'application/json'}

def api(method, path, **kwargs):
    return requests.request(method, f'https://api.appstoreconnect.apple.com/v1{path}',
        headers=headers(), **kwargs)

print(f'Waiting for build {BUILD_NUMBER}...')
build_id = None
for i in range(80):
    r = api('GET', f'/builds?filter[app]={APP_ID}&filter[version]={BUILD_NUMBER}&filter[processingState]=VALID&limit=1')
    data = r.json()
    if data.get('data'):
        build_id = data['data'][0]['id']
        print(f'Build ready: {build_id}')
        break
    print(f'  Waiting... ({i+1}/80)')
    time.sleep(30)

if not build_id:
    print('Build not found. Check ASC manually.')
    sys.exit(0)

api('PATCH', f'/builds/{build_id}',
    json={'data': {'type': 'builds', 'id': build_id,
                   'attributes': {'usesNonExemptEncryption': False}}})

r = api('GET', f'/apps/{APP_ID}/appStoreVersions?filter[platform]=IOS&limit=1')
versions = r.json().get('data', [])
version_id    = None
version_state = None
if versions:
    version_id    = versions[0]['id']
    version_state = versions[0]['attributes']['appStoreState']
    print(f'Version: {version_id} state={version_state}')

if version_state in ('WAITING_FOR_REVIEW', 'IN_REVIEW'):
    print('Already in review. Done.')
    sys.exit(0)

if not version_id or version_state == 'READY_FOR_DISTRIBUTION':
    r = api('POST', '/appStoreVersions', json={'data': {
        'type': 'appStoreVersions',
        'attributes': {'platform': 'IOS', 'versionString': '1.0'},
        'relationships': {'app': {'data': {'type': 'apps', 'id': APP_ID}}}
    }})
    version_id = r.json()['data']['id']

api('PATCH', f'/appStoreVersions/{version_id}/relationships/build',
    json={'data': {'type': 'builds', 'id': build_id}})
print('Build assigned to version')
print('TestFlight ready. Skipping review submission for manual testing.')
sys.exit(0)
