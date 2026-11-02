# Cert Unifier

**版本 3.1.1** — 面向 Let's Encrypt、Certbot 与旧式布局的、经过校验的 PEM 与 PFX 统一工具。

[English](README.md) · [Deutsch](README.de.md) · [中文](README.zh.md) · [हिन्दी](README.hi.md) · [Español](README.es.md) · [Русский](README.ru.md)

[![CI](https://github.com/paulmann/cert-unifier/actions/workflows/ci.yml/badge.svg)](https://github.com/paulmann/cert-unifier/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue)](LICENSE)
[![Bash 4.0+](https://img.shields.io/badge/bash-4.0%2B-4EAA25)](https://www.gnu.org/software/bash/)
[![OpenSSL 1.1.1+ / 3.x](https://img.shields.io/badge/openssl-1.1.1%2B%20%7C%203.x-721412)](https://www.openssl.org/)

## 目录

- [功能说明](#功能说明)
- [为什么统一工具必须校验](#为什么统一工具必须校验)
- [环境要求](#环境要求)
- [安装](#安装)
- [用法](#用法)
- [选项](#选项)
- [目录布局](#目录布局)
- [JSON 摘要](#json-摘要)
- [退出码](#退出码)
- [安全性](#安全性)
- [测试](#测试)
- [参与贡献](#参与贡献)
- [许可证](#许可证)
- [更新日志](#更新日志)

## 功能说明

Cert Unifier 遍历包含 Let's Encrypt 证书材料的目录树，检查每个私钥确实
属于其叶子证书，然后为每个域名写出一个经过校验的包：私钥在前，完整证书
链在后。

- **公钥比对**：对 RSA 和 EC 密钥都适用（用 `openssl x509 -pubkey` 与
  `openssl pkey -pubout` 比对），而不是只对 RSA 有效的模数哈希。
- **无法校验的内容一律不写**：密钥不匹配、密钥受口令保护、密钥不可读或
  缺少密钥，都会让该条目以错误终止，而不会生成损坏的包。
- **原子写入**：内容在目标目录中组装，强制为 0600 权限，然后重命名覆盖
  目标文件。
- **幂等**：字节完全相同的包保持不变（保留 mtime），已存在的 0644 权限
  包会被修正权限。
- **可选的 PKCS#12** 导出（面向 IIS/Windows），以及可选的到期警告。
- **机器可读**的 `--json` 摘要，便于自动化。
- **不访问网络**：从不申请、续期、吊销或安装证书，也从不重载服务。

## 为什么统一工具必须校验

只有当包中的密钥与证书匹配时，这个包才有用。常见的失败模式是静默的：
Certbot 在续期时会轮换私钥，旧式布局会把 `_le1`、`_le2`、`_le10` 并排
保留，运维人员也可能复制错密钥。用不匹配的密钥启动的 Web 服务器会在之后
握手时失败，而且往往是在最糟糕的时刻。Cert Unifier 把密钥与证书的匹配
当作前提条件，而不是警告。

## 环境要求

| 要求 | 原因 |
|-------------|-----|
| Bash 4.0 或更高版本 | 数组、`shopt`、进程替换 |
| `openssl` 1.1.1 或 3.x | 公钥比对、PEM 校验、PKCS#12 导出 |
| `flock`（可选） | 避免两次运行同时操作同一棵目录树 |
| 对密钥和证书的读权限 | 私钥会被写入包中 |
| 对输出目录的写权限 | 包写在源文件旁边 |

支持 Linux、macOS 和 WSL。macOS 自带的是 Bash 3.2；请安装更新的 Bash
（`brew install bash`），或用 Homebrew 的 `bash` 运行脚本。

## 安装

```bash
wget https://raw.githubusercontent.com/paulmann/cert-unifier/main/cert-unifier.sh
chmod +x cert-unifier.sh
./cert-unifier.sh --version
```

系统级安装：

```bash
sudo install -m 755 cert-unifier.sh /usr/local/bin/cert-unifier
```

## 用法

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

每个被处理的条目都会在其源文件旁写出 `<domain>.pem`（私钥、叶子证书，
然后是中间证书）；若指定了 `--output-dir`，则写入该目录。

## 选项

| 选项 | 说明 | 默认值 |
|--------|-------------|---------|
| `-h, --help` | 显示帮助并退出 | |
| `-V, --version` | 显示版本并退出 | |
| `-d, --dry-run` | 只校验并报告，不写任何文件 | 关闭 |
| `-v, --verbose` | DEBUG 级日志 | 关闭 |
| `-t, --tlds LIST` | 允许的 TLD，用逗号或空格分隔 | `ru com` |
| `-o, --output-dir PATH` | 把包写到此处而不是源文件旁 | 与源相同 |
| `--no-tld-filter` | 处理所有域名 | 关闭 |
| `--no-key-validation` | 即使无法校验密钥也照样打包 | 关闭 |
| `--pfx` | 同时写出 `.pfx` | 关闭 |
| `--pfx-password PASS` | PFX 口令（优先用 `PFX_PASSWORD`） | 空 |
| `--skip-pfx-on-mismatch` | 跳过不匹配的条目而不是报错 | 关闭 |
| `--check-expiry` | 对即将到期的证书发出警告 | 关闭 |
| `--expiry-days N` | 到期警告阈值（天） | `30` |
| `--recursive` | 为旧式布局递归进入子目录 | 关闭 |
| `--json` | 向 stdout 输出机器可读摘要 | 关闭 |

环境变量：`ALLOWED_TLDS`、`LOG_LEVEL`（`DEBUG`、`INFO`、`WARN`、`ERROR`）、
`PFX_PASSWORD`、`CERT_UNIFIER_LOCK`、`NO_KEY_VALIDATION`。

## 目录布局

**Certbot**

```text
/etc/letsencrypt/live/example.com/fullchain.pem
/etc/letsencrypt/live/example.com/privkey.pem
→ /etc/letsencrypt/live/example.com/example.com.pem
```

**旧式**

```text
example.com_le10.crt      leaf certificate
example.com_le10.crtca    chain
example.com_le10.key      private key (or example.com.key)
→ example.com.pem
```

`N` 可以是任意数字。同一目录中若存在同一域名的多个代次，`N` 最大者胜出，
因此旧的 `_le1` 永远不会覆盖更新的 `_le10`。

## JSON 摘要

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

`status` 的取值为 `success`、`none`（没有匹配项）或 `error`。警告和错误仍然
写入 stderr，以保证 stdout 可解析。

## 退出码

| 码 | 含义 |
|------|---------|
| 0 | 所请求的操作全部完成（在 `--dry-run` 下为全部已规划） |
| 1 | 运行时或校验错误；至少有一个条目被拒绝 |
| 2 | 未找到匹配的证书 |
| 130 | 被 INT 或 TERM 中断 |

## 安全性

- 私钥始终以 0600 权限写入，且处于 `umask 077` 之下。
- 写入在目标目录内是原子的；失败的运行会保留先前的包不变。
- 在扫描目录树之外创建的唯一文件是锁文件
  （`/var/lock/cert-unifier.lock`，可用 `CERT_UNIFIER_LOCK` 覆盖）。
- PFX 口令通过命令行传给 OpenSSL，因此在这次调用期间能在 `ps` 中看到。
  请优先使用短生命周期的环境变量；空口令会生成未加密的 PFX。
- 脚本从不删除源文件，从不访问网络，也从不重载服务。

## 测试

```bash
chmod +x tests/run-tests.sh
./tests/run-tests.sh
```

该测试套件用 OpenSSL 生成真实的 RSA 和 EC 测试夹具，并断言退出码、包内容、
权限、幂等性、dry-run 行为、JSON 有效性、PKCS#12 导出、对不匹配/缺失/受
口令保护的密钥的拒绝，以及清理。它会在每次 push 时于 GitHub Actions 中运行。

## 参与贡献

参见 [CONTRIBUTING.md](CONTRIBUTING.md) 和 [SECURITY.md](SECURITY.md)。改动
应保持 `tests/run-tests.sh` 与 `shellcheck` 干净通过。

## 许可证

本项目以 [MIT](LICENSE) 许可证发布，© 2026 Mikhail Deynekin。

## 更新日志

参见 [CHANGELOG.md](CHANGELOG.md)。
