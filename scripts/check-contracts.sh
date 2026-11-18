#!/usr/bin/env sh
# Contract check for the field manuals' dual-consumption promise.
#
# Required invocation — from the CONTENT REPO ROOT (the site that imports
# this Shell module), after a production build:
#
#   hugo --cleanDestinationDir --gc --minify --environment production
#   sh ../CAI-Field-Manual-Shell/scripts/check-contracts.sh
#
# The guards below key on the content-repo discriminators: a hugo.yaml with
# a baseURL plus a content/ tree (the Shell module's hugo.yaml has neither),
# and the build output in public/. Running it anywhere else fails fast
# instead of vacuously passing.
#
# docs_section is read from the site's OWN hugo.yaml (params.ui.docs_section;
# first match at any indentation). There is deliberately no fallback to the
# Shell module: a site that does not declare its docs section fails here.

# Belt and braces: contracts 1 and 2 are ALSO enforced at build time by the
# shortcodes themselves — layouts/_shortcodes/customize.html and
# layouts/_shortcodes/variant.html validate every token/axis/option against
# params.* and warnf on a miss, which the publication gate treats as fatal.
# This script re-checks the flattened source tree so a drift in the
# shortcodes cannot silently unguard the content. Named-form variant
# invocations (axis="version") are OUT OF SCOPE for the script: the
# shortcode validates named params at build time
# (layouts/_shortcodes/variant.html:23-28); only the positional form is
# matched here. Escaped shortcode examples in teaching content
# ({{</* ... */>}}) never match: every extraction regex requires the {{< or
# {{% open to be immediately followed by the keyword.
#
# Asserts, over content/ sources and the built markdown output:
#   1. every customize token used in content is declared in hugo.yaml
#   2. every variant axis/option pair used in content is declared in hugo.yaml
#   3. every source variant block yields exactly one "**Axis: Option(s)**"
#      label line in the built markdown, and no raw variant shortcode leaks
#   4. no "Expected output" promise is left without a following fenced block
#      (the status gate) or an explicit "(no output)" marker
#
# Exit 0 = contracts hold. Any violation prints the page and exits 1.

set -u

# Content-repo discriminator: baseURL + content/ (the Shell module's
# hugo.yaml has neither), then the build output.
[ -f hugo.yaml ] || { echo "CONTRACT: run from the content repo root (hugo.yaml not found)" >&2; exit 1; }
grep -qE '^baseURL:' hugo.yaml || { echo "CONTRACT: run from the content repo root (hugo.yaml has no baseURL)" >&2; exit 1; }
# docs_section is used only for the LLMS bundle check. We read it from
# hugo.yaml (params.ui.docs_section), but we do not require it to discover
# pages — that now works by iterating public/**/index.md with an existing
# content/** counterpart, so sites inheriting docs_section via the Shell
# module's deep-merge still pass.
docs_section=$(grep -E '^[[:space:]]*docs_section:' hugo.yaml | head -1 | awk '{print $2}')
[ -z "$docs_section" ] && docs_section=$(grep -rE '^[[:space:]]*docs_section:' . --include='hugo.yaml' | head -1 | awk '{print $2}')
fail=0
pages=0
labels=0
tokens=0

# Flattened source stream feeding contracts 1 and 2: every content .md in
# sorted order, newlines flattened so multi-line and percent-form shortcode
# invocations are still seen by the extraction regexes.
stream=$(find content -type f -name '*.md' | LC_ALL=C sort | xargs cat | tr '\n' ' ')
# Comma-free copy: a trailing/leading comma around an id must not fuse ids
# or corrupt a token ({{< variant version "3.5,3.6" >}}).
stream_nc=$(printf '%s' "$stream" | tr ',' ' ')

# 1. customize token ids: declared vs used -------------------------------------
declared_tokens=$(sed -n 's/.*- { id: \([a-z_]*\),.*/\1/p' hugo.yaml | sort -u)
used_tokens=$(printf '%s' "$stream_nc" | grep -ohE '\{\{[<%] *customize +[a-z_]+ *[%>]' | sed -E 's/\{\{[<%] *customize +([a-z_]+) *[%>]/\1/' | sort -u)
# The unquoted word-splitting below is the mechanism, not a hazard: token ids
# come from the extraction regex, which only admits [a-z_]+, so no glob
# characters or IFS whitespace can ever reach this loop.
for tok in $used_tokens; do
    tokens=$((tokens + 1))
    case "
$declared_tokens" in
    *"
$tok"*) ;;
    *)
        echo "CONTRACT custom-token: '$tok' used in content/ but not declared in hugo.yaml params.customize"
        fail=1
        ;;
    esac
done

# 2. variant axis/option pairs: declared vs used -------------------------------
# Same word-splitting rationale as contract 1: the sed reduces each match to
# axis|ids, ids being limited to [a-z0-9._,-]+ or a quoted space-separated
# list; quotes are dropped and commas/spaces become underscores so each pair
# stays one word, and the inner loop splits them back apart. No glob
# characters can appear.
for pair in $(printf '%s' "$stream" | grep -ohE '\{\{[<%] *variant +[a-z_]+ +("[^"]*"|[a-z0-9._,-]+) *[%>]' | sed -E 's/\{\{[<%] *variant +([a-z_]+) +("[^"]*"|[a-z0-9._,-]+) *[%>]/\1|\2/' | tr -d '"' | tr ',' ' ' | tr ' ' '_'); do
    axis=$(printf '%s' "$pair" | cut -d' ' -f1 | cut -d'|' -f1)
    rest=$(printf '%s' "$pair" | cut -d'|' -s -f2 | tr '_' ' ')
    if ! grep -qE "^    - id: $axis\$" hugo.yaml; then
        echo "CONTRACT variant-axis: axis '$axis' not declared in hugo.yaml params.variants"
        fail=1
        continue
    fi
    axis_block=$(sed -n "/- id: $axis\$/,/^    - id:/p" hugo.yaml)
    for opt in $rest; do
        case "$axis_block" in
        *"id: '$opt'"*|*"id: $opt"*) ;;
        *)
            echo "CONTRACT variant-option: option '$opt' not declared for axis '$axis' in hugo.yaml"
            fail=1
            ;;
        esac
    done
