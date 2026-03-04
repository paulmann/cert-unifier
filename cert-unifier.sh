#!/usr/bin/env bash
#
# cert-unifier.sh – Generate unified PEM and optionally PFX files for Let's Encrypt certificates
# =============================================================================
# Author:  Mikhail Deynekin (https://deynekin.com, mid1977@gmail.com)
# Version: 2.9.0
# Date:    2026-03-04
# License: MIT (https://opensource.org/licenses/MIT)
#
# Description:
#   This script scans a directory (default: /var/www/httpd-cert) for Let's Encrypt
#   certificates in two possible layouts and creates a unified PEM file
#   (private key + full certificate chain) suitable for services like
#   Apache, Nginx, Postfix, Dovecot, HAProxy, etc.
#   Optionally (--pfx) also generates a PKCS#12 (.pfx) file for IIS.
#
#   NEW in v2.9.0: When --pfx is enabled, the script auto-discovers the correct
#   key/certificate pair by comparing cryptographic modulus hashes, ensuring
#   PFX generation succeeds even with legacy file layouts.
#
#   Supported layouts:
#     1) Modern Certbot layout (live/<domain>/fullchain.pem + privkey.pem)
#     2) Legacy custom layout (<domain>_leX.crt + <domain>_leX.crtca [ + .key ])
#        Files may be located directly in the root directory OR in subdirectories.
#
#   The script is idempotent and safe to run periodically (e.g., from cron).
#
# Usage:
#   ./cert-unifier.sh [OPTIONS] [ROOT_DIRECTORY]
#
# Options:
#   -h, --help                  Show this help message
#   -V, --version               Print version information
#   -d, --dry-run               Validate inputs without writing any files
#   -v, --verbose               Enable DEBUG-level logging
#   -t, --tlds LIST             Comma/space-separated list of allowed TLDs (default: "ru com")
#   -o, --output-dir            Override output directory (default: same as input directory)
#   --no-tld-filter             Disable TLD filtering (process all domains)
#   --no-key-validation         Disable deep validation of private keys (accept any existing key file)
#   --pfx                       Also generate PKCS#12 (.pfx) files (requires openssl)
#   --skip-pfx-on-mismatch      Skip PFX generation if key/cert mismatch (don't fail)
#
# Environment variables:
#   LOG_LEVEL                   Set verbosity: DEBUG|INFO|WARN|ERROR (default: INFO)
#   ALLOWED_TLDS                Space-separated TLDs (same as -t option)
#   NO_KEY_VALIDATION           If set to "true", disable deep key validation (same as --no-key-validation)
#   PFX_PASSWORD                Password for PFX files (default: empty)
#
# Exit codes:
#   0   Success
#   1   Runtime error (missing dependencies, invalid paths, permission denied)
#   2   No certificates found matching criteria
#   3   Validation failed (dry-run mode)
#
# =============================================================================

set -euo pipefail

# -----------------------------------------------------------------------------
# Constants and global settings
# -----------------------------------------------------------------------------
readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_VERSION="2.9.0"
readonly DEFAULT_ROOT="/var/www/httpd-cert"
readonly MIN_PEM_SIZE=1024                     # minimum sane size for a PEM bundle
readonly PEM_PERMISSIONS="600"                 # private key must be protected
readonly LOCK_FILE="/var/lock/cert-unifier.lock"
readonly LOG_TIMESTAMP_FORMAT="+%Y-%m-%d %H:%M:%S"

# Allowed TLDs (can be overridden by env var or -t option)
ALLOWED_TLDS="${ALLOWED_TLDS:-ru com}"
# Flag to disable TLD filtering entirely
NO_TLD_FILTER=false
# Flag to disable deep validation of private keys (accept any existing key file)
NO_KEY_VALIDATION="${NO_KEY_VALIDATION:-false}"
# Flag to generate PFX files
GENERATE_PFX=false
# Flag to skip PFX generation on key/cert mismatch instead of failing
SKIP_PFX_ON_MISMATCH=false
# Password for PFX files (default empty)
PFX_PASSWORD="${PFX_PASSWORD:-}"

# Logging level (default INFO)
LOG_LEVEL="${LOG_LEVEL:-INFO}"

# Global counters (updated during processing)
TOTAL_PROCESSED=0
TOTAL_ERRORS=0

# -----------------------------------------------------------------------------
# Logging functions (colorized when output is a terminal)
# -----------------------------------------------------------------------------
_log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp
    timestamp="$(date "$LOG_TIMESTAMP_FORMAT")" || timestamp="0000-00-00 00:00:00"
    
    # Всегда выводим в stderr для ERROR и WARN
    if [[ "$level" == "ERROR" || "$level" == "WARN" ]]; then
        if [[ -t 2 ]]; then
            case "$level" in
                ERROR) echo -e "\e[31m[$timestamp] [$level]\e[0m $message" >&2 ;;
                WARN)  echo -e "\e[33m[$timestamp] [$level]\e[0m $message" >&2 ;;
            esac
        else
            echo "[$timestamp] [$level] $message" >&2
        fi
        return 0
    fi
    
    # INFO и DEBUG
    if [[ -t 1 ]]; then
        case "$level" in
            INFO)  echo -e "\e[32m[$timestamp] [$level]\e[0m $message" ;;
            DEBUG) [[ "$LOG_LEVEL" == "DEBUG" ]] && echo -e "\e[36m[$timestamp] [$level]\e[0m $message" ;;
        esac
    else
        # Не терминал — выводим INFO всегда
        [[ "$level" == "INFO" ]] && echo "[$timestamp] [$level] $message"
    fi
    return 0
}

