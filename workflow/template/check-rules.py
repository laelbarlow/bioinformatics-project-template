# SPDX-FileCopyrightText: 2026 Lael D. Barlow
# SPDX-License-Identifier: MIT

# Warns about two things in the workflow's rules. rules.smk runs it before
# every run, with or without containers. It reads the workflow's text and
# never stops the run.
#
# 1. A rule whose `container: image("<name>")` and `pixi run -e` name
#    different environments. In a container such a step stops, because the
#    image holds one environment. Without containers it runs in the
#    environment that `pixi run -e` names, so it would pass on a Mac and fail
#    on Linux. A `pixi run` is read as the image's own pixi reads it (the
#    options before the command).
#
# 2. A rule that names a file in workflow/, such as a script, anywhere but
#    under `input:`. Snakemake compares a command's text, not the script it
#    calls, so editing that file would not rerun the step. A file under
#    `script:` or `notebook:` is left out, because Snakemake watches those
#    itself.
#
# 3. With --without-containers only: a rule whose image has a recipe of its
#    own, workflow/containers/<name>.def, and whose command calls no pixi run.
#    Its software is inside that image, so on this machine the step finds
#    none of it.

import re
import sys
from pathlib import Path

HEADER = re.compile(r"^(?:rule|checkpoint)\s+(\w+)\s*:")
SECTION = re.compile(r"^(\s*)(\w+)\s*:")
IMAGE = re.compile(r"""\bimage\(\s*["']([A-Za-z0-9_.-]+)["']\s*\)""")
PIXI_RUN = re.compile(r"\bpixi\s+run\b([^\n]*)")
WORKFLOW_FILE = re.compile(r"(?<![\w/.-])workflow/(?:[\w.{}-]+/)*[\w{}-]+\.\w+")
WATCHED = {"input", "script", "notebook"}
OWN_RECIPES = Path("workflow/containers")


def rules(text: str) -> list[tuple[str, str]]:
    found: list[tuple[str, str]] = []
    name, body = None, []
    for line in text.splitlines():
        header = HEADER.match(line)
        if header or (line[:1].strip() and name):
            if name:
                found.append((name, "\n".join(body)))
            name, body = (header.group(1), []) if header else (None, [])
            continue
        if name and not line.lstrip().startswith("#"):
            body.append(line)
    if name:
        found.append((name, "\n".join(body)))
    return found


def sections(body: str) -> list[tuple[str, str]]:
    found: list[tuple[str, list[str]]] = []
    indent = None
    for line in body.splitlines():
        start = SECTION.match(line)
        if start and indent is None:
            indent = start.group(1)
        if start and start.group(1) == indent:
            found.append((start.group(2), [line[start.end() :]]))
        elif found:
            found[-1][1].append(line)
    return [(name, "\n".join(lines)) for name, lines in found]


def asked_environments(body: str) -> list[str]:
    asked = []
    for options in PIXI_RUN.findall(body.replace("\\\n", " ")):
        take = False
        for token in options.strip("\"' ").split():
            token = token.strip("\"'")
            if take:
                asked.append(token)
                break
            if token in {"-e", "--environment"}:
                take = True
            elif token.startswith("--environment="):
                asked.append(token.removeprefix("--environment="))
                break
            elif not token.startswith("-"):
                break
    return asked


def environment_warnings(body: str) -> list[str]:
    images = IMAGE.findall(body)
    if not images:
        return []
    return [
        f'runs in image("{images[0]}") and calls pixi run -e {asked}. A '
        f"rule's container: line and its pixi run -e must name the same "
        f"environment, or the step stops in a container."
        for asked in asked_environments(body)
        if asked != images[0]
    ]


def unlisted_files(body: str) -> list[str]:
    listed: set[str] = set()
    named: list[str] = []
    for name, text in sections(body):
        files = WORKFLOW_FILE.findall(text)
        if name == "input":
            listed.update(files)
        elif name not in WATCHED:
            named.extend(files)
    return [file for file in dict.fromkeys(named) if file not in listed]


def file_warnings(body: str) -> list[str]:
    return [
        f"names {file}, which is not one of its inputs, so editing that "
        f"file would not rerun the step. List it under input:, for "
        f'example as script="{file}", and write {{input.script}} in the '
        f"command."
        for file in unlisted_files(body)
    ]


def own_recipe_warnings(body: str) -> list[str]:
    images = IMAGE.findall(body)
    if not images or PIXI_RUN.search(body):
        return []
    recipe = OWN_RECIPES / f"{images[0]}.def"
    if not recipe.exists():
        return []
    warning = (
        f'runs in image("{images[0]}"), built from {recipe}, and calls no '
        f"pixi run. Without containers it runs on this machine, which may "
        f"not have that software: run it with containers."
    )
    return [warning]


def main() -> None:
    without_containers = "--without-containers" in sys.argv[1:]
    sources = [
        Path("workflow/Snakefile"),
        *sorted(Path("workflow").rglob("*.smk")),
    ]
    for source in sources:
        if not source.exists():
            continue
        for name, body in rules(source.read_text()):
            warnings = [*environment_warnings(body), *file_warnings(body)]
            if without_containers:
                warnings += own_recipe_warnings(body)
            for warning in warnings:
                print(f"{source}: rule {name} {warning}", file=sys.stderr)


if __name__ == "__main__":
    main()
