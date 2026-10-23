"""Inspect actual mapped products and the registered-owner cut (diagnostic only).

This consumes the original TD mapped netlist; it is not a timing approval.
"""
from pathlib import Path
import argparse,hashlib,json,re,sys
ap=argparse.ArgumentParser();ap.add_argument('--repo',type=Path,required=True);ap.add_argument('--folder',type=Path,required=True);ap.add_argument('--output',type=Path,required=True);a=ap.parse_args()
sys.path.insert(0,str(a.repo/'safevision/tools'))
from check_v3_native_clock_domains import Native,clean,net,bits
p=a.folder/'gate.netlist.v';raw=p.read_text(encoding='utf-8');N=Native(raw);text=clean(raw)
pat=r'^\s{2}(EG_[A-Z0-9_]+|AL_MAP_[A-Z0-9_]+)\s*(?:#\((.*?)\)\s*)?(\\?[^\s()]+)\s*\((.*?)\);'
cells=[];drivers={}
for m in re.finditer(pat,text,re.M|re.S):
 c=dict(kind=m[1],name=net(m[3]),params=m[2]or'',ports=dict(re.findall(r'\.([A-Za-z_0-9]+)\(\s*([^()]*)\)',m[4])))
 cells.append(c);kind=c['kind']
 outs=('o',) if kind.startswith('AL_MAP_LUT')else ('q',)if kind=='AL_MAP_SEQ'else ('p',)if kind=='EG_PHY_MULT18'else ('q','f','fx','fco')if kind in('EG_PHY_LSLICE','EG_PHY_MSLICE')else ()
 for port in outs:
  for b in bits(c['ports'].get(port,'')):drivers.setdefault(N.find(b),[]).append((c,port))
def cone(start):
 seen=set();used={};boundary={};pending=list(start)
 while pending:
  n=N.find(pending.pop())
  if n in seen:continue
  seen.add(n);ds=drivers.get(n,[])
  if not ds:continue
  if len(ds)!=1:raise ValueError('ambiguous physical driver '+n)
  c,port=ds[0];used[c['name']]=c
  if port=='q':boundary[n]=c;continue
  if c['kind'].startswith('AL_MAP_LUT'):ins=[k for k in c['ports']if k!='o']
  elif c['kind']=='EG_PHY_MULT18':ins=['a','b']
  elif c['kind']in('EG_PHY_LSLICE','EG_PHY_MSLICE'):ins=['a','b','c','d','e','fci']
  else:raise ValueError('unsupported combinational cone '+c['kind'])
  pending.extend(b for k in ins for b in bits(c['ports'].get(k,'')))
 return seen,used,boundary
prefix='player/shared_service$service/';lba=prefix+'registered_lba$'
def ff_inputs(name):
 c,pos=N.ff_driver(name);ds=list(reversed(bits(c['ports'].get('d',''))))
 if len(ds)<=pos:raise ValueError('missing native FF data input '+name)
 # The SD/filesystem service is REF50 (the board input), not MEM50.
 # Bind it to the actual system PLL reference pin rather than infer a name.
 assert N.find(net(c['ports']['clk']))==N.find(net(N.pll['ports']['refclk']))
 return ds[pos],c
owner_d,owner_ff=ff_inputs(lba+'owner1')
products={};sets={}
for product in('directory_product_q','file_product_q'):
 roots=[];qs=[]
 for i in range(32):
  q=lba+product+f'[{i}]';d,c=ff_inputs(q);roots.append(d);qs.append(N.find(q))
 seen,used,boundary=cone(roots);dsps={n:c for n,c in used.items()if c['kind']=='EG_PHY_MULT18'}
 products[product]=dict(real_Q_bits=32,clock='board_REF50_actual_PLL_reference',live_owner_input_in_product_cone=N.find(owner_d)in seen,
  multiplier_cells=[dict(name=n,a=c['ports'].get('a'),b=c['ports'].get('b'))for n,c in sorted(dsps.items())],
  upstream_FF_Q=sorted(boundary),net_count=len(seen))
 sets[product]=set(dsps)
stage2=[]
for i in range(32):stage2.append(ff_inputs(prefix+'shared_lba'+f'[{i}]')[0])
seen,used,boundary=cone(stage2)
stage2_products={name:sum(N.find(lba+name+f'[{i}]')in boundary for i in range(32))for name in products}
checks=dict(each_product_has_two_distinct_actual_MULT18=all(len(s)==2 for s in sets.values()),
 product_MULT18_sets_disjoint=not set.intersection(*sets.values()),
 no_live_owner_mux_before_products=all(not r['live_owner_input_in_product_cone']for r in products.values()),
 stage2_uses_all64_registered_product_Q=all(n==32 for n in stage2_products.values()),
 stage2_uses_registered_owner1=N.find(lba+'owner1')in boundary,
 stage2_has_no_unregistered_multiplier=not any(c['kind']=='EG_PHY_MULT18'for c in used.values()))
result=dict(accepted=all(checks.values()),diagnostic_scope='mapped native ownership/data cut only;not routed STA or hardware approval',
 raw_netlist=str(p),raw_sha256=hashlib.sha256(p.read_bytes()).hexdigest(),products=products,
 registered_owner_FF=dict(name=owner_ff['name'],d=owner_d,clock='board_REF50_actual_PLL_reference'),
 stage2_registered_product_bits=stage2_products,checks=checks,total_MULT18=sum(c['kind']=='EG_PHY_MULT18'for c in cells))
a.output.parent.mkdir(parents=True,exist_ok=True);a.output.write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
print(json.dumps(dict(accepted=result['accepted'],checks=checks,total_MULT18=result['total_MULT18'],output=str(a.output))))
raise SystemExit(0 if result['accepted']else 1)
