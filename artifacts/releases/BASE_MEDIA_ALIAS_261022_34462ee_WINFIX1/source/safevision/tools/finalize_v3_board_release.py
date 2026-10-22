"""Generate bits only from unchanged, strictly accepted frozen native builds.

The functional manifest is explicit: old, default evidence must never silently
approve new RTL. BASE-only engineering output is separately labelled and still
requires every BASE timing, physical, source and functional gate.
"""
import argparse
import hashlib
import json
import os
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

from audit_v3_raw_logs import audit_file
from audit_v3_resource_checkpoint import sources as audit_sources, within
from check_v3_board import check
from run_v3_board import invoke, source_commit_binding
from v3_functional_release import acceptance, unchanged
from v3_sources import ROOT, check_gui, snapshot
from check_v3_sim_graph import check as check_sim_graph


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read(path):
    return json.loads(path.read_text(encoding='utf-8-sig'))


def save(path, data):
    path.write_text(json.dumps(data, indent=2, ensure_ascii=False)+'\n', encoding='utf-8')


# These changed contracts extend the historical 113-test required set. Their
# independent models, actual logs and complete input fingerprints are mandatory.
SUPPLEMENTS = (
    ('handbook_26101804', 'tb_v3_rejected_counter_boundary'),
    ('handbook_26101804', 'tb_v3_mem_activity_tag'),
    ('handbook_26101804', 'tb_v3_mem_activity_tag_phase3'),
    ('handbook_26101804', 'tb_v3_mem_activity_tag_phase5'),
    ('handbook_26101804', 'tb_v3_related_status_capture'),
    ('handbook_26101804', 'tb_v3_row_integrity_full'),
    ('handbook_26101804', 'tb_v3_read_alignment'),
    ('handbook_26101804', 'tb_v3_read_alignment_short'),
    ('handbook_26101804', 'tb_v3_read_alignment_long'),
    ('handbook_26101804', 'tb_v3_read_alignment_basic'),
    ('handbook_26101804', 'tb_bram_adapter_aligned'),
    ('handbook_26101804', 'tb_bram_adapter_streaming'),
    ('handbook_26101901/development58/supplements', 'tb_v3_diag_board'),
    ('handbook_26101804', 'tb_v3_memory_path_observer'),
)

SUPPLEMENTS += tuple(('handbook_26101901/development58/supplements', top) for top in (
    'tb_v3_hd_uart_pipeline', 'tb_v3_hd_window_pipeline',
    'tb_v3_hd_progress_clear', 'tb_v3_hd_reject_carry',
    'tb_v3_sample_credit', 'tb_v3_fifo_phase50',
    'tb_v3_hd_audio_ring', 'tb_v3_hd_audio_wav',
    'tb_v3_hd_audio_wav_errors', 'tb_v3_hd_audio_system',
    'tb_v3_hd_audio_underflow', 'tb_v3_hd_audio_volume',
    'tb_v3_hd_audio_context', 'tb_v3_hd_audio_context_loop',
    'tb_v3_hd_audio_packet', 'tb_v3_hd_audio_ingress',
    'tb_v3_hd_audio_sample_fifo', 'tb_v3_wav_fallback_equivalence55',
    'tb_v3_wav_pair55_context', 'tb_v3_wav_pair55_wav_errors',
    'tb_v3_control_longpress55',
))

# Every supplemental record must bind the final selected snapshot. Preserve the
# historical records on disk, but never approve changed RTL using their hashes.
SUPPLEMENTS = tuple(('handbook_26101901/development76/supplements', top)
                    for _, top in SUPPLEMENTS) + tuple(
    ('handbook_26101901/development76/supplements', top) for top in (
        'tb_v3_column_equivalence67', 'tb_v3_directory_lba70',
        'tb_v3_hd_hex_payload74',
    ))


