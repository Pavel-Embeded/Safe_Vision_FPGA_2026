"""Current restoring-divider proof; never relabel the old reciprocal sweep."""
from pathlib import Path
import argparse,hashlib,json,re,sys
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--repo',type=Path,default=Path(__file__).resolve().parents[2])
parser.add_argument('--evidence-folder',type=Path,required=True)
parser.add_argument('--out',type=Path,required=True)
args=parser.parse_args();S=args.repo.resolve();O=args.out.resolve();O.mkdir(parents=True,exist_ok=True)
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
rtl=S/'safevision/rtl/audio/v3_audio_volume.v';code=re.sub(r'\s+','',rtl.read_text())
required=["reg[29:0]product;", "reg[6:0]remainder;", "wire[7:0]trial={remainder,product[29]};", "wirequotient_bit=trial>=8'd100;", "wire[29:0]divided={product[28:0],quotient_bit};", "wire[23:0]quotient=product[23:0];", "if(divide_count<30)begin", "product<=divided;remainder<=quotient_bit?trial-8'd100:trial;", "if(count==36)beginleft_out<=result;product<=multiplied[29:0];remainder<=0;divide_count<=0;sign_current<=sign_right;end", "if(count==73)beginright_out<=result;valid_out<=1;active<=0;end"]
for token in required:assert token in code,token
table=[]
for remainder in range(100):
 for incoming_bit in range(2):
  trial=2*remainder+incoming_bit
  q=int(trial>=100);next_remainder=trial-100 if q else trial
  assert(q,next_remainder)==divmod(trial,100)
  assert 0<=next_remainder<100 and q in (0,1)
  # Prefix invariant: extending a correct decimal quotient/remainder by
  # one binary input bit remains correct. The prior quotient cancels on
  # both sides, so these200 cases cover every possible prefix length.
  assert 2*remainder+incoming_bit==100*q+next_remainder
  table.append(dict(remainder=remainder,input_bit=incoming_bit,quotient_bit=q,next_remainder=next_remainder))
assert len(table)==200 and (1<<23)*100 < (1<<30) and ((1<<30)-1)//100 < (1<<24)
sys.path.insert(0,str(S/'safevision/tools'))
from audit_v3_resource_checkpoint import sources
from check_v3_sim_graph import check as graph
from audit_v3_raw_logs import audit_file
folder=args.evidence_folder.resolve()
report=json.loads((folder.parent/'results.json').read_text());assert report['complete']
meta=report['results'][0];assert meta['status']=='PASS'and meta['data_comparisons']==64000 and not meta['source_overrides']
sources(S,folder);graph(S,folder,dict(meta,suite=report['suite']));assert audit_file(folder/'sim.log',True)['accepted']
j=dict(schema=1,accepted=True,rtl_sha256=sha(rtl),proof_script_sha256=sha(Path(__file__)),proof_type='All200 legal restoring-division transition states plus induction over30 input bits; not an838860801-value execution sweep.',state_cases=200,dividend_bits=30,divisor=100,initial_remainder=0,remainder_max=99,max_legal_absolute_pcm24=1<<23,max_gain=100,max_legal_product=(1<<23)*100,max_30bit_quotient=((1<<30)-1)//100,retained_quotient_bits=24,left_publication_active_edge=37,right_publication_active_edge=74,real_hdl_transition_comparisons=64000,native_producer=str(folder),native_log_sha256=sha(folder/'sim.log'),scope='Exact unsigned division and required bit widths for all legal products. Signed conversion, bypass and public timing additionally require the frozen all-gain public-interface XSim miter. No STA, encrypted-IP or hardware claim.',transition_table=table)
(O/'serial_division.proof.json').write_text(json.dumps(j,indent=2)+'\n',encoding='utf-8')
print('350 PASS:200 exhaustive legal division steps,30-step induction,real HDL64000 comparisons; current RTL bound; old reciprocal proof not reused.')
