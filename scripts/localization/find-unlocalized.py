#!/usr/bin/env python3
"""Lists English-looking Swift literals that are not keys in Yomi/Localizable.xcstrings (S181).
Run from the iOS folder. Many hits are names, headers or sample data — read each one; real UI text gets
String(localized:) or a LocalizedStringKey param, then build + build-catalog.py."""
import json,re,sys,glob,collections
cat=json.load(open('Yomi/Localizable.xcstrings'))['strings']
keys=set(cat)
lit=re.compile(r'"((?:[^"\\]|\\.)*)"')
skip=re.compile(r'print\(|NSLog|log\.|logger\.|Logger|os_log|debugLog|\.debug\(|\.info\(|\.error\(|\.warning\(|\.notice\(|forKey|UserDefaults|@AppStorage|systemName|Image\(|\.sql|SELECT|INSERT|UPDATE |CREATE|accessibilityIdentifier|fatalError|precondition|assert|#Preview|case \w+ *=|http|\.json|NSPredicate|Notification\.Name|evaluate|javaScript|js\(|struct |enum ')
out=collections.defaultdict(list)
for f in glob.glob('Yomi/**/*.swift',recursive=True)+glob.glob('YomiWidget/*.swift'):
    for n,line in enumerate(open(f),1):
        s=line.strip()
        if s.startswith('//') or skip.search(line): continue
        for m in lit.finditer(line):
            v=m.group(1)
            if '\\(' in v:
                # convert interpolation to %@ style roughly
                k=re.sub(r'\\\((.*?)\)','%@',v)
            else: k=v
            # S184: digits and "·" allowed — "Paused — less than 200 MB free" and "Reading · %@" slipped through
            if not re.match(r'^[A-Z][a-z]+[ a-zA-Z0-9,.’\'!?…:%@·()—-]*$',k) and not re.match(r'^[A-Z][a-z]+( [a-z%@]+)+',k): continue
            if len(v)<3: continue
            if v in keys: continue
            # check key with interpolation forms
            cands=[re.sub(r'\\\((.*?)\)',x,v) for x in ('%@','%lld','%d')]
            if any(c in keys for c in cands): continue
            if 'String(localized' in line or 'LocalizedStringKey' in line: tag='LOC?'
            else: tag=''
            out[f].append((n,tag,v))
tot=0
for f in sorted(out):
    print('##',f,len(out[f]))
    for n,t,v in out[f]: print(f'  {n}{" "+t if t else ""}: {v}')
    tot+=len(out[f])
print('TOTAL',tot)
