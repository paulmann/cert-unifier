#!/usr/bin/env bash
#
# Regression suite for cert-unifier.sh.
#
# Every check asserts a concrete observable: an exit code, a file that exists,
# a line in the log. The suite deliberately does not use `set -e`: it must keep
# running after the first failing expectation and report the whole picture.
#
# Portable: Linux (CI), macOS with bash 4+ and OpenSSL, and Git Bash on Windows.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
UNIFIER="$ROOT_DIR/cert-unifier.sh"
TMP_BASE=$(mktemp -d "${TMPDIR:-/tmp}/cert-unifier-tests.XXXXXX")
LOG_DIR="$TMP_BASE/_logs"
mkdir -p "$LOG_DIR"

PASS=0
FAIL=0
SKIP=0

# Portable timeout: GNU coreutils on Linux, gtimeout or nothing on macOS.
run_limited() {
    if command -v timeout >/dev/null 2>&1; then
        timeout 30 "$@"
    elif command -v gtimeout >/dev/null 2>&1; then
        gtimeout 30 "$@"
    else
        "$@"
    fi
}

# shellcheck disable=SC2329,SC2317  # invoked through `trap cleanup EXIT`
cleanup() { rm -rf "$TMP_BASE"; }
trap cleanup EXIT

log()  { echo "[TEST] $*"; }
pass() { echo "  PASS: $*"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $*"; FAIL=$((FAIL + 1)); }
skip() { echo "  SKIP: $*"; SKIP=$((SKIP + 1)); }

# expect <description> <expected> <actual>
expect() {
    if [[ "$2" == "$3" ]]; then
        pass "$1"
    else
        fail "$1 (expected '$2', got '$3')"
    fi
}

# run_unifier <logname> [args...] -> prints exit code, keeps output in $LOG_DIR/<logname>.{out,err}
run_unifier() {
    local name="$1"; shift
    local rc=0
    run_limited bash "$UNIFIER" "$@" >"$LOG_DIR/$name.out" 2>"$LOG_DIR/$name.err" < /dev/null
    rc=$?
    echo "$rc"
}

# Portable helpers: file mode and mtime.
file_mode() {
    local p="$1"
    if stat -c '%a' "$p" >/dev/null 2>&1; then
        stat -c '%a' "$p"
    elif stat -f '%Lp' "$p" >/dev/null 2>&1; then
        stat -f '%Lp' "$p"
    else
        echo "unsupported"
    fi
}

file_mtime() {
    local p="$1"
    if stat -c '%Y' "$p" >/dev/null 2>&1; then
        stat -c '%Y' "$p"
    elif stat -f '%m' "$p" >/dev/null 2>&1; then
        stat -f '%m' "$p"
    else
        echo 0
    fi
}

printf 'x' >"$TMP_BASE/_mode_probe"
chmod 600 "$TMP_BASE/_mode_probe"
if [[ "$(file_mode "$TMP_BASE/_mode_probe")" == "600" ]]; then
    MODE_CHECKED=true
else
    MODE_CHECKED=false   # chmod is emulated on this filesystem (e.g. Git Bash)
fi

# Subject syntax differs on MSYS shells, where a value starting with "/" is
# rewritten into a Windows path. Detect which form OpenSSL accepts here.
SUBJ_STYLE="/"
_probe_key="$TMP_BASE/_probe.key"
openssl genrsa -out "$_probe_key" 2048 2>/dev/null
if ! openssl req -new -x509 -key "$_probe_key" -out "$TMP_BASE/_probe.crt" -days 1 \
    -subj "/CN=probe" >/dev/null 2>&1; then
    SUBJ_STYLE="//"
fi
rm -f "$_probe_key" "$TMP_BASE/_probe.crt"

# gen_cert <dir> <name> [rsa|ec] [days]
gen_cert() {
    local dir="$1" name="$2" type="${3:-rsa}" days="${4:-365}"
    mkdir -p "$dir"
    if [[ "$type" == "ec" ]]; then
        openssl ecparam -name prime256v1 -genkey -noout -out "$dir/${name}.key" 2>/dev/null
    else
        openssl genrsa -out "$dir/${name}.key" 2048 2>/dev/null
    fi
    openssl req -new -x509 -key "$dir/${name}.key" -out "$dir/${name}.crt" \
        -days "$days" -subj "${SUBJ_STYLE}CN=${name}" 2>/dev/null
}

# gen_certbot <root> <domain> [rsa|ec]
gen_certbot() {
    local root="$1" domain="$2" type="${3:-rsa}"
    gen_cert "$root" "$domain" "$type"
    mkdir -p "$root/$domain"
    cp "$root/$domain.crt" "$root/$domain/fullchain.pem"
    cp "$root/$domain.key" "$root/$domain/privkey.pem"
}

# gen_legacy <dir> <domain> <suffix> [rsa|ec]
gen_legacy() {
    local dir="$1" domain="$2" suffix="$3" type="${4:-rsa}"
    gen_cert "$dir" "${domain}_le${suffix}" "$type"
    cp "$dir/${domain}_le${suffix}.crt" "$dir/${domain}_le${suffix}.crtca"
}

# -----------------------------------------------------------------------------
log "CLI surface"
# -----------------------------------------------------------------------------
expect "--version exits 0" 0 "$(run_limited bash "$UNIFIER" --version </dev/null >/dev/null 2>&1; echo $?)"
expect "--help exits 0" 0 "$(run_limited bash "$UNIFIER" --help </dev/null >/dev/null 2>&1; echo $?)"
VERSION_LINE=$(run_limited bash "$UNIFIER" --version 2>/dev/null | head -1)
SCRIPT_VERSION=$(sed -n 's/^readonly SCRIPT_VERSION="\(.*\)"$/\1/p' "$UNIFIER")
expect "--version reports the script version" "cert-unifier.sh $SCRIPT_VERSION" "$VERSION_LINE"
expect "unknown option fails with 1" 1 "$(run_unifier unknown --bogus)"
expect "missing root fails with 1" 1 "$(run_unifier missing /nonexistent-dir)"

# -----------------------------------------------------------------------------
log "Certbot layout"
# -----------------------------------------------------------------------------
D="$TMP_BASE/certbot"
gen_certbot "$D" "example.com"
RC=$(run_unifier certbot --no-tld-filter "$D")
PEM="$D/example.com/example.com.pem"
expect "run succeeds" 0 "$RC"
expect "bundle written" "yes" "$([[ -f "$PEM" ]] && echo yes || echo no)"
expect "bundle starts with the private key" "PRIVATE KEY" "$(head -1 "$PEM" | sed 's/^-----BEGIN //; s/-----.*//')"
expect "bundle carries a certificate" 1 "$(grep -c -- '-----BEGIN CERTIFICATE-----' "$PEM")"
if [[ "$MODE_CHECKED" == true ]]; then
    expect "bundle mode is 600" "600" "$(file_mode "$PEM")"
else
    skip "bundle mode (chmod is emulated on this filesystem)"
fi

# -----------------------------------------------------------------------------
log "Legacy layout"
# -----------------------------------------------------------------------------
D="$TMP_BASE/legacy"
gen_legacy "$D" "legacy.ru" 1
RC=$(run_unifier legacy --no-tld-filter "$D")
expect "legacy run succeeds" 0 "$RC"
expect "legacy bundle written" "yes" "$([[ -f "$D/legacy.ru.pem" ]] && echo yes || echo no)"

# -----------------------------------------------------------------------------
log "Key/certificate mismatch is refused (3.1.1 regression)"
# -----------------------------------------------------------------------------
D="$TMP_BASE/mismatch"
gen_certbot "$D" "mismatch.com"
openssl genrsa -out "$D/mismatch.com/privkey.pem" 2048 2>/dev/null
RC=$(run_unifier mismatch --no-tld-filter "$D")
expect "mismatch fails with 1" 1 "$RC"
expect "no bundle is written" "no" "$([[ -f "$D/mismatch.com/mismatch.com.pem" ]] && echo yes || echo no)"
expect "error names the mismatch" 1 "$(grep -c 'does NOT match' "$LOG_DIR/mismatch.err")"
RC=$(run_unifier mismatch-skip --no-tld-filter --skip-pfx-on-mismatch "$D")
expect "--skip-pfx-on-mismatch continues" 0 "$RC"
expect "--skip-pfx-on-mismatch still writes nothing" "no" "$([[ -f "$D/mismatch.com/mismatch.com.pem" ]] && echo yes || echo no)"

# The documented environment variable must behave like the flag (3.1.2 fix).
D="$TMP_BASE/envmismatch"
gen_certbot "$D" "envmismatch.com"
openssl genrsa -out "$D/envmismatch.com/privkey.pem" 2048 2>/dev/null
RC=$(export NO_KEY_VALIDATION=true; run_unifier envmismatch --no-tld-filter "$D")
expect "NO_KEY_VALIDATION=true bundles unverifiable material" 0 "$RC"
expect "NO_KEY_VALIDATION=true writes the bundle" "yes" "$([[ -f "$D/envmismatch.com/envmismatch.com.pem" ]] && echo yes || echo no)"
expect "the opt-out is reported as a warning" 1 "$(grep -c 'validation disabled' "$LOG_DIR/envmismatch.err")"

# -----------------------------------------------------------------------------
log "A missing private key is refused (3.1.1 regression)"
# -----------------------------------------------------------------------------
D="$TMP_BASE/nokey"
gen_legacy "$D" "nokey.com" 1
rm -f "$D/nokey.com_le1.key"
RC=$(run_unifier nokey --no-tld-filter "$D")
expect "missing key fails with 1" 1 "$RC"
expect "no key-less bundle is written" "no" "$([[ -f "$D/nokey.com.pem" ]] && echo yes || echo no)"

# -----------------------------------------------------------------------------
log "Legacy multi-digit suffix and newest generation (3.1.1 regression)"
# -----------------------------------------------------------------------------
D="$TMP_BASE/le10"
gen_legacy "$D" "ten.com" 1
sleep 1
gen_legacy "$D" "ten.com" 10
RC=$(run_unifier le10 --no-tld-filter "$D")
expect "_le10 run succeeds" 0 "$RC"
expect "bundle written for _le10" "yes" "$([[ -f "$D/ten.com.pem" ]] && echo yes || echo no)"
if [[ -f "$D/ten.com.pem" ]]; then
    expect "newest generation wins" \
        "$(openssl x509 -in "$D/ten.com_le10.crt" -noout -fingerprint -sha256 2>/dev/null)" \
        "$(openssl x509 -in "$D/ten.com.pem" -noout -fingerprint -sha256 2>/dev/null)"
fi

# -----------------------------------------------------------------------------
log "Dry run"
# -----------------------------------------------------------------------------
D="$TMP_BASE/dryrun"
gen_certbot "$D" "dry.com"
RC=$(run_unifier dryrun --dry-run --no-tld-filter "$D")
expect "dry-run succeeds (3.1.1 regression)" 0 "$RC"
expect "dry-run writes no bundle" "no" "$([[ -f "$D/dry.com/dry.com.pem" ]] && echo yes || echo no)"
expect "dry-run reports the plan" 1 "$(grep -c 'DRY-RUN' "$LOG_DIR/dryrun.out")"

# -----------------------------------------------------------------------------
log "Idempotency"
# -----------------------------------------------------------------------------
D="$TMP_BASE/idem"
gen_certbot "$D" "idem.com"
run_unifier idem1 --no-tld-filter "$D" >/dev/null
BEFORE=$(file_mtime "$D/idem.com/idem.com.pem")
sleep 1
RC=$(run_unifier idem2 --no-tld-filter "$D")
AFTER=$(file_mtime "$D/idem.com/idem.com.pem")
expect "second run succeeds" 0 "$RC"
expect "unchanged content is reported" 1 "$(grep -c 'Unchanged' "$LOG_DIR/idem2.out")"
expect "file is not rewritten" "$BEFORE" "$AFTER"

# -----------------------------------------------------------------------------
log "JSON summary (3.1.1 regression)"
# -----------------------------------------------------------------------------
D="$TMP_BASE/json"
gen_certbot "$D" "json1.com"
gen_certbot "$D" "json2.com"
RC=$(run_unifier json --no-tld-filter --json "$D")
expect "json run succeeds" 0 "$RC"
JSON_OUT="$LOG_DIR/json.out"
PY=""
for candidate in python3 python; do
    if command -v "$candidate" >/dev/null 2>&1 && "$candidate" -c 'import json' >/dev/null 2>&1; then
        PY="$candidate"
        break
    fi
done
if [[ -n "$PY" ]]; then
    expect "json parses" 0 "$("$PY" -c 'import json,sys; json.load(open(sys.argv[1]))' "$JSON_OUT" >/dev/null 2>&1; echo $?)"
    expect "json lists both results" 2 "$("$PY" -c 'import json,sys; print(len(json.load(open(sys.argv[1]))["results"]))' "$JSON_OUT" 2>/dev/null)"
    expect "json status is success" "success" "$("$PY" -c 'import json,sys; print(json.load(open(sys.argv[1]))["status"])' "$JSON_OUT" 2>/dev/null)"
else
    skip "json validity (no python interpreter)"
fi
EMPTY="$TMP_BASE/empty"
mkdir -p "$EMPTY"
expect "empty tree fails with 2" 2 "$(run_unifier json-empty --no-tld-filter --json "$EMPTY")"
if [[ -n "$PY" ]]; then
    expect "empty json status is none" "none" "$("$PY" -c 'import json,sys; print(json.load(open(sys.argv[1]))["status"])' "$LOG_DIR/json-empty.out" 2>/dev/null)"
fi

# -----------------------------------------------------------------------------
log "EC keys"
# -----------------------------------------------------------------------------
D="$TMP_BASE/ec"
gen_certbot "$D" "ec.example.com" ec
RC=$(run_unifier ec --no-tld-filter "$D")
expect "EC run succeeds" 0 "$RC"
expect "EC bundle written" "yes" "$([[ -f "$D/ec.example.com/ec.example.com.pem" ]] && echo yes || echo no)"

# -----------------------------------------------------------------------------
log "PKCS#12 export (3.1.1 regression)"
# -----------------------------------------------------------------------------
D="$TMP_BASE/pfx"
gen_certbot "$D" "pfx.com"
RC=$(run_unifier pfx --no-tld-filter --pfx --pfx-password 'S3cret!' "$D")
expect "pfx run succeeds" 0 "$RC"
expect "pfx written" "yes" "$([[ -f "$D/pfx.com/pfx.com.pfx" ]] && echo yes || echo no)"
if [[ -f "$D/pfx.com/pfx.com.pfx" ]]; then
    expect "pfx opens with the password" 0 \
        "$(openssl pkcs12 -in "$D/pfx.com/pfx.com.pfx" -passin 'pass:S3cret!' -noout >/dev/null 2>&1 </dev/null; echo $?)"
fi
D="$TMP_BASE/pfx-ec"
gen_certbot "$D" "pfxec.com" ec
RC=$(run_unifier pfx-ec --no-tld-filter --pfx --pfx-password 'ecpass' "$D")
expect "EC pfx run succeeds" 0 "$RC"
expect "EC pfx opens with the password" 0 \
    "$(openssl pkcs12 -in "$D/pfxec.com/pfxec.com.pfx" -passin 'pass:ecpass' -noout >/dev/null 2>&1 </dev/null; echo $?)"

# -----------------------------------------------------------------------------
log "Passphrase-protected key is reported, never prompted for (3.1.1 regression)"
# -----------------------------------------------------------------------------
D="$TMP_BASE/encrypted"
gen_cert "$D" "enc.com"
mkdir -p "$D/enc.com"
cp "$D/enc.com.crt" "$D/enc.com/fullchain.pem"
openssl pkey -in "$D/enc.com.key" -aes256 -passout pass:secret -out "$D/enc.com/privkey.pem" 2>/dev/null
START=$(date +%s)
RC=$(run_unifier encrypted --no-tld-filter "$D")
ELAPSED=$(( $(date +%s) - START ))
expect "encrypted key fails with 1" 1 "$RC"
expect "run does not block on the prompt" "yes" "$([[ "$ELAPSED" -lt 20 ]] && echo yes || echo no)"
expect "no bundle is written" "no" "$([[ -f "$D/enc.com/enc.com.pem" ]] && echo yes || echo no)"
expect "error explains the passphrase" 0 "$(grep -qi 'passphrase-protected' "$LOG_DIR/encrypted.err"; echo $?)"

# -----------------------------------------------------------------------------
log "Structurally invalid key is refused"
# -----------------------------------------------------------------------------
D="$TMP_BASE/garbage"
gen_cert "$D" "garbage.com"
mkdir -p "$D/garbage.com"
cp "$D/garbage.com.crt" "$D/garbage.com/fullchain.pem"
# A PEM header assembled at run time: the literal is a test fixture, not a key,
# and a source file must not contain a private-key block that secret scanners
# (including `ghagent privacy`) flag.
PEM_LABEL='PRIVATE KEY'
printf -- '-----BEGIN %s-----\nAAAA\n-----END %s-----\n' "$PEM_LABEL" "$PEM_LABEL" >"$D/garbage.com/privkey.pem"
RC=$(run_unifier garbage --no-tld-filter "$D")
expect "garbage key fails with 1" 1 "$RC"
expect "no bundle is written" "no" "$([[ -f "$D/garbage.com/garbage.com.pem" ]] && echo yes || echo no)"

# -----------------------------------------------------------------------------
log "Output directory, recursion and TLD filter"
# -----------------------------------------------------------------------------
D="$TMP_BASE/outdir"
gen_certbot "$D" "od.com"
O="$TMP_BASE/outdir-target"
mkdir -p "$O"
RC=$(run_unifier outdir --no-tld-filter -o "$O" "$D")
expect "output-dir run succeeds" 0 "$RC"
expect "output lands in the override directory" "yes" "$([[ -f "$O/od.com.pem" ]] && echo yes || echo no)"
expect "output does not land next to the source" "no" "$([[ -f "$D/od.com/od.com.pem" ]] && echo yes || echo no)"

D="$TMP_BASE/nested"
mkdir -p "$D/deep/er"
gen_legacy "$D/deep/er" "deep.com" 1
expect "nested tree needs --recursive" 2 "$(run_unifier nested-plain --no-tld-filter "$D")"
expect "--recursive finds the nested tree" 0 "$(run_unifier nested-rec --no-tld-filter --recursive "$D")"
expect "--recursive writes the bundle" "yes" "$([[ -f "$D/deep/er/deep.com.pem" ]] && echo yes || echo no)"

D="$TMP_BASE/tld"
gen_certbot "$D" "site.org"
expect "a filtered TLD ends with 2" 2 "$(run_unifier tld "$D")"
expect "the TLD filter is explained" 1 "$(grep -c 'no-tld-filter' "$LOG_DIR/tld.err")"

# -----------------------------------------------------------------------------
log "Log level"
# -----------------------------------------------------------------------------
INFO_LINES=$(LOG_LEVEL=ERROR run_limited bash "$UNIFIER" --no-tld-filter --dry-run "$TMP_BASE/certbot" </dev/null 2>/dev/null | grep -c '\[INFO\]')
expect "LOG_LEVEL=ERROR silences INFO" 0 "$INFO_LINES"

# -----------------------------------------------------------------------------
log "Temporary files are cleaned up"
# -----------------------------------------------------------------------------
LEFTOVERS=$(find "$TMP_BASE" \( -name '.chain.*' -o -name '*.XXXXXX' -o -name '*.pem.new.*' \) 2>/dev/null | wc -l | tr -d ' ')
expect "no temporary files survive" 0 "$LEFTOVERS"

# -----------------------------------------------------------------------------
echo
echo "Results: $PASS passed, $FAIL failed, $SKIP skipped"
if (( FAIL > 0 )); then
    exit 1
fi
exit 0
