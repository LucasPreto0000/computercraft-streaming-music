import importlib.util
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import subprocess
import tempfile
import threading
import unittest

spec = importlib.util.spec_from_file_location("music_backend", Path(__file__).resolve().parents[1] / "backend/server.py")
backend = importlib.util.module_from_spec(spec)
spec.loader.exec_module(backend)


class BackendTests(unittest.TestCase):
    def test_reject_unconfigured_site(self):
        with self.assertRaises(ValueError):
            backend.validate_url("https://not-configured.example/video")

    def test_reject_private_network(self):
        backend.HOSTS.add("127.0.0.1")
        try:
            with self.assertRaises(ValueError):
                backend.validate_url("http://127.0.0.1/video")
        finally:
            backend.HOSTS.discard("127.0.0.1")

    def test_real_conversion_of_local_fixture(self):
        class QuietHandler(SimpleHTTPRequestHandler):
            def log_message(self, *_):
                pass

        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            fixture = root / "tone.wav"
            subprocess.run(["ffmpeg", "-nostdin", "-loglevel", "error", "-f", "lavfi",
                            "-i", "sine=frequency=440:duration=1", str(fixture)], check=True)
            server = ThreadingHTTPServer(("127.0.0.1", 0), partial(QuietHandler, directory=temp))
            thread = threading.Thread(target=server.serve_forever, daemon=True)
            thread.start()
            try:
                dest = root / "converted"
                dest.mkdir()
                # Exercise the converter directly; the public HTTP handler correctly
                # refuses local destinations and is separately covered above.
                output = backend.convert("http://127.0.0.1:%d/tone.wav" % server.server_port, dest)
                self.assertEqual(output.stat().st_size, 6000)  # 48,000 one-bit samples.
            finally:
                server.shutdown()
                server.server_close()
                thread.join()


if __name__ == "__main__":
    unittest.main()
