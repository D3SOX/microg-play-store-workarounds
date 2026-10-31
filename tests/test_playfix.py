import os
from pathlib import Path
import subprocess
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / 'modules/play-provenance-repair/playfix.sh'


class LargePackageDumpTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(dir=os.environ.get('TMPDIR'))
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        # Android may resolve printf as an external command. Bash with the
        # builtin disabled reproduces its per-argument exec limit on Linux.
        (self.root / 'bashenv').write_text('enable -n printf\n')
        self.env = dict(os.environ, BASH_ENV=str(self.root / 'bashenv'),
                        PATH=f'{self.root}:{os.environ["PATH"]}')
        self.mock('pm', 'echo package:/data/app/base.apk')
        self.mock('dumpsys', f'cat "{self.root / "dump"}"')
        self.mock('cmd', 'echo "package:com.android.vending uid:10144"')
        self.mock('su', 'echo Success')
        self.mock('am', 'exit 0')
        (self.root / 'dump').write_text(
            'x' * (256 * 1024) + '\n'
            '    versionName=1.2.3\n'
            '    versionCode=123 minSdk=28\n'
            '    installerPackageName=com.android.vending\n'
            '    installerPackageUid=10144\n'
            '    initiatingPackageName=com.android.vending\n'
            '    originatingPackageName=null\n'
            '    packageSource=2\n'
            '    com.pairip.licensecheck.LicenseActivity\n')

    def mock(self, name, body):
        path = self.root / name
        path.write_text('#!/bin/sh\n' + body + '\n')
        path.chmod(0o755)

    def run_tool(self, action):
        return subprocess.run(['bash', str(SCRIPT), action, 'com.anthropic.claude'],
                              env=self.env, capture_output=True, text=True)

    def test_inspect_large_dump(self):
        result = self.run_tool('inspect')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stderr, '')
        for line in ('versionName=1.2.3', 'versionCode=123',
                     'installerPackageName=com.android.vending',
                     'installerPackageUid=10144',
                     'initiatingPackageName=com.android.vending',
                     'originatingPackageName=null', 'packageSource=2',
                     'pairipDetected=true'):
            self.assertIn(line + '\n', result.stdout)

    def test_repair_recognizes_existing_play_provenance(self):
        result = self.run_tool('repair')
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        self.assertEqual(result.stderr, '')
        self.assertIn('No in-place reinstall is needed.', result.stdout)
        self.assertNotIn('[2/4]', result.stdout)

    def test_clear_efuse_reads_large_dump_before_guard(self):
        result = self.run_tool('clear-efuse')
        self.assertEqual(result.returncode, 1)
        self.assertIn('No eFuse preference was found', result.stderr)
        self.assertNotIn('Argument list too long', result.stderr)


