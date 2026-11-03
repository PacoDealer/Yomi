#!/usr/bin/env python3
"""Puts a build's release notes into TestFlight's "What to Test" field (App Store Connect API).

  testflight-notes.py N            wait for build N to show up in App Store Connect (up to 60 min), then set the text
  testflight-notes.py N --wait 0   don't wait: fail if the build isn't there yet
  testflight-notes.py N --dry-run  print the text that would be sent, touch nothing
  testflight-notes.py --check      read-only: confirm the API key works (lists the newest builds)

The key stays on this Mac, never in the repo: ~/.appstoreconnect/yomi.json holds {"key_id": "...", "issuer_id": "..."}
and the private key is ~/.appstoreconnect/private_keys/AuthKey_<key_id>.p8 (the file App Store Connect lets you
download once). Without that config the script says so and exits 0, so uploads work without a key.
Tokens are signed with the system `openssl` (ES256) and live 10 minutes.
"""
import base64
import importlib.util
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))  # iOS/
BUNDLE_ID = "pacodealer.Yomi"
LOCALE = "en-US"
API = "https://api.appstoreconnect.apple.com"
CONFIG = os.path.expanduser("~/.appstoreconnect/yomi.json")


def b64url(data):
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


def der_to_raw(der):
    """openssl writes ECDSA signatures as DER SEQUENCE{r, s}; JWT wants r || s, 32 bytes each."""
    assert der[0] == 0x30
    i = 2 if der[1] < 0x80 else 2 + (der[1] & 0x7F)
    out = b""
    for _ in range(2):
        assert der[i] == 0x02
        n = der[i + 1]
        out += der[i + 2:i + 2 + n].lstrip(b"\0").rjust(32, b"\0")
        i += 2 + n
    return out


def make_token(key_id, issuer_id, key_path, lifetime=600):
    header = b64url(json.dumps({"alg": "ES256", "kid": key_id, "typ": "JWT"}).encode())
    now = int(time.time())
    payload = b64url(json.dumps({"iss": issuer_id, "iat": now, "exp": now + lifetime,
                                 "aud": "appstoreconnect-v1"}).encode())
    signing_input = f"{header}.{payload}".encode()
    der = subprocess.run(["openssl", "dgst", "-sha256", "-sign", key_path], input=signing_input,
                         capture_output=True, check=True).stdout
    return f"{header}.{payload}.{b64url(der_to_raw(der))}"


class Client:
    def __init__(self, cfg):
        self.key_id, self.issuer = cfg["key_id"], cfg["issuer_id"]
        self.key_path = os.path.expanduser(cfg.get("key_path") or
                                           f"~/.appstoreconnect/private_keys/AuthKey_{self.key_id}.p8")
        if not os.path.exists(self.key_path):
            sys.exit(f"Private key not found: {self.key_path}")

    def call(self, method, path, query=None, body=None):
        url = API + path + ("?" + urllib.parse.urlencode(query) if query else "")
        req = urllib.request.Request(url, method=method, data=json.dumps(body).encode() if body else None)
        req.add_header("Authorization", "Bearer " + make_token(self.key_id, self.issuer, self.key_path))
        req.add_header("Content-Type", "application/json")
        try:
            with urllib.request.urlopen(req, timeout=60) as r:
                return json.loads(r.read() or b"{}")
        except urllib.error.HTTPError as e:
            detail = e.read().decode(errors="replace")[:600]
            sys.exit(f"{method} {path} → HTTP {e.code}: {detail}")

    def app_id(self):
        data = self.call("GET", "/v1/apps", {"filter[bundleId]": BUNDLE_ID, "fields[apps]": "bundleId"})["data"]
        if not data:
            sys.exit(f"No app with bundle id {BUNDLE_ID} visible to this key.")
        return data[0]["id"]

    def build(self, app, number):
        data = self.call("GET", "/v1/builds", {"filter[app]": app, "filter[version]": str(number), "limit": "1",
                                               "fields[builds]": "version,processingState"})["data"]
        return data[0] if data else None


def notes_text(build):
    spec = importlib.util.spec_from_file_location("whats_new", os.path.join(os.path.dirname(__file__), "whats-new.py"))
    wn = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(wn)
    path = os.path.join(ROOT, "release-notes", f"build-{build}.md")
    with open(path, encoding="utf-8") as f:
        sections = wn.parse_notes(f.read())
    text = "\n\n".join(h + "\n" + "\n".join("• " + i for i in items) for h, items in sections)
    if len(text) > 4000:  # App Store Connect's limit for What to Test
        text = text[:3990].rsplit("\n", 1)[0] + "\n…"
    return text


def main():
    args = sys.argv[1:]
    dry = "--dry-run" in args
    wait = 60
    if "--wait" in args:
        wait = int(args[args.index("--wait") + 1])
    if dry:
        n = next(a for a in args if a.isdigit())
        print(notes_text(int(n)))
        return
    if not os.path.exists(CONFIG):
        print(f"What to Test: skipped (no App Store Connect API key; see {CONFIG} in scripts/changelog/testflight-notes.py).")
        return
    with open(CONFIG) as f:
        client = Client(json.load(f))
    app = client.app_id()

    if "--check" in args:
        data = client.call("GET", "/v1/builds", {"filter[app]": app, "sort": "-uploadedDate", "limit": "3",
                                                 "fields[builds]": "version,processingState,uploadedDate"})["data"]
        print(f"API key works. App {BUNDLE_ID} = {app}. Newest builds:")
        for b in data:
            a = b["attributes"]
            print(f"  {a['version']}  {a['processingState']}  {a['uploadedDate']}")
        return

    number = int(next(a for a in args if a.isdigit()))
    text = notes_text(number)
    deadline = time.time() + wait * 60
    build = client.build(app, number)
    while build is None and time.time() < deadline:
        print(f"Build {number} not in App Store Connect yet; checking again in 60 s…", flush=True)
        time.sleep(60)
        build = client.build(app, number)
    if build is None:
        sys.exit(f"Build {number} did not show up within {wait} min. Rerun: scripts/changelog/testflight-notes.py {number}")

    locs = client.call("GET", f"/v1/builds/{build['id']}/betaBuildLocalizations")["data"]
    existing = next((l for l in locs if l["attributes"]["locale"] == LOCALE), None)
    if existing:
        client.call("PATCH", f"/v1/betaBuildLocalizations/{existing['id']}",
                    body={"data": {"type": "betaBuildLocalizations", "id": existing["id"],
                                   "attributes": {"whatsNew": text}}})
    else:
        client.call("POST", "/v1/betaBuildLocalizations",
                    body={"data": {"type": "betaBuildLocalizations",
                                   "attributes": {"locale": LOCALE, "whatsNew": text},
                                   "relationships": {"build": {"data": {"type": "builds", "id": build["id"]}}}}})
    print(f"What to Test set for build {number} ({LOCALE}).")


if __name__ == "__main__":
    main()
