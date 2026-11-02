#!/usr/bin/env bash
#
# cert-unifier.sh — Generate audited unified PEM and optionally PFX bundles
# from Let's Encrypt / Certbot / legacy certificate layouts.
#
# Version: 3.1.1
# License: MIT
# Copyright (c) 2026 Mikhail Deynekin
#
# Major improvements in 3.x:
#   - Public-key comparison (RSA + EC), enforced on every PEM write
#   - Idempotent writes (skip if content identical)
#   - --json machine-readable summary
#   - Optional recursive scan
#   - Passphrase-protected keys are detected, never prompted for
#   - Atomic writes + umask 077
#   - Comprehensive exit codes and logging
#
# 3.1.1 fixes defects found while reviewing the unreleased 3.1.0 tree:
#   - key/cert mismatch is no longer accepted silently without --pfx
#   - a missing private key no longer produces a key-less "unified" PEM
#   - --json no longer truncates its output under set -e
#   - --pfx works on OpenSSL 3.x (-name, not the nonexistent -friendlyname)
#   - legacy _le10+ suffixes are found, and the newest one wins
#   - a passphrase-protected key is reported instead of hanging the run
#
set -euo pipefail
umask 077

# -----------------------------------------------------------------------------
# Constants
# -----------------------------------------------------------------------------
SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_NAME
readonly SCRIPT_VERSION="3.1.1"
readonly DEFAULT_ROOT="/var/www/httpd-cert"
readonly MIN_PEM_SIZE=200
readonly PEM_MODE=600
readonly LOCK_FILE="${CERT_UNIFIER_LOCK:-/var/lock/cert-unifier.lock}"
readonly LOG_TS_FMT="+%Y-%m-%d %H:%M:%S"

# -----------------------------------------------------------------------------
# Globals
# -----------------------------------------------------------------------------
ALLOWED_TLDS="${ALLOWED_TLDS:-ru com}"
NO_TLD_FILTER=false
NO_KEY_VALIDATION=false
GENERATE_PFX=false
SKIP_PFX_ON_MISMATCH=false
CHECK_EXPIRY=false
EXPIRY_WARN_DAYS=30
RECURSIVE=false
JSON_OUTPUT=false
PFX_PASSWORD="${PFX_PASSWORD:-}"
LOG_LEVEL="${LOG_LEVEL:-INFO}"
OUTPUT_DIR_OVERRIDE=""
DRY_RUN=false
VERBOSE=false

TOTAL_PROCESSED=0
TOTAL_SKIPPED=0
TOTAL_PLANNED=0   # entries a --dry-run would have written
TOTAL_ERRORS=0
TOTAL_WARNINGS=0

declare -a TMP_FILES=()
declare -a RESULTS=()   # for JSON summary
declare -a WRITTEN_TARGETS=()   # detects two sources mapping to one output

# -----------------------------------------------------------------------------
# Logging
# -----------------------------------------------------------------------------
_log() {
    local level="$1"; shift
    local msg="$*"
    local ts
    ts="$(date "$LOG_TS_FMT" 2>/dev/null || echo "0000-00-00 00:00:00")"

    # Suppress normal logs when JSON mode is active (except errors)
    if [[ "$JSON_OUTPUT" == true && "$level" != "ERROR" && "$level" != "WARN" ]]; then
        return 0
    fi

    # Honour LOG_LEVEL: ERROR=0, WARN=1, INFO=2, DEBUG=3
    local max_level=2 level_num=2
    case "${LOG_LEVEL:-INFO}" in
        DEBUG) max_level=3 ;;
        WARN)  max_level=1 ;;
        ERROR) max_level=0 ;;
    esac
    case "$level" in
        ERROR) level_num=0 ;;
        WARN)  level_num=1 ;;
        INFO)  level_num=2 ;;
        DEBUG) level_num=3 ;;
    esac
    (( level_num <= max_level )) || return 0

    case "$level" in
        ERROR|WARN)
            if [[ -t 2 ]]; then
                case "$level" in
                    ERROR) echo -e "\e[31m[$ts] [ERROR]\e[0m $msg" >&2 ;;
                    WARN)  echo -e "\e[33m[$ts] [WARN]\e[0m $msg" >&2 ;;
                esac
            else
                echo "[$ts] [$level] $msg" >&2
            fi
            ;;
        INFO)
            if [[ -t 1 ]]; then
                echo -e "\e[32m[$ts] [INFO]\e[0m $msg"
            else
                echo "[$ts] [INFO] $msg"
            fi
            ;;
        DEBUG)
            [[ "$LOG_LEVEL" == "DEBUG" || "$VERBOSE" == true ]] || return 0
            if [[ -t 1 ]]; then
                echo -e "\e[36m[$ts] [DEBUG]\e[0m $msg"
            else
                echo "[$ts] [DEBUG] $msg"
            fi
            ;;
    esac
}

