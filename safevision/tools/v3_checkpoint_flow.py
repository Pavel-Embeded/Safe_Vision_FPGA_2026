"""Keep synthesis and implementation in separate native TD processes."""
from pathlib import Path
import hashlib,json,re,subprocess
PARENT='c1a26ff7872227bcf6c3e022dfd72b84e27422df'
FLOW='safevision/platform/anlogic_eg4s20_hx4s20c/project/v3_board_verify/'
RUN_BEFORE="   route_exit,text=invoke(exe,root/FLOW/(mode+'.tcl'),out/(mode+'.console.log'),env,cwd=folder)"
RUN_AFTER="""   if a.synth_only:
    route_exit,text=invoke(exe,root/FLOW/(mode+'.tcl'),out/(mode+'.console.log'),env,cwd=folder)
   else:
    from v3_checkpoint_flow import create_receipt
    synthesis_env=env.copy();synthesis_env['SAFEVISION_V3_SYNTH_ONLY']='1'
    synthesis_exit,synthesis_text=invoke(exe,root/FLOW/(mode+'.tcl'),folder/'synthesis.console.log',synthesis_env,cwd=folder)
    if synthesis_exit or 'V3 TD SYNTHESIZED'not in synthesis_text:raise RuntimeError('missing normal synthesis checkpoint completion')
    checkpoint_hash=hashlib.sha256((folder/'gate.db').read_bytes()).hexdigest()
    implementation_env=env.copy();implementation_env['SAFEVISION_BOARD_MODE']=mode
    route_exit,text=invoke(exe,root/FLOW/'v3_implementation_checkpoint.tcl',out/(mode+'.console.log'),implementation_env,cwd=folder)
    (folder/'implementation.console.log').write_bytes((out/(mode+'.console.log')).read_bytes())
    record['checkpoint_handoff']=create_receipt(folder,record['source_commit'],checkpoint_hash)
    save(manifest,record)"""
CHECK_FILES_BEFORE=' from v3_sources import build_parameters,required_media_bram_locations'
CHECK_FILES_AFTER=" files.extend(('checkpoint.synthesis.json','synthesis.console.log','implementation.console.log','gate.db','place.hidden.params'))\n"+CHECK_FILES_BEFORE
CHECK_BEFORE=" if errors:return result\n integrity="
CHECK_AFTER=""" if errors:return result
 from v3_checkpoint_flow import verify_receipt
 try:result['checkpoint_handoff']=verify_receipt(folder)
 except (ValueError,KeyError,OSError)as ex:errors.append(str(ex));return result
 integrity="""
SCOPE_BEFORE=" files.add(Path('safevision/tools/check_bmp_header_phase.py'))"
SCOPE_AFTER=SCOPE_BEFORE+"\n files.add(Path('safevision/tools/v3_checkpoint_flow.py'))"
SNAPSHOT_BEFORE='def snapshot(root):\n'
SNAPSHOT_AFTER=SNAPSHOT_BEFORE+' from v3_checkpoint_flow import validate\n validate(root)\n'

HIDDEN_ALLOWED_BEFORE="  ('place','effort'):{'low','medium','high'},"
HIDDEN_ALLOWED_AFTER="  ('place','ce_weight'):{'on'},('place','cn_opt_effort'):{'high'},\n  ('place','critical_hfn_opt'):{'on'},('place','enhanced_beeline_opt'):{'3'},\n  ('place','effort'):{'low','medium','high'},"
HIDDEN_READ_BEFORE="  if stage=='route'and name=='post_route_opt':"
HIDDEN_READ_AFTER="  if stage=='place'and name in('ce_weight','cn_opt_effort','critical_hfn_opt','enhanced_beeline_opt'):\n   path=folder/'place.hidden.params';text=path.read_text(encoding='utf-8');report_name=path.name\n   hits=re.findall(r'^place '+re.escape(name)+r' (\\w+)$',text,re.M)\n  elif stage=='route'and name=='post_route_opt':"

def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def blob(root,name):return subprocess.check_output(['git','-C',str(root),'cat-file','blob',PARENT+':'+name]).decode('utf-8-sig')
def transform(text,patches):
 for before,after in patches:
  if text.count(before)!=1:raise ValueError('checkpoint transform anchor changed: '+before[:80])
  text=text.replace(before,after)
 return text
