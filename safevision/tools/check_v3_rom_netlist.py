"""Check every graphics/catalog ROM data bit, including ninth-bit descriptors."""
import argparse,hashlib,json,re,sys
from pathlib import Path
def check_roms(text,root):
 mapped=[]
 for m in re.finditer(r'EG_PHY_BRAM\s*#\((.*?)\)\s+(\\[^\s]+|[\w$]+)\s*\(',text,re.S):
  if not any(prefix in m[2] for prefix in ('video/graphics/','uart/g_catalog/parser/','uart/g_catalog$parser/','scrolling/ticker/','scrolling$ticker/')):continue
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
 shared_ticker='.EXTERNAL_FONT(1)'in top and '.SHARED_TICKER(TICKER_ENABLE)'in top
 packed_ticker=shared_ticker and '.PACKED_EXTERNAL(1)'in top and '.SHARED_PACKED_FONT(TICKER_ENABLE)'in top
 packed_proof=None;spectrum_instance=None
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
   if packed_ticker:
    from build_ticker_shared32_lossless import build as build_packed
    generated,packed_proof=build_packed(root)
    for rel,payload in generated.items():
     if (root/rel).read_bytes()!=payload:raise ValueError('lossless packed font asset differs: '+rel)
    packed=[int(t,16)for t in generated['safevision/assets/fonts/v3_spectrum_ticker32.mem'].decode('ascii').split()]
    if packed[:384]!=words[:384]or len(packed)!=1024 or not packed_proof['all_pixels_preserved']or packed_proof['decoded_bit_comparisons']!=8192:raise ValueError('packed font coefficient/display prefix or complete bitmap differs')
    words=packed
   elif shared_ticker:
    glyph=root/'safevision/assets/fonts/v3_ticker_shared16.mem'
    font_values=[int(t,16)for t in glyph.read_text('ascii').split()]
    if len(font_values)!=512 or any(v<0 or v>255 for v in font_values):raise ValueError('shared ticker font shape differs')
    words[384:896]=font_values
    merged=root/'safevision/assets/fonts/v3_spectrum_ticker.mem'
    if [int(t,16)for t in merged.read_text('ascii').split()]!=words:raise ValueError('combined coefficient/font RAM contents differ')
    metadata=json.loads((merged.parent/'v3_spectrum_ticker.provenance.json').read_text('utf-8'))
    if metadata['message_characters']!=16 or metadata['font_start']!=384 or metadata['font_words']!=512 or metadata['rom_words']!=1024 or metadata['rom_word_bits']!=9 or metadata['font_word_bits']!=8 or metadata['font_order']!='character_row_half':raise ValueError('shared ticker font metadata shape differs')
    if metadata['bitmap_sha256']!=hashlib.sha256(glyph.read_bytes()).hexdigest()or metadata['merged_sha256']!=hashlib.sha256(merged.read_bytes()).hexdigest()or metadata['coefficients_sha256']!=hashlib.sha256(asset.read_bytes()).hexdigest():raise ValueError('shared ticker asset provenance differs')
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
  spectrum_instance=matches[0]
  result.append(dict(asset=asset.name,mapped_instance=matches[0],bytes_compared=1024,parity_bits_compared=1024,logical_bits=2048 if shared else 8192,quarter_wave_coefficients=128,zero_padding_words=384,layout='shared_dp9_coefficient_display'if shared else 'quarter_pdpw18',mutable_display_words=128 if shared else 0,unused_zero_words=640 if shared else 384,payload_sha256=hashlib.sha256(expected+parity).hexdigest()))
 production=(root/'safevision/platform/anlogic_eg4s20_hx4s20c/project/v3_board_verify/v3_board_sources.list').read_text(encoding='utf-8-sig')
 if 'ticker_enable.v' in production and not shared_ticker:
  enable=root/'safevision/platform/anlogic_eg4s20_hx4s20c/project/v3_board_verify/ticker_enable.v'
  if not re.search(r'`define\s+SAFEVISION_TICKER_ENABLE\s+1\b',enable.read_text()):raise ValueError('ticker production selection is disabled')
  asset=root/'safevision/assets/fonts/v3_ticker16.mem'
  values=[int(t,16)for t in asset.read_text(encoding='utf-8-sig').split()]
  if len(values)!=8192 or any(v not in(0,1)for v in values):raise ValueError('invalid ticker single-bit ROM shape')
  metadata=json.loads((asset.parent/'v3_ticker16.provenance.json').read_text(encoding='utf-8'))
  if metadata['message_characters']!=32 or metadata['rom_words']!=8192 or metadata['rom_word_bits']!=1 or metadata['storage_order']!='column_major_bit' or metadata['bitmap_sha256']!=hashlib.sha256(asset.read_bytes()).hexdigest():raise ValueError('ticker metadata/content differs')
  expected=sum(v<<i for i,v in enumerate(values)).to_bytes(1024,'little')
  parity=bytes(128)
  matches=[n for n,data,p,widths in mapped if 'scrolling/ticker/'in n.replace('$','/') and data==expected and p==parity and widths==['1','1']]
  if len(matches)!=1:raise ValueError('mapped ticker ROM missing/corrupt/duplicated')
  result.append(dict(asset=asset.name,mapped_instance=matches[0],bytes_compared=1024,parity_bits_compared=1024,logical_bits=8192,zero_padding_words=0,payload_sha256=hashlib.sha256(expected+parity).hexdigest()))
 if shared_ticker:
  if ('.MESSAGE_CHARS(32)'if packed_ticker else'.MESSAGE_CHARS(16)')not in top or any('scrolling/ticker/'in n.replace('$','/')for n,_,_,_ in mapped):raise ValueError('shared ticker production selection or memory inference differs')
  if packed_ticker:
   if spectrum_instance is None or packed_proof is None:raise ValueError('packed font requires the verified physical FFT RAM')
   result.append(dict(asset='v3_spectrum_ticker32.mem',mapped_instance=spectrum_instance,bytes_compared=1024,parity_bits_compared=1024,logical_bits=8192,stored_font_bits=packed_proof['font_payload_words']*9,decoded_bit_comparisons=8192,all_pixels_preserved=True,shared_coefficient_memory=True,immutable_word_start=384,immutable_word_count=packed_proof['font_payload_words'],unused_zero_words=640-packed_proof['font_payload_words']))
   result[-2].update(layout='shared_dp9_coefficient_display_lossless32',unused_zero_words=640-packed_proof['font_payload_words'])
  else:result.append(dict(asset='v3_ticker_shared16.mem',mapped_instance=spectrum_instance,bytes_compared=512,parity_bits_compared=512,logical_bits=4096,shared_coefficient_memory=True,immutable_word_start=384,immutable_word_count=512))
 return result
def main():
 ap=argparse.ArgumentParser();ap.add_argument('--netlist',type=Path,required=True);ap.add_argument('--repo',type=Path,required=True);ap.add_argument('--output',type=Path,required=True);a=ap.parse_args()
 try:result={'accepted':True,'roms':check_roms(a.netlist.read_text(encoding='utf-8-sig'),a.repo)}
 except Exception as ex:result={'accepted':False,'error':str(ex)}
 a.output.write_text(json.dumps(result,indent=2),encoding='utf-8');print(json.dumps(result,indent=2));return 0 if result['accepted'] else 1
if __name__=='__main__':sys.exit(main())
