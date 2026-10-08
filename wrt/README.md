# wrt/ — fork 自带的 OpenWrt 打包目录

这里放 WorkBuddy2API-Hub 的 OpenWrt 安装包配方与 CI。**独立于上游目录**：
上游只维护 `wb_*.py` / `dashboard.html` 等应用代码，本目录是 fork 自己加的，
所以上游同步（merge-upstream）永远不会和它冲突。

## 内容

```
wrt/
├── README.md                        # 本文件
├── ci/                              # CI 工作流（见下方「激活」一节）
│   ├── wrt-sync-upstream.yml        # 每天/手动同步上游
│   ├── wrt-packages.yml             # 构建 .ipk/.apk 并发布 release
│   └── activate-workflows.py        # 把这两个文件放进 .github/workflows/ 的脚本
└── openwrt/
    ├── build-ipk.sh                 # 打包 .ipk（opkg 系，OpenWrt <= 24.10），不需要 SDK
    ├── build-apk.sh                 # 打包 .apk（apk-tools 3，OpenWrt 25.x），需要 OpenWrt SDK
    └── workbuddy2api/
        ├── Makefile                 # 包定义（PKG_VERSION / PKG_RELEASE / 依赖 / postinst ...）
        └── files/                   # init.d、uci 配置、自动更新与预热脚本
```

两种包的内容一致：`wb_*.py` + `dashboard.html`（纯 Python 标准库）+
`/etc/init.d/workbuddy2api` + `/etc/config/workbuddy2api` + `/usr/bin/workbuddy2api-{update,warm}`。

| 产物 | 适用系统 | 安装方式 |
| --- | --- | --- |
| `workbuddy2api_<版本>-<发布号>_all.ipk` | opkg 系（OpenWrt 24.10 及更早） | `opkg install <文件>` |
| `workbuddy2api-<版本>-r<发布号>.apk` | apk-tools 3（OpenWrt 25.x） | `apk add --allow-untrusted <文件>`（未签名时） |

依赖（两套系统同名）：`python3-light`、`python3-urllib`、`python3-uuid`。

## ⚠ 激活 CI（一次性，需要维护者操作）

两个工作流现在放在 **`wrt/ci/`**，还没进 `.github/workflows/`。原因：GitHub
**要求 token 带 `workflow` 作用域才能创建/更新 `.github/workflows/` 下的文件**，
当前用的 PAT 只有 `repo, delete_repo` 两个作用域，走 REST API（blobs→trees→commits→refs）、
Contents API、GraphQL 全部会被 GitHub 拒绝（tree 创建返回 404，merge-upstream 返回 422
"refusing to allow a Personal Access Token to create or update workflow ... without
`workflow` scope"）。三种激活方式，任选其一：

1. **给 token 加上 `workflow` 作用域**（或新建一个带 `repo` + `workflow` 的 PAT），
   然后跑一次本仓库自带的脚本（会把两个文件原样放进 `.github/workflows/` 并推送）：
   ```sh
   GH_TOKEN=<带 workflow 作用域的 token> python3 wrt/ci/activate-workflows.py
   ```
2. **网页手动复制**：在 GitHub 上打开 `wrt/ci/wrt-sync-upstream.yml` 与
   `wrt/ci/wrt-packages.yml`，分别复制内容，用 "Add file → Create new file" 建
   `.github/workflows/wrt-sync-upstream.yml` 与 `.github/workflows/wrt-packages.yml`
   （直接提交到 main 即可；网页操作不受 token 作用域限制）。
3. 本地有 git 的环境里：`git mv wrt/ci/wrt-sync-upstream.yml wrt/ci/wrt-packages.yml .github/workflows/ && git push`。

激活后可以删掉 `wrt/ci/` 里的副本（保留也无妨，不会被当成工作流）。

## CI 说明（激活后生效）

- **`wrt-sync-upstream.yml`**：每天 03:23 UTC 调一次 `POST /repos/.../merge-upstream`
  （等价于网页上的 "Sync fork" 按钮），也可以手动 `workflow_dispatch`。
  409（冲突）会**明确报错**要求人工处理，不吞掉；422（workflow 作用域等）也会明确报错。
- **`wrt-packages.yml`**：`workflow_dispatch` / 每天 04:37 UTC / 推送到 `main`
  且改动了 `wrt/**`、`wb_*.py`、`dashboard.html` 时触发。流程：
  1. 先调同一个 merge-upstream 同步上游（失败也继续，见 `if: always()`）；
  2. 从 `wb_proxy.py` 的 `server_version` 与 Makefile 取版本，tag 为
     `wrt-<PKG_VERSION>-<PKG_RELEASE>`（例：`wrt-1.6.16-1`）；
  3. **幂等**：该 tag 的 release 已存在且 `.apk`/`.ipk` 资产齐全就直接跳过，
     重复运行不会产生重复 release / 重复资产；
  4. 构建 `.ipk`（脚本自检结构）与 `.apk`（下载并缓存 OpenWrt 25.12.2 x86-64
     SDK，`zstd` 解压），然后创建/补全 release 并上传缺失的资产。

### 签名

CI 默认**没有私钥**，`.apk` 是未签名的，安装时用
`apk add --allow-untrusted <文件>`。若在仓库 secret 里配置：

- `WRT_SIGNING_KEY` — PEM 私钥全文（EC P-256 或 RSA）。配置后 CI 会用 SDK 自带的
  `apk adbsign --sign-key` 签名并 `apk verify` 自检，release 说明里也会标明"已签名"。
  用户侧把对应公钥（`workbuddy2api-signing.pem`）放进 `/etc/apk/keys/` 后即可不加
  `--allow-untrusted` 直接安装。
- `WRT_SYNC_TOKEN`（可选）— 带 `workflow` 作用域的 PAT。上游改动
  `.github/workflows/*` 时需要它，否则 merge-upstream 会以 422 失败（workflow 里
  会自动优先使用它，没有就退回 `GITHUB_TOKEN`）。

> 注意：workflow 里用 `GITHUB_TOKEN` 推送产生的 commit 不会触发其它 workflow
> （GitHub 的防递归机制），所以同步和构建放在同一个 workflow 文件里，构建不依赖
> "同步推送"去触发。

## 本地构建

```sh
# .ipk：任意 POSIX sh + python3 即可，不需要 SDK（脚本内嵌打包器并自检）
sh wrt/openwrt/build-ipk.sh --app-src <含 wb_*.py 的目录>      # 产物在 wrt/ipk/

# .apk：需要 OpenWrt 25.x 的 x86_64 SDK（glibc 宿主机）
sh wrt/openwrt/build-apk.sh <SDK 目录> [应用源码目录]           # 产物在 wrt/apk/
```

不传应用源码目录时，两个脚本都会按各自顶部钉死的 `PIN_SHA` 从上游 GitHub
拉取源码到 `wrt/app-src/`（缓存复用）。`PIN_SHA` / `PIN_VER` 与 Makefile 的
`PKG_VERSION` 必须一致，否则脚本会拒绝打包。

## 升级上游版本

1. 改 `wrt/openwrt/workbuddy2api/Makefile` 的 `PKG_VERSION`（需要时 `PKG_RELEASE`）；
2. 同步改 `wrt/openwrt/build-apk.sh` 与 `build-ipk.sh` 顶部的 `PIN_SHA`（新版本的上游
   commit）与 `PIN_VER`；
3. 推送后 `wrt-packages.yml`（激活后）会自动为新版本建一个新的 release（tag 含新版本号）。
