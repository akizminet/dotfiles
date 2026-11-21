#!/usr/bin/env python3
"""Check whether cache.nixos.org has cached all upstream nixpkgs derivations."""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

LOCAL_NAMES = frozenset({"pam.d"})
LOCAL_PREFIXES = (
    "initrd-linux-",
    "google-chrome-",
    "firefox-bin-",
    "libsciter-",
    "rustdesk-",
    "celluloid-",
    "akquick-",
    "nm-openvpn-sso",
)
LOCAL_SUFFIXES = ("-modules-shrunk",)

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


def classify_drvs(
    drv_paths: list[str],
) -> tuple[list[str], list[str]]:
    if not drv_paths:
        return [], []

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
    blockers: list[str] = []
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
            blockers.append(name)

    return sorted(local_filtered), sorted(blockers)


def write_github_outputs(
    total_drvs: int, local_filtered: list[str], blockers: list[str]
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
                for name in blockers:
                    fh.write(f"- `{name}`\n")
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
    args = parser.parse_args()

    with tempfile.TemporaryDirectory() as tmpdir_str:
        tmpdir = Path(tmpdir_str)
        hw_path = tmpdir / "hardware-configuration.nix"
        hw_path.write_text(
            '{\n'
            '  fileSystems."/" = { device = "/dev/null"; fsType = "ext4"; };\n'
            '  boot.kernelModules = [ "kvm-intel" ];\n'
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

        cmd = [
            "nix",
            "build",
            "--dry-run",
            "--impure",
            "--override-input",
            "celluloid-src",
            f"path:{dummy_celluloid}",
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
        try:
            local_filtered, blockers = classify_drvs(drvs)
        except RuntimeError as exc:
            print(str(exc), file=sys.stderr)
            return 1

        in_gha = os.environ.get("GITHUB_ACTIONS") == "true"
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
        for name in blockers:
            print(f"  BLOCKER: {name}")
        if blockers and in_gha:
            blocker_list = ", ".join(dict.fromkeys(blockers))
            print(
                f"::warning title=Upstream cache still building::"
                f"{len(blockers)} upstream blocker(s) not yet on cache.nixos.org: {blocker_list}"
            )

        write_github_outputs(len(drvs), local_filtered, blockers)
        return 0 if not blockers else 2


if __name__ == "__main__":
    raise SystemExit(main())
