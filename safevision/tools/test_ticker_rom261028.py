"""Read real mapped ticker bits, then require four corruptions to be refused."""
import argparse,hashlib,json,re
from pathlib import Path
from check_v3_rom_netlist import check_roms
def main():
 ap=argparse.ArgumentParser();ap.add_argument('--netlist',type=Path,required=True);ap.add_argument('--repo',type=Path,required=True);ap.add_argument('--output',type=Path,required=True);a=ap.parse_args()
 raw=a.netlist.read_text('utf-8-sig');good=check_roms(raw,a.repo)
 ticker=next(row for row in good if row['asset']=='v3_ticker16.mem')
 blocks=list(re.finditer(r'EG_PHY_BRAM\s*#\((.*?)\)\s+(\\[^\s]+|[\w$]+)\s*\(',raw,re.S))
 block=next(m for m in blocks if m[2]==ticker['mapped_instance'])
 body=block[0];token=re.search(r'(\.INIT_00\(256\s*\x27h)([0-9a-fA-F]{64})',body)
 assert token is not None
 metadata=json.loads((a.repo/'safevision/assets/fonts/v3_ticker16.provenance.json').read_text('utf-8-sig'))
 assert metadata['rom_word_bits']in(1,16)
 physical_width='1'if metadata['rom_word_bits']==1 else'18'
 assert body.count('.DATA_WIDTH_A("'+physical_width+'")')==1
 flipped=body[:token.start(2)]+f'{int(token[2],16)^1:064x}'+body[token.end(2):]
 cases={'flipped_data_bit':raw[:block.start()]+flipped+raw[block.end():],
        'wrong_port_width':raw[:block.start()]+body.replace('.DATA_WIDTH_A("'+physical_width+'")','.DATA_WIDTH_A("9")')+raw[block.end():],
        'missing_ticker_ram':raw[:block.start()]+body.replace('EG_PHY_BRAM','MISSING_RAM')+raw[block.end():],
        'duplicate_ticker_ram':raw+'\n'+body+');\n'}
 results=[]
 for name,mutated in cases.items():
  try:check_roms(mutated,a.repo)
  except ValueError as exc:results.append(dict(name=name,rejected=True,reason=str(exc)))
  else:raise AssertionError('corrupted mapped ROM accepted: '+name)
 result=dict(accepted=True,native_netlist_sha256=hashlib.sha256(a.netlist.read_bytes()).hexdigest(),mapped_roms=good,controls=results)
 a.output.write_text(json.dumps(result,indent=2)+'\n','utf-8');print('TICKER MAPPED ROM AND FOUR REFUSAL CONTROLS PASS')
if __name__=='__main__':main()
