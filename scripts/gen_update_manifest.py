import json
import sys

# 参数：manifest_name  apk_name  tag  vname  vcode  sha  size  digest  base
# manifest_name: 生成的 .json 文件名（不含扩展名），须与 app 内 Updater.getManifestName 完全一致
#   = {mode}-{abi}[-beta]  (无 "app-" 前缀)，例：leanback-armeabi_v7a-beta
# apk_name: 真实 APK 文件名（含 -debug 后缀，不带扩展名），例：app-leanback-armeabi_v7a-debug
manifest_name, apk_name, tag, vname, vcode, sha, size, digest, base = sys.argv[1:10]
apk_url = f"{base}/{apk_name}.apk"
channel = "beta" if manifest_name.endswith("-beta") else "stable"
data = {
    "name": tag,
    "versionName": vname,
    "desc": f"{tag} - {sha} (qznet/webhtv-silent1566 自动跟随构建)",
    "channel": channel,
    "code": int(vcode),
    "apk": apk_url,
    "size": int(size),
    "sha256": digest,
    "notes": "自动跟随上游 Silent1566/webhtv 构建；含全屏上下键调速定制。",
    "downloads": {"github": {"url": apk_url}},
}
with open(f"dist/{manifest_name}.json", "w", encoding="utf-8") as fh:
    json.dump(data, fh, ensure_ascii=False, indent=2)
print(f"  manifest: dist/{manifest_name}.json  ->  {apk_url}")
