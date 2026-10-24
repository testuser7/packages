# SPDX-License-Identifier: GPL-2.0-only
#
# Copyright (C) 2023 Luca Barbato and Donald Hoskins

include $(TOPDIR)/rules.mk

PKG_NAME:=rust
PKG_VERSION:=1.96.0
PKG_RELEASE:=2

PKG_MAINTAINER:=Luca Barbato <lu_zero@luminem.org>
PKG_LICENSE:=Apache-2.0 MIT
PKG_LICENSE_FILES:=LICENSE-APACHE LICENSE-MIT
PKG_CPE_ID:=cpe:/a:rust-lang:rust

PKG_HOST_ONLY:=1
PKG_BUILD_FLAGS:=no-mips16

include ./rust-values.mk

ifeq ($(CONFIG_RUST_USE_PREBUILT_BINARIES),y)
  ifeq ($(strip $(RUST_BIN_SUM)),)
    $(error rust: No prebuilt host binary hash for RUSTC_HOST_ARCH='$(RUSTC_HOST_ARCH)'; \
      enable only for supported hosts or set CONFIG_RUST_USE_PREBUILT_BINARIES=n)
  endif
else
  RUST_BIN_SUM:=
endif

# The Rust target triple does not distinguish PowerPC soft-float from
# hard-float, so the upstream prebuilt std may have the wrong ABI.
ifeq ($(ARCH),powerpc)
  ifeq ($(CONFIG_SOFT_FLOAT),y)
    RUST_STD_SUM:=
  endif
endif

ifeq ($(CONFIG_RUST_USE_PREBUILT_STD),y)
  ifeq ($(strip $(RUST_BIN_SUM)),)
    RUST_STD_SUM:=
  else
    ifeq ($(strip $(RUST_STD_SUM)),)
      ifneq ($(CONFIG_RUST_BUILD_STD_FROM_SOURCE),y)
        RUST_STD_UNAVAILABLE:=y
      else
        $(warning rust: No prebuilt std for RUSTC_TARGET_ARCH='$(RUSTC_TARGET_ARCH)'; building the Rust toolchain from source as configured)
        RUST_BIN_SUM:=
      endif
    endif
  endif
else
  RUST_BIN_SUM:=
  RUST_STD_SUM:=
endif

# Source build configuration (must be set before host-build.mk)
ifneq ($(RUST_BIN_SUM),)
  PKG_SOURCE:=rust-$(PKG_VERSION)-$(RUSTC_HOST_ARCH).tar.xz
  PKG_SOURCE_URL:=https://static.rust-lang.org/dist/
  PKG_HASH:=$(RUST_BIN_SUM)
  PKG_BUILD_DIR:=$(BUILD_DIR_HOST)/rust-$(PKG_VERSION)-$(RUSTC_HOST_ARCH)
  HOST_BUILD_DIR:=$(BUILD_DIR_HOST)/rust-$(PKG_VERSION)-$(RUSTC_HOST_ARCH)
  HOST_BUILD_DEPENDS:=
else
  PKG_SOURCE:=rustc-$(PKG_VERSION)-src.tar.xz
  PKG_SOURCE_URL:=https://static.rust-lang.org/dist/
  PKG_HASH:=$(RUST_SRC_HASH)
  PKG_BUILD_DIR:=$(BUILD_DIR_HOST)/rustc-$(PKG_VERSION)-src
  HOST_BUILD_DIR:=$(BUILD_DIR_HOST)/rustc-$(PKG_VERSION)-src
  HOST_BUILD_DEPENDS:=python3/host
endif

include $(INCLUDE_DIR)/host-build.mk
include $(INCLUDE_DIR)/package.mk

ifneq ($(RUST_BIN_SUM),)
  HOST_UNPACK:=$(HOST_TAR) -C "$(HOST_BUILD_DIR)" --strip-components=1 -xf "$(DL_DIR)/$(PKG_SOURCE)"
endif

