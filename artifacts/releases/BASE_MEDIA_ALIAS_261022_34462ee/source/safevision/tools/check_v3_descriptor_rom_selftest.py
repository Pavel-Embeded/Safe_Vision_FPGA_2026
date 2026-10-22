from pathlib import Path
import argparse,hashlib,json,re,sys
p=argparse.ArgumentParser();p.add_argument('--repo',type=Path,required=True);p.add_argument('--netlist',type=Path,required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args()
sys.path.insert(0,str(a.repo/'safevision/tools'));import check_v3_rom_netlist as audit
text=a.netlist.read_text(encoding='utf-8-sig');original=audit.check_roms(text,a.repo)
target=next(r['mapped_instance']for r in original if r['asset']=='v3_four_features_text.mem')
blocks=list(re.finditer(r'EG_PHY_BRAM\s*#\((.*?)\)\s+(\\[^\s]+|[\w$]+)\s*\(',text,re.S))
block=next(m for m in blocks if m[2]==target);params=block[1];results=[]
def flip(label,name):
 m=re.search(r'\.'+name+r"\(256'h([0-9a-fA-F]{64})\)",params);assert m
 altered=params[:m.start(1)]+f'{int(m[1],16)^1:064x}'+params[m.end(1):]
 return label,altered
cases=[flip('descriptor_flag_bit_inverted','INITP_00'),flip('ordinary_character_data_bit_inverted','INIT_00')]
cases.append(('all_descriptor_flags_lost',re.sub(r"(\.INITP_[0-9A-Fa-f]{2}\(256'h)[0-9A-Fa-f]{64}",lambda m:m[1]+'0'*64,params)))
assert params.count('.DATA_WIDTH_A("9")')==1
cases.append(('descriptor_port_width_changed',params.replace('.DATA_WIDTH_A("9")','.DATA_WIDTH_A("18")')))
for label,changed in cases:
 mutated=text[:block.start(1)]+changed+text[block.end(1):];assert mutated!=text
 try:audit.check_roms(mutated,a.repo)
 except ValueError as ex:results.append(dict(mutation=label,detected=True,error=str(ex)))
 else:results.append(dict(mutation=label,detected=False))
result=dict(accepted=all(r['detected']for r in results),unmodified_netlist_accepted=True,original_mapped_roms=original,negative_cases=results,netlist=str(a.netlist),netlist_sha256=hashlib.sha256(a.netlist.read_bytes()).hexdigest(),verifier_sha256=hashlib.sha256(Path(audit.__file__).read_bytes()).hexdigest(),selftest_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),purpose='ROM auditor only; this does not approve physical fit, STA, bitgen or hardware')
a.output.parent.mkdir(parents=True,exist_ok=True);a.output.write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8');print(json.dumps(dict(accepted=result['accepted'],unmodified_passed=True,negative_detected=sum(r['detected']for r in results),total_negative=len(results))));assert result['accepted']
