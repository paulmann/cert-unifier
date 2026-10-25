# Módulo de seguridad Cert Unifier

[![Versión](https://img.shields.io/badge/version-2.9.0-blue.svg)](https://github.com/paulmann/cert-unifier)
[![Plataforma](https://img.shields.io/badge/platform-Linux%20%7C%20macOS-blue.svg)](https://www.linux.org/)
[![Bash](https://img.shields.io/badge/bash-4.0%2B-red.svg)](https://www.gnu.org/software/bash/)
[![OpenSSL](https://img.shields.io/badge/openssl-1.1.1%2B-orange.svg)](https://www.openssl.org/)

<!-- md-i18n:switcher -->
**En otros idiomas:** [English](README.md) · [Deutsch](README.de.md) · [中文](README.zh.md) · [हिन्दी](README.hi.md) · Español · [Русский](README.ru.md)

- [1. Vista general](#1-vista-general)
- [2. Funciones principales](#2-funciones-principales)
- [3. Requisitos del sistema](#3-requisitos-del-sistema)
- [4. Guía de inicio rápido](#4-guía-de-inicio-rápido)
- [5. Instalación y configuración](#5-instalación-y-configuración)
- [6. Arquitectura y componentes](#6-arquitectura-y-componentes)
- [7. Ejemplos de uso](#7-ejemplos-de-uso)
- [8. Referencia de parámetros](#8-referencia-de-parámetros)
- [9. Consideraciones técnicas](#9-consideraciones-técnicas)
- [10. Licencia y reconocimientos](#10-licencia-y-reconocimientos)

***

## 1. Vista general

**Cert Unifier** (v2.9.0) es un módulo Bash de alto rendimiento diseñado para automatizar el ensamblado, la validación y la unificación de certificados SSL/TLS y claves privadas en paquetes PEM y PFX estandarizados. Concebido para flujos de trabajo DevOps y despliegues automatizados de servidores web (Nginx, Apache, HAProxy), garantiza la consistencia criptográfica y las operaciones de archivo atómicas en estructuras de certificados diversas.

### Propósito principal
El módulo simplifica la gestión del ciclo de vida de los certificados mediante:
- La fusión de certificados hoja y cadenas intermedias con sus claves privadas correspondientes
- La validación de la coincidencia de módulos RSA/EC para impedir el despliegue de activos no correspondientes
- La automatización de la generación de PKCS#12 (PFX) para entornos Windows/IIS
- La aplicación de permisos de archivo seguros (0600) al material criptográfico sensible
- La compatibilidad tanto con las estructuras modernas de Certbot como con las estructuras de directorios heredadas

***

## 2. Funciones principales

### 2.1 Ensamblado unificado de PEM
- **Escrituras atómicas**: utiliza búferes temporales para garantizar la integridad del archivo durante el ensamblado
- **Normalización de saltos de línea**: separación correcta garantizada entre la clave y los componentes de la cadena
- **Descubrimiento automático**: escaneo inteligente de las estructuras de Certbot heredadas y modernas

### 2.2 Validación criptográfica avanzada
- **Verificación de módulos**: validación profunda de las claves privadas frente a los certificados antes de la unificación
- **Integridad de las claves**: compatibilidad con varios motores (RSA/EC) para la extracción y la comparación de módulos
- **Coincidencia para PFX**: la versión 2.9.0 incorpora el descubrimiento automático de pares clave/certificado coincidentes para la creación de PKCS#12

### 2.3 Compatibilidad completa de estructuras
- **Certbot nativo**: procesamiento nativo de las estructuras `/etc/letsencrypt/live`
- **Compatibilidad heredada**: compatibilidad con las convenciones de nombres `leX.crt` y `leX.key`
- **Filtrado por TLD**: procesamiento de dominios personalizable según los dominios de nivel superior (por defecto: .ru, .com)

### 2.4 Funciones para despliegues empresariales
- **Modo de simulación**: validación completa de las entradas y de las rutas de salida sin modificar el sistema de archivos
- **Permisos seguros**: aplicación automática de permisos 0600 a las claves privadas y a los archivos PFX
- **Arquitectura de registro**: registro multinivel (DEBUG, INFO, WARN, ERROR) con marcas de tiempo

***

## 3. Requisitos del sistema

### 3.1 Requisitos mínimos
- **SO**: Linux (cualquier distribución moderna), macOS o WSL
- **Shell**: Bash 4.0 o posterior
- **Utilidades**: `openssl`, `grep`, `awk`, `date`
- **Permisos**: acceso de lectura a los certificados de origen; acceso de escritura a los directorios de salida

### 3.2 Configuración recomendada
- **OpenSSL**: 1.1.1+ (admite ECC moderno y atributos de nombre amigable)
- **Sistema de archivos**: compatible con el modelo estándar de permisos de Linux/Unix
- **Dependencias**: kit completo de `openssl` para la generación de PFX y la validación profunda de claves

***

## 4. Guía de inicio rápido

### 4.1 Despliegue en 3 pasos

**Paso 1: Descargar el script**
```bash
wget https://raw.githubusercontent.com/paulmann/cert-unifier/main/cert-unifier.sh
chmod +x cert-unifier.sh
```

**Paso 2: Unificación básica**
```bash
./cert-unifier.sh /var/www/httpd-cert
```

**Paso 3: Generación avanzada de PFX**
```bash
./cert-unifier.sh --pfx --pfx-password "your_password" /etc/letsencrypt/live
```

***

## 5. Instalación y configuración

### 5.1 Instalación manual
1. Mueva el script a un directorio del PATH del sistema (por ejemplo, `/usr/local/bin`)
2. Asegúrese de que las dependencias estén satisfechas: `apt install openssl grep awk`
3. Configure las variables de entorno si es necesario:
   - `ALLOWEDTLDS="ru com org"`
   - `LOGLEVEL="INFO"`

### 5.2 Configuración automatizada de CI/CD
En entornos corporativos, integre mediante GitLab CI o GitHub Actions:
```yaml
- name: Unify Certificates
  run: |
    export ALLOWEDTLDS="com net"
    ./cert-unifier.sh --no-key-validation --output-dir ./dist /certs/source
```

***

## 6. Arquitectura y componentes

### 6.1 Flujo lógico
1. **Comprobación del entorno**: valida la versión de OpenSSL y las dependencias
2. **Escaneo de directorios**: recorre el directorio raíz de destino e identifica las estructuras
3. **Validación**: extrae los módulos; compara los pares clave-certificado
4. **Ensamblado**: Concat(clave, cadena) -> escritura atómica en .pem
5. **Generación de PFX** (opcional): convierte el paquete PEM a PKCS#12

***

## 7. Ejemplos de uso

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

## 8. Referencia de parámetros

| Opción | Descripción | Valor predeterminado |
| :--- | :--- | :--- |
| `-d, --dry-run` | Valida sin escribir archivos | `false` |
| `-v, --verbose` | Activa el registro de nivel DEBUG | `false` |
| `-t, --tlds` | Lista de TLD permitidos | `ru com` |
| `-o, --output-dir` | Sobrescribe la ruta de salida | Directorio de entrada |
| `--no-tld-filter` | Procesa todos los dominios | `false` |
| `--pfx` | Genera archivos PKCS12 | `false` |
| `--pfx-password`| Establece la contraseña del PFX | Vacío |

***

## 9. Consideraciones técnicas

### 9.1 Integración con OpenSSL
El script detecta las capacidades de la versión de OpenSSL en tiempo de ejecución. La compatibilidad con `friendlyname` de PFX se habilita automáticamente para OpenSSL 1.1.x y 3.x, lo que garantiza una mejor integración con la interfaz del Administrador de certificados de Windows.

### 9.2 Mecanismo de escritura atómica
Para evitar condiciones de carrera en las que un servidor web podría leer un certificado escrito parcialmente, **Cert Unifier** escribe en `*.pem.new` y realiza un movimiento o renombrado atómico tras una validación correcta.

***

## 10. Licencia y reconocimientos

### 10.1 Licencia
Distribuido bajo la **PolyForm Noncommercial License 1.0.0**. Consulte `LICENSE` para obtener más detalles.

### 10.2 Copyright
Copyright (c) 2026 **Mikhail Deynekin**.
- **Correo electrónico**: [mid1977@gmail.com](mailto:mid1977@gmail.com)
- **GitHub**: [paulmann](https://github.com/paulmann)
- **Web**: [deynekin.com](https://deynekin.com/)

---
**v2.9.0** • **Unificación criptográfica empresarial** • **Activo**
© 2026 Paulmann. Gestión PKI unificada.
