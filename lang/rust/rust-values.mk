# SPDX-License-Identifier: GPL-2.0-only
#
# Copyright (C) 2023 Luca Barbato and Donald Hoskins

# Clear environment variables which should be handled internally,
# as users might configure their own env on the host

# CCache
unexport RUSTC_WRAPPER

# Rust Environmental Vars
RUSTC_HOST_SUFFIX:=$(word 4, $(subst -, ,$(GNU_HOST_NAME)))
RUSTC_HOST_ARCH:=$(HOST_ARCH)-unknown-linux-$(RUSTC_HOST_SUFFIX)
CARGO_HOME:=$(DL_DIR)/cargo

ifeq ($(CONFIG_USE_MUSL),y)
  # Force linking of the SSP library for musl
  ifdef CONFIG_PKG_CC_STACKPROTECTOR_REGULAR
    ifeq ($(strip $(PKG_SSP)),1)
      RUSTC_LDFLAGS+=-lssp_nonshared
    endif
  endif
  ifdef CONFIG_PKG_CC_STACKPROTECTOR_STRONG
    ifeq ($(strip $(PKG_SSP)),1)
      RUSTC_LDFLAGS+=-lssp_nonshared
    endif
  endif
endif

CARGO_RUSTFLAGS+=-Ctarget-feature=-crt-static $(RUSTC_LDFLAGS)

ifeq ($(HOST_OS),Darwin)
  ifeq ($(HOST_ARCH),arm64)
    RUSTC_HOST_ARCH:=aarch64-apple-darwin
  else ifeq ($(HOST_ARCH),x86_64)
    RUSTC_HOST_ARCH:=x86_64-apple-darwin
  endif
endif

# mips64 openwrt has a specific target in rustc
ifeq ($(ARCH),mips64)
  RUSTC_TARGET_ARCH:=$(REAL_GNU_TARGET_NAME)
else
  RUSTC_TARGET_ARCH:=$(subst openwrt,unknown,$(REAL_GNU_TARGET_NAME))
endif

RUSTC_TARGET_ARCH:=$(subst muslgnueabi,musleabi,$(RUSTC_TARGET_ARCH))

ifeq ($(ARCH),i386)
  RUSTC_TARGET_ARCH:=$(subst i486,i586,$(RUSTC_TARGET_ARCH))
else ifeq ($(ARCH),riscv64)
  RUSTC_TARGET_ARCH:=$(subst riscv64,riscv64gc,$(RUSTC_TARGET_ARCH))
endif

# 32-bit PowerPC has both soft-float and hard-float subtargets: mpc85xx is an
# e500v2 with no floating-point unit at all, while apm821xx (powerpc_464fp)
# has one. They share the powerpc-unknown-linux-musl triple, which is the
# hard-float one, so on the soft-float subtarget rustc emits lfd, stfd and
# fdiv for a core with no floating-point registers, and passes doubles in
# registers nothing else in the image uses.
#
# CONFIG_SOFT_FLOAT already carries this: it defaults to y when the target has
# no fpu feature, and it is what puts --with-float=soft into the toolchain and
# -msoft-float into TARGET_CFLAGS.
ifeq ($(ARCH),powerpc)
  ifeq ($(CONFIG_SOFT_FLOAT),y)
    RUSTC_TARGET_RUSTFLAGS+=-Ctarget-feature=-hard-float
  endif
endif

CARGO_RUSTFLAGS+=$(RUSTC_TARGET_RUSTFLAGS)

# ARM Logic
ifeq ($(ARCH),arm)
  ifeq ($(CONFIG_arm_v6)$(CONFIG_arm_v7),)
    RUSTC_TARGET_ARCH:=$(subst arm,armv5te,$(RUSTC_TARGET_ARCH))
  else ifeq ($(CONFIG_arm_v7),y)
    RUSTC_TARGET_ARCH:=$(subst arm,armv7,$(RUSTC_TARGET_ARCH))
  endif

  ifeq ($(CONFIG_HAS_FPU),y)
    RUSTC_TARGET_ARCH:=$(subst musleabi,musleabihf,$(RUSTC_TARGET_ARCH))
    RUSTC_TARGET_ARCH:=$(subst gnueabi,gnueabihf,$(RUSTC_TARGET_ARCH))
  endif
endif

ifeq ($(ARCH),aarch64)
    RUSTC_CFLAGS:=-mno-outline-atomics
endif

