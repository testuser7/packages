#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only

set -euo pipefail

target=${1:?Rust target triple is required}
work_dir=${2:?build directory is required}
lib_dir=${3:?target rustlib directory is required}
cargo=${CARGO:-cargo}
rustc=${RUSTC:-rustc}
script_dir=$(cd -- "$(dirname -- "$0")" && pwd)
helper_dir="$work_dir/helper"
manifest="$helper_dir/Cargo.toml"
target_dir="$work_dir/target"
sysroot=$("$rustc" --print sysroot)
rust_src="$sysroot/lib/rustlib/src/rust/library"

if [[ ! -f "$rust_src/Cargo.lock" ]]; then
	echo "rust: rust-src component is missing from sysroot: $rust_src" >&2
	exit 1
fi

mkdir -p "$helper_dir/src"
cp "$script_dir/Cargo.toml" "$manifest"
cp "$script_dir/src/lib.rs" "$helper_dir/src/lib.rs"

printf 'rust: building target standard library for %s offline\n' "$target" >&2
"$cargo" build \
	-Z build-std=core,alloc,std \
	--manifest-path "$manifest" \
	--target "$target" \
	--target-dir "$target_dir" \
	--release \
	--lib

deps="$target_dir/$target/release/deps"
mkdir -p "$lib_dir"
shopt -s nullglob
crates=(
	addr2line adler adler2 cfg_if core alloc std gimli hashbrown libc memchr
	miniz_oxide object compiler_builtins panic_unwind panic_abort
	rustc_demangle std_detect unwind
)
artifacts=()
for crate in "${crates[@]}"; do
	for artifact in "$deps/lib$crate-"*.rlib "$deps/lib$crate-"*.rmeta; do
		artifacts+=("$artifact")
	done
done

if ((${#artifacts[@]} == 0)); then
	echo "rust: no target standard-library artifacts found in $deps" >&2
	exit 1
fi

printf 'rust: installing %s target standard-library artifacts\n' \
	"${#artifacts[@]}" >&2
cp -- "${artifacts[@]}" "$lib_dir/"
