


import argparse
from collections import defaultdict, deque
import hashlib
import json
from pathlib import Path
import re


def normalized(value):
    return re.sub(r'\s+', '', value)


def audit(path):
    data = path.read_bytes()
    text = data.decode('utf-8', errors='replace')
    edges = defaultdict(list)
    for match in re.finditer(r'(?m)^\s*buf\s+\S+\s+\(([^,\n]+),([^;\n]+)\);', text):
        edges[normalized(match[2])].append(normalized(match[1]))
    pads = {}
    errors = []
    for match in re.finditer(r'EG_PHY_PAD\s*#\((.*?)\)\s+(\\\S+)\s+\((.*?)\);', text, re.S):
        params, name, ports = match.groups()
        dq = re.search(r'\.bpad\(\s*\\dq\[(\d+)\]\s*\)', ports)
        if not dq:
            continue
        bit = int(dq[1])
        if bit in pads:
            errors.append(f'DQ{bit}: duplicate physical capture pads')
        ipclk = re.search(r'\.ipclk\(([^)]*)\)', ports)
        diq = re.search(r'\.diq\(\{([^}]*)\}\)', ports)
        if not ipclk or not diq:
            errors.append(f'DQ{bit}: missing registered input data or clock')
            continue
        source = normalized(diq[1].split(',')[-1])
        clock = normalized(ipclk[1])
        if '.IN_DFFMODE("FF")' not in params or '.INPCLKMUX("CLK")' not in params:
            errors.append(f'DQ{bit}: input register not configured with clock')
        if clock != r'\adapter/clk':
            errors.append(f'DQ{bit}: unexpected/constant capture clock {clock}')
        target = r'\adapter/Sdr_rd_dout' + f'[{bit}]'
        queue = deque([(source, [source])])
        seen = set()
        route = None
        while queue:
            node, chain = queue.popleft()
            if node == target:
                route = chain
                break
            if node in seen:
                continue
            seen.add(node)
            queue.extend((n, chain + [n]) for n in edges[node] if n not in seen)
        if route is None:
            errors.append(f'DQ{bit}: no live PAD input-to-adapter data path')
        pads[bit] = dict(pad=name, clock=clock, path=route)
    if set(pads) != set(range(32)):
        errors.append('expected exactly 32 DQ input register paths')
    sinks = []
    consumed = set()
    for match in re.finditer(r'EG_PHY_BRAM\s*#\((.*?)\)\s+(\\\S+)\s+\((.*?)\);', text, re.S):
        params, name, ports = match.groups()
        if r'\adapter/Sdr_rd_dout' not in ports:
            continue
        clocks = [normalized(x) for x in re.findall(r'\.clka?b?\(([^)]*)\)', ports)]
        if clocks != [r'\adapter/clk', r'\adapter/clk']:
            errors.append(f'{name}: read-buffer clocks are missing/constant/unexpected')
        bit_ranges = re.findall(r'\\adapter/Sdr_rd_dout\s*\[(\d+):(\d+)\]', ports)
        bits = sorted({b for high, low in bit_ranges for b in range(int(low), int(high) + 1)})
        consumed.update(bits)
        enable = re.search(r'\.cea\(([^)]*)\)', ports)
        if not enable or not normalized(enable[1]).startswith('\\adapter/'):
            errors.append(f'{name}: missing live read-buffer write enable')
        sinks.append(dict(instance=name, clocks=clocks, bits=bits,
                          capture_enable=normalized(enable[1]) if enable else None))
    if consumed != set(range(32)):
        errors.append('registered DQ data does not feed all 32 live adapter read-buffer bits')
    pll = next((m for m in re.finditer(
        r'\b\w*PLL\w*\s*#\((.*?)\)\s+(\\\S+)\s+\((.*?)\);', text, re.S)
        if m[2] == r'\system_pll/pll_inst'), None)
    pll_clock = False
    if pll:
        clkc = re.search(r'\.clkc\(\{([^}]*)\}\)', pll[3])
        outputs = [normalized(x) for x in clkc[1].split(',')] if clkc else []
        enabled = '.CLKC1_ENABLE("ENABLE")' in pll[1]
        reference = re.search(r'\.refclk\(([^)]*)\)', pll[3])
        dynamic_reference = reference and not re.match(r"\d*'[bhd]|^[01]$", normalized(reference[1]))
        pll_clock = len(outputs) == 5 and outputs[-2] == r'\adapter/clk' and enabled and dynamic_reference
    if not pll_clock:
        errors.append('PAD capture clock is not driven by system PLL CLKC1')
    warned_fabric_ff = bool(re.search(r'\bSdr_rd_dout_reg\[', text))
    if warned_fabric_ff:
        errors.append('warned fabric-register name remains; inspect rather than classify as packed away')
    return dict(status='PASS_MAPPED_IO_PACK' if not errors else 'FAIL', netlist=str(path),
                netlist_sha256=hashlib.sha256(data).hexdigest(), dq_registered_bits=len(pads),
                capture_clock_source='system_pll CLKC1', original_fabric_ff_present=warned_fabric_ff,
                mapped_paths=pads, read_buffer_sinks=sinks, live_data_bits=len(consumed),
                errors=errors, routed_timing_verified=False, hardware_verified=False)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('netlist', type=Path)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    result = audit(args.netlist)
    if args.output:
        args.output.write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps({k: v for k, v in result.items() if k != 'mapped_paths'}))
    return 0 if result['status'] == 'PASS_MAPPED_IO_PACK' else 1


if __name__ == '__main__':
    raise SystemExit(main())
