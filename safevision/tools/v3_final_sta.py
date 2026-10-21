"""Fresh-process STA of one frozen routed database; no place/route or DB writes.

TD 6.2 report_clock_summary mutates temporary clock metadata. Formal timing,
exceptions and zero-defect health are collected first. Clock-tree inspection
and its post-check are separately preserved; detailed results must stay exact.
"""
import hashlib,json,re,shutil,subprocess
from pathlib import Path
from datetime import datetime,timezone
from collections import Counter
from check_board_timing import read_report,PATH_RE,point_name

def digest(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def timing_identity(text,parse_global=True):
 margins={name:float(re.search(pattern,text,re.M)[1]) for name,pattern in (
  ('SWNS',r'^\s*SWNS:\s*([-.0-9]+)ns,'),('HWNS',r'^\s*HWNS:\s*([-.0-9]+)ns,'),
  ('STNS',r'^\s*SWNS:[^\n]*STNS:\s*([-.0-9]+)ns'),('HTNS',r'^\s*HWNS:[^\n]*HTNS:\s*([-.0-9]+)ns'))} if parse_global else {}
 groups=list(re.finditer(r'^Path Group\s*:\s*([^\n]*)',text,re.M));matches=list(PATH_RE.finditer(text));paths=Counter()
 for i,m in enumerate(matches):
  block=text[m.end():matches[i+1].start() if i+1<len(matches) else len(text)]
  corner=re.search(r'^Process\s*:\s*(slow|fast)\s*$',block,re.M)
  budget=re.search(r'^Budget\s*:\s*([-+.0-9]+)ns',block,re.M)
  group=next((g[1].strip() for g in reversed(groups) if g.start()<m.start()),'')
  if not corner or not budget:raise ValueError('incomplete detailed timing corner/budget')
  paths[(point_name(m[2]),point_name(m[3]),m[4].lower(),round(float(m[1]),3),corner[1],group,round(float(budget[1]),3))]+=1
 clocks=sorted(set((name,round(float(rise),3),round(float(fall),3),round(float(period),3)) for name,rise,fall,period in re.findall(r'clock\s+(\S+)\s+\{\s*rise@([-+.0-9]+)ns\s+fall@([-+.0-9]+)ns\s+period=([-+.0-9]+)',text)))
 return margins,paths,clocks

def actual_exceptions(text):
 return Counter(tuple(m.groups()[:4])+(' '.join(m[5].split()),) for m in re.finditer(r'^\s*(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(set_(?:max_delay|multicycle_path)[^\n]*)$',text,re.M))
def serialize_paths(paths):
 return [dict(zip(('begin','end','type','slack_ns','corner','group','budget_ns','count'),(*key,count))) for key,count in paths.items()]

def reassess(exe,folder,sdc_paths,audit_path=None,env=None,route_process_exit_code=None):
 folder=Path(folder).resolve();database=folder/'route.db';constraints=[Path(p).resolve() for p in sdc_paths]
 if audit_path:constraints.append(Path(audit_path).resolve())
 frozen={str(database):digest(database),**{str(p):digest(p) for p in constraints}}
 before_timing=read_report(folder/'route.timing');before_exceptions=read_report(folder/'route.exceptions')
 old_reports={}
 for name in ('route.timing','route.check','route.exceptions','route.clocks','route.derived.sdc','route.status','constraint.objects.tsv'):
  p=folder/name
  if p.is_file():
   copy=folder/('inprocess.'+name);shutil.copyfile(p,copy);old_reports[name]={'path':str(copy),'sha256':digest(copy)}
 commands=['cd {'+folder.as_posix()+'}','if {[catch {',' import_db {'+database.as_posix()+'}',' clear_sdc']
 commands+=[' read_sdc {'+Path(p).as_posix()+'}' for p in sdc_paths];commands+=[' update_timing -mode final']
 if audit_path:commands+=[' source {'+Path(audit_path).as_posix()+'}']
 commands+=[' report_timing_summary -ep_num 200 -path_num 3 -file route.timing',' report_timing_status -file route.status',
 ' report_timing_exception -ep_num 200 -path_num 8 -file route.exceptions',' check_timing -verbose -file route.check',' export_sdc -file route.derived.sdc',
 # All formal reports above use the exact same pre-clock-summary clock graph.
 ' report_clock_summary -levels 20 -expand_buckets -debug -file route.clocks',
 ' check_timing -verbose -file after_clock_report.check',
 ' report_timing_summary -ep_num 200 -path_num 3 -file after_clock_report.timing',
 ' report_timing_exception -ep_num 200 -path_num 8 -file after_clock_report.exceptions',
 '} err]} {puts stderr "V3 FINAL STA FAILED: $err";exit 1}','puts "V3 FINAL STA COMPLETE"','exit 0']
 tcl=folder/'final_sta.tcl';tcl.write_text('\n'.join(commands)+'\n',encoding='ascii')
 record={'schema':2,'created_at_utc':datetime.now(timezone.utc).isoformat(),'scope':'fresh-process STA only of frozen physical database; no placement or route',
 'database_and_constraint_sha256_before':frozen,'native_tcl_sha256':digest(tcl),'native_executable':str(exe),'native_executable_sha256':digest(Path(exe)),
 'caller_route_process_exit_code':route_process_exit_code,'route_process_exit_supplied_by_caller':route_process_exit_code is not None,
 'inprocess_reports':old_reports,'accepted':False,'errors':[]}
 output=folder/'final_sta.manifest.json'
 def save():output.write_text(json.dumps(record,indent=2,ensure_ascii=False)+'\n',encoding='utf-8')
 save()
 try:
  if route_process_exit_code not in (None,0):raise RuntimeError('caller route process did not exit zero')
  with (folder/'final_sta.console.log').open('w',encoding='utf-8') as f:p=subprocess.run([str(exe),tcl.as_posix()],cwd=folder,env=env,stdout=f,stderr=subprocess.STDOUT,timeout=600)
  record['sta_process_exit_code']=p.returncode;console=(folder/'final_sta.console.log').read_text(encoding='utf-8',errors='replace')
  record['normal_completion']=p.returncode==0 and 'V3 FINAL STA COMPLETE' in console and not re.search(r'V3 FINAL STA FAILED|\bERROR:',console)
  if not record['normal_completion']:raise RuntimeError('fresh TD STA failed or lacks normal completion marker')
  after={name:digest(Path(name)) for name in frozen};record['database_and_constraint_sha256_after']=after
  if after!=frozen:raise RuntimeError('frozen database or constraints changed during final STA')
  margins0,paths0,clocks0=timing_identity(before_timing);margins1,paths1,clocks1=timing_identity(read_report(folder/'route.timing'))
  margins2,paths2,clocks2=timing_identity(read_report(folder/'after_clock_report.timing'))
  _,epaths0,eclocks0=timing_identity(before_exceptions,False);_,epaths1,eclocks1=timing_identity(read_report(folder/'route.exceptions'),False);_,epaths2,eclocks2=timing_identity(read_report(folder/'after_clock_report.exceptions'),False)
  record.update(global_margins_before=margins0,global_margins_after=margins1,reported_path_count_before=sum(paths0.values()),reported_path_count_after=sum(paths1.values()),
   reported_path_signature_unchanged=paths0==paths1,added_endpoint_paths=serialize_paths(paths1-paths0),removed_endpoint_paths=serialize_paths(paths0-paths1),
   effective_reported_clocks_before=clocks0,effective_reported_clocks_after=clocks1,
   actual_exception_commands_and_counts_unchanged=actual_exceptions(before_exceptions)==actual_exceptions(read_report(folder/'route.exceptions')),
   post_clock_diagnostic={'same_detailed_paths_and_slacks':paths1==paths2,'same_effective_reported_clocks':clocks1==clocks2,'same_global_margins':margins1==margins2,
    'same_exception_commands_and_counts':actual_exceptions(read_report(folder/'route.exceptions'))==actual_exceptions(read_report(folder/'after_clock_report.exceptions')),
    'formal_health_file':'route.check','diagnostic_health_file':'after_clock_report.check','diagnostic_health_never_substitutes_for_gate':True})
  record['native_exception_path_identity']={'count_before':sum(epaths0.values()),'count_after':sum(epaths1.values()),'same_path_slack_corner_group_budget':epaths0==epaths1,'same_effective_clocks':eclocks0==eclocks1,'unchanged_after_clock_diagnostic':epaths1==epaths2 and eclocks1==eclocks2}
  if epaths0!=epaths1 or eclocks0!=eclocks1 or epaths1!=epaths2 or eclocks1!=eclocks2:raise RuntimeError('native exception path/slack/corner/group/clock coverage differs')
  if any(abs(margins0[k]-margins1[k])>0.001 for k in margins0):raise RuntimeError('fresh STA global margins disagree with in-process timing')
  if paths0!=paths1 or clocks0!=clocks1:raise RuntimeError('fresh STA path/slack/corner/group/clock coverage differs; review preserved reports')
  if not record['actual_exception_commands_and_counts_unchanged']:raise RuntimeError('fresh STA actual exception command/counter coverage differs')
  if not all(record['post_clock_diagnostic'][key] for key in ('same_detailed_paths_and_slacks','same_effective_reported_clocks','same_global_margins','same_exception_commands_and_counts')):raise RuntimeError('clock diagnostic changed effective STA result')
  record['accepted']=True
 except Exception as e:record['errors'].append(str(e))
 save()
 if not record['accepted']:raise RuntimeError('final STA integrity: '+'; '.join(record['errors']))
 return record