def development_proof_acceptance(root, manifest):
    """Require actual compiler graphs and the new contracts before bitgen."""
    index = read(within(root, manifest))
    required_mutants = {
        'fifo_write_release_early', 'fifo_read_release_wrong_edge',
        'reject_carry_equal_is_greater', 'reject_carry_wrong_bit',
        'progress_clear_stale_storage', 'autoplay_cycle_increment_two',
        'fallback_initial_mask_wrong', 'fallback_commit_lost',
        'acr_terminal_one_sample_late', 'control_longpress_increment_two',
        'column_reciprocal_round_down', 'column_quotient_wrong_slice',
        'column_publish_one_clock_early', 'rx_tick_prediction_wrong_threshold',
        'directory_bias_wrong_cluster', 'directory_cluster_offset_one_early',
        'hd_fault_nibble_parity_reversed', 'hd_underflow_hex_displaced',
    }
    actual = {row['mutation'] for row in index['negative_controls']}
    if not required_mutants.issubset(actual):
        raise ValueError('missing development semantic controls: '+repr(sorted(required_mutants-actual)))
    records = []
    for row in index['positive_tests']:
        folder = within(root, row['evidence'])
        records.append(check_sim_graph(root, folder, read(folder/'result.json')))
    for row in index['negative_controls']:
        folder = within(root, row['evidence']); case = read(folder/'case.json')
        records.append(check_sim_graph(root, folder, dict(suite=case['suite'], top=case['top']), case))
    names = ['safevision/tools/check_v3_sim_graph.py']
    for stem in ('v3_uart_pipeline_reference', 'v3_fifo_phase49_reference',
                 'v3_wav_fallback_reference55', 'v3_hd_supervisor_reference',
                 'v3_led_publication_reference', 'v3_wav_bounds_reference',
                 'v3_volume_column_reference67'):
        name = 'safevision/verification/models/'+stem+'.freeze.json'
        m = read(root/name); names += [name, m['original_path']]
        origin = within(root, m['original_path'])
        if sha(origin) != m['original_sha256']:
            raise ValueError('historical reference original changed: '+stem)
        reference = m.get('reference_path', 'safevision/verification/models/'+stem+'.sv')
        names.append(reference); raw = (root/reference).read_bytes()
        if hashlib.sha256(raw).hexdigest() != m['reference_sha256']:
            raise ValueError('frozen reference changed: '+stem)
        if m.get('namespace_only'):
            for a,b in sorted(m['namespace_only'], key=lambda pair:len(pair[1]), reverse=True):
                raw = raw.replace(b.encode(), a.encode())
            original = origin.read_bytes()
            if m.get('fragment_start'):
                marker = m['fragment_start'].encode()
                if original.count(marker) != 1:
                    raise ValueError('ambiguous historical reference fragment: '+stem)
                original = original[original.index(marker):]
                if hashlib.sha256(original).hexdigest() != m['fragment_sha256']:
                    raise ValueError('historical reference fragment changed: '+stem)
            if m.get('newline_normalized_to_LF'):
                raw = raw.replace(b'\r\n', b'\n')
                original = original.replace(b'\r\n', b'\n')
            if raw != original:
                raise ValueError('reference transformation changed: '+stem)
    name = 'safevision/verification/models/hd_audio_stimulus.freeze.json'
    for m in read(root/name):
        names += [m['original'], m['derived']]
        a,b = (root/m['original']).read_bytes(), (root/m['derived']).read_bytes()
        if hashlib.sha256(a).hexdigest()!=m['original_sha256'] or hashlib.sha256(b).hexdigest()!=m['derived_sha256']:
            raise ValueError('HD audio stimulus bytes changed')
        x,y = m['namespace_only']
        b = b.replace(y.encode(), x.encode())
        if a != b:
            raise ValueError('HD audio stimulus differs beyond namespace')
    names.append(name)
    return records, {n:sha(within(root,n)) for n in set(names)}


def supplemental_acceptance(root):
    hashes, records = {}, []
    # The portable audit reads these additional proof inputs. Bind them even
    # though they are not HDL compiler inputs, so transfer/bitgen cannot omit
    # or silently change the frozen stimulus and arithmetic qualification.
    if (root/'safevision/rtl/hd/v3_command_parser_catalog.v').exists():
        additions = [
            'safevision/verification/models/hd_command_catalog_stimulus.freeze.json',
            'evidence/v3/handbook_26101901/catalog_csa19/exhaustive.json',
            'evidence/v3/handbook_26101901/catalog_csa19/catalog.v',
        ]
        frozen = read(root/additions[0])
        additions += [frozen['original'], frozen['derived']]
        for name in additions:
            path = within(root, name)
            hashes[name] = sha(path)
    for group, top in SUPPLEMENTS:
        folder = within(root, 'evidence/v3/'+group+'/positive/'+top)
        result = read(folder/'result.json')
        if result['top'] != top or result['status'] != 'PASS' or result['source_overrides']:
            raise ValueError('supplemental runner rejected: '+top)
        count = audit_sources(root, folder)
        check_sim_graph(root, folder, result)
        raw = audit_file(folder/'sim.log', True)
        if not raw['accepted']:
            raise ValueError('supplemental raw log rejected: '+top)
        files = set(p for p in folder.rglob('*') if p.is_file())
        for name in read(folder/'sources.sha256.json'):
            if not name.startswith('generated:'):
                files.add(within(root, name))
        hashes.update({p.relative_to(root).as_posix(): sha(p) for p in files})
        records.append(dict(top=top, source_bindings_checked=count, raw_log_sha256=raw['sha256']))
    return records, hashes


