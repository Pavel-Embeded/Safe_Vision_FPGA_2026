"""Data failure, prefixed failure, truncated run and fabricated PASS must reject."""
import argparse,json
from pathlib import Path
from audit_v3_raw_logs import audit_text

def main():
 ap=argparse.ArgumentParser();ap.add_argument('--run-dir',type=Path,required=True);a=ap.parse_args();a.run_dir.mkdir(parents=True,exist_ok=False)
 good='[PASS] data checked\nPASS tb_fixture errors=0 comparisons=42\n$finish called at time : 50 ns\n'
 cases=[('normal',good,True,True),('legacy','[PASS] checked\n$finish called\n',False,True),('legacy_no_explicit','[PASS] checked\n$finish called\n',True,False),('prefixed_fail','[MODEL] [FAIL] corrupt payload\n'+good,True,False),('indented_fail','   [FAIL] bad\n'+good,True,False),('fatal','Fatal: assertion\n'+good,True,False),('prefixed_fatal','[MODEL] Fatal: assertion\n'+good,True,False),('tool_error','ERROR: simulator error\n'+good,True,False),('skip','[SKIP] missing test\n'+good,True,False),('prefixed_skip','[MODEL] [SKIP] missing\n'+good,True,False),('nonzero',good.replace('errors=0','errors=1'),True,False),('earlier_nonzero','errors=3\n'+good,True,False),('missing_finish',good.replace('$finish called','interrupted'),True,False),('no_success','errors=0\n$finish called\n',True,False),('failed_summary','1 (FAIL)\n'+good,True,False),('filename_not_failure','# Log file: C:/FAIL_count/sim.log\n'+good,True,True)]
 for name,text,required,want in cases:
  got=audit_text(text,required);assert got['accepted']==want,(name,got)
 record={'checks':len(cases),'errors':0,'release_ready':False};(a.run_dir/'selftest.json').write_text(json.dumps(record,indent=2)+'\n',encoding='utf-8');print('PASS raw-log selftest checks='+str(len(cases))+' errors=0')
if __name__=='__main__':main()
