# SPDX-FileCopyrightText: 2026 Lael D. Barlow
# SPDX-License-Identifier: MIT

# The template's rules. workflow/Snakefile includes this file first, so that
# image() is defined before any rule of yours names an image. Taking a template
# update replaces this folder; nothing of yours belongs in it.

import json
import re
import subprocess
import sys
from pathlib import Path

CONTAINERS = any(
    method.name == "APPTAINER"
    for method in workflow.deployment_settings.deployment_method
)
IMAGES = {}

# Warns about a rule whose image() and pixi run -e differ, and about a rule
# that names a file in workflow/ without listing it as an input, on any
# machine; without containers, also about a rule that runs software only an
# image of its own recipe holds.
subprocess.run(
    [
        sys.executable,
        "workflow/template/check-rules.py",
        *([] if CONTAINERS else ["--without-containers"]),
    ],
    stdout=sys.stderr,
)

UPDATE_CONTAINERS = [sys.executable, "workflow/template/update-containers.py"]

if CONTAINERS:
    # Names the images and builds none, so a dry run costs nothing. Its own
    # messages say what went wrong, so it stops without a traceback.
    named = subprocess.run(
        [*UPDATE_CONTAINERS, "names"], stdout=subprocess.PIPE, text=True
    )
    if named.returncode:
        sys.exit(1)
    IMAGES = json.loads(named.stdout)


def image(environment):
    if not CONTAINERS:
        return None
    if environment not in IMAGES:
        raise ValueError(
            f"image({environment!r}) has no image. image() takes the name "
            f"of an environment written in quotes, such as \"seqkit\": the "
            f"images are found by reading the rules before the run."
        )
    return IMAGES[environment]


MANUSCRIPT_SOURCES = sorted(
    str(path)
    for path in Path("manuscript").rglob("*")
    if path.suffix in {".typ", ".bib"}
)

# The document's text without its comments, so a file named only in a comment
# is not an input.
MANUSCRIPT_TEXT = re.sub(
    r"(?m)^\s*//.*$",
    "",
    re.sub(
        r"(?s)/\*.*?\*/",
        "",
        "\n".join(Path(source).read_text() for source in MANUSCRIPT_SOURCES),
    ),
)

DOCUMENT_INPUTS = sorted(
    set(re.findall(r'"/results/manuscript/([^"]+)"', MANUSCRIPT_TEXT))
)

PROJECT_INPUTS = sorted(
    set(re.findall(r'"/((?:resources|workflow)/[^"]+)"', MANUSCRIPT_TEXT))
)

RUN_RECORD = "results/provenance/run-info.tsv"

SHOWN_RESULTS = [
    f"results/{path}"
    for path in DOCUMENT_INPUTS
    if f"results/{path}" != RUN_RECORD
]

SHOWN_TABLES = [
    path for path in SHOWN_RESULTS if path.endswith((".tsv", ".csv"))
]


localrules:
    record_run,
    stage_document_inputs,


rule record_run:
    input:
        script="workflow/template/record-run.py",
        lock="pixi.lock",
        version="workflow/template/VERSION",
        results=SHOWN_RESULTS,
    output:
        RUN_RECORD,
    params:
        images=sorted(IMAGES.values()),
    shell:
        """
        python {input.script} \
            --lock {input.lock} \
            --template-version {input.version} \
            --images {params.images} \
            --output {output}
        """


rule stage_document_inputs:
    input:
        [f"results/{path}" for path in DOCUMENT_INPUTS],
    output:
        [f"results/manuscript/{path}" for path in DOCUMENT_INPUTS],
    shell:
        """
        set -- {output}
        for source in {input}; do
            cp "$source" "$1"
            shift
        done
        """


rule render_document:
    input:
        staged=[f"results/manuscript/{path}" for path in DOCUMENT_INPUTS],
        sources=MANUSCRIPT_SOURCES,
        project=PROJECT_INPUTS,
    output:
        "results/manuscript/document.pdf",
    container:
        image("doc")
    shell:
        """
        pixi run -e doc \
            typst compile --root . --ignore-system-fonts \
                manuscript/document.typ {output}
        """


# Before the first step of a run that has steps to run, builds the images that
# are missing and removes the ones no rule names any more. A dry run builds
# nothing. A project with its own onstart: replaces this one, and must call
# build_images() from it.
def build_images():
    if not CONTAINERS or workflow.touch:
        return
    built = subprocess.run([*UPDATE_CONTAINERS, "build"], stdout=sys.stderr)
    if built.returncode:
        sys.exit(1)


onstart:
    build_images()


# After a run that finishes, a warning for each number typed into the document
# that a table the document reads also holds. It never stops the build. A
# project with its own onsuccess: replaces this one, and can call
# check_typed_numbers() from it.
def check_typed_numbers():
    script = "workflow/template/check-typed-numbers.py"
    subprocess.run([sys.executable, script, *SHOWN_TABLES])


onsuccess:
    check_typed_numbers()