log_info()  { _log INFO  "$@"; }
log_warn()  { _log WARN  "$@"; ((TOTAL_WARNINGS++)) || true; }
log_error() { _log ERROR "$@"; ((TOTAL_ERRORS++)) || true; }
log_debug() { _log DEBUG "$@"; }

# -----------------------------------------------------------------------------
# Cleanup
# -----------------------------------------------------------------------------
# shellcheck disable=SC2329,SC2317  # invoked through `trap cleanup EXIT`
cleanup() {
    local f
    # Guard the expansion: under `set -u`, Bash 4.0-4.3 treats an empty array
    # expansion as an unbound variable.
    if (( ${#TMP_FILES[@]} > 0 )); then
        for f in "${TMP_FILES[@]}"; do
            if [[ -n "$f" && -e "$f" ]]; then
                rm -f "$f" 2>/dev/null || true
            fi
        done
    fi
}
trap cleanup EXIT
trap 'log_warn "Interrupted"; exit 130' INT TERM

# -----------------------------------------------------------------------------
# Help / version
# -----------------------------------------------------------------------------
show_help() {
    cat <<EOF
${SCRIPT_NAME} ${SCRIPT_VERSION}

Assemble audited PEM (key + full chain) and optional PKCS#12 (PFX) bundles
from Certbot and legacy Let's Encrypt layouts.

USAGE:
    $SCRIPT_NAME [OPTIONS] [ROOT_DIRECTORY]

OPTIONS:
    -h, --help                  Show this help
    -V, --version               Show version
    -d, --dry-run               Validate and report without writing final files
    -v, --verbose               Enable DEBUG logging
    -t, --tlds LIST             Allowed TLDs (comma or space separated)
    -o, --output-dir PATH       Write outputs here instead of next to sources
    --no-tld-filter             Process every domain
    --no-key-validation         Skip deep private-key validation
    --pfx                       Also generate .pfx files
    --pfx-password PASS         Password for PFX
    --skip-pfx-on-mismatch      Continue if key/cert do not match
    --check-expiry              Warn about certificates expiring soon
    --expiry-days N             Days threshold for expiry warning (default: 30)
    --recursive                 Scan subdirectories recursively (legacy layout)
    --json                      Emit machine-readable JSON summary to stdout

ENVIRONMENT:
    ALLOWED_TLDS, LOG_LEVEL, PFX_PASSWORD, CERT_UNIFIER_LOCK, NO_KEY_VALIDATION

EXIT CODES:
    0  Success
    1  Runtime / validation error
    2  No matching certificates found
    130 Interrupted
EOF
}

show_version() {
    echo "${SCRIPT_NAME} ${SCRIPT_VERSION}"
    echo "Copyright (c) 2026 Mikhail Deynekin"
    echo "License: MIT"
}

# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------
is_allowed_tld() {
    local domain="$1"
    [[ "$NO_TLD_FILTER" == true ]] && return 0
    local tld
    for tld in $ALLOWED_TLDS; do
        [[ "$domain" == *."$tld" || "$domain" == "$tld" ]] && return 0
    done
    return 1
}

abspath() {
    local p="$1"
    if command -v realpath >/dev/null 2>&1 && realpath -m "$p" >/dev/null 2>&1; then
        realpath -m "$p"
    elif command -v readlink >/dev/null 2>&1 && readlink -f "$p" >/dev/null 2>&1; then
        readlink -f "$p"
    else
        (cd "$(dirname "$p")" 2>/dev/null && printf '%s/%s\n' "$(pwd)" "$(basename "$p")") || printf '%s\n' "$p"
    fi
}

# -----------------------------------------------------------------------------
# Cryptographic helpers
# -----------------------------------------------------------------------------
# Prints the SHA-256 fingerprint of a public key on stdout.
# Exit status tells the caller why there is no hash:
#   0 = hash computed, 1 = cannot read/parse, 2 = passphrase-protected key
get_pubkey_hash() {
    local file="$1"
    local kind="$2"   # cert | key
    local pub=""

    if [[ ! -f "$file" || ! -s "$file" ]]; then
        return 1
    fi

    if [[ "$kind" == "cert" ]]; then
        pub=$(openssl x509 -in "$file" -noout -pubkey 2>/dev/null) || return 1
    else
        # Never hand a passphrase-protected key to OpenSSL: it would block on
        # the passphrase prompt instead of failing.
        if grep -q "ENCRYPTED" "$file" 2>/dev/null; then
            return 2
        fi
        pub=$(openssl pkey -in "$file" -pubout 2>/dev/null) || \
        pub=$(openssl rsa  -in "$file" -pubout 2>/dev/null) || \
        pub=$(openssl ec   -in "$file" -pubout 2>/dev/null) || return 1
    fi

    [[ -n "$pub" ]] || return 1
    printf '%s' "$pub" | openssl dgst -sha256 2>/dev/null | awk '{print $NF}'
}

# Compare the public key of key_file with the leaf certificate in cert_file.
#   0 = match, 1 = mismatch, 2 = key is passphrase-protected,
#   3 = certificate public key unreadable, 4 = key public key unreadable
verify_key_matches_cert() {
    local key_file="$1"
    local cert_file="$2"
    local cert_h="" key_h="" status=0

    [[ -n "$key_file" && -f "$key_file" ]] || return 4
    cert_h=$(get_pubkey_hash "$cert_file" cert) || return 3
    # The `|| status=$?` form keeps `set -e` from aborting on a non-zero status.
    key_h=$(get_pubkey_hash "$key_file" key) || status=$?
    case "$status" in
        0) : ;;
        2) return 2 ;;
        *) return 4 ;;
    esac

    [[ "$cert_h" == "$key_h" ]] && return 0
    return 1
}

