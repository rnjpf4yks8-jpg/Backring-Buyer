# Pedigree rank for each hip in a sale, 1 = strongest. Run: python3 score.py <data dir>
# <data dir>/ft/<id>.json: https://www.fasigtipton.com/django/api/horses/?sale=<id> for every Fasig-Tipton sale (1 to 330)
# <data dir>/kee_all.json: every node--horse from https://catalog-backend.keeneland.com/jsonapi (attributes only)
# Writes <data dir>/ranks.json; load it with: node admin.js pedigree-ranks <saleId> ranks.json
#
# Score 0-100 = 50% sire + 30% dam's produce + 20% dam's sire, each a percentile across the ranked hips:
#   sire / dam's sire: his foals' yearling and weanling prices against that year's median, recent years
#     weighted more, pulled toward half the median until he has about five sold;
#   dam: how her earlier foals sold against their year's median; no foals sold counts as 0.6x the median.
# A hip's own sale never counts toward its score.
import json, glob, math, statistics, collections, sys
S = sys.argv[1]
def norm(s): return ' '.join((s or '').upper().replace('’', "'").split())
def yr(s): return (s or '')[-4:]

# ---- Auction records: one row per offering with a sale price ----
recs = []  # (sire, dam, damsire, yob, cat, year, price, key)
for f in glob.glob(f'{S}/ft/*.json'):
    try: d = json.load(open(f))
    except Exception: continue
    for h in d:
        p = float(h.get('price') or 0)
        if p <= 0 or h.get('private_sale'): continue
        recs.append(dict(sire=norm(h['sire']), dam=norm(h['dam']), damsire=norm(h.get('sire_of_dam')),
                         yob=yr(h.get('year_of_birth')), cat=h.get('sold_as_code') or '',
                         year=(h.get('session') or h.get('last_updated') or '')[:4], price=p,
                         key=('FT', h['sale'], h['hip'])))
for x in json.load(open(f'{S}/kee_all.json')):
    p = float(x.get('field_price') or 0)
    if p <= 0: continue
    cat = {'Yearling': 'Y', 'Weanling': 'W'}.get(x['field_sold_as'], 'O')
    recs.append(dict(sire=norm(x['field_sire']), dam=norm(x['field_dam']), damsire=norm(x['field_broodmare_sire']),
                     yob=yr(x['field_foaling_date']), cat=cat, year='2026', price=p,
                     key=('KEE', x['field_sale_id'], int(x['field_hip_number']))))

# Price relative to that year's median for the same kind of offering (yearling, weanling, 2yo...).
groups = collections.defaultdict(list)
for r in recs: groups[(r['year'], r['cat'])].append(r['price'])
med = {k: statistics.median(v) for k, v in groups.items() if len(v) >= 30}
for r in recs:
    m = med.get((r['year'], r['cat']))
    r['lr'] = math.log(r['price'] / m) if m else None

def same_horse(r, h): return r['dam'] == h['dam'] and r['yob'] == h['yob']

# ---- Sire and dam-sire index: their yearlings and weanlings at auction since 2009, each year back counting 20% less ----
def recent_young(r): return r['cat'] in ('Y', 'W') and r['year'].isdigit() and r['lr'] is not None
W = collections.defaultdict(float, {str(y): 0.8 ** (2026 - y) for y in range(2000, 2027)})
by_sire, by_ds = collections.defaultdict(list), collections.defaultdict(list)
for r in recs:
    if recent_young(r):
        by_sire[r['sire']].append(r); by_ds[r['damsire']].append(r)

PRIOR_N = 5          # a sire needs about this many sold foals before his own record outweighs the default
SIRE_DEFAULT = math.log(0.5)   # unknown or barely-sold sires start at half the median price
def index(rows, h, default):
    rows = [r for r in rows if not same_horse(r, h)]
    w = sum(W[r['year']] for r in rows)
    s = sum(W[r['year']] * r['lr'] for r in rows)
    return (s + PRIOR_N * default) / (w + PRIOR_N), len(rows)

# ---- Dam's produce: earlier foals of the same dam sold at auction (any age, since 2009) ----
by_dam = collections.defaultdict(list)
for r in recs:
    if r['lr'] is not None and r['cat'] in ('Y', 'W', 'TT', 'RA', 'RB', 'BP', 'B'): by_dam[(r['dam'], r['damsire'])].append(r)
DAM_DEFAULT = math.log(0.6)
def dam_index(h):
    rows = [r for r in by_dam[(h['dam'], h['damsire'])] if not same_horse(r, h)]
    # one row per foal: the best price that foal brought
    best = {}
    for r in rows: best[r['yob'] + r['sire']] = max(best.get(r['yob'] + r['sire'], -99), r['lr'])
    v = list(best.values())
    return (sum(v) + 1 * DAM_DEFAULT) / (len(v) + 1), len(v), (max(v) if v else None)

# ---- Hips to rank ----
hips = {}
for h in json.load(open(f'{S}/ft/320.json')):
    hips.setdefault('ft-oct-2026', []).append(dict(hip=h['hip'], sire=norm(h['sire']), dam=norm(h['dam']),
        damsire=norm(h.get('sire_of_dam')), yob=yr(h.get('year_of_birth')), sold_as='Yearling', price=h.get('price')))
for x in json.load(open(f'{S}/kee_all.json')):
    if x['field_sale_id'] != '133' or x.get('field_hidden_indicator') == 'Y': continue
    hips.setdefault('kee-nov-2026', []).append(dict(hip=int(x['field_hip_number']), sire=norm(x['field_sire']), dam=norm(x['field_dam']),
        damsire=norm(x['field_broodmare_sire']), yob=yr(x['field_foaling_date']), sold_as=x['field_sold_as'],
        covering=x.get('field_covering_sire')))

out = {}
for sale, hs in hips.items():
    for h in hs:
        h['sireIdx'], h['sireN'] = index(by_sire[h['sire']], h, SIRE_DEFAULT)
        h['dsIdx'], h['dsN'] = index(by_ds[h['damsire']], h, SIRE_DEFAULT)
        h['damIdx'], h['damN'], h['damBest'] = dam_index(h)
    out[sale] = hs

# Turn each part into a 0-100 percentile across both sales, then weight.
allh = [h for hs in out.values() for h in hs]
def pct(key):
    vals = sorted(h[key] for h in allh)
    import bisect
    for h in allh:
        lo, hi = bisect.bisect_left(vals, h[key]), bisect.bisect_right(vals, h[key])
        h[key + 'Pct'] = round(100 * (lo + hi) / 2 / len(vals))
for k in ('sireIdx', 'damIdx', 'dsIdx'): pct(k)
WEIGHTS = dict(sire=0.5, dam=0.3, damsire=0.2)
for h in allh:
    h['score'] = round(WEIGHTS['sire'] * h['sireIdxPct'] + WEIGHTS['dam'] * h['damIdxPct'] + WEIGHTS['damsire'] * h['dsIdxPct'], 1)
for sale, hs in out.items():
    hs.sort(key=lambda h: (-h['score'], -h['sireIdx'], -h['damIdx'], h['hip']))
    for i, h in enumerate(hs, 1): h['rank'] = i
json.dump(out, open(f'{S}/ranks.json', 'w'), indent=1)
for sale, hs in out.items(): print(sale, len(hs))
