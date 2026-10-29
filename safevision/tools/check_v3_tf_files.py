


import argparse,ctypes,hashlib,json,os,re,struct
from pathlib import Path

def inspect_bmp(path):
 result={'name':path.name,'bytes':path.stat().st_size,'errors':[]}
 with path.open('rb') as stream:header=stream.read(54)
 if len(header)!=54:
  result['errors'].append('BMP header shorter than 54 bytes');result['accepted']=False;return result
 signature,declared,_,_,offset=struct.unpack_from('<2sIHHI',header)
 dib,width,height,planes,bpp,compression=struct.unpack_from('<IiiHHI',header,14)
 result.update(width=width,height=height,bpp=bpp,compression=compression,pixel_offset=offset,declared_bytes=declared)
 checks=[(signature==b'BM','signature must be BM'),(dib>=40,'DIB header must be at least 40 bytes'),
  (width==640 and abs(height)==480,'image must be 640 x 480'),(planes==1,'planes must be 1'),
  (bpp==24 and compression==0,'requires 24bit uncompressed BI_RGB'),
  (offset>=max(54,14+dib),'pixel offset overlaps the header'),
  (declared<=result['bytes'],'declared file size exceeds directory size'),
  (offset+921600<=result['bytes'],'incomplete pixel payload')]
 result['errors']=[msg for good,msg in checks if not good]
 result['accepted']=not result['errors']
 digest=hashlib.sha256()
 with path.open('rb') as stream:
  for block in iter(lambda:stream.read(1024*1024),b''):digest.update(block)
 result['sha256']=digest.hexdigest()
 return result

def filesystem(path):
 if os.name!='nt':return {'type':None,'reason':'filesystem check available on Windows'}
 drive=Path(path.anchor)
 name=ctypes.create_unicode_buffer(256);kind=ctypes.create_unicode_buffer(256)
 serial=ctypes.c_ulong();maxlen=ctypes.c_ulong();flags=ctypes.c_ulong()
 query=ctypes.WinDLL('kernel32',use_last_error=True).GetVolumeInformationW
 query.argtypes=[ctypes.c_wchar_p,ctypes.c_wchar_p,ctypes.c_ulong,ctypes.POINTER(ctypes.c_ulong),ctypes.POINTER(ctypes.c_ulong),ctypes.POINTER(ctypes.c_ulong),ctypes.c_wchar_p,ctypes.c_ulong]
 query.restype=ctypes.c_int
 ok=query(str(drive),name,256,ctypes.byref(serial),ctypes.byref(maxlen),ctypes.byref(flags),kind,256)
 return {'root':str(drive),'type':kind.value if ok else None,'error':None if ok else ctypes.get_last_error()}

def check(root,require_card=False):
 root=Path(root).resolve()
 if not root.is_dir():raise ValueError('directory does not exist: '+str(root))
 images=[];ignored=[]
 for path in sorted(root.iterdir()):
  if not path.is_file() or path.suffix.upper()!='.BMP':continue
  if not re.fullmatch(r'SV[0-9]{4}\.BMP',path.name) or path.name=='SV0000.BMP':
   ignored.append({'name':path.name,'reason':'not uppercase SV0001.BMP .. SV9999.BMP'});continue
  images.append(inspect_bmp(path))
 good=[row for row in images if row['accepted']]
 fs=filesystem(root);errors=[]
 if len(good)<4:errors.append('requires at least four distinct legal BMP files in the root directory')
 if require_card and fs.get('type')!='FAT32':errors.append('card filesystem is not confirmed FAT32')
 if require_card and root!=Path(root.anchor):errors.append('select the card drive root, not a subdirectory')
 return {'accepted':not errors,'root':str(root),'filesystem':fs,'valid_images':len(good),'selected_first_four':[x['name'] for x in good[:4]],
  'images':images,'ignored_names':ignored,'errors':errors,'read_only':True,'raw_mbr_and_fat_chain_verified':False,'hardware_verified':False}

def main():
 ap=argparse.ArgumentParser();ap.add_argument('--root',required=True,type=Path);ap.add_argument('--output',required=True,type=Path)
 ap.add_argument('--require-card',action='store_true');a=ap.parse_args()
 output=a.output.resolve();root=a.root.resolve()
 if output==root or output.is_relative_to(root):raise ValueError('report must be outside the card/input directory')
 result=check(root,a.require_card);output.parent.mkdir(parents=True,exist_ok=True)
 output.write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
 print(json.dumps(result,ensure_ascii=False,indent=2));return 0 if result['accepted'] else 1
if __name__=='__main__':raise SystemExit(main())