def implementation_text(original):
 tail=original[original.index(' # Remove the pre-map clock objects'):]
 return '''# Import the exact serialized synthesis checkpoint in a fresh TD process.
# Source, constraints, hold repair and final reports use the production flow.
set board_mode $::env(SAFEVISION_BOARD_MODE)
if {$board_mode ni {base hd}} {error "Select base or hd"}
set here [file dirname [file normalize [info script]]]
set root [file normalize $::env(SAFEVISION_REPO)]
set out [file join [file normalize $::env(SAFEVISION_V3_OUT)] $board_mode]
cd $out
if {[catch {
 import_db [file join $out gate.db]
 source [file join $here v3_build_parameters.tcl]
 set mode_parameters [file join $here v3_build_parameters_${board_mode}.tcl]
 if {[file isfile $mode_parameters]} {source $mode_parameters}
 set place_hidden [open place.hidden.params w]
 foreach key {ce_weight cn_opt_effort critical_hfn_opt enhanced_beeline_opt} {puts $place_hidden "place $key [get_param place $key]"}
 close $place_hidden
'''+tail
def validate(root):
 expected={
  'safevision/tools/run_v3_board.py':transform(blob(root,'safevision/tools/run_v3_board.py'),[(RUN_BEFORE,RUN_AFTER)]),
  'safevision/tools/check_v3_board.py':transform(blob(root,'safevision/tools/check_v3_board.py'),[(CHECK_FILES_BEFORE,CHECK_FILES_AFTER),(CHECK_BEFORE,CHECK_AFTER)]),
  'safevision/tools/v3_sources.py':transform(blob(root,'safevision/tools/v3_sources.py'),[(SCOPE_BEFORE,SCOPE_AFTER),(SNAPSHOT_BEFORE,SNAPSHOT_AFTER),(HIDDEN_ALLOWED_BEFORE,HIDDEN_ALLOWED_AFTER),(HIDDEN_READ_BEFORE,HIDDEN_READ_AFTER)]),
  FLOW+'v3_implementation_checkpoint.tcl':implementation_text(blob(root,FLOW+'v3_td_flow.tcl'))}
 for name,text in expected.items():
  if(root/name).read_text('utf-8-sig')!=text:raise ValueError('unreviewed checkpoint-flow change: '+name)
 return dict(accepted=True,physical_function_changed=False,constraint_changed=False,exact_original_implementation_tail_retained=True,stages=2)
def create_receipt(folder,commit,before):
 if sha(folder/'gate.db')!=before:raise ValueError('serialized synthesis checkpoint changed during implementation')
 row=dict(schema=1,method='fresh synthesis / serialized gate.db / fresh implementation',source_commit=commit,synthesis_database_sha256_before=before,synthesis_database_sha256_after=sha(folder/'gate.db'),synthesis_console_sha256=sha(folder/'synthesis.console.log'),implementation_console_sha256=sha(folder/'implementation.console.log'),synthesis_process_exit=0,implementation_process_exit=0)
 (folder/'checkpoint.synthesis.json').write_text(json.dumps(row,indent=2)+'\n',encoding='utf-8')
 return verify_receipt(folder)
def verify_receipt(folder):
 row=json.loads((folder/'checkpoint.synthesis.json').read_text('utf-8-sig'));manifest=json.loads((folder/'build.manifest.json').read_text('utf-8-sig'))
 if row['schema']!=1 or row['method']!='fresh synthesis / serialized gate.db / fresh implementation':raise ValueError('checkpoint method differs')
 if row['source_commit']!=manifest['source_commit']or not manifest['source_commit_binding']['verified']:raise ValueError('checkpoint source commit differs')
 if row['synthesis_process_exit']!=0 or row['implementation_process_exit']!=0:raise ValueError('checkpoint subprocess failed')
 if row['synthesis_database_sha256_before']!=row['synthesis_database_sha256_after']or row['synthesis_database_sha256_after']!=sha(folder/'gate.db'):raise ValueError('checkpoint bytes differ')
 for name,key,marker in [('synthesis.console.log','synthesis_console_sha256','V3 TD SYNTHESIZED'),('implementation.console.log','implementation_console_sha256','V3 TD ROUTED')]:
  raw=(folder/name).read_text('utf-8',errors='replace')
  if sha(folder/name)!=row[key]or marker not in raw or re.search(r'V3 TD FAILED|\bERROR:|HDL-5105 CRITICAL-WARNING',raw):raise ValueError('checkpoint native completion differs: '+name)
 implementation=(folder/'implementation.console.log').read_text('utf-8',errors='replace')
 if not re.search(r'finish command "import_db [^\n]*gate\.db"',implementation):raise ValueError('implementation did not import serialized checkpoint')
 return dict(accepted=True,**row)
