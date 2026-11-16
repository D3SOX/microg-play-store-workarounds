import os
from pathlib import Path
import subprocess
import tempfile
import unittest

SRC = Path(__file__).resolve().parents[1] / 'modules/playstore-base/module-src'
SCRIPT = SRC / 'post-fs-data.sh'


class PostFsDataTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(dir=os.environ.get('TMPDIR'))
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.bin = self.root / 'bin'
        self.bin.mkdir()
        moddir = self.root / 'module'
        self.apk = moddir / 'system/product/priv-app/FakeStore/FakeStore.apk'
        self.apk.parent.mkdir(parents=True)
        self.apk.write_text('apk')
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

    def test_phonesky_layout_skips_mounts_and_cache(self):
        # customize.sh moves the APK here on ROMs without FakeStore.
        phonesky = self.apk.parent.parent / 'Phonesky/Phonesky.apk'
        phonesky.parent.mkdir()
        self.apk.rename(phonesky)
        self.apk.parent.rmdir()
        for _ in range(2):
            self.assertEqual(self.boot(0).returncode, 0)
        self.assertEqual(self.mounted_targets(), [])
        self.assertTrue((self.cache / 'entry').exists())
        self.assertFalse(self.state.exists())


class CustomizeTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(dir=os.environ.get('TMPDIR'))
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.modpath = self.root / 'module'
        self.apps = self.modpath / 'system/product/priv-app'
        (self.apps / 'FakeStore').mkdir(parents=True)
        (self.apps / 'FakeStore/FakeStore.apk').write_text('apk')
        self.gms_perms = self.modpath / 'system/product/etc/permissions/privapp-permissions-playstore-base-gmscore.xml'
        self.gms_perms.parent.mkdir(parents=True)
        self.gms_perms.write_text('<permissions/>')
        self.rom = self.root / 'rom'
        self.rom.mkdir()
        script = (SRC / 'customize.sh').read_text()
        script = script.replace('/product/priv-app/FakeStore/FakeStore.apk', str(self.rom / 'FakeStore.apk'))
        for part in ('system', 'product', 'system_ext'):
            script = script.replace(f'/{part}/priv-app/GmsCore', str(self.rom / f'{part}-GmsCore'))
        self.script = self.root / 'customize.sh'
        self.script.write_text(script)

    def install(self):
        wrapper = ('ui_print() { echo "$1"; }\n'
                   'abort() { echo "$1"; exit 1; }\n'
                   f'MODPATH="{self.modpath}"\n'
                   f'. "{self.script}"\n')
        return subprocess.run(['sh', '-c', wrapper], capture_output=True, text=True)

    def layout(self):
        return sorted(str(p.relative_to(self.apps)) for p in self.apps.rglob('*'))

    def test_fakestore_rom_keeps_fakestore_path(self):
        (self.rom / 'FakeStore.apk').write_text('fakestore')
        self.assertEqual(self.install().returncode, 0)
        self.assertEqual(self.layout(), ['FakeStore', 'FakeStore/FakeStore.apk'])

    def test_rom_without_fakestore_uses_phonesky_path(self):
        self.assertEqual(self.install().returncode, 0)
        self.assertEqual(self.layout(), ['Phonesky', 'Phonesky/Phonesky.apk'])
        self.assertEqual((self.apps / 'Phonesky/Phonesky.apk').read_text(), 'apk')

    def test_without_gmscore_apk_drops_gmscore_allowlist(self):
        self.assertEqual(self.install().returncode, 0)
        self.assertFalse(self.gms_perms.exists())

    def add_gmscore(self):
        apk = self.apps / 'PrebuiltGmsCore/PrebuiltGmsCore.apk'
        apk.parent.mkdir()
        apk.write_text('gms')

    def test_gmscore_is_added_when_the_rom_has_none(self):
        self.add_gmscore()
        self.assertEqual(self.install().returncode, 0)
        self.assertIn('PrebuiltGmsCore/PrebuiltGmsCore.apk', self.layout())
        self.assertTrue(self.gms_perms.exists())

    def test_gmscore_is_skipped_when_the_rom_ships_it(self):
        # A second system copy would collide with the ROM's microG.
        self.add_gmscore()
        (self.rom / 'product-GmsCore').mkdir()
        result = self.install()
        self.assertEqual(result.returncode, 0)
        self.assertNotIn('PrebuiltGmsCore', self.layout())
        self.assertFalse(self.gms_perms.exists())
        self.assertIn('Skipping the GmsCore APK', result.stdout)

    def test_missing_apk_aborts(self):
        (self.apps / 'FakeStore/FakeStore.apk').unlink()
        result = self.install()
        self.assertEqual(result.returncode, 1)
        self.assertIn('no Play Store APK', result.stdout)


if __name__ == '__main__':
    unittest.main()