define Package/rust
  SECTION:=lang
  CATEGORY:=Languages
  SUBMENU:=Rust
  TITLE:=Rust Programming Language Compiler
  URL:=https://www.rust-lang.org/
  DEPENDS:=$(RUST_ARCH_DEPENDS)
endef

define Package/rust/description
  Rust is a multi-paradigm, general-purpose programming language designed for performance
  and safety, especially safe concurrency. Rust is syntactically similar to C++, but can
  guarantee memory safety by using a borrow checker to validate references.
endef

define Package/rust/config
  source "$(SOURCE)/Config.in"
endef

# Rust-lang has an uninstall script
RUST_UNINSTALL:=$(STAGING_DIR)/host/lib/rustlib/uninstall.sh

# Install directory flags shared by both build paths
RUST_HOST_INSTALL_ARGS = \
	--prefix=$(STAGING_DIR)/host \
	--bindir=$(STAGING_DIR)/host/bin \
	--libdir=$(STAGING_DIR)/host/lib \
	--sysconfdir=$(STAGING_DIR)/host/etc \
	--datadir=$(STAGING_DIR)/host/share \
	--mandir=$(STAGING_DIR)/host/man

# Target Flags
TARGET_CONFIGURE_ARGS = \
	--set=target.$(RUSTC_TARGET_ARCH).ar=$(TARGET_AR) \
	--set=target.$(RUSTC_TARGET_ARCH).cc=$(TARGET_CC_NOCACHE) \
	--set=target.$(RUSTC_TARGET_ARCH).cxx=$(TARGET_CXX_NOCACHE) \
	--set=target.$(RUSTC_TARGET_ARCH).linker=$(TARGET_CC_NOCACHE) \
	--set=target.$(RUSTC_TARGET_ARCH).ranlib=$(TARGET_RANLIB) \
	--set=target.$(RUSTC_TARGET_ARCH).crt-static=false \
	$(if $(CONFIG_USE_MUSL),--set=target.$(RUSTC_TARGET_ARCH).musl-root=$(TOOLCHAIN_ROOT_DIR))

define Host/Prepare
	@if [ "$(RUST_STD_UNAVAILABLE)" = y ]; then \
		echo "rust: No prebuilt target std for RUSTC_TARGET_ARCH='$(RUSTC_TARGET_ARCH)'; enable CONFIG_RUST_BUILD_STD_FROM_SOURCE to build the Rust toolchain from source" >&2; \
		exit 1; \
	fi
	$(call Host/Prepare/Default)
	$(if $(RUST_BIN_SUM),
		$(Q) MKHASH="$(MKHASH)" $(SCRIPT_DIR)/download.pl "$(DL_DIR)" \
			"rust-std-$(PKG_VERSION)-$(RUSTC_TARGET_ARCH).tar.xz" "$(RUST_STD_SUM)" "" \
			"https://static.rust-lang.org/dist/"
	)
endef

define Host/Uninstall
	[ -f $(RUST_UNINSTALL) ] && \
		$(BASH) $(RUST_UNINSTALL) || echo No Uninstall
endef

define Rust/Validate/Std
	@set -eu; \
		libdir="$(STAGING_DIR)/host/lib/rustlib/$(RUSTC_TARGET_ARCH)/lib"; \
		for crate in core alloc std compiler_builtins; do \
			set -- "$$libdir"/lib$$crate-*.rlib; \
			if [ ! -f "$$1" ]; then \
				echo "rust: missing target std artifact lib$$crate-*.rlib in $$libdir" >&2; \
				exit 1; \
			fi; \
		done; \
		for crate in core alloc std; do \
			set -- "$$libdir"/lib$$crate-*.rmeta; \
			if [ ! -f "$$1" ]; then \
				echo "rust: missing target std metadata lib$$crate-*.rmeta in $$libdir" >&2; \
				exit 1; \
			fi; \
		done; \
		set -- "$$libdir"/libpanic_unwind-*.rlib; \
		if [ ! -f "$$1" ]; then \
			set -- "$$libdir"/libpanic_abort-*.rlib; \
			if [ ! -f "$$1" ]; then \
				echo "rust: missing target panic runtime (libpanic_unwind or libpanic_abort) in $$libdir" >&2; \
				exit 1; \
			fi; \
		fi
