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
            xray = (root / 'modules/playstore-xray-privacy-filter/module.prop').read_text()
            xray_version = next(line.split('=', 1)[1] for line in xray.splitlines()
                                if line.startswith('version='))
            # Local build output must never reach release archives.
            (root / 'modules/playstore-base/playstore_base.zip').write_text('apk inside')
            (root / 'modules/playstore-base/module-src/system/product/priv-app/FakeStore/FakeStore.apk').write_text('apk')
            (root / 'modules/playstore-xray-privacy-filter/bin/xray').write_text('binary')
            result = subprocess.run(['bash', str(root / 'scripts/build-release.sh')],
                                    capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            files = sorted(p.name for p in (root / 'dist').iterdir())
            self.assertEqual(files, ['play_provenance_repair-v9.8.7.zip',
                                    'playstore_base_module_source.zip',
                                    f'playstore_xray_privacy_filter-v{xray_version}-arm64.zip'])
            for name in files:
                with zipfile.ZipFile(root / 'dist' / name) as archive:
                    self.assertIsNone(archive.testzip())
                    names = archive.namelist()
                    self.assertFalse([n for n in names if n.endswith(('.zip', '.apk', 'bin/xray'))], name)
                    if name.startswith('play_provenance_repair'):
                        self.assertIn('version=v9.8.7', archive.read('module.prop').decode())
                        self.assertIn('webroot/index.html', archive.namelist())
