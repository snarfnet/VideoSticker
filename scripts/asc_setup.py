import jwt, time, requests, sys, json, base64

KEY_ID = 'WDXGY9WX55'
ISSUER = '2be0734f-943a-4d61-9dc9-5d9045c46fec'
APP_ID = '6782303634'
P8_PATH = 'C:/Users/Windows/Downloads/AuthKey_WDXGY9WX55.p8'

p8 = open(P8_PATH).read()


def tok():
    return jwt.encode(
        {'iss': ISSUER, 'iat': int(time.time()), 'exp': int(time.time()) + 1200, 'aud': 'appstoreconnect-v1'},
        p8, algorithm='ES256', headers={'kid': KEY_ID})


def api(method, path, **kw):
    r = requests.request(method, f'https://api.appstoreconnect.apple.com/v1{path}',
                         headers={'Authorization': f'Bearer {tok()}', 'Content-Type': 'application/json'}, **kw)
    return r


def show(label, r):
    ok = r.status_code < 300
    print(f'[{"OK" if ok else "ERR"} {r.status_code}] {label}')
    if not ok:
        print('   ', r.text[:400])
    return r


# ---- texts ----
DESC_JA = """撮った動画から、動くスタンプを作れるアプリです。

お辞儀や挨拶など2〜4秒の動画を撮るだけ。人物だけを自動で切り抜いて、6コマのアニメーションスタンプ（APNG）にします。

■ 特長
・動画を撮る、またはアルバムから選ぶだけ
・人物を自動で切り抜き（背景を消す／残すは切り替え可能）
・動きを判定して、ぴったりの文言を自動でグループ分け
・スワイプで文言を微調整
・サラリーマンの挨拶24文言を収録（お辞儀・お願い・確認OKなど）
・書き出してそのまま共有

ビジネスチャットで使える、ちょっと丁寧で動くスタンプが手軽に作れます。"""

KEYS_JA = "スタンプ,動くスタンプ,アニメ,動画,APNG,挨拶,ビジネス,お辞儀,切り抜き,人物,背景透過,自作,gif,作成"

DESC_EN = """Turn your own videos into animated stickers.

Record a short 2-4 second clip - a bow, a wave, a greeting - and the app cuts out the person and builds a 6-frame animated sticker (APNG).

Features
- Record a video or pick one from your library
- Automatic person cutout (keep or remove the background)
- Motion detection sorts your clip into the right caption group
- Swipe to fine-tune the caption
- 24 ready-made business greetings (bow, request, confirm, and more)
- Export and share right away

Make polite, animated stickers for business chat in seconds."""

KEYS_EN = "sticker,animated sticker,video sticker,apng,gif maker,greeting,business,bow,cutout,person,background"

URL = 'https://snarfnet.github.io/'

JA_TEXT = {'description': DESC_JA, 'keywords': KEYS_JA}
EN_TEXT = {'description': DESC_EN, 'keywords': KEYS_EN}


def pick(locale):
    if locale.startswith('ja'):
        return JA_TEXT
    return EN_TEXT


# ---- 1. category ----
r = api('GET', f'/apps/{APP_ID}/appInfos?limit=10')
infos = r.json().get('data', [])
info_id = infos[0]['id']
print('appInfo', info_id, 'state', infos[0]['attributes'].get('appStoreState'))

show('primaryCategory=PHOTO_AND_VIDEO', api('PATCH', f'/appInfos/{info_id}', json={'data': {
    'type': 'appInfos', 'id': info_id,
    'relationships': {'primaryCategory': {'data': {'type': 'appCategories', 'id': 'PHOTO_AND_VIDEO'}}}}}))

# ---- 2. content rights ----
show('contentRightsDeclaration', api('PATCH', f'/apps/{APP_ID}', json={'data': {
    'type': 'apps', 'id': APP_ID,
    'attributes': {'contentRightsDeclaration': 'DOES_NOT_USE_THIRD_PARTY_CONTENT'}}}))

# ---- 3. version ----
r = api('GET', f'/apps/{APP_ID}/appStoreVersions?filter[platform]=IOS&limit=1')
version_id = r.json()['data'][0]['id']
vstate = r.json()['data'][0]['attributes']['appStoreState']
print('version', version_id, 'state', vstate)

show('copyright', api('PATCH', f'/appStoreVersions/{version_id}', json={'data': {
    'type': 'appStoreVersions', 'id': version_id,
    'attributes': {'copyright': '2026 tokyonasu'}}}))