validate_pem() {
    local file="$1"
    local expected="${2:-any}"

    [[ -f "$file" && -s "$file" ]] || return 1
    grep -q -- "-----BEGIN " "$file" || return 1

    command -v openssl >/dev/null 2>&1 || return 0

    # A passphrase-protected key would make OpenSSL wait for input, so the
    # header is all we can check here. The caller decides what to do with it.
    if [[ "$expected" != "cert" ]] && grep -q "ENCRYPTED" "$file" 2>/dev/null; then
        log_warn "Passphrase-protected key: $file (OpenSSL validation skipped)"
        return 0
    fi

    local ok=false
    if [[ "$expected" == "cert" || "$expected" == "any" ]]; then
        openssl x509 -in "$file" -noout -text >/dev/null 2>&1 && ok=true
    fi
    if [[ "$expected" == "key" || "$expected" == "any" ]]; then
        if openssl pkey -in "$file" -noout -text >/dev/null 2>&1 || \
           openssl rsa  -in "$file" -noout -text >/dev/null 2>&1 || \
           openssl ec   -in "$file" -noout -text >/dev/null 2>&1; then
            ok=true
        fi
    fi

    [[ "$ok" == true ]] && return 0

    log_warn "OpenSSL could not fully validate $file (header present) — accepting with warning"
    return 0
}

cat_with_newline() {
    local file="$1"
    [[ -f "$file" && -s "$file" ]] || return 0
    cat "$file"
    local last
    last=$(tail -c1 "$file" 2>/dev/null || true)
    if [[ -n "$last" && "$last" != $'\n' ]]; then
        printf '\n'
    fi
    return 0
}

files_identical() {
    local a="$1" b="$2"
    [[ -f "$a" && -f "$b" ]] || return 1
    cmp -s "$a" "$b"
}

# Escape a string for a JSON string literal.
json_escape() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\n'/\\n}"
    s="${s//$'\r'/\\r}"
    s="${s//$'\t'/\\t}"
    printf '%s' "$s"
}

# Append one entry to the machine-readable summary.
add_result() {
    local domain="$1"
    local status="$2"
    local pem="$3"
    local fingerprint="${4:-}"
    local entry
    if [[ -n "$fingerprint" ]]; then
        entry=$(printf '{"domain":"%s","status":"%s","pem":"%s","fingerprint":"%s"}' \
            "$(json_escape "$domain")" "$(json_escape "$status")" \
            "$(json_escape "$pem")" "$(json_escape "$fingerprint")")
    else
        entry=$(printf '{"domain":"%s","status":"%s","pem":"%s"}' \
            "$(json_escape "$domain")" "$(json_escape "$status")" "$(json_escape "$pem")")
    fi
    RESULTS+=("$entry")
}

