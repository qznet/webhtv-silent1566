import json
import sys

name, tag, vname, vcode, sha, size, digest, base = sys.argv[1:9]
url = f"{base}/{name}-debug.apk"
data = {
    "name": tag,
    "versionName": vname,
    "desc": f"{tag} - {sha} (qznet/webhtv-silent1566 自动跟随构建)",
    "channel": "beta" if "beta" in tag else "stable",
    "code": int(vcode),
    "apk": url,
    "size": int(size),
    "sha256": digest,
    "notes": "自动跟随上游 Silent1566/webhtv 构建；含全屏上下键调速定制。",
    "downloads": {"github": {"url": url}},
}
with open(f"dist/{name}.json", "w", encoding="utf-8") as fh:
    json.dump(data, fh, ensure_ascii=False, indent=2)
print(f"  manifest: dist/{name}.json")