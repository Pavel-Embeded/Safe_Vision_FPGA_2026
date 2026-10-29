"""Refuse altered installation evidence; fixtures never access hardware."""
from pathlib import Path
import hashlib
import json
import re
import shutil
import tempfile
import unittest
from verify_ticker_flash261028 import ROOT, STAGES, verify


class FlashEvidenceControls(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory(prefix='sv-flash-controls-')
        cls.release = Path(cls.temp.name) / 'release'
        cls.release.mkdir()
        source = ROOT / 'artifacts/releases/BASE_26102801'
        index = json.loads((source / 'release.index.json').read_text('utf-8-sig'))
        for name in ('release.index.json', index['bitstream']):
            shutil.copyfile(source / name, cls.release / name)
        shutil.copytree(source / 'flash', cls.release / 'flash')
        shutil.copytree(source / 'board/boot', cls.release / 'board/boot')
        shutil.copyfile(source / 'board/execution_context.json', cls.release / 'board/execution_context.json')
        cls.original = {p.relative_to(cls.release): p.read_bytes() for p in cls.release.rglob('*') if p.is_file()}

    @classmethod
    def tearDownClass(cls):
        cls.temp.cleanup()

    def tearDown(self):
        for name, raw in self.original.items():
            (self.release / name).write_bytes(raw)

    def edit(self, name, function):
        path = self.release / name
        record = json.loads(path.read_text('utf-8-sig'))
        function(record)
        path.write_text(json.dumps(record), 'utf-8')

    def receipt(self, function):
        self.edit('flash/receipt.json', function)

    def stage_log(self, stage, transform):
        path = self.release / 'flash' / (stage + '.console.log')
        path.write_text(transform(path.read_text('utf-8-sig')), 'utf-8')
        self.receipt(lambda r: r['stages'][stage].update(log_sha256=hashlib.sha256(path.read_bytes()).hexdigest()))

    def test_actual_saved_installation_passes(self):
        result = verify(self.release)
        self.assertTrue(result['accepted'])
        self.assertEqual(result['independently_replayed_stages'], len(STAGES))
        self.assertFalse(result['cold_power_cycle_verified'])

    def test_wrong_bit_refused(self):
        self.receipt(lambda r: r.update(bit_sha256='0' * 64))
        with self.assertRaisesRegex(ValueError, 'bitstream'):
            verify(self.release)

    def test_wrong_programming_tool_refused(self):
        self.receipt(lambda r: r.update(bitwriter_sha256='0' * 64))
        with self.assertRaisesRegex(ValueError, 'tool identity'):
            verify(self.release)

    def test_wrong_fpga_in_rehashed_log_refused(self):
        self.stage_log('04_verify', lambda text: text.replace('EG4S20BG256', 'EG4S10BG256'))
        with self.assertRaisesRegex(ValueError, 'FPGA identity'):
            verify(self.release)

    def test_missing_verify_refused(self):
        self.receipt(lambda r: r.update(verify_spi_succeeded=False))
        with self.assertRaisesRegex(ValueError, 'incomplete'):
            verify(self.release)

    def test_failed_process_refused(self):
        self.receipt(lambda r: r['stages']['04_verify'].update(process_exit=1))
        with self.assertRaisesRegex(ValueError, 'Failed stage'):
            verify(self.release)

    def test_missing_stage_refused(self):
        self.receipt(lambda r: r['stages'].pop('02_backup'))
        with self.assertRaisesRegex(ValueError, 'installation stage'):
            verify(self.release)

    def test_verify_before_backup_refused(self):
        self.receipt(lambda r: r['stages']['04_verify'].update(started_at_utc=r['stages']['01_probe']['started_at_utc']))
        with self.assertRaisesRegex(ValueError, 'order'):
            verify(self.release)

    def test_raw_log_tamper_refused(self):
        path = self.release / 'flash/04_verify.console.log'
        path.write_bytes(path.read_bytes() + b'changed')
        with self.assertRaisesRegex(ValueError, 'evidence changed'):
            verify(self.release)

    def test_rehashed_error_log_refused(self):
        self.stage_log('04_verify', lambda text: text + '\nERROR: injected failure\n')
        with self.assertRaisesRegex(ValueError, 'reports an error'):
            verify(self.release)

    def test_rehashed_missing_completion_refused(self):
        self.stage_log('04_verify', lambda text: text.replace('SV_FLASH_VERIFY_DONE', 'SV_FLASH_VERIFY_ABSENT'))
        with self.assertRaisesRegex(ValueError, 'completion marker'):
            verify(self.release)

    def test_wrong_flash_identification_refused(self):
        self.stage_log('01_probe', lambda text: re.sub(r'(Density and Feature\s*:\s*)15\b', r'\g<1>14', text, flags=re.I))
        with self.assertRaisesRegex(ValueError, 'EF4015'):
            verify(self.release)

    def test_backup_copy_changed_refused(self):
        path = self.release / 'flash/before_flash_b.bin'
        data = bytearray(path.read_bytes()); data[123] ^= 1; path.write_bytes(data)
        with self.assertRaisesRegex(ValueError, 'read mismatch'):
            verify(self.release)

    def test_short_readback_refused(self):
        path = self.release / 'flash/after_flash_a.bin'
        path.write_bytes(path.read_bytes()[:-1])
        with self.assertRaisesRegex(ValueError, 'read mismatch'):
            verify(self.release)

    def test_false_prior_image_attribution_refused(self):
        self.receipt(lambda r: r.update(previous_image_matches_known_26102301=True))
        with self.assertRaisesRegex(ValueError, 'misattributed'):
            verify(self.release)

    def test_coldboot_claim_from_refresh_refused(self):
        self.receipt(lambda r: r.update(cold_power_cycle_verified=True))
        with self.assertRaisesRegex(ValueError, 'physical power cycle'):
            verify(self.release)

    def test_detached_boot_context_refused(self):
        self.edit('board/execution_context.json', lambda r: r.update(flash_receipt_sha256='0' * 64))
        with self.assertRaisesRegex(ValueError, 'detached'):
            verify(self.release)

    def test_boot_before_flash_refused(self):
        self.edit('board/execution_context.json', lambda r: r.update(utc='2020-01-01T00:00:00Z'))
        with self.assertRaisesRegex(ValueError, 'predates'):
            verify(self.release)

    def test_tampered_boot_bytes_refused(self):
        path = self.release / 'board/boot/rx.bin'
        path.write_bytes(path.read_bytes() + b'corrupt')
        with self.assertRaisesRegex(ValueError, 'raw bytes differ'):
            verify(self.release)

    def test_false_healthy_boot_summary_refused(self):
        self.edit('board/boot/status.json', lambda r: r.update(INTEGRITY=0x1234))
        with self.assertRaisesRegex(ValueError, 'summary differs'):
            verify(self.release)

    def test_damaged_recovery_bit_refused(self):
        path = self.release / 'flash/recovery/SafeVision_BASE_6a957b0.bit'
        path.write_bytes(b'not a recoverable bitstream')
        with self.assertRaisesRegex(ValueError, 'rollback'):
            verify(self.release)


if __name__ == '__main__':
    unittest.main()
