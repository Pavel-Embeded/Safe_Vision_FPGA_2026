


import argparse,hashlib,json,re,subprocess,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
CASES=[
 ('alpha_front','tb_v3_math','safevision/rtl/video/video_compositor/alpha_blend.v',
  'pr<=dr*','pr<=-dr*','v3',1),
 ('row_crc','tb_v3_row_integrity','safevision/rtl/memory/v3_row_integrity.v',
  'signatures[source_index]<=~next_source_crc','signatures[source_index]<=(~next_source_crc)^32\'h1','v3',1),
 ('raster_tag','tb_v3_coords_fade','safevision/rtl/video/scaler/scaler_coords.v',
  'valid<=v1','valid<=!v1','v3',3),
 ('recovery_ack','tb_v3_recovery_events','safevision/rtl/control/media_recovery_ctrl.v',
  'attempts<=0;recovered<=1','attempts<=0;recovered<=0','v3',1),
 ('bmp_extent_carry','tb_v3_bmp_extent_pipeline','safevision/rtl/media/bmp_parser.v',
  'wire[32:0] checked_extent',
  'wire[31:0] checked_extent','bmp_extent_pipeline',1),
 ('parser_digit_seen','tb_v3_parser_digit_seen','safevision/rtl/control/v3_command_parser.v',
  "digit_seen<=1'b1", "digit_seen<=1'b0",'parser_digit_seen',1),
 ('priority_saturation','tb_v3_priority_difference','safevision/rtl/audio/audio_priority_arbiter.v',
  "({1'b0,gain} + {1'b0,ramp_step} > 10'd256)",
  "(gain + ramp_step > 9'd256)",'priority_difference',1),
]

def main():
    ap=argparse.ArgumentParser();ap.add_argument('--run-dir',required=True)
    ap.add_argument('--case',action='append',choices=[c[0] for c in CASES]);a=ap.parse_args()
    base=Path(a.run_dir).resolve();base.mkdir(parents=True,exist_ok=True)
    if not str(base).isascii():raise ValueError('ASCII work directory required')
    records=[];originals={}
    for name,top,relative,old,new,suite,anchor_count in CASES:
        if a.case and name not in a.case:continue
        source=ROOT/relative;raw=source.read_bytes();originals[relative]=hashlib.sha256(raw).hexdigest()
        text=raw.decode('utf-8-sig')
        if text.count(old)!=anchor_count:raise RuntimeError('mutation anchor ambiguous: '+name)
        folder=base/name;folder.mkdir(exist_ok=True);mutant=folder/source.name
        mutant.write_text(text.replace(old,new),encoding='utf-8')
        command=[sys.executable,str(ROOT/'safevision/tools/run_v3_sim.py'),'--suite',suite,
                 '--run-dir',str(folder/'simulation'),'--top',top,
                 '--override-source',relative+'='+str(mutant)]
        with (folder/'console.log').open('w',encoding='utf-8') as f:
            p=subprocess.run(command,cwd=ROOT,stdout=f,stderr=subprocess.STDOUT)
        sim=folder/'simulation'/top/'sim.log'
        log=sim.read_text(encoding='utf-8',errors='replace') if sim.is_file() else ''
        normal='$finish called' in log and bool(re.search(r'PASS\s+'+re.escape(top)+r'\b|\[TB\]\s*'+re.escape(top)+r'\s+done',log))
        errors=[int(x) for x in re.findall(r'errors\s*=\s*(\d+)',log)]
        detected=p.returncode==1 and normal and '[FAIL]' in log and any(errors)
        record={'mutation':name,'top':top,'detected':detected,'normal_completion':normal,
                'error_counts':errors,'original_sha256':originals[relative],
                'mutated_sha256':hashlib.sha256(mutant.read_bytes()).hexdigest()}
        records.append(record);print(json.dumps(record),flush=True)
    preserved=all(hashlib.sha256((ROOT/k).read_bytes()).hexdigest()==v for k,v in originals.items())
    result={'negative_controls':records,'originals_preserved':preserved,
            'complete':preserved and all(r['detected'] for r in records)}
    (base/'negative_controls.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
    return 0 if result['complete'] else 1
if __name__=='__main__':sys.exit(main())
