import hashlib
import json
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0,str(Path(__file__).resolve().parents[2]/'tools'))
from check_verilog import language

class VerilogProfileTests(unittest.TestCase):
    def setUp(self):
        self.temporary=tempfile.TemporaryDirectory()
        self.root=Path(self.temporary.name)
        self.registry=self.root/'safevision/platform/anlogic_eg4s20_hx4s20c/ip/protected_sources.sha256.json'
        self.registry.parent.mkdir(parents=True)
        self.registry.write_text('[]',encoding='utf-8')
        self.source=self.root/'probe.v'

    def tearDown(self):self.temporary.cleanup()

    def test_verilog_source_and_diagnostic_strings(self):
        self.source.write_text('module probe; reg[7:0] value; initial begin value=8\'d1; $display("logic string ++ $fatal"); $finish; end endmodule',encoding='utf-8')
        self.assertTrue(language(self.root)['accepted'])

    def test_reject_language_extensions(self):
        for body in ('logic[7:0] value;', 'reg[7:0] value; initial value++;', "wire[7:0] value=8'(1);", '$fatal(1,"bad");'):
            with self.subTest(body=body):
                self.source.write_text('module probe; '+body+' endmodule',encoding='utf-8')
                with self.assertRaises(ValueError):language(self.root)

    def test_reject_other_hdl_extension(self):
        self.source.with_suffix('.sv').write_text('module probe; endmodule',encoding='utf-8')
        with self.assertRaises(ValueError):language(self.root)

    def test_protected_source_checksum(self):
        raw=b'`pragma protect begin_protected\nZGF0YQ==\n`pragma protect end_protected\n'
        self.source.write_bytes(raw)
        self.registry.write_text(json.dumps([{'path':'probe.v','sha256':hashlib.sha256(raw).hexdigest()}]),encoding='utf-8')
        self.assertEqual(language(self.root)['protected_vendor_files'],['probe.v'])
        self.source.write_bytes(raw+b'\n')
        with self.assertRaises(ValueError):language(self.root)

if __name__=='__main__':unittest.main()
