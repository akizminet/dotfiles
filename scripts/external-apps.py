#!/usr/bin/env python3
"""Manage official self-updating external apps declared in external-apps.nix."""

from __future__ import annotations

import argparse
import json
import os
import platform
import shutil
import subprocess
import sys
import tarfile
import tempfile
import urllib.request
from pathlib import Path

JETBRAINS_RELEASES_URL = (
    "https://data.services.jetbrains.com/products/releases"
    "?code={code}&latest=true&type=release"
)


def home_dir() -> Path:
    return Path.home()


def state_file_path() -> Path:
    xdg_state = os.environ.get("XDG_STATE_HOME")
    base = Path(xdg_state) if xdg_state else home_dir() / ".local" / "state"
    return base / "dotfiles" / "external-apps.json"


def load_manifest(manifest_path: Path) -> tuple[list[str], dict[str, dict]]:
    data = json.loads(manifest_path.read_text(encoding="utf-8"))
    enabled = list(data.get("enabled", []))
    catalog = dict(data.get("catalog", {}))
    return enabled, catalog


def load_state() -> set[str]:
    path = state_file_path()
    if not path.is_file():
        return set()
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
        apps = data.get("apps", [])
        return set(apps) if isinstance(apps, list) else set()
    except Exception:
        return set()


def save_state(apps: set[str]) -> None:
    path = state_file_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    payload = {"apps": sorted(apps)}
    path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")


def resolve_home_rel(rel: str) -> Path:
    rel_path = Path(rel)
    if not rel or rel_path.is_absolute() or ".." in rel_path.parts:
        raise ValueError(f"Unsafe relative path in manifest: {rel!r}")
    home_resolved = home_dir().resolve()
    candidate = Path(os.path.abspath(str(home_dir() / rel_path)))
    if candidate == home_dir() or candidate == home_resolved:
        raise ValueError(f"Refusing to operate on home directory itself: {rel!r}")
    if not candidate.parent.resolve().is_relative_to(home_resolved):
        raise ValueError(f"Path escapes home directory: {rel!r}")
    return candidate


def path_present(path: Path) -> bool:
    return path.is_symlink() or path.exists()


def is_app_installed(spec: dict) -> bool:
    binary = resolve_home_rel(spec["binary"])
    return binary.is_file() and os.access(binary, os.X_OK)


def existing_app_paths(spec: dict, purge: bool) -> list[Path]:
    rels = list(spec.get("remove_paths", []))
    if purge:
        rels.extend(spec.get("purge_paths", []))
    found: list[Path] = []
    seen: set[Path] = set()
    for rel in rels:
        target = resolve_home_rel(rel)
        if target not in seen and path_present(target):
            seen.add(target)
            found.append(target)
    return found


def delete_path(target: Path) -> None:
    if target.is_symlink() or target.is_file():
        target.unlink()
    elif target.is_dir():
        shutil.rmtree(target)


def confirm_removal(label: str, targets: list[Path], yes: bool) -> bool:
    print(f"Paths to remove for '{label}':")
    for target in targets:
        print(f"  - {target}")
    if yes:
        return True
    if not sys.stdin.isatty():
        print(
            "Refusing to remove paths without confirmation; re-run with --yes.",
            file=sys.stderr,
        )
        return False
    reply = input(f"Remove {len(targets)} path(s) for '{label}'? [y/N] ").strip().lower()
    return reply in ("y", "yes")


