# checkip — Inteligência de IP, ASN, RDAP, PTR e Geo Aproximada (`checkip.sh`)

🇺🇸 [English](README.md) | 🇧🇷 **Português (BR)** | 🇪🇸 [Español](README-es.md)

[![License](https://img.shields.io/badge/license-Apache--2.0-green.svg)](LICENSE) [![Version](https://img.shields.io/badge/version-2.0.0-blue.svg)](https://github.com/sr00t3d/checkip/releases) [![Shell](https://img.shields.io/badge/bash-4.0+-blue.svg)](https://www.gnu.org/software/bash/)

`checkip.sh` é uma CLI leve em Bash para reconhecimento rápido de IPs e domínios: resolve domínios para IPv4/IPv6, consulta DNS Reverso (PTR), ASN/ISP/Anycast e geolocalização aproximada em nível cidade/ISP (`ipinfo.io` com fallback automático `ipwho.is`), consulta o bloco oficial via **RDAP de IP** (`rdap.org/ip/<ip>`) e gera saídas em `table`, `json` e `csv`.

> **Créditos Históricos:** Refatorado do script original de 2012 de **Percio Andrade (Percio Castelo)**. Substituiu a antiga API desativada do Google Geocoding e o `hostname -i` por APIs HTTPS modernas, RDAP oficial de IP e transparência sobre a precisão de geolocalização por IP.

## Principais Recursos

- **Entrada Flexível:** aceita IPv4, IPv6, domínios (resolvidos via `dig`) ou `--my-ip` / `-i` (IP público de saída).
- **Inteligência e Titularidade de IP:** ASN/Organização, indicador Anycast, DNS Reverso (PTR) e bloco oficial RIR via RDAP (`name`, `handle`, `CIDR`, `country`).
- **Geolocalização Aproximada + Mapas:** cidade, estado, país, CEP, fuso horário, coordenadas e links OpenStreetMap/Google Maps — com aviso explícito de que IPs apontam para alocações de ISP/datacenter, não GPS de rua.
- **Proteção contra IPs Privados (RFC1918):** detecta faixas privadas/loopback/CGNAT e evita chamadas externas desnecessárias.
- **Pronto para Automação:** `-o table|json|csv`, `--no-rdap`, `-q/--quiet`, `--no-color`, `-V/--version`, `-h/--help`, suporte opcional a `IPINFO_TOKEN`.

## Instalação

```bash
git clone https://github.com/sr00t3d/checkip.git
cd checkip
chmod +x checkip.sh
sudo install -m 0755 checkip.sh /usr/local/bin/checkip
```

## Uso

```bash
checkip 1.1.1.1
checkip perciocastelo.com.br
checkip --my-ip
checkip -o json 8.8.8.8
checkip -o csv 1.1.1.1
```

## Exemplo de Saída Real

### Saída em Tabela (`checkip.sh --no-color 1.1.1.1`)

```text
=====================================================================
 checkip.sh v2.0.0 | Target: 1.1.1.1 -> 1.1.1.1 | 2026-11-21T01:08:32Z
=====================================================================
  IP / Scope   : 1.1.1.1 (public)
  Reverse PTR  : one.one.one.one
  ASN / Org    : AS13335 Cloudflare, Inc.
  Anycast      : true
  Location     : Brisbane, Queensland, AU (postal: 9010 | tz: Australia/Brisbane)
  Coords (aprox): -27.4679, 153.0281 (source: ipinfo.io)
  OpenStreetMap: https://www.openstreetmap.org/?mlat=-27.4679&mlon=153.0281#map=11/-27.4679/153.0281
  Google Maps  : https://www.google.com/maps?q=-27.4679,153.0281
  RDAP Block   : APNIC-LABS (1.1.1.0/24) | Handle: 1.1.1.0 - 1.1.1.255 | Country: AU

[!] Note: IP coordinates are approximate (ISP/datacenter/city level), never street-level GPS.
```

## Licença

Licenciado sob a [Apache License 2.0](LICENSE).
