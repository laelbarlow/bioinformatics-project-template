# SPDX-FileCopyrightText: 2026 Lael D. Barlow
# SPDX-License-Identifier: MIT

# Checks the container path end to end, on a Linux x86_64 machine with
# Apptainer and pixi. It works on a copy of the project, so nothing in the
# project changes. From the project folder:
#
#     sh .github/checks/containers.sh
#
# What it checks:
#   1. --rulegraph and a dry run build nothing and write no results/, the
#      graph is all --rulegraph prints, and the dry run names the images a
#      run will build;
#   2. the first run builds every image, names each <env>-<12 hex>.sif,
#      lists it in images.json, records its checksum, builds the PDF, and
#      installs no imaged environment on the host, and the doc image holds
#      the pixi release that container.def names;
#   3. a second run builds nothing and runs nothing;
#   4. an image deleted by hand is not rebuilt by a dry run, and the next
#      run with a step to run rebuilds it at the same path;
#   5. archived images copied into an empty results/containers/ are used
#      without a build;
#   6. a package added to one environment builds nothing on a dry run; a run
#      builds that one image under a new name, removes the old one, and
#      reruns exactly the rules in EXPECT_RERUN;
#   7. a recipe of the project's own, workflow/containers/<CHANGE_ENV>.def,
#      builds that one image under a new name and reruns exactly the rules
#      in EXPECT_RERUN;
#   8. a recipe whose name is no pixi environment builds an image without
#      pixi, which a rule runs in and the provenance table records;
#   9. a rule whose container: line and pixi run -e disagree stops with the
#      image's message.
#
# Settings, as environment variables:
#   CHANGE_ENV, CHANGE_PACKAGE, EXPECT_RERUN   steps 6 and 7; the defaults suit a
#                                              project whose only image is doc
#   CORES                                      default 2
#   WORK                                       default a new temporary folder,
#                                              removed when every check passes
# Step 6 solves the changed pixi.toml again, so it needs the network. When
# the pixi running this is newer than the one inside the images, step 6 also
# checks that the images install a lock the newer pixi wrote.

set -eu

project=$(pwd)
if [ ! -f "$project/workflow/template/rules.smk" ]; then
    echo "Run this from the project folder." >&2
    exit 2
fi
work=${WORK:-$(mktemp -d)}
cores=${CORES:-2}
change_env=${CHANGE_ENV:-doc}
change_package=${CHANGE_PACKAGE:-'pigz = ">=2.8,<3"'}
expect_rerun=${EXPECT_RERUN:-all record_run render_document stage_document_inputs}
hex12='[0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]'

copy=$work/project
rm -rf "$copy"
mkdir -p "$copy"
tar -C "$project" --exclude=.pixi --exclude=./results --exclude=.snakemake \
    --exclude=.git -cf - . | tar -C "$copy" -xf -
cd "$copy"

fail() {
    echo "FAILED  $1" >&2
    echo "        logs in $work" >&2
    exit 1
}
ok() { echo "ok      $1"; }

# Runs a command, its output into $work/<name>.log.
run() {
    name=$1
    shift
    "$@" > "$work/$name.log" 2>&1 || {
        tail -40 "$work/$name.log" >&2
        fail "$name: $*"
    }
}

# How many images the run <name> built, and the rules it finished.
built() { grep -c '^Building results/containers/' "$work/$1.log" || true; }
finished() {
    sed -n 's/^Finished jobid: [0-9]* (Rule: \([A-Za-z0-9_]*\))$/\1/p' \
        "$work/$1.log" | sort -u | tr '\n' ' ' | sed 's/ $//'
}

# The image of one environment, and every environment, from images.json.
image_of() {
    sed -n "s/^ *\"$1\": \"\(results\/containers\/[^\"]*\)\".*/\1/p" \
        results/containers/images.json
}
environments() {
    sed -n 's/^ *"\([^"]*\)": .*/\1/p' results/containers/images.json
}

# 1
pixi run --locked snakemake --rulegraph > "$work/graph.dot" 2> "$work/graph.log" \
    || { tail -40 "$work/graph.log" >&2; fail "snakemake --rulegraph"; }
