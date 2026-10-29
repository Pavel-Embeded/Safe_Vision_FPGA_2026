


import argparse
import hashlib
import json
import re
import shutil
import tempfile
from pathlib import Path
import xml.etree.ElementTree as ET

from check_v3_native_clock_domains import Native, PREFIX, PLL, check_texts, net, clean
from check_v3_clock_contract import check as configured_clock_check

NAMES = ('gate.netlist.v', 'route.netlist.v', 'route.clocks')
ROOT = Path(__file__).resolve().parents[2]


def configured_controls(parent):
    base = 'safevision/platform/anlogic_eg4s20_hx4s20c/'
    top = base + 'rtl/safevision_top/safevision_v3_top.v'
    core = 'safevision/rtl/video/v3_video_display_core.v'
    files = [top, core, base + 'project/v3_board_verify/v3_board.sdc', base + 'project/v3_board_verify/io_budget.json']
    files += [base + 'ip/pll/' + n for n in ('sv_video_hd_pll.v', 'sv_video_vga_pll.v', 'sv_v3_memory_pll.v')]
    files += ['safevision/rtl/storage/spi_master.v', 'safevision/rtl/storage/sd_bmp_player.v', 'safevision/rtl/control/v3_supervisor.v', 'safevision/rtl/hd/v3_supervisor.v']
    controls = [
        ('actual_configured_clock_contract', None, None, None),
        ('explicit_write_clock_replaced_by_mem50', top, '.cache_write_clk(pll_sys100_clk)', '.cache_write_clk(mem_clk)'),
        ('explicit_reset_synchronizer_mem50', top, 'reset_cache_write(.clk(pll_sys100_clk)', 'reset_cache_write(.clk(mem_clk)'),
        ('core_external_clock_bypassed', core, 'EXTERNAL_CACHE_WRITE?cache_write_clk:sys_clk', 'EXTERNAL_CACHE_WRITE?sys_clk:sys_clk'),
        ('core_external_reset_bypassed', core, 'EXTERNAL_CACHE_WRITE?cache_write_rst_n:(sys_rst_n&&!media_reset)', 'EXTERNAL_CACHE_WRITE?sys_rst_n:(sys_rst_n&&!media_reset)'),
        ('physical_sys_clock_replaced_by_pll100_in_base', top, 'assign sys_clk=HD?pll_sys100_clk:mem_clk;', 'assign sys_clk=pll_sys100_clk;'),
    ]
    rows = []
    with tempfile.TemporaryDirectory(prefix='clock_guard_', dir=parent) as temporary:
        root = Path(temporary)
        if not root.resolve().is_relative_to(parent.resolve()):
            raise AssertionError('temporary control directory escaped output folder')
        for label, name, old, new in controls:
            for relative in files:
                destination = root / relative
                destination.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(ROOT / relative, destination)
            if name:
                path = root / name
                text = path.read_text(encoding='utf-8')
                if text.count(old) != 1:
                    raise AssertionError('configured mutation needs exact applicability: ' + label)
                path.write_text(text.replace(old, new), encoding='utf-8')
            error = None
            try:
                configured_clock_check(root)
            except ValueError as ex:
                error = str(ex)
            if bool(error) != bool(name):
                raise AssertionError((label, error))
            rows.append(dict(case=label, expected_reject=bool(name), rejected=bool(error), error=error,
                             input_kind='configured_source_control' if name else 'unchanged_actual_configured_source'))
    return rows


def change_port(text, cell_name, port, value):
    text = clean(text)
    pattern = r'^\s{2}(EG_[A-Z0-9_]+|AL_MAP_SEQ)\s*(?:#\((.*?)\)\s*)?(\\?[^\s()]+)\s*\((.*?)\);'
    hits = [m for m in re.finditer(pattern, text, re.M | re.S) if net(m[3]) == cell_name]
    if len(hits) != 1:
        raise AssertionError('mutator requires exactly one actual cell: ' + cell_name)
    m = hits[0]
    changed, count = re.subn(r'\.' + port + r'\(\s*[^()]*\)', '.' + port + '(' + value.replace('\\', '\\\\') + ')', m[0])
    if count != 1:
        raise AssertionError('mutator requires exactly one actual port: ' + port)
    return text[:m.start()] + changed + text[m.end():]


