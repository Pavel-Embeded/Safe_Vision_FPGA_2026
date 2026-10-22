"""Verify the local current BASE source, immutable payload and raw board run."""
from pathlib import Path
import argparse,importlib.util,json,hashlib,subprocess,sys
sys.dont_write_bytecode=True
def read(p):return json.loads(p.read_text(encoding='utf-8-sig'))
def main():
 ap=argparse.ArgumentParser();ap.add_argument('--repo',type=Path,default=Path(__file__).resolve().parents[2]);ap.add_argument('--output',type=Path);a=ap.parse_args();r=a.repo.resolve()
 pointer=read(r/'artifacts/releases/BASE_MEDIA_ALIAS_261022.json');p=(r/pointer['package']).resolve();assert p.is_relative_to(r)
 assert hashlib.sha256((p/'release.index.json').read_bytes()).hexdigest()==pointer['release_index_sha256']
 spec=importlib.util.spec_from_file_location('alias_portable_verifier',p/'verify_portable.py');v=importlib.util.module_from_spec(spec);spec.loader.exec_module(v);offline=v.verify(p);assert offline['accepted']
 approval=read(p/'approval.index.json');sys.path.insert(0,str(r/'safevision/tools'));from v3_sources import snapshot
 assert snapshot(r)==approval['source_sha256'],'Local current build inputs differ from the approved bit'
 for name,digest in {**approval['source_sha256'],**approval['proof_sha256']}.items():
  assert hashlib.sha256((r/name).read_bytes()).hexdigest()==digest,'Current local source/proof differs: '+name
 board=(r/pointer['board_validation']).resolve();assert board.is_relative_to(r);program=read(board/'programming.json');assert program['accepted']and not program['flash_written']and not program['TF_written']
 assert program['bit_sha256']==pointer['bit_sha256']==read(p/'release.index.json')['modes'][0]['bit_sha256']
 subprocess.run([sys.executable,'-X','utf8','-B',str(r/'safevision/tools/host/audit_media_alias_261022.py'),str(board/'geometry')],check=True,capture_output=True)
 board_audit=read(board/'geometry/geometries.audit.json');assert board_audit['accepted']and board_audit['audio_wav_all_valid']and board_audit['actual_cached_image_ids']==[1,2,3,4]
 result=dict(accepted=True,offline=offline,current_source_matches_approved_bit=True,board_serial_audit=board_audit,physical_display_verified=read(board/'user_observation.json').get('accepted',False)if(board/'user_observation.json').exists()else False,flash_written=False,TF_written=False,github_uploaded=False)
 if a.output:a.output.write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
 print(json.dumps({k:v for k,v in result.items()if k not in('offline','board_serial_audit')},indent=2));return 0
if __name__=='__main__':sys.exit(main())
