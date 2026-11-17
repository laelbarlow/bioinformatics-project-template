set -eu

usage() {
    cat <<'USAGE'
Usage: sh record-values.sh --output FILE [TABLE...]
USAGE
}

output=""

while [ "$#" -gt 0 ]; do
    case "$1" in
        --output)  output=$2; shift ;;
        -h|--help) usage; exit 0 ;;
        -*) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
        *) break ;;
    esac
    shift
done

if [ -z "$output" ]; then
    usage >&2
    exit 2
fi

{
    printf 'name\tvalue\n'
    printf 'run_date\t%s\n' "$(date '+%Y-%m-%d')"
    for table in "$@"; do
        tail -n +2 "$table"
    done
} > "$output"
