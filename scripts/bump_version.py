#!/usr/bin/env python3
import subprocess
import semver

def get_latest_tag() -> str:
    result = subprocess.run(
        ["git", "describe", "--tags", "--abbrev=0"],
        capture_output=True, text=True
    )
    return result.stdout.strip() if result.returncode == 0 else "v0.0.0"

def bump_minor(version_str: str) -> str:
    clean = version_str.lstrip("v")
    parsed = semver.VersionInfo.parse(clean)
    return f"v{parsed.bump_minor()}"

if __name__ == "__main__":
    latest = get_latest_tag()
    new_version = bump_minor(latest)
    print(new_version)
