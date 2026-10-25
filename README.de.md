# Cert Unifier Sicherheitsmodul

[![Version](https://img.shields.io/badge/version-2.9.0-blue.svg)](https://github.com/paulmann/cert-unifier)
[![Plattform](https://img.shields.io/badge/platform-Linux%20%7C%20macOS-blue.svg)](https://www.linux.org/)
[![Bash](https://img.shields.io/badge/bash-4.0%2B-red.svg)](https://www.gnu.org/software/bash/)
[![OpenSSL](https://img.shields.io/badge/openssl-1.1.1%2B-orange.svg)](https://www.openssl.org/)

<!-- md-i18n:switcher -->
**In anderen Sprachen:** [English](README.md) · Deutsch · [中文](README.zh.md) · [हिन्दी](README.hi.md) · [Español](README.es.md) · [Русский](README.ru.md)

- [1. Überblick](#1-überblick)
- [2. Kernfunktionen](#2-kernfunktionen)
- [3. Systemanforderungen](#3-systemanforderungen)
- [4. Schnellstartanleitung](#4-schnellstartanleitung)
- [5. Installation und Einrichtung](#5-installation-und-einrichtung)
- [6. Architektur und Komponenten](#6-architektur-und-komponenten)
- [7. Anwendungsbeispiele](#7-anwendungsbeispiele)
- [8. Parameterreferenz](#8-parameterreferenz)
- [9. Technische Hinweise](#9-technische-hinweise)
- [10. Lizenz und Danksagung](#10-lizenz-und-danksagung)

***

## 1. Überblick

**Cert Unifier** (v2.9.0) ist ein leistungsfähiges Bash-Modul, das das Zusammenführen, die Validierung und die Vereinheitlichung von SSL/TLS-Zertifikaten und privaten Schlüsseln zu standardisierten PEM- und PFX-Bündeln automatisiert. Es ist für DevOps-Workflows und automatisierte Bereitstellungen auf Webservern (Nginx, Apache, HAProxy) ausgelegt und gewährleistet kryptografische Konsistenz sowie atomare Dateioperationen über unterschiedliche Zertifikatsstrukturen hinweg.

### Hauptzweck
Das Modul vereinfacht die Verwaltung des Zertifikatslebenszyklus, indem es:
- Endzertifikate und Zwischenketten mit den passenden privaten Schlüsseln zusammenführt
- die Übereinstimmung von RSA/EC-Moduli validiert, um die Bereitstellung nicht zusammenpassender Komponenten zu verhindern
- die Erzeugung von PKCS#12 (PFX) für Windows-/IIS-Umgebungen automatisiert
- sichere Dateiberechtigungen (0600) für sensibles kryptografisches Material durchsetzt
- sowohl moderne Certbot-Layouts als auch ältere Verzeichnisstrukturen unterstützt

***

## 2. Kernfunktionen

### 2.1 Einheitliche PEM-Zusammensetzung
- **Atomare Schreibvorgänge**: Verwendet temporäre Puffer, um die Dateiintegrität beim Zusammenführen zu gewährleisten
- **Normalisierung der Zeilenumbrüche**: Garantiert eine korrekte Trennung zwischen Schlüssel- und Kettenkomponenten
- **Automatische Erkennung**: Intelligentes Durchsuchen älterer und moderner Certbot-Layouts

### 2.2 Erweiterte kryptografische Validierung
- **Modulprüfung**: Tiefgehende Validierung privater Schlüssel gegen Zertifikate vor der Vereinheitlichung
- **Schlüsselintegrität**: Unterstützung mehrerer Engines (RSA/EC) zum Extrahieren und Vergleichen von Moduli
- **PFX-Zuordnung**: v2.9.0 führt die automatische Erkennung passender Schlüssel-/Zertifikatspaare für die PKCS#12-Erzeugung ein

### 2.3 Umfassende Layout-Unterstützung
- **Certbot-nativ**: Native Verarbeitung von `/etc/letsencrypt/live`-Strukturen
- **Altbestand**: Unterstützung der Namenskonventionen `leX.crt` und `leX.key`
- **TLD-Filterung**: Anpassbare Domainverarbeitung anhand von Top-Level-Domains (Standard: .ru, .com)

### 2.4 Funktionen für den Unternehmenseinsatz
- **Dry-Run-Modus**: Vollständige Validierung von Eingaben und Ausgabepfaden ohne Änderung des Dateisystems
- **Sichere Berechtigungen**: Automatische Vergabe von 0600-Berechtigungen für private Schlüssel und PFX-Dateien
- **Protokollierungsarchitektur**: Mehrstufige Protokollierung (DEBUG, INFO, WARN, ERROR) mit Zeitstempeln

***

## 3. Systemanforderungen

### 3.1 Mindestanforderungen
- **Betriebssystem**: Linux (jede moderne Distribution), macOS oder WSL
- **Shell**: Bash 4.0 oder neuer
- **Dienstprogramme**: `openssl`, `grep`, `awk`, `date`
- **Berechtigungen**: Lesezugriff auf die Quellzertifikate; Schreibzugriff auf die Ausgabeverzeichnisse

### 3.2 Empfohlene Konfiguration
- **OpenSSL**: 1.1.1+ (unterstützt moderne ECC- und Friendly-Name-Attribute)
- **Dateisystem**: Standard-Berechtigungsmodell von Linux/Unix wird unterstützt
- **Abhängigkeiten**: Vollständiges `openssl`-Toolkit für die PFX-Erzeugung und tiefgehende Schlüsselvalidierung

***

## 4. Schnellstartanleitung

### 4.1 Bereitstellung in 3 Schritten

**Schritt 1: Skript herunterladen**
```bash
wget https://raw.githubusercontent.com/paulmann/cert-unifier/main/cert-unifier.sh
chmod +x cert-unifier.sh
```

**Schritt 2: Grundlegende Vereinheitlichung**
```bash
./cert-unifier.sh /var/www/httpd-cert
```

**Schritt 3: Erweiterte PFX-Erzeugung**
```bash
./cert-unifier.sh --pfx --pfx-password "your_password" /etc/letsencrypt/live
```

***

## 5. Installation und Einrichtung

### 5.1 Manuelle Installation
1. Verschieben Sie das Skript in ein Verzeichnis der System-PATH (z. B. `/usr/local/bin`)
2. Stellen Sie sicher, dass die Abhängigkeiten vorhanden sind: `apt install openssl grep awk`
3. Konfigurieren Sie bei Bedarf Umgebungsvariablen:
   - `ALLOWEDTLDS="ru com org"`
   - `LOGLEVEL="INFO"`

### 5.2 Automatisierte CI/CD-Einrichtung
In Unternehmensumgebungen erfolgt die Integration über GitLab CI oder GitHub Actions:
```yaml
- name: Unify Certificates
  run: |
    export ALLOWEDTLDS="com net"
    ./cert-unifier.sh --no-key-validation --output-dir ./dist /certs/source
```

***

## 6. Architektur und Komponenten

### 6.1 Logischer Ablauf
1. **Umgebungsprüfung**: Validiert OpenSSL-Version und Abhängigkeiten
2. **Verzeichnisdurchlauf**: Iteriert über das Zielstammverzeichnis und erkennt die Layouts
3. **Validierung**: Extrahiert Moduli; vergleicht Schlüssel-Zertifikat-Paare
4. **Zusammensetzung**: Concat(key, chain) -> atomares Schreiben nach .pem
5. **PFX-Erzeugung** (optional): Wandelt das PEM-Bündel in PKCS#12 um

***

## 7. Anwendungsbeispiele

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

## 8. Parameterreferenz

| Option | Beschreibung | Standard |
| :--- | :--- | :--- |
| `-d, --dry-run` | Validieren ohne Dateien zu schreiben | `false` |
| `-v, --verbose` | DEBUG-Protokollierung aktivieren | `false` |
| `-t, --tlds` | Liste der zulässigen TLDs | `ru com` |
| `-o, --output-dir` | Ausgabepfad überschreiben | Eingabeverzeichnis |
| `--no-tld-filter` | Alle Domains verarbeiten | `false` |
| `--pfx` | PKCS12-Dateien erzeugen | `false` |
| `--pfx-password`| PFX-Passwort setzen | Leer |

***

## 9. Technische Hinweise

### 9.1 OpenSSL-Integration
Das Skript erkennt die Fähigkeiten der OpenSSL-Version zur Laufzeit. Die PFX-Unterstützung für `friendlyname` wird für OpenSSL 1.1.x und 3.x automatisch aktiviert, was eine bessere Einbindung in die Oberfläche des Windows-Zertifikat-Managers gewährleistet.

### 9.2 Mechanismus für atomares Schreiben
Um Race Conditions zu vermeiden, bei denen ein Webserver ein nur teilweise geschriebenes Zertifikat lesen könnte, schreibt **Cert Unifier** nach `*.pem.new` und führt nach erfolgreicher Validierung ein atomares Verschieben bzw. Umbenennen durch.

***

## 10. Lizenz und Danksagung

### 10.1 Lizenz
Veröffentlicht unter der **PolyForm Noncommercial License 1.0.0**. Einzelheiten siehe `LICENSE`.

### 10.2 Urheberrecht
Copyright (c) 2026 **Mikhail Deynekin**.
- **E-Mail**: [mid1977@gmail.com](mailto:mid1977@gmail.com)
- **GitHub**: [paulmann](https://github.com/paulmann)
- **Web**: [deynekin.com](https://deynekin.com/)

---
**v2.9.0** • **Vereinheitlichung von Unternehmenskryptografie** • **Aktiv**
© 2026 Paulmann. Einheitliche PKI-Verwaltung.