log_info()  { _log "INFO"  "$@"; }
log_warn()  { _log "WARN"  "$@"; }
log_error() { _log "ERROR" "$@"; }
log_debug() { _log "DEBUG" "$@"; }

# -----------------------------------------------------------------------------
# Help and version
# -----------------------------------------------------------------------------
show_help() {
    cat << EOF
${SCRIPT_NAME} version ${SCRIPT_VERSION}

Generate unified PEM files (private key + certificate chain) for Let's Encrypt certificates.
NEW in v2.9.0: Auto-discovery of matching key/cert pairs for PFX generation.

USAGE:
    $SCRIPT_NAME [OPTIONS] [ROOT_DIRECTORY]

OPTIONS:
    -h, --help                  Show this help message and exit
    -V, --version               Print version information and exit
    -d, --dry-run               Validate inputs without writing files
    -v, --verbose               Enable DEBUG-level logging
    -t, --tlds LIST             Comma/space-separated list of allowed TLDs (default: "$ALLOWED_TLDS")
    -o, --output-dir PATH       Override default output directory (default: same as input)
    --no-tld-filter             Disable TLD filtering (process all domains)
    --no-key-validation         Disable deep validation of private keys (accept any existing key file)
    --pfx                       Also generate PKCS#12 (.pfx) files (requires openssl)
    --skip-pfx-on-mismatch      Skip PFX generation if key/cert mismatch (don't fail)

ENVIRONMENT VARIABLES:
    LOG_LEVEL                   Set verbosity: DEBUG|INFO|WARN|ERROR (default: INFO)
    ALLOWED_TLDS                Space-separated TLDs to process (same as -t)
    NO_KEY_VALIDATION           If set to "true", disable deep key validation (same as --no-key-validation)
    PFX_PASSWORD                Password for PFX files (default: empty)

EXAMPLES:
    $SCRIPT_NAME
    $SCRIPT_NAME /opt/certs
    $SCRIPT_NAME --dry-run --verbose /etc/letsencrypt/live
    ALLOWED_TLDS="ru com org" $SCRIPT_NAME /var/www/certs
    $SCRIPT_NAME --no-tld-filter /var/www/certs
    $SCRIPT_NAME --no-key-validation /var/www/certs
    $SCRIPT_NAME --pfx /var/www/certs
    $SCRIPT_NAME --pfx --skip-pfx-on-mismatch /var/www/certs

EXIT CODES:
    0   Success
    1   Runtime error (missing dependencies, invalid paths, permission denied)
    2   No certificates found matching criteria
    3   Validation failed (dry-run mode)

EOF
}

show_version() {
    echo "${SCRIPT_NAME} version ${SCRIPT_VERSION}"
    echo "Copyright (c) 2026 Mikhail Deynekin. MIT License."
}

# -----------------------------------------------------------------------------
# Utility functions
# -----------------------------------------------------------------------------

# Check if a domain ends with any allowed TLD.
# Returns 0 if allowed, 1 otherwise. If NO_TLD_FILTER is true, always returns 0.
is_allowed_tld() {
    local domain="$1"
    
    if [[ "$NO_TLD_FILTER" == "true" ]]; then
        return 0
    fi
    
    local tld
    for tld in $ALLOWED_TLDS; do
        [[ "$domain" == *".$tld" ]] && return 0
    done
    return 1
}

# Normalize a path by removing duplicate slashes and resolving . and .. components.
# This is a pure Bash implementation (no external dependencies).
normalize_path() {
    local path="$1"
    local -a parts
    local part
    
    # Replace multiple slashes with a single slash
    while [[ "$path" =~ //+ ]]; do
        path="${path//\/\//\/}"
    done
    
    # Split into components
    IFS='/' read -ra parts <<< "$path"
    
    # Resolve . and ..
    local -a stack
    for part in "${parts[@]}"; do
        case "$part" in
            ""|.) ;;            # ignore empty and current dir
            ..)  if [[ ${#stack[@]} -gt 0 ]]; then
                     unset 'stack[${#stack[@]}-1]'
                 fi ;;
            *)   stack+=("$part") ;;
        esac
    done
    
    # Rebuild path
    if [[ ${#stack[@]} -eq 0 ]]; then
        echo "/"
    else
        printf "/%s" "${stack[@]}"
        echo
    fi
}

# -----------------------------------------------------------------------------
# Helper: Output file content ensuring it ends with exactly one newline
# Guarantees PEM block separation without corrupting structure
# -----------------------------------------------------------------------------
cat_with_newline() {
    local file="$1"
    [[ ! -f "$file" || ! -s "$file" ]] && return 0
    
    cat "$file"
    
    # Check if file ends with newline; if not, add one
    local last_byte
    last_byte=$(tail -c1 "$file" 2>/dev/null) || return 0
    if [[ -n "$last_byte" && "$last_byte" != $'\n' ]]; then
        printf '\n'
    fi
}

# -----------------------------------------------------------------------------
# Helper: Get OpenSSL major.minor version as comparable number
# -----------------------------------------------------------------------------
get_openssl_version_num() {
    local ver
    ver=$(openssl version 2>/dev/null | grep -oP 'OpenSSL \K[0-9]+\.[0-9]+') || echo "1.1"
    local major minor
    IFS='.' read -r major minor <<< "$ver"
    echo "$((major * 100 + minor))"  # e.g., 1.1 → 101, 3.0 → 300
}

# -----------------------------------------------------------------------------
# Helper: Check if openssl pkcs12 supports -friendlyname flag
# OpenSSL 3.0+ supports it; 1.1.1 may not (runtime check)
# -----------------------------------------------------------------------------
openssl_supports_friendlyname() {
    local ver_num
    ver_num=$(get_openssl_version_num)
    
    if [[ "$ver_num" -ge 300 ]]; then
        return 0
    elif [[ "$ver_num" -ge 101 ]]; then
        # Runtime check for 1.1.x
        openssl pkcs12 -help 2>&1 | grep -q '\-friendlyname'
        return $?
    fi
    return 1
}

# -----------------------------------------------------------------------------
# Helper: Extract modulus hash from a certificate or key file
# Returns hash string on stdout, empty on error
# -----------------------------------------------------------------------------
_get_modulus_hash() {
    local file="$1"
    local type="${2:-auto}"  # 'cert', 'key', or 'auto'
    
    if [[ ! -f "$file" || ! -s "$file" ]]; then
        return 1
    fi
    
    local hash=""
    
    if [[ "$type" == "cert" || "$type" == "auto" ]]; then
        hash=$(openssl x509 -noout -modulus -in "$file" 2>/dev/null | openssl md5 2>/dev/null | awk '{print $NF}')
        [[ -n "$hash" ]] && echo "$hash" && return 0
    fi
    
    if [[ "$type" == "key" || "$type" == "auto" ]]; then
        # Try RSA first, then EC
        hash=$(openssl rsa -noout -modulus -in "$file" 2>/dev/null | openssl md5 2>/dev/null | awk '{print $NF}') || \
        hash=$(openssl ec -noout -pubout -in "$file" 2>/dev/null | openssl md5 2>/dev/null | awk '{print $NF}')
        [[ -n "$hash" ]] && echo "$hash" && return 0
    fi
    
    return 1
}

# -----------------------------------------------------------------------------
# Helper: Verify that private key matches the leaf certificate in chain
# Returns 0 if match, 1 if mismatch or error
# -----------------------------------------------------------------------------
_verify_key_cert_match() {
    local key_file="$1"
    local cert_chain_file="$2"
    
    local cert_modulus key_modulus
    cert_modulus=$(_get_modulus_hash "$cert_chain_file" "cert") || {
        log_debug "⚠ Could not extract certificate modulus for verification"
        return 0  # Don't block on verification failure
    }
    
    key_modulus=$(_get_modulus_hash "$key_file" "key") || {
        log_debug "⚠ Could not extract key modulus for verification (unsupported key type?)"
        return 0
    }
    
    if [[ "$cert_modulus" != "$key_modulus" ]]; then
        log_debug "🔐 Key/cert mismatch detected:"
        log_debug "   Cert modulus: $cert_modulus"
        log_debug "   Key modulus:  $key_modulus"
        return 1
    fi
    
    return 0
}

# -----------------------------------------------------------------------------
# NEW v2.9.0: Auto-discover matching private key for a certificate
# Searches common patterns and returns first matching key path
# Used when --pfx is enabled to ensure correct pair for PFX generation
# Compatible with Bash 4.2 (CentOS 7)
# -----------------------------------------------------------------------------
discover_key_cert_pair() {
    local cert_file="$1"          # Leaf certificate file
    local search_dir="$2"         # Directory to search for keys
    local preferred_key="${3:-}"  # Initially preferred key (may be wrong)
    
    # If PFX generation is not requested, just return the preferred key
    if [[ "$GENERATE_PFX" != "true" ]]; then
        echo "${preferred_key:-}"
        return 0
    fi
    
    # 🔧 Все логи — в stderr, только результат — в stdout
    echo "🔍 discover_key_cert_pair: cert=$cert_file, dir=$search_dir, preferred=${preferred_key:-none}" >&2
    
    # Extract expected modulus from certificate
    local expected_modulus
    expected_modulus=$(_get_modulus_hash "$cert_file" "cert") || {
        echo "⚠ Could not extract modulus from certificate: $cert_file" >&2
        echo "${preferred_key:-}"
        return 0
    }
    echo "   Expected modulus: $expected_modulus" >&2
    
    # If preferred key exists and matches, use it immediately
    if [[ -n "$preferred_key" && -f "$preferred_key" ]]; then
        local pref_modulus
        pref_modulus=$(_get_modulus_hash "$preferred_key" "key") || true
        if [[ -n "$pref_modulus" && "$pref_modulus" == "$expected_modulus" ]]; then
            echo "   ✓ Preferred key matches: $preferred_key" >&2
            echo "🔑 Auto-discovered matching key for PFX: $preferred_key" >&2
            echo "$preferred_key"
            return 0
        else
            echo "   ✗ Preferred key does NOT match: $preferred_key (modulus: ${pref_modulus:-unknown})" >&2
        fi
    fi
    
    # Build list of candidate key files to search
    local -a candidates=()
    local cert_basename
    cert_basename=$(basename "$cert_file")
    
    # Extract domain name from cert filename (handle _leX suffix)
    local domain
    if [[ "$cert_basename" =~ ^(.+)_le[0-9]+\.crt$ ]]; then
        domain="${BASH_REMATCH[1]}"
        
        # Add _leX.key variants found in directory
        local f
        for f in "$search_dir/${domain}_le"*.key; do
            [[ -f "$f" ]] && candidates+=("$f")
        done
        
        # Check Certbot live directory
        if [[ -d "$search_dir/live/${domain}" ]]; then
            [[ -f "$search_dir/live/${domain}/privkey.pem" ]] && candidates+=("$search_dir/live/${domain}/privkey.pem")
        fi
    fi
    
    # Add standard patterns
    [[ -f "$search_dir/${domain}.key" ]] && candidates+=("$search_dir/${domain}.key")
    [[ -f "$search_dir/privkey.pem" ]] && candidates+=("$search_dir/privkey.pem")
    
    if [[ -d "$search_dir/live" ]]; then
        for f in "$search_dir"/live/*/privkey.pem; do
            [[ -f "$f" ]] && candidates+=("$f")
        done
    fi
    
    for f in "$search_dir"/*.key; do
        [[ -f "$f" ]] && candidates+=("$f")
    done
    
    # Remove duplicates (Bash 4.2 compatible)
    local -a unique_candidates=()
    local c existing already_added
    for c in "${candidates[@]}"; do
        [[ -z "$c" ]] && continue
        already_added=false
        for existing in "${unique_candidates[@]}"; do
            [[ "$existing" == "$c" ]] && already_added=true && break
        done
        [[ "$already_added" == "false" ]] && unique_candidates+=("$c")
    done
    
    echo "   Searching ${#unique_candidates[@]} candidate key files..." >&2
    
    # Test each candidate
    for c in "${unique_candidates[@]}"; do
        [[ -f "$c" ]] || continue
        
        local cand_modulus
        cand_modulus=$(_get_modulus_hash "$c" "key") || continue
        
        if [[ "$cand_modulus" == "$expected_modulus" ]]; then
            echo "🔑 Auto-discovered matching key for PFX: $c" >&2
            echo "   Modulus hash: $cand_modulus" >&2
            echo "$c"
            return 0
        fi
        echo "   ✗ $c (modulus: $cand_modulus)" >&2
    done
    
    # No matching key found
    echo "⚠ No matching private key found for certificate: $cert_file" >&2
    echo "   Expected modulus: $expected_modulus" >&2
    
    # Return preferred key anyway (PFX will fail, but PEM can proceed)
    echo "${preferred_key:-}"
    return 0
}

# -----------------------------------------------------------------------------
# Professional PEM validation (two‑level with detailed diagnostics)
# For private keys, validation can be completely disabled via --no-key-validation.
# -----------------------------------------------------------------------------
validate_pem_file() {
    local file="$1"
    local expected_type="${2:-any}"   # 'cert', 'key', or 'any'

    # Check file existence and readability
    if [[ ! -e "$file" ]]; then
        log_debug "File does not exist: $file"
        return 1
    fi
    if [[ ! -r "$file" ]]; then
        log_debug "File not readable: $file"
        return 1
    fi
    if [[ ! -s "$file" ]]; then
        log_debug "File is empty: $file"
        return 1
    fi

    # For keys, if NO_KEY_VALIDATION is true, accept the file immediately
    if [[ "$expected_type" == "key" && "$NO_KEY_VALIDATION" == "true" ]]; then
        log_debug "Key validation disabled, accepting $file"
        return 0
    fi

    # Level 1: must contain a PEM header (first line should start with "-----BEGIN")
    local first_line
    IFS= read -r first_line < "$file" 2>/dev/null
    if [[ "$first_line" != "-----BEGIN"* ]]; then
        log_debug "File $file does not contain a PEM header (first line: ${first_line:0:30}...)"
        return 1
    fi

    # If openssl is missing, we stop here and trust the header
    if ! command -v openssl >/dev/null 2>&1; then
        log_debug "openssl not available, relying on PEM header for $file"
        return 0
    fi

    # Level 2: deep validation with openssl
    local openssl_valid=false

    # Try all relevant openssl commands depending on expected_type
    if [[ "$expected_type" == "cert" || "$expected_type" == "any" ]]; then
        if openssl x509 -in "$file" -noout -text >/dev/null 2>&1; then
            openssl_valid=true
        fi
    fi

    if [[ "$expected_type" == "key" || "$expected_type" == "any" ]]; then
        # Try multiple key formats: RSA, EC, DSA, and generic PKCS#8
        if openssl rsa -in "$file" -noout -text >/dev/null 2>&1 || \
           openssl ec -in "$file" -noout -text >/dev/null 2>&1 || \
           openssl dsa -in "$file" -noout -text >/dev/null 2>&1 || \
           openssl pkey -in "$file" -noout -text >/dev/null 2>&1; then
            openssl_valid=true
        fi
    fi

    if [[ "$openssl_valid" == true ]]; then
        return 0
    fi

    # Fallback: openssl could not validate, but header exists → accept with warning
    log_warn "openssl validation failed for $file, but PEM header present – accepting (may be risky)"
    return 0
}

# -----------------------------------------------------------------------------
# Generate PKCS#12 (.pfx) from private key and certificate chain
# Compatible with OpenSSL 1.1.1 (CentOS 7) and 3.x
# -----------------------------------------------------------------------------
generate_pfx() {
    local key_file="$1"
    local cert_chain_file="$2"
    local pfx_file="$3"
    local dry_run="${4:-false}"
    
    if [[ "$dry_run" == "true" ]]; then
        log_info "[DRY-RUN] Would generate PFX: $pfx_file"
        return 0
    fi
    
    if ! command -v openssl >/dev/null 2>&1; then
        log_error "openssl not found – cannot generate PFX for $pfx_file"
        ((TOTAL_ERRORS++)) || true
        return 1
    fi
    
    log_debug "Generating PFX: $pfx_file from key=$key_file, chain=$cert_chain_file"
    
    # 🔍 PRE-CHECK: Verify key/cert cryptographic match
    if ! _verify_key_cert_match "$key_file" "$cert_chain_file"; then
        if [[ "$SKIP_PFX_ON_MISMATCH" == "true" ]]; then
            log_warn "⚠ Skipping PFX generation for $pfx_file (key/cert mismatch, --skip-pfx-on-mismatch active)"
            return 0  # Don't count as error
        fi
        log_error "🔐 ABORT: Private key does NOT match certificate – PFX generation impossible"
        log_error "   Key file:  $key_file"
        log_error "   Cert file: $cert_chain_file"
        ((TOTAL_ERRORS++)) || true
        return 1
    fi
    
    # Build OpenSSL arguments using array (safe parameter handling)
    local -a openssl_args=(
        pkcs12 -export
        -out "$pfx_file"
        -inkey "$key_file"
        -in "$cert_chain_file"
    )
    
    # Handle password (empty password is valid for PFX)
    if [[ -n "$PFX_PASSWORD" ]]; then
        openssl_args+=(-passout "pass:$PFX_PASSWORD")
    else
        openssl_args+=(-passout pass:)  # Explicit empty password
    fi
    
    # Add certificate name for Windows/IIS compatibility (version-aware flag)
    local cert_name
    cert_name=$(basename "${pfx_file%.pfx}" 2>/dev/null | cut -d. -f1) || cert_name="certificate"
    
    if openssl_supports_friendlyname; then
        openssl_args+=(-friendlyname "$cert_name")
        log_debug "Using -friendlyname flag (OpenSSL supports it)"
    else
        openssl_args+=(-name "$cert_name")
        log_debug "Using -name flag (OpenSSL 1.1.1 compatibility)"
    fi
    
    # Execute with comprehensive error capture
    local err_output
    if ! err_output=$(openssl "${openssl_args[@]}" 2>&1); then
        local status=$?
        log_error "Failed to generate PFX for $pfx_file (openssl exit code $status)"
        log_error "openssl stderr: $err_output"
        ((TOTAL_ERRORS++)) || true
        return 1
    fi
    
    # Apply secure permissions immediately after successful creation
    chmod 600 "$pfx_file" 2>/dev/null || log_warn "Could not set 600 permissions on $pfx_file"
    log_info "✓ Generated PFX: $pfx_file"
    return 0
}

# -----------------------------------------------------------------------------
# Atomic PEM file writer with permission enforcement and PFX integration
# Uses cat_with_newline() for reliable PEM structure assembly
# -----------------------------------------------------------------------------
atomic_write_pem() {
    local src_key="${1:-}"
    local src_chain="$2"
    local dest_pem="$3"
    local dry_run="${4:-false}"
    
    local tmp_file="${dest_pem}.new.$$"
    
    log_debug "Assembling PEM: key=[${src_key:-none}], chain=$src_chain → $dest_pem"
    
    # Assemble PEM with guaranteed proper newline separation using helper
    {
        if [[ -n "$src_key" && -f "$src_key" ]]; then
            cat_with_newline "$src_key"
        fi
        if [[ ! -f "$src_chain" ]]; then
            echo "ERROR: chain file missing: $src_chain" >&2
            return 1
        fi
        cat_with_newline "$src_chain"
    } > "$tmp_file" 2>/dev/null || {
        log_error "Failed to assemble PEM content for $dest_pem"
        rm -f "$tmp_file"
        return 1
    }
    
    # Sanity check: minimum size for valid PEM bundle
    local file_size
    file_size=$(wc -c < "$tmp_file" | tr -d ' ')
    if (( file_size < MIN_PEM_SIZE )); then
        log_warn "Generated PEM too small (${file_size} bytes < ${MIN_PEM_SIZE}); skipping write"
        rm -f "$tmp_file"
        return 1
    fi
    
    # Validate assembled bundle before writing
    if ! validate_pem_file "$tmp_file" "any"; then
        log_error "Generated PEM failed validation; discarding"
        rm -f "$tmp_file"
        return 1
    fi
    
    # Dry-run mode: report and cleanup
    if [[ "$dry_run" == "true" ]]; then
        log_info "[DRY-RUN] Would write $dest_pem (${file_size} bytes)"
        rm -f "$tmp_file"
        if [[ "$GENERATE_PFX" == "true" && -n "$src_key" ]]; then
            local pfx_file="${dest_pem%.pem}.pfx"
            generate_pfx "$src_key" "$src_chain" "$pfx_file" "$dry_run"
        fi
        return 0
    fi
    
    # Set secure permissions BEFORE atomic move (defense in depth)
    if ! chmod "$PEM_PERMISSIONS" "$tmp_file" 2>/dev/null; then
        log_error "Failed to set permissions $PEM_PERMISSIONS on $tmp_file"
        rm -f "$tmp_file"
        return 1
    fi
    
    # Atomic replacement via rename (POSIX-safe)
    if mv -f "$tmp_file" "$dest_pem"; then
        log_info "✓ Updated $dest_pem (${file_size} bytes, mode: $PEM_PERMISSIONS)"
        
        # Generate PFX immediately after successful PEM write (uses original chain file)
        if [[ "$GENERATE_PFX" == "true" && -n "$src_key" ]]; then
            local pfx_file="${dest_pem%.pem}.pfx"
            generate_pfx "$src_key" "$src_chain" "$pfx_file" "$dry_run"
        fi
        return 0
    else
        log_error "Failed to atomically replace $dest_pem"
        rm -f "$tmp_file"
        return 1
    fi
}

# -----------------------------------------------------------------------------
# Concurrency lock (using flock)
# -----------------------------------------------------------------------------
acquire_lock() {
    if command -v flock >/dev/null 2>&1; then
        exec 200>"$LOCK_FILE" || {
            log_warn "Could not create lock file: $LOCK_FILE"
            return 0
        }
        if ! flock -n 200 2>/dev/null; then
            log_error "Another instance is already running (lock: $LOCK_FILE)"
            exit 1
        fi
        log_debug "Lock acquired: $LOCK_FILE"
    else
        log_warn "flock not available; proceeding without concurrency protection"
    fi
    return 0
}

# -----------------------------------------------------------------------------
# Processing functions for the two certificate layouts
# -----------------------------------------------------------------------------

# Process modern Certbot layout: <domain>/fullchain.pem + privkey.pem
process_certbot_layout() {
    local root_dir="$1"
    local dry_run="${2:-false}"
    local errors=0
    local processed=0
    
    log_debug "Scanning Certbot layout: $root_dir/*/fullchain.pem"
    
    for domain_dir in "$root_dir"/*/; do
        [[ -d "$domain_dir" ]] || continue
        
        # Normalize directory path (remove trailing slash for later concatenation)
        domain_dir="$(normalize_path "$domain_dir")"
        
        local fullchain="${domain_dir}/fullchain.pem"
        local privkey="${domain_dir}/privkey.pem"
        
        # Only process directories that contain both required files
        if [[ ! -f "$fullchain" || ! -f "$privkey" ]]; then
            continue
        fi
        
        local domain
        domain="$(basename "$domain_dir")"
        
        if ! is_allowed_tld "$domain"; then
            log_debug "Skipping $domain (TLD not in allowed list)"
            continue
        fi
        
        if ! validate_pem_file "$privkey" "key"; then
            log_warn "Invalid private key: $privkey; skipping $domain"
            ((errors++)) || true
            ((TOTAL_ERRORS++)) || true
            continue
        fi
        if ! validate_pem_file "$fullchain" "cert"; then
            log_warn "Invalid certificate chain: $fullchain; skipping $domain"
            ((errors++)) || true
            ((TOTAL_ERRORS++)) || true
            continue
        fi
        
        local output_pem="${domain_dir}/${domain}.pem"
        if atomic_write_pem "$privkey" "$fullchain" "$output_pem" "$dry_run"; then
            ((processed++)) || true
            ((TOTAL_PROCESSED++)) || true
        else
            ((errors++)) || true
            ((TOTAL_ERRORS++)) || true
        fi
    done
    
    log_debug "Certbot layout: processed $processed, errors $errors"
    return $errors
}

# Process legacy layout: <domain>_leX.crt + <domain>_leX.crtca + optional .key
# This function scans both the root directory itself and all immediate subdirectories.
# NEW v2.9.0: Uses discover_key_cert_pair() when --pfx is enabled to find matching key
# -----------------------------------------------------------------------------
process_legacy_layout() {
    local root_dir="$1"
    local dry_run="${2:-false}"
    local errors=0
    local processed=0
    
    log_debug "Scanning legacy layout (root directory and subdirectories): $root_dir"
    
    # Build list of directories to scan: root_dir itself and all first-level subdirs
    local -a scan_dirs=("$root_dir")
    
    # Add subdirectories (if any)
    for subdir in "$root_dir"/*/; do
        if [[ -d "$subdir" ]]; then
            scan_dirs+=("$(normalize_path "$subdir")")
        fi
    done
    
    for dir in "${scan_dirs[@]}"; do
        log_debug "Scanning directory: $dir"
        
        shopt -s nullglob
        for crt_file in "$dir"/*_le[0-9].crt; do
            [[ -f "$crt_file" ]] || continue
            
            local crt_basename
            crt_basename="$(basename "$crt_file")"
            
            # Extract domain and LE suffix using regex (safe against '_le' inside domain)
            if [[ ! "$crt_basename" =~ ^(.+)_le([0-9]+)\.crt$ ]]; then
                log_warn "Unexpected filename format: $crt_basename; skipping"
                ((errors++)) || true
                ((TOTAL_ERRORS++)) || true
                continue
            fi
            
            local domain="${BASH_REMATCH[1]}"
            local le_suffix="${BASH_REMATCH[2]}"
            
            if ! is_allowed_tld "$domain"; then
                log_debug "Skipping $domain (TLD not allowed)"
                continue
            fi
            
            local chain_file="${dir}/${domain}_le${le_suffix}.crtca"
            if [[ ! -f "$chain_file" ]]; then
                log_warn "Missing chain file for $domain: $chain_file; skipping"
                ((errors++)) || true
                ((TOTAL_ERRORS++)) || true
                continue
            fi
            
            # Look for private key with priority: _leX.key first, then domain.key
            # This order matches typical Let's Encrypt rotation patterns
            local preferred_key=""
            for candidate in "${dir}/${domain}_le${le_suffix}.key" "${dir}/${domain}.key"; do
                if [[ -f "$candidate" ]]; then
                    preferred_key="$candidate"
                    break
                fi
            done
            
            # 🔑 NEW v2.9.0: When --pfx is enabled, auto-discover the correct matching key
		local key_file="$preferred_key"
		if [[ "$GENERATE_PFX" == "true" && -n "$preferred_key" ]]; then
		    key_file=$(discover_key_cert_pair "$crt_file" "$dir" "$preferred_key")
		    [[ -z "$key_file" && -n "$preferred_key" ]] && key_file="$preferred_key"
		fi
            
            # Validate all components
            if [[ -n "$key_file" ]] && ! validate_pem_file "$key_file" "key"; then
                log_warn "Invalid private key: $key_file; skipping $domain"
                ((errors++)) || true
                ((TOTAL_ERRORS++)) || true
                continue
            fi
            if ! validate_pem_file "$crt_file" "cert"; then
                log_warn "Invalid certificate: $crt_file; skipping $domain"
                ((errors++)) || true
                ((TOTAL_ERRORS++)) || true
                continue
            fi
            if ! validate_pem_file "$chain_file" "cert"; then
                log_warn "Invalid chain: $chain_file; skipping $domain"
                ((errors++)) || true
                ((TOTAL_ERRORS++)) || true
                continue
            fi
            
            # Create temporary chain file with leaf + intermediates (proper newline handling)
            local tmp_chain
            tmp_chain="$(mktemp "${dir}/.chain_tmp.XXXXXX")" || {
                log_error "Failed to create temporary chain file for $domain"
                ((errors++)) || true
                ((TOTAL_ERRORS++)) || true
                continue
            }
            
            # Use helper to ensure clean PEM concatenation
            {
                cat_with_newline "$crt_file"    # Leaf certificate FIRST (critical for PFX)
                cat_with_newline "$chain_file"  # Intermediate CAs
            } > "$tmp_chain"
            
            local output_pem="${dir}/${domain}.pem"
            if atomic_write_pem "$key_file" "$tmp_chain" "$output_pem" "$dry_run"; then
                ((processed++)) || true
                ((TOTAL_PROCESSED++)) || true
            else
                ((errors++)) || true
                ((TOTAL_ERRORS++)) || true
            fi
            
            rm -f "$tmp_chain"
        done
        shopt -u nullglob
    done
    
    log_debug "Legacy layout: processed $processed, errors $errors"
    return $errors
}

# -----------------------------------------------------------------------------
# Optional: check certificate expiry (post‑processing)
# -----------------------------------------------------------------------------
check_certificate_expiry() {
    local pem_file="$1"
    local warning_days="${2:-30}"
    
    if ! command -v openssl >/dev/null 2>&1; then
        return 0
    fi
    
    # Extract end date
    local expiry_date
    expiry_date=$(openssl x509 -in "$pem_file" -noout -enddate 2>/dev/null | cut -d= -f2) || return 0
    
    # Convert to epoch
    local expiry_epoch
    expiry_epoch=$(date -d "$expiry_date" +%s 2>/dev/null) || return 0
    
    local now_epoch
    now_epoch=$(date +%s)
    
    local days_left=$(( (expiry_epoch - now_epoch) / 86400 ))
    
    if (( days_left < 0 )); then
        log_warn "✗ EXPIRED: $pem_file (expired on $expiry_date)"
        return 1
    elif (( days_left < warning_days )); then
        log_warn "⚠ Expiring soon: $pem_file (${days_left} days left, expires $expiry_date)"
        return 1
    else
        log_debug "✓ Valid: $pem_file (expires in ${days_left} days)"
        return 0
    fi
}

# -----------------------------------------------------------------------------
# Environment check and startup banner
# -----------------------------------------------------------------------------
environment_check() {
    log_info "=== Environment Check ==="
    log_info "Script version: $SCRIPT_VERSION"
    log_info "Bash version: $BASH_VERSION"
    
    # Check openssl
    if command -v openssl >/dev/null 2>&1; then
        local openssl_version
        openssl_version=$(openssl version 2>/dev/null | head -n1)
        log_info "OpenSSL: $openssl_version"
    else
        log_warn "OpenSSL not found – validation limited to PEM header checks"
        if [[ "$GENERATE_PFX" == "true" ]]; then
            log_error "PFX generation requested but openssl is missing"
            exit 1
        fi
    fi
    
    # Check flock
    if command -v flock >/dev/null 2>&1; then
        log_debug "flock available – concurrency lock will be used"
    else
        log_warn "flock not available – running without concurrency protection"
    fi
    
    # Summarize effective settings
    log_info "Settings:"
    log_info "  TLD filter: $([ "$NO_TLD_FILTER" == true ] && echo "disabled" || echo "enabled (allowed: $ALLOWED_TLDS)")"
    log_info "  Key validation: $([ "$NO_KEY_VALIDATION" == true ] && echo "disabled" || echo "enabled")"
    log_info "  Generate PFX: $([ "$GENERATE_PFX" == true ] && echo "yes (password: ${PFX_PASSWORD:+set}/empty)" || echo "no")"
    log_info "  Skip PFX on mismatch: $([ "$SKIP_PFX_ON_MISMATCH" == true ] && echo "yes" || echo "no")"
    log_info "  Auto key discovery: $([ "$GENERATE_PFX" == true ] && echo "enabled (v2.9.0)" || echo "n/a")"
    log_info "  Dry run: $([ "${dry_run:-false}" == true ] && echo "yes" || echo "no")"
    log_info "  Verbose: $([ "$LOG_LEVEL" == "DEBUG" ] && echo "yes" || echo "no")"
    log_info "=========================="
}

# -----------------------------------------------------------------------------
# Display usage examples for generated PEM files
# -----------------------------------------------------------------------------
show_usage_info() {
    cat << EOF

═══════════════════════════════════════════════════════════════════════════════
 HOW TO USE THE GENERATED FILES
═══════════════════════════════════════════════════════════════════════════════

The generated .pem files contain the private key followed by the full certificate
chain (leaf + intermediates). They can be used directly in various web servers.

─── NGINX ────────────────────────────────────────────────────────────────────
In your server block, specify:
    ssl_certificate     /path/to/your/domain.pem;
    ssl_certificate_key /path/to/your/domain.pem;   # same file (contains key)

Example:
    server {
        listen 443 ssl;
        server_name example.com;
        ssl_certificate     /var/www/httpd-cert/example.com/example.com.pem;
        ssl_certificate_key /var/www/httpd-cert/example.com/example.com.pem;
    }

─── Apache ───────────────────────────────────────────────────────────────────
In your virtual host configuration:
    SSLCertificateFile      /path/to/your/domain.pem   # contains key + chain

Example:
    <VirtualHost *:443>
        ServerName example.com
        SSLEngine on
        SSLCertificateFile      /var/www/httpd-cert/example.com/example.com.pem
        # No separate key or chain files needed
    </VirtualHost>

─── IIS (Windows) ────────────────────────────────────────────────────────────
If you generated PFX files (using --pfx option), import the .pfx file into IIS
via the "Server Certificates" section. Use the password you provided (empty if none).

─── Other services (Postfix, Dovecot, HAProxy) ───────────────────────────────
Most services that support PEM format can use the same file for both key and
certificate chain. Refer to your service documentation for exact directives.

═══════════════════════════════════════════════════════════════════════════════
EOF
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------
main() {
    local dry_run=false
    local verbose=false
    local output_dir_override=""
    
    # If no arguments are given, show help (but still allow default operation if root dir exists)
    if [[ $# -eq 0 ]]; then
        # If DEFAULT_ROOT exists, proceed silently; otherwise show help
        if [[ ! -d "$DEFAULT_ROOT" ]]; then
            show_help
            exit 0
        fi
    fi
    
    # Parse command line options
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)                  show_help; exit 0 ;;
            -V|--version)               show_version; exit 0 ;;
            -d|--dry-run)               dry_run=true; shift ;;
            -v|--verbose)               verbose=true; LOG_LEVEL="DEBUG"; shift ;;
            -t|--tlds)                  ALLOWED_TLDS="${2//,/ }"; shift 2 ;;
            -o|--output-dir)            output_dir_override="$2"; shift 2 ;;
            --no-tld-filter)            NO_TLD_FILTER=true; shift ;;
            --no-key-validation)        NO_KEY_VALIDATION=true; shift ;;
            --pfx)                      GENERATE_PFX=true; shift ;;
            --skip-pfx-on-mismatch)     SKIP_PFX_ON_MISMATCH=true; shift ;;
            -*)                         log_error "Unknown option: $1"; show_help; exit 1 ;;
            *)                          break ;;   # first non‑option argument is root_dir
        esac
    done
    
    # Determine root directory
    local root_dir="${1:-}"
    if [[ -z "$root_dir" ]]; then
        if [[ -d "$DEFAULT_ROOT" ]]; then
            root_dir="$DEFAULT_ROOT"
        else
            root_dir="$(pwd)"
            log_info "No directory specified; using current: $root_dir"
        fi
    fi
    
    # Validate root directory
    if [[ ! -d "$root_dir" ]]; then
        log_error "Root directory does not exist: $root_dir"
        exit 1
    fi
    
    # Convert to absolute path
    root_dir="$(cd "$root_dir" && pwd -P)"
    
    # Determine output directory
    local output_root="$root_dir"
    if [[ -n "$output_dir_override" ]]; then
        output_root="$output_dir_override"
        if [[ ! -d "$output_root" ]]; then
            log_error "Output directory does not exist: $output_root"
            exit 1
        fi
        output_root="$(cd "$output_root" && pwd -P)"
    fi
    
    # Acquire lock to prevent concurrent runs
    acquire_lock
    
    # Show startup banner and environment check
    environment_check
    
    log_info "Starting PEM generation (root: $root_dir, output: $output_root)"
    
    # Process Certbot layout
    process_certbot_layout "$root_dir" "$dry_run"
    
    # Process legacy layout
    process_legacy_layout "$root_dir" "$dry_run"
    
    # Summary
    echo ""
    if (( TOTAL_PROCESSED == 0 )); then
        log_warn "No matching certificates found in $root_dir"
        exit 2
    elif (( TOTAL_ERRORS > 0 )); then
        log_warn "Completed with $TOTAL_ERRORS warning(s)/error(s). Processed: $TOTAL_PROCESSED"
        exit 1
    else
        log_info "✓ Success: $TOTAL_PROCESSED PEM file(s) processed"
        # Show usage information only in normal (non-dry-run) mode
        if [[ "$dry_run" != "true" ]]; then
            show_usage_info
        fi
        exit 0
    fi
}

# Trap signals for clean exit
trap 'log_warn "Interrupted"; exit 130' INT TERM

# Run main with all arguments
main "$@"
