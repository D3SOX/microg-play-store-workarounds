import os
from pathlib import Path
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / 'modules/playstore-base/module-src/post-fs-data.sh'


class PostFsDataTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(dir=os.environ.get('TMPDIR'))
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.bin = self.root / 'bin'
        self.bin.mkdir()
        moddir = self.root / 'module'
        apk = moddir / 'system/product/priv-app/FakeStore/FakeStore.apk'
        apk.parent.mkdir(parents=True)
        apk.write_text('apk')
        self.perms = moddir / 'system/product/etc/permissions/privapp-permissions-com.android.vending.xml'
        self.perms.parent.mkdir(parents=True)
        self.perms.write_text('<permissions/>')
        self.mounts = self.root / 'mounts'
        self.state = self.root / 'initialized'
        self.mounted = self.root / 'mounted'
        self.cache = self.root / 'package_cache'
        self.cache.mkdir()
        (self.cache / 'entry').write_text('cached parse')
        script = SCRIPT.read_text()
        for old, new in (('/data/adb/playstore_base_initialized_v2', self.state),
                         ('/data/adb/playstore_base-postfs.log', self.root / 'log'),
                         ('/dev/playstore_base.mounted', self.mounted),
                         ('/data/system/package_cache', self.cache)):
            script = script.replace(old, str(new))
        self.script = moddir / 'post-fs-data.sh'
        self.script.write_text(script)
        for name in ('resetprop', 'chcon', 'sha256sum', 'ls'):
            self.mock(name, 'exit 0')
        self.env = dict(os.environ, PATH=f'{self.bin}:{os.environ["PATH"]}')

    def mock(self, name, body):
        path = self.bin / name
        path.write_text('#!/bin/sh\n' + body + '\n')
        path.chmod(0o755)

    def boot(self, mount_rc):
        self.mock('mount', f'echo "$4" >> {self.mounts}; exit {mount_rc}')
        return subprocess.run(['sh', str(self.script)], env=self.env, capture_output=True, text=True)

    def test_initialized_mount_keeps_cache(self):
        self.state.touch()
        self.assertEqual(self.boot(0).returncode, 0)
        self.assertTrue(self.mounted.exists())
        self.assertTrue((self.cache / 'entry').exists())

    def test_failed_mount_drops_cache_and_marker(self):
        self.state.touch()
        self.assertEqual(self.boot(1).returncode, 1)
        self.assertFalse(self.mounted.exists())
        self.assertFalse(self.state.exists())
        self.assertEqual(list(self.cache.iterdir()), [])

    def mounted_targets(self):
        return self.mounts.read_text().split() if self.mounts.exists() else []

    def test_mounts_allowlist_before_apk(self):
        self.assertEqual(self.boot(0).returncode, 0)
        self.assertEqual(self.mounted_targets(), [
            '/product/etc/permissions/privapp-permissions-com.android.vending.xml',
            '/product/priv-app/FakeStore/FakeStore.apk',
        ])

    def test_missing_allowlist_skips_apk(self):
        # Mounting the APK without its allowlist makes system_server crash on boot.
        self.perms.unlink()
        self.assertEqual(self.boot(0).returncode, 1)
        self.assertEqual(self.mounted_targets(), [])
        self.assertFalse(self.mounted.exists())


if __name__ == '__main__':
    unittest.main()
