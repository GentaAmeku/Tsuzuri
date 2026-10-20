import json,sys
name=sys.argv[1]
raw=sys.stdin.read()
try:
    r=json.loads(raw)
except Exception:
    print(name,'RAW:',raw[:2000]); sys.exit(0)
print(name,'ok=',r.get('ok'), len([c for c in r.get('checks',[]) if c['ok']]),'/',len(r.get('checks',[])))
for d in r.get('diagnostics',[]): print('-',d['severity'],d['code'],'|',d['message'][:600])
if not r.get('ok') and r.get('error'): print(r['error'][:2000])
