# bioinformatics-project-template

This project structure is one I have used for several applied bioinformatics
projects to keep them organized and easily reproducible. The purpose is to fully
define (and automate) the entire project from data downloading to report
typesetting so it runs with a single command as follows:

```sh
pixi run snakemake                                      # Linux, in containers
pixi run snakemake --workflow-profile none --cores 2    # a Mac, or no Apptainer
```

The template runs as it is, so you can try it before filling it in with your own
analysis.

## How it works

- [pixi](https://pixi.sh) installs each tool in its own environment and pins
  every version in `pixi.lock`. This is a really nice way to keep track of
  exactly what version of each conda package was used.
- [Snakemake](https://snakemake.github.io) runs the steps, and reruns only
  the ones whose inputs have changed, so you can avoid redundant reruns without
  custom conditional statements in your code.
- [Apptainer](https://apptainer.org) runs the steps in containers built from
  their environments, so the operating system is consistent and the environment
  fully isolated.
- [Typst](https://typst.app) builds the document, as the workflow's last
  step. Working with Typst directly is my favourite way to generate PDFs. 

Ideally, you won't type results into the document directly. Numbers, tables,
figures, and code listings/blocks from the workflow output and code can be
pulled into the Typst document when it compiles. This way the source files are
clearly recorded, and these elements will be updated if the workflow is modified
and rerun.


## Getting started

1. Install [Pixi](https://pixi.prefix.dev/latest/installation/):

   ```sh
   curl -fsSL https://pixi.sh/install.sh | sh
   ```

   The installer adds pixi to your shell's startup file, so open a new
   terminal before you go on. On Windows, work in WSL. Containers also need
   Apptainer, which runs on Linux only: If necessary, install it as
   [its documentation](https://apptainer.org/docs/admin/main/installation.html)
   describes, or ask your system administrator to install it.

2. Make your own copy and run it:

   ```sh
   git clone https://github.com/laelbarlow/bioinformatics-project-template my-project
   cd my-project
   rm -rf .git
   pixi run snakemake
   ```

   Without Apptainer, add `--workflow-profile none --cores 2` to the last
   line. The first run installs the software, builds the images if you have
   Apptainer, and writes the PDF to `results/manuscript/document.pdf`. With
   containers that takes a few minutes. `rm -rf .git` drops the template's
   history, so the folder is yours from its first commit.

3. Make it yours. Change the project's name in `pixi.toml`, replace
   `README.md` and `CITATION.cff` with your own, and note what you change in
   `CHANGELOG.md`. Add a `LICENSE` of your own for your work, and credit the
   template as [Attributing the template](#attributing-the-template) shows.

4. Commit, and push to a repository of your own, such as an empty one on
   GitHub:

   ```sh
   git init -b main
   git add -A
   git commit -m "Start my project"
   git remote add origin https://github.com/you/my-project
   git push -u origin main
   ```

   Commit as you go, and commit `pixi.lock` with `pixi.toml`, even lines a
   newer pixi rewrote that you didn't touch. Before you push,
   `sh .github/checks/lint.sh` lints your scripts.

## Where things go

```
manuscript/   document.typ and references.bib, which you write
workflow/     Snakefile: your rules
              scripts/: your Python, R and shell scripts
resources/    inputs that no step writes, such as a sample sheet
results/      everything a run writes, with the PDF at
              results/manuscript/document.pdf
```

You can delete `results/` at any time and get it all back, so put nothing
there by hand. Public data is better downloaded by a rule than kept in
`resources/`.

Leave the template's own files as they are: `workflow/template/`,
`manuscript/lib.typ`, `workflow/profiles/default/config.yaml` and
`.github/checks/`.

## Adding a step

Say you want to measure the GC content of a genome you were given, with
SeqKit. Give SeqKit an environment in `pixi.toml`, above the `[environments]`
table:

```toml
[feature.seqkit.dependencies]
seqkit = ">=2.10,<3"
```

and add a line for it to the `[environments]` table at the end of the file:

```toml
seqkit = { features = ["seqkit"], no-default-feature = true }
```

Then put the genome in `resources/` (`mkdir -p resources` makes the folder)
and write a rule in `workflow/Snakefile`:

```python
rule tabulate:
    input:
        "resources/genome.fna",
    output:
        "results/tables/gc.tsv",
    container:
        image("seqkit")
    shell:
        """
        pixi run -e seqkit \
            seqkit fx2tab --name --gc --header-line {input} > {output}
        """
```

The rule names the environment twice: `image("seqkit")` picks the container
and `pixi run -e seqkit` picks the environment inside it. The two names must
match: every run warns about a rule whose names differ, and in a container
that step stops. Last,
add `"results/tables/gc.tsv"` to `rule all`, or use it as another rule's
input. `pixi run snakemake -n` lists what would run. To run the same step on
several genomes, use a
[wildcard](https://snakemake.readthedocs.io/en/stable/snakefiles/rules.html#wildcards).

When a step runs a script, list the script as an input of its rule, as the
template's `record_values` rule does, along with any other file the script
reads. Snakemake reruns a step when its inputs or its command change, but it
doesn't look inside a script the command calls. A script that isn't an input
can change without its step running again, so every run warns about a rule
that names a file in `workflow/` without listing it as an input.

## Writing the document

`manuscript/document.typ` is an ordinary Typst file, with four extra functions
that bring in what the workflow produced:

```typst
#value("genomes")
#show-table("/results/manuscript/tables/summary.tsv", [Caption.])
#show-figure("/results/manuscript/figures/gc.png", [Caption.])
#code("/workflow/scripts/plot.R", region: "model")
```

If a file or a value is missing, the build stops. A table's first line is its
column names. To refer to a table or figure, put a label after the call, as in
`#show-table(...) <tab-summary>`, and write `@tab-summary` in the text. In the
document, write `/results/manuscript/...` for a file the workflow wrote at
`results/...`: the table above is the workflow's `results/tables/summary.tsv`.
The template copies each file you name into `results/manuscript/` before the
build, so you don't add a rule for that.

`value()` looks a name up in `results/tables/values.tsv`, which the
`record_values` rule writes. To add values, have a step write a tab-separated
table with a header line, then one name and value per line, and add that table
to the rule's `tables` input. A software version is a value too, so record it
with a step rather than typing it in. When a run of the workflow finishes, it
warns about any number of three or more significant digits in your text that
a table the document reads also holds.

`code()` shows a whole script, or only the lines between `# region: model` and
`# end region: model`. Those markers also work inside a rule's `shell:`
command in `workflow/Snakefile`. A line over 80 characters stops the build:
break it, or raise the limit with `limit:`.

Once the analysis has run, `pixi run -e doc render` rebuilds the document
alone, and `pixi run -e doc watch` does so after every save.

Snakemake reruns a step when its inputs, its command or its image changes, so
you don't need to start from nothing before you share the PDF. It misses two
changes. An environment you change while running without containers reruns
nothing, so delete `results/` and run again. A rule you remove or rename
leaves its old output behind, so delete that file. Git ignores `results/`, so copy
the PDF out of it to share it.

## Containers

`pixi run snakemake` runs each rule that has a `container:` line in an
Apptainer image. On a machine without Apptainer, add `--workflow-profile none
--cores 2` and those rules run on your machine instead. A rule with no
`container:` line always runs on your machine, in the default environment.

You don't write the images yourself. The template builds one for each
environment you name with `image("...")`, from the packages `pixi.lock` pins
for it. The first run builds them, and each takes a few minutes. A dry run
builds nothing.

An image's file name ends in a fingerprint of its recipe and its packages, as
in `results/containers/seqkit-1a2b3c4d5e6f.sif`. When you change an
environment, its image gets a new name, and Snakemake reruns the steps that
use it and the steps after them. Without containers there is no such check, so
delete `results/` to rerun the analysis.

To archive a study, copy `results/containers/*.sif` out of `results/` after a
run. Copied back into the same project, they are used without a rebuild.

### Software that isn't a conda package

pixi installs packages from conda-forge, bioconda and PyPI. For anything
else, such as a release a project publishes on its own site or an image
someone else maintains, give the step an image recipe of its own:
`workflow/containers/<name>.def`. When that file exists, `image("<name>")` is
built from it instead of from the template's recipe, and editing the recipe
gives the image a new name. Keep its `From:` line pinned by digest, so the
base image can't change under the same name.

A recipe can start from a published image and need nothing more, here a
BioContainers image:

```
Bootstrap: docker
From: quay.io/biocontainers/<tool>@sha256:<digest>
```

or install a release in `%post`:

```
Bootstrap: docker
From: ubuntu@sha256:<digest>

%post
    apt-get update
    apt-get install -y --no-install-recommends curl ca-certificates
    curl -fsSL -o /tmp/tool.tar.gz https://example.org/tool-1.2.3-linux-x64.tar.gz
    tar -xzf /tmp/tool.tar.gz -C /opt
    ln -s /opt/tool-1.2.3/bin/tool /usr/local/bin/tool
```

When `<name>` isn't an environment in `pixi.toml`, the rule runs the tool
without `pixi run -e`:

```python
rule run_tool:
    input:
        "resources/genome.fna",
    output:
        "results/tool/report.tsv",
    container:
        image("tool")
    shell:
        "tool --input {input} --output {output}"
```

That rule works only with containers. A run without them warns about it
before it starts, because the tool isn't on your machine. The build prints
`WARNING: Unused build args: ENV`, which is expected: the template passes
every recipe the environment's name, and this one doesn't use it.

If instead one of your pixi environments needs something pixi can't install,
such as a system package, start its recipe from a copy of the template's:

```sh
mkdir -p workflow/containers
cp workflow/template/container.def workflow/containers/seqkit.def
```

The copy still installs the pixi environment, so the rule keeps its
`pixi run -e seqkit`, and it runs without containers too.

The fingerprint misses three things: a file a recipe copies in with `%files`,
the packages a recipe installs with `apt-get` (whatever the mirror holds on
the day it builds), and an environment's tasks and activation in `pixi.toml`.
After changing one, delete the image and rerun the rules that use it, as in
`pixi run snakemake --forcerun tabulate`.

## Good to know

- Images are built for `linux-64` only. Elsewhere, run without containers.
- A rule that runs an image of its own recipe without `pixi run -e` works
  only with containers. If yours has one, say so in your README.
- If a version you pin isn't built for every platform, add
  `platforms = ["linux-64"]` to that feature in a table of its own,
  `[feature.seqkit]`, above `[feature.seqkit.dependencies]`. That environment
  then runs only on Linux.
- It runs on a single machine. It hasn't been adapted to spread its steps
  across a cluster through a scheduler such as SLURM, although Snakemake
  makes that entirely feasible.
- The images contain pixi 0.81.0. If a newer pixi on your machine writes a
  `pixi.lock` that it can't read, the run stops and says so. Run without
  containers until a template release moves the images to a newer pixi.
- For interactive development of scripts, the [Zed](https://zed.dev) editor's
  REPL can run lines of a script in the `python` or `rstats` environment
  provided as examples in this template. For R, run `pixi run -e rstats kernel`
  once on the machine that holds the project, and again if the folder moves or
  the environment is reinstalled. For Python, `pixi install -e python` is
  enough. On your own machine the R kernel is named after the project's folder,
  as in *R (my-project)*. Over SSH, choose the kernel *rstats; pixi* or *python;
  pixi* in Zed while a Python file is open.


## Attributing the template

`LICENSE-template` covers only the template's own files, the ones you leave
as they are, and each of them that can hold a comment names it in an SPDX
header. The files you write or change, such as `manuscript/document.typ`,
`workflow/Snakefile` and your scripts, carry no header and fall under your own
`LICENSE`. Keep `LICENSE-template` and the headers: the MIT licence asks that
its notice stay with the template's files.

Then say where the project came from, with the version in
`workflow/template/VERSION`. In your README:

> Made from
> [bioinformatics-project-template](https://github.com/laelbarlow/bioinformatics-project-template)
> &lt;version&gt;, by Lael D. Barlow.

In a paper or report the project builds, cite it where you describe the
workflow:

> Barlow LD. bioinformatics-project-template, version &lt;version&gt;.
> https://github.com/laelbarlow/bioinformatics-project-template

and in your own `CITATION.cff`, list it under `references:`:

```yaml
references:
  - type: software
    title: bioinformatics-project-template
    authors:
      - family-names: Barlow
        given-names: Lael D.
    version: "<version>"
    repository-code: "https://github.com/laelbarlow/bioinformatics-project-template"
```

## Licence

The template's files are under the MIT licence, in `LICENSE-template`.
