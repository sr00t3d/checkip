# checkip — Inteligencia de IP, ASN, RDAP, PTR y Geo Aproximada (`checkip.sh`)

🇺🇸 [English](README.md) | 🇧🇷 [Português (BR)](README-ptbr.md) | 🇪🇸 **Español**

[![License](https://img.shields.io/badge/license-Apache--2.0-green.svg)](LICENSE) [![Version](https://img.shields.io/badge/version-2.0.0-blue.svg)](https://github.com/sr00t3d/checkip/releases) [![Shell](https://img.shields.io/badge/bash-4.0+-blue.svg)](https://www.gnu.org/software/bash/)

![Portada CheckIP](checkip-cover.webp)

`checkip.sh` es una CLI ligera en Bash para reconocimiento rápido de IPs y dominios: resuelve dominios a IPv4/IPv6, consulta DNS Inverso (PTR), ASN/ISP/Anycast y geolocalización aproximada a nivel ciudad/ISP (`ipinfo.io` con fallback automático `ipwho.is`), obtiene el bloque oficial mediante **RDAP de IP** (`rdap.org/ip/<ip>`) y genera salidas en `table`, `json` y `csv`.

> **Créditos Históricos:** Refactorizado del script original de 2012 de **Percio Andrade (Percio Castelo)**.

## Uso

```bash
checkip 1.1.1.1
checkip perciocastelo.com.br
checkip --my-ip
checkip -o json 8.8.8.8
checkip -o csv 1.1.1.1
```

## Licencia

Licenciado bajo la [Apache License 2.0](LICENSE).

## Windows (PowerShell `checkip.ps1`)

Cero dependencias externas — funciona de forma nativa en **Windows PowerShell 5.1** y **PowerShell 7+**:

```powershell
.\checkip.ps1 1.1.1.1
.\checkip.ps1 1.1.1.1 8.8.8.8 -Output csv
.\checkip.ps1 -MyIp -Output json
```
