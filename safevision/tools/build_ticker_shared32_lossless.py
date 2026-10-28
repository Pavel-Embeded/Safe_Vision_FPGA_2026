"""Pack the existing32-glyph bitmap into the unused9-bit FFT RAM words."""
from pathlib import Path
import argparse,hashlib,json
ROOT=Path(__file__).resolve().parents[2]
def digest(data):return hashlib.sha256(data).hexdigest()
def build(root):
 bitmap=root/'safevision/assets/fonts/v3_ticker16.mem';original=bitmap.read_bytes()
 bits=[int(v,16)for v in original.decode('utf-8-sig').split()]
 meta=json.loads((root/'safevision/assets/fonts/v3_ticker16.provenance.json').read_text('utf-8-sig'))
 if len(bits)!=8192 or set(bits)-{0,1}or len(meta['message'])!=32:raise ValueError('expected the complete32-cell16x16bitmap')
 source=root/'safevision/assets/fonts/v3_spectrum_ticker.mem';source_bytes=source.read_bytes()
 legacy=[int(v,16)for v in source_bytes.decode('utf-8-sig').split()]
 if len(legacy)!=1024 or any(v<0 or v>511 for v in legacy):raise ValueError('expected1024native9-bit words')
 merged=legacy[:384]+[0]*640;payload=[];unique={};descriptors=[]
 for index in range(32):
  glyph=tuple(bits[index*256:(index+1)*256])
  if glyph not in unique:
   xs=[x for x in range(16)for y in range(16)if glyph[x*16+y]]
   if not xs or any(glyph[x*16+y]for x in range(16)for y in (0,15)):raise ValueError('glyph exceeds the lossless retained row range')
   xmin=min(xs);width=max(xs)-xmin+1;stream=[glyph[x*16+y]for x in range(xmin,xmin+width)for y in range(1,15)]
   base=len(payload)
   for first in range(0,len(stream),9):payload.append(sum(v<<j for j,v in enumerate(stream[first:first+9])))
   unique[glyph]=(base,xmin,width)
  base,xmin,width=unique[glyph];descriptors.append((base<<8)|(xmin<<4)|width)
 if len(payload)>640:raise ValueError('lossless payload exceeds the available640words')
 merged[384:384+len(payload)]=payload
 compared=0
 for index,descriptor in enumerate(descriptors):
  base=descriptor>>8;xmin=(descriptor>>4)&15;width=descriptor&15
  for x in range(16):
   for y in range(16):
    value=0
    if xmin<=x<xmin+width and 1<=y<=14:
     linear=(x-xmin)*14+y-1;quotient=(linear*57)>>9;remainder=linear-quotient*9
     if (quotient,remainder)!=divmod(linear,9):raise ValueError('packed address arithmetic differs')
     value=(merged[384+base+quotient]>>remainder)&1
    if value!=bits[index*256+x*16+y]:raise ValueError('decoded bitmap differs')
    compared+=1
 for value in range(256):
  if ((value*57)>>9)!=value//9:raise ValueError('8-bit division identity differs')
 rom=''.join(f'{v:03x}\n'for v in merged).encode('ascii')
 header='// Full32-character bitmap, deduplicated and cropped only across zero pixels.\nfunction [17:0] packed_ticker_descriptor;\n input [4:0] index;\n begin case(index)\n'
 header+=''.join(f"  5'd{i}:packed_ticker_descriptor=18'h{v:05x};\n"for i,v in enumerate(descriptors))
 header+="  default:packed_ticker_descriptor=18'd0;\n endcase end\nendfunction\n";header=header.encode('ascii')
 provenance=dict(schema=1,message=meta['message'],message_characters=32,unique_glyphs=len(unique),cell_size=[16,16],stored_y_first=1,stored_y_count=14,font_start_word=384,font_payload_words=len(payload),font_word_bits=9,source_bitmap_sha256=digest(original),source_shared16_sha256=digest(source_bytes),combined_sha256=digest(rom),descriptor_sha256=digest(header),decoded_bit_comparisons=compared,all_pixels_preserved=True,coefficient_and_display_prefix_preserved=merged[:384]==legacy[:384],division_domain=list(range(256)),division_rule='floor(n/9) = (57*n) >> 9 for n in0..255',descriptors=descriptors,font_license='SIL Open Font License 1.1',font_source_provenance='safevision/assets/fonts/v3_ticker16.provenance.json')
 return {'safevision/assets/fonts/v3_spectrum_ticker32.mem':rom,'safevision/rtl/include/v3_ticker_packed32.vh':header,'safevision/assets/fonts/v3_spectrum_ticker32.provenance.json':(json.dumps(provenance,ensure_ascii=False,indent=2)+'\n').encode('utf-8')},provenance
def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--repo',type=Path,default=ROOT);p.add_argument('--write',action='store_true');a=p.parse_args();files,proof=build(a.repo.resolve())
 for name,data in files.items():
  target=a.repo.resolve()/name
  if a.write:target.write_bytes(data)
  elif not target.is_file()or target.read_bytes()!=data:raise ValueError('stale generated asset: '+name)
 print('LOSSLESS32 '+('GENERATED'if a.write else'CHECK PASS')+f": {proof['decoded_bit_comparisons']}bits, {proof['font_payload_words']}/640words")
 return 0
if __name__=='__main__':raise SystemExit(main())