def native_identity_matches(identity, record, mode, current):
    """Accept both recorded commit key names, rejecting absence or disagreement."""
    commits = [identity[key] for key in ('commit', 'source_commit') if key in identity]
    return (bool(commits) and all(value == record['source_commit'] for value in commits)
            and identity.get('mode', mode) == mode and identity.get('sources') == current)


def native_acceptance(root, run, mode, current):
    frozen = (run/mode/'source').resolve()
    folder = (run/mode/'td'/mode).resolve()
    record = read(folder/'build.manifest.json')
    identity = read(run/mode/'source.identity.json')
    if (record['mode'] != mode or record['status'] != 'PASS'
            or not record['source_unchanged'] or not record['source_commit_binding']['verified']
            or record['sources'] != current or snapshot(frozen) != current
            or not native_identity_matches(identity, record, mode, current)):
        raise ValueError(mode+': native build or source identity rejected')
    binding = source_commit_binding(root, root, record['source_commit'], current)
    if not binding['verified']:
        raise ValueError(mode+': build commit does not bind actual sources')
    # Fresh-STA records use the original frozen paths. Recheck those exact files,
    # then require their bytes to equal the current committed project above.
    gate = check(folder, frozen)
    if not gate['gate_accepted'] or not gate['timing_passed'] or gate['status'] != 'PASS':
        raise ValueError(mode+': strict routed gate rejected: '+repr(gate['errors']))
    exe = Path(record['td_executable']).resolve()
    if not exe.is_file() or sha(exe) != record['td_executable_sha256']:
        raise ValueError(mode+': native executable changed')
    if not record.get('td_version'):
        raise ValueError(mode+': missing actual tool version')
    for report in record['gate']['reports']:
        if sha(Path(report['path'])) != report['sha256']:
            raise ValueError(mode+': previously approved report changed')
    protected = {row['path']: row['sha256'] for row in gate['reports']}
    protected[str(folder/'build.manifest.json')] = sha(folder/'build.manifest.json')
    protected[str(run/mode/'source.identity.json')] = sha(run/mode/'source.identity.json')
    return dict(mode=mode, folder=folder, frozen=frozen, record=record,
                gate=gate, protected=protected, exe=exe)