endef

ifneq ($(RUST_BIN_SUM),)

# Prebuilt binary tarball has no configure script or Makefile, so we
# override the default host build steps with no-ops.
define Host/Patch
	@:
endef

define Host/Configure
	@:
endef

define Host/Compile
	@:
endef

define Host/Install
	rm -rf $(STAGING_DIR)/host/lib/rustlib
	$(BASH) $(HOST_BUILD_DIR)/install.sh \
		$(RUST_HOST_INSTALL_ARGS) \
		--disable-ldconfig \
		--components=rustc,cargo,rust-std-$(RUSTC_HOST_ARCH)
	$(call Rust/Install/Std/Prebuilt)
	$(call Rust/Validate/Std)
endef

define Rust/Install/Std/Prebuilt
	$(INSTALL_DIR) $(HOST_BUILD_DIR)/std-$(RUSTC_TARGET_ARCH)
	$(HOST_TAR) -xf "$(DL_DIR)/rust-std-$(PKG_VERSION)-$(RUSTC_TARGET_ARCH).tar.xz" -C "$(HOST_BUILD_DIR)/std-$(RUSTC_TARGET_ARCH)" --strip-components=1
	$(BASH) "$(HOST_BUILD_DIR)/std-$(RUSTC_TARGET_ARCH)/install.sh" \
		$(RUST_HOST_INSTALL_ARGS) \
		--disable-ldconfig \
		--components=rust-std-$(RUSTC_TARGET_ARCH)
	rm -rf $(HOST_BUILD_DIR)/std-$(RUSTC_TARGET_ARCH)
endef

else

# CARGO_HOME is an environment variable
HOST_CONFIGURE_VARS += CARGO_HOME="$(CARGO_HOME)"

# Rust Configuration Arguments
HOST_CONFIGURE_ARGS = \
	--build=$(RUSTC_HOST_ARCH) \
	--target=$(RUSTC_TARGET_ARCH),$(RUSTC_HOST_ARCH) \
	--host=$(RUSTC_HOST_ARCH) \
	$(RUST_HOST_INSTALL_ARGS) \
	--dist-compression-formats=gz \
	--disable-sanitizers \
	--release-channel=stable \
	--enable-cargo-native-static \
	--bootstrap-cache-path=$(DL_DIR)/rustc \
	--set=llvm.download-ci-llvm=false \
	$(TARGET_CONFIGURE_ARGS)

define Host/Compile
	$(RUST_SCCACHE_VARS) \
	CARGO_HOME=$(CARGO_HOME) \
	TARGET_CFLAGS="$(TARGET_CFLAGS)" \
	$(if $(RUSTC_TARGET_RUSTFLAGS),$(RUSTC_TARGET_CARGO_RUSTFLAGS)="$(RUSTC_TARGET_RUSTFLAGS)") \
	$(PYTHON) $(HOST_BUILD_DIR)/x.py \
		--build-dir $(HOST_BUILD_DIR)/build \
		dist build-manifest rustc rust-std cargo llvm-tools rust-src
endef

define Host/Install
	rm -rf $(STAGING_DIR)/host/lib/rustlib
	( \
		cd $(HOST_BUILD_DIR)/build/dist ; \
		for targz in *.tar.gz; do \
			$(STAGING_DIR_HOST)/bin/libdeflate-gzip -dc "$$$$targz" | tar -xf - ; \
		done ; \
		find . -mindepth 2 -maxdepth 2 -type f -name install.sh \
			-execdir bash '{}' --prefix=$(STAGING_DIR)/host --disable-ldconfig \; ; \
	)
	$(call Rust/Validate/Std)
endef

endif

$(eval $(call HostBuild))
$(eval $(call BuildPackage,rust))
