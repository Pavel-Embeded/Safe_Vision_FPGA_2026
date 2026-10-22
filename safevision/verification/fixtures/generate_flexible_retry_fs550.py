from pathlib import Path
import argparse,importlib.util
def generate(out):
 path=Path(__file__).with_name('generate_flexible_fs550.py')
 spec=importlib.util.spec_from_file_location('independent_flexible_fixture',path)
 module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
 module.generate(out,bad_primary=True)
if __name__=='__main__':
 ap=argparse.ArgumentParser();ap.add_argument('--output',required=True);generate(ap.parse_args().output)