first=$(head -1 "$work/graph.dot")
[ "$first" = "digraph snakemake_dag {" ] \
    || fail "--rulegraph printed more than the graph: $first"
run dry pixi run --locked snakemake -n
[ "$(built graph)" -eq 0 ] || fail "--rulegraph built an image"
[ "$(built dry)" -eq 0 ] || fail "the dry run built an image"
[ ! -e results ] || fail "--rulegraph or the dry run wrote results/"
unbuilt=$(grep -c 'is not built yet. A run builds it first.' "$work/dry.log" || true)
[ "$unbuilt" -ge 1 ] || fail "the dry run did not name the images a run builds"
ok "--rulegraph and a dry run built nothing, wrote no results/, and named $unbuilt images"

# 2
run first pixi run --locked snakemake --cores "$cores"
n=0
for env in $(environments); do
    image=$(image_of "$env")
    # shellcheck disable=SC2254
    case $image in
        results/containers/"$env"-$hex12.sif) ;;
        *) fail "images.json gives $env the image '$image'" ;;
    esac
    [ -s "$image" ] || fail "$image is missing"
    [ ! -e ".pixi/envs/$env" ] || fail "the run installed .pixi/envs/$env"
    grep -q "^container_${env}_sha256	" results/provenance/run-info.tsv \
        || fail "run-info.tsv has no checksum for $env"
    n=$((n + 1))
done
[ "$n" -ge 1 ] || fail "images.json lists no image"
[ "$(built first)" -eq "$n" ] || fail "the first run built $(built first) of $n images"
[ "$(find results/containers -name '*.sif' | wc -l)" -eq "$n" ] \
    || fail "results/containers holds an image images.json does not list"
grep -q '^containers	apptainer' results/provenance/run-info.tsv \
    || fail "run-info.tsv does not record apptainer"
[ -s results/manuscript/document.pdf ] || fail "no PDF"
named=$(sed -n 's/.*prefix-dev\/pixi:\([0-9.]*\)-.*/\1/p' workflow/template/container.def)
held=$(apptainer exec "$(image_of doc)" /usr/local/bin/pixi --version \
    2> "$work/version.log") || fail "apptainer exec $(image_of doc) pixi --version"
[ "$held" = "pixi $named" ] \
    || fail "container.def names pixi $named; the doc image holds: $held"
ok "$n images, each <env>-<12 hex>.sif and recorded; PDF built; none on the host; $held"

# 3
run again pixi run --locked snakemake --cores "$cores"
[ "$(built again)" -eq 0 ] || fail "the second run built an image"
[ -z "$(finished again)" ] || fail "the second run ran: $(finished again)"
grep -q 'Nothing to be done' "$work/again.log" \
    || fail "the second run did not say there was nothing to do"
ok "a second run builds nothing and runs nothing"

# 4
env=$(environments | head -1)
image=$(image_of "$env")
rm "$image"
run deleted-dry pixi run --locked snakemake -n
[ "$(built deleted-dry)" -eq 0 ] || fail "a dry run rebuilt the deleted $image"
run deleted pixi run --locked snakemake --cores "$cores" --forcerun render_document
[ "$(built deleted)" -eq 1 ] || fail "deleting $image built $(built deleted) images"
[ "$(image_of "$env")" = "$image" ] || fail "the rebuilt image has a new name"
[ -s "$image" ] || fail "$image was not rebuilt"
ok "$image deleted: a dry run built nothing; a run rebuilt it at the same path"

