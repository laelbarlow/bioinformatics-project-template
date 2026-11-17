// The document. `pixi run snakemake` runs the analysis and builds it into
// results/manuscript/document.pdf. Replace each TODO.

#import "lib.typ": *

#let value = value.with(file: "/results/manuscript/tables/values.tsv")

#show: article.with(
  title: [TODO: the title],
  author: "TODO: Your Name",
  note: none,
)

#heading(numbering: none)[Abstract]

TODO: the question, the data, the finding in this run's own values, and what
it means.

= Introduction

TODO: the question, the software that answers it, and the alternatives.

= Methods

TODO: one subsection per step of the workflow. Show the code that ran with
`code()`, and give each tool's version where it is first used.

TODO: replace this example. Each value this document quotes is read from a
file the run wrote. This one records the date of the run, #value("run_date"),
and is written by this script:

#code("/workflow/scripts/record-values.sh")

= Results

TODO: the findings, each from a table, figure or value the run wrote.

#heading(numbering: none)[References]

TODO: cite works in `references.bib` with `@key`, or delete this heading.

#bibliography("references.bib", style: "chicago-author-date", title: none)

#heading(numbering: none)[Appendix: provenance]

#show-table(
  "/results/manuscript/provenance/run-info.tsv",
  [The run that produced this document's results: when it was recorded, the
   template version, the project's git commit, the platform, the pixi and
   Snakemake versions, the checksum of `pixi.lock`, and whether the steps ran
   in containers, with each image's checksum. Snakemake reruns only the steps
   that a change affects, so some results can come from an earlier run than
   the one recorded here.],
)
