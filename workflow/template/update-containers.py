# SPDX-FileCopyrightText: 2026 Lael D. Barlow
# SPDX-License-Identifier: MIT

# Names and builds the Apptainer images the rules use. rules.smk calls it when
# Snakemake runs with containers, in two ways:
#
#     python workflow/template/update-containers.py names
#     python workflow/template/update-containers.py build
#
# `names` runs whenever Snakemake reads the rules. For each name in a rule's
# `container: image("<name>")` it prints the image's path,
# results/containers/<name>-<fingerprint>.sif, as JSON, from which image()
# reads the paths. It builds nothing and writes nothing, so a dry run costs
# nothing.
#
# `build` runs before the first step of a run that has steps to run, from the
# onstart: handler in rules.smk. It builds each image that is missing, removes
# the images no rule names any more, and writes results/containers/images.json.
# Snakemake's --no-hooks skips it, as it skips every handler.

import fcntl
import json
import platform
import re
import shutil
import subprocess
import sys
from hashlib import sha256
from pathlib import Path

import yaml

CONTAINERS = Path("results/containers")
IMPORTS = CONTAINERS / "typst-imports.typ"
INDEX = CONTAINERS / "images.json"
TEMPLATE_DEFINITION = Path("workflow/template/container.def")
OWN_DEFINITIONS = Path("workflow/containers")
LOCK = Path("pixi.lock")
# The lock format the images' pixi reads. Moving the base image in
# container.def to a newer pixi may need this changed with it.
LOCK_FORMAT = 7


def workflow_text() -> str:
    sources = [
        Path("workflow/Snakefile"),
        *sorted(Path("workflow").rglob("*.smk")),
    ]
    text = "\n".join(source.read_text() for source in sources)
    return re.sub(r"(?m)^\s*#.*$", "", text)


def named_environments() -> list[str]:
    text = workflow_text()
    literal = re.search(r"results/containers/([A-Za-z0-9_.-]+?)\.sif", text)
    if literal:
        path, environment = literal.group(0), literal.group(1)
        sys.exit(
            f"workflow/Snakefile names the image {path} by its path.\n"
            f'Name it by its environment: container: image("{environment}")'
        )
    pattern = r"""\bimage\(\s*["']([A-Za-z0-9_.-]+)["']\s*\)"""
    return sorted(set(re.findall(pattern, text)))


def locked_packages() -> dict[str, list[str]]:
    loader = getattr(yaml, "CSafeLoader", yaml.SafeLoader)
    lock = yaml.load(LOCK.read_text(), Loader=loader)
    if lock.get("version") != LOCK_FORMAT:
        sys.exit(
            f"pixi.lock is format {lock.get('version')}; the pixi inside the "
            f"images reads format {LOCK_FORMAT}. Run without containers "
            f"(--workflow-profile none) until a template release moves the "
            f"images to a newer pixi."
        )
    return {
        name: [
            f"{kind}: {url}"
            for entry in environment["packages"].get("linux-64", [])
            for kind, url in entry.items()
        ]
        for name, environment in lock["environments"].items()
    }


def typst_imports() -> str:
    pattern = r'(?m)^\s*#import\s*"(@preview/[^"]*)"'
    found: set[str] = set()
    for source in Path("manuscript").rglob("*.typ"):
        found.update(re.findall(pattern, source.read_text()))
    return "".join(f'#import "{name}"\n' for name in sorted(found))


def definition_of(environment: str) -> Path:
    own = OWN_DEFINITIONS / f"{environment}.def"
    return own if own.exists() else TEMPLATE_DEFINITION


def fingerprint_of(environment: str, packages: list[str], imports: str) -> str:
    parts = [definition_of(environment).read_text(), *packages]
    if environment == "doc":
        parts.append(imports)
    return sha256("\n".join(parts).encode()).hexdigest()


def planned_images() -> dict[str, str]:
    imports = typst_imports()
    locked = locked_packages()
    images: dict[str, str] = {}
    for environment in named_environments():
        own = definition_of(environment) != TEMPLATE_DEFINITION
        if not own and not locked.get(environment):
            sys.exit(
                f'The workflow names image("{environment}"), but pixi.lock '
                f"has no linux-64 packages for an environment of that name, "
                f"and there is no {OWN_DEFINITIONS}/{environment}.def."
            )
        packages = locked.get(environment, [])
        fingerprint = fingerprint_of(environment, packages, imports)
        image = CONTAINERS / f"{environment}-{fingerprint[:12]}.sif"
        images[environment] = str(image)
    return images


def build(environment: str, image: Path) -> None:
    print(f"Building {image}. This takes a few minutes.", flush=True)
    partial = image.with_suffix(".partial")
    result = subprocess.run(
        [
            "apptainer",
            "build",
            "--force",
            "--warn-unused-build-args",
            "--build-arg",
            f"ENV={environment}",
            str(partial),
            str(definition_of(environment)),
        ],
        check=False,
    )
    if result.returncode != 0:
        partial.unlink(missing_ok=True)
        sys.exit(f"Building {image} failed. The error is above.")
    partial.replace(image)


def check_machine() -> None:
    without = "    pixi run snakemake --workflow-profile none --cores 2"
    if shutil.which("apptainer") is None:
        sys.exit(
            f"Apptainer is not installed here. To run without containers:\n{without}"
        )
    if platform.machine() not in {"x86_64", "AMD64"}:
        sys.exit(
            f"The images are built for linux-64, and this machine is "
            f"{platform.machine()}. To run without containers:\n{without}"
        )


def print_names() -> None:
    images = planned_images()
    for image in images.values():
        if not Path(image).exists():
            print(
                f"{image} is not built yet. A run builds it first.",
                file=sys.stderr,
            )
    print(json.dumps(images))


def build_images() -> None:
    CONTAINERS.mkdir(parents=True, exist_ok=True)
    with (CONTAINERS / ".lock").open("w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        IMPORTS.write_text(typst_imports())
        images = planned_images()
        for environment, image in images.items():
            if not Path(image).exists():
                build(environment, Path(image))
        for old in [*CONTAINERS.glob("*.sif"), *CONTAINERS.glob("*.partial")]:
            if str(old) not in images.values():
                old.unlink()
        INDEX.write_text(json.dumps(images, indent=2) + "\n")


def main() -> None:
    modes = {"names": print_names, "build": build_images}
    if len(sys.argv) != 2 or sys.argv[1] not in modes:
        sys.exit("Usage: python update-containers.py names|build")
    check_machine()
    modes[sys.argv[1]]()


if __name__ == "__main__":
    main()
