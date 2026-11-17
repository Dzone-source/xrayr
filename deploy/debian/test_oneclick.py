"""Exercise download verification and startup without root/APT/systemd changes."""
import hashlib
import io
import pathlib
import subprocess
import tarfile
import tempfile
import unittest

SCRIPT = pathlib.Path(__file__).with_name('oneclick.sh').resolve()


class OneClickTests(unittest.TestCase):
    def run_bundle(self, corrupt_archive=False, corrupt_binary=False, kernel_failure=False):
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            archive = root / 'fixture.tar.gz'
            payload = b'prebuilt test binary'
            binary_hash = hashlib.sha256(b'wrong' if corrupt_binary else payload).hexdigest()
            with tarfile.open(archive, 'w:gz') as tar:
                for name, data in {'XrayR': payload, 'XrayR.sha256': f'{binary_hash}  XrayR\n'.encode(), 'install.sh': b'#!/bin/bash\n'}.items():
                    info = tarfile.TarInfo(name)
                    info.size = len(data)
                    tar.addfile(info, io.BytesIO(data))
            digest = hashlib.sha256(archive.read_bytes()).hexdigest()
            if corrupt_archive:
                digest = '0' * 64
            (root / 'fixture.sha256').write_text(f'{digest}  XrayR-debian-linux-amd64.tar.gz\n')
            work = root / 'work'
            work.mkdir()
            result = subprocess.run(['bash', '-c', '''
source "$1"
root=$2; work=$3; kernel_failure=$4
curl() {
  local url="${@: -3:1}" out="${@: -1}"
  if [[ $url == *.sha256 ]]; then cp "$root/fixture.sha256" "$out"; else cp "$root/fixture.tar.gz" "$out"; fi
}
bash() {
  [[ $1 == "$work/package/install.sh" ]] || exit 99
  echo install >> "$root/actions"
  [[ -f $3 ]] || exit 98
  return "$kernel_failure"
}
systemctl() { echo "$*" >> "$root/actions"; }
install_bundle "$work"
''', 'test', str(SCRIPT), str(root), str(work), str(int(kernel_failure))], capture_output=True, text=True)
            actions = (root / 'actions').read_text().splitlines() if (root / 'actions').exists() else []
            return result, actions

    def test_archive_checksum_failure_blocks_execution(self):
        result, actions = self.run_bundle(corrupt_archive=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(actions, [])

    def test_binary_checksum_failure_blocks_execution(self):
        result, actions = self.run_bundle(corrupt_binary=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(actions, [])

    def test_install_failure_blocks_service_start(self):
        result, actions = self.run_bundle(kernel_failure=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(actions, ['install'])

    def test_verified_bundle_installs_and_starts(self):
        result, actions = self.run_bundle()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(actions, ['install', 'enable --now xrayr', 'is-active --quiet xrayr'])
        self.assertIn('No panel node configured', result.stdout)


if __name__ == '__main__':
    unittest.main()
