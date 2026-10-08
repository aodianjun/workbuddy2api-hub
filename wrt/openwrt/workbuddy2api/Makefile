#
# WorkBuddy2API-Hub · OpenWrt 版
#
# 纯 Python 包（只用标准库，零 pip 依赖），与 CPU 架构无关，
# 因此 PKGARCH:=all，产物是 workbuddy2api-1.6.16-r1.apk（架构 all）。
#
# 在 OpenWrt SDK 里构建：
#   sh openwrt/build-apk.sh <SDK 目录>      # 推荐：自动按钉死的 commit 拉上游源码
# 或手动：
#   cp -R openwrt/workbuddy2api <SDK>/package/
#   cd <SDK> && make package/workbuddy2api/compile V=s
#
# 上游源码（wb_*.py + dashboard.html）不在这里下载：build-apk.sh 会先把它
# 放进 files/usr/lib/workbuddy2api/，Build/Prepare 只做拷贝。
#
include $(TOPDIR)/rules.mk

PKG_NAME:=workbuddy2api
PKG_VERSION:=1.6.16
PKG_RELEASE:=1

PKG_LICENSE:=MIT
PKG_MAINTAINER:=aodianjun

PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_NAME)-$(PKG_VERSION)

# 应用源码目录：优先包目录自带（整个包目录可独立拷进 SDK），
# 不存在时回退到 ../../app-src（仓库里原地构建时用）。
APP_SRC:=$(firstword $(wildcard $(CURDIR)/files/usr/lib/workbuddy2api) $(wildcard $(CURDIR)/../../app-src))
ifeq ($(APP_SRC),)
$(error 找不到应用源码（files/usr/lib/workbuddy2api 或 ../../app-src），请先运行 openwrt/build-apk.sh)
endif

include $(INCLUDE_DIR)/package.mk

define Package/workbuddy2api
  SECTION:=net
  CATEGORY:=Network
  TITLE:=WorkBuddy multi-account gateway with OpenAI-compatible API
  URL:=https://github.com/ardeyouxipianyi/workbuddy2api-hub
  DEPENDS:=+python3-light +python3-urllib +python3-uuid
  PKGARCH:=all
endef

define Package/workbuddy2api/description
  把腾讯 WorkBuddy（国际版 workbuddy.ai / 国内版 codebuddy.cn）包装成
  OpenAI 兼容 API 的多账号网关：/v1/chat/completions 与 /v1/responses，
  自带看板（8788 端口）做账号管理、用量统计、定价估算与每日自动任务。

  纯 Python 标准库实现（上游不引入任何 pip 依赖），依赖只有 python3-light /
  python3-urllib / python3-uuid 三个包；Windows 专属功能（从桌面客户端内存
  回收解码密钥）在 Linux 上自动跳过，账号用看板的浏览器 OAuth 添加。

  安装后不会自动启动服务，启用方法：
    1) uci set workbuddy2api.main.panel_password='你的面板密码'
       uci commit workbuddy2api
    2) /etc/init.d/workbuddy2api enable && /etc/init.d/workbuddy2api start
    3) 浏览器打开 http://<路由器IP>:8788/ 登录，点「添加账号 (OAuth)」授权

  配置 /etc/config/workbuddy2api（含面板密码与可选固定 API Key，权限 600）；
  账号凭据与用量 /etc/workbuddy2api/（已加入 sysupgrade 保留列表）。
  升级只替换 /usr/lib/workbuddy2api 下的程序文件，配置与账号不受影响。

  自动更新：装包时会加一条 cron（每天 04:17 跑 /usr/bin/workbuddy2api-update），
  自动检查上游 GitHub 新版本并替换程序文件——带文件校验、导入冒烟测试、
  健康检查与失败自动回滚；uci main.auto_update=0 可关闭。
endef

define Build/Prepare
	rm -rf $(PKG_BUILD_DIR)
	mkdir -p $(PKG_BUILD_DIR)
	$(CP) $(CURDIR)/files/. $(PKG_BUILD_DIR)/
endef

define Build/Compile
endef

define Package/workbuddy2api/install
	$(INSTALL_DIR) $(1)/usr/lib/workbuddy2api
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/usr/lib/workbuddy2api/wb_*.py $(1)/usr/lib/workbuddy2api/
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/usr/lib/workbuddy2api/dashboard.html $(1)/usr/lib/workbuddy2api/
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/usr/bin/workbuddy2api-update $(1)/usr/bin/workbuddy2api-update
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/usr/bin/workbuddy2api-warm $(1)/usr/bin/workbuddy2api-warm
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/etc/init.d/workbuddy2api $(1)/etc/init.d/workbuddy2api
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) $(PKG_BUILD_DIR)/etc/config/workbuddy2api $(1)/etc/config/workbuddy2api
endef

# 配置文件（升级时按 conffile 处理：写进 /lib/apk/packages/workbuddy2api.conffiles）
define Package/workbuddy2api/conffiles
/etc/config/workbuddy2api
endef

# 安装后置脚本：准备数据目录、加入 sysupgrade 保留列表、收紧配置权限、
# 装自动更新的 cron。与 powerfee 同样的约定——首次安装不自动启用/启动服务
# （25.12 的 default_postinst 会先 enable+start，这里显式撤销），升级时不动现状。
define Package/workbuddy2api/postinst
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] || {
	mkdir -p /etc/workbuddy2api/accounts /etc/workbuddy2api/usage
	chmod 700 /etc/workbuddy2api /etc/workbuddy2api/accounts
	[ -f /etc/config/workbuddy2api ] && chmod 600 /etc/config/workbuddy2api
	grep -q '^/etc/workbuddy2api$$' /etc/sysupgrade.conf 2>/dev/null || \
		echo '/etc/workbuddy2api' >> /etc/sysupgrade.conf
	# 自动更新：每天 04:17 检查上游新版本（uci main.auto_update=0 可关；
	# 幂等，重复安装/升级不会写重复行）
	mkdir -p /etc/crontabs
	grep -q 'workbuddy2api-update' /etc/crontabs/root 2>/dev/null || \
		echo '17 4 * * * /usr/bin/workbuddy2api-update --quiet' >> /etc/crontabs/root
	# 缓存预热：每 12 分钟把面板的贵接口（统计页 4 个时间窗 + /usage 汇总）
	# 先跑一遍，用户切页不用等十几秒（uci main.warm=0 可关）
	grep -q 'workbuddy2api-warm' /etc/crontabs/root 2>/dev/null || \
		echo '*/12 * * * * /usr/bin/workbuddy2api-warm --quiet' >> /etc/crontabs/root
	/etc/init.d/cron restart >/dev/null 2>&1 || true
	[ "$${PKG_UPGRADE}" = "1" ] || {
		/etc/init.d/workbuddy2api disable >/dev/null 2>&1
		/etc/init.d/workbuddy2api stop >/dev/null 2>&1
	}
}
endef

# 卸载后置脚本：清程序目录与自动更新（python 运行留下的 __pycache__ 一并清掉）。
# /etc/workbuddy2api（账号/用量）与 /etc/config/workbuddy2api 是用户数据，保留。
define Package/workbuddy2api/postrm
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] || {
	rm -rf /usr/lib/workbuddy2api /usr/lib/workbuddy2api.prev
	rm -f /usr/bin/workbuddy2api-update /usr/bin/workbuddy2api-warm
	sed -i '/workbuddy2api-update/d; /workbuddy2api-warm/d' /etc/crontabs/root 2>/dev/null
	/etc/init.d/cron restart >/dev/null 2>&1 || true
}
endef

$(eval $(call BuildPackage,workbuddy2api))
