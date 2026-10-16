from pathlib import Path
import argparse,json,math
p=argparse.ArgumentParser();p.add_argument('--output',required=True);a=p.parse_args();out=Path(a.output);out.mkdir(parents=True,exist_ok=True)
values=[]
for phase in range(65536):
 quadrant=phase>>14;index=(phase>>9)&31
 if quadrant&1:index=31-index
 value=round(2000000*math.sin(index*math.pi/64))
 if quadrant&2:value=-value
 values.append(value&0xffffff)
(out/'tone_oracle.mem').write_text('\n'.join(f'{value:06x}' for value in values)+'\n')
(out/'tone_oracle.json').write_text(json.dumps({'phases':65536,'amplitude':2000000,'source':'independent Python math sine and signed quadrant symmetry'},indent=2))