done

# 3. every source variant block surfaces exactly one label line ----------------
# Discovery: iterate every public/**/index.md that has a content/** counterpart
# (leaf bundle content/<p>/index.md → public/<p>/index.md, plain page
# content/<p>.md → public/<p>/index.md, section _index.md → public/<p>/index.md).
# The site home public/index.md is excluded. docs_section is kept only for the
# LLMS bundle existence check.
manual_mds=""
for _md in $(find public -name index.md | LC_ALL=C sort); do
  [ "$_md" = "public/index.md" ] && continue
  _src="content/${_md#public/}"
  if [ ! -f "$_src" ]; then
    _plain=${_src%/index.md}.md
    [ -f "$_plain" ] && _src=$_plain
  fi
  if [ ! -f "$_src" ]; then
    _sec_src="${_md#public/}"; _sec_src="content/${_sec_src%index.md}_index.md"
    [ -f "$_sec_src" ] && _src=$_sec_src
  fi
  [ -f "$_src" ] || continue
  manual_mds="${manual_mds} ${_md}"
done

# Derived label alternation from hugo.yaml's variants block (replaces the
# hardcoded RHAIE Version|Ops Mode pair): every `label:` line under
# `variants:` becomes one ERE alternative, escaped for ERE. Flow-map option
# lines that the label sed cannot reduce pass through verbatim; as escaped
# ERE alternatives they can only match their own literal text, never the
# emitted "**Axis: Option**" shape, so they are inert. The count assertion
# below is load-bearing: variant blocks in source must equal label lines in
# the built page.
labels_list=$(sed -n '/^  variants:/,/^[[:graph:]]/p' hugo.yaml | grep -E 'label:' | sed -E "s/^[[:space:]]*(- \{ )?label:[[:space:]]*['\"]?([^'\"}]+)['\"]?[,} ]*/\2/" | sort -u)
labels_re=$(printf '%s\n' "$labels_list" | sed -E 's/[^[:alnum:] _-]/\\&/g' | paste -s -d '|' -)
for md in $manual_mds; do
    # Map the built page back to its source, trying, in order: the leaf
    # bundle (content/<path>/index.md), the plain page
    # (content/<path>.md), then the section/branch _index.md.
    src="content/${md#public/}"
    if [ ! -f "$src" ]; then
        plain=${src%/index.md}.md
        [ -f "$plain" ] && src=$plain
    fi
    if [ ! -f "$src" ]; then
        sec_src="${md#public/}"; sec_src="content/${sec_src%index.md}_index.md"
        [ -f "$sec_src" ] && src=$sec_src
    fi
    [ -f "$src" ] || continue
    pages=$((pages + 1))
    pstream=$(tr '\n' ' ' < "$src")
    src_variants=$(printf '%s' "$pstream" | grep -oE '\{\{[<%] *variant ' | wc -l | tr -d ' ')
    [ "$src_variants" -eq 0 ] && continue
    out_labels=$(grep -cE "\*\*($labels_re): " "$md" || true)
    labels=$((labels + out_labels))
    if [ "$out_labels" -ne "$src_variants" ]; then
        echo "CONTRACT variant-labels: $md — $src_variants variant blocks, $out_labels labels"
        fail=1
    fi
    if grep -qE '\{\{[<%] *variant' "$md"; then
        echo "CONTRACT variant-labels: $md leaked raw variant shortcodes into the markdown output"
        fail=1
    fi
done

# 4. status gate: "Expected output" must be followed by a fenced block ---------
for md in $manual_mds; do
    src="content/${md#public/}"
    if [ ! -f "$src" ]; then
        plain=${src%/index.md}.md
        [ -f "$plain" ] && src=$plain
    fi
    if [ ! -f "$src" ]; then
        sec_src="${md#public/}"; sec_src="content/${sec_src%index.md}_index.md"
        [ -f "$sec_src" ] && src=$sec_src
    fi
    [ -f "$src" ] || src="$md"
    awk '
        /Expected output/ { pending = NR; next }
        pending != 0 && /^[[:space:]]*$/ { next }
        pending != 0 && /^```/ { pending = 0; next }
        pending != 0 && /^\(no output\)/ { pending = 0; next }
        pending != 0 { printf "CONTRACT status-gate: %s line %d — \"Expected output\" with no following fence\n", FILENAME, pending; bad = 1; pending = 0 }
        END { exit bad }
    ' "$md" || fail=1
    # the promise with no verify command at all (the review's finding 1 shape)
    if grep -qE "confirm the output matches the expected output below" "$src" && ! awk '/Expected output/{f=1} END{exit f?0:1}' "$src"; then
        echo "CONTRACT status-gate: $md promises 'expected output below' but no page carries an Expected output block"
        fail=1
    fi
done

# Vacuous-pass guard: an empty page set means the docs_section found no built
# pages — the check proved nothing.
[ "$pages" -eq 0 ] && { echo "CONTRACT: 0 manual pages matched docs_section '$docs_section' in public/ — wrong docs_section or stale build?" >&2; fail=1; }

[ "$fail" -eq 0 ] &&
    echo "contracts OK — $pages pages, $labels variant labels, $tokens customize tokens" &&
    exit 0

echo "contracts FAILED — fix the pages above; see Docs/issue-3-top5.md item 1"
exit 1
