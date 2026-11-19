#!/usr/bin/env python3
"""
Antigravity Auto-Updater Script
Automatically checks the official Antigravity update server for new releases,
or updates from a specific version / tarball URL.

Update server endpoints discovered from resources/app.asar & app-update.yml:
- Updater API: https://antigravity-hub-auto-updater-974169037036.us-central1.run.app/releases
- Artifact GCS: https://storage.googleapis.com/antigravity-public/antigravity-hub/<version>-<execution_id>/linux-<arch>/Antigravity.tar.gz
"""

import argparse
import json
import os
import platform
import re
import shutil
import struct
import sys
import tarfile
import tempfile
import urllib.error
import urllib.request
from pathlib import Path

UPDATER_BASE_URL = "https://antigravity-hub-auto-updater-974169037036.us-central1.run.app"
RELEASES_API_URL = f"{UPDATER_BASE_URL}/releases"
PUBLIC_ARTIFACT_BASE_URL = "https://storage.googleapis.com/antigravity-public"

DEFAULT_INSTALL_DIR = Path.home() / "opt" / "antigravity"
DEFAULT_BACKUP_DIR = Path.home() / "opt" / "antigravity.old"


def log_info(msg: str) -> None:
    print(f"\033[1;34m[INFO]\033[0m {msg}")


def log_success(msg: str) -> None:
    print(f"\033[1;32m[OK]\033[0m   {msg}")


def log_warn(msg: str) -> None:
    print(f"\033[1;33m[WARN]\033[0m {msg}")


def log_error(msg: str) -> None:
    print(f"\033[1;31m[ERR]\033[0m  {msg}", file=sys.stderr)


def parse_version(v: str) -> tuple[int, ...]:
    """Parse version string like '2.23.1' into tuple of ints for comparison."""
    parts = []
    for part in v.split("."):
        m = re.match(r"^(\d+)", part)
        parts.append(int(m.group(1)) if m else 0)
    return tuple(parts)


def get_installed_version(install_dir: Path) -> str | None:
    """Extract current installed version from resources/app.asar."""
    asar_path = install_dir / "resources" / "app.asar"
    if not asar_path.is_file():
        return None

    try:
        with open(asar_path, "rb") as f:
            header_data = f.read(16)
            if len(header_data) < 16:
                return None
            _, _, _, str_len = struct.unpack("<IIII", header_data)
            header_json = f.read(str_len).decode("utf-8", errors="ignore")
            header = json.loads(header_json)

            pkg_info = header.get("files", {}).get("package.json")
            if pkg_info and "offset" in pkg_info and "size" in pkg_info:
                # Calculate data offset (16 + aligned header size)
                # Fallback: search directly for productName: Antigravity
                pass

            f.seek(0)
            raw = f.read()
            m = re.search(
                rb'"name"\s*:\s*"antigravity"[\s\S]{0,200}?"version"\s*:\s*"([^"]+)"',
                raw,
            )
            if m:
                return m.group(1).decode("utf-8")
    except Exception as e:
        log_warn(f"Could not read version from {asar_path}: {e}")

    return None


def fetch_releases() -> list[dict[str, str]]:
    """Fetch available releases from Antigravity's auto-updater Cloud Run service."""
    req = urllib.request.Request(
        RELEASES_API_URL,
        headers={"User-Agent": "Antigravity-Updater/1.0"},
    )
    with urllib.request.urlopen(req, timeout=15) as resp:
        data = json.loads(resp.read().decode("utf-8"))
        if not isinstance(data, list):
            raise ValueError("Unexpected response format from /releases API")
        return data


def detect_arch() -> str:
    machine = platform.machine().lower()
    if machine in ("aarch64", "arm64"):
        return "arm64"
    return "x64"


def build_artifact_url(version: str, execution_id: str, arch: str | None = None) -> str:
    arch = arch or detect_arch()
    return (
        f"{PUBLIC_ARTIFACT_BASE_URL}/antigravity-hub/"
        f"{version}-{execution_id}/linux-{arch}/Antigravity.tar.gz"
    )


def download_with_progress(url: str, dest: Path) -> None:
    log_info(f"Downloading: {url}")
    req = urllib.request.Request(url, headers={"User-Agent": "Antigravity-Updater/1.0"})
    with urllib.request.urlopen(req, timeout=60) as resp, open(dest, "wb") as out:
        total = int(resp.headers.get("Content-Length", 0))
        downloaded = 0
        chunk_size = 1024 * 256  # 256 KB
        while True:
            chunk = resp.read(chunk_size)
            if not chunk:
                break
            out.write(chunk)
            downloaded += len(chunk)
            if total > 0:
                pct = downloaded * 100 / total
                mb_done = downloaded / (1024 * 1024)
                mb_total = total / (1024 * 1024)
                print(
                    f"\r  -> {mb_done:.1f} / {mb_total:.1f} MB ({pct:.1f}%)",
                    end="",
                    flush=True,
                )
        if total > 0:
            print()


