"""Prove that the auxiliary auditor rejects weakened, missing or crashed proof.

This changes only a temporary copy of already collected evidence. It creates no
native PASS record and never modifies production sources or the original proof.
"""
from pathlib import Path
import argparse, copy, hashlib, json, shutil, stat
from audit_v3_packed_clock_261023 import audit

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def save(path, data):
    path.write_text(json.dumps(data, indent=2) + '\n', encoding='utf-8')

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--root', type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument('--evidence', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    baseline = audit(args.root, args.evidence)
    output = args.output.resolve()
    output.mkdir(exist_ok=False)
    original = json.loads((args.evidence / 'complete.json').read_text())
    inventory = json.loads((args.evidence / 'files.sha256.json').read_text())
    cases = ['incomplete', 'missing_negative', 'reduced_comparisons', 'wrong_ratio_no_detection',
             'negative_exit_zero', 'weakened_mutation', 'missing_finish', 'fatal_is_not_detection']
    records = []
    for name in cases:
        fixture = output / 'fixture'
        fixture.mkdir()
        for relative in [*inventory, 'files.sha256.json']:
            target = fixture / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(args.evidence / relative, target)
        data = copy.deepcopy(original)
        changed = []
        if name == 'incomplete':
            data['complete'] = False
        elif name == 'missing_negative':
            data['normal_semantic_negatives'].pop()
        elif name == 'reduced_comparisons':
            data['positive'][0]['result']['data_comparisons'] = 1
        elif name == 'wrong_ratio_no_detection':
            record = next(x for x in data['positive'] if x['top'] == 'tb_v3_packed_clock_negative_261023')
            log = fixture / record['capture'] / 'sim.log'
            import re
            log.write_text(re.sub(r'detections=\d+', 'detections=0', log.read_text()), encoding='utf-8')
            record['log_sha256'] = sha(log)
            changed.append(log)
        elif name == 'negative_exit_zero':
            data['normal_semantic_negatives'][0]['process_exit'] = 0
        elif name == 'weakened_mutation':
            data['normal_semantic_negatives'][0]['mutation']['new'] = '.cache_write_clk(pll_sys100_clk)'
        elif name == 'missing_finish':
            record = data['positive'][0]
            log = fixture / record['capture'] / 'sim.log'
            log.write_text(log.read_text().replace('$finish called', 'INTERRUPTED before finish'), encoding='utf-8')
            record['log_sha256'] = sha(log)
            changed.append(log)
        elif name == 'fatal_is_not_detection':
            record = data['normal_semantic_negatives'][0]
            log = fixture / record['capture'] / 'sim.log'
            log.write_text(log.read_text() + '\nFatal: injected simulator crash\n', encoding='utf-8')
            record['log_sha256'] = sha(log)
            changed.append(log)
        save(fixture / 'complete.json', data)
        updated = dict(inventory)
        for path in [fixture / 'complete.json', *changed]:
            updated[path.relative_to(fixture).as_posix()] = sha(path)
        save(fixture / 'files.sha256.json', updated)
        refused = False
        try:
            audit(args.root, fixture)
        except ValueError as error:
            refused = True
            message = str(error)
        if not refused:
            raise RuntimeError('auxiliary auditor accepted corrupted proof: ' + name)
        records.append(dict(name=name, rejected=True, reason=message))
        # Delete only this generated fixture inside the explicit output root.
        if fixture.resolve() != output / 'fixture' or not fixture.is_relative_to(output):
            raise RuntimeError('unsafe generated fixture cleanup path')
        for path in [fixture, *fixture.rglob('*')]:
            info = path.lstat()
            if path.is_symlink() or getattr(info, 'st_file_attributes', 0) & stat.FILE_ATTRIBUTE_REPARSE_POINT:
                raise RuntimeError('reparse point in generated fixture')
        shutil.rmtree(fixture)
    save(output / 'receipt.json', dict(accepted=True, baseline=baseline, audit_refusals=records,
                                      native_tests_created=False, hardware_verified=False))
    print('PACKED CLOCK AUDITOR SELFTEST PASS: 8 corrupted/weak proof variants refused')

if __name__ == '__main__':
    main()
