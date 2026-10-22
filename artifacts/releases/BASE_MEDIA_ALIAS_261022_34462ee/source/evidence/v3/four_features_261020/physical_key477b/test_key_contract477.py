"""Recheck original board PDF and detect the shared-reference/ADC key swap."""
from pathlib import Path
import hashlib,json,re,shutil,sys
from pypdf import PdfReader
S=Path('D:/Codex/svkeyfix476/source');O=Path('D:/Codex/svkeyproof477b');O.mkdir()
sys.path.insert(0,str(S/'safevision/tools'))
from check_v3_board_reference import check,FLOW
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
save=lambda p,j:p.write_text(json.dumps(j,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
ref=json.loads((S/FLOW/'board_reference.json').read_text());material=Path(ref['source_root_at_review']);manual=next(d for d in ref['source_documents']if d['relative_path'].endswith('HX4S20开发板手册-HDL版2410.pdf'))
pdf=material/manual['relative_path'];assert sha(pdf)==manual['sha256']and pdf.stat().st_size==manual['bytes']
page=PdfReader(pdf).pages[18].extract_text();(O/'manual2410_printed_p19.txt').write_text(page,encoding='utf-8')
physical=dict(re.findall(r'\b(KEY[1-4])\s+([A-RT]\d+)\b',page));assert physical=={'KEY1':'A2','KEY2':'B2','KEY3':'B1','KEY4':'C1'}
old=Path('D:/Codex/svapproval448/source');adc=(S/FLOW/'v3_board.adc').read_text();original_ref=(S/FLOW/'board_reference.json').read_bytes()
def swap_adc(text):
 return text.replace('{ btn_auto } { LOCATION = B1;','{ btn_auto } { LOCATION = ZZ;').replace('{ btn_emergency } { LOCATION = C1;','{ btn_emergency } { LOCATION = B1;').replace('{ btn_auto } { LOCATION = ZZ;','{ btn_auto } { LOCATION = C1;')
def swap_ref(j):j['ports']['btn_auto']['LOCATION']='C1';j['ports']['btn_emergency']['LOCATION']='B1'
cases=[]
for name in ('positive','old_original_without_new_metadata','adc_swapped','reference_swapped','both_swapped_previous_bug','both_swapped_and_metadata','missing_key_contract','mislabelled_key','wrong_active_level','key_pull_down','duplicate_key_ball','missing_key_port'):
 root=O/name;f=root/FLOW;f.mkdir(parents=True)
 a=adc;j=json.loads(original_ref)
 if name=='old_original_without_new_metadata':
  a=(old/FLOW/'v3_board.adc').read_text();j=json.loads((old/FLOW/'board_reference.json').read_text())
 if name in ('adc_swapped','both_swapped_previous_bug','both_swapped_and_metadata'):a=swap_adc(a)
 if name in ('reference_swapped','both_swapped_previous_bug','both_swapped_and_metadata'):swap_ref(j)
 if name=='both_swapped_and_metadata':
  j['key_function_contract'][2]['ball']='C1';j['key_function_contract'][3]['ball']='B1'
 if name=='missing_key_contract':del j['key_function_contract']
 if name=='mislabelled_key':j['key_function_contract'][2]['button']='KEY4'
 if name=='wrong_active_level':j['key_function_contract'][2]['active_level']=1
 if name=='key_pull_down':a=a.replace('{ btn_auto } { LOCATION = B1; IOSTANDARD = LVCMOS33; PULLTYPE = PULLUP;','{ btn_auto } { LOCATION = B1; IOSTANDARD = LVCMOS33; PULLTYPE = PULLDOWN;')
 if name=='duplicate_key_ball':a=a.replace('{ btn_auto } { LOCATION = B1;','{ btn_auto } { LOCATION = B2;')
 if name=='missing_key_port':a='\n'.join(line for line in a.splitlines()if not line.startswith('set_pin_assignment { btn_auto }'))+'\n'
 (f/'v3_board.adc').write_text(a,encoding='utf-8',newline='\n');save(f/'board_reference.json',j);shutil.copyfile(S/FLOW/'v3_board.sdc',f/'v3_board.sdc')
 issue=None;rejected=False;result=None
 try:result=check(root)
 except ValueError as e:issue=str(e);rejected=True
 positive=name=='positive';accepted=not rejected if positive else rejected
 row=dict(name=name,positive=positive,accepted=accepted,rejected=rejected,issue=issue,result=result);save(root/'case.json',row);assert accepted,row;cases.append(row)
# The OLD real routed pad report must be refused by the NEW contract.
area=Path('D:/Codex/svformal415/base/td/base/route.area');issue=None
try:check(S,area.read_text())
except ValueError as e:issue=str(e)
assert issue and 'routed name/standard mismatch'in issue
(O/'old_route.area').write_bytes(area.read_bytes())
result=dict(accepted=all(x['accepted']for x in cases),positive_cases=1,negative_cases=len(cases)-1,old_real_routed_pad_mapping_rejected=True,old_route_rejection=issue,original_manual_sha256=sha(pdf),original_manual_printed_page=19,extracted_physical_key_balls=physical,manual_extraction_sha256=sha(O/'manual2410_printed_p19.txt'),checker_sha256=sha(S/'safevision/tools/check_v3_board_reference.py'),source_adc_sha256=sha(S/FLOW/'v3_board.adc'),source_reference_sha256=sha(S/FLOW/'board_reference.json'),test_script_sha256=sha(Path(__file__)),records=cases,hardware_verified=False,native_STA_approved=False)
save(O/'summary.json',result);print(json.dumps({k:v for k,v in result.items()if k!='records'}),flush=True)
