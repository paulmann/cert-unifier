# Cert Unifier 安全模块

[![版本](https://img.shields.io/badge/version-2.9.0-blue.svg)](https://github.com/paulmann/cert-unifier)
[![平台](https://img.shields.io/badge/platform-Linux%20%7C%20macOS-blue.svg)](https://www.linux.org/)
[![Bash](https://img.shields.io/badge/bash-4.0%2B-red.svg)](https://www.gnu.org/software/bash/)
[![OpenSSL](https://img.shields.io/badge/openssl-1.1.1%2B-orange.svg)](https://www.openssl.org/)

<!-- md-i18n:switcher -->
**其他语言：** [English](README.md) · [Deutsch](README.de.md) · 中文 · [हिन्दी](README.hi.md) · [Español](README.es.md) · [Русский](README.ru.md)

- [1. 概述](#1-概述)
- [2. 主要特性](#2-主要特性)
- [3. 系统要求](#3-系统要求)
- [4. 快速开始](#4-快速开始)
- [5. 安装与配置](#5-安装与配置)
- [6. 架构与组件](#6-架构与组件)
- [7. 用法示例](#7-用法示例)
- [8. 参数参考](#8-参数参考)
- [9. 技术说明](#9-技术说明)
- [10. 许可证与致谢](#10-许可证与致谢)

***

## 1. 概述

**Cert Unifier**（v2.9.0）是一个高性能 Bash 模块，用于自动化地组装、校验并把 SSL/TLS 证书与私钥统一为标准的 PEM 和 PFX 捆绑包。它为 DevOps 工作流和自动化 Web 服务器部署（Nginx、Apache、HAProxy）而构建，在多样的证书结构下保证密码学一致性与文件操作的原子性。

### 主要用途
该模块通过以下方式简化证书生命周期管理：
- 把叶证书与中间证书链同匹配的私钥合并
- 校验 RSA/EC 模数是否一致，避免部署不匹配的材料
- 自动生成 PKCS#12（PFX）以适配 Windows/IIS 环境
- 对敏感密码学材料强制安全文件权限（0600）
- 同时支持现代 Certbot 布局与旧式目录结构

***

## 2. 主要特性

### 2.1 统一的 PEM 组装
- **原子写入**：使用临时缓冲区，确保组装期间的文件完整性
- **换行规范化**：保证密钥与链组件之间正确分隔
- **自动发现**：智能扫描旧式与现代 Certbot 布局

### 2.2 高级密码学校验
- **模数验证**：统一之前对私钥与证书进行深度校验
- **密钥完整性**：多引擎支持（RSA/EC）进行模数提取与比较
- **PFX 匹配**：v2.9.0 引入自动发现匹配的密钥/证书对，用于创建 PKCS#12

### 2.3 全面的布局支持
- **Certbot 原生**：原生处理 `/etc/letsencrypt/live` 结构
- **旧式支持**：支持 `leX.crt` 与 `leX.key` 命名约定
- **TLD 过滤**：按顶级域自定义要处理的域名（默认：.ru、.com）

### 2.4 企业部署特性
- **试运行模式**：完整校验输入与输出路径，不修改文件系统
- **安全权限**：自动为私钥和 PFX 文件应用 0600 权限
- **日志架构**：多级别日志（DEBUG、INFO、WARN、ERROR），带时间戳

***

## 3. 系统要求

### 3.1 最低要求
- **操作系统**：Linux（任意现代发行版）、macOS 或 WSL
- **Shell**：Bash 4.0 或更高版本
- **工具**：`openssl`、`grep`、`awk`、`date`
- **权限**：对源证书的读取权限；对输出目录的写入权限

### 3.2 建议配置
- **OpenSSL**：1.1.1+（支持现代 ECC 与友好名称属性）
- **文件系统**：支持标准 Linux/Unix 权限模型
- **依赖**：完整的 `openssl` 工具集，用于生成 PFX 与深度密钥校验

***

## 4. 快速开始

### 4.1 三步完成部署

**第 1 步：下载脚本**
```bash
wget https://raw.githubusercontent.com/paulmann/cert-unifier/main/cert-unifier.sh
chmod +x cert-unifier.sh
```

**第 2 步：基础统一**
```bash
./cert-unifier.sh /var/www/httpd-cert
```

**第 3 步：高级 PFX 生成**
```bash
./cert-unifier.sh --pfx --pfx-password "your_password" /etc/letsencrypt/live
```

***

## 5. 安装与配置

### 5.1 手动安装
1. 把脚本移动到系统 PATH 目录（例如 `/usr/local/bin`）
2. 确认依赖已满足：`apt install openssl grep awk`
3. 如有需要，配置环境变量：
   - `ALLOWEDTLDS="ru com org"`
   - `LOGLEVEL="INFO"`

### 5.2 自动化 CI/CD 配置
在企业环境中，通过 GitLab CI 或 GitHub Actions 集成：
```yaml
- name: Unify Certificates
  run: |
    export ALLOWEDTLDS="com net"
    ./cert-unifier.sh --no-key-validation --output-dir ./dist /certs/source
```

***

## 6. 架构与组件

### 6.1 逻辑流程
1. **环境检查**：校验 OpenSSL 版本与依赖
2. **目录扫描**：遍历目标根目录，识别布局
3. **校验**：提取模数；比较密钥与证书对
4. **组装**：Concat(key, chain) -> 原子写入 .pem
5. **PFX 生成**（可选）：把 PEM 捆绑包转换为 PKCS#12

***

## 7. 用法示例

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

## 8. 参数参考

| 选项 | 说明 | 默认值 |
| :--- | :--- | :--- |
| `-d, --dry-run` | 校验但不写入文件 | `false` |
| `-v, --verbose` | 启用 DEBUG 级别日志 | `false` |
| `-t, --tlds` | 允许的 TLD 列表 | `ru com` |
| `-o, --output-dir` | 覆盖输出路径 | 输入目录 |
| `--no-tld-filter` | 处理所有域名 | `false` |
| `--pfx` | 生成 PKCS12 文件 | `false` |
| `--pfx-password`| 设置 PFX 密码 | 空 |

***

## 9. 技术说明

### 9.1 OpenSSL 集成
脚本在运行时检测 OpenSSL 版本的能力。对 OpenSSL 1.1.x 与 3.x 自动启用 PFX `friendlyname` 支持，从而在 Windows 证书管理器中获得更好的界面集成。

### 9.2 原子写入机制
为避免 Web 服务器读到写了一半的证书这类竞态条件，**Cert Unifier** 先写入 `*.pem.new`，校验成功后再执行原子的移动/重命名。

***

## 10. 许可证与致谢

### 10.1 许可证
以 **PolyForm Noncommercial License 1.0.0** 分发。详见 `LICENSE`。

### 10.2 版权
版权所有 (c) 2026 **Mikhail Deynekin**。
- **邮箱**：[mid1977@gmail.com](mailto:mid1977@gmail.com)
- **GitHub**：[paulmann](https://github.com/paulmann)
- **网站**：[deynekin.com](https://deynekin.com/)

---
**v2.9.0** • **企业级密码学统一** • **活跃**
© 2026 Paulmann. 统一的 PKI 管理。
