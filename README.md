# checkip — IP Intelligence, ASN, RDAP, PTR & Approximate Geo CLI (`checkip.sh`)

🇺🇸 **English** | 🇧🇷 [Português (BR)](README-ptbr.md) | 🇪🇸 [Español](README-es.md)

[![License](https://img.shields.io/badge/license-Apache--2.0-green.svg)](LICENSE) [![Version](https://img.shields.io/badge/version-2.0.0-blue.svg)](https://github.com/sr00t3d/checkip/releases) [![Shell](https://img.shields.io/badge/bash-4.0+-blue.svg)](https://www.gnu.org/software/bash/)

![CheckIP Cover](checkip-cover.webp)

`checkip.sh` is a lightweight Bash CLI for quick IP and domain network reconnaissance: resolves domains to IPv4/IPv6, looks up Reverse DNS (PTR), queries ASN/ISP/Anycast and approximate city-level geolocation (`ipinfo.io` with automatic `ipwho.is` fallback), fetches official **RIR IP RDAP** ownership blocks (`rdap.org/ip/<ip>`), and outputs clean `table`, `json`, or `csv`.

> **Historical Credits:** Refactored from the original 2012 script by **Percio Andrade (Percio Castelo)**. Replaced the deprecated Google Geocoding API and private `hostname -i` lookup with modern HTTPS APIs, official IP RDAP, and honest city/ISP geolocation accuracy disclosures.

## Key Features

- **Flexible Input:** accepts IPv4, IPv6, domains (auto-resolved via `dig`), or `--my-ip` / `-i` (public egress IP).
- **IP Intelligence & Ownership:** ASN/Organization, Anycast indicator, Reverse DNS (PTR), and official RIR RDAP network block (`name`, `handle`, `CIDR`, `country`).
- **Approximate Geolocation + Maps:** city, region, country, postal code, timezone, coordinates, and OpenStreetMap/Google Maps links — with an explicit accuracy notice (IPs resolve to ISP/datacenter allocations, never street-level GPS).
- **RFC1918 / Private IP Guard:** detects private/loopback/CGNAT ranges (`10.0.0.0/8`, `192.168.0.0/16`, `172.16.0.0/12`, `100.64.0.0/10`, `fe80::`) and skips unnecessary external API calls.
- **Automation-Ready:** `-o table|json|csv`, `--no-rdap`, `-q/--quiet`, `--no-color`, `-V/--version`, `-h/--help`, optional `IPINFO_TOKEN`.

## Installation

```bash
git clone https://github.com/sr00t3d/checkip.git
cd checkip
chmod +x checkip.sh
sudo install -m 0755 checkip.sh /usr/local/bin/checkip
```

## Usage

```bash
checkip 1.1.1.1
checkip perciocastelo.com.br
checkip --my-ip
checkip -o json 8.8.8.8
checkip -o csv 1.1.1.1
```

## Real Output Example

### Table Output (`checkip.sh --no-color 1.1.1.1`)

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

### Structured JSON Output (`checkip.sh -o json 8.8.8.8`)

```json
{
  "tool": "checkip.sh",
  "version": "2.0.0",
  "input": "8.8.8.8",
  "ip": "8.8.8.8",
  "scope": "public",
  "ptr": "dns.google",
  "geo": {
    "source": "ipinfo.io",
    "precision": "approximate_city_or_isp",
    "city": "Mountain View",
    "region": "California",
    "country": "US",
    "asn_org": "AS15169 Google LLC",
    "anycast": true
  },
  "rdap": {
    "network_name": "GOGL",
    "handle": "NET-8-8-8-0-2",
    "country": "US",
    "range_or_cidr": "8.8.8.0/24"
  }
}
```

## License

Licensed under the [Apache License 2.0](LICENSE).
