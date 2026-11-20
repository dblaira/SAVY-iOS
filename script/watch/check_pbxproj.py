# Parses project.pbxproj, reports dangling object references, each target with its SDK and
# watch-related files, and file references that sit in no group. Usage:
# python3 -I check_pbxproj.py <App>.xcodeproj/project.pbxproj
import re, sys
src = open(sys.argv[1]).read()
src = src.split('\n', 1)[1]  # drop // !$*UTF8*$!
tok_re = re.compile(r'\s+|/\*.*?\*/|//[^\n]*|"(?:\\.|[^"\\])*"|[{}()=;,]|[^\s{}()=;,"]+', re.S)
toks = [t for t in tok_re.findall(src) if t.strip() and not t.startswith('/*') and not t.startswith('//')]
pos = 0
def parse():
    global pos
    t = toks[pos]
    if t == '{':
        pos += 1; d = {}
        while toks[pos] != '}':
            k = toks[pos].strip('"'); pos += 1
            assert toks[pos] == '=', (k, toks[pos-3:pos+3]); pos += 1
            d[k] = parse()
            assert toks[pos] == ';', (k, toks[pos]); pos += 1
        pos += 1; return d
    if t == '(':
        pos += 1; a = []
        while toks[pos] != ')':
            a.append(parse())
            if toks[pos] == ',': pos += 1
        pos += 1; return a
    pos += 1
    return t.strip('"') if t.startswith('"') else t
root = parse()
objs = root['objects']
ids = set(objs)
missing = []
def walk(v, path):
    if isinstance(v, dict):
        for k, x in v.items(): walk(x, path + [k])
    elif isinstance(v, list):
        for x in v: walk(x, path)
    elif isinstance(v, str) and re.fullmatch(r'[0-9A-F]{24}', v) and v not in ids:
        missing.append((path, v))
for k, v in objs.items(): walk(v, [k])
print("objects:", len(objs), "dangling refs:", missing[:10])
targets = [objs[t]['name'] for t in objs[root['rootObject']]['targets']]
print("targets:", targets)
for t in objs[root['rootObject']]['targets']:
    o = objs[t]
    phases = [objs[p]['isa'] for p in o['buildPhases']]
    files = []
    for p in o['buildPhases']:
        for f in objs[p].get('files', []):
            fr = objs[f].get('fileRef') or objs[f].get('productRef')
            files.append(objs[fr].get('path') or objs[fr].get('productName'))
    cfgs = {objs[c]['name']: objs[c]['buildSettings'].get('SDKROOT') for c in objs[o['buildConfigurationList']]['buildConfigurations']}
    print(o['name'], o['productType'], cfgs, len(files), [f for f in files if 'Watch' in f or 'Capture' in f or f.endswith('appex') or f=='Assets.xcassets'])
# every file ref in a group?
grouped = set()
for k, v in objs.items():
    if v.get('isa') in ('PBXGroup', 'PBXVariantGroup'):
        grouped.update(v.get('children', []))
orphans = [objs[k].get('path') for k, v in objs.items() if v.get('isa') == 'PBXFileReference' and k not in grouped]
print("ungrouped file refs:", orphans)
