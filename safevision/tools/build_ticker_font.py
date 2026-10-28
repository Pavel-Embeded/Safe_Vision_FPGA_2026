"""Build the small fixed-message ROM from the pinned open font."""
import argparse
import hashlib
import json
import struct
from pathlib import Path
from PIL import Image,ImageDraw,ImageFont

MESSAGE='安全提示：遇紧急情况，请保持冷静，听从工作人员指挥，并有序撤离。'
FONT_BLOB='fafdfebf3103db4dc81d33ebd55b6786e08c9ebe'

def source_copyright(raw):
    # Read only the SFNT name table. The pinned Git blob is checked first.
    count=struct.unpack_from('>H',raw,4)[0]
    for i in range(count):
        tag,_,offset,length=struct.unpack_from('>4sIII',raw,12+16*i)
        if tag!=b'name':continue
        table=raw[offset:offset+length]
        _,records,strings=struct.unpack_from('>HHH',table,0)
        choices=[]
        for j in range(records):
            platform,encoding,language,name,size,start=struct.unpack_from('>HHHHHH',table,6+12*j)
            if name!=0:continue
            text=table[strings+start:strings+start+size]
            value=text.decode('utf-16-be'if platform in(0,3)else'mac_roman')
            choices.append((platform==3,language==0x409,value))
        assert choices
        return sorted(choices,reverse=True)[0][2]
    raise ValueError('Pinned font has no copyright name table')

def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--font',type=Path,required=True)
    ap.add_argument('--license',type=Path,required=True)
    ap.add_argument('--font-commit',required=True)
    ap.add_argument('--repo',type=Path,required=True)
    ap.add_argument('--preview',type=Path,required=True)
    args=ap.parse_args()
    raw=args.font.read_bytes()
    assert hashlib.sha1(b'blob '+str(len(raw)).encode()+b'\0'+raw).hexdigest()==FONT_BLOB
    copyright_text=source_copyright(raw)
    assert len(MESSAGE)==32
    # The CJK outline includes descenders: 14px fits the full outline in a
    # 16px cell without cropping punctuation or the bottom character stroke.
    font=ImageFont.truetype(str(args.font),14)
    box=font.getbbox(MESSAGE,anchor='ls');baseline=-box[1]
    assert box[3]-box[1]<=16
    raster=Image.new('L',(512,16),0);draw=ImageDraw.Draw(raster)
    for i,char in enumerate(MESSAGE):draw.text((16*i+1,baseline),char,font=font,fill=255,anchor='ls')
    raster=raster.point(lambda value:255 if value>=96 else 0)
    words=[]
    for char in range(32):
        for row in range(16):
            words.append(sum((1<<(15-col)) for col in range(16) if raster.getpixel((16*char+col,row))))
    assert len(words)==512 and any(words) and not any(words[len(MESSAGE)*16:])
    asset=args.repo/'safevision/assets/fonts/v3_ticker16.mem'
    asset.write_text(''.join(f'{word:04x}\n'for word in words),'ascii',newline='\n')
    reference=args.repo/'safevision/verification/assets/ticker261028'
    reference.mkdir(parents=True,exist_ok=True)
    (reference/'pixels.mem').write_text(''.join(('1\n'if raster.getpixel((x,y))else'0\n')for y in range(16)for x in range(512)),'ascii',newline='\n')
    (args.repo/'safevision/assets/fonts/OFL-NotoSansSC.txt').write_bytes(args.license.read_bytes())
    metadata=dict(message=MESSAGE,unicode=[f'U+{ord(c):04X}'for c in MESSAGE],
                  glyph_size=[16,16],message_characters=len(MESSAGE),rom_words=512,rom_word_bits=16,
                  physical_budget_ram9k=1,font_pixels=14,threshold=96,baseline=baseline,
                  source_repository='https://github.com/notofonts/noto-cjk',source_commit=args.font_commit,
                  source_path='Sans/SubsetOTF/SC/NotoSansSC-Medium.otf',source_git_blob=FONT_BLOB,
                  source_sha256=hashlib.sha256(raw).hexdigest(),copyright=copyright_text,
                  license='SIL Open Font License 1.1',derived_asset_name='SafeVisionTicker16',
                  bitmap_sha256=hashlib.sha256(asset.read_bytes()).hexdigest(),
                  reference_sha256=hashlib.sha256((reference/'pixels.mem').read_bytes()).hexdigest())
    (asset.parent/'v3_ticker16.provenance.json').write_text(json.dumps(metadata,ensure_ascii=False,indent=2)+'\n','utf-8',newline='\n')
    args.preview.parent.mkdir(parents=True,exist_ok=True)
    raster.crop((0,0,len(MESSAGE)*16,16)).resize((len(MESSAGE)*64,64),Image.Resampling.NEAREST).save(args.preview)
    print(json.dumps(metadata,ensure_ascii=False))

if __name__=='__main__':main()
