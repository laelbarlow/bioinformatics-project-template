// SPDX-FileCopyrightText: 2026 Lael D. Barlow
// SPDX-License-Identifier: MIT

// The readers and the page style for a project document. Taking a template
// update replaces this file, so changes of yours belong in document.typ.
//
// Four readers pull things out of the project, and each one stops the build
// rather than print something wrong:
//
//   code(path, region: "name")   the code that ran, read from the file
//   show-table(path, caption)    a TSV or CSV the analysis wrote
//   show-figure(path, caption)   an image the analysis drew
//   value("name")                one value from a two-column TSV
//
// A value() call is a lookup, not a claim: it resolves only if the analysis
// ran and wrote the file.

// The widest code line, in characters, that code() prints. At 1in margins
// and DejaVu Sans Mono 8.6pt, a US-letter page fits 89 and an A4 page 85;
// typst overflows a longer line without a warning. 80 is the width editors
// already mark. A longer line is allowed on one call with limit:, as in
// #code("/workflow/scripts/x.py", limit: 120), so the exception shows.
#let code-width = 80

#let longest-unbroken-listing = 30

// A table this long or shorter is kept on one page.
#let longest-unbroken-table = 30

#let marker-body(line) = {
  let t = line.trim()
  for opener in ("#", "//", "--", "%") {
    if t.starts-with(opener) {
      t = t.slice(opener.len()).trim()
      break
    }
  }
  t
}

#let dedent(lines) = {
  let indents = lines
    .filter(l => l.trim() != "")
    .map(l => l.len() - l.trim(at: start).len())
  if indents.len() == 0 { return lines }
  let n = calc.min(..indents)
  lines.map(l => if l.len() >= n { l.slice(n) } else { l })
}

#let check-width(lines, nums, path, limit: code-width) = {
  for (i, line) in lines.enumerate() {
    let w = line.replace("\t", "    ").clusters().len()
    if w > limit {
      panic(
        path + " line " + str(nums.at(i)) + " is " + str(w)
          + " characters wide; this page fits " + str(limit)
          + ". Shorten it in the script, or break it with a trailing backslash."
      )
    }
  }
}

#let script-lines(path) = {
  let src = read(path)
  if src.trim() == "" { panic(path + " is empty.") }
  src.replace("\r\n", "\n").trim("\n", repeat: true).split("\n")
}

#let lang-of(path) = {
  // A Snakefile has no extension, and it is python.
  let name = path.split("/").last()
  if name == "Snakefile" { return "python" }
  let ext = name.split(".").last()
  let known = (
    py: "python", R: "r", r: "r", sh: "bash", bash: "bash",
    smk: "python", typ: "typst",
  )
  if ext in known { known.at(ext) } else { ext }
}

