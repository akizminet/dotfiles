#!/usr/bin/env python3
"""Check whether cache.nixos.org has cached all upstream nixpkgs derivations."""

from __future__ import annotations

import argparse
import concurrent.futures
import errno
import http.client
import json
import os
import re
import socket
import subprocess
import sys
import tempfile
import threading
from pathlib import Path

LOCAL_NAMES = frozenset({"pam.d"})
LOCAL_PREFIXES = (
    "initrd-linux-",
    "google-chrome-",
    "firefox-bin-",
    "celluloid-",
    "akquick-",
    "fcitx5-lotus-",
    "nm-openvpn-sso",
)
LOCAL_SUFFIXES = ("-modules-shrunk",)

CACHE_HOST = "cache.nixos.org"
CACHE_WORKERS = 16
CACHE_RETRIES = 3

WILL_BUILD_RE = re.compile(
    r"^(?:these \d+ derivations|this derivation) will be built:$"
)
DRV_LINE_RE = re.compile(r"^\s+(/nix/store/[a-z0-9]+-[^\s]+\.drv)$")


def strip_store_prefix(drv_path: str) -> str:
    return drv_path.removeprefix("/nix/store/")


def parse_unbuilt_drvs(output: str) -> list[str]:
    drvs: list[str] = []
    in_build_section = False
    for line in output.splitlines():
        if not in_build_section:
            if WILL_BUILD_RE.match(line.strip()):
                in_build_section = True
            continue
        match = DRV_LINE_RE.match(line)
        if match:
            drvs.append(match.group(1))
        else:
            break
    return drvs


def load_derivations(drv_paths: list[str]) -> dict[str, dict]:
    merged: dict[str, dict] = {}
    batch_size = 200
    for start in range(0, len(drv_paths), batch_size):
        batch = drv_paths[start : start + batch_size]
        proc = subprocess.run(
            ["nix", "derivation", "show", *batch],
            capture_output=True,
            text=True,
            check=False,
        )
        if proc.returncode != 0:
            raise RuntimeError(
                f"nix derivation show failed ({proc.returncode}):\n{proc.stderr}"
            )
        raw = json.loads(proc.stdout)
        entries = raw.get("derivations", raw)
        for key, info in entries.items():
            merged[strip_store_prefix(key)] = info
    return merged


def parse_structured_attrs(info: dict) -> dict:
    sa = info.get("structuredAttrs")
    if isinstance(sa, dict):
        return sa
    if isinstance(sa, str):
        try:
            return json.loads(sa)
        except json.JSONDecodeError:
            return {}
    raw_json = info.get("env", {}).get("__json")
    if isinstance(raw_json, str):
        try:
            return json.loads(raw_json)
        except json.JSONDecodeError:
            return {}
    return {}


def drv_name(key: str, info: dict, sa: dict) -> str:
    env = info.get("env", {})
    name = info.get("name") or env.get("name") or sa.get("name")
    if name:
        return name
    rest = key.split("-", 1)[1] if "-" in key else key
    return rest.removesuffix(".drv")


def is_trivial_local(info: dict, sa: dict) -> bool:
    env = info.get("env", {})
    return (
        env.get("preferLocalBuild") == "1"
        or env.get("allowSubstitutes") == "0"
        or sa.get("preferLocalBuild") is True
        or sa.get("allowSubstitutes") is False
    )


def input_drv_keys(info: dict) -> list[str]:
    inputs = info.get("inputs", {})
    if isinstance(inputs, dict) and isinstance(inputs.get("drvs"), dict):
        return [strip_store_prefix(k) for k in inputs["drvs"]]
    input_drvs = info.get("inputDrvs", {})
    if isinstance(input_drvs, dict):
        return [strip_store_prefix(k) for k in input_drvs]
    return []


def output_hashes(info: dict) -> list[str]:
    hashes: list[str] = []
    for out_info in info.get("outputs", {}).values():
        path = out_info.get("path", "")
        if path:
            hashes.append(strip_store_prefix(path).split("-", 1)[0])
    return hashes


