"""Independently recheck the saved Flash installation and reload evidence."""
from pathlib import Path
from datetime import datetime
import argparse
import hashlib
import json
import re

ROOT = Path(__file__).resolve().parents[2]
OLD_FLASH = '5647f05ec18958947d32874eeb788fa396a05d0bab7c1b71f112ceb7e9b31eee'
STAGES = ('01_probe', '02_backup', '03_program', '04_verify', '05_readback', '06_refresh')
FRAME = re.compile(rb'\$(C:ACK=([0-9A-F]{2}),([0-9A-F]{8}))\*([0-9A-F]{2})\r\n')


def require(ok, message):
    if not ok:
        raise ValueError(message)


def read(path):
    return json.loads(path.read_text('utf-8-sig'))


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def xor(raw):
    value = 0
    for byte in raw:
        value ^= byte
    return value


def verify(release):
    index = read(release / 'release.index.json')
    folder = release / 'flash'
    receipt = read(folder / 'receipt.json')
    require(index['accepted'] and index['expected_firmware_id'] == receipt['firmware_id'] == '26102801', 'Flash firmware identity differs')
    require(sha(release / index['bitstream']) == index['bit_sha256'] == receipt['bit_sha256'], 'Flash candidate bitstream differs')
    require(receipt['approval_source_commit'] == index['approval_source_commit'], 'Flash approval commit differs')
    require(receipt['bitwriter_sha256'] == '513b024c8c1853825441939c9c51feb0156c2c6c2043f854a39e805c38064401', 'Flash programming tool identity differs')
    require(receipt['accepted'] and all(receipt[k] is True for k in ('program_spi_succeeded', 'verify_spi_succeeded', 'refresh_succeeded', 'flash_written')), 'Flash operation incomplete')
    require(receipt['cold_power_cycle_verified'] is False, 'This receipt does not establish a physical power cycle')
    require(receipt['flash_jedec'] == 'EF4015' and receipt['flash_bytes'] == 2097152, 'Wrong Flash device')
    require(set(receipt['stages']) == set(STAGES), 'Missing or extra installation stage')
    previous = datetime.fromisoformat(receipt['started_at_utc'])
    logs = {}
    for name in STAGES:
        stage = receipt['stages'][name]
        require(stage['accepted'] and stage['process_exit'] == 0, 'Failed stage: ' + name)
        require(sha(folder / (name + '.console.log')) == stage['log_sha256'] and sha(folder / (name + '.tcl')) == stage['tcl_sha256'], 'Raw Flash evidence changed: ' + name)
        start = datetime.fromisoformat(stage['started_at_utc'])
        end = datetime.fromisoformat(stage['ended_at_utc'])
        require(previous <= start <= end, 'Flash operation order differs')
        previous = end
        text = (folder / (name + '.console.log')).read_text('utf-8-sig', errors='replace')
        require(not re.search(r'(?im)^\s*(?:SV_FLASH_FAILED|ERROR\b|[A-Z]+-\d+\s*:\s*.*\b(?:failed|error)\b)', text), 'Flash log reports an error')
        require(not any(word in text for word in ('Unknown cable', 'USB device open error')), 'Flash cable failure')
        require(re.search(r'RUN-1003\s*:\s*finish command "read_device_id -cable 0"', text), 'Device probe did not complete')
        require(re.search(r'(?m)^EG4S20BG256\s*$', text), 'Unexpected FPGA identity in Flash log')
        logs[name] = text
    require(previous <= datetime.fromisoformat(receipt['ended_at_utc']), 'Flash completion predates its stages')
    for pattern in (r'Manufacturer ID\s*:\s*ef\b', r'Interface type\s*:\s*40\b', r'Density and Feature\s*:\s*15\b'):
        require(re.search(pattern, logs['01_probe'], re.I), 'EF4015 identification missing')
    require('SV_FLASH_PROBE_DONE' in logs['01_probe'], 'Probe completion missing')
    for prefix, name in (('before_flash', '02_backup'), ('after_flash', '05_readback')):
        record = receipt[prefix]
        expected = [prefix + '_' + letter + '.bin' for letter in ('a', 'b')]
        require(record['copies'] == expected and record['bytes'] == 2097152 and record['independent_reads_equal'], 'Wrong full-Flash capture inventory')
        for filename in expected:
            path = folder / filename
            require(path.stat().st_size == 2097152 and sha(path) == record['sha256'], 'Full Flash read mismatch: ' + filename)
            require(re.search(r'RUN-1003\s*:\s*finish command "read_flash -start_addr 0x000000 -length 2097152 -output [^\r\n]*' + re.escape(filename) + r' -level 1 -total 1 -cable 0"', logs[name]), 'Full Flash read completion missing')
        require((folder / expected[0]).read_bytes() == (folder / expected[1]).read_bytes(), 'Independent Flash reads differ')
        require(all('SV_FLASH_READ_' + letter + '_DONE' in logs[name] for letter in ('A', 'B')), 'Read completion markers missing')
    require(receipt['before_flash']['sha256'] != receipt['after_flash']['sha256'], 'New Flash contents unchanged')
    require(receipt['previous_image_matches_known_26102301'] == (receipt['before_flash']['sha256'] == OLD_FLASH), 'Prior Flash identity was misattributed')
    for name, mode, marker in (('03_program', 'program_spi', 'PROGRAM'), ('04_verify', 'verify_spi', 'VERIFY'), ('06_refresh', 'refresh', 'REFRESH')):
        require(re.search(r'RUN-1003\s*:\s*finish command "download -bit [^\r\n]*' + re.escape(index['bitstream']) + r' -mode ' + mode + r' -spd 7 -cable 0"', logs[name]), 'Normal operation completion missing: ' + mode)
        require('SV_FLASH_' + marker + '_DONE' in logs[name], 'Operation completion marker missing: ' + mode)
    context = read(release / 'board/execution_context.json')
    require(context['capture_after_flash_refresh'] and context['sram_program_repeated_for_this_capture'] is False and context['flash_receipt_sha256'] == sha(folder / 'receipt.json'), 'Reload capture is detached from Flash installation')
    require(datetime.fromisoformat(context['utc'].replace('Z', '+00:00')) >= datetime.fromisoformat(receipt['ended_at_utc']), 'Reload capture predates Flash installation')
    boot = release / 'board/boot'
    require(read(boot / 'boot.json')['accepted'] and read(boot / 'boot.json')['firmware_id'] == '26102801', 'Flash boot not ready')
    events = [json.loads(line) for line in (boot / 'trace.jsonl').read_text('utf-8-sig').splitlines() if line]
    raw = (boot / 'rx.bin').read_bytes()
    require(raw == b''.join(bytes.fromhex(e['hex']) for e in events if e['kind'] == 'rx'), 'Flash boot raw bytes differ')
    sent = [e for e in events if e['kind'] == 'tx']
    replies = list(FRAME.finditer(raw))
    require(len(sent) == len(replies) > 0 and raw.count(b'$C:ACK=') == len(replies), 'Flash boot transaction inventory differs')
    values = {}
    for tx, reply in zip(sent, replies):
        body = tx['body'].encode('ascii')
        require(bytes.fromhex(tx['hex']) == b'$' + body + ('*%02X\r\n' % xor(body)).encode('ascii'), 'Flash boot TX checksum differs')
        require(xor(reply[1]) == int(reply[4], 16) and int(reply[2], 16) == 0, 'Flash boot ACK rejected or corrupt')
        values[tx['body']] = int(reply[3], 16)
    require(values['B:DIAG=0'] == 0x26102801 and values['B:STATUS?'] == 7 and values['B:CACHE?'] == 15, 'Flash reload firmware or cache differs')
    counters = ('FAULT', 'LEVEL', 'INTEGRITY', 'PRESENTATION', 'RECOVERY', 'VUNDERFLOW', 'UNDERFLOW', 'OVERFLOW', 'WAVFALLBACK')
    require(all(values['B:' + name + '?'] == 0 for name in counters), 'Flash reload health fault')
    status = read(boot / 'status.json')
    require(all(status[name] == values['B:' + name + '?'] for name in ('STATUS', 'CACHE', 'SLOT', 'GEN') + counters) and status['ID'] == values['B:DIAG=0'], 'Flash boot summary differs from raw ACKs')
    recovery = folder / 'recovery/SafeVision_BASE_6a957b0.bit'
    require(sha(recovery) == receipt['previous_successful_bit_sha256'] == '95ace341ca3aa00363b1a5fc31108fe6d3cd352579906047a6bb02c0ac1a4c5e', 'Known successful rollback image differs')
    return dict(accepted=True, firmware_id='26102801', bit_sha256=index['bit_sha256'], flash_jedec='EF4015', flash_bytes=2097152, before_flash_sha256=receipt['before_flash']['sha256'], after_flash_sha256=receipt['after_flash']['sha256'], independently_replayed_stages=len(STAGES), boot_ack_count=len(replies), flash_written=True, refresh_boot_verified=True, cold_power_cycle_verified=False, hardware_test_performed=False, scope='Independent replay of saved program/verify/readback/reload evidence; physical power removal remains a separate observation')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--release', type=Path, default=ROOT / 'artifacts/releases/BASE_26102801')
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    try:
        result = verify(args.release.resolve())
    except Exception as error:
        result = dict(accepted=False, error=type(error).__name__ + ': ' + str(error))
    args.output.write_text(json.dumps(result, indent=2) + '\n', 'utf-8')
    print('FLASH EVIDENCE REPLAY ' + ('PASS' if result['accepted'] else 'FAILED: ' + result['error']))
    return 0 if result['accepted'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
