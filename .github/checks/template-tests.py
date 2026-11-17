# SPDX-FileCopyrightText: 2026 Lael D. Barlow
# SPDX-License-Identifier: MIT

# Tests of the template's own code: the typed-number warning, the checks that
# a rule's image() and pixi run -e agree and that a rule lists the files in
# workflow/ it names as inputs, the table reader and the other readers in
# manuscript/lib.typ, the naming of images without building them, and that
# every place naming the images' pixi release names the same one.
# From the project folder:
#
#     pixi run python .github/checks/template-tests.py

import importlib.util
import os
import re
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

PROJECT = Path.cwd()
TEMPLATE = PROJECT / "workflow" / "template"


def run_script(name: str, folder: Path, *arguments: str) -> str:
    result = subprocess.run(
        [sys.executable, str(TEMPLATE / f"{name}.py"), *arguments],
        cwd=folder,
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode != 0 or "Traceback" in result.stderr:
        raise AssertionError(f"{name}.py failed:\n{result.stderr}")
    return result.stderr


def write(folder: Path, files: dict[str, str]) -> None:
    for name, text in files.items():
        path = folder / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)


class TypedNumbers(unittest.TestCase):
    DOCUMENT = """\
#import "lib.typ": *
The mean GC content was 39.27 percent.
Rounded, it was 39.3 percent of 4,641,652 bases.
#value("gc_mean") and #show-table("/results/x/123.tsv", [C.])
// 39.27 in a comment
/* 39.27 in a block
comment */
`39.27` in raw text <tab-39-27>
SeqKit 2.10.1 counted the bases, with 150 bp reads.
Genomes larger than 1,250,000 bases were left out.
"""

    def test_copied_numbers_are_found_and_the_rest_are_not(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            write(
                root,
                {
                    "manuscript/document.typ": self.DOCUMENT,
                    "results/tables/values.tsv": (
                        "name\tvalue\ngc_mean\t39.2714\nseqkit_version\t2.10.1\n"
                    ),
                    "results/tables/genomes.tsv": (
                        "name\tlength\tlimit\nE. coli\t4641652\t1250000\n"
                    ),
                },
            )
            warned = run_script(
                "check-typed-numbers",
                root,
                "results/tables/values.tsv",
                "results/tables/genomes.tsv",
            ).splitlines()
            lines = sorted(int(w.split(":")[1]) for w in warned)
            self.assertEqual(lines, [2, 3, 3, 9, 10], "\n".join(warned))
            self.assertIn("wrote 39.2714 in", "\n".join(warned))

    def test_only_the_tables_it_is_given_are_read(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            write(
                root,
                {
                    "manuscript/document.typ": "It was 39.27 percent.\n",
                    "results/tables/unshown.tsv": "name\tgc\nx\t39.27\n",
                },
            )
            self.assertEqual(run_script("check-typed-numbers", root), "")

    def test_an_unreadable_table_is_skipped(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            write(
                root,
                {
                    "manuscript/document.typ": "It was 39.27 percent.\n",
                    "results/tables/long.tsv": "name\tseq\nx\t" + "ACGT" * 50000 + "\n",
                    "results/tables/gc.tsv": "name\tgc\nx\t39.27\n",
                },
            )
            warned = run_script(
                "check-typed-numbers",
                root,
                "results/tables/long.tsv",
                "results/tables/gc.tsv",
                "results/tables/missing.tsv",
            )
            self.assertIn("39.27 is typed in", warned)


class Environments(unittest.TestCase):
    SNAKEFILE = '''\
include: "template/rules.smk"

rule agrees:
    container:
        image("seqkit")
    shell:
        "pixi run -e seqkit seqkit stats {input} > {output}"

rule differs:
    container:
        image("seqkit")
    shell:
        """
        pixi run \\
            --environment python python x.py
        """

rule vendor:
    container:
        image("vendor")
    shell:
        "vendor-tool {input} > {output}"

rule host:
    shell:
        "pixi run -e python python y.py"

rule tool_option:
    container:
        image("doc")
    shell:
        "pixi run -e doc typst compile -e x.typ"

# image("seqkit") in a comment, and pixi run -e python
'''

    def test_only_the_rule_whose_names_differ_is_named(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            write(root, {"workflow/Snakefile": self.SNAKEFILE})
            warned = run_script("check-rules", root).splitlines()
            self.assertEqual(len(warned), 1, "\n".join(warned))
            self.assertIn("rule differs", warned[0])
            self.assertIn("pixi run -e python", warned[0])

    def test_the_template_itself_is_clean(self) -> None:
        self.assertEqual(run_script("check-rules", PROJECT), "")


class OwnRecipes(unittest.TestCase):
    SNAKEFILE = '''\
rule vendor:
    container:
        image("vendor")
    shell:
        "vendor-tool {input} > {output}"

rule extended:
    container:
        image("seqkit")
    shell:
        "pixi run -e seqkit seqkit stats {input} > {output}"

rule no_recipe:
    container:
        image("other")
    shell:
        "other-tool > {output}"
'''

    def test_only_a_pixi_less_own_recipe_is_warned_about_without_containers(
        self,
    ) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            write(
                root,
                {
                    "workflow/Snakefile": self.SNAKEFILE,
                    "workflow/containers/vendor.def": "Bootstrap: docker\n",
                    "workflow/containers/seqkit.def": "Bootstrap: docker\n",
                },
            )
            self.assertEqual(run_script("check-rules", root), "")
            warned = run_script(
                "check-rules", root, "--without-containers"
            ).splitlines()
            self.assertEqual(len(warned), 1, "\n".join(warned))
            self.assertIn("rule vendor", warned[0])
            self.assertIn("workflow/containers/vendor.def", warned[0])

    def test_the_template_itself_is_clean_without_containers(self) -> None:
        self.assertEqual(
            run_script("check-rules", PROJECT, "--without-containers"), ""
        )


class ListedFiles(unittest.TestCase):
    SNAKEFILE = '''\
rule listed:
    input:
        script="workflow/scripts/a.py",
        table="results/x.tsv",
    shell:
        "python {input.script} {input.table} > {output}"

rule unlisted:
    input:
        "results/x.tsv",
    output:
        "results/y.tsv",
    shell:
        """
        python workflow/scripts/b.py \\
            {input} {output}
        python workflow/scripts/b.py --again {output}
        """

rule named_twice:
    input:
        "workflow/scripts/c.R",
    shell: "Rscript workflow/scripts/c.R {output}"

rule in_params:
    params:
        script="workflow/scripts/d.sh",
        folder="workflow/scripts",
    shell:
        "sh {params.script} /opt/workflow/scripts/z.sh"

rule directive:
    script:
        "workflow/scripts/e.py"

# python workflow/scripts/f.py in a comment
'''

    def test_only_a_file_named_outside_the_inputs_is_warned_about(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            write(root, {"workflow/Snakefile": self.SNAKEFILE})
            warned = run_script("check-rules", root).splitlines()
            self.assertEqual(len(warned), 2, "\n".join(warned))
            self.assertIn("rule unlisted names workflow/scripts/b.py", warned[0])
            self.assertIn("rule in_params names workflow/scripts/d.sh", warned[1])


class Readers(unittest.TestCase):
    def compile(self, files: dict[str, str], body: str) -> str:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            shutil.copy(PROJECT / "manuscript" / "lib.typ", root / "lib.typ")
            write(root, files)
            write(root, {"test.typ": '#import "lib.typ": *\n' + body})
            result = subprocess.run(
                [
                    "pixi",
                    "run",
                    "--locked",
                    "-e",
                    "doc",
                    "typst",
                    "compile",
                    "--root",
                    str(root),
                    "--ignore-system-fonts",
                    str(root / "test.typ"),
                    str(root / "test.pdf"),
                ],
                cwd=PROJECT,
                capture_output=True,
                text=True,
                check=False,
            )
            return "" if result.returncode == 0 else result.stderr

    def test_tables_are_read(self) -> None:
        files = {
            "hash.tsv": "#name\tGC\nchr1\t40\n",
            "comment.tsv": "##format: 1\nname\tGC\nchr1\t40\n",
            "comma.csv": "name,GC\nchr1,40\n",
        }
        body = """\
#for path in ("/hash.tsv", "/comment.tsv", "/comma.csv") {
  let t = data-rows(path)
  assert.eq(t.header, ("name", "GC"), message: path)
  assert.eq(t.rows, (("chr1", "40"),), message: path)
}
#show-table("/hash.tsv", [Caption.])\
"""
        self.assertEqual(self.compile(files, body), "")

    def test_bad_tables_stop_the_build(self) -> None:
        cases = {
            "name\tGC\n": "has one line",
            "": "is empty",
            "#only\n#comments\n": "has no rows",
        }
        for text, message in cases.items():
            body = '#show-table("/t.tsv", [C.])'
            self.assertIn(message, self.compile({"t.tsv": text}, body))

    def test_a_long_cell_breaks_without_a_character_added(self) -> None:
        body = """\
#let cell = "GCF_000146045.2_R64_genomic.fna"
#let shown = breakable(cell)
#assert(shown.children.all(c => c.func() == box))
#assert.eq(shown.children.map(c => c.body.text).join(), cell)
#assert.eq(breakable("a short cell"), "a short cell")
#assert.eq(breakable(""), "")\
"""
        self.assertEqual(self.compile({}, body), "")

    def test_values(self) -> None:
        files = {"v.tsv": "name\tvalue\nn\t5\ntwice\t1\ntwice\t2\n"}
        found = '#assert.eq(value("n", file: "/v.tsv"), "5")'
        self.assertEqual(self.compile(files, found), "")
        missing = '#value("absent", file: "/v.tsv")'
        self.assertIn("has no row named absent", self.compile(files, missing))
        twice = '#value("twice", file: "/v.tsv")'
        self.assertIn("records twice 2 times", self.compile(files, twice))

    def test_code_regions_and_width(self) -> None:
        script = "\n".join(
            [
                "x = 1",
                "# region: inner",
                "y = 2",
                "# end region: inner",
                "z = " + "3" * 90,
            ]
        )
        files = {"s.py": script}
        self.assertEqual(self.compile(files, '#code("/s.py", region: "inner")'), "")
        self.assertIn("characters wide", self.compile(files, '#code("/s.py")'))
        self.assertIn(
            "expected exactly 1",
            self.compile(files, '#code("/s.py", region: "absent")'),
        )


class Images(unittest.TestCase):
    LOCK = """\
version: 7
environments:
  seqkit:
    packages:
      linux-64:
      - conda: https://example.org/seqkit-2.10.1.conda
  doc:
    packages:
      linux-64:
      - conda: https://example.org/typst-0.15.0.conda
"""
    SNAKEFILE = """\
rule a:
    container:
        image("seqkit")

rule b:
    container:
        image("doc")
"""

    def names(self, root: Path) -> dict[str, str]:
        path = TEMPLATE / "update-containers.py"
        spec = importlib.util.spec_from_file_location("update_containers", path)
        assert spec is not None and spec.loader is not None
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        here = os.getcwd()
        os.chdir(root)
        try:
            return module.planned_images()
        finally:
            os.chdir(here)

    def test_naming_builds_nothing_and_follows_the_packages(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            definition = (TEMPLATE / "container.def").read_text()
            write(
                root,
                {
                    "pixi.lock": self.LOCK,
                    "workflow/Snakefile": self.SNAKEFILE,
                    "workflow/template/container.def": definition,
                    "manuscript/document.typ": "Text.\n",
                },
            )
            before = self.names(root)
            self.assertEqual(sorted(before), ["doc", "seqkit"])
            for environment, image in before.items():
                self.assertRegex(
                    image, rf"^results/containers/{environment}-[0-9a-f]{{12}}\.sif$"
                )
            self.assertFalse((root / "results").exists())
            write(root, {"pixi.lock": self.LOCK.replace("2.10.1", "2.10.2")})
            after = self.names(root)
            self.assertNotEqual(after["seqkit"], before["seqkit"])
            self.assertEqual(after["doc"], before["doc"])


class PixiRelease(unittest.TestCase):
    def test_every_place_names_the_same_release(self) -> None:
        definition = (TEMPLATE / "container.def").read_text()
        named = re.search(r"prefix-dev/pixi:(\d+\.\d+\.\d+)-", definition)
        assert named is not None
        release = named.group(1)
        floor = ".".join(release.split(".")[:2])
        manifest = (PROJECT / "pixi.toml").read_text()
        self.assertIn(f'requires-pixi = ">={floor}"', manifest)
        readme = (PROJECT / "README.md").read_text()
        stated = re.findall(r"The images contain pixi (\d+\.\d+\.\d+)", readme)
        for version in stated:
            self.assertEqual(version, release, "README.md")


if __name__ == "__main__":
    unittest.main(verbosity=2)