class RepairFlowTests(LargePackageDumpTests):
    def setUp(self):
        super().setUp()
        # Redirect device-only paths into a sandbox; keep the actual repair flow.
        self.script = self.root / 'playfix.sh'
        self.script.write_text(SCRIPT.read_text().replace('/data/app', str(self.root / 'app'))
                               .replace('/data/user/', str(self.root / 'user') + '/')
                               .replace('/data/adb/', str(self.root / 'adb') + '/'))
        with (self.root / 'bashenv').open('a') as f:
            f.write('sleep() { :; }\n')
        self.stage = self.root / 'app/vmdl42.tmp'
        self.stage.mkdir(parents=True)
        apkdir = self.root / 'installed'
        apkdir.mkdir()
        for name in ('base.apk', 'split_config.arm64_v8a.apk', 'split_config.xhdpi.apk'):
            (apkdir / name).write_text(name)
        self.mock('pm', '\n'.join(f'echo package:{p}' for p in apkdir.iterdir()))
        self.mock('chown', 'exit 0')
        self.mock('restorecon', 'exit 0')
        self.mock('su', f'''echo "$*" >> "{self.root / 'su.log'}"
case "$*" in
 *install-create*) echo 'Success: created install session [42]' ;;
 *install-commit*) cat "{self.root / 'after'}" > "{self.root / 'dump'}"; cat "{self.root / 'commit'}" ;;
 *) echo Success ;;
esac''')
        self.good_dump = (self.root / 'dump').read_text()
        (self.root / 'after').write_text(self.good_dump)
        (self.root / 'commit').write_text('Success\n')

    def run_tool(self, action):
        return subprocess.run(['bash', str(self.script), action, 'com.anthropic.claude'],
                              env=self.env, capture_output=True, text=True)

    def needs_reinstall(self):
        (self.root / 'dump').write_text(self.good_dump.replace(
            'initiatingPackageName=com.android.vending', 'initiatingPackageName=null'))

    def test_split_apks_and_successful_verification(self):
        self.needs_reinstall()
        result = self.run_tool('repair')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('reinstallCompleted=true', result.stdout)
        self.assertEqual(len(list(self.stage.glob('*.apk'))), 3)
        for apk in self.stage.glob('*.apk'):
            self.assertEqual(apk.read_text(), apk.name)
        self.assertNotIn('install-abandon', (self.root / 'su.log').read_text())

    def test_failed_commit_abandons_session(self):
        self.needs_reinstall()
        (self.root / 'commit').write_text('Failure [INSTALL_FAILED_INVALID_APK]\n')
        result = self.run_tool('repair')
        self.assertEqual(result.returncode, 1)
        self.assertIn('Install commit failed', result.stderr)
        self.assertIn('install-abandon', (self.root / 'su.log').read_text())
        self.assertNotIn('reinstallCompleted=true', result.stdout)

    def test_unreadable_metadata_after_commit(self):
        self.needs_reinstall()
        (self.root / 'after').write_text('Package service unavailable\n')
        result = self.run_tool('repair')
        self.assertEqual(result.returncode, 3, result.stdout + result.stderr)
        self.assertIn('Reinstall succeeded;', result.stdout)
        self.assertNotIn('install-abandon', (self.root / 'su.log').read_text())

    def test_known_non_play_provenance_after_commit(self):
        self.needs_reinstall()
        (self.root / 'after').write_text((self.root / 'dump').read_text())
        result = self.run_tool('repair')
        self.assertEqual(result.returncode, 2)
        self.assertIn('still not fully Google Play', result.stdout)

    def test_missing_metadata_fails_inspection_and_prevents_reinstall(self):
        (self.root / 'dump').write_text('No package metadata\n')
        for action in ('inspect', 'repair'):
            result = self.run_tool(action)
            self.assertEqual(result.returncode, 1)
            self.assertIn('metadata is unreadable', result.stderr)
            self.assertNotIn('[2/4]', result.stdout)

    def test_stale_warning_requires_play_and_pairip_and_true(self):
        prefs = self.root / 'user/0/com.anthropic.claude/shared_prefs'
        prefs.mkdir(parents=True)
        pref = prefs / 'license.xml'
        for play, pairip, state, error in (
            (False, True, 'true', 'both Google Play'),
            (True, False, 'true', 'not detected'),
            (True, True, 'false', 'not currently true'),
        ):
            dump = self.good_dump
            if not play:
                dump = dump.replace('initiatingPackageName=com.android.vending', 'initiatingPackageName=null')
            if not pairip:
                dump = dump.replace('com.pairip.licensecheck.LicenseActivity', '')
            (self.root / 'dump').write_text(dump)
            original = f'<boolean name="eFuse" value="{state}" />\n'
            pref.write_text(original)
            result = self.run_tool('clear-efuse')
            self.assertEqual(result.returncode, 1)
            self.assertIn(error, result.stderr)
            self.assertEqual(pref.read_text(), original)
        (self.root / 'dump').write_text(self.good_dump)
        pref.write_text('<boolean name="eFuse" value="true" />\n')
        result = self.run_tool('clear-efuse')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('value="false"', pref.read_text())
        backups = list((self.root / 'adb/play_provenance_repair/backups').iterdir())
        self.assertEqual(len(backups), 1)
        self.assertIn('value="true"', backups[0].read_text())
        self.assertEqual(list(prefs.glob('.playfix*')), [])

    def efuse_pref(self, content):
        prefs = self.root / 'user/0/com.anthropic.claude/shared_prefs'
        prefs.mkdir(parents=True)
        pref = prefs / 'license.xml'
        pref.write_text(content)
        return prefs, pref

    def test_clear_efuse_does_not_write_through_planted_symlinks(self):
        prefs, pref = self.efuse_pref('<boolean name="eFuse" value="true" />\n')
        victim = self.root / 'victim'
        victim.write_text('untouched\n')
        for name in ('license.xml.playfix.tmp', 'license.xml.playfix.bak', '.playfix.tmp'):
            (prefs / name).symlink_to(victim)
        result = self.run_tool('clear-efuse')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(victim.read_text(), 'untouched\n')
        self.assertIn('value="false"', pref.read_text())
        self.assertFalse(pref.is_symlink())

    def test_symlinked_preference_is_ignored(self):
        prefs, pref = self.efuse_pref('<boolean name="eFuse" value="true" />\n')
        victim = self.root / 'victim.xml'
        pref.rename(victim)
        pref.symlink_to(victim)
        result = self.run_tool('clear-efuse')
        self.assertEqual(result.returncode, 1)
        self.assertIn('No eFuse preference was found', result.stderr)
        self.assertIn('value="true"', victim.read_text())

    def test_clear_efuse_only_changes_the_efuse_element(self):
        _, pref = self.efuse_pref('<map><boolean name="other" value="true" />'
                                  '<boolean name="eFuse" value="false" /></map>\n')
        result = self.run_tool('inspect')
        self.assertIn('eFuseState=false\n', result.stdout)
        self.mock('am', f'echo "$*" >> "{self.root / 'am.log'}"')
        result = self.run_tool('clear-efuse')
        self.assertEqual(result.returncode, 1)
        self.assertIn('not currently true', result.stderr)
        self.assertFalse((self.root / 'am.log').exists())

        pref.write_text('<map><boolean name="other" value="true" />'
                        '<boolean name="eFuse" value="true" /></map>\n')
        result = self.run_tool('clear-efuse')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(pref.read_text(), '<map><boolean name="other" value="true" />'
                                           '<boolean name="eFuse" value="false" /></map>\n')


if __name__ == '__main__':
    unittest.main()
