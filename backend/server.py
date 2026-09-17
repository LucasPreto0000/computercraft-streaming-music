"""Private media conversion service. Run behind HTTPS; never expose without auth."""
import hmac
import ipaddress
import os
from pathlib import Path
import socket
import subprocess
import sys
import tempfile
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlsplit

TOKEN = os.environ.get("MUSIC_TOKEN", "")
HOSTS = {h.strip().lower() for h in os.environ.get("MUSIC_ALLOWED_HOSTS", "").split(",") if h.strip()}
SLOTS = threading.BoundedSemaphore(2)


def validate_url(value):
    url = urlsplit(value)
    if url.scheme not in ("http", "https") or not url.hostname or url.username or url.password:
        raise ValueError("Use a public HTTP(S) video URL")
    if url.hostname.lower() not in HOSTS:
        raise ValueError("Site not enabled by the backend owner")
    for address in socket.getaddrinfo(url.hostname, url.port or 443):
        if not ipaddress.ip_address(address[4][0]).is_global:
            raise ValueError("Private network destinations are not permitted")
    return value


def convert(url, directory):
    subprocess.run([
        sys.executable, "-m", "yt_dlp", "--ignore-config", "--no-playlist",
        "--no-progress", "--socket-timeout", "20", "--retries", "1",
        "--max-filesize", "100M", "--match-filter", "duration <=? 1800",
        "-f", "bestaudio/best", "-o", str(directory / "source.%(ext)s"), "--", url,
    ], check=True, timeout=180, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    sources = [p for p in directory.glob("source.*") if p.suffix not in (".part", ".ytdl")]
    if len(sources) != 1:
        raise ValueError("No playable media was returned")
    output = directory / "audio.dfpwm"
    subprocess.run([
        "ffmpeg", "-nostdin", "-hide_banner", "-loglevel", "error",
        "-i", str(sources[0]), "-vn", "-t", "1800", "-ac", "1", "-ar", "48000",
        "-af", "aresample=48000:filter_size=64,alimiter=limit=0.97:level=false",
        "-f", "dfpwm", str(output),
    ], check=True, timeout=180, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return output


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass  # Do not log private/signed URLs or authorization headers.

    def do_GET(self):
        if not hmac.compare_digest(self.headers.get("Authorization", ""), "Bearer " + TOKEN):
            self.send_error(401, "Authentication required")
            return
        parsed = urlsplit(self.path)
        if parsed.path != "/audio":
            self.send_error(404)
            return
        try:
            url = validate_url(parse_qs(parsed.query).get("url", [""])[0])
        except (ValueError, OSError):
            self.send_error(400, "Invalid URL or site not enabled")
            return
        if not SLOTS.acquire(blocking=False):
            self.send_error(503, "Converter busy; retry shortly")
            return
        try:
            with tempfile.TemporaryDirectory(prefix="music-") as folder:
                output = convert(url, Path(folder))
                self.send_response(200)
                self.send_header("Content-Type", "application/octet-stream")
                self.send_header("Content-Length", str(output.stat().st_size))
                self.end_headers()
                with output.open("rb") as source:
                    while chunk := source.read(65536):
                        self.wfile.write(chunk)
        except (BrokenPipeError, ConnectionResetError):
            pass
        except (subprocess.SubprocessError, OSError, ValueError):
            self.send_error(502, "Cannot convert this video; unavailable, unsupported or restricted")
        finally:
            SLOTS.release()


if __name__ == "__main__":
    if len(TOKEN) < 24 or not HOSTS:
        raise SystemExit("Set MUSIC_TOKEN (24+ characters) and MUSIC_ALLOWED_HOSTS")
    ThreadingHTTPServer(("127.0.0.1", int(os.environ.get("PORT", "8080"))), Handler).serve_forever()
