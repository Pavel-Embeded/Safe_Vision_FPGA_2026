"""Install the already approved BASE image; retain each actual Flash read."""
from pathlib import Path
from datetime import datetime, timezone
import hashlib, json, re, subprocess, sys

W = Path(__file__).resolve().parent
ROOT = W / 'wav_reject_barrier_source'
RELEASE = ROOT / 'artifacts/releases/BASE_26102801'
OUT = W / 'flash_install292'
BW = Path('D:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/bin/bw_commands_prompt.exe')
EXPECTED_BIT = '1a0cf8cccdb1487b34f70e20eaa333dc106826dbc1d821be99b6a828b80b4083'
EXPECTED_TOOL = '513b024c8c1853825441939c9c51feb0156c2c6c2043f854a39e805c38064401'
OLD_FLASH = '5647f05ec18958947d32874eeb788fa396a05d0bab7c1b71f112ceb7e9b31eee'
sys.path.insert(0, str(ROOT / 'safevision/tools'))
from v3_sources import snapshot
from run_v3_board import source_commit_binding

def now(): return datetime.now(timezone.utc).isoformat()
def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
def read(p): return json.loads(p.read_text('utf-8-sig'))
def save(p, v):
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(json.dumps(v, indent=2, ensure_ascii=False) + '\n', 'utf-8')
def require(value, message):
    if not value: raise RuntimeError(message)

require(not OUT.exists(), 'A fresh Flash evidence directory is required')
index = read(RELEASE / 'release.index.json')
bit = RELEASE / index['bitstream']
require(index['accepted'] and index['expected_firmware_id'] == '26102801', 'Approval missing')
require(sha(bit) == EXPECTED_BIT == index['bit_sha256'], 'Approved image identity differs')
require(sha(BW) == EXPECTED_TOOL, 'Unexpected BitWriter executable')
require(snapshot(ROOT) == index['source_sha256'], 'Physical source changed')
for name, digest in index['approval_inputs_sha256'].items():
    require(sha(ROOT / name) == digest, 'Approval input changed: ' + name)
require(source_commit_binding(ROOT, ROOT, index['approval_source_commit'], index['approval_inputs_sha256'])['verified'], 'Approval commit binding failed')
offline = read(W / 'clean_offline285/verification.json')
require(offline['accepted'] and offline['bit_sha256'] == EXPECTED_BIT, 'Fresh clean offline replay missing')
old = Path('D:/Codex/SafeVision_BASE_CURRENT/repo/artifacts/releases/BASE_26102301_6a957b0/flash_install')
old_bit = old / 'SafeVision_BASE_6a957b0.bit'
require(sha(old_bit) == '95ace341ca3aa00363b1a5fc31108fe6d3cd352579906047a6bb02c0ac1a4c5e', 'Prior successful recovery image missing')
OUT.mkdir()
receipt = dict(schema=1, firmware_id='26102801', bit_sha256=EXPECTED_BIT,
               approval_source_commit=index['approval_source_commit'], bitwriter_sha256=EXPECTED_TOOL,
               started_at_utc=now(), accepted=False, program_spi_succeeded=False,
               verify_spi_succeeded=False, refresh_succeeded=False,
               cold_power_cycle_verified=False, stages={})
save(OUT / 'receipt.json', receipt)
save(W / 'board_ticker274/physical_feedback.json', dict(
    evidence_kind='user_report', firmware_id='26102801', bit_sha256=EXPECTED_BIT,
    recorded_at_utc=now(), user_verbatim='六项均正常；六项都正常',
    replies=['六项均正常', '六项都正常'],
    scope='User observed the current SRAM-programmed image before this Flash operation; not a post-Flash or cold-power observation',
    chinese_legible=True, scroll_smooth=True, uptime_visible=True,
    spectrum_visible=True, pictures_normal=True, audio_normal=True))

def stage(name, body, markers):
    tcl = OUT / (name + '.tcl'); log = OUT / (name + '.console.log')
    tcl.write_text('if {[read_device_id -cable 0] ne "EG4S20BG256"} {error "Unexpected FPGA"}\n' + body + '\nexit 0\n', 'utf-8')
    started = now()
    print('START ' + name, flush=True)
    with log.open('wb') as stream:
        code = subprocess.run([str(BW), tcl.as_posix()], stdout=stream, stderr=subprocess.STDOUT).returncode
    text = log.read_bytes().decode('utf-8-sig', errors='replace')
    accepted = code == 0 and all(m in text for m in markers) and not re.search(r'(?im)^\s*(?:SV_FLASH_FAILED|ERROR\b|[A-Z]+-\d+\s*:\s*.*\b(?:failed|error)\b)', text) and not any(x in text for x in ('Unknown cable', 'USB device open error'))
    receipt['stages'][name] = dict(accepted=accepted, started_at_utc=started, ended_at_utc=now(), process_exit=code, log_sha256=sha(log), tcl_sha256=sha(tcl))
    save(OUT / 'receipt.json', receipt)
    require(accepted, 'Flash stage failed; preserve logs: ' + name)
    print('PASS ' + name, flush=True)
    return text

