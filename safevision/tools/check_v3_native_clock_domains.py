


import argparse
import hashlib
import json
import re
from pathlib import Path
import xml.etree.ElementTree as ET

PREFIX = 'video/cache/packed_data$store/'
PLL = 'system_pll/pll_inst'
TOP = 'safevision/platform/anlogic_eg4s20_hx4s20c/rtl/safevision_top/safevision_v3_top.v'


def clean(text):
    return re.sub(r'//[^\n]*|/\*.*?\*/', '', text, flags=re.S)


def net(text):
    return re.sub(r'\s+(?=\[\d+(?::\d+)?\])', '', text.strip()).lstrip('\\').strip()


def bits(text):

    out = []
    for part in text.strip().strip('{}').split(','):
        name = net(part)
        span = re.fullmatch(r'(.*)\[(\d+):(\d+)\]', name)
        if span:
            high, low = int(span[2]), int(span[3])
            step = -1 if high >= low else 1
            out.extend(span[1] + '[' + str(i) + ']' for i in range(high, low + step, step))
        elif name:
            out.append(name)
    return out


class Native:
    def __init__(self, text):
        text = clean(text)


        self.widths = {}
        for declaration in re.finditer(r'^\s*(?:wire|input|output|inout)\s*\[(\d+):(\d+)\]\s+(\\?[^\s;]+)\s*;', text, re.M):
            name = net(declaration[3])
            span = (int(declaration[1]), int(declaration[2]))
            if name in self.widths and self.widths[name] != span:
                raise ValueError('conflicting actual native bus declarations: ' + name)
            self.widths[name] = span
        self.cells = []
        self.parent = {}
        pattern = r'^\s{2}(EG_[A-Z0-9_]+|AL_MAP_SEQ)\s*(?:#\((.*?)\)\s*)?(\\?[^\s()]+)\s*\((.*?)\);'
        for m in re.finditer(pattern, text, re.M | re.S):
            ports = dict(re.findall(r'\.([A-Za-z_0-9]+)\(\s*([^()]*)\)', m[4]))
            self.cells.append(dict(kind=m[1], name=net(m[3]), params=m[2] or '', ports=ports))
        for m in re.finditer(r'^\s{2}buf\s+\\?[^\s()]+\s*\(([^();]+)\);', text, re.M):
            pair = m[1].split(',')
            if len(pair) != 2:
                raise ValueError('unsupported native buf syntax')
            left, right = self.expand(pair[0]), self.expand(pair[1])
            if not left or len(left) != len(right):
                raise ValueError('unequal-width actual native buf ports')
            for a, b in zip(left, right):
                self.union(a, b)
        for m in re.finditer(r'^\s*assign\s+([^=;]+)=([^;]+);', text, re.M):
            left, right = self.expand(m[1]), self.expand(m[2])


            if len(left) == len(right) and all(re.fullmatch(r'[A-Za-z_$][A-Za-z_0-9/$.[\]:-]*', x) for x in left + right):
                for a, b in zip(left, right):
                    self.union(a, b)
        self.clock_inputs = {}
        for cell in self.cells:
            if cell['kind'] == 'EG_PHY_GCLK':
                p = cell['ports']
                self.clock_inputs.setdefault(self.find(net(p.get('clko', ''))), []).append(self.find(net(p.get('clki', ''))))
        plls = [c for c in self.cells if c['kind'] == 'EG_PHY_PLL' and c['name'] == PLL]
        if len(plls) != 1:
            raise ValueError('missing/duplicate actual system PLL instance')
        self.pll = plls[0]
        params = dict(re.findall(r'\.([A-Za-z_0-9]+)\(([^()]*)\)', self.pll['params']))
        expected = {'FIN': '"50.000000"', 'REFCLK_DIV': '1', 'FBCLK_DIV': '2',
                    'FEEDBK_MODE': '"NORMAL"', 'FEEDBK_PATH': '"CLKC0_EXT"',
                    'CLKC0_DIV': '10', 'CLKC0_CPHASE': '9', 'CLKC0_FPHASE': '0',
                    'CLKC1_DIV': '20', 'CLKC1_CPHASE': '19', 'CLKC1_FPHASE': '0',
                    'CLKC0_ENABLE': '"ENABLE"', 'CLKC1_ENABLE': '"ENABLE"'}
        if any(params.get(k) != value for k, value in expected.items()):
            raise ValueError('actual system PLL is not the phase-related MEM50/WRITE100 profile')
        outs = self.expand(self.pll['ports'].get('clkc', ''))
        if len(outs) != 5:
            raise ValueError('system PLL requires five explicit clkc output positions')
        self.outputs = {i: self.find(n) for i, n in enumerate(reversed(outs))}
        if self.outputs[0] == self.outputs[1]:
            raise ValueError('WRITE100 and MEM50 PLL outputs are aliased')

    def expand(self, text):

        result = []
        for name in bits(text):
            if name in self.widths:
                high, low = self.widths[name]
                step = -1 if high >= low else 1
                result.extend(name + '[' + str(i) + ']' for i in range(high, low + step, step))
            else:
                result.append(name)
        return result

    def find(self, name):
        self.parent.setdefault(name, name)
        if self.parent[name] != name:
            self.parent[name] = self.find(self.parent[name])
        return self.parent[name]

    def union(self, a, b):
        self.parent[self.find(a)] = self.find(b)

    def origin(self, name, visiting=None):
        name = self.find(net(name))
        if name in self.outputs.values():
            return {i for i, n in self.outputs.items() if n == name}
        visiting = set() if visiting is None else set(visiting)
        if name in visiting:
            raise ValueError('cyclic native clock buffer chain')
        visiting.add(name)
        parents = self.clock_inputs.get(name, [])
        if len(parents) != 1:
            raise ValueError('clock is not driven by one actual system PLL output: ' + name)
        return self.origin(parents[0], visiting)

    def ff_driver(self, name):
        canonical = self.find(name)
        found = []
        for c in self.cells:
            qs = self.expand(c['ports'].get('q', ''))
            for position, output in enumerate(reversed(qs)):
                if self.find(output) == canonical:
                    if c['kind'] not in ('AL_MAP_SEQ', 'EG_PHY_LSLICE', 'EG_PHY_MSLICE') or not re.search(r'\.DFFMODE\("FF"\)', c['params']):
                        raise ValueError('expected clock-owned net is not a physical FF Q: ' + name)
                    if not c['ports'].get('clk'):
                        raise ValueError('expected FF has no real clock: ' + name)
                    found.append((c, position))
        if len(found) != 1:
            raise ValueError('expected FF Q driver missing/duplicated: ' + name + ' count=' + str(len(found)))
        return found[0]

    def reset_drivers(self, name, text):


        if name != 'reset_sys/release_pipe[1]':
            c, position = self.ff_driver(name)
            return [(name, c, position)]
        replicas = sorted(set(re.findall(re.escape(name) + r'_dup_\d+\b', clean(text))))
        rows = []
        for actual in [name] + replicas:
            try:
                c, position = self.ff_driver(actual)
            except ValueError as error:
                absent = 'expected FF Q driver missing/duplicated: ' + name + ' count=0'
                if actual == name and replicas and str(error) == absent:
                    continue
                raise
            if replicas:
                first, _ = self.ff_driver('reset_sys/release_pipe[0]')
                params = dict(re.findall(r'\.([A-Za-z_0-9]+)\(([^()]*)\)', c['params']))
                required = {'CEMUX': '"1"', 'CLKMUX': '"CLK"', 'DFFMODE': '"FF"',
                            'SRMODE': '"ASYNC"', 'SRMUX': '"INV"'}
                if c['kind'] == 'AL_MAP_SEQ':
                    required['REGSET'] = '"RESET"'
                    data = list(reversed(self.expand(c['ports'].get('d', ''))))
                else:
                    required['REG' + str(position) + '_SD'] = '"MI"'
                    required['REG' + str(position) + '_REGSET'] = '"RESET"'
                    data = list(reversed(self.expand(c['ports'].get('mi', ''))))
                if any(params.get(k) != v for k, v in required.items()):
                    raise ValueError('SYS reset replica is not an unconditional asynchronous-reset FF: ' + actual)
                if len(data) <= position or self.find(data[position]) != self.find('reset_sys/release_pipe[0]'):
                    raise ValueError('SYS reset replica D is not the actual preceding release stage: ' + actual)
                if not c['ports'].get('sr') or self.find(net(c['ports']['sr'])) != self.find(net(first['ports'].get('sr', ''))):
                    raise ValueError('SYS reset replica SR differs from the actual preceding release stage: ' + actual)
            rows.append((actual, c, position))
        if not rows:
            raise ValueError('SYS reset has neither its original Q nor actual validated replicas')
        return rows