class _IPv4HTTPSConnection(http.client.HTTPSConnection):
    """HTTPSConnection forced to IPv4 when IPv6 routes are unreachable."""

    def connect(self) -> None:
        last_err: OSError | None = None
        for res in socket.getaddrinfo(
            self.host, self.port, socket.AF_INET, socket.SOCK_STREAM
        ):
            af, socktype, proto, _, sa = res
            sock: socket.socket | None = None
            try:
                sock = socket.socket(af, socktype, proto)
                if self.timeout is not socket._GLOBAL_DEFAULT_TIMEOUT:  # type: ignore[attr-defined]
                    sock.settimeout(self.timeout)
                if self.source_address:
                    sock.bind(self.source_address)
                sock.connect(sa)
                self.sock = self._context.wrap_socket(sock, server_hostname=self.host)
                return
            except OSError as exc:
                last_err = exc
                if sock is not None:
                    sock.close()
        if last_err is not None:
            raise last_err
        raise OSError(f"No IPv4 address resolved for {self.host}:{self.port}")


class CacheChecker:
    """Thread-safe keep-alive HEAD checker for cache.nixos.org."""

    def __init__(self, host: str = CACHE_HOST, timeout: float = 15.0) -> None:
        self.host = host
        self.timeout = timeout
        self._local = threading.local()
        self._lock = threading.Lock()
        self._force_ipv4 = False
        self._conns: list[http.client.HTTPSConnection] = []

    def _new_conn(self) -> http.client.HTTPSConnection:
        cls = _IPv4HTTPSConnection if self._force_ipv4 else http.client.HTTPSConnection
        conn = cls(self.host, timeout=self.timeout)
        with self._lock:
            self._conns.append(conn)
        self._local.conn = conn
        return conn

    def _get_conn(self) -> http.client.HTTPSConnection:
        conn = getattr(self._local, "conn", None)
        if conn is None:
            return self._new_conn()
        return conn

    def _reset_conn(self) -> None:
        conn = getattr(self._local, "conn", None)
        if conn is not None:
            try:
                conn.close()
            except Exception:
                pass
            self._local.conn = None

    def check_hash(self, store_hash: str) -> bool:
        path = f"/{store_hash}.narinfo"
        last_exc: Exception | None = None
        for attempt in range(CACHE_RETRIES):
            conn = self._get_conn()
            try:
                conn.request("HEAD", path, headers={"Host": self.host})
                resp = conn.getresponse()
                resp.read()
                if resp.status == 200:
                    return True
                if resp.status == 404:
                    return False
                raise RuntimeError(
                    f"Unexpected HTTP {resp.status} from https://{self.host}{path}"
                )
            except OSError as exc:
                last_exc = exc
                if exc.errno == errno.ENETUNREACH:
                    with self._lock:
                        self._force_ipv4 = True
                self._reset_conn()
            except http.client.HTTPException as exc:
                last_exc = exc
                self._reset_conn()
            if attempt + 1 < CACHE_RETRIES:
                continue
        raise RuntimeError(
            f"Failed checking https://{self.host}{path} after {CACHE_RETRIES} attempts: {last_exc}"
        )

    def close(self) -> None:
        with self._lock:
            for conn in self._conns:
                try:
                    conn.close()
                except Exception:
                    pass
            self._conns.clear()


def collect_uncached_drvs_remote(root_drv: str) -> tuple[list[str], dict[str, dict]]:
    """Walk the derivation DAG and return derivations not cached on cache.nixos.org."""
    root_key = strip_store_prefix(root_drv)
    frontier: set[str] = {root_key}
    seen: set[str] = {root_key}
    loaded: dict[str, dict] = {}
    cache_status: dict[str, bool] = {}
    uncached: list[str] = []

    checker = CacheChecker()
    try:
        with concurrent.futures.ThreadPoolExecutor(max_workers=CACHE_WORKERS) as pool:
            while frontier:
                batch_paths = [f"/nix/store/{k}" for k in sorted(frontier)]
                frontier.clear()
                info_map = load_derivations(batch_paths)
                loaded.update(info_map)

                hashes_to_check = sorted(
                    {
                        h
                        for info in info_map.values()
                        for h in output_hashes(info)
                        if h not in cache_status
                    }
                )
                if hashes_to_check:
                    for h, is_cached in zip(
                        hashes_to_check, pool.map(checker.check_hash, hashes_to_check)
                    ):
                        cache_status[h] = is_cached

                for key, info in info_map.items():
                    hashes = output_hashes(info)
                    if hashes and all(cache_status.get(h, False) for h in hashes):
                        continue
                    uncached.append(f"/nix/store/{key}")
                    for dep_key in input_drv_keys(info):
                        if dep_key not in seen:
                            seen.add(dep_key)
                            frontier.add(dep_key)
    finally:
        checker.close()

    return uncached, loaded


