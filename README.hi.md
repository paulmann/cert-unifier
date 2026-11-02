# Cert Unifier

**संस्करण 3.1.1** — Let's Encrypt, Certbot और लेगेसी लेआउट के लिए सत्यापित PEM और PFX एकीकरण।

[English](README.md) · [Deutsch](README.de.md) · [中文](README.zh.md) · [हिन्दी](README.hi.md) · [Español](README.es.md) · [Русский](README.ru.md)

[![CI](https://github.com/paulmann/cert-unifier/actions/workflows/ci.yml/badge.svg)](https://github.com/paulmann/cert-unifier/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue)](LICENSE)
[![Bash 4.0+](https://img.shields.io/badge/bash-4.0%2B-4EAA25)](https://www.gnu.org/software/bash/)
[![OpenSSL 1.1.1+ / 3.x](https://img.shields.io/badge/openssl-1.1.1%2B%20%7C%203.x-721412)](https://www.openssl.org/)

## विषय-सूची

- [यह क्या करता है](#यह-क्या-करता-है)
- [यूनिफ़ायर को सत्यापन क्यों चाहिए](#यूनिफ़ायर-को-सत्यापन-क्यों-चाहिए)
- [आवश्यकताएँ](#आवश्यकताएँ)
- [स्थापना](#स्थापना)
- [उपयोग](#उपयोग)
- [विकल्प](#विकल्प)
- [लेआउट](#लेआउट)
- [JSON सारांश](#json-सारांश)
- [एग्ज़िट कोड](#एग्ज़िट-कोड)
- [सुरक्षा](#सुरक्षा)
- [परीक्षण](#परीक्षण)
- [योगदान](#योगदान)
- [लाइसेंस](#लाइसेंस)
- [चेंजलॉग](#चेंजलॉग)

## यह क्या करता है

Cert Unifier Let's Encrypt सामग्री के निर्देशिका-वृक्ष को स्कैन करता है, जाँचता
है कि प्रत्येक निजी कुंजी वास्तव में अपने लीफ़ प्रमाणपत्र की है, और प्रति डोमेन
एक सत्यापित बंडल लिखता है: पहले निजी कुंजी, फिर पूरी श्रृंखला।

- **सार्वजनिक कुंजी मिलान** RSA और EC कुंजियों के लिए (`openssl x509 -pubkey`
  की तुलना `openssl pkey -pubout` से), न कि ऐसा मॉड्यूलस हैश जो केवल RSA पर
  काम करता है।
- **जो सत्यापित नहीं हो सकता, उसे लिखने से इनकार**: बेमेल कुंजी, पासफ़्रेज़ से
  सुरक्षित कुंजी, अपठनीय कुंजी या अनुपस्थित कुंजी — ऐसी प्रविष्टि टूटा हुआ
  बंडल बनाने के बजाय त्रुटि के साथ रुक जाती है।
- **परमाणु लेखन (atomic writes)**: सामग्री लक्ष्य निर्देशिका में जोड़ी जाती है,
  मोड 0600 पर बाध्य की जाती है, फिर गंतव्य पर पुनर्नामित की जाती है।
- **इडेम्पोटेंट (idempotent)**: बाइट-समान बंडल अछूता रहता है (mtime सुरक्षित
  रहता है), और पहले से मौजूद 0644 बंडल का मोड ठीक कर दिया जाता है।
- **वैकल्पिक PKCS#12** निर्यात IIS/Windows के लिए, और वैकल्पिक समाप्ति
  चेतावनियाँ।
- **मशीन-पठनीय** `--json` सारांश, ऑटोमेशन के लिए।
- **कोई नेटवर्क एक्सेस नहीं**: यह कभी प्रमाणपत्र अनुरोध, नवीनीकरण, निरसन या
  इंस्टॉल नहीं करता, और कभी किसी सेवा को पुनः लोड नहीं करता।

## यूनिफ़ायर को सत्यापन क्यों चाहिए

बंडल तभी उपयोगी है जब उसके भीतर की कुंजी प्रमाणपत्र से मेल खाती हो। सामान्य
विफलताएँ चुपचाप होती हैं: Certbot नवीनीकरण पर निजी कुंजी बदल देता है, लेगेसी
लेआउट `_le1`, `_le2`, `_le10` को साथ-साथ रखते हैं, और ऑपरेटर गलत कुंजी कॉपी
कर देते हैं। बेमेल कुंजी के साथ शुरू होने वाला वेब सर्वर बाद में हैंडशेक पर
विफल होता है — सबसे बुरे समय पर। Cert Unifier कुंजी और प्रमाणपत्र के मिलान को
चेतावनी नहीं, पूर्व-शर्त मानता है।

## आवश्यकताएँ

| आवश्यकता | क्यों |
|-------------|-----|
| Bash 4.0 या नया | arrays, `shopt`, प्रोसेस प्रतिस्थापन |
| `openssl` 1.1.1 या 3.x | सार्वजनिक कुंजी मिलान, PEM सत्यापन, PKCS#12 निर्यात |
| `flock` (वैकल्पिक) | दो रन को एक ही वृक्ष को छूने से रोकता है |
| कुंजियों और प्रमाणपत्रों पर पढ़ने की पहुँच | निजी कुंजी बंडल में पढ़ी जाती है |
| आउटपुट निर्देशिका पर लिखने की पहुँच | बंडल स्रोतों के पास लिखे जाते हैं |

Linux, macOS और WSL समर्थित हैं। macOS के साथ Bash 3.2 आता है; नया Bash
इंस्टॉल करें (`brew install bash`) या स्क्रिप्ट को Homebrew के `bash` से चलाएँ।

## स्थापना

```bash
wget https://raw.githubusercontent.com/paulmann/cert-unifier/main/cert-unifier.sh
chmod +x cert-unifier.sh
./cert-unifier.sh --version
```

सिस्टम-व्यापी:

```bash
sudo install -m 755 cert-unifier.sh /usr/local/bin/cert-unifier
```

## उपयोग

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

प्रत्येक संसाधित प्रविष्टि अपने स्रोत फ़ाइलों के पास `<domain>.pem` लिखती है
(निजी कुंजी, फिर लीफ़, फिर इंटरमीडिएट), या दिए जाने पर `--output-dir` में।

## विकल्प

| विकल्प | विवरण | डिफ़ॉल्ट |
|--------|-------------|---------|
| `-h, --help` | सहायता दिखाकर बाहर निकलें | |
| `-V, --version` | संस्करण दिखाकर बाहर निकलें | |
| `-d, --dry-run` | सत्यापित करें और रिपोर्ट करें, कुछ न लिखें | बंद |
| `-v, --verbose` | DEBUG लॉगिंग | बंद |
| `-t, --tlds LIST` | अनुमत TLD, कॉमा या स्पेस से अलग | `ru com` |
| `-o, --output-dir PATH` | बंडल स्रोतों के पास के बजाय यहाँ लिखें | स्रोत के समान |
| `--no-tld-filter` | हर डोमेन को संसाधित करें | बंद |
| `--no-key-validation` | कुंजी सत्यापित न हो पाने पर भी बंडल बनाएँ | बंद |
| `--pfx` | साथ में `.pfx` भी लिखें | बंद |
| `--pfx-password PASS` | PFX पासवर्ड (`PFX_PASSWORD` बेहतर) | खाली |
| `--skip-pfx-on-mismatch` | विफल होने के बजाय बेमेल प्रविष्टियाँ छोड़ें | बंद |
| `--check-expiry` | समाप्ति के निकट प्रमाणपत्रों पर चेतावनी दें | बंद |
| `--expiry-days N` | समाप्ति चेतावनी सीमा, दिनों में | `30` |
| `--recursive` | लेगेसी लेआउट के लिए उप-निर्देशिकाओं में जाएँ | बंद |
| `--json` | stdout पर मशीन-पठनीय सारांश दें | बंद |

पर्यावरण चर: `ALLOWED_TLDS`, `LOG_LEVEL` (`DEBUG`, `INFO`, `WARN`, `ERROR`),
`PFX_PASSWORD`, `CERT_UNIFIER_LOCK`, `NO_KEY_VALIDATION`.

## लेआउट

**Certbot**

```text
/etc/letsencrypt/live/example.com/fullchain.pem
/etc/letsencrypt/live/example.com/privkey.pem
→ /etc/letsencrypt/live/example.com/example.com.pem
```

**लेगेसी**

```text
example.com_le10.crt      leaf certificate
example.com_le10.crtca    chain
example.com_le10.key      private key (or example.com.key)
→ example.com.pem
```

`N` कोई भी संख्या हो सकती है। जब एक ही निर्देशिका में एक डोमेन की कई पीढ़ियाँ
हों, तो सबसे बड़ा `N` जीतता है, इसलिए पुराना `_le1` कभी नए `_le10` को
ओवरराइट नहीं करता।

## JSON सारांश

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

`status` का मान `success`, `none` (कुछ भी मेल नहीं खाया) या `error` होता है।
चेतावनियाँ और त्रुटियाँ अब भी stderr पर जाती हैं ताकि stdout पार्स करने योग्य
रहे।

## एग्ज़िट कोड

| कोड | अर्थ |
|------|---------|
| 0 | जो अनुरोध किया गया, सब हो गया (`--dry-run` में सब योजनाबद्ध हो गया) |
| 1 | रनटाइम या सत्यापन त्रुटि; कम से कम एक प्रविष्टि अस्वीकार हुई |
| 2 | कोई मेल खाता प्रमाणपत्र नहीं मिला |
| 130 | INT या TERM से बाधित |

## सुरक्षा

- निजी कुंजी हमेशा `umask 077` के अंतर्गत मोड 0600 के साथ लिखी जाती है।
- लेखन लक्ष्य निर्देशिका में परमाणु है; विफल रन पिछला बंडल अछूता छोड़ देता
  है।
- स्कैन किए गए वृक्ष के बाहर बनाई जाने वाली एकमात्र फ़ाइल लॉक फ़ाइल है
  (`/var/lock/cert-unifier.lock`, `CERT_UNIFIER_LOCK` से बदलें)।
- PFX पासवर्ड OpenSSL को कमांड लाइन पर दिया जाता है, इसलिए उस कॉल की अवधि
  में यह `ps` में दिखता है। अल्पकालिक पर्यावरण चर पसंद करें; खाली पासवर्ड
  बिना एन्क्रिप्शन वाला PFX बनाता है।
- स्क्रिप्ट कभी स्रोत फ़ाइलें नहीं हटाती, कभी नेटवर्क को नहीं छूती और कभी
  सेवा को पुनः लोड नहीं करती।

## परीक्षण

```bash
chmod +x tests/run-tests.sh
./tests/run-tests.sh
```

सुइट OpenSSL से वास्तविक RSA और EC फ़िक्स्चर बनाती है और एग्ज़िट कोड, बंडल
सामग्री, अनुमतियाँ, इडेम्पोटेंसी, dry-run व्यवहार, JSON वैधता, PKCS#12 निर्यात,
बेमेल/अनुपस्थित/पासफ़्रेज़-सुरक्षित कुंजियों के इनकार, और सफ़ाई की जाँच करती
है। यह हर push पर GitHub Actions में चलती है।

## योगदान

[CONTRIBUTING.md](CONTRIBUTING.md) और [SECURITY.md](SECURITY.md) देखें।
बदलावों से `tests/run-tests.sh` और `shellcheck` साफ़ रहने चाहिए।

## लाइसेंस

यह परियोजना [MIT](LICENSE) लाइसेंस के अंतर्गत वितरित की गई है, © 2026 Mikhail Deynekin।

## चेंजलॉग

[CHANGELOG.md](CHANGELOG.md) देखें।