# The same flags have to reach the std that rust/host builds for the target,
# or std and the packages linked against it disagree about how a double is
# passed. Bootstrap sets RUSTFLAGS itself on the cargo invocations it spawns,
# so setting that would be overwritten; it does however read
# CARGO_TARGET_<TRIPLE>_RUSTFLAGS and fold it in, scoped to that triple, which
# leaves the host artifacts built in the same run untouched.
# Deferred, because the blocks above still rewrite RUSTC_TARGET_ARCH.
RUSTC_TARGET_UPPER = $(subst -,_,$(call toupper,$(RUSTC_TARGET_ARCH)))
RUSTC_TARGET_CARGO_RUSTFLAGS = CARGO_TARGET_$(RUSTC_TARGET_UPPER)_RUSTFLAGS

# Support only a subset for now.
RUST_ARCH_DEPENDS:=@(aarch64||arm||i386||loongarch64||mips||mips64||mips64el||mipsel||powerpc||powerpc64||riscv64||x86_64)

ifneq ($(CONFIG_RUST_SCCACHE),)
  RUST_SCCACHE_DIR:=$(if $(call qstrip,$(CONFIG_RUST_SCCACHE_DIR)),$(call qstrip,$(CONFIG_RUST_SCCACHE_DIR)),$(TOPDIR)/.sccache)

  RUST_SCCACHE_VARS:= \
	CARGO_INCREMENTAL=0 \
	RUSTC_WRAPPER=sccache \
	SCCACHE_DIR=$(RUST_SCCACHE_DIR)
endif

CARGO_HOST_CONFIG_VARS= \
	$(RUST_SCCACHE_VARS) \
	CARGO_HOME=$(CARGO_HOME)

CARGO_HOST_PROFILE:=release

CARGO_PKG_CONFIG_VARS= \
	$(RUST_SCCACHE_VARS) \
	CARGO_BUILD_TARGET=$(RUSTC_TARGET_ARCH) \
	CARGO_HOME=$(CARGO_HOME) \
	CARGO_PROFILE_RELEASE_CODEGEN_UNITS=1 \
	CARGO_PROFILE_RELEASE_DEBUG=false \
	CARGO_PROFILE_RELEASE_DEBUG_ASSERTIONS=false \
	CARGO_PROFILE_RELEASE_LTO=true \
	CARGO_PROFILE_RELEASE_OPT_LEVEL=z \
	CARGO_PROFILE_RELEASE_OVERFLOW_CHECKS=true \
	CARGO_PROFILE_RELEASE_PANIC=unwind \
	CARGO_PROFILE_RELEASE_RPATH=false \
	CARGO_TARGET_$(RUSTC_TARGET_UPPER)_LINKER=$(TARGET_CC_NOCACHE) \
	RUSTFLAGS="$(CARGO_RUSTFLAGS)" \
	TARGET_CC=$(TARGET_CC_NOCACHE) \
	TARGET_CFLAGS="$(TARGET_CFLAGS) $(RUSTC_CFLAGS)"

CARGO_PKG_PROFILE:=$(if $(CONFIG_DEBUG),dev,release)

CARGO_RUSTFLAGS+=-Clink-arg=-fuse-ld=$(TARGET_LINKER)

# Host prebuilt binary hashes (standalone installer .sha256 from static.rust-lang.org/dist/)
RUST_BIN_SUM_AARCH64_APPLE_DARWIN:=30976378b6aaefd1861ba475905c6ba22a44c981418ce52285006af26337f98c
RUST_BIN_SUM_AARCH64_UNKNOWN_LINUX_GNU:=a48fb1e853be56ce9b8e2751f5464dbd5e16440cd81e237920f3a5e7e806333e
RUST_BIN_SUM_AARCH64_UNKNOWN_LINUX_MUSL:=39d40844c2257f0eb83d62fbbf24d2574f3c40f85c7a740d0ea649f1b6ccc973
RUST_BIN_SUM_X86_64_APPLE_DARWIN:=13b237d0294bad3bb7b18d559517947ed8348ea25812fa3b468c904996f80e34
RUST_BIN_SUM_X86_64_UNKNOWN_LINUX_GNU:=231fcae47ee950621374725b5fc3b5441d2fbda2955ac45dd7dc816d8876cfe7
RUST_BIN_SUM_X86_64_UNKNOWN_LINUX_MUSL:=da398394254c8ffd29d1e397dfc00941dfb6a631bc7254cf797481fec8df6f5a

RUST_BIN_SUM:=$(RUST_BIN_SUM_$(call toupper,$(subst -,_,$(RUSTC_HOST_ARCH))))

