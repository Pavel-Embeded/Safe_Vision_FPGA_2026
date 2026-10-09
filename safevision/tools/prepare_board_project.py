"""Generate TD GUI projects from the same dependency manifest as board STA.

The official HDMI HDL is separately installed by prepare_board_project.ps1.
The legacy SDRAM-only GUI project remains available as safevision_loopback.al.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import xml.etree.ElementTree as ET

PLATFORM = 'safevision/platform/anlogic_eg4s20_hx4s20c'


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--repo', type=Path, required=True)
    args = ap.parse_args()
    root = args.repo.resolve()
    project = root / PLATFORM / 'project'
    manifest = project / 'board_verify/board_sources.list'
    vendor = project / 'vendor_hdmi/hdl_source'
    paths = []
    for line in manifest.read_text(encoding='utf-8').splitlines():
        line = line.strip()
        if not line or line.startswith('#'):
            continue
        line = line.replace('@video_pll@', 'sv_video_vga_pll.v')
        file = vendor / line[7:] if line.startswith('vendor/') else root / 'safevision' / line
        if not file.is_file():
            raise FileNotFoundError(file)
        paths.append(file)
    target = project / 'safevision.al'
    # TD's .al dialect writes the literal attribute value UsedInP&R.
    # Sanitize only that legacy token for the strict standard XML reader.
    template = (project / 'safevision_loopback.al').read_text(encoding='utf-8-sig')
    tree = ET.ElementTree(ET.fromstring(template.replace('UsedInP&R', 'UsedInP&amp;R')))
    doc = tree.getroot()
    # TD project paths are relative to the saved .al, so clones remain portable.
    doc.set('Path', '.')
    doc.find('Name').text = target.stem
    for tag in ['LABEL', 'MODULE']:
        doc.find('TOP_MODULE/' + tag).text = 'safevision_top'
    sources = doc.find('Source_Files')
    sources.clear()
    for group, items, belong in [
        ('Verilog', paths, 'design_1'),
        ('ADC_FILE', [project / 'board_verify/board_b.adc'], 'constraint_1'),
        ('SDC_FILE', [project / 'board_verify/board_b.sdc', project / 'board_verify/board_cdc.sdc'], 'constraint_1'),
    ]:
        parent = ET.SubElement(sources, group)
        for order, file in enumerate(items, 1):
            entry = ET.SubElement(parent, 'File', Path=os.path.relpath(file, project).replace('\\', '/'))
            info = ET.SubElement(entry, 'FileInfo')
            for name, value in [('UsedInSyn', 'true'), ('UsedInP&R', 'true'), ('BelongTo', belong), ('CompileOrder', str(order))]:
                ET.SubElement(info, 'Attr', Name=name, Val=value)
    config = doc.find("FileSets/FileSet[@Name='design_1']/Config")
    config.clear()
    ET.SubElement(config, 'Option', Name='IncludeDir', Val='../../../rtl/include')
    ET.indent(tree, space='    ')
    data = ET.tostring(doc, encoding='unicode').replace('UsedInP&amp;R', 'UsedInP&R')
    target.write_text('<?xml version="1.0" encoding="UTF-8"?>\n' + data + '\n', encoding='utf-8')
    records = [{'path': os.path.relpath(file, root).replace('\\', '/'), 'sha256': hashlib.sha256(file.read_bytes()).hexdigest()} for file in paths]
    audit = {'top': 'safevision_top', 'mode': 'base', 'device': doc.find('HardWare/Device').text,
             'project': str(target), 'sources': records, 'timing_passed': False, 'hardware_verified': False}
    (project / 'gui_base.manifest.json').write_text(json.dumps(audit, indent=2), encoding='utf-8')
    print(f'Prepared {target}: {len(paths)} verified HDL dependencies. Use run_board_sta.ps1 for the timing/bitgen gate.')


if __name__ == '__main__':
    main()
