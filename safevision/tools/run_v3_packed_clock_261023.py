


from pathlib import Path
import argparse, concurrent.futures, hashlib, json, re, shutil, subprocess, sys

ROOT = Path(__file__).resolve().parents[2]
TOP_FILE = 'safevision/platform/anlogic_eg4s20_hx4s20c/rtl/safevision_top/safevision_v3_top.v'
CORE_FILE = 'safevision/rtl/video/v3_video_display_core.v'

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def require(ok, message):
    if not ok:
        raise ValueError(message)

def save(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2) + '\n', encoding='utf-8')

def check_positive(run, tops, minimum):
    receipt = json.loads((run / 'results.json').read_text(encoding='utf-8-sig'))
    require(receipt.get('complete') is True, 'native positive cohort incomplete: ' + str(run))
    selected = {item['top']: item for item in receipt['results']}
    records = []
    for top in tops:
        item = selected[top]
        require(item['status'] == 'PASS' and not item.get('source_overrides'), 'positive uses mutation or failed')
        folder = run / top
        text = (folder / 'sim.log').read_text(encoding='utf-8', errors='replace')
        require('$finish called' in text and re.search(r'\[TB\]\s*' + re.escape(top) + r'\s+done', text), 'normal completion missing')
        require(not re.search(r'(?im)\[FAIL\]|\[SKIP\]|^\s*(?:FATAL|Fatal:|ERROR:)', text), 'positive contains failure')
        counts = [int(x) for x in re.findall(r'errors\s*=\s*(\d+)', text)]
        require(counts and not any(counts), 'positive has nonzero errors')
        require(item.get('data_comparisons', 0) >= minimum, 'independent data comparison coverage too small')
        before = json.loads((folder / 'sources.sha256.json').read_text(encoding='utf-8'))
        require(all((ROOT / name).is_file() and sha(ROOT / name) == digest for name, digest in before.items()), 'positive input changed: ' + top)
        if top == 'tb_v3_packed_clock_negative_261023':
            detections = [int(x) for x in re.findall(r'detections\s*=\s*(\d+)', text)]
            require(detections and detections[-1] > 100, '1:1 mismatch was not independently detected')
        records.append(dict(top=top, result=item, capture=str(folder), log_sha256=sha(folder / 'sim.log'), inputs=before))
    return records

def negative(output, name, source, old, new, message):
    raw = (ROOT / source).read_text(encoding='utf-8')
    require(raw.count(old) == 1, 'mutation contract changed: ' + name)
    folder = output / name
    folder.mkdir()
    mutant = folder / Path(source).name
    mutant.write_text(raw.replace(old, new), encoding='utf-8')
    argv = [sys.executable, '-X', 'utf8', '-B', str(ROOT / 'safevision/tools/run_v3_sim.py'),
            '--suite', 'v3_board_clocks', '--run-dir', str(folder / 'native'),
            '--override-source', source + '=' + str(mutant)]
    with (folder / 'runner.log').open('wb') as log:
        process = subprocess.run(argv, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT, timeout=1200)
    capture = folder / 'native/tb_v3_board_clocks'
    text = (capture / 'sim.log').read_text(encoding='utf-8', errors='replace')
    require(process.returncode == 1, 'negative runner did not reject normally: ' + name)
    require('$finish called' in text and '[TB] tb_v3_board_clocks done' in text, 'negative did not finish: ' + name)
    require(not re.search(r'(?im)^\s*(?:FATAL|Fatal:|ERROR:)|\[SKIP\]', text), 'negative crashed or skipped: ' + name)
    counts = [int(x) for x in re.findall(r'errors\s*=\s*(\d+)', text)]
    require(counts and counts[-1] > 0 and message in text, 'intended semantic detection absent: ' + name)
    result = dict(name=name, accepted=True, normally_finished=True, detections=counts[-1],
                  source=source, source_sha256=sha(ROOT / source), mutant_sha256=sha(mutant),
                  mutation=dict(old=old, new=new), process_exit=process.returncode,
                  capture=str(capture), log_sha256=sha(capture / 'sim.log'))
    save(folder / 'receipt.json', result)
    print(json.dumps(dict(name=name, accepted=True, detections=counts[-1])), flush=True)
    return result

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--packed-run', required=True, type=Path)
    parser.add_argument('--board-run', required=True, type=Path)
    parser.add_argument('--video-run', required=True, type=Path)
    parser.add_argument('--readback-run', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    args.output.mkdir(exist_ok=False)
    positive = check_positive(args.packed_run, ['tb_v3_packed_clock_positive_261023', 'tb_v3_packed_clock_negative_261023'], 25000)
    positive += check_positive(args.board_run, ['tb_v3_board_clocks'], 210)
    positive += check_positive(args.video_run, ['tb_v3_handbook_video_base'], 3686400)
    positive += check_positive(args.readback_run, ['tb_v3_packed_readback_261023'], 921600)
    contracts = [
        ('top_writer_back_to_sys50', TOP_FILE, '.cache_write_clk(pll_sys100_clk)', '.cache_write_clk(sys_clk)', 'production packed writer really runs at 100MHz'),
        ('core_ignores_external_writer', CORE_FILE, '.write_clk(EXTERNAL_CACHE_WRITE?cache_write_clk:sys_clk)', '.write_clk(sys_clk)', 'production packed writer really runs at 100MHz'),
        ('top_disables_external_writer', TOP_FILE, '.EXTERNAL_CACHE_WRITE(1)', '.EXTERNAL_CACHE_WRITE(0)', 'production core explicitly selects external packed writer'),
        ('writer_omits_media_reset', TOP_FILE, '.async_rst_n(media_common_rst_n),.rst_n(cache_write_rst_n)', '.async_rst_n(control_common_rst_n),.rst_n(cache_write_rst_n)', 'media recovery immediately asserts the WRITE100 reset epoch'),
    ]
    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
        negative_records = list(pool.map(lambda contract: negative(args.output, *contract), contracts))

    for record in positive:
        require(all(sha(ROOT / name) == digest for name, digest in record['inputs'].items()), 'source changed during auxiliary gate')


        capture = Path(record['capture'])
        target = args.output / 'positive' / record['top']
        target.mkdir(parents=True)
        for item in capture.iterdir():
            if item.is_file() and item.suffix.lower() in ('.log', '.json', '.prj', '.mem'):
                shutil.copyfile(item, target / item.name)
        record['capture'] = target.relative_to(args.output).as_posix()
    for record in negative_records:
        record['capture'] = Path(record['capture']).relative_to(args.output).as_posix()
        save(args.output / record['name'] / 'receipt.json', record)
    save(args.output / 'complete.json', dict(complete=True, accepted=True, positive=positive,
         gate_tool='safevision/tools/run_v3_packed_clock_261023.py', gate_tool_sha256=sha(Path(__file__)),
         normal_semantic_negatives=negative_records, original_matrix=dict(positive=303, negative=221, retained=True),
         hardware_verified=False, STA_approved=False, bitstream_generated=False))


    files = {p.relative_to(args.output).as_posix(): sha(p) for p in args.output.rglob('*')
             if p.is_file() and 'xsim.dir' not in p.parts and p.suffix.lower() in ('.json', '.log', '.prj', '.mem', '.v')}
    save(args.output / 'files.sha256.json', files)
    print('PACKED CLOCK AUXILIARY GATE PASS', flush=True)
    return 0

if __name__ == '__main__':
    raise SystemExit(main())
