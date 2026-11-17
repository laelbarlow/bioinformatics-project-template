# SPDX-FileCopyrightText: 2026 Lael D. Barlow
# SPDX-License-Identifier: MIT

# Warns about numbers typed into the document that a table it reads holds:
#
#     python workflow/template/check-typed-numbers.py TABLE...
#
# rules.smk runs it after every run that finishes, with the tables the
# document shows or takes values from, as check_typed_numbers().
#
# It reads the prose of each .typ file in manuscript/ except lib.typ, and the
# tables it is given. A number in the prose with three or more significant
# digits that one of those tables holds is printed with its line, as is one
# that rounds a value in results/tables/values.tsv. A table it cannot read is
# skipped. It warns and never stops the build. It finds copied results, not
# numbers worked out by hand from them, which only a reader can check.

import csv
import re
import sys
from decimal import ROUND_HALF_UP, Decimal, InvalidOperation
from pathlib import Path

MANUSCRIPT = Path("manuscript")
VALUES = Path("results/tables/values.tsv")

NUMBER = re.compile(
    r"(?<![\w.-])v?(\d{4}-\d{2}-\d{2}|\d[\d,]*(?:\.\d+)*)(?![\w-])"
)


def blank(match: re.Match[str]) -> str:
    return re.sub(r"[^\n]", " ", match.group(0))


def prose(text: str) -> str:
    patterns = [
        r"```.*?```",
        r"`[^`\n]*`",
        r"/\*.*?\*/",
        r"(?<!:)//[^\n]*",
        r"(?m)^\s*#(?:import|let|set|show|bibliography)(?![\w-])[^\n]*",
        r"(?<=[(,:])\s*\"[^\"\n]*\"",
        r"<[\w:.-]+>",
        r"@[\w:.-]+",
    ]
    for pattern in patterns:
        text = re.sub(pattern, blank, text, flags=re.DOTALL)
    return text


def plain(token: str) -> str:
    return token.removeprefix("v").replace(",", "")


def worth_checking(token: str) -> bool:
    digits = "".join(character for character in token if character.isdigit())
    return len(digits.strip("0")) >= 3


def numbers_in(table: Path) -> list[str]:
    delimiter = "," if table.suffix == ".csv" else "\t"
    found = []
    try:
        with table.open(newline="") as handle:
            for row in csv.reader(handle, delimiter=delimiter):
                for cell in row:
                    cell = re.sub(r"T[\d:]+Z?", " ", cell)
                    found.extend(plain(t) for t in NUMBER.findall(cell))
    except (OSError, UnicodeDecodeError, csv.Error):
        return []
    return [token for token in found if worth_checking(token)]


def written_numbers(tables: list[Path]) -> dict[str, tuple[str, bool]]:
    found: dict[str, tuple[str, bool]] = {}
    for table in tables:
        values = table == VALUES
        for token in numbers_in(table):
            source, seen = found.get(token, (str(table), False))
            if values:
                source = str(VALUES)
            found[token] = (source, seen or values)
    return found


def rounded(value: str, places: int) -> str | None:
    try:
        number = Decimal(value)
    except InvalidOperation:
        return None
    step = Decimal(1).scaleb(-places)
    return str(number.quantize(step, rounding=ROUND_HALF_UP))


def match(
    token: str, written: dict[str, tuple[str, bool]]
) -> tuple[str, str] | None:
    if token in written:
        return token, written[token][0]
    if token.count(".") != 1:
        return None
    places = len(token.split(".")[1])
    for value, (source, values) in written.items():
        if not values:
            continue
        longer = value.count(".") == 1 and len(value.split(".")[1]) > places
        if longer and rounded(value, places) == token:
            return value, source
    return None


def main() -> None:
    written = written_numbers([Path(path) for path in sys.argv[1:]])
    if not written:
        return
    sources = sorted(
        path for path in MANUSCRIPT.rglob("*.typ") if path.name != "lib.typ"
    )
    warnings = []
    for source in sources:
        lines = prose(source.read_text()).splitlines()
        for number, line in enumerate(lines, start=1):
            for typed in NUMBER.findall(line):
                token = plain(typed.rstrip(","))
                if not worth_checking(token):
                    continue
                found = match(token, written)
                if found is None:
                    continue
                value, table = found
                wrote = "it" if value == token else value
                shown = typed.rstrip(",")
                warnings.append(
                    f"{source}:{number}: {shown} is typed in, and the run "
                    f"wrote {wrote} in {table}. Use value() or a table."
                )
    if warnings:
        print("\n".join(warnings), file=sys.stderr)


if __name__ == "__main__":
    main()
