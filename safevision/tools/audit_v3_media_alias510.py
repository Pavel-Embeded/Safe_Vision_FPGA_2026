"""Independent raw-card and canonical-name audit for BASE alias qualification."""
from pathlib import Path
import json,hashlib,struct,binascii,re,functools,operator
def read(p):return json.loads(p.read_text(encoding='utf-8-sig'))
def audit(root):
 e=Path(root)/'evidence/v3/multires_alias_261022';p=e/'card_readonly';j=read(p/'directory.json');assert j['accepted']and j['read_only']
 recovery=e/'scheduler_recovery'
 if recovery.exists():
  receipt=read(recovery/'native_children.json');identity=read(recovery/'process_identity.json')
  assert receipt['accepted']and receipt['all_native_runner_exits_zero']and receipt['coordinator_terminated_after_all_native_children_finished']and receipt['assertions_clocks_sources_unchanged']
  assert set(receipt['recovered_cases'])=={'tb_v3_max_card241','tb_v3_resident','tb_v3_setting_wave_board_hd198','tb_v3_shared_storage'}
  assert identity['observer_sha256']==hashlib.sha256((recovery/'recover_scheduler510.py').read_bytes()).hexdigest()
 sectors={}
 for r in j['requests']:
  wire=(p/f"reply_{r['seq']:03}_{r['lba']:08X}.bin").read_bytes();assert len(wire)==530 and wire[:4]==b'SVR1'and wire[4]==r['seq']and struct.unpack_from('<I',wire,5)[0]==r['lba']
  assert wire[9:12]==b'\0'*3 and struct.unpack_from('<H',wire,12)[0]==512 and wire[-1]==10
  assert functools.reduce(operator.xor,wire[:528],0)==wire[528]==r['uart_xor']
  payload=wire[16:528];assert binascii.crc_hqx(payload,0)==struct.unpack_from('<H',wire,14)[0]==r['sd_crc']
  assert payload==(p/f"sector_{r['lba']:08X}.bin").read_bytes();sectors[r['lba']]=payload
 assert len(sectors)==j['sectors_read']==31
 u16=lambda b,o:struct.unpack_from('<H',b,o)[0];u32=lambda b,o:struct.unpack_from('<I',b,o)[0]
 assert u16(sectors[0],510)==0xaa55 and sectors[0][450]in(11,12)and u32(sectors[0],454)==8192
 b=sectors[8192];assert u16(b,11)==512 and b[13]==8 and u16(b,510)==0xaa55
 fat=8192+u16(b,14);data=fat+b[16]*u32(b,36);assert fat==10718 and data==40960 and u32(b,44)==2
 raw=b''.join(sectors[data+i]for i in range(8));ref=read(e/'card_directory.reference.json');assert hashlib.sha256(raw).hexdigest()==ref['root_sha256']
 asset=Path(root)/'safevision/verification/assets/card_directory510';assert bytes.fromhex((asset/'actual_root509.mem').read_text())==raw
 entries=[];canon=[]
 for index in range(128):
  r=raw[index*32:(index+1)*32]
  if r[0]==0:break
  if r[0]==229 or r[11]&24 or r[11]==15:continue
  name=r[:11].decode('ascii');m=re.fullmatch(r'SV(\d{3}|\d{4}) +(BMP|WAV)',name)
  if not m:continue
  cluster=u16(r,20)<<16|u16(r,26);size=u32(r,28);normalized=f'SV{int(m[1]):04}  {m[2]}'.encode()
  canon.append((normalized+r[11:12]+cluster.to_bytes(4,'big')+size.to_bytes(4,'big')+index.to_bytes(2,'big')).hex())
  entries.append(dict(id=int(m[1]),ext=m[2],cluster=cluster,size=size))
 assert canon==(asset/'actual_entries509.mem').read_text().split()and len(entries)==20
 bmps=sorted((r for r in entries if r['ext']=='BMP'),key=lambda r:r['id'])[:4]
 wavs={r['id']:r for r in entries if r['ext']=='WAV'}
 assert [r['id']for r in bmps]==ref['expected_keys']==[1,2,3,4]
 assert [r['cluster']for r in bmps]==ref['bmp_clusters']and[wavs[r['id']]['cluster']for r in bmps]==ref['wav_clusters']
 for r,(w,h)in zip(bmps,[(480,800),(641,479),(1280,720),(1920,1080)]):
  header=sectors[data+(r['cluster']-2)*8];assert header[:2]==b'BM'and struct.unpack_from('<ii',header,18)==(w,h)and u16(header,26)==1 and u16(header,28)==24 and u32(header,30)==0
  assert u32(header,2)==r['size']==54+((w*3+3)//4*4)*h
  a=sectors[data+(wavs[r['id']]['cluster']-2)*8];assert a[:4]==b'RIFF'and a[8:16]==b'WAVEfmt 'and u16(a,20)==1 and u16(a,22)==2 and u32(a,24)==48000 and u16(a,34)==16
  assert u32(a,16)==16 and u32(a,28)==192000 and u16(a,32)==4 and a[36:40]==b'data'
  assert u32(a,4)+8==wavs[r['id']]['size']==u32(a,40)+44==1536044 and u32(a,40)%4==0
 return dict(accepted=True,crc_checked_sectors=31,canonical_entries=20,actual_new_images=4,actual_matching_wav_headers=4)