# 5
mkdir -p "$work/archive"
cp results/containers/*.sif "$work/archive/"
rm -rf results
mkdir -p results/containers
cp "$work/archive"/*.sif results/containers/
run archived pixi run --locked snakemake --cores "$cores"
[ "$(built archived)" -eq 0 ] || fail "archived images were built again"
[ -s results/manuscript/document.pdf ] || fail "no PDF from the archived images"
ok "archived images in an empty results/: used, none built"

# 6
before=$(cat results/containers/images.json)
old=$(image_of "$change_env")
at="[feature.$change_env.dependencies]"
grep -qxF "$at" pixi.toml || fail "pixi.toml has no line $at"
awk -v at="$at" -v line="$change_package" \
    '{ print } $0 == at && !done { print line; done = 1 }' pixi.toml > pixi.toml.new
mv pixi.toml.new pixi.toml
run changed-dry pixi run snakemake -n
[ "$(built changed-dry)" -eq 0 ] || fail "a dry run after the change built an image"
[ -e "$old" ] || fail "a dry run after the change removed $old"
run changed pixi run snakemake --cores "$cores"
[ "$(built changed)" -eq 1 ] || fail "the change built $(built changed) images"
[ ! -e "$old" ] || fail "the old image $old is still there"
moved=$(printf '%s\n' "$before" | diff - results/containers/images.json \
    | sed -n 's/^> *"\([^"]*\)".*/\1/p' | tr '\n' ' ' | sed 's/ $//')
[ "$moved" = "$change_env" ] || fail "the change moved the images of: $moved"
[ "$(finished changed)" = "$expect_rerun" ] \
    || fail "the change ran: $(finished changed); expected: $expect_rerun"
ok "$change_package in $change_env: $(image_of "$change_env") built; ran $(finished changed)"

# 7
before=$(cat results/containers/images.json)
old=$(image_of "$change_env")
mkdir -p workflow/containers
{
    cat workflow/template/container.def
    printf '\n%%labels\n    recipe %s\n' "$change_env"
} > "workflow/containers/$change_env.def"
run custom pixi run snakemake --cores "$cores"
[ "$(built custom)" -eq 1 ] || fail "the own recipe built $(built custom) images"
[ ! -e "$old" ] || fail "the old image $old is still there"
moved=$(printf '%s\n' "$before" | diff - results/containers/images.json \
    | sed -n 's/^> *"\([^"]*\)".*/\1/p' | tr '\n' ' ' | sed 's/ $//')
[ "$moved" = "$change_env" ] || fail "the own recipe moved the images of: $moved"
[ "$(finished custom)" = "$expect_rerun" ] \
    || fail "the own recipe ran: $(finished custom); expected: $expect_rerun"
ok "workflow/containers/$change_env.def: $(image_of "$change_env") built; ran $(finished custom)"

# 8
base=$(sed -n 's/^From: //p' workflow/template/container.def)
printf 'Bootstrap: docker\nFrom: %s\n\n%%post\n    echo plain > /plain-recipe\n' \
    "$base" > workflow/containers/plain.def
cat >> workflow/Snakefile <<'RULE'


rule plain_image:
    output:
        "results/plain.txt",
    container:
        image("plain")
    shell:
        "cat /plain-recipe > {output}"
RULE
run plain pixi run snakemake --cores "$cores" \
    results/plain.txt results/provenance/run-info.tsv
[ "$(built plain)" -eq 1 ] || fail "the plain recipe built $(built plain) images"
[ "$(cat results/plain.txt)" = plain ] || fail "the rule did not run in the plain image"
grep -q '^container_plain_sha256	' results/provenance/run-info.tsv \
    || fail "run-info.tsv has no checksum for the plain image"
[ ! -e .pixi/envs/plain ] || fail "the run installed .pixi/envs/plain"
ok "workflow/containers/plain.def, no pixi environment: $(image_of plain) built, ran, recorded"

# 9
rule=$(grep -l "pixi run -e $change_env " workflow/Snakefile workflow/template/rules.smk | head -1)
sed "s/pixi run -e $change_env /pixi run -e other-environment /" "$rule" > "$rule.new"
mv "$rule.new" "$rule"
if pixi run snakemake --cores 1 > "$work/mismatch.log" 2>&1; then
    fail "a rule running pixi run -e other-environment in the $change_env image succeeded"
fi
grep -q "pixi run -e other-environment, inside the $change_env image" "$work/mismatch.log" \
    || { tail -20 "$work/mismatch.log" >&2; fail "the image's message is not in the log"; }
ok "a mismatched pixi run -e stops: $(grep -m1 'inside the' "$work/mismatch.log")"

cd /
[ -n "${WORK:-}" ] || rm -rf "$work"
echo "PASSED"
