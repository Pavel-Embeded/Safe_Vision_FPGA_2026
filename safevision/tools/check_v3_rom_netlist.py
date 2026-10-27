"""Check every graphics/catalog ROM data bit, including ninth-bit descriptors."""
import argparse,hashlib,json,re,sys
from pathlib import Path
def check_roms(text,root):
 mapped=[]
 for m in re.finditer(r'EG_PHY_BRAM\s*#\((.*?)\)\s+(\\[^\s]+|[\w$]+)\s*\(',text,re.S):
  if not any(prefix in m[2] for prefix in ('video/graphics/','uart/g_catalog/parser/','uart/g_catalog$parser/','scrolling/ticker/')):continue
  blocks={int(k,16):int(v,16).to_bytes(32,'little') for k,v in re.findall(r'\.INIT_([0-9A-Fa-f]{2})\(256\s*\x27h([0-9A-Fa-f]{64})\)',m[1])}
  parity={int(k,16):int(v,16).to_bytes(32,'little') for k,v in re.findall(r'\.INITP_([0-9A-Fa-f]{2})\(256\s*\x27h([0-9A-Fa-f]{64})\)',m[1])}
  widths=re.findall(r'\.DATA_WIDTH_[AB]\("([0-9]+)"\)',m[1])
  if set(blocks)==set(range(32))and set(parity)==set(range(4)):
   mapped.append((m[2],b''.join(blocks[i] for i in range(32)),b''.join(parity[i]for i in range(4)),widths))
 result=[]
 top=(root/'safevision/platform/anlogic_eg4s20_hx4s20c/rtl/safevision_top/safevision_v3_top.v').read_text(encoding='utf-8')
 selected=re.findall(r'\.STATUS_TEXT_FILE\("\.\./\.\./assets/fonts/([a-zA-Z0-9_]+\.mem)"\)',top)
 if selected not in ([],['v3_handbook_status_text.mem']):raise ValueError('unreviewed/ambiguous production status ROM selection')
 status='fonts/'+(selected[0] if selected else 'v3_status_text.mem')
 layer=(root/'safevision/rtl/video/v3_status_layers.v').read_text(encoding='utf-8-sig')
 descriptor='DESCRIPTOR_TEXT=USER_FEATURES&&HANDBOOK_PROFILE'in layer
 if descriptor:
  if '.USER_FEATURES(1)'not in top or '.HANDBOOK_PROFILE(1)'not in top:raise ValueError('descriptor ROM requires explicit production USER_FEATURES and HANDBOOK_PROFILE')
  status='fonts/v3_four_features_text.mem'
 for rel in ('fonts/font8x16_compact.mem',status,'control/v3_command_catalog.mem'):
  path=root/'safevision/assets'/rel;name=path.name
  tokens=path.read_text(encoding='utf-8-sig').split()
  values=[int(token,16) for token in tokens]
  is_descriptor=descriptor and rel==status
  if any(v<0 or v>511 if is_descriptor else v<0 or v>255 for v in values):raise ValueError('ROM word exceeds reviewed width: '+name)
  expected=bytes(v&255 for v in values)
  if len(expected)!=1024:raise ValueError('ROM length is not 1024 bytes: '+name)
  expected_parity=sum(((v>>8)&1)<<i for i,v in enumerate(values)).to_bytes(128,'little')
  matches=[n for n,data,parity,widths in mapped if data==expected and parity==expected_parity and (not is_descriptor or widths==['9','9'])]
  if len(matches)!=1:raise ValueError('mapped ROM content missing/corrupt/duplicated: '+name)
  result.append({'asset':name,'mapped_instance':matches[0],'bytes_compared':1024,'parity_bits_compared':1024,'logical_bits':9216 if is_descriptor else 8192,'payload_sha256':hashlib.sha256(expected+expected_parity).hexdigest()})
 if '.FLEX_SPECTRUM(1)'in top:
  asset=root/'safevision/assets/audio/v3_spectrum_twiddle.mem'
  values=[int(t,16)for t in asset.read_text(encoding='utf-8-sig').split()]
  if len(values)!=512 or any(v<0 or v>0xffff for v in values) or any(values[128:]):raise ValueError('invalid quarter-wave spectrum ROM shape/padding')
  spectrum=(root/'safevision/rtl/video/v3_audio_spectrum.v').read_text(encoding='utf-8-sig')
  shared=bool(re.search(r'reg\s*\[8:0\]\s+shared_ram\s*\[0:1023\]',spectrum))
  if shared:
   # One physical DP9 RAM: quarter coefficients are split into two nine-bit
   # words each. Both display banks and every unused word start at zero.
   words=[0]*1024
   for i,v in enumerate(values[:128]):words[2*i]=v&511;words[2*i+1]=(v>>9)&127
   expected=bytes(v&255 for v in words)
   parity=sum(((v>>8)&1)<<i for i,v in enumerate(words)).to_bytes(128,'little')
   reviewed_widths=['9','9']
  else:
   # TD maps each logical16 word into physical18; bits8/17 are in INITP.
   expected=b''.join(bytes((v&255,(v>>9)&255))for v in values)
   parity=sum((((v>>8)&1)|(((v>>17)&1)<<1))<<(2*i)for i,v in enumerate(values)).to_bytes(128,'little')
   reviewed_widths=['18','18']
  matches=[n for n,data,p,widths in mapped if data==expected and p==parity and widths==reviewed_widths]
  if len(matches)!=1:raise ValueError('mapped spectrum twiddle ROM missing/corrupt/duplicated')
  result.append(dict(asset=asset.name,mapped_instance=matches[0],bytes_compared=1024,parity_bits_compared=1024,logical_bits=2048 if shared else 8192,quarter_wave_coefficients=128,zero_padding_words=384,layout='shared_dp9_coefficient_display'if shared else 'quarter_pdpw18',mutable_display_words=128 if shared else 0,unused_zero_words=640 if shared else 384,payload_sha256=hashlib.sha256(expected+parity).hexdigest()))
 production=(root/'safevision/platform/anlogic_eg4s20_hx4s20c/project/v3_board_verify/v3_board_sources.list').read_text(encoding='utf-8-sig')
 if 'ticker_enable.v' in production:
  enable=root/'safevision/platform/anlogic_eg4s20_hx4s20c/project/v3_board_verify/ticker_enable.v'
  if not re.search(r'`define\s+SAFEVISION_TICKER_ENABLE\s+1\b',enable.read_text()):raise ValueError('ticker production selection is disabled')
  asset=root/'safevision/assets/fonts/v3_ticker16.mem'
  values=[int(t,16)for t in asset.read_text(encoding='utf-8-sig').split()]
  if len(values)!=512 or any(v<0 or v>65535 for v in values) or any(values[336:]):raise ValueError('invalid ticker ROM size, width or zero padding')
  expected=b''.join(bytes((v&255,(v>>9)&255))for v in values)
  parity=sum(((v>>8)&1)<<(2*i)for i,v in enumerate(values)).to_bytes(128,'little')
  matches=[n for n,data,p,widths in mapped if 'scrolling/ticker/'in n and data==expected and p==parity and widths==['18','18']]
  if len(matches)!=1:raise ValueError('mapped ticker ROM missing/corrupt/duplicated')
  result.append(dict(asset=asset.name,mapped_instance=matches[0],bytes_compared=1024,parity_bits_compared=1024,logical_bits=8192,zero_padding_words=176,payload_sha256=hashlib.sha256(expected+parity).hexdigest()))
 return result
def main():
 ap=argparse.ArgumentParser();ap.add_argument('--netlist',type=Path,required=True);ap.add_argument('--repo',type=Path,required=True);ap.add_argument('--output',type=Path,required=True);a=ap.parse_args()
 try:result={'accepted':True,'roms':check_roms(a.netlist.read_text(encoding='utf-8-sig'),a.repo)}
 except Exception as ex:result={'accepted':False,'error':str(ex)}
 a.output.write_text(json.dumps(result,indent=2),encoding='utf-8');print(json.dumps(result,indent=2));return 0 if result['accepted'] else 1
if __name__=='__main__':sys.exit(main())