# Target std prebuilt hashes (from channel-rust-1.99.1.toml xz_hash)
RUST_STD_SUM_AARCH64_UNKNOWN_LINUX_GNU:=e25668477083d6a9ddb87b9beb9c00742225f38233ccb4bfba3afa7a07427f52
RUST_STD_SUM_AARCH64_UNKNOWN_LINUX_MUSL:=2f3eb0d0610e2b7f6b2121d106e2490ac648decfa0c09b30873bdfc60de6c1ab
RUST_STD_SUM_ARM_UNKNOWN_LINUX_GNUEABI:=fb93e9715ef14ed17fd6922dd200d14cfe855b46c4fa1e8a03ee85ca75646022
RUST_STD_SUM_ARM_UNKNOWN_LINUX_GNUEABIHF:=32278298365b7b78cf5b67ec34bf5e11821679dfea8a6d867725af860c4cbe50
RUST_STD_SUM_ARM_UNKNOWN_LINUX_MUSLEABI:=f66cb84ada451344f46757c72d1bfa5a34e8f174affe67b7fa9c3b2d8a033e26
RUST_STD_SUM_ARM_UNKNOWN_LINUX_MUSLEABIHF:=74adeec515565c17242c8fafedbda40a30a49f85e9510fc60013cbc539f83782
RUST_STD_SUM_ARMV5TE_UNKNOWN_LINUX_GNUEABI:=16147e552d542b300e5068075ef0e38600e989816e794afe18e34b6247192598
RUST_STD_SUM_ARMV5TE_UNKNOWN_LINUX_MUSLEABI:=34e0afee32cf40fac1283c2a4c71c265a93973b4df1a774889e89de138bd510d
RUST_STD_SUM_ARMV7_UNKNOWN_LINUX_GNUEABIHF:=53fdf6581a24f510def5173813a0d23518a8cde547b9fbf4876499f19feda18c
RUST_STD_SUM_ARMV7_UNKNOWN_LINUX_MUSLEABIHF:=edccfaef9195cb74b5c33541e587629f92433f59fb5e4bbb7b8293f966ecd60a
RUST_STD_SUM_I586_UNKNOWN_LINUX_GNU:=0a0d01938461c2cea3d9771f6a2f9b0bc42e8adbf5b45ecb9cb92b5371688ddf
RUST_STD_SUM_I586_UNKNOWN_LINUX_MUSL:=df81795fc9a09a75f3387ede4b17a10bcfb55ab04a8e358d05172479683bec8d
RUST_STD_SUM_LOONGARCH64_UNKNOWN_LINUX_GNU:=6400e6880a1f8183bba1a8b939cb1c6d189ab64e4aff4f246c00161941ee76e8
RUST_STD_SUM_LOONGARCH64_UNKNOWN_LINUX_MUSL:=3053ebe881b3434879a934012c4a61b1fa94a0aec922115a574cc81e8e3ca15e
RUST_STD_SUM_POWERPC_UNKNOWN_LINUX_GNU:=25d05cf16db111ecfe7dd8e1a3d61d144f2348e87dafeb07ff3cf402e3196cfd
RUST_STD_SUM_POWERPC64_UNKNOWN_LINUX_GNU:=58f8526a50eb47eb106130a29e77c97e3c5fd60af41e8a16a63d39673f9aa33d
RUST_STD_SUM_POWERPC64_UNKNOWN_LINUX_MUSL:=5979c6f3c06a71007a28023359cd61fe11eba35286c7ae4bb0bf5e19cda45c71
RUST_STD_SUM_RISCV64GC_UNKNOWN_LINUX_GNU:=0fe2aa8294281e16886a101466160ec460ed99e51c8af11e1c76f88f8bd0de6b
RUST_STD_SUM_RISCV64GC_UNKNOWN_LINUX_MUSL:=59797f5c7c87ef38c1d202576cb6fb9c6423730d8efcaf2fab7c367d2d878a39
RUST_STD_SUM_X86_64_UNKNOWN_LINUX_GNU:=109b074225bf5b9ea3820890876bfdf4ed161adbfaf94b2b4b5984c85ee5d958
RUST_STD_SUM_X86_64_UNKNOWN_LINUX_MUSL:=1dd241eaeb19ff3b5180461c77bdee93d6cafc669eda9de834e7c06b0ec3ca95

RUST_STD_SUM:=$(RUST_STD_SUM_$(call toupper,$(subst -,_,$(RUSTC_TARGET_ARCH))))

# Rust source component hash from channel-rust-1.99.1.toml xz_hash
RUST_SRC_COMPONENT_SUM:=e485a88c45db546b73571df7bebfcb4454ba4fb552c492e25fc5b00eeb5bf22d

RUST_SRC_HASH:=6451598a99e77f07571960f6b21d577399d3a30f33e80cbd2e3a4aae6535d265
