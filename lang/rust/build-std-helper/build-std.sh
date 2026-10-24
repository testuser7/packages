#!/bin/bash
set -eu

: "${RUST_SRC_ARCHIVE:?RUST_SRC_ARCHIVE is required}"
: "${RUST_STD_WORK_DIR:?RUST_STD_WORK_DIR is required}"
: "${RUST_STD_LIB_DIR:?RUST_STD_LIB_DIR is required}"
: "${RUST_STD_SRC_INSTALL_DIR:?RUST_STD_SRC_INSTALL_DIR is required}"
: "${RUST_STD_TARGET:?RUST_STD_TARGET is required}"
: "${RUST_STD_CARGO:?RUST_STD_CARGO is required}"
: "${RUST_STD_CARGO_HOME:?RUST_STD_CARGO_HOME is required}"
: "${RUST_STD_TAR:?RUST_STD_TAR is required}"
: "${RUST_STD_LINKER:?RUST_STD_LINKER is required}"
: "${RUST_STD_RUSTFLAGS:?RUST_STD_RUSTFLAGS is required}"

phase=
run_phase() {
	phase=$1
	shift
	printf 'rust: %s\n' "$phase" >&2
	"$@" || {
		status=$?
		printf 'rust: %s failed (exit %s)\n' "$phase" "$status" >&2
		exit "$status"
	}
}

src_dir="$RUST_STD_WORK_DIR/src"
target_dir="$RUST_STD_WORK_DIR/target"
script_dir="$(cd -- "$(dirname -- "$0")" && pwd)"

run_phase "preparing source and target directories" rm -rf "$RUST_STD_WORK_DIR"
run_phase "creating source directory" mkdir -p "$src_dir"
run_phase "extracting Rust source archive $RUST_SRC_ARCHIVE" \
	"$RUST_STD_TAR" -xf "$RUST_SRC_ARCHIVE" -C "$src_dir" --strip-components=1

if [ ! -d "$src_dir/library" ]; then
	printf 'rust: Rust source archive does not contain library/: %s\n' "$RUST_SRC_ARCHIVE" >&2
	exit 1
fi

run_phase "installing Rust standard-library sources" mkdir -p "$RUST_STD_SRC_INSTALL_DIR"
run_phase "replacing installed standard-library sources" rm -rf "$RUST_STD_SRC_INSTALL_DIR/library"
run_phase "copying standard-library sources" cp -a "$src_dir/library" "$RUST_STD_SRC_INSTALL_DIR/library"
run_phase "creating target rustlib directory" mkdir -p "$RUST_STD_LIB_DIR"

target_key=$(printf '%s' "$RUST_STD_TARGET" | tr '[:lower:]-' '[:upper:]_')
run_phase "building target standard library for $RUST_STD_TARGET" \
	env \
		CARGO_HOME="$RUST_STD_CARGO_HOME" \
		CARGO_NET_OFFLINE=false \
		CARGO_BUILD_TARGET="$RUST_STD_TARGET" \
		"CARGO_TARGET_${target_key}_LINKER=$RUST_STD_LINKER" \
		"CARGO_TARGET_${target_key}_RUSTFLAGS=$RUST_STD_RUSTFLAGS" \
		"$RUST_STD_CARGO" build \
		--manifest-path "$script_dir/Cargo.toml" \
		--target "$RUST_STD_TARGET" \
		--target-dir "$target_dir" \
		--release \
		-Z build-std=core,alloc,std \
		--lib

deps="$target_dir/$RUST_STD_TARGET/release/deps"
artifact_list="$RUST_STD_WORK_DIR/std-artifacts.list"
run_phase "discovering target standard-library artifacts" \
	find "$deps" -type f \
		\( -name 'libaddr2line-*' -o -name 'libadler-*' -o -name 'libadler2-*' \
		-o -name 'libcfg_if-*' -o -name 'libcore-*' -o -name 'liballoc-*' \
		-o -name 'libstd-*' -o -name 'libgimli-*' -o -name 'libhashbrown-*' \
		-o -name 'liblibc-*' -o -name 'libmemchr-*' -o -name 'libminiz_oxide-*' \
		-o -name 'libobject-*' -o -name 'libcompiler_builtins-*' \
		-o -name 'libpanic_unwind-*' -o -name 'libpanic_abort-*' \
		-o -name 'librustc_demangle-*' -o -name 'libstd_detect-*' \
		-o -name 'libunwind-*' \) \
		\( -name '*.rlib' -o -name '*.rmeta' \) \
		-print0 > "$artifact_list"

mapfile -d '' artifacts < "$artifact_list"
if [ "${#artifacts[@]}" -eq 0 ]; then
	printf 'rust: no target standard-library artifacts found in %s\n' "$deps" >&2
	exit 1
fi

run_phase "installing ${#artifacts[@]} target standard-library artifacts" \
	cp -- "${artifacts[@]}" "$RUST_STD_LIB_DIR/"
