"""Independent UART oracle for six-pattern guarded fourbeat write experiment."""
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2];V=ROOT/'safevision/verification/vectors'
patterns=[int(x,16) for x in (V/'adapter_path_patterns.hex').read_text().split()]
frames=[]
for scenario in range(4):
 for rnd in range(1,13):
  mode=(rnd-1)//2;bad=(scenario in (1,2) and scenario==rnd) or (scenario==3 and rnd==1);expected=patterns[mode*64+5];first=patterns[mode*64+48]
  report=('SVADP26101730\r\nINIT=01 LOCK=01\r\n'
   f'CFG=00{1 if rnd%2 else 2} BASE=000000 N=000040\r\n'
   f'RND={rnd:08X}/0000000C PAT={mode:X}\r\n'
   f'W=0040 R=0050 CAP=0050 BAD={int(bad):04X}\r\nTOT={80*rnd:010X}\r\n'
   +(f'BAD0={rnd:08X}:000005 E={expected:08X} A={expected^1:08X}\r\n' if bad else 'BAD0=FFFFFFFF:FFFFFF E=00000000 A=00000000\r\n')
   +f'TX={expected^1 if scenario==3 and rnd==1 else 0:08X} INPT={expected if scenario==3 and rnd==1 else 0:08X} DM={1 if scenario==3 and rnd==1 else 0:X} CNT={80:04X}\r\nDONE\r\n')
  assert len(report)==231;frames.extend(report.encode())
(V/'adapter_readrotate_reports.hex').write_bytes(''.join(f'{x:02X}\n' for x in frames).encode())
