import json
import tempfile
import unittest
from pathlib import Path
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from threading import Thread

from inspect_panel import DiagnosticError, fetch_node, read_settings, safe_schema


class DiagnosticTests(unittest.TestCase):
    def test_config(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / 'config.yml'
            path.write_text('Nodes:\n  - PanelType: SSpanel\n    ApiConfig:\n      ApiHost: "https://example.com"\n      ApiKey: "FAKE_TEST_KEY" # comment\n      NodeID: 2\n    ControllerConfig:\n      EnableREALITY: true\n')
            self.assertEqual(read_settings(path, 2)['ApiKey'], 'FAKE_TEST_KEY')
            with self.assertRaises(DiagnosticError):
                read_settings(path, 3)

    def test_redaction(self):
        node = {'ret': 1, 'data': {'server': 'sensitive-host', 'port': 443, 'version': '', 'key': 'FAKE_TEST_KEY', 'custom_config': json.dumps({'network': 'tcp', 'flow': 'xtls-rprx-vision', 'reality-opts': {'private_key': 'FAKE_PRIVATE_KEY', 'dest': 'sensitive-dest'}, 'path': '/sensitive-path'})}}
        report = json.dumps(safe_schema(node))
        for hidden in ('FAKE_TEST_KEY', 'FAKE_PRIVATE_KEY', 'sensitive-host', 'sensitive-dest', 'sensitive-path'):
            self.assertNotIn(hidden, report)
        for needed in ('443', 'tcp', 'xtls-rprx-vision', 'semicolon_fields'):
            self.assertIn(needed, report)

    def test_redirect_not_followed(self):
        seen = []
        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *args):
                pass
            def do_GET(self):
                seen.append(self.path.split('?')[0])
                self.send_response(302)
                self.send_header('Location', '/must-not-follow')
                self.end_headers()
        server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
        thread = Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            with self.assertRaisesRegex(DiagnosticError, '302'):
                fetch_node({'ApiHost': f'http://127.0.0.1:{server.server_port}', 'ApiKey': 'FAKE_TEST_KEY', 'NodeID': '2'})
            self.assertEqual(seen, ['/mod_mu/nodes/2/info'])
        finally:
            server.shutdown()
            server.server_close()
            thread.join()


if __name__ == '__main__':
    unittest.main()
