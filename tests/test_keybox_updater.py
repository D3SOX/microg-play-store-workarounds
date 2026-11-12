import base64
import codecs
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time
import unittest

MODULE = Path(__file__).resolve().parents[1] / 'modules/omk-keybox-updater'
YURIKEY = 'https://raw.githubusercontent.com/Yurii0307/yurikey/main/key'
INTEGRITYBOX = 'https://github.com/MeowDump/Integrity-Box/releases/download/archive/Megatron'
STATUS = 'https://android.googleapis.com/attestation/status'
DAY = 86400


def openssl(*args, cwd):
    subprocess.run(['openssl', *args], cwd=cwd, check=True, capture_output=True)


class Certs:
    """A fake attestation root and EC leaf keys signed by it."""

    def __init__(self, root):
        self.dir = root / 'pki'
        self.dir.mkdir()
        self.n = 0
        # Over 25 years, so notAfter is a GeneralizedTime.
        openssl('req', '-x509', '-newkey', 'ec', '-pkeyopt', 'ec_paramgen_curve:P-256', '-nodes',
                '-keyout', 'root.key', '-out', 'root.pem', '-days', '10000', '-subj', '/CN=Test root',
                cwd=self.dir)
        der = subprocess.run(['openssl', 'x509', '-in', 'root.pem', '-outform', 'DER'], cwd=self.dir,
                             check=True, capture_output=True).stdout
        self.root_pem = (self.dir / 'root.pem').read_text()
        self.root_sha256 = __import__('hashlib').sha256(der).hexdigest()

    def leaf(self, days, serial):
        self.n += 1
        name = f'leaf{self.n}'
        openssl('req', '-newkey', 'ec', '-pkeyopt', 'ec_paramgen_curve:P-256', '-nodes',
                '-keyout', f'{name}.key', '-out', f'{name}.csr', '-subj', f'/CN={name}', cwd=self.dir)
        openssl('x509', '-req', '-in', f'{name}.csr', '-CA', 'root.pem', '-CAkey', 'root.key',
                '-set_serial', serial, '-days', str(days), '-out', f'{name}.pem', cwd=self.dir)
        return (self.dir / f'{name}.key').read_text(), (self.dir / f'{name}.pem').read_text()

    def key(self, days, serial='0x1001', count=None, private=True, root=None, algorithm='ecdsa'):
        key, leaf = self.leaf(days, serial)
        chain = [leaf, root or self.root_pem]
        certs = ''.join(f'<Certificate format="pem">\n{c}</Certificate>\n' for c in chain)
        private_key = f'<PrivateKey format="pem">\n{key}</PrivateKey>\n' if private else ''
        return (f'<Key algorithm="{algorithm}">\n' + private_key +
                f'<CertificateChain>\n<NumberOfCertificates>{count or len(chain)}</NumberOfCertificates>\n'
                + certs + '</CertificateChain>\n</Key>\n')

    def keybox(self, days, serial='0x1001', extra='', **options):
        return ('<?xml version="1.0"?>\n<AndroidAttestation>\n<NumberOfKeyboxes>1</NumberOfKeyboxes>\n'
                '<Keybox DeviceID="test">\n' + self.key(days, serial, **options) + extra +
                '</Keybox>\n</AndroidAttestation>\n')


def integritybox(xml):
    """Encodes a keybox like the Integrity-Box Megatron file."""
    data = codecs.encode(xml, 'rot13').encode().hex().encode()
    for _ in range(10):
        data = base64.encodebytes(data)
    return data


class KeyboxUpdaterTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory(dir=os.environ.get('TMPDIR'))
        cls.certs = Certs(Path(cls.temp.name))

    @classmethod
    def tearDownClass(cls):
        cls.temp.cleanup()

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(dir=os.environ.get('TMPDIR'))
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.bin = self.root / 'bin'
        self.bin.mkdir()
        self.omk = self.root / 'omk'
        (self.omk / 'logs').mkdir(parents=True)
        self.log = self.omk / 'logs/keymint.log'
        self.log.write_text('')
        self.keybox = self.omk / 'keybox.xml'
        self.omk_module = self.root / 'omk_module'
        self.omk_module.mkdir()
        self.backups = self.root / 'state/backups'
        self.web = self.root / 'web'
        self.web.mkdir()
        self.urls = {}
        self.replies = self.root / 'replies'

        moddir = self.root / 'module'
        moddir.mkdir()
        for name in ('certinfo.awk', 'keybox.awk'):
            (moddir / name).write_text((MODULE / name).read_text())
        script = (MODULE / 'update.sh').read_text()
        for old, new in (('/data/adb/modules/oh_my_keymint', self.omk_module),
                         ('/data/misc/keystore/omk', self.omk),
                         ('/data/adb/omk_keybox_updater/backups', self.backups),
                         ('WAIT_SECONDS=15', 'WAIT_SECONDS=3')):
            script = script.replace(old, str(new))
        script = __import__('re').sub(r'GOOGLE_ROOTS="[^"]*"', f'GOOGLE_ROOTS="{self.certs.root_sha256}"', script)
        self.script = moddir / 'update.sh'
        self.script.write_text(script)

        self.mock('id', 'echo 0')
        self.mock('chown', f'echo "$*" >> "{self.root / "chown.log"}"')
        self.mock('chcon', f'echo "$*" >> "{self.root / "chcon.log"}"')
        # Each sleep plays OhMyKeymint's next reaction to a keybox change.
        self.mock('sleep', f'''f="{self.replies}"
[ -s "$f" ] || exit 0
head -n 1 "$f" >> "{self.log}"
tail -n +2 "$f" > "$f.next"; mv "$f.next" "$f"''')
        self.mock('curl', f'''echo "$*" >> "{self.root / 'curl.log'}"
out=""; url=""
while [ "$#" -gt 0 ]; do
  case "$1" in -o) out=$2; shift ;; https://*) url=$1 ;; esac
  shift
done
file=$(awk -v u="$url" '$1 == u {{ print $2 }}' "{self.root / 'urls'}")
[ -n "$file" ] && [ -f "$file" ] || exit 22
cp "$file" "$out"''')
        self.serve(STATUS, json.dumps({'entries': {}}))

    def mock(self, name, body):
        path = self.bin / name
        path.write_text('#!/bin/sh\n' + body + '\n')
        path.chmod(0o755)

    def serve(self, url, content):
        path = self.web / str(len(self.urls))
        path.write_bytes(content if isinstance(content, bytes) else content.encode())
        self.urls[url] = path
        (self.root / 'urls').write_text(''.join(f'{u} {p}\n' for u, p in self.urls.items()))

    def revoke(self, *serials):
        self.serve(STATUS, json.dumps({'entries': {s: {'status': 'REVOKED'} for s in serials}}))

    def omk_replies(self, *replies):
        lines = {'ok': '[INFO] keymint::keybox - active keybox identity updated from keybox.xml (fallback=false)\n'
                       '[INFO] keymint::keymaster::db - found 3 stale keybox-bound keys to retire',
                 'reject': '[WARN] keymint::keybox - invalid keybox.xml at keybox.xml: bad key; rewriting bundled template'}
        self.replies.write_text(''.join(lines[r] + '\n' for r in replies))

    def run_update(self):
        env = dict(os.environ, PATH=f'{self.bin}:{os.environ["PATH"]}', TMPDIR=str(self.root))
        return subprocess.run(['sh', str(self.script)], env=env, capture_output=True, text=True)

    def test_certinfo_reads_serial_dates_and_state(self):
        _, leaf = self.certs.leaf(30, '0x00ff0001')
        der = subprocess.run(['openssl', 'x509', '-outform', 'DER'], input=leaf.encode(),
                             check=True, capture_output=True).stdout
        hexdump = subprocess.run(['od', '-An', '-v', '-tx1'], input=der, check=True, capture_output=True).stdout
        now = time.strftime('%Y%m%d%H%M%S', time.gmtime())
        out = subprocess.run(['awk', '-v', f'now={now}', '-f', str(MODULE / 'certinfo.awk')], input=hexdump,
                             check=True, capture_output=True).stdout.decode().split()
        self.assertEqual(out[:2], ['ff0001', str(0xff0001)])
        self.assertEqual(out[3][:8], time.strftime('%Y%m%d', time.gmtime(time.time() + 30 * DAY)))
        self.assertEqual(out[4], 'valid')
        root_der = subprocess.run(['openssl', 'x509', '-outform', 'DER'], input=self.certs.root_pem.encode(),
                                  check=True, capture_output=True).stdout
        hexdump = subprocess.run(['od', '-An', '-v', '-tx1'], input=root_der, check=True, capture_output=True).stdout
        out = subprocess.run(['awk', '-v', 'now=99991231000000', '-f', str(MODULE / 'certinfo.awk')],
                             input=hexdump, check=True, capture_output=True).stdout.decode().split()
        self.assertTrue(out[3].startswith('20'), out)  # GeneralizedTime
        self.assertEqual(out[4], 'expired')

    def test_installs_newer_keybox_with_backup(self):
        old = self.certs.keybox(10)
        self.keybox.write_text(old)
        self.keybox.chmod(0o640)
        new = self.certs.keybox(20, '0x2002')
        self.serve(YURIKEY, base64.b64encode(new.encode()))
        self.omk_replies('ok')
        result = self.run_update()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.keybox.read_text(), new)
        self.assertEqual(self.keybox.stat().st_mode & 0o777, 0o640)
        self.assertEqual([p.read_text() for p in self.backups.iterdir()], [old])
        self.assertIn('u:object_r:keystore_data_file:s0', (self.root / 'chcon.log').read_text())
        self.assertIn('deleted 3 app keys', result.stdout)
        self.assertEqual([p.name for p in self.omk.iterdir() if p.name.startswith('.')], [])

    def test_downloads_ignore_curl_config_and_proxies(self):
        self.run_update()
        for line in (self.root / 'curl.log').read_text().splitlines():
            self.assertTrue(line.startswith('-q '), line)
            self.assertIn("--noproxy *", line)

    def test_keeps_current_ec_keybox_and_its_mode(self):
        current = self.certs.keybox(20, algorithm='ec')
        self.keybox.write_text(current)
        self.serve(YURIKEY, base64.b64encode(self.certs.keybox(10, '0x2002').encode()))
        result = self.run_update()
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertIn('Nothing changed', result.stdout)
        self.assertEqual(self.keybox.read_text(), current)

    def test_keybox_expires_with_its_first_certificate(self):
        self.keybox.write_text(self.certs.keybox(10))
        # The EC chain lasts 20 days, but the RSA entry expires in 5.
        short = self.certs.key(5, '0x3003', algorithm='rsa')
        self.serve(YURIKEY, base64.b64encode(self.certs.keybox(20, '0x2002', extra=short).encode()))
        result = self.run_update()
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertIn('Nothing changed', result.stdout)

    def test_keeps_current_keybox_that_expires_no_earlier(self):
        current = self.certs.keybox(20)
        self.keybox.write_text(current)
        self.serve(YURIKEY, base64.b64encode(self.certs.keybox(10, '0x2002').encode()))
        result = self.run_update()
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertIn('Nothing changed', result.stdout)
        self.assertEqual(self.keybox.read_text(), current)
        self.assertFalse(self.backups.exists())

    def test_replaces_revoked_current_keybox(self):
        self.keybox.write_text(self.certs.keybox(30, '0xdead01'))
        new = self.certs.keybox(10, '0x2002')
        self.serve(YURIKEY, base64.b64encode(new.encode()))
        self.revoke('dead01')
        self.omk_replies('ok')
        result = self.run_update()
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertIn('is revoked', result.stdout)
        self.assertEqual(self.keybox.read_text(), new)

    def test_rejects_revoked_candidate_by_decimal_serial(self):
        current = self.certs.keybox(10)
        self.keybox.write_text(current)
        self.serve(YURIKEY, base64.b64encode(self.certs.keybox(20, '0x2002').encode()))
        self.revoke(str(0x2002))
        result = self.run_update()
        self.assertEqual(result.returncode, 1, result.stdout)
        self.assertIn('No source has a valid keybox', result.stdout)
        self.assertEqual(self.keybox.read_text(), current)

    def test_rejects_invalid_candidates(self):
        other = Certs(self.root)
        for xml, reason in ((self.certs.keybox(20, private=False), 'no private key'),
                            (self.certs.keybox(20, count=3), 'lists 3 certificates but has 2'),
                            (self.certs.keybox(20, root=other.root_pem), 'Google attestation root')):
            self.serve(YURIKEY, base64.b64encode(xml.encode()))
            result = self.run_update()
            self.assertEqual(result.returncode, 1, result.stdout)
            self.assertIn(reason, result.stdout)
            self.assertFalse(self.keybox.exists())

    def test_rejects_truncated_keybox(self):
        full = self.certs.keybox(20)
        truncated = full[:full.index('<PrivateKey')]
        self.serve(YURIKEY, base64.b64encode(truncated.encode()))
        result = self.run_update()
        self.assertEqual(result.returncode, 1, result.stdout)
        self.assertIn('incomplete', result.stdout)
        self.assertFalse(self.keybox.exists())

    def test_rejects_expired_candidate(self):
        self.serve(YURIKEY, base64.b64encode(self.certs.keybox(1).encode()))
        self.mock('date', f'''case "$*" in *%Y%m%d%H%M%S*) /usr/bin/date -u -d @{int(time.time()) + 2 * DAY} +%Y%m%d%H%M%S ;;
*) exec /usr/bin/date "$@" ;; esac''')
        result = self.run_update()
        self.assertEqual(result.returncode, 1, result.stdout)
        self.assertIn('expired on', result.stdout)

    def test_picks_the_source_that_expires_last(self):
        self.serve(YURIKEY, base64.b64encode(self.certs.keybox(10).encode()))
        later = self.certs.keybox(20, '0x2002')
        self.serve(INTEGRITYBOX, integritybox(later))
        self.omk_replies('ok')
        result = self.run_update()
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertIn('Installing the integritybox keybox', result.stdout)
        self.assertEqual(self.keybox.read_text(), later)

    def test_restores_previous_keybox_when_omk_rejects_new_one(self):
        old = self.certs.keybox(10)
        self.keybox.write_text(old)
        self.serve(YURIKEY, base64.b64encode(self.certs.keybox(20, '0x2002').encode()))
        self.omk_replies('reject', 'ok')
        result = self.run_update()
        self.assertEqual(result.returncode, 1, result.stdout)
        self.assertIn('Restored the previous keybox', result.stdout)
        self.assertEqual(self.keybox.read_text(), old)

    def test_changes_nothing_without_revocation_list(self):
        del self.urls[STATUS]
        (self.root / 'urls').write_text(''.join(f'{u} {p}\n' for u, p in self.urls.items()))
        result = self.run_update()
        self.assertEqual(result.returncode, 1, result.stdout)
        self.assertIn('Could not download the revocation list', result.stdout)

    def test_requires_enabled_ohmykeymint(self):
        (self.omk_module / 'disable').touch()
        result = self.run_update()
        self.assertEqual(result.returncode, 1, result.stdout)
        self.assertIn('not installed or not enabled', result.stdout)


if __name__ == '__main__':
    unittest.main()
