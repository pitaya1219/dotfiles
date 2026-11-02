#!/usr/bin/env python3
"""Upload a file to Nextcloud over WebDAV and return its link."""
import base64
import itertools
import urllib.error
import urllib.parse
import urllib.request
import uuid
import xml.etree.ElementTree as ET

FOLDER = "logseq-assets"
# The proxy in front of Nextcloud answers 413 to request bodies somewhere between
# 92 and 110 MiB, and meetings exceed that, so every upload goes in chunks.
CHUNK_BYTES = 50 * 2**20
TIMEOUT_SECONDS = 600
# Cloudflare rejects Python's default User-Agent.
USER_AGENT = "curl/8.5.0"
_NS = {"d": "DAV:", "oc": "http://owncloud.org/ns"}
_PROPFIND = (
    b'<?xml version="1.0"?><d:propfind xmlns:d="DAV:" xmlns:oc="http://owncloud.org/ns">'
    b"<d:prop><d:getcontentlength/><oc:fileid/></d:prop></d:propfind>"
)


class UploadError(RuntimeError):
    pass


def upload(path, name, url, user, password):
    """Upload path as FOLDER/name, check its size, and return the /f/<id> link."""
    url = url.rstrip("/")
    auth = "Basic " + base64.b64encode(f"{user}:{password}".encode()).decode()

    def dav(method, target, data=None, headers=None):
        req = urllib.request.Request(target, data=data, method=method, headers=headers or {})
        req.add_header("Authorization", auth)
        req.add_header("User-Agent", USER_AGENT)
        with urllib.request.urlopen(req, timeout=TIMEOUT_SECONDS) as r:
            return r.read()

    quoted_user = urllib.parse.quote(user)
    folder = f"{url}/remote.php/dav/files/{quoted_user}/{FOLDER}"
    target = f"{folder}/{urllib.parse.quote(name)}"
    chunks = f"{url}/remote.php/dav/uploads/{quoted_user}/{uuid.uuid4().hex}"
    size = path.stat().st_size
    try:
        try:
            dav("MKCOL", folder)
        except urllib.error.HTTPError as e:
            if e.code != 405:  # 405: the folder already exists
                raise
        dav("MKCOL", chunks)
        with open(path, "rb") as f:
            for number in itertools.count(1):
                chunk = f.read(CHUNK_BYTES)
                if not chunk:
                    break
                dav("PUT", f"{chunks}/{number:05d}", data=chunk)
        dav(
            "MOVE",
            f"{chunks}/.file",
            headers={"Destination": target, "OC-Total-Length": str(size)},
        )
        props = ET.fromstring(
            dav(
                "PROPFIND",
                target,
                data=_PROPFIND,
                headers={"Depth": "0", "Content-Type": "application/xml"},
            )
        )
    except (OSError, ET.ParseError) as e:
        raise UploadError(str(e)) from e
    remote_size = props.findtext(".//d:getcontentlength", namespaces=_NS)
    file_id = props.findtext(".//oc:fileid", namespaces=_NS)
    if remote_size != str(size) or not file_id:
        raise UploadError(f"size after upload is {remote_size}, expected {size}")
    return f"{url}/f/{file_id}"
