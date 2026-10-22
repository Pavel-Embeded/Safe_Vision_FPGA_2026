from pathlib import Path
import copy,json,sys
S=Path(__file__).resolve().parents[2];sys.path.insert(0,str(S/'safevision/tools'))
from v3_resource_policy import load,validate,CAPACITY
from check_v3_board import resource_gate
p=load(S);checks=[]
def report(lut=18000,reg=13500,bram=46,bram32k=4,dsp=21,pll=3):
 values=locals();return '\n'.join(f'#{k} {values[k]} out of {n} {100*values[k]/n:.2f}%'for k,n in CAPACITY.items())
cases=[('candidate62',dict(),True),('physical64',dict(bram=48),True),('physical65',dict(bram=49),False),('double_pool_overflow',dict(bram=60,bram32k=2),False),('lut_capacity',dict(lut=19600),True),('lut_overflow',dict(lut=19601),False),('dff_limit',dict(reg=15680),True),('dff_over_limit',dict(reg=15681),False),('dsp_overflow',dict(dsp=30),False),('wrong_pll_count',dict(pll=2),False)]
for name,args,expected in cases:
 actual=resource_gate(report(**args),p);assert actual['accepted']==expected,(name,actual);checks.append(dict(name=name,expected=expected,accepted=actual['accepted'],errors=actual['errors']))
tamper=[('enlarge_device',lambda q:q['physical_capacity'].update(bram=128)),('discount32k',lambda q:q.update(ram32k_cost_in_9k_tiles=1)),('waive_timing',lambda q:q.update(requires_all_corner_setup_hold_recovery_removal=False)),('waive_routing',lambda q:q.update(requires_successful_native_placement_routing=False)),('remove_features',lambda q:q.update(feature_reduction_permitted=True)),('missing_ram_authorization',lambda q:q.pop('ram_authorization')),('wrong_ram_authorization_date',lambda q:q['ram_authorization'].update(date='2026-10-19'))]
for name,mutate in tamper:
 q=copy.deepcopy(p);mutate(q);rejected=False
 try:validate(q)
 except ValueError:rejected=True
 assert rejected,name;checks.append(dict(name=name,policy_tamper_rejected=True))
j=dict(accepted=True,checks=checks,physical_capacity_unchanged=True,bram32k_cost_in_9k_tiles=4,user_ram_authorization=p['ram_authorization'],native_placement_and_STA_still_required=True)
print(json.dumps(j,ensure_ascii=False,indent=2))
