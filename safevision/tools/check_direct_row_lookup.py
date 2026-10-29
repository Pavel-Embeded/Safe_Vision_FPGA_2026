"""Check the complete cache-index transformation and its finite address domain."""
from pathlib import Path
import argparse,hashlib,json,re,subprocess,zlib
ROOT=Path(__file__).resolve().parents[2]
PARENT='521c9c295766e71d836f392ef9a16e6b8e65fcee'
META='safevision/verification/models/direct_row_lookup112.freeze.json'
META_SHA='8298bf25fcb88582994e5d7dc4425764912bf9dab5c0d51d8bb703d4092240d2'
MAP='safevision/rtl/include/pixel_format_defs.vh'
MAP_SHA='0b8c2719d4a403860e7d28aeaf9c34d81714ed92044560c3a4a99ab74e7c23a0'
ASSET='safevision/verification/assets/direct_row_crc113.mem'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def require(ok,message):
 if not ok:raise ValueError(message)
def gold_asset():
 result=[]
 for slot in range(4):
  for row in range(512):
   crc=0
   if row<480:
    payload=bytearray()
    for col in range(320):
     address=slot*655360+row*1280+col*4
     word=(0x93a57ce1^((address*0x1020411)&0xffffffff)^(address>>3))&0xffffffff
     payload+=word.to_bytes(4,'little')
    crc=zlib.crc32(payload)
   result.append(crc)
 return ''.join(f'{value:08x}\n'for value in result).encode('ascii')
def check(root):
 root=Path(root).resolve();require(sha(root/META)==META_SHA and sha(root/MAP)==MAP_SHA,'frozen transformation/address map changed')
 meta=json.loads((root/META).read_text('utf-8-sig'));require(meta['parent_commit']==PARENT,'frozen parent changed')
 wanted={f'safevision/rtl/{v}/{name}.v'for v,name in[('video','v3_line_cache'),('video','v3_video_display_core'),('memory','v3_row_integrity'),('hd','v3_line_cache'),('hd','v3_video_display_core'),('hd','v3_row_integrity')]}
 wanted.add('safevision/platform/anlogic_eg4s20_hx4s20c/rtl/safevision_top/safevision_v3_top.v')
 require(set(meta['files'])==wanted,'transformation file inventory differs')
 sources={};references={}
 for name,row in meta['files'].items():
  original=subprocess.check_output(['git','-C',str(root),'cat-file','blob',PARENT+':'+name])
  require(hashlib.sha256(original).hexdigest()==row['original_sha256'],'frozen original source differs: '+name)
  expected=original.decode('utf-8-sig').replace('\r\n','\n')
  for patch in row['patches']:
   require(expected.count(patch['before'])==patch['occurrences'],'whole-body transform anchor differs')
   expected=expected.replace(patch['before'],patch['after'])
  require((root/name).read_text('utf-8-sig')==expected and sha(root/name)==row['current_sha256'],'unreviewed source edit: '+name)
  sources[name]=sha(root/name)
  if'reference'in row:
   before=b'module v3_row_integrity #(';after=('module '+row['reference_module']+' #(').encode()
   require(original.count(before)==1 and(root/row['reference']).read_bytes()==original.replace(before,after)and sha(root/row['reference'])==row['reference_sha256'],'reference changed beyond module name')
   references[row['reference']]=row['reference_sha256']
 for variant in('video','hd'):
  s=(root/f'safevision/rtl/{variant}/v3_line_cache.v').read_text('utf-8-sig')
  assignments={name:[value.strip()for value in re.findall(r'\b'+name+r'\s*<=\s*([^;]+);',s)]for name in('slot','row','lookup_addr')}
  require(assignments==dict(slot=['0','wanted_slot'],row=['0','wanted_row'],lookup_addr=['0',"`SV_SLOT_BASE(wanted_slot)+wanted_row*32'd1280"]),'cache register epoch/coherence differs')
  require('assign lookup_slot_index=slot;assign lookup_row_index=row;'in s and'bank<=wanted_bank;slot<=wanted_slot;row<=wanted_row;'in s,'cache aliases no longer share the original registered epoch')
 vectors=[];valid_count=0;indices=set()
 for slot in range(4):
  for row in range(1024):
   address=(slot*512+row)*1280
   old_slot=3 if address>=1966080 else 2 if address>=1310720 else 1 if address>=655360 else 0
   offset=address-old_slot*655360;old_valid=offset<614400 and offset%1280==0
   selected=slot+(row>>9);new_valid=selected<4 and(row&511)<480
   old_index=old_slot*512+offset//1280 if old_valid else 0
   new_index=selected*512+(row&511)if new_valid else 0
   require(old_valid==new_valid and old_index==new_index,'direct address alias differs')
   valid_count+=int(new_valid)
   if new_valid:indices.add(new_index)
   vectors.append((slot,row,address,int(new_valid),new_index))
 expected=gold_asset();require((root/ASSET).read_bytes()==expected,'independent zlib CRC fixture changed')
 return dict(accepted=True,scope='Complete-source reconstruction and induction on unchanged cache registers, exhaustive4096cache-generated addresses, independent1920row zlib CRC fixtures. Native public-output tests and routed timing are separate.',parent_commit=PARENT,source_sha256=sources,reference_sha256=references,metadata_sha256=META_SHA,map_sha256=MAP_SHA,tool_sha256=sha(Path(__file__)),asset_sha256=sha(root/ASSET),cases=len(vectors),valid_queries=valid_count,invalid_queries=len(vectors)-valid_count,unique_valid_signature_rows=len(indices),vectors_sha256=hashlib.sha256(json.dumps(vectors,separators=(',',':')).encode()).hexdigest(),lookup_latency_cycles=1,added_latency_cycles=0,CRC_operators_or_state_updates_changed=False,new_clock_domain=False,new_timing_exception=False,hardware_verified=False)
def main():
 p=argparse.ArgumentParser();p.add_argument('--repo',type=Path,default=ROOT);p.add_argument('--output',type=Path,required=True);a=p.parse_args()
 try:result=check(a.repo);code=0
 except Exception as exc:result=dict(accepted=False,error=str(exc));code=1
 a.output.write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8',newline='\n');print('DIRECT ROW SOURCE/DOMAIN '+('PASS'if result['accepted']else'FAIL '+result['error']));return code
if __name__=='__main__':raise SystemExit(main())
