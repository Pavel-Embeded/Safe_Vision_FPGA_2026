"""Independent expected UART frames for two-direction telemetry diagnostic."""
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
V=ROOT/'safevision/verification/vectors'
# The independent six-pattern fixture is also used in26101715's full coverage.
patterns=[int(x,16) for x in (V/'adapter_path_patterns.hex').read_text().split()]
frames=[]
for scenario in range(3):
    for rnd in (1,2):
        bad=(scenario==rnd)
        expected=patterns[5]
        report=('SVADP26101716\r\nINIT=01 LOCK=01\r\n'
          f'CFG=00{rnd} BASE=000000 N=000040\r\n'
          f'RND={rnd:08X}/00000002 PAT=0\r\n'
          f'W=0040 R=0040 CAP=0040 BAD={int(bad):04X}\r\n'
          f'TOT={64*rnd:010X}\r\n'
          +(f'BAD0={rnd:08X}:000005 E={expected:08X} A={expected^1:08X}\r\n' if bad else 'BAD0=FFFFFFFF:FFFFFF E=00000000 A=00000000\r\n')
          +f'TX={patterns[0]:08X} INPT={patterns[0]:08X} DM=0 CNT=0040\r\nDONE\r\n')
        assert len(report)==231
        frames.extend(report.encode('ascii'))
(V/'adapter_trace_reports.hex').write_bytes(''.join(f'{x:02X}\n' for x in frames).encode('ascii'))