def clock_tree(text):
    tree = ET.fromstring(text)
    clocks = {}
    owners = {}

    def walk(element, owner=None):
        if element.tag == 'clock':
            owner = element.attrib.get('name')
            if not owner or owner in clocks:
                raise ValueError('missing/duplicate native XML clock')
            clocks[owner] = dict(element.attrib)
        elif element.tag == 'pin' and owner:
            name = element.attrib.get('name')
            if name:
                owners.setdefault(name, set()).add(owner)
        for child in element:
            walk(child, owner)

    walk(tree)
    for index, freq in ((0, 100.0), (1, 50.0)):
        name = PLL + '.clkc[' + str(index) + ']'
        c = clocks.get(name)
        if not c or c.get('freq') != f'{freq:.3f}MHz' or c.get('type') != 'generated':
            raise ValueError('actual derived system PLL clock/frequency mismatch: ' + name)
        if int(c.get('endpoints', '0')) <= 0 or int(c.get('clocks', '0')) <= 0:
            raise ValueError('actual PLL clock has no clock endpoints: ' + name)
        if int(c.get('nonclocks', '-1')) != 0:
            raise ValueError('actual PLL output has unclassified/nonclock loads: ' + name)
    return clocks, owners


def source_profile(repo):
    text = clean((repo / TOP).read_text(encoding='utf-8'))
    instances = re.findall(r'\bv3_video_display_core\s*#\((.*?)\)\s+video\s*\(', text, re.S)
    if len(instances) != 1 or re.search(r'\bdefparam\s+video\.', text):
        raise ValueError('missing/ambiguous native display-core parameter contract')
    header = instances[0]
    def literal(name, default):
        found = re.findall(r'\.' + name + r'\(([^()]*)\)', header)
        if not found:
            return default
        if len(found) != 1 or found[0].strip() not in ('0', '1'):
            raise ValueError('unsupported native clock scope parameter: ' + name)
        return int(found[0])
    compact = re.sub(r'\s+', '', text)
    mode_dependent = 'assignsys_clk=HD?pll_sys100_clk:mem_clk;' in compact
    return dict(packed=literal('PACKED_CACHE', 0), external=literal('EXTERNAL_CACHE_WRITE', 0), mode_dependent_control=mode_dependent)