def install_jetbrains(spec: dict, update_only: bool, dry_run: bool) -> int:
    code = spec["product_code"]
    install_dir = resolve_home_rel(spec["install_dir"])
    backup_dir = Path(f"{install_dir}.old")
    arch_key = (
        "linuxARM64"
        if platform.machine().lower() in ("aarch64", "arm64")
        else "linux"
    )

    if dry_run:
        action = "update" if update_only else "install"
        print(
            f"[DRY-RUN] Would {action} JetBrains {code} ({arch_key}) into {install_dir}"
        )
        return 0

    current_ver = None
    product_info = install_dir / "product-info.json"
    if product_info.is_file():
        try:
            current_ver = json.loads(product_info.read_text(encoding="utf-8")).get(
                "version"
            )
        except Exception:
            current_ver = None

    api_url = JETBRAINS_RELEASES_URL.format(code=code)
    req = urllib.request.Request(api_url, headers={"User-Agent": "dotfiles-external-apps/1.0"})
    with urllib.request.urlopen(req, timeout=20) as resp:
        payload = json.loads(resp.read().decode("utf-8"))

    releases = payload.get(code) or []
    if not releases:
        print(f"[ERR] No releases found for JetBrains product {code}.", file=sys.stderr)
        return 1

    latest = releases[0]
    target_ver = latest.get("version")
    download_info = (latest.get("downloads") or {}).get(arch_key)
    if not download_info or not download_info.get("link"):
        print(
            f"[ERR] No download link for JetBrains {code} ({arch_key}).",
            file=sys.stderr,
        )
        return 1

    if update_only and current_ver and target_ver == current_ver:
        print(f"[OK] JetBrains {code} is already up to date (v{current_ver}).")
        return 0

    url = download_info["link"]
    print(f"[INFO] Downloading JetBrains {code} v{target_ver}: {url}")
    with tempfile.TemporaryDirectory(prefix="jetbrains_dl_") as tmp_str:
        tmp_dir = Path(tmp_str)
        archive_path = tmp_dir / "product.tar.gz"
        dl_req = urllib.request.Request(
            url, headers={"User-Agent": "dotfiles-external-apps/1.0"}
        )
        with urllib.request.urlopen(dl_req, timeout=120) as resp, open(
            archive_path, "wb"
        ) as out:
            shutil.copyfileobj(resp, out, length=256 * 1024)

        extract_dir = tmp_dir / "extract"
        extract_dir.mkdir()
        print("[INFO] Extracting archive...")
        with tarfile.open(archive_path, "r:gz") as tar:
            tar.extractall(path=extract_dir, filter="fully_trusted")

        subdirs = [d for d in extract_dir.iterdir() if d.is_dir()]
        src_dir = subdirs[0] if len(subdirs) == 1 else extract_dir

        install_dir.parent.mkdir(parents=True, exist_ok=True)
        if install_dir.exists():
            if backup_dir.exists():
                shutil.rmtree(backup_dir)
            shutil.move(str(install_dir), str(backup_dir))

        try:
            shutil.move(str(src_dir), str(install_dir))
        except Exception:
            if not install_dir.exists() and backup_dir.exists():
                shutil.move(str(backup_dir), str(install_dir))
            raise

        if backup_dir.exists():
            shutil.rmtree(backup_dir)

    print(f"[OK] Installed JetBrains {code} v{target_ver} into {install_dir}.")
    return 0


def run_action(action_spec: dict, update_only: bool, dry_run: bool) -> int:
    kind = action_spec["type"]
    if kind == "shell":
        cmd = action_spec["command"]
        if dry_run:
            print(f"[DRY-RUN] Would run: bash -c {cmd!r}")
            return 0
        proc = subprocess.run(["bash", "-c", cmd], check=False)
        return proc.returncode
    if kind == "command":
        argv = list(action_spec["argv"])
        if dry_run:
            print(f"[DRY-RUN] Would run: {' '.join(argv)}")
            return 0
        proc = subprocess.run(argv, check=False)
        return proc.returncode
    if kind == "jetbrains":
        return install_jetbrains(action_spec, update_only=update_only, dry_run=dry_run)

    print(f"[ERR] Unsupported action type: {kind}", file=sys.stderr)
    return 1


