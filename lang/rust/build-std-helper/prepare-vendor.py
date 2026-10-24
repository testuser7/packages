#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only

import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import shutil
import subprocess
import tarfile
import tomllib
from urllib.parse import quote


def fail(message):
    raise SystemExit(f"rust: {message}")


def extract_crate(archive, destination, expected_root):
    destination.mkdir(parents=True, exist_ok=True)
    with tarfile.open(archive, "r:gz") as crate:
        seen = set()
        for member in crate.getmembers():
            path = PurePosixPath(member.name)
            if path.is_absolute() or ".." in path.parts or not path.parts:
                fail(f"unsafe path in crate archive {archive}: {member.name}")
            if path.parts[0] != expected_root:
                fail(f"unexpected root in crate archive {archive}: {member.name}")
            relative = Path(*path.parts[1:])
            if not relative.parts:
                continue
            if relative in seen:
                fail(f"duplicate path in crate archive {archive}: {member.name}")
            seen.add(relative)
            output = destination / relative
            if member.isdir():
                output.mkdir(parents=True, exist_ok=True)
            elif member.isfile():
                output.parent.mkdir(parents=True, exist_ok=True)
                source = crate.extractfile(member)
                if source is None:
                    fail(f"cannot read crate member {member.name}")
                with source, output.open("wb") as target:
                    shutil.copyfileobj(source, target)
                output.chmod(member.mode & 0o777)
            else:
                fail(f"unsupported file type in crate archive {archive}: {member.name}")


def file_checksums(directory):
    checksums = {}
    for path in sorted(directory.rglob("*")):
        if path.is_symlink():
            fail(f"symlink in vendored crate is unsupported: {path}")
        if path.is_file():
            relative = path.relative_to(directory).as_posix()
            checksums[relative] = hashlib.sha256(path.read_bytes()).hexdigest()
    return checksums


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", required=True, type=Path)
    parser.add_argument("--download-dir", required=True, type=Path)
    parser.add_argument("--download-script", required=True)
    parser.add_argument("--mkhash", required=True)
    parser.add_argument("--vendor-dir", required=True, type=Path)
    parser.add_argument("--cargo-home", required=True, type=Path)
    args = parser.parse_args()

    with tarfile.open(args.source, "r:xz") as source:
        locks = [
            member for member in source.getmembers()
            if PurePosixPath(member.name).parts[-2:] == ("library", "Cargo.lock")
        ]
        if len(locks) != 1:
            fail(f"expected one library/Cargo.lock in {args.source}, found {len(locks)}")
        lock_file = source.extractfile(locks[0])
        if lock_file is None:
            fail(f"cannot read library/Cargo.lock from {args.source}")
        lock = tomllib.loads(lock_file.read().decode("utf-8"))

    packages = {}
    for package in lock.get("package", []):
        package_source = package.get("source")
        if package_source is None:
            continue
        if package_source != "registry+https://github.com/rust-lang/crates.io-index":
            fail(f"unsupported Cargo.lock source for {package['name']}: {package_source}")
        checksum = package.get("checksum")
        if not checksum:
            fail(f"missing checksum in Cargo.lock for {package['name']} {package['version']}")
        packages[(package["name"], package["version"])] = checksum

    if not packages:
        fail(f"no crates.io dependencies found in {args.source}")

    args.download_dir.mkdir(parents=True, exist_ok=True)
    if args.vendor_dir.exists():
        shutil.rmtree(args.vendor_dir)
    args.vendor_dir.mkdir(parents=True)
    environment = os.environ.copy()
    environment["MKHASH"] = args.mkhash

    for (name, version), checksum in sorted(packages.items()):
        crate_file = f"{name}-{version}.crate"
        crate_path = args.download_dir / crate_file
        crate_url = f"https://static.crates.io/crates/{quote(name, safe='-')}/"
        print(f"rust: downloading pinned Cargo dependency {crate_file}", flush=True)
        try:
            subprocess.run(
                [
                    args.download_script,
                    str(args.download_dir),
                    crate_file,
                    checksum,
                    "",
                    crate_url,
                ],
                check=True,
                env=environment,
            )
        except subprocess.CalledProcessError as error:
            fail(f"OpenWrt download failed for pinned dependency {crate_file} (exit {error.returncode})")
        crate_dir = args.vendor_dir / f"{name}-{version}"
        extract_crate(crate_path, crate_dir, f"{name}-{version}")
        metadata = {
            "files": file_checksums(crate_dir),
            "package": checksum,
        }
        (crate_dir / ".cargo-checksum.json").write_text(
            json.dumps(metadata, sort_keys=True, separators=(",", ":")) + "\n",
            encoding="utf-8",
        )

    args.cargo_home.mkdir(parents=True, exist_ok=True)
    cargo_config = (
        "[net]\n"
        "offline = true\n"
        "\n"
        "[source.crates-io]\n"
        'replace-with = "rust-std-vendored-sources"\n'
        "\n"
        "[source.rust-std-vendored-sources]\n"
        f"directory = {json.dumps(str(args.vendor_dir.resolve()))}\n"
    )
    (args.cargo_home / "config.toml").write_text(cargo_config, encoding="utf-8")


if __name__ == "__main__":
    main()
