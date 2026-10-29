
from pathlib import Path
import argparse,hashlib,json
from PIL import Image,ImageDraw,ImageFont
from build_ticker_font import FONT_BLOB,source_copyright
MESSAGE='遇险请保持冷静，听从指挥有序撤离'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
 ap=argparse.ArgumentParser();ap.add_argument('--repo',type=Path,required=True);ap.add_argument('--font',type=Path,required=True);ap.add_argument('--font-commit',required=True);ap.add_argument('--preview',type=Path,required=True);a=ap.parse_args()
 raw=a.font.read_bytes();assert hashlib.sha1(b'blob '+str(len(raw)).encode()+b'\0'+raw).hexdigest()==FONT_BLOB
 assert len(MESSAGE)==16
 font=ImageFont.truetype(str(a.font),14);box=font.getbbox(MESSAGE,anchor='ls');baseline=-box[1];assert box[3]-box[1]<=16
 image=Image.new('L',(256,16));draw=ImageDraw.Draw(image)
 for i,char in enumerate(MESSAGE):draw.text((i*16+1,baseline),char,font=font,fill=255,anchor='ls')
 image=image.point(lambda x:255 if x>=96 else 0)
 words=[sum(int(bool(image.getpixel((char*16+half*8+x,row))))<<(7-x)for x in range(8))for char in range(16)for row in range(16)for half in range(2)]
 root=a.repo;folder=root/'safevision/assets/fonts';glyph=folder/'v3_ticker_shared16.mem';glyph.write_text(''.join(f'{v:02x}\n'for v in words),'ascii',newline='\n')
 coefficients=root/'safevision/assets/audio/v3_spectrum_twiddle.mem';values=[int(x,16)for x in coefficients.read_text('ascii').split()];assert len(values)==512 and not any(values[128:])
 merged=[0]*1024
 for i,v in enumerate(values[:128]):merged[2*i]=v&511;merged[2*i+1]=(v>>9)&127
 merged[384:896]=words
 asset=folder/'v3_spectrum_ticker.mem';asset.write_text(''.join(f'{v:03x}\n'for v in merged),'ascii',newline='\n')
 ref=root/'safevision/verification/assets/ticker_shared261028';ref.mkdir(parents=True,exist_ok=True)
 pixels=ref/'pixels.mem';pixels.write_text(''.join('1\n'if image.getpixel((x,y))else'0\n'for y in range(16)for x in range(256)),'ascii',newline='\n')
 data=dict(message=MESSAGE,message_characters=16,glyph_size=[16,16],font_pixels=14,baseline=baseline,threshold=96,rom_words=1024,rom_word_bits=9,font_start=384,font_words=512,font_word_bits=8,font_order='character_row_half',source_git_blob=FONT_BLOB,source_repository='https://github.com/notofonts/noto-cjk',source_commit=a.font_commit,source_path='Sans/SubsetOTF/SC/NotoSansSC-Medium.otf',source_sha256=hashlib.sha256(raw).hexdigest(),copyright=source_copyright(raw),license='SIL Open Font License 1.1',derived_asset_name='SafeVisionSharedTicker16',bitmap_sha256=sha(glyph),merged_sha256=sha(asset),coefficients_sha256=sha(coefficients),reference_sha256=sha(pixels))
 (folder/'v3_spectrum_ticker.provenance.json').write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n','utf-8',newline='\n')
 a.preview.parent.mkdir(parents=True,exist_ok=True);image.resize((1024,64),Image.Resampling.NEAREST).save(a.preview)
 print('COMBINED FONT/COEFFICIENT ROM:',len(merged),'words; independent font pixels:',4096)
if __name__=='__main__':main()