// Show code from a file: the whole file, a named region, or a line range --
// one of the three, never two.
//
// A named region is marked in the script itself:
//     # region: summarise
//     ...the lines to show...
//     # end region: summarise
// The markers are addresses, not explanations, and they are never printed.
// Every build resolves them, so a renamed or missing marker stops the build.
#let code(path, region: none, lines: none, limit: code-width) = {
  if region != none and lines != none {
    panic("Give region: or lines:, not both.")
  }
  let all = script-lines(path)
  // Every step below narrows the text and its real line numbers together.
  // Adding an offset to a starting line instead gets this wrong the moment a
  // nested region marker is filtered out of the middle of the selection.
  let nums = range(1, all.len() + 1)
  let chosen = all
  if region != none {
    let open = "region: " + region
    let close = "end region: " + region
    let starts = all.enumerate().filter(p => marker-body(p.at(1)) == open).map(p => p.at(0))
    let ends = all.enumerate().filter(p => marker-body(p.at(1)) == close).map(p => p.at(0))
    if starts.len() != 1 {
      panic(
        path + " has " + str(starts.len()) + " lines reading: # " + open
          + " -- expected exactly 1."
      )
    }
    if ends.len() != 1 {
      panic(
        path + " has " + str(ends.len()) + " lines reading: # " + close
          + " -- expected exactly 1."
      )
    }
    if ends.first() < starts.first() {
      panic(path + ": the end marker for " + region + " comes before the start.")
    }
    chosen = all.slice(starts.first() + 1, ends.first())
    nums = nums.slice(starts.first() + 1, ends.first())
  } else if lines != none {
    if lines.at(0) < 1 or lines.at(1) > all.len() {
      panic(
        path + " has " + str(all.len()) + " lines, so lines: " + repr(lines)
          + " cannot be shown."
      )
    }
    chosen = all.slice(lines.at(0) - 1, lines.at(1))
    nums = nums.slice(lines.at(0) - 1, lines.at(1))
  }
  // A region marker is an address, not code, so it is never printed -- which
  // is what lets one region sit inside another.
  let keep = chosen
    .enumerate()
    .filter(p => {
      let body = marker-body(p.at(1))
      not (body.starts-with("region: ") or body.starts-with("end region: "))
    })
    .map(p => p.at(0))
  nums = keep.map(i => nums.at(i))
  chosen = dedent(keep.map(i => chosen.at(i)))
  if chosen.filter(l => l.trim() != "").len() == 0 {
    panic(path + ": that selection has no code in it.")
  }
  check-width(chosen, nums, path, limit: limit)
  // A listing with no file name on it is a fragment the reader cannot place,
  // and a path typed into the prose beside it is a claim that can go stale.
  // This is the path the call was given, so the label cannot disagree with the
  // code under it.
  block(breakable: chosen.len() > longest-unbroken-listing, {
    set block(above: 0.5em, below: 0.5em)
    // sticky: the label is kept on the page with the code it names.
    block(sticky: true, text(
      font: "DejaVu Sans Mono",
      size: 8pt,
      fill: luma(110),
      path.trim("/", at: start) + ", " + if nums.first() == nums.last() {
        "line " + str(nums.first())
      } else {
        "lines " + str(nums.first()) + "\u{2013}" + str(nums.last())
      },
    ))
    raw(chosen.join("\n"), lang: lang-of(path), block: true)
  })
}

// typst breaks a line at a space and nowhere else, and a results table is full
// of things with no space in them: an accession, a path, a full-precision
// percentage. A word longer than `every` characters is set as boxes of that
// many, side by side: a line may break between two boxes, and nothing is
// added to the text, so a cell copied out of the PDF is the cell the run
// wrote.
#let breakable(cell, every: 16) = {
  let words = cell.split(" ").map(word => {
    let characters = word.clusters()
    if characters.len() <= every { word } else {
      characters.chunks(every).map(c => box(c.join())).join()
    }
  })
  words.join(" ")
}

// The first line of a table is its column names. Many tools write that line
// after a #, as `seqkit fx2tab --header-line` does (#name, GC): a line that
// starts with one #, sits right above the first row and has as many columns
// as it is read as the header. Any other line that starts with # is a comment.
#let data-rows(path) = {
  let text = read(path)
  if text.trim() == "" {
    panic(path + " is empty. The analysis ran but wrote nothing into it.")
  }
  let sep = if path.ends-with(".csv") { "," } else { "\t" }
  let lines = text.replace("\r\n", "\n").split("\n").filter(l => l.trim() != "")
  let at = lines.position(l => not l.starts-with("#"))
  if at == none {
    panic(path + " has no rows: every line in it starts with #.")
  }
  let data = lines.slice(at).filter(l => not l.starts-with("#"))
  if at > 0 {
    let above = lines.at(at - 1)
    if (
      not above.starts-with("##")
        and above.split(sep).len() == data.first().split(sep).len()
    ) {
      data.insert(0, above.slice(1))
    }
  }
  let rows = csv(bytes(data.join("\n")), delimiter: sep)
  if rows.len() < 2 {
    panic(
      path + " has one line, which is read as the column names, and no rows."
        + " If the step that wrote it found nothing, report that as a count"
        + " with value() instead of showing the table."
    )
  }
  (header: rows.first(), rows: rows.slice(1))
}

