"""Bind the small LED/UART models to the real top and frozen original bytes."""
from pathlib import Path
import argparse,hashlib,json
ROOT=Path(__file__).resolve().parents[2]
def fragment(text):
    start=' reg normal_uart_half;';end='\n wire[23:0] axis_data;'
    assert text.count(start)==1 and text.count(end)==1
    return text[text.index(start):text.index(end)]
def check(root):
    top=root/'safevision/platform/anlogic_eg4s20_hx4s20c/rtl/safevision_top/safevision_v3_top.v'
    models=root/'safevision/verification/models'
    candidate=models/'v3_led_publication_candidate.sv'
    reference=models/'v3_led_publication_reference.sv'
    part=fragment(top.read_text(encoding='utf-8'))
    assert candidate.read_text(encoding='utf-8').endswith(part+'\nendmodule\n'),'candidate model differs from real top publication'
    frozen=json.loads((models/'v3_led_publication_reference.freeze.json').read_text(encoding='utf-8'))
    assert hashlib.sha256(reference.read_bytes()).hexdigest()==frozen['reference_sha256']
    text=reference.read_text(encoding='utf-8');a=text.index(' reg normal_uart_half;');z=text.rindex('\nendmodule\n');old=text[a:z]
    assert hashlib.sha256(old.encode()).hexdigest()==frozen['fragment_sha256']
    return dict(accepted=True,top_sha256=hashlib.sha256(top.read_bytes()).hexdigest(),candidate_sha256=hashlib.sha256(candidate.read_bytes()).hexdigest(),reference_sha256=frozen['reference_sha256'],candidate_fragment_matches_real_top=True,reference_fragment_matches_frozen_original=True)
def main():
    ap=argparse.ArgumentParser();ap.add_argument('--output',type=Path,required=True);a=ap.parse_args();a.output.mkdir(parents=True,exist_ok=True)
    j=check(ROOT);(a.output/'led_publication.binding.json').write_bytes((json.dumps(j,indent=2)+'\n').encode());print('PASS actual top/candidate/frozen original LED publication binding')
if __name__=='__main__':main()