def check_texts(gate, route, clock_xml, *, packed=True, external_reset=False, sys_output=None):

    if not packed:
        if PREFIX in gate or PREFIX in route:
            raise ValueError('packed cache exists in native netlist despite disabled source scope')
        return dict(accepted=True, applicable=False, reason='packed cache disabled in source and absent in both native netlists')
    clocks, owners = clock_tree(clock_xml)
    expected = [(PREFIX + 'packet_data[' + str(i) + ']', 1) for i in range(32)]
    expected += [(PREFIX + 'request_toggle', 1)]
    expected += [(PREFIX + 'high_data[' + str(i) + ']', 0) for i in range(16)]
    expected += [(PREFIX + s, 0) for s in ('high_pending', 'seen_toggle', 'done_toggle')]
    if external_reset:
        expected += [('reset_cache_write/release_pipe[' + str(i) + ']', 0) for i in (0, 1)]
    if sys_output is not None:
        if sys_output not in (0, 1):
            raise ValueError('unsupported actual SYS output selection')
        expected += [('reset_sys/release_pipe[' + str(i) + ']', sys_output) for i in (0, 1)]
    result = dict(accepted=True, applicable=True, clock_owners={}, physical_stages={}, external_cache_reset_required=external_reset)
    for stage, text in (('gate', gate), ('route', route)):
        parsed = Native(text)
        rows = []
        pin_bindings = set()
        expanded_expected = [(name, output, actual, c, q_bit) for name, output in expected
                             for actual, c, q_bit in parsed.reset_drivers(name, text)]
        for name, output, actual, c, q_bit in expanded_expected:
            origin = parsed.origin(c['ports']['clk'])
            if origin != {output}:
                raise ValueError(stage + ' wrong clock ownership for ' + name + ': PLL outputs ' + repr(sorted(origin)))
            binding = (c['name'], q_bit)
            if binding in pin_bindings:
                raise ValueError(stage + ' independent serializer/reset FFs share a physical Q')
            pin_bindings.add(binding)
            actual_pin = c['name'] + '.clk'
            clock_name = PLL + '.clkc[' + str(output) + ']'
            if stage == 'route' and owners.get(actual_pin) != {clock_name}:
                raise ValueError('routed XML endpoint clock ownership differs for ' + actual_pin + ': ' + repr(sorted(owners.get(actual_pin, set()))))
            rows.append(dict(signal=name, actual_signal=actual, cell=c['name'], q_bit=q_bit, clock_pin=actual_pin, pll_output=output))
        rams = [c for c in parsed.cells if c['name'].startswith(PREFIX) and c['kind'] in ('EG_PHY_BRAM', 'EG_PHY_BRAM32K')]
        if len(rams) != 4 or any(c['kind'] != 'EG_PHY_BRAM32K' for c in rams):
            raise ValueError(stage + ' packed cache must have exactly four native BRAM32K macros')
        for c in rams:
            if parsed.origin(c['ports'].get('clka', '')) != {0}:
                raise ValueError(stage + ' packed BRAM write port is not WRITE100: ' + c['name'])
            pin = c['name'] + '.clka'
            if stage == 'route' and owners.get(pin) != {PLL + '.clkc[0]'}:
                raise ValueError('packed BRAM write XML endpoint differs: ' + pin)
            rows.append(dict(cell=c['name'], clock_pin=pin, pll_output=0, kind='BRAM32K_write'))
        result['physical_stages'][stage] = rows
    result['clock_owners'] = {name: clocks[name] for name in (PLL + '.clkc[0]', PLL + '.clkc[1]')}
    result['timing_signoff_by_this_check'] = False
    result['hardware_verified'] = False
    return result


def check(folder, repo):
    profile = source_profile(repo)
    names = ('gate.netlist.v', 'route.netlist.v', 'route.clocks')
    if folder.name not in ('base', 'hd'):
        raise ValueError('native clock domain gate requires an explicit base/hd folder')
    sys_output = 1 if profile['mode_dependent_control'] and folder.name == 'base' else 0
    result = check_texts(*[(folder / n).read_text(encoding='utf-8') for n in names], packed=bool(profile['packed']), external_reset=bool(profile['external']), sys_output=sys_output)
    result['source_profile'] = profile
    result['inputs'] = [{'path': str((folder / n).resolve()), 'sha256': hashlib.sha256((folder / n).read_bytes()).hexdigest()} for n in names]
    return result


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--folder', type=Path, required=True)
    ap.add_argument('--repo', type=Path, required=True)
    ap.add_argument('--output', type=Path, required=True)
    args = ap.parse_args()
    try:
        result = check(args.folder, args.repo)
    except (ValueError, OSError, KeyError, ET.ParseError) as error:
        result = dict(accepted=False, errors=[str(error)], hardware_verified=False)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
    print('PASS native packed clock ownership' if result['accepted'] else 'FAIL ' + repr(result['errors']))
    return 0 if result['accepted'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
