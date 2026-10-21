"""Independent raw-log acceptance. A runner JSON never overrides failed data checks."""
import argparse,hashlib,json,re
from pathlib import Path

def audit_text(text,require_error_count=False):
 errors=[]
 if '$finish called' not in text:errors.append('missing normal $finish')
 markers=len(re.findall(r'(?m)\[PASS\]|^PASS\s',text))
 if not markers:errors.append('missing success check marker')
 if re.search(r'\[FAIL\]|\[SKIP\]',text,re.I):errors.append('explicit FAIL/SKIP anywhere in raw log')
 if re.search(r'(?im)^\s*(?:\[[^]\n]+\]\s*)?(?:FAIL\b|FATAL\b|Fatal:|ERROR:|SKIP\b)',text):errors.append('fatal/tool/skip/failure diagnostic')
 if re.search(r'(?im)^.*\(FAIL\).*$',text):errors.append('failed summary')
 counts=[int(x) for x in re.findall(r'(?i)\berrors\s*=\s*(\d+)',text)]
 if any(counts):errors.append('nonzero errors summary')
 if require_error_count and not counts:errors.append('missing explicit errors summary')
 return {'accepted':not errors,'normal_finish':'$finish called' in text,'success_markers':markers,'error_values':counts,'errors':errors}

def audit_file(path,require_error_count=False):
 p=Path(path)
 if not p.is_file():return {'path':str(p),'accepted':False,'normal_finish':False,'errors':['missing raw log']}
 raw=p.read_bytes()
 text=raw.decode('utf-16') if raw.startswith((b'\xff\xfe',b'\xfe\xff')) else raw.decode('utf-8-sig',errors='replace')
 return {'path':str(p),'sha256':hashlib.sha256(raw).hexdigest(),**audit_text(text,require_error_count)}

def main():
 ap=argparse.ArgumentParser();ap.add_argument('--log',type=Path,action='append',required=True);ap.add_argument('--output',type=Path,required=True);ap.add_argument('--require-error-count',action='store_true');a=ap.parse_args()
 results=[audit_file(p,a.require_error_count) for p in a.log]
 record={'accepted':all(x['accepted'] for x in results),'results':results,'scope':'raw simulation logs only; not STA/bitstream/hardware'}
 a.output.parent.mkdir(parents=True,exist_ok=True);a.output.write_text(json.dumps(record,indent=2)+'\n',encoding='utf-8');print(json.dumps({'accepted':record['accepted'],'logs':len(results)}))
 return 0 if record['accepted'] else 1
if __name__=='__main__':raise SystemExit(main())
