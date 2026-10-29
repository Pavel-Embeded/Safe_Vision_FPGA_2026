from pathlib import Path
import argparse
import hashlib
import json
import re

ROOT = Path(__file__).resolve().parents[2]

def fragment(text):
    start = ' reg normal_uart_half;'
    end = '\n wire[23:0] axis_data;'
    if text.count(start) != 1 or text.count(end) != 1: raise ValueError('ambiguous LED publication logic')
    return text[text.index(start):text.index(end)]

def check(root):
    top = root / 'safevision/platform/anlogic_eg4s20_hx4s20c/rtl/safevision_top/safevision_v3_top.v'
    models = root / 'safevision/verification/models'
    candidate = models / 'v3_led_publication_candidate.v'
    reference = models / 'v3_led_publication_reference.v'
    live = re.sub(r'\s+', '', fragment(top.read_text('utf-8-sig')))
    model = candidate.read_text('utf-8-sig')
    model = model[model.index(' reg normal_uart_half;'):model.rindex('\nendmodule')]
    if live != re.sub(r'\s+', '', model): raise ValueError('candidate differs from production LED logic')
    return dict(accepted=True, candidate_fragment_matches_real_top=True, sha256={p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in (top,candidate,reference)})

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    result = check(ROOT)
    (args.output / 'led_publication.binding.json').write_text(json.dumps(result, indent=2)+'\n', encoding='utf-8')
    print('PASS actual top/candidate LED publication binding')

if __name__ == '__main__': main()