probe = stage('01_probe', 'puts "SV_FLASH_PROBE_BEGIN"\nget_flash_manufacturer -cable 0 -spd 7\nputs "SV_FLASH_PROBE_DONE"', ['SV_FLASH_PROBE_DONE'])
for pattern in (r'Manufacturer ID\s*:\s*ef\b', r'Interface type\s*:\s*40\b', r'Density and Feature\s*:\s*15\b'):
    require(re.search(pattern, probe, re.I), 'Expected EF4015 2 MiB Flash not confirmed; no write issued')
receipt['flash_jedec'] = 'EF4015'; receipt['flash_bytes'] = 2097152

def read_pair(stage_name, prefix):
    body = ''
    for copy in ('a', 'b'):
        output = OUT / (prefix + '_' + copy + '.bin')
        body += f'''set output {{{output.as_posix()}}}
if {{[file exists $output]}} {{error "Preserve existing Flash capture"}}
if {{[catch {{read_flash -start_addr 0x000000 -length 2097152 -output $output -level 1 -total 1 -cable 0}} err]}} {{puts stderr "SV_FLASH_FAILED $err";exit 1}}
if {{![file isfile $output] || [file size $output]!=2097152}} {{error "Incomplete Flash capture"}}
puts "SV_FLASH_READ_{copy.upper()}_DONE"
'''
    stage(stage_name, body, ['SV_FLASH_READ_A_DONE', 'SV_FLASH_READ_B_DONE'])
    paths = [OUT / (prefix + '_' + c + '.bin') for c in ('a', 'b')]
    require(all(p.stat().st_size == 2097152 for p in paths), 'Incomplete full Flash read')
    require(paths[0].read_bytes() == paths[1].read_bytes(), 'Two independent full Flash reads differ')
    result = dict(bytes=2097152, sha256=sha(paths[0]), copies=[p.name for p in paths], independent_reads_equal=True)
    receipt[prefix] = result; save(OUT / 'receipt.json', receipt)
    return result

before = read_pair('02_backup', 'before_flash')
receipt['previous_image_matches_known_26102301'] = before['sha256'] == OLD_FLASH
receipt['previous_successful_bit_sha256'] = sha(old_bit)
save(OUT / 'receipt.json', receipt)
candidate = bit.as_posix()
require(not any(c in candidate for c in '{}\r\n'), 'Unsafe Tcl image path')
for name, mode, key, marker in (
    ('03_program', 'program_spi', 'program_spi_succeeded', 'SV_FLASH_PROGRAM_DONE'),
    ('04_verify', 'verify_spi', 'verify_spi_succeeded', 'SV_FLASH_VERIFY_DONE')):
    text = stage(name, f'set candidate {{{candidate}}}\nif {{[catch {{download -bit $candidate -mode {mode} -spd 7 -cable 0}} err]}} {{puts stderr "SV_FLASH_FAILED $err";exit 1}}\nputs "{marker}"', [marker])
    require(re.search(r'RUN-1003\s*:\s*finish command "download .* -mode ' + mode + r' ', text), 'Normal completion marker missing: ' + mode)
    receipt[key] = True; save(OUT / 'receipt.json', receipt)
after = read_pair('05_readback', 'after_flash')
require(after['sha256'] != before['sha256'], 'Flash content unchanged despite new image request')
text = stage('06_refresh', f'set candidate {{{candidate}}}\nif {{[catch {{download -bit $candidate -mode refresh -spd 7 -cable 0}} err]}} {{puts stderr "SV_FLASH_FAILED $err";exit 1}}\nputs "SV_FLASH_REFRESH_DONE"', ['SV_FLASH_REFRESH_DONE'])
require(re.search(r'RUN-1003\s*:\s*finish command "download .* -mode refresh ', text), 'Refresh completion missing')
receipt.update(refresh_succeeded=True, accepted=True, ended_at_utc=now(), flash_written=True)
save(OUT / 'receipt.json', receipt)
print('FLASH PROGRAM + VERIFY + TWO FULL READBACKS + REFRESH PASS', flush=True)
