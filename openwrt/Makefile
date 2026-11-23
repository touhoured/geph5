include $(TOPDIR)/rules.mk

PKG_NAME:=geph5-client
PKG_VERSION:=$(GEPH_VERSION)
PKG_RELEASE:=1
PKG_LICENSE:=MPL-2.0

include $(INCLUDE_DIR)/package.mk

define Package/geph5-client
  SECTION:=net
  CATEGORY:=Network
  TITLE:=Geph5 command-line client
  URL:=https://geph.io
endef

define Build/Prepare
	mkdir -p $(PKG_BUILD_DIR)
endef

define Build/Compile
endef

define Package/geph5-client/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(CURDIR)/geph5-client $(1)/usr/bin/
endef

$(eval $(call BuildPackage,geph5-client))
