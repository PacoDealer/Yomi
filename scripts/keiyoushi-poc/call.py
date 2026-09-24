#!/usr/bin/env python3
"""Drive M-Extension-Server's POST /dalvik the way Yomi will: the first call sends the APK, later calls reuse
the server-issued handle. Walks popular -> search -> details -> chapters -> pages -> first image, timing each."""
import base64, json, sys, time, urllib.request, urllib.error

PORT = 18765
# The bridge copies the caller's User-Agent onto extension requests; Yomi will send its WKWebView UA.
UA = ("Mozilla/5.0 (iPhone; CPU iPhone OS 26_6 like Mac OS X) AppleWebKit/605.1.15 "
      "(KHTML, like Gecko) Version/26.0 Mobile/15E148 Safari/604.1")
_handles = {}
NEWEST = "--newest" in sys.argv

def call(apk, method, **kw):
    body = {"method": method, **kw}
    if apk in _handles:
        body["extensionId"] = _handles[apk]
    else:
        body["data"] = base64.b64encode(open(apk, "rb").read()).decode()
    req = urllib.request.Request(f"http://127.0.0.1:{PORT}/dalvik", json.dumps(body).encode(),
                                 {"Content-Type": "application/json", "User-Agent": UA})
    t = time.time()
    try:
        with urllib.request.urlopen(req, timeout=300) as r:
            _handles[apk] = r.headers.get("X-Mangayomi-Extension-Id") or _handles.get(apk)
            out = json.loads(r.read())
    except urllib.error.HTTPError as e:
        out = {"error": f"HTTP {e.code}", "body": e.read().decode()[:600]}
    return out, int((time.time() - t) * 1000)

def first_list(res):
    if isinstance(res, list):
        return res
    if isinstance(res, dict):
        for v in res.values():
            if isinstance(v, list):
                return v
    return None

def show(label, ms, res):
    items = first_list(res)
    summary = f"{len(items)} items" if items is not None else "object"
    print(f"{label:<22} {ms:>6} ms  {summary}  {json.dumps(res)[:220]}")
    return items

def run(apk, query):
    ok = True
    popular = show("getPopularManga", *reversed(call(apk, "getPopularManga", page=1)))
    ok &= bool(popular)
    show(f"getSearchManga({query})", *reversed(call(apk, "getSearchManga", page=1, search=query, filterList=[])))
    if not popular:
        return False
    manga = {k: popular[0].get(k) for k in ("url", "title", "thumbnail_url")}
    details, ms = call(apk, "getDetailsManga", mangaData=manga)
    show("getDetailsManga", ms, details)
    ok &= "error" not in details
    chapters = show("getChapterList", *reversed(call(apk, "getChapterList", mangaData=manga)))
    ok &= bool(chapters)
    if not chapters:
        return False
    ch = chapters[0] if NEWEST else chapters[-1]
    print("chapter:", ch.get("name"))
    pages = show("getPageList", *reversed(call(apk, "getPageList", chapterData={"url": ch["url"], "name": ch.get("name")})))
    ok &= bool(pages)
    if pages:
        p = pages[0]
        url = p.get("imageUrl") or p.get("url")
        print("first page object:", json.dumps(p)[:300])
        if url:
            if url.startswith("/"):
                url = f"http://127.0.0.1:{PORT}{url}"
            t = time.time()
            try:
                with urllib.request.urlopen(urllib.request.Request(url, headers={"User-Agent": UA}), timeout=120) as r:
                    data = r.read()
                    print(f"{'first image':<22} {int((time.time()-t)*1000):>6} ms  {len(data)} bytes  {r.headers.get('Content-Type')}  magic={data[:12]!r}")
            except Exception as e:
                ok = False
                print("first image FAILED:", e)
    return ok

if __name__ == "__main__":
    args = [a for a in sys.argv[1:] if a != "--newest"]
    sys.exit(0 if run(args[0], args[1] if len(args) > 1 else "solo") else 1)