def ensure_unchanged(root, hardware, proof, natives):
    if snapshot(root) != hardware or not unchanged(root, proof):
        raise ValueError('current hardware or functional proof changed during approval/bitgen')
    for native in natives:
        if snapshot(native['frozen']) != hardware:
            raise ValueError('frozen hardware sources changed during approval/bitgen')
        if any(sha(Path(p)) != digest for p, digest in native['protected'].items()):
            raise ValueError('approved routed evidence/database changed during approval/bitgen')
        if sha(native['exe']) != native['record']['td_executable_sha256']:
            raise ValueError('TD executable changed during approval/bitgen')


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--repo', type=Path, default=ROOT)
    ap.add_argument('--native-run', type=Path, required=True)
    ap.add_argument('--functional-manifest', type=Path, required=True)
    ap.add_argument('--output', type=Path, required=True)
    ap.add_argument('--check-only', action='store_true')
    ap.add_argument('--engineering-base-only', action='store_true',
                    help='BASE hardware repair candidate; never a two-mode release')
    a = ap.parse_args()
    if not __debug__:
        raise RuntimeError('release audit requires Python assertions enabled')
    root, run, out = a.repo.resolve(), a.native_run.resolve(), a.output.resolve()
    if not str(out).isascii():
        raise ValueError('use an ASCII output directory for TD')
    if out.exists() and any(out.iterdir()):
        raise ValueError('use a new empty output directory')
    if out.is_relative_to(root) or root.is_relative_to(out):
        raise ValueError('bitgen output must be isolated from the source checkout')
    out.mkdir(parents=True, exist_ok=True)
    summary = dict(schema=1, accepted=False, bitstreams_complete=False,
                   two_mode_release=False, hardware_verified=False,
                   engineering_candidate=a.engineering_base_only,
                   github_upload_performed=False,
                   created_at_utc=datetime.now(timezone.utc).isoformat())
    try:
        hardware = snapshot(root)
        gui = [check_gui(root, mode) for mode in ('base', 'hd')]
        functional, proof = acceptance(root, a.functional_manifest)
        graph_records, graph_inputs = development_proof_acceptance(root, a.functional_manifest)
        proof.update(graph_inputs)
        summary['actual_compiler_graphs'] = graph_records
        supplements, extra = supplemental_acceptance(root)
        proof.update(extra)
        helper = Path(__file__).resolve()
        proof[helper.relative_to(root).as_posix()] = sha(helper)
        commit = subprocess.check_output(['git', '-C', str(root), 'rev-parse', 'HEAD']).decode().strip()
        binding = source_commit_binding(root, root, commit, {**hardware, **proof})
        if not binding['verified']:
            raise ValueError('approval source/proof/tool is not an exact committed tree: '+repr(binding['errors']))
        modes = ('base',) if a.engineering_base_only else ('base', 'hd')
        natives = [native_acceptance(root, run, mode, hardware) for mode in modes]
        ensure_unchanged(root, hardware, proof, natives)
        summary.update(accepted=True, approval_source_commit=commit,
                       source_commit_binding=binding, functional_acceptance=functional,
                       supplemental_tests=supplements, source_sha256=hardware,
                       proof_sha256=proof, gui_cli=gui)
        for native in natives:
            save(out/(native['mode']+'.gate.json'), native['gate'])
        if a.check_only:
            summary['check_only'] = True
        else:
            # Keep all outputs pending until every requested mode succeeds.
            bits = []
            for native in natives:
                mode, folder = native['mode'], native['folder']
                ensure_unchanged(root, hardware, proof, natives)
                pending = out/(mode+'.pending.bit')
                tcl = out/(mode+'.bitgen.tcl')
                tcl.write_text('if {[catch {\n import_db {'+(folder/'route.db').as_posix()+'}\n bitgen -bit {'+pending.as_posix()+'}\n export_bitgen_param -file {'+(out/(mode+'.bitgen.params')).as_posix()+'}\n} err]} {puts stderr "V3 TD FAILED: $err";exit 1}\nputs "V3 BITGEN COMPLETE"\nexit 0\n', encoding='ascii')
                exit_code, text = invoke(native['exe'], tcl, out/(mode+'.bitgen.console.log'), os.environ.copy())
                if exit_code or 'V3 BITGEN COMPLETE' not in text or not pending.is_file() or not pending.stat().st_size:
                    raise RuntimeError(mode+': missing normal bitgen completion')
                ensure_unchanged(root, hardware, proof, natives)
                bits.append(dict(mode=mode, pending=pending, bytes=pending.stat().st_size,
                                 sha256=sha(pending), design_build_commit=native['record']['source_commit'],
                                 route_database_sha256=sha(folder/'route.db'),
                                 bitgen_parameters_sha256=sha(out/(mode+'.bitgen.params')),
                                 bitgen_script_sha256=sha(tcl),
                                 bitgen_console_sha256=sha(out/(mode+'.bitgen.console.log')),
                                 td_version=native['record']['td_version'],
                                 td_executable_sha256=native['record']['td_executable_sha256'],
                                 native_parameters=native['record']['native_parameters']))
            ensure_unchanged(root, hardware, proof, natives)
            for row in bits:
                bit = out/('SafeVision_'+row['mode'].upper()+'_'+commit[:7]+'.bit')
                row.pop('pending').replace(bit)
                row['path'] = str(bit)
            summary.update(bitstreams=bits, bitstreams_complete=True,
                           two_mode_release=not a.engineering_base_only)
        save(out/'release.index.json', summary)
        print('V3 FINALIZATION PASS: '+str(out), flush=True)
        return 0
    except Exception as ex:
        summary.update(accepted=False, bitstreams_complete=False, error=str(ex))
        save(out/'release.index.json', summary)
        print('V3 FINALIZATION REJECTED: '+str(ex), flush=True)
        return 1


if __name__ == '__main__':
    sys.exit(main())
