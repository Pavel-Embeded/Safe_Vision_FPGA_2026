from pathlib import Path
import hashlib,json,re

FLOW="safevision/platform/anlogic_eg4s20_hx4s20c/project/v3_board_verify/"

def validate(root):
 def tail(name):
  text=(root/FLOW/name).read_text("utf-8-sig")
  return "\n".join(x.rstrip()for x in text[text.index(" clear_sdc"):].splitlines()if x.strip())
 if tail("v3_td_flow.tcl")!=tail("v3_implementation_checkpoint.tcl"):raise ValueError("implementation timing/route stages differ from production flow")
 return dict(accepted=True,stages=2)

def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()


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