def install_tarball(tarball_path: Path, install_dir: Path, backup_dir: Path) -> str | None:
    with tempfile.TemporaryDirectory(prefix="antigravity_extract_") as extract_tmp:
        extract_path = Path(extract_tmp)
        log_info("Extracting archive...")
        with tarfile.open(tarball_path, "r:gz") as tar:
            tar.extractall(path=extract_path, filter="fully_trusted")

        subdirs = [d for d in extract_path.iterdir() if d.is_dir()]
        src_dir = subdirs[0] if len(subdirs) == 1 else extract_path

        binary_path = src_dir / "antigravity"
        if not binary_path.is_file():
            raise RuntimeError(f"Could not find 'antigravity' binary inside extracted archive ({src_dir})")

        new_ver = get_installed_version(src_dir)

        install_dir.parent.mkdir(parents=True, exist_ok=True)
        if install_dir.exists():
            if backup_dir.exists():
                log_info(f"Removing old backup at {backup_dir}...")
                shutil.rmtree(backup_dir)
            log_info(f"Backing up current installation to {backup_dir}...")
            shutil.move(str(install_dir), str(backup_dir))

        log_info(f"Installing new version into {install_dir}...")
        shutil.move(str(src_dir), str(install_dir))

        # Ensure executable permissions
        for bin_rel in ("antigravity", "chrome-sandbox", "chrome_crashpad_handler", "resources/bin/language_server"):
            target = install_dir / bin_rel
            if target.is_file():
                target.chmod(target.stat().st_mode | 0o111)

        return new_ver


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Check and update Antigravity from official Google Cloud release server."
    )
    parser.add_argument(
        "target",
        nargs="?",
        help="Optional: Direct .tar.gz URL or specific version (e.g. '2.23.1'). Defaults to latest.",
    )
    parser.add_argument(
        "-c",
        "--check",
        action="store_true",
        help="Only check for updates without downloading or installing.",
    )
    parser.add_argument(
        "-l",
        "--list",
        action="store_true",
        help="List recent available releases from the server.",
    )
    parser.add_argument(
        "-f",
        "--force",
        action="store_true",
        help="Force reinstall even if already on the target/latest version.",
    )
    parser.add_argument(
        "--install-dir",
        type=Path,
        default=DEFAULT_INSTALL_DIR,
        help=f"Installation directory (default: {DEFAULT_INSTALL_DIR})",
    )
    parser.add_argument(
        "--backup-dir",
        type=Path,
        default=DEFAULT_BACKUP_DIR,
        help=f"Backup directory (default: {DEFAULT_BACKUP_DIR})",
    )
    args = parser.parse_args()

    current_ver = get_installed_version(args.install_dir)
    log_info(f"Install directory : {args.install_dir}")
    log_info(f"Current version   : {current_ver or 'Not installed / Unknown'}")

    # Direct URL mode
    if args.target and (args.target.startswith("http://") or args.target.startswith("https://")):
        url = args.target
        target_ver = None
    else:
        log_info(f"Querying release server: {RELEASES_API_URL}")
        try:
            releases = fetch_releases()
        except Exception as e:
            log_error(f"Failed to query releases API: {e}")
            return 1

        if not releases:
            log_error("No releases returned from server.")
            return 1

        if args.list:
            print("\nAvailable releases (top 15):")
            for r in releases[:15]:
                v = r.get("version", "?")
                eid = r.get("execution_id", "?")
                marker = " (installed)" if v == current_ver else ""
                print(f"  - {v:<10} [build: {eid}]{marker}")
            return 0

        if args.target:
            match = next((r for r in releases if r.get("version") == args.target), None)
            if not match:
                log_error(f"Version '{args.target}' not found on release server.")
                return 1
        else:
            # Sort by semantic version just in case, though API returns newest first
            match = max(releases, key=lambda r: parse_version(r.get("version", "0.0.0")))

        target_ver = match["version"]
        exec_id = match["execution_id"]
        url = build_artifact_url(target_ver, exec_id)

        log_info(f"Latest/Target ver : {target_ver} (execution_id: {exec_id})")
        log_info(f"Artifact URL      : {url}")

        if current_ver and target_ver == current_ver and not args.force:
            log_success(f"Antigravity is already up to date (v{current_ver}). Use --force to reinstall.")
            return 0

        if args.check:
            if current_ver and parse_version(target_ver) > parse_version(current_ver):
                log_info(f"Update available: {current_ver} -> {target_ver}")
            return 0

    with tempfile.TemporaryDirectory(prefix="antigravity_dl_") as dl_tmp:
        tarball_path = Path(dl_tmp) / "Antigravity.tar.gz"
        try:
            download_with_progress(url, tarball_path)
            installed_ver = install_tarball(tarball_path, args.install_dir, args.backup_dir)
        except Exception as e:
            log_error(f"Update failed: {e}")
            return 1

    final_ver = installed_ver or target_ver or "unknown"
    log_success(f"Successfully updated Antigravity to v{final_ver}!")
    log_info(f"Previous version backed up at: {args.backup_dir}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
