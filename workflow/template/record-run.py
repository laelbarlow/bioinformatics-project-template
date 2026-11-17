# SPDX-FileCopyrightText: 2026 Lael D. Barlow
# SPDX-License-Identifier: MIT

# Writes the provenance record the document's appendix shows: when it was
# recorded, the template version, the project's git commit, the platform, the
# pixi and Snakemake versions, the checksum of pixi.lock and, for a run in
# containers, Apptainer's version and each image's checksum. The rule
# record_run in rules.smk calls it. The commit is "none" outside a git
# repository, and says so when the project has uncommitted changes.

import argparse
import hashlib
import re
import subprocess
import sys
from datetime import UTC, datetime
from pathlib import Path


def output_of(*command: str) -> str:
    return subprocess.run(
        command, capture_output=True, text=True, check=True
    ).stdout.strip()


def git_output(*arguments: str) -> str | None:
    try:
        result = subprocess.run(
            ["git", *arguments], capture_output=True, text=True, check=False
        )
    except OSError:
        return None
    return result.stdout.strip() if result.returncode == 0 else None


def git_commit() -> str:
    commit = git_output("rev-parse", "--short=12", "HEAD")
    changes = git_output("status", "--porcelain")
    if commit is None or changes is None:
        return "none"
    return f"{commit}, with uncommitted changes" if changes else commit


def sha256_of(path: Path) -> str:
    with path.open("rb") as handle:
        return hashlib.file_digest(handle, "sha256").hexdigest()


def environment_of(image: Path) -> str:
    return re.sub(r"-[0-9a-f]{12}$", "", image.stem)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--lock", type=Path, required=True)
    parser.add_argument("--template-version", type=Path, required=True)
    parser.add_argument("--images", type=Path, nargs="*", default=[])
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    missing = [str(image) for image in args.images if not image.exists()]
    if missing:
        sys.exit(
            f"{' and '.join(missing)} is not built. The images are built "
            f"before a run's first step by build_images() in "
            f"workflow/template/rules.smk. --no-hooks skips it, and a "
            f"Snakefile with its own onstart: must call build_images()."
        )

    recorded = datetime.now(UTC).strftime("%Y-%m-%dT%H:%M:%SZ")
    rows = [
        ("recorded_utc", recorded),
        ("template_version", args.template_version.read_text().strip()),
        ("git_commit", git_commit()),
        ("platform", output_of("uname", "-srm")),
        ("pixi_version", output_of("pixi", "--version")),
        ("snakemake_version", output_of("snakemake", "--version")),
        ("pixi_lock_sha256", sha256_of(args.lock)),
    ]
    if args.images:
        rows.append(("containers", output_of("apptainer", "--version")))
        for image in sorted(args.images, key=environment_of):
            key = f"container_{environment_of(image)}_sha256"
            rows.append((key, sha256_of(image)))
    else:
        rows.append(("containers", "none"))

    lines = ["key\tvalue", *(f"{key}\t{value}" for key, value in rows)]
    args.output.write_text("\n".join(lines) + "\n")


if __name__ == "__main__":
    main()
