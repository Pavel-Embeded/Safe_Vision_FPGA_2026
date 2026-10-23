"""Fail-closed, portable audit of the independent packed writer clock proof."""
from pathlib import Path
import argparse, hashlib, json, re

def require(ok, message):
    if not ok:
        raise ValueError('packed-clock evidence: ' + message)

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def safe(base, name):
    path = (base / name).resolve()
    require(not Path(name).is_absolute() and path.is_relative_to(base.resolve()), 'path escapes evidence root')
    require(path.is_file(), 'missing file ' + name)
    return path

def normal_log(path, top, expected_errors):
    text = path.read_text(encoding='utf-8', errors='replace')
    require('$finish called' in text and '[TB] ' + top + ' done' in text, 'missing normal native completion')
    require(not re.search(r'(?im)^\s*(?:FATAL|Fatal:|ERROR:)|\[SKIP\]', text), 'crash/skip cannot establish detection')
    errors = [int(x) for x in re.findall(r'errors\s*=\s*(\d+)', text)]
    require(errors and (all(x == 0 for x in errors) if not expected_errors else errors[-1] == expected_errors), 'normal error count differs')
    if not expected_errors:
        require('[PASS]' in text and '[FAIL]' not in text, 'positive contains failure or missing checks')
    else:
        comparisons = [int(x) for x in re.findall(r'comparisons\s*=\s*(\d+)', text)]
        require(comparisons and comparisons[-1] > 0, 'negative did not execute native checks')
    return text

def audit(root, evidence):
    root, evidence = Path(root).resolve(), Path(evidence).resolve()
    index = json.loads(safe(evidence, 'complete.json').read_text(encoding='utf-8'))
    require(index.get('complete') is True and index.get('accepted') is True, 'cohort incomplete')
    require(index.get('hardware_verified') is False and index.get('STA_approved') is False, 'functional proof exceeds its boundary')
    require(index.get('original_matrix') == dict(positive=303, negative=221, retained=True), 'original matrix was reduced')
    require(sha(safe(root, index['gate_tool'])) == index['gate_tool_sha256'], 'gate producer source changed')
    inventory = json.loads(safe(evidence, 'files.sha256.json').read_text(encoding='utf-8'))
    require('complete.json' in inventory, 'cohort not inventoried')
    for name, digest in inventory.items():
        require(sha(safe(evidence, name)) == digest, 'raw evidence changed: ' + name)
    wanted = {'tb_v3_packed_clock_positive_261023': 102442,
              'tb_v3_packed_clock_negative_261023': 25604,
              'tb_v3_board_clocks': 210,
              'tb_v3_handbook_video_base': 3686400,
              'tb_v3_packed_readback_261023': 921600}
    positive = index.get('positive', [])
    require(len(positive) == len(wanted) and {x['top'] for x in positive} == set(wanted), 'required positive/control coverage missing or duplicated')
    for item in positive:
        top = item['top']
        require(item['result']['status'] == 'PASS' and not item['result'].get('source_overrides'), 'positive did not use original native sources')
        require(item['result'].get('data_comparisons', 0) >= wanted[top], 'independent data coverage too small')
        log = safe(evidence, item['capture'] + '/sim.log')
        require(sha(log) == item['log_sha256'], 'positive log changed')
        text = normal_log(log, top, 0)
        captured = json.loads(safe(evidence, item['capture'] + '/sources.sha256.json').read_text(encoding='utf-8'))
        require(captured == item['inputs'], 'positive input receipt changed')
        for name, digest in captured.items():
            require(sha(safe(root, name)) == digest, 'qualified source changed: ' + name)
        if top.endswith('negative_261023'):
            values = [int(x) for x in re.findall(r'detections\s*=\s*(\d+)', text)]
            require(values and values[-1] > 100, 'former WRITE50 corruptions were not detected')
    definitions = {
        'top_writer_back_to_sys50': ('.cache_write_clk(pll_sys100_clk)', '.cache_write_clk(sys_clk)', 'production packed writer really runs at 100MHz'),
        'core_ignores_external_writer': ('.write_clk(EXTERNAL_CACHE_WRITE?cache_write_clk:sys_clk)', '.write_clk(sys_clk)', 'production packed writer really runs at 100MHz'),
        'top_disables_external_writer': ('.EXTERNAL_CACHE_WRITE(1)', '.EXTERNAL_CACHE_WRITE(0)', 'production core explicitly selects external packed writer'),
        'writer_omits_media_reset': ('.async_rst_n(media_common_rst_n),.rst_n(cache_write_rst_n)', '.async_rst_n(control_common_rst_n),.rst_n(cache_write_rst_n)', 'media recovery immediately asserts the WRITE100 reset epoch')}
    negatives = index.get('normal_semantic_negatives', [])
    require(len(negatives) == 4 and {x['name'] for x in negatives} == set(definitions), 'four independent wiring/reset negatives required')
    for item in negatives:
        before, after, message = definitions[item['name']]
        require(item.get('accepted') is True and item.get('normally_finished') is True and item.get('process_exit') == 1 and item['detections'] > 0, 'negative was not normal semantic rejection')
        require(item['mutation'] == dict(old=before, new=after), 'wrong mutation contract')
        source = safe(root, item['source'])
        raw = source.read_text(encoding='utf-8')
        require(sha(source) == item['source_sha256'] and raw.count(before) == 1, 'negative baseline changed')
        mutant = safe(evidence, item['name'] + '/' + source.name)
        require(sha(mutant) == item['mutant_sha256'] and mutant.read_text(encoding='utf-8') == raw.replace(before, after), 'mutation differs from intended clock/reset fault')
        log = safe(evidence, item['capture'] + '/sim.log')
        require(sha(log) == item['log_sha256'], 'negative log changed')
        text = normal_log(log, 'tb_v3_board_clocks', item['detections'])
        require(message in text, 'intended public clock/reset contract did not reject the fault')
        inputs = json.loads(safe(evidence, item['capture'] + '/sources.sha256.json').read_text(encoding='utf-8'))
        for name, digest in inputs.items():
            require(digest == (item['mutant_sha256'] if name == item['source'] else sha(safe(root, name))), 'negative native input changed: ' + name)
    return dict(accepted=True, native_cohorts=5, normally_rejected_wiring_reset_mutants=4,
                normally_rejected_serializer_1to1=True, matrix_303_221_retained=True,
                hardware_verified=False, STA_approved=False)

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--root', type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument('--evidence', type=Path, required=True)
    args = parser.parse_args()
    print(json.dumps(audit(args.root, args.evidence), indent=2))

if __name__ == '__main__':
    main()