#let show-table(path, caption, limit: 20, wide: false, label: none) = {
  let t = data-rows(path)
  let shown = if t.rows.len() > limit { t.rows.slice(0, limit) } else { t.rows }
  let cap = if t.rows.len() > limit {
    [#caption Showing #shown.len() of #t.rows.len() rows; the whole table is in
     #raw(path.trim("/", at: start)).]
  } else { caption }
  let grain = if wide { 8 } else { 16 }
  let body = table(
    columns: t.header.len(),
    align: left,
    table.header(..t.header.map(h => strong(breakable(h, every: grain)))),
    ..shown.flatten().map(c => breakable(c, every: grain)),
  )
  // A short table is kept whole. Its caption, above it, is sticky, so the
  // two stay on one page.
  let drawn = figure(
    kind: table,
    caption: cap,
    if shown.len() > longest-unbroken-table { body } else {
      block(breakable: false, body)
    },
  )
  // wide: true sets the table on a landscape page, for a table with too many
  // columns for portrait. A label written after the call would then land on
  // the page, not the table, so a wide table takes it as label: <tab-name>.
  let labelled = if label == none { drawn } else { [#drawn#label] }
  if wide {
    page(flipped: true, { set text(size: 8pt); labelled })
  } else {
    labelled
  }
}

#let show-figure(path, caption, width: 90%) = {
  if read(path, encoding: none).len() == 0 {
    panic(path + " is a zero-byte file. The plotting step started and did not finish.")
  }
  figure(image(path, width: width), caption: caption)
}

// One value, by name, from a two-column TSV the analysis writes. document.typ
// names the file once, with #let value = value.with(file: "...").
#let value(key, file: none) = {
  if file == none {
    panic("value() has no file: name one with #let value = value.with(file: ...)")
  }
  let t = data-rows(file)
  let hit = t.rows.filter(r => r.len() >= 2 and r.at(0).trim() == key)
  if hit.len() == 0 {
    panic(
      file + " has no row named " + key + ". Either the analysis does not write"
        + " it yet, or it did not run."
    )
  }
  if hit.len() > 1 {
    panic(
      file + " records " + key + " " + str(hit.len()) + " times. That is a stale"
        + " row from an earlier run: delete results/ and run the project again."
    )
  }
  let v = hit.first().at(1).trim()
  if v == "" { panic(file + ": the value for " + key + " is blank.") }
  v
}

// The page style. note: is one line under the author: an affiliation, a
// journal and manuscript number for a review, or none.
#let article(
  title: none,
  author: none,
  note: none,
  paper: "us-letter",
  body,
) = {
  set document(title: title, author: if author == none { () } else { author })
  set page(paper: paper, margin: 1in, numbering: "1", number-align: center)
  // Libertinus Serif and DejaVu Sans Mono are inside typst, so the document
  // is the same on every machine. A system font would make the page count
  // depend on the machine that built it.
  set text(font: "Libertinus Serif", size: 11pt, lang: "en")
  set par(leading: 0.8em, spacing: 1.2em, justify: false)
  set heading(numbering: "1.")
  show heading: set block(above: 1.4em, below: 0.8em)

  show raw.where(block: true): it => block(
    width: 100%,
    fill: luma(246),
    inset: (x: 0.8em, y: 0.7em),
    radius: 3pt,
    breakable: true,
  )[
    #set text(font: "DejaVu Sans Mono", size: 8.6pt)
    // No line numbers: a reader who copies a command from the PDF would copy
    // them too. The label above the block gives the file and its lines.
    #it
  ]
  show raw.where(block: false): set text(font: "DejaVu Sans Mono", size: 9.5pt)
  show raw.where(block: false): it => if it.text.len() <= 32 { box(it) } else {
    it
  }
  show figure.where(kind: table): set text(size: 8.5pt)
  show figure.where(kind: table): set figure.caption(position: top)
  show figure.caption.where(kind: table): it => block(sticky: true, it)
  show figure.caption: set text(size: 9.5pt)
  show figure.caption: set align(left)
  // A long table may run over a page. Any other figure stays with its caption.
  show figure.where(kind: table): set block(breakable: true)
  show link: set text(fill: rgb("#1a4f8a"))

  align(center)[
    #text(size: 16pt, weight: "bold")[#title]
    #v(0.6em)
    #author
    #if note != none { v(0.2em); note }
  ]
  v(1.2em)
  body
}
