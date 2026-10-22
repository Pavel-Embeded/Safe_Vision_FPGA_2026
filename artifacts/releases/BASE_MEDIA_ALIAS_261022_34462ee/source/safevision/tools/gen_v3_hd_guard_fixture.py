"""Reproduce independent zlib CRC fixtures, without invoking HDL or CAD tools."""
import argparse,hashlib,json,struct,zlib
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
GEOMETRIES=((480,320),(255,320),(256,128),(3,128),(2,64),(5,320))
def fixture(rows,words):
 values=[]
 for slot in range(4):
  for row in range(rows):
   packed=b''.join(struct.pack('<I',((slot<<28)^(row<<16)^(col*0x10204081))&0xffffffff)for col in range(words))
   values.append(f'{zlib.crc32(packed):08x}')
 return ('\n'.join(values)+'\n').encode('ascii')
def main():
 ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('--output',type=Path);ap.add_argument('--verify',action='store_true');args=ap.parse_args()
 if not(args.verify or args.output):ap.error('use --verify or --output')
 records=[]
 for rows,words in GEOMETRIES:
  name=f'guard_pad_{rows}_{words}.mem';data=fixture(rows,words)
  if args.output:args.output.mkdir(parents=True,exist_ok=True);(args.output/name).write_bytes(data)
  if args.verify:
   actual=ROOT/'safevision/verification/fixtures'/name
   if actual.read_bytes()!=data:raise ValueError('independent fixture differs:'+name)
  records.append(dict(name=name,rows=rows,words=words,slots=4,sha256=hashlib.sha256(data).hexdigest(),crc_convention='reflected IEEE CRC32, little-endian32bit words, Python zlib'))
 print(json.dumps(dict(accepted=True,verified_repository_fixtures=args.verify,cases=records),indent=2))
if __name__=='__main__':main()
