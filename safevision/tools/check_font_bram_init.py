"""Check TD's public emitted BRAM INIT parameters against all 4096 asset bytes.

Uses the per-bank data_offset/depth/width metadata in TD write_verilog output.
This is initialization readback, not a simulation of the encrypted BRAM model.
Usage: python check_font_bram_init.py font_gate.v font8x16.mem
"""
import re
import sys
from pathlib import Path

def check(netlist: Path, asset: Path):
    text = netlist.read_text(encoding="utf-8")
    data = re.sub(r"//[^\n]*", "", asset.read_text(encoding="ascii"))
    golden = [int(v, 16) for v in data.split()]
    if len(golden) != 4096 or any(v > 255 for v in golden):
        raise ValueError("Font asset must have exactly 4096 bytes")
    markers = list(re.finditer(r"// address_offset=(\d+);data_offset=(\d+);depth=(\d+);width=(\d+);", text))
    if len(markers) != 4:
        raise ValueError("Expected four 4096x2 physical BRAM banks for standalone 4096x8 ROM")
    restored = [0] * 4096
    covered = 0
    for k, m in enumerate(markers):
        address, offset, depth, width = map(int, m.groups())
        if address != 0 or depth != 4096 or width != 2 or offset not in (0, 2, 4, 6):
            raise ValueError("Unexpected TD bank layout")
        mask = 3 << offset
        if covered & mask:
            raise ValueError("Duplicate TD data bank")
        covered |= mask
        end = markers[k+1].start() if k+1 < len(markers) else len(text)
        bank = text[m.end():end]
        init = {int(i, 16): int(v, 16) for i, v in re.findall(r"\.INIT_([0-9A-Fa-f]{2})\(256'h([0-9A-Fa-f]{64})\)", bank)}
        if set(init) != set(range(32)):
            raise ValueError("Missing BRAM INIT parameter")
        for a in range(4096):
            value = (init[a//128] >> ((a%128)*2)) & 3
            restored[a] |= value << offset
    if covered != 255:
        raise ValueError("Incomplete data-bit coverage")
    for a, (got, want) in enumerate(zip(restored, golden)):
        if got != want:
            raise ValueError(f"BRAM init mismatch address {a:03x}: got {got:02x}, expected {want:02x}")
    print("PASS font BRAM INIT readback: 4096/4096 bytes, four physical 9K banks")

if __name__ == "__main__":
    if len(sys.argv) != 3:
        raise SystemExit("Usage: check_font_bram_init.py font_gate.v font8x16.mem")
    check(Path(sys.argv[1]), Path(sys.argv[2]))
