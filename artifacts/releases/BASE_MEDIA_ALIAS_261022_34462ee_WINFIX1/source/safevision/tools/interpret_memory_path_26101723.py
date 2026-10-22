"""Interpret ID17 passive windows. This is never a hardware acceptance gate."""
import argparse
import json
from pathlib import Path

WORDS = 320


def interpret(report):
    result = dict(available=False, hardware_acceptance_passed=False,
                  root_cause_proven=False, github_upload_performed=False,
                  windows={}, observations=[], limitations=[
        'Queries are sequential. Interpret full, frozen windows only.',
        'Source/write windows and the first verification require the same media epoch and candidate.',
        'Counts do not prove address order; two set flags do not prove data equality.',
        'Self-reported ID is not cryptographic firmware identity.'])
    values = report.get('values', {})
    required = [f'DIAG{i:02d}' for i in range(16)]
    if (not report.get('capture_complete') or report.get('errors') or
            report.get('expected_self_reported_id') != '26101723' or
            values.get('DIAG00') != 0x26101723 or
            any(name not in values for name in required)):
        result['observations'].append('A complete ID26101723 capture is required; old14/17 use different fields.')
        return result
    if any(type(values[name]) is not int or not 0 <= values[name] <= 0xffffffff for name in required):
        result['observations'].append('Malformed 32-bit diagnostic word.')
        return result
    packed, host = values['DIAG14'], values['DIAG15']
    counts = dict(source=(packed >> 18) & 511, write=(packed >> 9) & 511,
                  raw=packed & 511, host=(host >> 15) & 511)
    if (packed >> 27 or host & 0xff007000 or any(n > WORDS for n in counts.values()) or
            any(values[f'DIAG{i:02d}'] > 1 for i in range(10, 14))):
        result['observations'].append('Reserved bits or counts are inconsistent with ID17; inspect raw evidence.')
        return result
    for name, selector in [('source', 12), ('write', 13), ('raw', 10), ('host', 11)]:
        word, count = values[f'DIAG{selector:02d}'], counts[name]
        result['windows'][name] = dict(words=count, nonzero_seen=bool(word),
            complete=count == WORDS, every_observed_bit_zero=(word == 0 and count == WORDS))
    result['available'] = True
    result['all_windows_full'] = all(n == WORDS for n in counts.values())
    result['write_mask_at_first_read_command'] = (host >> 8) & 15
    result['write_mask_at_first_read_response'] = (host >> 4) & 15
    if not result['all_windows_full']:
        result['observations'].append('At least one window is incomplete. No stage localization is made.')
        return result
    zero = {k: v['every_observed_bit_zero'] for k, v in result['windows'].items()}
    if zero['source'] and not zero['write']:
        result['observations'].append('Accepted source words were all zero, but actual unmasked write commands included set bits. Check write buffering and candidate association.')
    if zero['source'] and zero['write'] and not zero['raw']:
        result['observations'].append('Source and unmasked write windows were all zero, but aligned physical read responses included set bits. Check physical storage, addresses, masks and read alignment; no single cause is proved.')
    if zero['raw'] and not zero['host']:
        result['observations'].append('Aligned physical responses were all zero, but verification-client words included set bits. Check read cache, response routing and transaction association.')
    if (zero['host'] and values.get('INTEGRITY') and values['DIAG05'] == 0 and
            values['DIAG06'] == 0xFCC39D65 and values['DIAG07'] != 0xFCC39D65):
        result['observations'].append('The first320 verification-client words were all zero, but row0 CRC differs from the320-zero-word CRC. Check the CRC capture/state/count path and association with the failing verification.')
    if not result['observations']:
        result['observations'].append('These windows alone do not localize the fault. Two set flags are not an equality test.')
    return result


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('analysis', type=Path)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    if args.analysis.resolve() == args.output.resolve():
        parser.error('preserve the input report')
    result = interpret(json.loads(args.analysis.read_text(encoding='utf-8-sig')))
    args.output.write_text(json.dumps(result, indent=2, ensure_ascii=False)+'\n', encoding='utf-8')
    print(json.dumps(result, indent=2, ensure_ascii=False))