# -----------------------------------------------------------------------------
# PFX
# -----------------------------------------------------------------------------
generate_pfx() {
    local key_file="$1"
    local chain_file="$2"
    local pfx_file="$3"
    local dry="${4:-false}"

    if [[ "$dry" == true ]]; then
        log_info "[DRY-RUN] Would generate PFX: $pfx_file"
        return 0
    fi

    command -v openssl >/dev/null 2>&1 || {
        log_error "openssl missing — cannot generate PFX"
        return 1
    }

    local match_status=0
    verify_key_matches_cert "$key_file" "$chain_file" || match_status=$?
    case "$match_status" in
        0) : ;;
        2)
            log_warn "Skipping PFX $pfx_file (passphrase-protected key)"
            return 0
            ;;
        1)
            if [[ "$SKIP_PFX_ON_MISMATCH" == true ]]; then
                log_warn "Skipping PFX $pfx_file (key/cert mismatch)"
                return 0
            fi
            log_error "Key does not match certificate — aborting PFX for $pfx_file"
            return 1
            ;;
        *)
            log_error "Cannot verify key against certificate — aborting PFX for $pfx_file"
            return 1
            ;;
    esac

    local -a args=(
        pkcs12 -export
        -out "$pfx_file"
        -inkey "$key_file"
        -in "$chain_file"
        -passout "pass:${PFX_PASSWORD}"
    )

    # `-name` sets the friendly name in both OpenSSL 1.1.1 and 3.x. There is no
    # `-friendlyname` option in the pkcs12 command on any version.
    local name
    name=$(basename "${pfx_file%.pfx}")
    args+=(-name "$name")

    local err
    if ! err=$(openssl "${args[@]}" 2>&1); then
        log_error "PFX generation failed for $pfx_file: $err"
        return 1
    fi

    chmod "$PEM_MODE" "$pfx_file" 2>/dev/null || log_warn "Could not chmod 600 $pfx_file"
    log_info "Generated PFX: $pfx_file"
    return 0
}

