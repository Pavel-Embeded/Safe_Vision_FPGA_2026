from pathlib import Path
import json
R=Path(__file__).resolve().parents[2]
V=R/'safevision/verification/vectors';V.mkdir(exist_ok=True)
def pat(a,m):
    if m==0:
        parts=[0xC3^(((a&31)<<3)|((a>>5)&7)),0x3C^(a&255),0x5A^(a&255)^((a>>5)&255),0xA5^(a&255)^((a>>13)&255)]
        return sum(v<<(8*i) for i,v in enumerate(parts))
    if m==1:
        x=(a+0xA5C35A3C)&0xffffffff
        x^=(x<<13)&0xffffffff;x^=x>>17;x^=(x<<5)&0xffffffff
        return x
    if m==2:return 1<<(a&31)
    if m==3:return (1<<(a&31))^0xffffffff
    if m==4:return 0xffffffff if a&1 else 0
    return 0xaaaaaaaa if a&1 else 0x55555555
(V/'adapter_path_patterns.hex').write_bytes(''.join(f'{pat(a,m):08X}\n' for m in range(6) for a in range(64)).encode('ascii'))
reports=[]
for rnd,bad in [(12,False),(1,True),(2,True)]:
    exp=pat(5,0);actual=exp^1
    report=('SVADP26101715\r\nINIT=01 LOCK=01\r\n'
     f'CFG=00{2 if rnd%2==0 else 1} BASE=000000 N=000040\r\n'
     f'RND={rnd:08X}/0000000C PAT={(rnd-1)//2:X}\r\n'
     f'W=0040 R=0040 CAP=0040 BAD={1 if bad else 0:04X}\r\n'
     f'TOT={rnd*64:010X}\r\n'
     +(f'BAD0={rnd:08X}:000005 E={exp:08X} A={actual:08X}\r\n' if bad else 'BAD0=FFFFFFFF:FFFFFF E=00000000 A=00000000\r\n')+'DONE\r\n')
    assert len(report)==190
    reports+=report.encode('ascii')
(V/'adapter_path_reports.hex').write_bytes(''.join(f'{b:02X}\n' for b in reports).encode('ascii'))
mf=R/'safevision/build/manifests/adapter_path_probe_sim.json'
m=json.loads(mf.read_text());m['assets']=['safevision/verification/vectors/adapter_path_patterns.hex','safevision/verification/vectors/adapter_path_reports.hex']
mf.write_bytes((json.dumps(m,indent=2)+'\n').encode('utf-8'))
