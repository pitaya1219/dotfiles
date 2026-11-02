#!/usr/bin/env python3
"""Regression tests for the Nextcloud upload, against a local WebDAV stub.

    python3 tools/mtg-minutes/tests/test_nextcloud.py
"""
import base64
import sys
import tempfile
import threading
import unittest
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "lib"))
import nextcloud  # noqa: E402


class Stub(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def _reply(self, code, body=b""):
        self.send_response(code)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _handle(self):
        s = self.server
        body = self.rfile.read(int(self.headers.get("Content-Length") or 0))
        s.requests.append((self.command, self.path, dict(self.headers), body))
        if self.command == "PUT" and s.fail_put:
            return self._reply(500)
        if self.command == "MKCOL" and self.path.endswith("/logseq-assets"):
            return self._reply(405)
        if self.command == "PROPFIND":
            size = s.reported_size if s.reported_size is not None else sum(
                len(r[3]) for r in s.requests if r[0] == "PUT"
            )
            return self._reply(
                207,
                f'<d:multistatus xmlns:d="DAV:" xmlns:oc="http://owncloud.org/ns"><d:response>'
                f"<d:propstat><d:prop><d:getcontentlength>{size}</d:getcontentlength>"
                f"<oc:fileid>42</oc:fileid></d:prop></d:propstat></d:response></d:multistatus>".encode(),
            )
        return self._reply(201)

    do_MKCOL = do_PUT = do_MOVE = do_PROPFIND = _handle


class UploadTest(unittest.TestCase):
    def setUp(self):
        self.server = HTTPServer(("127.0.0.1", 0), Stub)
        self.server.requests = []
        self.server.fail_put = False
        self.server.reported_size = None
        threading.Thread(target=self.server.serve_forever, daemon=True).start()
        self.addCleanup(self.server.server_close)
        self.addCleanup(self.server.shutdown)
        self.url = f"http://127.0.0.1:{self.server.server_port}/"
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.path = Path(tmp.name) / "a.m4a"

    def upload(self):
        return nextcloud.upload(self.path, "mtg 1.m4a", self.url, "ryu", "secret")

    def test_splits_into_chunks_and_returns_the_file_link(self):
        original = nextcloud.CHUNK_BYTES
        nextcloud.CHUNK_BYTES = 4
        self.addCleanup(setattr, nextcloud, "CHUNK_BYTES", original)
        self.path.write_bytes(b"0123456789")

        self.assertEqual(self.upload(), self.url.rstrip("/") + "/f/42")

        requests = self.server.requests
        puts = [r for r in requests if r[0] == "PUT"]
        self.assertEqual([r[3] for r in puts], [b"0123", b"4567", b"89"])
        self.assertEqual([r[1].rsplit("/", 1)[1] for r in puts], ["00001", "00002", "00003"])
        move = next(r for r in requests if r[0] == "MOVE")
        self.assertTrue(move[1].endswith("/.file"))
        self.assertTrue(
            move[2]["Destination"].endswith("/dav/files/ryu/logseq-assets/mtg%201.m4a")
        )
        self.assertEqual(move[2]["Oc-Total-Length"], "10")
        self.assertEqual(move[2]["User-Agent"], nextcloud.USER_AGENT)
        self.assertEqual(
            move[2]["Authorization"], "Basic " + base64.b64encode(b"ryu:secret").decode()
        )

    def test_http_failure_raises_upload_error(self):
        self.path.write_bytes(b"data")
        self.server.fail_put = True
        with self.assertRaises(nextcloud.UploadError):
            self.upload()

    def test_size_mismatch_raises_upload_error(self):
        self.path.write_bytes(b"data")
        self.server.reported_size = 1
        with self.assertRaises(nextcloud.UploadError):
            self.upload()


if __name__ == "__main__":
    unittest.main()