# -----------------------------------------------------------------------------
# Atomic PEM writer (with idempotency)
# -----------------------------------------------------------------------------
atomic_write_pem() {
    local key_file="$1"
    local chain_file="$2"
    local dest_pem="$3"
    local dry="${4:-false}"
    local domain="${5:-unknown}"

    # A bundle without a private key, or with a key that does not belong to the
    # certificate, is worse than no bundle at all: refuse it before writing.
    if [[ -z "$key_file" || ! -f "$key_file" ]]; then
        log_error "No private key found for $domain — refusing to write $dest_pem"
        add_result "$domain" "error" "$dest_pem"
        return 1
    fi

    if [[ -d "$dest_pem" ]]; then
        log_error "Output path is a directory: $dest_pem — skipping $domain"
        add_result "$domain" "error" "$dest_pem"
        return 1
    fi

    if [[ "$NO_KEY_VALIDATION" != true ]]; then
        local verdict=0
        verify_key_matches_cert "$key_file" "$chain_file" || verdict=$?
        case "$verdict" in
            0) log_debug "Private key matches certificate: $domain" ;;
            1)
                if [[ "$SKIP_PFX_ON_MISMATCH" == true ]]; then
                    log_warn "Private key does NOT match certificate for $domain — skipping (--skip-pfx-on-mismatch)"
                    ((TOTAL_SKIPPED++)) || true
                    add_result "$domain" "skipped" "$dest_pem"
                    return 0
                fi
                log_error "Private key does NOT match certificate for $domain — refusing to write $dest_pem"
                add_result "$domain" "error" "$dest_pem"
                return 1
                ;;
            2)
                log_error "Private key is passphrase-protected: $key_file — cannot verify it; use --no-key-validation to bundle it anyway"
                add_result "$domain" "error" "$dest_pem"
                return 1
                ;;
            *)
                log_error "Cannot verify private key against certificate for $domain — refusing to write $dest_pem"
                add_result "$domain" "error" "$dest_pem"
                return 1
                ;;
        esac
    else
        log_debug "Private key validation disabled (--no-key-validation)"
    fi

    # Two layouts can resolve to one output (for example certbot and legacy
    # entries for the same domain under -o). Never overwrite in silence.
    if (( ${#WRITTEN_TARGETS[@]} > 0 )); then
        local t
        for t in "${WRITTEN_TARGETS[@]}"; do
            if [[ "$t" == "$dest_pem" ]]; then
                log_warn "Output collision: $dest_pem is produced by more than one source — the later one wins"
                break
            fi
        done
    fi
    WRITTEN_TARGETS+=("$dest_pem")

    local tmp
    tmp=$(mktemp "${dest_pem}.XXXXXX" 2>/dev/null || mktemp /tmp/cert-unifier.XXXXXX)
    TMP_FILES+=("$tmp")

    # Assemble content safely (avoid return/exit inside group)
    : > "$tmp"
    if [[ -n "$key_file" && -f "$key_file" ]]; then
        cat_with_newline "$key_file" >> "$tmp" || {
            log_error "Failed to read key for $dest_pem"
            return 1
        }
    fi
    if [[ -f "$chain_file" ]]; then
        cat_with_newline "$chain_file" >> "$tmp" || {
            log_error "Failed to read chain for $dest_pem"
            return 1
        }
    else
        log_error "Missing chain file: $chain_file"
        return 1
    fi

    local size
    size=$(wc -c < "$tmp" | tr -d ' ')
    if (( size < MIN_PEM_SIZE )); then
        log_warn "Assembled PEM too small ($size bytes) — skipping $dest_pem"
        return 1
    fi

    if ! validate_pem "$tmp" any; then
        log_error "Assembled PEM failed validation — discarding"
        return 1
    fi

    # Idempotency check
    if [[ -f "$dest_pem" ]] && files_identical "$tmp" "$dest_pem"; then
        # Content is already right, but the mode may not be: an older release
        # left 0644 bundles behind, and the private key must be 0600.
        chmod "$PEM_MODE" "$dest_pem" 2>/dev/null || true
        log_info "Unchanged: $dest_pem (content identical, mode enforced)"
        ((TOTAL_SKIPPED++)) || true
        add_result "$domain" "unchanged" "$dest_pem"
        if [[ "$GENERATE_PFX" == true && -n "$key_file" && "$dry" != true ]]; then
            generate_pfx "$key_file" "$chain_file" "${dest_pem%.pem}.pfx" false || true
        fi
        return 0
    fi

    if [[ "$dry" == true ]]; then
        log_info "[DRY-RUN] Would write $dest_pem ($size bytes)"
        ((TOTAL_PLANNED++)) || true
        add_result "$domain" "dry-run" "$dest_pem"
        if [[ "$GENERATE_PFX" == true && -n "$key_file" ]]; then
            generate_pfx "$key_file" "$chain_file" "${dest_pem%.pem}.pfx" true
        fi
        return 0
    fi

    chmod "$PEM_MODE" "$tmp" || {
        log_error "Failed to set mode $PEM_MODE on temporary PEM"
        return 1
    }

    if mv -f "$tmp" "$dest_pem"; then
        log_info "Updated $dest_pem ($size bytes, mode $PEM_MODE)"
        local fp
        fp=$(openssl x509 -in "$dest_pem" -noout -fingerprint -sha256 2>/dev/null | cut -d= -f2 || echo "unknown")
        log_debug "Fingerprint (SHA256): $fp"
        RESULTS+=("$(printf '{"domain":"%s","status":"updated","pem":"%s","fingerprint":"%s"}' \
            "$(json_escape "$domain")" "$(json_escape "$dest_pem")" "$(json_escape "$fp")")")

        if [[ "$GENERATE_PFX" == true && -n "$key_file" ]]; then
            generate_pfx "$key_file" "$chain_file" "${dest_pem%.pem}.pfx" false || true
        fi

        if [[ "$CHECK_EXPIRY" == true ]]; then
            check_expiry "$dest_pem"
        fi
        ((TOTAL_PROCESSED++)) || true
        return 0
    else
        log_error "Atomic rename failed for $dest_pem"
        return 1
    fi
}

check_expiry() {
    local pem="$1"
    command -v openssl >/dev/null 2>&1 || return 0
    local end
    end=$(openssl x509 -in "$pem" -noout -enddate 2>/dev/null | cut -d= -f2) || return 0
    local end_epoch now_epoch days
    end_epoch=$(date -d "$end" +%s 2>/dev/null || date -j -f "%b %d %T %Y %Z" "$end" +%s 2>/dev/null || echo 0)
    now_epoch=$(date +%s)
    days=$(( (end_epoch - now_epoch) / 86400 ))
    if (( days < 0 )); then
        log_warn "EXPIRED: $pem (expired $end)"
    elif (( days < EXPIRY_WARN_DAYS )); then
        log_warn "Expiring soon: $pem ($days days left)"
    else
        log_debug "Valid: $pem ($days days left)"
    fi
}

# -----------------------------------------------------------------------------
# Lock
# -----------------------------------------------------------------------------
acquire_lock() {
    if ! command -v flock >/dev/null 2>&1; then
        log_warn "flock not available — running without lock"
        return 0
    fi
    exec 200>"$LOCK_FILE" || {
        log_warn "Cannot create lock file $LOCK_FILE — continuing unlocked"
        return 0
    }
    if ! flock -n 200; then
        log_error "Another instance is running (lock: $LOCK_FILE)"
        exit 1
    fi
    log_debug "Lock acquired: $LOCK_FILE"
}

# -----------------------------------------------------------------------------
# Layout processors
# -----------------------------------------------------------------------------
process_certbot_layout() {
    local root="$1"
    local dry="$2"
    local domain_dir fullchain privkey domain output

    log_debug "Scanning Certbot layout under $root"

    for domain_dir in "$root"/*/; do
        [[ -d "$domain_dir" ]] || continue
        domain_dir="$(abspath "$domain_dir")"
        fullchain="$domain_dir/fullchain.pem"
        privkey="$domain_dir/privkey.pem"
        [[ -f "$fullchain" && -f "$privkey" ]] || continue

        domain=$(basename "$domain_dir")
        is_allowed_tld "$domain" || { log_debug "Skipping $domain (TLD filter)"; continue; }

        if [[ "$NO_KEY_VALIDATION" != true ]] && ! validate_pem "$privkey" key; then
            log_warn "Invalid key: $privkey — skipping $domain"
            continue
        fi
        validate_pem "$fullchain" cert || { log_warn "Invalid chain: $fullchain"; continue; }

        output="${OUTPUT_DIR_OVERRIDE:-$domain_dir}/${domain}.pem"
        atomic_write_pem "$privkey" "$fullchain" "$output" "$dry" "$domain" || true
    done
}

process_legacy_layout() {
    local root="$1"
    local dry="$2"
    local dir crt base domain le_suffix candidate key_file chain output tmp_chain

    log_debug "Scanning legacy layout under $root (recursive=$RECURSIVE)"

    local -a dirs=("$root")
    if [[ "$RECURSIVE" == true ]]; then
        while IFS= read -r -d '' sub; do
            dirs+=("$sub")
        done < <(find "$root" -mindepth 1 -type d -print0 2>/dev/null)
    else
        local sub
        for sub in "$root"/*/; do
            if [[ -d "$sub" ]]; then
                dirs+=("$(abspath "$sub")")
            fi
        done
    fi

    for dir in "${dirs[@]}"; do
        shopt -s nullglob
        local -a crts=("$dir"/*_le[0-9]*.crt)
        shopt -u nullglob
        if (( ${#crts[@]} == 0 )); then
            continue
        fi

        # One output per domain: when several renewal generations sit in the
        # same directory (_le1, _le10, ...), the highest suffix is the newest.
        local -a domains=()
        local d seen
        for crt in "${crts[@]}"; do
            base=$(basename "$crt")
            if [[ ! "$base" =~ ^(.+)_le([0-9]+)\.crt$ ]]; then
                log_warn "Unexpected certificate name: $crt"
                continue
            fi
            domain="${BASH_REMATCH[1]}"
            is_allowed_tld "$domain" || { log_debug "Skipping $domain (TLD filter)"; continue; }
            seen=false
            for d in "${domains[@]}"; do
                if [[ "$d" == "$domain" ]]; then
                    seen=true
                fi
            done
            if [[ "$seen" == false ]]; then
                domains+=("$domain")
            fi
        done

        for domain in "${domains[@]}"; do
            local max_suffix=0 suffix_num
            for crt in "${crts[@]}"; do
                base=$(basename "$crt")
                if [[ "$base" =~ ^(.+)_le([0-9]+)\.crt$ ]] && [[ "${BASH_REMATCH[1]}" == "$domain" ]]; then
                    suffix_num=$(( 10#${BASH_REMATCH[2]} ))
                    if (( suffix_num > max_suffix )); then
                        max_suffix=$suffix_num
                    fi
                fi
            done
            le_suffix="$max_suffix"

            chain="$dir/${domain}_le${le_suffix}.crtca"
            if [[ ! -f "$chain" ]]; then
                log_error "Missing chain file for $domain: $chain"
                add_result "$domain" "error" "${OUTPUT_DIR_OVERRIDE:-$dir}/${domain}.pem"
                continue
            fi

            key_file=""
            for candidate in "$dir/${domain}_le${le_suffix}.key" "$dir/${domain}.key"; do
                if [[ -f "$candidate" ]]; then
                    key_file="$candidate"
                    break
                fi
            done

            if [[ -n "$key_file" && "$NO_KEY_VALIDATION" != true ]]; then
                validate_pem "$key_file" key || { log_error "Invalid private key: $key_file"; continue; }
            fi
            validate_pem "$chain" cert || { log_error "Invalid chain file: $chain"; continue; }

            tmp_chain=$(mktemp "${dir}/.chain.XXXXXX") || {
                log_error "Cannot create a temporary chain file in $dir"
                continue
            }
            TMP_FILES+=("$tmp_chain")
            {
                cat_with_newline "$dir/${domain}_le${le_suffix}.crt"
                cat_with_newline "$chain"
            } > "$tmp_chain"

            output="${OUTPUT_DIR_OVERRIDE:-$dir}/${domain}.pem"
            atomic_write_pem "$key_file" "$tmp_chain" "$output" "$dry" "$domain" || true
        done
    done
}

# -----------------------------------------------------------------------------
# JSON summary
# -----------------------------------------------------------------------------
emit_json() {
    [[ "$JSON_OUTPUT" == true ]] || return 0
    local status="success"
    if (( TOTAL_ERRORS > 0 )); then
        status="error"
    elif (( TOTAL_PROCESSED == 0 && TOTAL_SKIPPED == 0 && TOTAL_PLANNED == 0 )); then
        status="none"
    fi

    printf '{\n'
    printf '  "version": "%s",\n' "$SCRIPT_VERSION"
    printf '  "status": "%s",\n' "$status"
    printf '  "processed": %d,\n' "$TOTAL_PROCESSED"
    printf '  "skipped": %d,\n' "$TOTAL_SKIPPED"
    printf '  "planned": %d,\n' "$TOTAL_PLANNED"
    printf '  "errors": %d,\n' "$TOTAL_ERRORS"
    printf '  "warnings": %d,\n' "$TOTAL_WARNINGS"
    printf '  "results": [\n'
    local i=0
    local r
    if (( ${#RESULTS[@]} > 0 )); then
        for r in "${RESULTS[@]}"; do
            if (( i > 0 )); then
                printf ',\n'
            fi
            printf '    %s' "$r"
            i=$(( i + 1 ))
        done
        printf '\n'
    fi
    printf '  ]\n}\n'
}

# -----------------------------------------------------------------------------
# Environment
# -----------------------------------------------------------------------------
environment_check() {
    log_info "=== Environment ==="
    log_info "Version: $SCRIPT_VERSION"
    log_info "Bash: $BASH_VERSION"
    if command -v openssl >/dev/null 2>&1; then
        log_info "OpenSSL: $(openssl version 2>/dev/null | head -1)"
    else
        log_warn "OpenSSL not found — limited validation"
        [[ "$GENERATE_PFX" == true ]] && { log_error "PFX requested but openssl missing"; exit 1; }
    fi
    if command -v flock >/dev/null 2>&1; then
        log_debug "flock available"
    else
        log_warn "flock missing"
    fi
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------
main() {
    # Handle help/version early
    local arg
    for arg in "$@"; do
        case "$arg" in
            -h|--help) show_help; exit 0 ;;
            -V|--version) show_version; exit 0 ;;
        esac
    done

    # Parse remaining arguments (must not use command substitution — it creates a subshell)
    local root_dir=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -d|--dry-run) DRY_RUN=true; shift ;;
            -v|--verbose) VERBOSE=true; LOG_LEVEL=DEBUG; shift ;;
            -t|--tlds)
                [[ -n "${2:-}" ]] || { log_error "--tlds requires a value"; exit 1; }
                ALLOWED_TLDS="${2//,/ }"
                shift 2
                ;;
            -o|--output-dir)
                [[ -n "${2:-}" ]] || { log_error "--output-dir requires a path"; exit 1; }
                OUTPUT_DIR_OVERRIDE="$2"
                shift 2
                ;;
            --no-tld-filter) NO_TLD_FILTER=true; shift ;;
            --no-key-validation) NO_KEY_VALIDATION=true; shift ;;
            --pfx) GENERATE_PFX=true; shift ;;
            --pfx-password)
                [[ -n "${2:-}" ]] || { log_error "--pfx-password requires a value"; exit 1; }
                PFX_PASSWORD="$2"
                shift 2
                ;;
            --skip-pfx-on-mismatch) SKIP_PFX_ON_MISMATCH=true; shift ;;
            --check-expiry) CHECK_EXPIRY=true; shift ;;
            --expiry-days)
                [[ "${2:-}" =~ ^[0-9]+$ ]] || { log_error "--expiry-days requires a non-negative integer"; exit 1; }
                EXPIRY_WARN_DAYS="$2"
                shift 2
                ;;
            --recursive) RECURSIVE=true; shift ;;
            --json) JSON_OUTPUT=true; shift ;;
            -*) log_error "Unknown option: $1"; show_help; exit 1 ;;
            *)
                if [[ -n "$root_dir" ]]; then
                    log_error "Unexpected argument: $1 (only one ROOT_DIRECTORY is accepted)"
                    exit 1
                fi
                root_dir="$1"
                shift
                ;;
        esac
    done

    if [[ -z "$root_dir" ]]; then
        if [[ -d "$DEFAULT_ROOT" ]]; then
            root_dir="$DEFAULT_ROOT"
        else
            root_dir="$(pwd)"
            log_info "No directory given, using current: $root_dir"
        fi
    fi

    [[ -d "$root_dir" ]] || { log_error "Root directory does not exist: $root_dir"; exit 1; }
    root_dir="$(abspath "$root_dir")"

    if [[ -n "$OUTPUT_DIR_OVERRIDE" ]]; then
        [[ -d "$OUTPUT_DIR_OVERRIDE" ]] || { log_error "Output directory does not exist: $OUTPUT_DIR_OVERRIDE"; exit 1; }
        OUTPUT_DIR_OVERRIDE="$(abspath "$OUTPUT_DIR_OVERRIDE")"
    fi

    acquire_lock
    environment_check

    log_info "Starting (root: $root_dir, output: ${OUTPUT_DIR_OVERRIDE:-same}, dry-run: $DRY_RUN, recursive: $RECURSIVE)"

    process_certbot_layout "$root_dir" "$DRY_RUN"
    process_legacy_layout "$root_dir" "$DRY_RUN"

    emit_json

    if [[ "$JSON_OUTPUT" != true ]]; then
        echo
    fi
    if (( TOTAL_PROCESSED == 0 && TOTAL_SKIPPED == 0 && TOTAL_PLANNED == 0 )); then
        if (( TOTAL_ERRORS > 0 )); then
            log_warn "Finished with $TOTAL_ERRORS error(s), $TOTAL_WARNINGS warning(s). Nothing was written"
            exit 1
        fi
        log_warn "No matching certificates found in $root_dir"
        if [[ "$NO_TLD_FILTER" != true ]]; then
            log_warn "TLD filter is active (ALLOWED_TLDS='$ALLOWED_TLDS'); retry with --no-tld-filter to process every domain"
        fi
        exit 2
    fi

    if (( TOTAL_ERRORS > 0 )); then
        log_warn "Finished with $TOTAL_ERRORS error(s), $TOTAL_WARNINGS warning(s). Processed: $TOTAL_PROCESSED, skipped: $TOTAL_SKIPPED"
        exit 1
    fi

    if (( TOTAL_PLANNED > 0 )); then
        log_info "Success (dry-run): $TOTAL_PLANNED would be written, $TOTAL_SKIPPED unchanged"
    else
        log_info "Success: $TOTAL_PROCESSED updated, $TOTAL_SKIPPED unchanged"
    fi
    if [[ "$DRY_RUN" != true && "$JSON_OUTPUT" != true ]]; then
        cat <<EOF

HOW TO USE THE GENERATED FILES
------------------------------
PEM (key + full chain):
  nginx:  ssl_certificate     <domain>.pem;
  apache: SSLCertificateFile  <domain>.pem;

PFX (when --pfx was used):
  Import into Windows Certificate Store / IIS.

Always keep private key material mode 0600.
EOF
    fi
    exit 0
}

main "$@"
