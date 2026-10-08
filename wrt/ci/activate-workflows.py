#!/usr/bin/env python3
"""把 wrt/ci/ 下的两个工作流放进 .github/workflows/ 并推送到 fork 的 main。

GitHub 要求 token 带 `workflow` 作用域才能创建/更新 .github/workflows/ 下的文件；
本脚本用 blobs -> trees -> commits -> refs 的 REST 流程提交（等价于 git push），
需要环境变量 GH_TOKEN（或 GITHUB_TOKEN）里有一个带 `workflow` 作用域的 PAT。

用法：
    GH_TOKEN=<token> python3 wrt/ci/activate-workflows.py [--repo owner/name] [--dry-run]

默认仓库：aodianjun/workbuddy2api-hub，默认分支 main。
"""
import argparse
import base64
import hashlib
import json
import os
import sys
import urllib.error
import urllib.request

API = "https://api.github.com"
HERE = os.path.dirname(os.path.abspath(__file__))
WORKFLOWS = ["wrt-sync-upstream.yml", "wrt-packages.yml"]


def api(method, path, token, data=None):
    url = path if path.startswith("http") else API + path
    body = None
    if data is not None:
        body = data if isinstance(data, (bytes, bytearray)) else json.dumps(data).encode()
    r = urllib.request.Request(url, data=body, method=method)
    r.add_header("User-Agent", "wrt-ci-activate")
    r.add_header("Authorization", "Bearer " + token)
    r.add_header("Accept", "application/vnd.github+json")
    try:
        with urllib.request.urlopen(r) as resp:
            return resp.status, json.loads(resp.read().decode() or "{}")
    except urllib.error.HTTPError as e:
        try:
            return e.code, json.loads(e.read().decode() or "{}")
        except Exception:
            return e.code, {}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo", default="aodianjun/workbuddy2api-hub")
    ap.add_argument("--branch", default="main")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    token = (os.environ.get("GH_TOKEN") or os.environ.get("GITHUB_TOKEN") or "").strip()
    if not token:
        sys.exit("错误：需要环境变量 GH_TOKEN（带 workflow 作用域的 PAT）")

    s, r = api("GET", "/user", token)
    if s != 200:
        sys.exit("错误：token 无效（HTTP %s: %s）" % (s, r.get("message")))
    print("token 用户:", r.get("login"))

    files = {}
    for name in WORKFLOWS:
        p = os.path.join(HERE, name)
        with open(p, "rb") as f:
            b = f.read()
        files[".github/workflows/" + name] = (b, hashlib.sha256(b).hexdigest())
        print("待提交: .github/workflows/%s (%d 字节, sha256 %s)" % (name, len(b), files[".github/workflows/" + name][1]))

    if args.dry_run:
        print("dry-run：不推送")
        return

    for attempt in (1, 2):
        s, r = api("GET", "/repos/%s/git/ref/heads/%s" % (args.repo, args.branch), token)
        if s != 200:
            sys.exit("错误：读取 %s 失败 HTTP %s" % (args.branch, s))
        tip = r["object"]["sha"]
        s, r = api("GET", "/repos/%s/git/commits/%s" % (args.repo, tip), token)
        base_tree = r["tree"]["sha"]

        entries = []
        for path, (b, _sha) in files.items():
            s, r = api("POST", "/repos/%s/git/blobs" % args.repo, token,
                       {"content": base64.b64encode(b).decode(), "encoding": "base64"})
            if s != 201:
                sys.exit("错误：创建 blob 失败 HTTP %s %s（token 是否有 workflow 作用域？）" % (s, r))
            entries.append({"path": path, "mode": "100644", "type": "blob", "sha": r["sha"]})

        s, r = api("POST", "/repos/%s/git/trees" % args.repo, token,
                   {"base_tree": base_tree, "tree": entries})
        if s != 201:
            sys.exit("错误：创建 tree 失败 HTTP %s %s\n"
                     "（若为 404/422：token 缺少 `workflow` 作用域——GitHub 不允许它改 .github/workflows/）"
                     % (s, r))
        tree = r["sha"]

        s, r = api("POST", "/repos/%s/git/commits" % args.repo, token, {
            "message": "ci: 激活 OpenWrt 打包工作流（wrt-sync-upstream / wrt-packages）",
            "tree": tree, "parents": [tip]})
        if s != 201:
            sys.exit("错误：创建 commit 失败 HTTP %s %s" % (s, r))
        commit = r["sha"]

        s, r = api("GET", "/repos/%s/git/ref/heads/%s" % (args.repo, args.branch), token)
        if r["object"]["sha"] != tip:
            print("main 在提交期间被移动，重试…")
            continue
        s, r = api("PATCH", "/repos/%s/git/refs/heads/%s" % (args.repo, args.branch), token,
                   {"sha": commit, "force": False})
        if s != 200:
            print("推送失败 HTTP %s %s" % (s, r))
            if attempt == 1:
                continue
            sys.exit(1)
        print("已推送: %s -> %s" % (args.branch, commit))

        # 校验
        ok = True
        for path, (_b, sha) in files.items():
            s, r = api("GET", "/repos/%s/contents/%s?ref=%s" % (args.repo, path, args.branch), token)
            remote_sha = hashlib.sha256(base64.b64decode(r.get("content", ""))).hexdigest() if s == 200 else None
            print("%s  remote sha256 %s  %s" % ("OK " if remote_sha == sha else "FAIL", remote_sha, path))
            ok = ok and remote_sha == sha
        print("完成" if ok else "校验失败")
        return


if __name__ == "__main__":
    main()