# ---- review detail (create or patch) ----
r = api('GET', f'/appStoreVersions/{version_id}/appStoreReviewDetail')
rd = r.json().get('data')
rd_attrs = {
    'contactFirstName': 'Tokyo', 'contactLastName': 'Nasu',
    'contactEmail': 'snarfnet@gmail.com', 'contactPhone': '+14155550123',
    'demoAccountRequired': False, 'demoAccountName': '', 'demoAccountPassword': '',
    'notes': 'No account needed. Record or pick a short video, the app cuts out the person and makes an animated sticker.'}
if rd:
    show('reviewDetail PATCH', api('PATCH', f'/appStoreReviewDetails/{rd["id"]}', json={'data': {
        'type': 'appStoreReviewDetails', 'id': rd['id'], 'attributes': rd_attrs}}))
else:
    show('reviewDetail POST', api('POST', '/appStoreReviewDetails', json={'data': {
        'type': 'appStoreReviewDetails', 'attributes': rd_attrs,
        'relationships': {'appStoreVersion': {'data': {'type': 'appStoreVersions', 'id': version_id}}}}}))

# ---- 4. age rating (all NONE/False) ----
r = api('GET', f'/appInfos/{info_id}/ageRatingDeclaration')
ard = r.json().get('data')
if ard:
    ard_id = ard['id']
    none_fields = ['sexualContentGraphicAndNudity', 'gamblingSimulated',
                   'violenceRealisticProlongedGraphicOrSadistic', 'matureOrSuggestiveThemes',
                   'alcoholTobaccoOrDrugUseOrReferences', 'medicalOrTreatmentInformation', 'contests',
                   'violenceRealistic', 'gunsOrOtherWeapons', 'violenceCartoonOrFantasy',
                   'sexualContentOrNudity', 'horrorOrFearThemes', 'profanityOrCrudeHumor']
    bool_fields = ['lootBox', 'unrestrictedWebAccess', 'healthOrWellnessTopics', 'gambling',
                   'ageAssurance', 'messagingAndChat', 'parentalControls', 'advertising', 'userGeneratedContent']
    attrs = {f: 'NONE' for f in none_fields}
    attrs.update({f: False for f in bool_fields})
    show('ageRating', api('PATCH', f'/ageRatingDeclarations/{ard_id}', json={'data': {
        'type': 'ageRatingDeclarations', 'id': ard_id, 'attributes': attrs}}))
else:
    print('[WARN] no ageRatingDeclaration')

# ---- 5. privacy policy url (appInfoLocalizations) ----
r = api('GET', f'/appInfos/{info_id}/appInfoLocalizations?limit=20')
for il in r.json().get('data', []):
    loc = il['attributes'].get('locale', '')
    show(f'privacyPolicyUrl {loc}', api('PATCH', f'/appInfoLocalizations/{il["id"]}', json={'data': {
        'type': 'appInfoLocalizations', 'id': il['id'],
        'attributes': {'privacyPolicyUrl': URL}}}))

# ---- 6. version localizations (description, keywords, urls) ----
r = api('GET', f'/appStoreVersions/{version_id}/appStoreVersionLocalizations?limit=20')
locs = r.json().get('data', [])
print('locales:', [l['attributes']['locale'] for l in locs])
for loc in locs:
    code = loc['attributes']['locale']
    t = pick(code)
    show(f'versionLoc {code}', api('PATCH', f'/appStoreVersionLocalizations/{loc["id"]}', json={'data': {
        'type': 'appStoreVersionLocalizations', 'id': loc['id'],
        'attributes': {
            'description': t['description'],
            'keywords': t['keywords'],
            'supportUrl': URL,
            'marketingUrl': URL}}}))

# ---- 7. price ¥600 (JPN base) ----
r = api('GET', f'/apps/{APP_ID}/appPricePoints?filter[territory]=JPN&limit=200')
pts = r.json().get('data', [])
pp600 = next((p['id'] for p in pts if p['attributes'].get('customerPrice') == '600'), None)
print('price points found:', len(pts), 'pp600:', pp600)
if pp600:
    show('price 600 JPY', api('POST', '/appPriceSchedules', json={
        'data': {'type': 'appPriceSchedules', 'relationships': {
            'app': {'data': {'type': 'apps', 'id': APP_ID}},
            'baseTerritory': {'data': {'type': 'territories', 'id': 'JPN'}},
            'manualPrices': {'data': [{'type': 'appPrices', 'id': '${p600}'}]}}},
        'included': [{'type': 'appPrices', 'id': '${p600}',
                      'attributes': {'startDate': None},
                      'relationships': {'appPricePoint': {'data': {'type': 'appPricePoints', 'id': pp600}}}}]}))
else:
    print('[WARN] ¥600 price point not found')

print('\nDONE. Store info set. Review submission intentionally skipped (manual TestFlight testing first).')
