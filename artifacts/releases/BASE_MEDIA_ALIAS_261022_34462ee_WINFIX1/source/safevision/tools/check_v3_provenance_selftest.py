"""Verify commit and ROM gates detect byte corruption without touching sources."""
import argparse,hashlib,json,subprocess,sys
from pathlib import Path
from run_v3_board import source_commit_binding
from check_v3_rom_netlist import check_roms
ROOT=Path(__file__).resolve().parents[2]
def main():
 ap=argparse.ArgumentParser();ap.add_argument('--run-dir',type=Path,required=True);ap.add_argument('--native-netlist',type=Path,required=True);a=ap.parse_args()
 base=a.run_dir.resolve();base.mkdir(parents=True,exist_ok=True);fixture=base/'source_fixture';fixture.mkdir(exist_ok=True)
 name='safevision/tools/check_board_timing.py'
 baseline=subprocess.run(['git','-C',str(ROOT),'show','HEAD:'+name],capture_output=True,check=True).stdout
 path=fixture/name;path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(baseline)
 cases=[]
 def check(name,ok):
  cases.append({'case':name,'pass':bool(ok)})
  if not ok:raise AssertionError(name)
 check('exact committed source bytes bind',source_commit_binding(fixture,ROOT,'HEAD',[name])['verified'])
 path.write_bytes(baseline+b'\n# intentional isolated mutation\n')
 check('modified source bytes rejected',not source_commit_binding(fixture,ROOT,'HEAD',[name])['verified'])
 path.write_bytes(baseline)
 check('uncommitted dependency rejected',not source_commit_binding(fixture,ROOT,'HEAD',['uncommitted.v'])['verified'])
 check('unknown commit rejected',not source_commit_binding(fixture,ROOT,'refs/heads/this-ref-does-not-exist',[name])['verified'])
 text=a.native_netlist.read_text(encoding='utf-8-sig');native=check_roms(text,ROOT)
 check('native mapped ROM compares all 3072 bytes',sum(x['bytes_compared'] for x in native)==3072)
 for entry in native:
  # Rename just one mapped graphics instance out of the production hierarchy;
  # its asset must then have no eligible physical implementation.
  bad=text.replace(entry['mapped_instance'],'\\removed_rom_for_negative_control',1)
  try:check_roms(bad,ROOT);detected=False
  except ValueError:detected=True
  check('missing mapped '+entry['asset']+' detected',detected)
 check('fixture source restored',path.read_bytes()==baseline)
 result={'scope':'release-gate fault injection; no FPGA acceptance','cases':cases,'complete':all(x['pass'] for x in cases),'native_netlist_sha256':hashlib.sha256(a.native_netlist.read_bytes()).hexdigest()}
 (base/'results.json').write_text(json.dumps(result,indent=2),encoding='utf-8');print('PASS V3 release provenance cases='+str(len(cases)));return 0
if __name__=='__main__':sys.exit(main())