def change_xml(text, label, pin=None):
    tree = ET.fromstring(text)
    clock0 = next(x for x in tree.iter('clock') if x.get('name') == PLL + '.clkc[0]')
    clock1 = next(x for x in tree.iter('clock') if x.get('name') == PLL + '.clkc[1]')
    if label == 'zero':
        clock0.set('endpoints', '0'); clock0.set('clocks', '0')
    elif label == 'frequency':
        clock0.set('freq', '50.000MHz')
    elif label == 'duplicate':
        tree.append(ET.fromstring(ET.tostring(clock0)))
    elif label == 'missing_pin':
        hits = [x for x in tree.iter('pin') if x.get('name') == pin]
        if len(hits) != 1:
            raise AssertionError('missing exact XML pin for control')
        hits[0].set('name', 'negative_control_removed_endpoint')
    elif label == 'wrong_owner':
        parents = {child: parent for parent in tree.iter() for child in parent}
        hits = [x for x in tree.iter('pin') if x.get('name') == pin]
        if len(hits) != 1:
            raise AssertionError('missing exact XML pin for owner control')
        parents[hits[0]].remove(hits[0]); clock1.append(hits[0])
    else:
        raise AssertionError(label)
    return ET.tostring(tree, encoding='unicode')


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--positive-folder', type=Path, required=True)
    ap.add_argument('--bad-real-folder', type=Path, required=True)
    ap.add_argument('--output', type=Path, required=True)
    args = ap.parse_args()
    source = [(args.positive_folder / n).read_text(encoding='utf-8') for n in NAMES]
    gate, route, xml = source
    g, r = Native(gate), Native(route)
    high = PREFIX + 'high_pending'
    packet = PREFIX + 'packet_data[17]'
    gh = g.ff_driver(high)[0]
    gp = g.ff_driver(packet)[0]
    rh = r.ff_driver(high)[0]
    rp = r.ff_driver(packet)[0]
    write_g, mem_g = gh['ports']['clk'], gp['ports']['clk']
    write_r, mem_r = rh['ports']['clk'], rp['ports']['clk']
    gr = next(c for c in g.cells if c['kind'] == 'EG_PHY_BRAM32K' and c['name'].startswith(PREFIX))
    rr = next(c for c in r.cells if c['kind'] == 'EG_PHY_BRAM32K' and c['name'].startswith(PREFIX))
    cases = [
        ('unchanged_real_positive', source, {'sys_output': 0}, False),
        ('gate_high_clock_mem50', [change_port(gate, gh['name'], 'clk', mem_g), route, xml], {}, True),
        ('gate_packet_clock_write100', [change_port(gate, gp['name'], 'clk', write_g), route, xml], {}, True),
        ('route_high_clock_mem50', [gate, change_port(route, rh['name'], 'clk', mem_r), xml], {}, True),
        ('route_packet_clock_write100', [gate, change_port(route, rp['name'], 'clk', write_r), xml], {}, True),
        ('gate_ram_write_mem50', [change_port(gate, gr['name'], 'clka', mem_g), route, xml], {}, True),
        ('route_ram_write_mem50', [gate, change_port(route, rr['name'], 'clka', mem_r), xml], {}, True),
        ('xml_high_clock_missing', [gate, route, change_xml(xml, 'missing_pin', rh['name'] + '.clk')], {}, True),
        ('xml_high_wrong_clock_owner', [gate, route, change_xml(xml, 'wrong_owner', rh['name'] + '.clk')], {}, True),
        ('xml_ram_write_missing', [gate, route, change_xml(xml, 'missing_pin', rr['name'] + '.clka')], {}, True),
        ('xml_ram_write_wrong_clock_owner', [gate, route, change_xml(xml, 'wrong_owner', rr['name'] + '.clka')], {}, True),
        ('xml_write100_zero_endpoints', [gate, route, change_xml(xml, 'zero')], {}, True),
        ('xml_write100_frequency_drift', [gate, route, change_xml(xml, 'frequency')], {}, True),
        ('xml_duplicate_clock', [gate, route, change_xml(xml, 'duplicate')], {}, True),
        ('actual_external_reset_missing', source, {'external_reset': True}, True),
        ('base_control_wrong_pll_output', source, {'sys_output': 1}, True),
        ('packed_present_but_scope_disabled', source, {'packed': False}, True),
        ('nonpacked_bounded_not_applicable', ['module unrelated; endmodule'] * 2 + [''], {'packed': False}, False),
    ]
    pll_params = g.pll['params']
    if pll_params.count('.CLKC1_CPHASE(19)') != 1:
        raise AssertionError('positive actual PLL profile changed')

    changed = pll_params.replace('.CLKC1_CPHASE(19)', '.CLKC1_CPHASE(18)')
    clean_gate = clean(gate)
    if clean_gate.count(pll_params) != 1:
        raise AssertionError('actual system PLL parameter block is not unique')
    cases.append(('gate_pll_phase_relationship_drift', [clean_gate.replace(pll_params, changed), route, xml], {}, True))
    renamed = change_port(gate, gp['name'], 'q', 'negative_control_missing_packet_q')
    cases.append(('gate_missing_packet_q', [renamed, route, xml], {}, True))
    cases.append(('unchanged_bad_real_capture', [(args.bad_real_folder / n).read_text(encoding='utf-8') for n in NAMES], {}, True))
    rows = []
    for label, inputs, options, expected_reject in cases:
        error = None
        try:
            check_texts(*inputs, **options)
        except (ValueError, ET.ParseError) as ex:
            error = str(ex)
        if bool(error) != expected_reject:
            raise AssertionError((label, expected_reject, error))
        rows.append(dict(case=label, expected_reject=expected_reject, rejected=bool(error), error=error,
                         input_kind='unchanged_real_TD_capture' if label in ('unchanged_real_positive', 'unchanged_bad_real_capture') else 'parser_negative_control' if expected_reject else 'scope_control'))
    args.output.parent.mkdir(parents=True, exist_ok=True)
    rows.extend(configured_controls(args.output.parent))
    captures = []
    for folder in (args.positive_folder, args.bad_real_folder):
        captures.append(dict(folder=str(folder.resolve()), files=[dict(name=n, sha256=hashlib.sha256((folder / n).read_bytes()).hexdigest()) for n in NAMES]))
    result = dict(complete=True, accepted=True, results=rows, positive_cases=sum(not row['expected_reject'] for row in rows),
                  expected_rejections=sum(row['expected_reject'] for row in rows), original_native_captures=captures,
                  no_native_reports_modified=True, timing_signoff_by_this_check=False, hardware_verified=False)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
    print('PASS native clock checker: ' + str(result['positive_cases']) + ' positive, ' + str(result['expected_rejections']) + ' expected rejections')


if __name__ == '__main__':
    main()