def classify_drvs(
    drv_paths: list[str],
    preloaded: dict[str, dict] | None = None,
) -> tuple[list[str], list[tuple[str, str]]]:
    if not drv_paths:
        return [], []

    if preloaded is not None:
        needed_keys = [strip_store_prefix(p) for p in drv_paths]
        missing_paths = [
            f"/nix/store/{k}" for k in needed_keys if k not in preloaded
        ]
        data = {k: preloaded[k] for k in needed_keys if k in preloaded}
        if missing_paths:
            data.update(load_derivations(missing_paths))
    else:
        data = load_derivations(drv_paths)

    parsed: dict[str, tuple[str, bool]] = {}
    rev_deps: dict[str, set[str]] = {}

    for key, info in data.items():
        sa = parse_structured_attrs(info)
        parsed[key] = (drv_name(key, info, sa), is_trivial_local(info, sa))
        for dep_key in input_drv_keys(info):
            if dep_key in data:
                rev_deps.setdefault(dep_key, set()).add(key)

    akquick_keys = {
        k for k, (name, _) in parsed.items() if name.startswith("akquick-")
    }
    vendor_keys = {
        k
        for k, (name, _) in parsed.items()
        if name == "cargo-vendor-dir"
        and rev_deps.get(k)
        and rev_deps[k].issubset(akquick_keys)
    }

    vendor_only = set(vendor_keys)
    changed = True
    while changed:
        changed = False
        for key in data:
            if (
                key not in vendor_only
                and rev_deps.get(key)
                and rev_deps[key].issubset(vendor_only)
            ):
                vendor_only.add(key)
                changed = True

    local_filtered: list[str] = []
    blockers: list[tuple[str, str]] = []
    for key, (name, trivial) in parsed.items():
        if (
            trivial
            or key in akquick_keys
            or key in vendor_only
            or name in LOCAL_NAMES
            or name.startswith(LOCAL_PREFIXES)
            or name.endswith(LOCAL_SUFFIXES)
        ):
            local_filtered.append(name)
        else:
            blockers.append((name, key))

    return sorted(local_filtered), sorted(blockers)


