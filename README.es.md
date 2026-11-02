# Cert Unifier

**Versión 3.1.1** — unificación auditada de PEM y PFX para Let's Encrypt, Certbot y estructuras heredadas.

[English](README.md) · [Deutsch](README.de.md) · [中文](README.zh.md) · [हिन्दी](README.hi.md) · [Español](README.es.md) · [Русский](README.ru.md)

[![CI](https://github.com/paulmann/cert-unifier/actions/workflows/ci.yml/badge.svg)](https://github.com/paulmann/cert-unifier/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue)](LICENSE)
[![Bash 4.0+](https://img.shields.io/badge/bash-4.0%2B-4EAA25)](https://www.gnu.org/software/bash/)
[![OpenSSL 1.1.1+ / 3.x](https://img.shields.io/badge/openssl-1.1.1%2B%20%7C%203.x-721412)](https://www.openssl.org/)

## Contenido

- [Qué hace](#qué-hace)
- [Por qué un unificador necesita verificar](#por-qué-un-unificador-necesita-verificar)
- [Requisitos](#requisitos)
- [Instalación](#instalación)
- [Uso](#uso)
- [Opciones](#opciones)
- [Estructuras](#estructuras)
- [Resumen JSON](#resumen-json)
- [Códigos de salida](#códigos-de-salida)
- [Seguridad](#seguridad)
- [Pruebas](#pruebas)
- [Contribuir](#contribuir)
- [Licencia](#licencia)
- [Registro de cambios](#registro-de-cambios)

## Qué hace

Cert Unifier recorre un árbol de directorios con material de Let's Encrypt,
comprueba que cada clave privada pertenezca realmente a su certificado final y
escribe un paquete auditado por dominio: la clave privada seguida de la cadena
completa.

- **Cotejo de claves públicas** para claves RSA y EC (`openssl x509 -pubkey`
  frente a `openssl pkey -pubout`), no un hash del módulo que solo funciona
  con RSA.
- **Se niega a escribir lo que no puede verificar**: una clave que no coincide,
  una clave protegida con frase de contraseña, una clave ilegible o la ausencia
  de clave detienen esa entrada con un error en lugar de producir un paquete
  roto.
- **Escrituras atómicas**: el contenido se ensambla en el directorio de
  destino, se fuerza el modo 0600 y luego se renombra sobre el destino.
- **Idempotente**: un paquete idéntico byte a byte se deja intacto (se conserva
  mtime) y a un paquete 0644 preexistente se le corrige el modo.
- **Exportación opcional a PKCS#12** para IIS/Windows y avisos opcionales de
  caducidad.
- **Resumen `--json`** legible por máquina para la automatización.
- **Sin acceso a la red**: nunca solicita, renueva, revoca ni instala
  certificados, y nunca recarga un servicio.

## Por qué un unificador necesita verificar

Un paquete solo es útil si la clave que contiene coincide con el certificado.
Los fallos habituales son silenciosos: Certbot rota la clave privada en cada
renovación, las estructuras heredadas mantienen `_le1`, `_le2` y `_le10` una al
lado de otra, y los operadores copian la clave equivocada. Un servidor web que
arranca con una clave que no coincide falla más tarde en el handshake, en el
peor momento posible. Cert Unifier trata la coincidencia entre clave y
certificado como una condición previa, no como un aviso.

## Requisitos

| Requisito | Motivo |
|-------------|-----|
| Bash 4.0 o posterior | arrays, `shopt`, sustitución de procesos |
| `openssl` 1.1.1 o 3.x | cotejo de claves públicas, validación PEM, exportación PKCS#12 |
| `flock` (opcional) | evita que dos ejecuciones toquen el mismo árbol |
| Acceso de lectura a claves y certificados | la clave privada se incorpora al paquete |
| Acceso de escritura al directorio de salida | los paquetes se escriben junto a las fuentes |

Se admiten Linux, macOS y WSL. macOS incluye Bash 3.2; instale un Bash más
reciente (`brew install bash`) o ejecute el script con el `bash` de Homebrew.

## Instalación

```bash
wget https://raw.githubusercontent.com/paulmann/cert-unifier/main/cert-unifier.sh
chmod +x cert-unifier.sh
./cert-unifier.sh --version
```

En todo el sistema:

```bash
sudo install -m 755 cert-unifier.sh /usr/local/bin/cert-unifier
```

## Uso

```bash
# 1. inspect the tree without writing anything
./cert-unifier.sh --dry-run --verbose /etc/letsencrypt/live

# 2. run it on one domain directory, then on the whole tree
./cert-unifier.sh /etc/letsencrypt/live/example.com
./cert-unifier.sh /etc/letsencrypt/live

# 3. PEM plus PKCS#12 (the password is read from the environment)
PFX_PASSWORD='...' ./cert-unifier.sh --pfx /var/www/certs

# 4. legacy tree with more than one generation per domain
./cert-unifier.sh --no-tld-filter --recursive /opt/certs
```

Cada entrada procesada escribe `<domain>.pem` (clave privada, luego el
certificado final y luego los intermedios) junto a sus archivos de origen, o en
`--output-dir` si se indica.

## Opciones

| Opción | Descripción | Valor predeterminado |
|--------|-------------|---------|
| `-h, --help` | Mostrar la ayuda y salir | |
| `-V, --version` | Mostrar la versión y salir | |
| `-d, --dry-run` | Validar e informar sin escribir nada | desactivado |
| `-v, --verbose` | Registro DEBUG | desactivado |
| `-t, --tlds LIST` | TLD permitidos, separados por comas o espacios | `ru com` |
| `-o, --output-dir PATH` | Escribir los paquetes aquí en lugar de junto a las fuentes | igual que el origen |
| `--no-tld-filter` | Procesar todos los dominios | desactivado |
| `--no-key-validation` | Empaquetar aunque no se pueda verificar la clave | desactivado |
| `--pfx` | Escribir además un `.pfx` | desactivado |
| `--pfx-password PASS` | Contraseña PFX (mejor `PFX_PASSWORD`) | vacía |
| `--skip-pfx-on-mismatch` | Omitir las entradas que no coinciden en lugar de fallar | desactivado |
| `--check-expiry` | Avisar de certificados próximos a caducar | desactivado |
| `--expiry-days N` | Umbral del aviso de caducidad en días | `30` |
| `--recursive` | Descender a subdirectorios para la estructura heredada | desactivado |
| `--json` | Emitir un resumen legible por máquina en stdout | desactivado |

Variables de entorno: `ALLOWED_TLDS`, `LOG_LEVEL` (`DEBUG`, `INFO`, `WARN`,
`ERROR`), `PFX_PASSWORD`, `CERT_UNIFIER_LOCK`, `NO_KEY_VALIDATION`.

## Estructuras

**Certbot**

```text
/etc/letsencrypt/live/example.com/fullchain.pem
/etc/letsencrypt/live/example.com/privkey.pem
→ /etc/letsencrypt/live/example.com/example.com.pem
```

**Heredada**

```text
example.com_le10.crt      leaf certificate
example.com_le10.crtca    chain
example.com_le10.key      private key (or example.com.key)
→ example.com.pem
```

`N` puede ser cualquier número. Cuando hay varias generaciones de un mismo
dominio en el mismo directorio, gana el `N` más alto, de modo que un `_le1`
antiguo nunca sobrescribe un `_le10` más reciente.

## Resumen JSON

```bash
./cert-unifier.sh --json /etc/letsencrypt/live
```

```json
{
  "version": "3.1.1",
  "status": "success",
  "processed": 1,
  "skipped": 0,
  "planned": 0,
  "errors": 0,
  "warnings": 0,
  "results": [
    {"domain": "example.com", "status": "updated", "pem": "/etc/letsencrypt/live/example.com/example.com.pem", "fingerprint": "..."}
  ]
}
```

`status` es `success`, `none` (no coincidió nada) o `error`. Los avisos y
errores siguen yendo a stderr para que stdout siga siendo analizable.

## Códigos de salida

| Código | Significado |
|------|---------|
| 0 | Todo lo solicitado se hizo (en `--dry-run`, todo quedó planificado) |
| 1 | Error de ejecución o de validación; al menos una entrada fue rechazada |
| 2 | No se encontraron certificados coincidentes |
| 130 | Interrumpido por INT o TERM |

## Seguridad

- La clave privada siempre se escribe con modo 0600, bajo `umask 077`.
- Las escrituras son atómicas en el directorio de destino; una ejecución
  fallida deja intacto el paquete anterior.
- El único archivo creado fuera del árbol explorado es el archivo de bloqueo
  (`/var/lock/cert-unifier.lock`, se puede cambiar con `CERT_UNIFIER_LOCK`).
- La contraseña PFX se pasa a OpenSSL en la línea de comandos, por lo que es
  visible en `ps` durante esa llamada. Prefiera una variable de entorno de vida
  corta; una contraseña vacía produce un PFX sin cifrar.
- El script nunca elimina archivos de origen, nunca accede a la red y nunca
  recarga un servicio.

## Pruebas

```bash
chmod +x tests/run-tests.sh
./tests/run-tests.sh
```

La batería genera fixtures reales RSA y EC con OpenSSL y comprueba códigos de
salida, contenido de los paquetes, permisos, idempotencia, comportamiento en
dry-run, validez del JSON, exportación PKCS#12, rechazo de claves que no
coinciden, faltantes o protegidas con contraseña, y la limpieza. Se ejecuta en
GitHub Actions con cada push.

## Contribuir

Véanse [CONTRIBUTING.md](CONTRIBUTING.md) y [SECURITY.md](SECURITY.md). Se
espera que los cambios mantengan limpios `tests/run-tests.sh` y `shellcheck`.

## Licencia

Publicado bajo la licencia [MIT](LICENSE), © 2026 Mikhail Deynekin.

## Registro de cambios

Véase [CHANGELOG.md](CHANGELOG.md).
