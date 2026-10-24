"""Use actual shipped inputs to exercise CI refusal paths, never board I/O."""
from pathlib import Path
import hashlib, json, re, shutil, subprocess, tempfile, unittest
import yaml
from verify_current_base_ci import ROOT, RELEASE, FORMAL_CHECK, frozen_reference_environment, replay_timing, replay_uart

class CurrentDelivery(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory(prefix='safevision-ci-')
        cls.root = Path(cls.temp.name) / 'repo'
        cls.root.mkdir()
        shutil.copytree(ROOT / RELEASE, cls.root / RELEASE)
        cls.index_path = cls.root / RELEASE / 'release.index.json'
        cls.index = json.loads(cls.index_path.read_text(encoding='utf-8-sig'))
        names = list(cls.index['native_inputs_sha256']) + [str(FORMAL_CHECK).replace('\\','/'), 'safevision/tools/verify_base_release.mjs']
        for name in names:
            target = cls.root / name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(ROOT / name, target)

    @classmethod
    def tearDownClass(cls):
        cls.temp.cleanup()

    def reader(self, expected=True):
        p = subprocess.run(['node', str(self.root/'safevision/tools/verify_base_release.mjs')], capture_output=True, text=True)
        self.assertEqual(p.returncode == 0, expected, p.stdout+p.stderr)
        return p

    def changed(self, path, data, action):
        original = path.read_bytes()
        try:
            path.write_bytes(data)
            action()
        finally:
            path.write_bytes(original)

    def test_actual_delivery_and_report_replay(self):
        self.reader()
        self.assertTrue(replay_timing(self.root)['accepted'])
        self.assertEqual(replay_uart(self.root)['validated_ack_frames'], 5016)

    def test_corrupted_bitstream(self):
        p = self.root / RELEASE / 'SafeVision_BASE_6a957b0.bit'
        b = bytearray(p.read_bytes()); b[32] ^= 1
        self.changed(p, b, lambda: self.reader(False))

    def test_changed_native_input(self):
        p = self.root / next(iter(self.index['native_inputs_sha256']))
        self.changed(p, p.read_bytes()+b'changed', lambda: self.reader(False))

    def test_manifest_escape(self):
        outside = self.root.parent / 'outside.txt'; outside.write_bytes(b'outside')
        changed = json.loads(json.dumps(self.index))
        changed['native_inputs_sha256']['../outside.txt'] = hashlib.sha256(b'outside').hexdigest()
        self.changed(self.index_path, json.dumps(changed).encode(), lambda: self.reader(False))

    def test_unearned_cold_boot_claim(self):
        changed = {**self.index, 'cold_power_cycle_verified': True}
        self.changed(self.index_path, json.dumps(changed).encode(), lambda: self.reader(False))

    def test_unlisted_payload(self):
        p = self.root / RELEASE / 'unlisted.txt'
        try:
            p.write_bytes(b'not approved')
            self.reader(False)
        finally:
            p.unlink()

    def test_timing_parser_rejects_a_negative_path(self):
        p = self.root / RELEASE / 'native/base/route.timing'
        text = p.read_text(encoding='utf-8-sig')
        changed, n = re.subn(r'(Slack\s*:\s*)[-+.0-9]+(ns)', r'\g<1>-0.001\2', text, count=1)
        self.assertEqual(n, 1)
        def reject():
            with self.assertRaisesRegex(ValueError, 'routed timing'):
                replay_timing(self.root)
        self.changed(p, changed.encode(), reject)

    def test_uart_raw_byte_corruption(self):
        p = self.root / RELEASE / 'flash_install/evidence/after_flash_refresh/ready/rx.bin'
        b = bytearray(p.read_bytes()); b[0] ^= 1
        def reject():
            with self.assertRaisesRegex(ValueError, 'trace/raw'):
                replay_uart(self.root)
        self.changed(p, b, reject)

    def test_uart_missing_normal_close(self):
        p = self.root / RELEASE / 'flash_install/evidence/after_flash_refresh/ready/trace.jsonl'
        lines = p.read_text(encoding='utf-8-sig').splitlines()
        def reject():
            with self.assertRaisesRegex(ValueError, 'normal close'):
                replay_uart(self.root)
        self.changed(p, ('\n'.join(lines[:-1])+'\n').encode(), reject)

    def test_workflow_bootstrap_and_current_gate(self):
        document = yaml.load((ROOT/'.github/workflows/base-qualification.yml').read_text(), Loader=yaml.BaseLoader)
        self.assertIn('on', document)
        self.assertEqual(document['permissions']['contents'], 'read')
        job = document['jobs']['audit']; steps = job['steps']
        checkout = next(i for i, step in enumerate(steps) if step.get('uses', '').startswith('actions/checkout@'))
        self.assertTrue(any('core.longpaths true' in step.get('run', '') for step in steps[:checkout]))
        self.assertEqual(job['env']['GIT_CONFIG_VALUE_0'], 'true')
        self.assertEqual(steps[checkout]['with']['fetch-depth'], '0')
        self.assertIn('BASE_26102301_6a957b0', steps[checkout]['with']['sparse-checkout'])
        commands = '\n'.join(step.get('run', '') for step in steps)
        self.assertIn('test_base_delivery.py', commands)
        self.assertIn('test_current_base_ci.py', commands)
        self.assertIn('verify_current_base_ci.py', commands)
        self.assertNotIn('verify_base_delivery.py --run-dir', commands)
        self.assertFalse(any(step.get('continue-on-error') == 'true' for step in steps))

    def test_detached_references_import_into_an_empty_store(self):
        out = self.root.parent/'reference-import'
        out.mkdir()
        env = frozen_reference_environment(ROOT, out)
        self.assertIn('GIT_ALTERNATE_OBJECT_DIRECTORIES', env)
        self.assertEqual(subprocess.check_output(['git', '-C', str(out/'audit-objects'), 'cat-file', '-t', '5ece9156a28f44514b564472f4d821e72f09b77a']).strip(), b'commit')

if __name__ == '__main__':
    unittest.main()
