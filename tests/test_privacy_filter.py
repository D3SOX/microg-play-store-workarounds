import os
from pathlib import Path
import subprocess
import tempfile
import time
import unittest

MODULE = Path(__file__).resolve().parents[1] / 'modules/playstore-xray-privacy-filter'
UID = '10144'


class PrivacyFilterTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(dir=os.environ.get('TMPDIR'))
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.bin = self.root / 'bin'
        self.bin.mkdir()
        self.state = self.root / 'state'
        self.moddir = self.root / 'module'
        (self.moddir / 'bin').mkdir(parents=True)
        for name in ('service.sh', 'uninstall.sh'):
            script = (MODULE / name).read_text()
            for old, new in (('/data/adb/playstore_xray_privacy_filter', self.state),
                             ('/dev/playstore_xray_privacy_filter.xray.pid', self.root / 'xray.pid'),
                             ('/data/system/packages.list', self.root / 'packages.list')):
                script = script.replace(old, str(new))
            (self.moddir / name).write_text(script)
        (self.root / 'bashenv').write_text('sleep() { :; }\n')
        self.env = dict(os.environ, BASH_ENV=str(self.root / 'bashenv'),
                        PATH=f'{self.bin}:{os.environ["PATH"]}')
        self.mock(self.moddir / 'bin/xray', 'exit 0')
        for name in ('iptables', 'ip6tables'):
            self.mock(self.bin / name, f'''echo "{name} $*" >> "{self.root / 'rules'}"
case "$*" in *" -C "*|*" -D "*) exit 1 ;; esac
[ -f "{self.root / 'fail'}" ] && echo "$*" | grep -qf "{self.root / 'fail'}" && exit 1
exit 0''')
        self.mock(self.bin / 'ss', f'cat "{self.root / "listening"}" 2>/dev/null')
        self.mock(self.bin / 'cmd', f'''case "$*" in
 *list\\ packages*) cat "{self.root / 'pm_uid'}" 2>/dev/null ;;
 *query-services*) echo com.android.vending/com.google.android.finsky.downloadservice.DownloadService ;;
esac''')
        self.mock(self.bin / 'pm', f'echo "$*" >> "{self.root / "pm.log"}"')
        self.mock(self.bin / 'getprop', 'echo 1')
        self.mock(self.bin / 'dumpsys', 'echo false')
        (self.root / 'packages.list').write_text(f'com.android.vending {UID} 0 /data/user/0/x platform 3003 0 1\n')

    def mock(self, path, body):
        path.write_text('#!/bin/sh\n' + body + '\n')
        path.chmod(0o755)

    def run_script(self, name):
        return subprocess.run(['bash', str(self.moddir / name)], env=self.env,
                              capture_output=True, text=True)

    def rules(self):
        return (self.root / 'rules').read_text()

    def bootlog(self):
        return (self.state / 'boot.log').read_text()

    def test_blocks_play_store_even_if_xray_and_package_manager_never_come_up(self):
        result = self.run_script('service.sh')
        self.assertEqual(result.returncode, 0, result.stderr)
        rules = self.rules()
        for rule in (f'iptables -w -A playstore_xray -m owner --uid-owner {UID} -j REJECT',
                     f'ip6tables -w -A playstore_xray -m owner --uid-owner {UID} -j REJECT',
                     f'iptables -w -t nat -A playstore_xray -m owner --uid-owner {UID} -p tcp -j REDIRECT --to-ports 12345',
                     'iptables -w -t filter -I OUTPUT 1 -j playstore_xray',
                     'iptables -w -t nat -I OUTPUT 1 -j playstore_xray'):
            self.assertIn(rule + '\n', rules)
        self.assertIn('Play Store traffic stays blocked', self.bootlog())
        self.assertIn('rules installed', self.bootlog())

    def test_rules_precede_xray_start(self):
        self.mock(self.moddir / 'bin/xray', f'cp "{self.root / "rules"}" "{self.root / "rules_at_start"}"')
        (self.root / 'listening').write_text('LISTEN 0 4096 127.0.0.1:12345 0.0.0.0:*\n')
        self.run_script('service.sh')
        for _ in range(100):
            if (self.root / 'rules_at_start').exists():
                break
            time.sleep(0.05)
        self.assertIn('-j REJECT', (self.root / 'rules_at_start').read_text())

    def test_failed_rule_is_reported(self):
        (self.root / 'fail').write_text('REJECT\n')
        self.run_script('service.sh')
        self.assertIn('filtering is incomplete', self.bootlog())
        self.assertNotIn('rules installed', self.bootlog())

    def test_package_manager_uid_change_is_also_blocked(self):
        (self.root / 'pm_uid').write_text('package:com.android.vending uid:10200\n')
        self.run_script('service.sh')
        rules = self.rules()
        self.assertIn(f'--uid-owner {UID} -j REJECT', rules)
        self.assertIn('--uid-owner 10200 -j REJECT', rules)
        self.assertIn('UID=10200 from PackageManager', self.bootlog())

    def test_uninstall_keeps_marker_until_download_service_is_enabled(self):
        self.state.mkdir()
        (self.state / 'downloadservice_disabled_by_module').touch()
        self.mock(self.bin / 'pm', 'exit 1')
        self.run_script('uninstall.sh')
        time.sleep(0.5)
        self.assertTrue((self.state / 'downloadservice_disabled_by_module').exists())

        self.mock(self.bin / 'pm', f'echo "$*" >> "{self.root / "pm.log"}"')
        self.run_script('uninstall.sh')
        for _ in range(100):
            if not self.state.exists():
                break
            time.sleep(0.05)
        self.assertFalse(self.state.exists())
        self.assertIn('enable --user 0 com.android.vending/', (self.root / 'pm.log').read_text())


if __name__ == '__main__':
    unittest.main()
