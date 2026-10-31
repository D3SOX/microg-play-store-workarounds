import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
import zipfile

ROOT = Path(__file__).resolve().parents[1]


class ReleaseTests(unittest.TestCase):
    def test_archive_names_follow_metadata_and_only_zips_are_emitted(self):
        with tempfile.TemporaryDirectory(dir=os.environ.get('TMPDIR')) as work:
            root = Path(work)
            shutil.copytree(ROOT / 'modules', root / 'modules')
            shutil.copytree(ROOT / 'scripts', root / 'scripts')
            prop = root / 'modules/play-provenance-repair/module.prop'
            lines = prop.read_text().splitlines()
            prop.write_text('\n'.join('version=v9.8.7' if line.startswith('version=') else line
                                      for line in lines) + '\n')
            result = subprocess.run(['bash', str(root / 'scripts/build-release.sh')],
                                    capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            files = sorted(p.name for p in (root / 'dist').iterdir())
            self.assertEqual(files, ['play_provenance_repair-v9.8.7.zip',
                                    'playstore_base_module_source.zip',
                                    'playstore_xray_privacy_filter-v1.3-arm64.zip'])
            for name in files:
                with zipfile.ZipFile(root / 'dist' / name) as archive:
                    self.assertIsNone(archive.testzip())
                    if name.startswith('play_provenance_repair'):
                        self.assertIn('version=v9.8.7', archive.read('module.prop').decode())
                        self.assertIn('webroot/index.html', archive.namelist())