def cmd_status(enabled: list[str], catalog: dict[str, dict]) -> int:
    state_apps = load_state()
    enabled_set = set(enabled)

    print(
        f"{'APP':<14} {'STATE':<21} {'STATUS':<11} {'LOCATION':<24} {'UPDATER'}"
    )
    print(
        f"{'---':<14} {'-----':<21} {'------':<11} {'--------':<24} {'-------'}"
    )

    for app_id in enabled:
        spec = catalog[app_id]
        status = "installed" if is_app_installed(spec) else "missing"
        print(
            f"{app_id:<14} {'enabled':<21} {status:<11} "
            f"{spec['location']:<24} {spec['updater_label']}"
        )

    for app_id, spec in catalog.items():
        if app_id in enabled_set:
            continue
        orphaned_paths = existing_app_paths(spec, purge=False)
        if orphaned_paths or app_id in state_apps:
            status = "orphaned" if orphaned_paths else "stale-state"
            print(
                f"{app_id:<14} {'removed-from-config':<21} {status:<11} "
                f"{spec['location']:<24} {spec['updater_label']}"
            )
    return 0


def cmd_install(
    target: str, enabled: list[str], catalog: dict[str, dict], dry_run: bool
) -> int:
    if target == "all":
        targets = [app_id for app_id in enabled if not is_app_installed(catalog[app_id])]
        if not targets:
            print("[OK] All enabled external apps are already installed.")
            return 0
    else:
        if target not in catalog:
            print(f"[ERR] Unknown external app: {target}", file=sys.stderr)
            return 1
        if is_app_installed(catalog[target]):
            print(f"[OK] {target} is already installed.")
            return 0
        targets = [target]

    state_apps = load_state()
    exit_code = 0
    for app_id in targets:
        print(f"[INFO] Installing {app_id}...")
        rc = run_action(catalog[app_id]["installer"], update_only=False, dry_run=dry_run)
        if rc != 0:
            print(f"[ERR] Failed to install {app_id} (exit {rc}).", file=sys.stderr)
            exit_code = rc
        elif not dry_run:
            state_apps.add(app_id)
            save_state(state_apps)
    return exit_code


def cmd_update(
    target: str, enabled: list[str], catalog: dict[str, dict], dry_run: bool
) -> int:
    if target == "all":
        targets = []
        for app_id in enabled:
            if is_app_installed(catalog[app_id]):
                targets.append(app_id)
            else:
                print(f"[SKIP] {app_id} is not installed.")
        if not targets:
            print("[INFO] No installed external apps to update.")
            return 0
    else:
        if target not in catalog:
            print(f"[ERR] Unknown external app: {target}", file=sys.stderr)
            return 1
        if not is_app_installed(catalog[target]):
            print(
                f"[ERR] {target} is not installed. Run 'external-apps install {target}' first.",
                file=sys.stderr,
            )
            return 1
        targets = [target]

    exit_code = 0
    for app_id in targets:
        print(f"[INFO] Updating {app_id}...")
        rc = run_action(catalog[app_id]["updater"], update_only=True, dry_run=dry_run)
        if rc != 0:
            print(f"[ERR] Failed to update {app_id} (exit {rc}).", file=sys.stderr)
            exit_code = rc
    return exit_code


def remove_single_app(
    app_id: str, spec: dict, purge: bool, dry_run: bool, yes: bool
) -> tuple[bool, int]:
    targets = existing_app_paths(spec, purge=purge)
    if not targets:
        print(f"[INFO] No files on disk to remove for {app_id}.")
        return True, 0

    if dry_run:
        print(f"[DRY-RUN] Would remove files for '{app_id}':")
        for target in targets:
            print(f"  - {target}")
        return True, 0

    if not confirm_removal(app_id, targets, yes=yes):
        return False, 1

    for target in targets:
        delete_path(target)
        print(f"[OK] Removed {target}")
    return True, 0


def cmd_remove(
    target: str,
    catalog: dict[str, dict],
    purge: bool,
    dry_run: bool,
    yes: bool,
) -> int:
    if target not in catalog:
        print(f"[ERR] Unknown external app: {target}", file=sys.stderr)
        return 1

    removed, rc = remove_single_app(
        target, catalog[target], purge=purge, dry_run=dry_run, yes=yes
    )
    if rc == 0 and removed and not dry_run:
        state_apps = load_state()
        if target in state_apps:
            state_apps.discard(target)
            save_state(state_apps)
    return rc


