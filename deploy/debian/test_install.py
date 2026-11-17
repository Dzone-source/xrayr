"""Check installer sequencing without running APT or touching system paths."""
import pathlib
import subprocess
import tempfile
import unittest

SCRIPT = pathlib.Path(__file__).with_name('install.sh').resolve()


class InstallTests(unittest.TestCase):
    def run_installer(self, preflight_status=0, kernel_status=0):
        with tempfile.TemporaryDirectory() as temp:
            log = pathlib.Path(temp) / 'actions'
            result = subprocess.run(
                ['bash', '-c', '''
source "$1"
preflight() { echo preflight >> "$log"; return "$preflight_status"; }
bash() {
  [[ $1 == "$script_dir/network.sh" && $2 == kernel ]] || exit 98
  echo kernel >> "$log"
  return "$kernel_status"
}
install() { echo install >> "$log"; }
systemctl() { [[ $1 == daemon-reload ]] || exit 99; echo reload >> "$log"; }
log=$2; preflight_status=$3; kernel_status=$4
main fake-binary fake-config
''', 'test', str(SCRIPT), str(log), str(preflight_status), str(kernel_status)],
                capture_output=True, text=True,
            )
            return result, log.read_text().splitlines()

    def test_existing_installation_or_preflight_failure_stops_before_kernel(self):
        result, actions = self.run_installer(preflight_status=1)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(actions, ['preflight'])

    def test_kernel_failure_stops_before_xrayr_writes(self):
        result, actions = self.run_installer(kernel_status=1)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(actions, ['preflight', 'kernel'])

    def test_kernel_precedes_xrayr_install_without_reboot(self):
        result, actions = self.run_installer()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(actions, ['preflight', 'kernel'] + ['install'] * 4 + ['reload'])
        self.assertIn('manual reboot', result.stdout)


if __name__ == '__main__':
    unittest.main()
