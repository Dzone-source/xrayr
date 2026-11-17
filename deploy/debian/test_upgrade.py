"""Run real backup/binary swaps on temporary files, mock kernel and systemd only."""
import pathlib
import subprocess
import tempfile
import unittest

SCRIPT = pathlib.Path(__file__).with_name('oneclick.sh').resolve()


class UpgradeTests(unittest.TestCase):
    def run_upgrade(self, active=True, kernel_fail=False, restart_fail=False):
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            (root / 'config').mkdir()
            (root / 'config/config.yml').write_text('private config retained')
            (root / 'binary').write_text('old binary')
            (root / 'unit').write_text('original unit')
            (root / 'package').mkdir()
            (root / 'package/XrayR').write_text('new binary')
            result = subprocess.run(['bash', '-c', '''
source "$1"
root=$2; active=$3; kernel_fail=$4; restart_fail=$5
BACKUP_ROOT=$root/backups; CONFIG_ROOT=$root/config
upgrade_binary=$root/binary; upgrade_unit=$root/unit; upgrade_service=XrayR.service
systemctl() {
  echo "$*" >> "$root/actions"
  case $1 in
    cat) cat "$upgrade_unit" ;;
    is-active) [[ $active == 1 ]] ;;
    restart)
      if [[ $restart_fail == 1 && ! -e $root/failed-once ]]; then
        touch "$root/failed-once"; return 1
      fi ;;
    *) return 99 ;;
  esac
}
sleep() { :; }
run_kernel_update() { echo kernel >> "$root/actions"; [[ $kernel_fail == 0 ]]; }
upgrade_bundle "$root/package"
''', 'test', str(SCRIPT), str(root), str(int(active)), str(int(kernel_fail)), str(int(restart_fail))], capture_output=True, text=True)
            binary = (root / 'binary').read_text()
            config = (root / 'config/config.yml').read_text()
            backups = list((root / 'backups').glob('upgrade-*'))
            self.assertEqual(len(backups), 1)
            self.assertEqual((backups[0] / 'XrayR').read_text(), 'old binary')
            self.assertEqual((backups[0] / 'config/config.yml').read_text(), config)
            self.assertEqual((root / 'unit').read_text(), 'original unit')
            self.assertEqual(config, 'private config retained')
            return result, binary, (root / 'actions').read_text()

    def test_multiple_services_are_rejected_before_filesystem_changes(self):
        result = subprocess.run(['bash', '-c', '''
source "$1"
systemctl() {
  case $3 in
    LoadState) echo loaded ;;
    Id) echo "${@: -1}" ;;
  esac
}
discover_upgrade
''', 'test', str(SCRIPT)], capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Multiple XrayR services', result.stderr)

    def test_unknown_binary_is_rejected(self):
        result = subprocess.run(['bash', '-c', '''
source "$1"
systemctl() {
  case $3 in
    LoadState) echo loaded ;;
    Id) echo xrayr.service ;;
    ExecStart) echo '{ path=/opt/custom/proxy ; argv[]=/opt/custom/proxy ; }' ;;
  esac
}
discover_upgrade
''', 'test', str(SCRIPT)], capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Unsupported service binary path', result.stderr)

    def test_success_preserves_config_and_restarts_original_service(self):
        result, binary, actions = self.run_upgrade()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(binary, 'new binary')
        self.assertIn('restart XrayR.service', actions)
        self.assertNotIn('enable', actions)

    def test_kernel_failure_does_not_replace_or_restart(self):
        result, binary, actions = self.run_upgrade(kernel_fail=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(binary, 'old binary')
        self.assertNotIn('restart', actions)

    def test_restart_failure_restores_old_binary(self):
        result, binary, actions = self.run_upgrade(restart_fail=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(binary, 'old binary')
        self.assertEqual(actions.count('restart XrayR.service'), 2)

    def test_inactive_service_remains_inactive(self):
        result, binary, actions = self.run_upgrade(active=False)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(binary, 'new binary')
        self.assertNotIn('restart', actions)


if __name__ == '__main__':
    unittest.main()