def cmd_sync(
    enabled: list[str],
    catalog: dict[str, dict],
    purge: bool,
    dry_run: bool,
    yes: bool,
) -> int:
    state_apps = load_state()
    enabled_set = set(enabled)
    exit_code = 0

    # 1. Install missing enabled apps (fresh machine setup / newly added app)
    for app_id in enabled:
        spec = catalog[app_id]
        if is_app_installed(spec):
            state_apps.add(app_id)
            continue
        print(f"[INFO] Installing missing enabled app '{app_id}'...")
        rc = run_action(spec["installer"], update_only=False, dry_run=dry_run)
        if rc != 0:
            print(f"[ERR] Failed to install {app_id} (exit {rc}).", file=sys.stderr)
            exit_code = rc
        elif not dry_run:
            state_apps.add(app_id)

    # 2. Remove apps removed from enabledApps
    for app_id, spec in catalog.items():
        if app_id in enabled_set:
            continue
        targets = existing_app_paths(spec, purge=purge)
        if not targets and app_id not in state_apps:
            continue
        if targets:
            removed, rc = remove_single_app(
                app_id, spec, purge=purge, dry_run=dry_run, yes=yes
            )
            if rc != 0:
                exit_code = rc
            if removed and not dry_run:
                state_apps.discard(app_id)
        elif not dry_run:
            state_apps.discard(app_id)

    if not dry_run:
        # Keep only installed enabled apps plus any orphaned apps the user declined to delete
        cleaned_state = {
            app_id
            for app_id in state_apps
            if (app_id in enabled_set and is_app_installed(catalog[app_id]))
            or (
                app_id not in enabled_set
                and bool(existing_app_paths(catalog[app_id], purge=False))
            )
        }
        save_state(cleaned_state)

    return exit_code


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="external-apps",
        description="Install, update, sync, and remove official external self-updating apps.",
    )
    parser.add_argument(
        "--manifest",
        type=Path,
        required=True,
        help="Path to Nix-generated external-apps JSON manifest.",
    )
    sub = parser.add_subparsers(dest="subcommand", required=True)

    sub.add_parser("status", help="Show status of declared and orphaned external apps.")

    p_install = sub.add_parser("install", help="Install an app or 'all' missing enabled apps.")
    p_install.add_argument("target", help="App ID or 'all'")
    p_install.add_argument("--dry-run", action="store_true", help="Preview without changing disk.")

    p_update = sub.add_parser("update", help="Update an installed app or 'all' installed enabled apps.")
    p_update.add_argument("target", help="App ID or 'all'")
    p_update.add_argument("--dry-run", action="store_true", help="Preview without changing disk.")

    p_remove = sub.add_parser("remove", help="Remove an external app's official installation.")
    p_remove.add_argument("target", help="App ID")
    p_remove.add_argument("--purge", action="store_true", help="Also remove config/cache/data directories.")
    p_remove.add_argument("--dry-run", action="store_true", help="Preview paths without deleting.")
    p_remove.add_argument("-y", "--yes", action="store_true", help="Skip confirmation prompt.")

    p_sync = sub.add_parser(
        "sync",
        help="Install missing enabled apps and remove apps dropped from config.",
    )
    p_sync.add_argument("--purge", action="store_true", help="Also remove config/cache/data when pruning.")
    p_sync.add_argument("--dry-run", action="store_true", help="Preview changes without modifying disk.")
    p_sync.add_argument("-y", "--yes", action="store_true", help="Skip confirmation prompts when removing.")

    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()

    enabled, catalog = load_manifest(args.manifest)
    if args.subcommand == "status":
        return cmd_status(enabled, catalog)
    if args.subcommand == "install":
        return cmd_install(args.target, enabled, catalog, dry_run=args.dry_run)
    if args.subcommand == "update":
        return cmd_update(args.target, enabled, catalog, dry_run=args.dry_run)
    if args.subcommand == "remove":
        return cmd_remove(
            args.target,
            catalog,
            purge=args.purge,
            dry_run=args.dry_run,
            yes=args.yes,
        )
    if args.subcommand == "sync":
        return cmd_sync(
            enabled,
            catalog,
            purge=args.purge,
            dry_run=args.dry_run,
            yes=args.yes,
        )
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