def write_github_outputs(
    total_drvs: int, local_filtered: list[str], blockers: list[tuple[str, str]]
) -> None:
    ready = len(blockers) == 0
    github_output = os.environ.get("GITHUB_OUTPUT")
    if github_output:
        with open(github_output, "a", encoding="utf-8") as fh:
            fh.write(f"ready={'true' if ready else 'false'}\n")
            fh.write(f"total_drvs={total_drvs}\n")
            fh.write(f"blocker_count={len(blockers)}\n")

    step_summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if step_summary:
        with open(step_summary, "a", encoding="utf-8") as fh:
            status = (
                "Ready (all upstream derivations cached)"
                if ready
                else "Waiting for upstream cache"
            )
            fh.write(f"### NixOS Cache Check: {status}\n\n")
            fh.write(f"- Total unbuilt derivations: `{total_drvs}`\n")
            fh.write(f"- Local/trivial derivations filtered: `{len(local_filtered)}`\n")
            fh.write(f"- Upstream cache blockers: `{len(blockers)}`\n")
            if blockers:
                fh.write("\n#### Upstream blockers\n\n")
                for name, key in blockers:
                    fh.write(f"- `{name}` (`/nix/store/{key}`)\n")
            if local_filtered:
                fh.write("\n<details>\n<summary>Filtered local/trivial derivations</summary>\n\n")
                for name in local_filtered:
                    fh.write(f"- `{name}`\n")
                fh.write("\n</details>\n")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--flake", default=".", help="Path or URI to flake")
    parser.add_argument(
        "--attr",
        default="nixosConfigurations.default.config.system.build.toplevel",
        help="Flake output attribute to dry-run",
    )
    parser.add_argument(
        "--override-input",
        action="append",
        nargs=2,
        default=[],
        metavar=("NAME", "URI"),
        help="Override a flake input (repeatable)",
    )
    mode_group = parser.add_mutually_exclusive_group()
    mode_group.add_argument(
        "--ignore-local-store",
        action="store_true",
        help="Check cache.nixos.org directly via derivation DAG instead of local /nix/store",
    )
    mode_group.add_argument(
        "--use-local-store",
        action="store_true",
        help="Use nix build --dry-run against the local /nix/store",
    )
    args = parser.parse_args()

    in_gha = os.environ.get("GITHUB_ACTIONS") == "true"
    use_local_store = (
        True
        if args.use_local_store
        else False
        if args.ignore_local_store
        else in_gha
    )

    with tempfile.TemporaryDirectory() as tmpdir_str:
        tmpdir = Path(tmpdir_str)
        hw_path = tmpdir / "hardware-configuration.nix"
        hw_path.write_text(
            '{ config, lib, modulesPath, ... }:\n'
            '{\n'
            '  imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];\n'
            '  fileSystems."/" = { device = "/dev/null"; fsType = "btrfs"; options = [ "subvol=nixos" ]; };\n'
            '  fileSystems."/boot" = { device = "/dev/null"; fsType = "vfat"; };\n'
            '  boot.kernelModules = [ "kvm-intel" ];\n'
            '  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;\n'
            '}\n',
            encoding="utf-8",
        )

        dummy_celluloid = tmpdir / "dummy-celluloid-src"
        dummy_celluloid.mkdir()
        (dummy_celluloid / "placeholder").touch()

        env = os.environ.copy()
        env["GIT_SSH_COMMAND"] = "/bin/false"
        env["NIXOS_HARDWARE_CONFIG"] = str(hw_path)
        env["NIXOS_HOSTNAME"] = "workstation"
        env["NIXOS_MACHINE_ID"] = "none"

        override_args: list[str] = [
            "--override-input",
            "celluloid-src",
            f"path:{dummy_celluloid}",
        ]
        for input_name, input_uri in args.override_input:
            override_args.extend(["--override-input", input_name, input_uri])

        preloaded: dict[str, dict] | None = None
        if use_local_store:
            cmd = [
                "nix",
                "build",
                "--dry-run",
                "--impure",
                *override_args,
                "--no-write-lock-file",
                f"{args.flake}#{args.attr}",
            ]
            proc = subprocess.run(
                cmd, env=env, capture_output=True, text=True, check=False
            )
            combined = "\n".join(part for part in (proc.stdout, proc.stderr) if part)
            if proc.returncode != 0:
                print(combined, file=sys.stderr)
                return 1
            drvs = parse_unbuilt_drvs(combined)
        else:
            cmd = [
                "nix",
                "eval",
                "--raw",
                "--impure",
                *override_args,
                f"{args.flake}#{args.attr}.drvPath",
            ]
            proc = subprocess.run(
                cmd, env=env, capture_output=True, text=True, check=False
            )
            if proc.returncode != 0:
                combined = "\n".join(part for part in (proc.stdout, proc.stderr) if part)
                print(combined, file=sys.stderr)
                return 1
            root_drv = proc.stdout.strip()
            try:
                drvs, preloaded = collect_uncached_drvs_remote(root_drv)
            except RuntimeError as exc:
                print(str(exc), file=sys.stderr)
                return 1

        try:
            local_filtered, blockers = classify_drvs(drvs, preloaded=preloaded)
        except RuntimeError as exc:
            print(str(exc), file=sys.stderr)
            return 1

        print(f"total_drvs={len(drvs)}")
        print(f"filtered_local={len(local_filtered)}")
        if local_filtered:
            if in_gha:
                print(
                    f"::group::Filtered local/trivial derivations ({len(local_filtered)})"
                )
            for name in local_filtered:
                print(f"  LOCAL: {name}")
            if in_gha:
                print("::endgroup::")

        print(f"upstream_blockers={len(blockers)}")
        for name, key in blockers:
            print(f"  BLOCKER: {name} (/nix/store/{key})")
        if blockers and in_gha:
            blocker_list = ", ".join(dict.fromkeys(name for name, _ in blockers))
            print(
                f"::warning title=Upstream cache still building::"
                f"{len(blockers)} upstream blocker(s) not yet on cache.nixos.org: {blocker_list}"
            )

        write_github_outputs(len(drvs), local_filtered, blockers)
        return 0 if not blockers else 2


if __name__ == "__main__":
    raise SystemExit(main())
