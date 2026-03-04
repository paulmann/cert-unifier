# Cert Unifier Security Module

[![Version](https://img.shields.io/badge/version-2.9.0-blue.svg)](https://github.com/paulmann/cert-unifier)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-Linux%20%7C%20macOS-blue.svg)](https://www.linux.org/)
[![Bash](https://img.shields.io/badge/bash-4.0%2B-red.svg)](https://www.gnu.org/software/bash/)
[![OpenSSL](https://img.shields.io/badge/openssl-1.1.1%2B-orange.svg)](https://www.openssl.org/)

- [1. Overview](#1-overview)
- [2. Key Features](#2-key-features)
- [3. System Requirements](#3-system-requirements)
- [4. Quick Start Guide](#4-quick-start-guide)
- [5. Installation & Setup](#5-installation--setup)
- [6. Architecture & Components](#6-architecture--components)
- [7. Usage Examples](#7-usage-examples)
- [8. Parameters Reference](#8-parameters-reference)
- [9. Technical Considerations](#9-technical-considerations)
- [10. License & Acknowledgments](#10-license--acknowledgments)

***

## 1. Overview

**Cert Unifier** (v2.9.0) is a high-performance Bash module designed to automate the assembly, validation, and unification of SSL/TLS certificates and private keys into standardized PEM and PFX bundles. Engineered for DevOps workflows and automated web server deployments (Nginx, Apache, HAProxy), it ensures cryptographic consistency and atomic file operations across diverse certificate structures.

### Primary Purpose
The module streamlines certificate lifecycle management by:
- Merging leaf certificates and intermediate chains with matching private keys
- Validating RSA/EC modulus matches to prevent deployment of mismatched assets
- Automating PKCS#12 (PFX) generation for Windows/IIS environments
- Enforcing secure file permissions (0600) on sensitive cryptographic material
- Supporting both modern Certbot layouts and legacy directory structures

***

## 2. Key Features

### 2.1 Unified PEM Assembly
- **Atomic Writes**: Utilizes temporary buffers to ensure file integrity during assembly
- **Newline Normalization**: Guaranteed proper separation between key and chain components
- **Auto-Discovery**: Intelligent scanning of legacy and modern Certbot layouts

### 2.2 Advanced Cryptographic Validation
- **Modulus Verification**: Deep validation of private keys against certificates before unification
- **Key Integrity**: Multi-engine support (RSA/EC) for modulus extraction and comparison
- **PFX Matching**: v2.9.0 introduces auto-discovery of matching key/cert pairs for PKCS#12 creation

### 2.3 Comprehensive Layout Support
- **Certbot Native**: Native processing of `/etc/letsencrypt/live` structures
- **Legacy Support**: Support for `leX.crt` and `leX.key` naming conventions
- **TLD Filtering**: Customizable domain processing based on Top-Level Domains (default: .ru, .com)

### 2.4 Enterprise Deployment Features
- **Dry-Run Mode**: Full validation of inputs and output paths without filesystem modification
- **Secure Permissions**: Automated application of 0600 permissions to private keys and PFX files
- **Logging Architecture**: Multi-level logging (DEBUG, INFO, WARN, ERROR) with timestamps

***

## 3. System Requirements

### 3.1 Minimum Requirements
- **OS**: Linux (any modern distribution), macOS, or WSL
- **Shell**: Bash 4.0 or later
- **Utilities**: `openssl`, `grep`, `awk`, `date`
- **Permissions**: Read access to source certificates; write access to output directories

### 3.2 Recommended Configuration
- **OpenSSL**: 1.1.1+ (supports modern ECC and friendly name attributes)
- **Filesystem**: Standard Linux/Unix permissions model supported
- **Dependencies**: Full `openssl` toolkit for PFX generation and deep key validation

***

## 4. Quick Start Guide

### 4.1 Deployment in 3 Steps

**Step 1: Download the Script**
```bash
wget https://raw.githubusercontent.com/paulmann/cert-unifier/main/cert-unifier.sh
chmod +x cert-unifier.sh
```

**Step 2: Basic Unification**
```bash
./cert-unifier.sh /var/www/httpd-cert
```

**Step 3: Advanced PFX Generation**
```bash
./cert-unifier.sh --pfx --pfx-password "your_password" /etc/letsencrypt/live
```

***

## 5. Installation & Setup

### 5.1 Manual Installation
1. Move the script to a system PATH directory (e.g., `/usr/local/bin`)
2. Ensure dependencies are satisfied: `apt install openssl grep awk`
3. Configure environment variables if needed:
   - `ALLOWEDTLDS="ru com org"`
   - `LOGLEVEL="INFO"`

### 5.2 Automated CI/CD Setup
In corporate environments, integrate via GitLab CI or GitHub Actions:
```yaml
- name: Unify Certificates
  run: |
    export ALLOWEDTLDS="com net"
    ./cert-unifier.sh --no-key-validation --output-dir ./dist /certs/source
```

***

## 6. Architecture & Components

### 6.1 Logic Flow
1. **Environment Check**: Validates OpenSSL version and dependencies
2. **Directory Scanning**: Iterates through target root, identifying layouts
3. **Validation**: Extracts moduli; compares key-cert pairs
4. **Assembly**: Concat(key, chain) -> atomic write to .pem
5. **PFX Generation** (Optional): Converts PEM bundle to PKCS#12

***

## 7. Usage Examples

```bash
# Dry run with verbose debugging
./cert-unifier.sh --dry-run --verbose /etc/letsencrypt/live

# Process all domains (no TLD filtering)
./cert-unifier.sh --no-tld-filter /var/www/certs

# Generate PFX files and skip mismatches
./cert-unifier.sh --pfx --skip-pfx-on-mismatch /opt/certs

# Override output directory
./cert-unifier.sh -o /tmp/unified_certs /var/www/certs
```

***

## 8. Parameters Reference

| Option | Description | Default |
| :--- | :--- | :--- |
| `-d, --dry-run` | Validate without writing files | `false` |
| `-v, --verbose` | Enable DEBUG level logging | `false` |
| `-t, --tlds` | List of allowed TLDs | `ru com` |
| `-o, --output-dir` | Override output path | Input dir |
| `--no-tld-filter` | Process all domains | `false` |
| `--pfx` | Generate PKCS12 files | `false` |
| `--pfx-password`| Set PFX password | Empty |

***

## 9. Technical Considerations

### 9.1 OpenSSL Integration
The script detects OpenSSL version capabilities at runtime. PFX `friendlyname` support is automatically enabled for OpenSSL 1.1.x and 3.x, ensuring better UI integration in Windows Certificate Manager.

### 9.2 Atomic Write Mechanism
To prevent race conditions where a web server might read a partially written certificate, **Cert Unifier** writes to `*.pem.new` and performs an atomic move/rename upon successful validation.

***

## 10. License & Acknowledgments

### 10.1 License
Distributed under the **MIT License**. See `LICENSE` for details.

### 10.2 Copyright
Copyright (c) 2026 **Mikhail Deynekin**.
- **Email**: [mid1977@gmail.com](mailto:mid1977@gmail.com)
- **GitHub**: [paulmann](https://github.com/paulmann)
- **Web**: [deynekin.com](https://deynekin.com/)

---
**v2.9.0** • **Enterprise Cryptography Unification** • **Active**
© 2026 Paulmann. Unified PKI Management.
