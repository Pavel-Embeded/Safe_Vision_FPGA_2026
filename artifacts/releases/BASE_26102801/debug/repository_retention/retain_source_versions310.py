"""Keep dated deduplication evidence valid after active source development."""
from pathlib import Path
import hashlib,json,subprocess
w=Path(__file__).resolve().parent;root=w/'wav_reject_barrier_source';git='D:/Git/mingw64/bin/git.exe';base='09faac2e8fa718c9f92ef4a5013b68003ec8afe6'
relative='evidence/repository_cleanup_261026/duplicates.json'
raw=subprocess.check_output([git,'-C',str(root),'show',base+':'+relative])
original=json.loads(raw);current=json.loads(raw)
tree={}
for entry in subprocess.check_output([git,'-C',str(root),'ls-files','--stage','-z']).split(b'\0'):
 if entry:
  meta,name=entry.split(b'\t',1);tree[name.decode()]=meta.decode().split()[1]
ledger=root/relative;assert not ledger.exists()
original_path=ledger.parent/'duplicates_261026.original.json';assert not original_path.exists()
original_path.parent.mkdir(parents=True,exist_ok=True);original_path.write_bytes(raw)
changed=[];objects={}
for row in current['records']:
 if tree.get(row['retained'])==row['git_blob']:continue
 old_path=row['retained'];blob=row['git_blob']
 frozen=subprocess.check_output([git,'-C',str(root),'show',base+':'+old_path])
 assert subprocess.check_output([git,'-C',str(root),'rev-parse',base+':'+old_path]).decode().strip()==blob
 assert len(frozen)==row['bytes']and hashlib.sha256(frozen).hexdigest()==row['sha256']
 target=ledger.parent/'retained_source_261028'/blob/Path(old_path).name
 if target.exists():assert target.read_bytes()==frozen
 else:target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(frozen)
 row['retained']=target.relative_to(root).as_posix()
 changed.append(dict(removed=row['removed'],previous_retained=old_path,retained=row['retained'],git_blob=blob,current_source_blob=tree[old_path]))
 objects[blob]=dict(path=row['retained'],bytes=len(frozen),sha256=row['sha256'])
assert len(changed)==24 and len(objects)==12
for before,after in zip(original['records'],current['records']):assert {k:v for k,v in before.items()if k!='retained'}=={k:v for k,v in after.items()if k!='retained'}
assert {k:v for k,v in original.items()if k!='records'}=={k:v for k,v in current.items()if k!='records'}
ledger.write_text(json.dumps(current,ensure_ascii=False,indent=2)+'\n','utf-8',newline='\n')
receipt=dict(schema=1,accepted=True,baseline_commit=base,original_ledger='duplicates_261026.original.json',original_ledger_sha256=hashlib.sha256(raw).hexdigest(),active_ledger_sha256=hashlib.sha256(ledger.read_bytes()).hexdigest(),moved_references=changed,original_objects=objects,removed_paths_and_counts_unchanged=True,current_rtl_and_constraints_changed_by_this_operation=False)
(ledger.parent/'retained_source_261028.index.json').write_text(json.dumps(receipt,indent=2)+'\n','utf-8')
attrs=root/'.gitattributes';s=attrs.read_text('utf-8');assert '/evidence/repository_cleanup_261026/retained_source_261028/**'not in s
s+='\n/evidence/repository_cleanup_261026/retained_source_261028/** -text\n/evidence/repository_cleanup_261026/duplicates_261026.original.json -text\n';attrs.write_text(s,'utf-8',newline='\n')
print('RETAINED12EXACT HISTORICAL SOURCE OBJECTS; UPDATED24LOCATIONS; ORIGINAL LEDGER AND ALL CHECKS PRESERVED')
