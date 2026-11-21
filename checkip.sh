#!/usr/bin/env bash
# ==============================================================================
#  checkip.sh — IP Intelligence, ASN, RDAP, PTR & Approximate Geo CLI
# ==============================================================================
#  Author  : Percio Castelo (Percio Andrade) <percio@perciocastelo.com.br>
#  Website : https://perciocastelo.com.br
#  Project : https://perciocastelo.com.br/projetos/en/checkip.html
#  Repo    : https://github.com/sr00t3d/checkip
#  License : Apache-2.0
#  Version : 2.0.0
# ==============================================================================

set -uo pipefail

readonly SCRIPT_NAME="checkip.sh"
readonly SCRIPT_VERSION="2.0.0"

# Runtime options
TARGET=""
MY_IP=0
SKIP_RDAP=0
FORMAT="table"
QUIET=0
NO_COLOR=0

# Detected tools & metadata
HAVE_JQ=0
HAVE_PY3=0
TIMESTAMP_UTC="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

# Collected fields
INPUT_RAW=""
RESOLVED_IP=""
IP_SCOPE="public"
PTR_RECORD=""
GEO_SOURCE=""
CITY=""
REGION=""
COUNTRY=""
POSTAL=""
TIMEZONE=""
LAT=""
LON=""
ASN_ORG=""
ANYCAST="false"
RDAP_NET_NAME=""
RDAP_CIDR=""
RDAP_HANDLE=""
RDAP_COUNTRY=""
MAPS_OSM=""
MAPS_GOOGLE=""

# Colors
RED="" GREEN="" YELLOW="" CYAN="" BOLD="" RESET=""
OK="[OK]" ATT="[!]" FAIL="[ERR]"

init_colors() {
  if [[ "$NO_COLOR" -eq 0 && -t 1 && -z "${NO_COLOR:-}" && "$FORMAT" == "table" ]]; then
    RED=$'\033[0;31m'
    GREEN=$'\033[0;32m'
    YELLOW=$'\033[0;33m'
    CYAN=$'\033[0;36m'
    BOLD=$'\033[1m'
    RESET=$'\033[0m'
    OK="${GREEN}[OK]${RESET}"
    ATT="${YELLOW}[!]${RESET}"
    FAIL="${RED}[ERR]${RESET}"
  else
    RED="" GREEN="" YELLOW="" CYAN="" BOLD="" RESET=""
    OK="[OK]" ATT="[!]" FAIL="[ERR]"
  fi
}

show_help() {
  cat <<'USAGE'
checkip.sh v2.0.0 — IP Intelligence, ASN, RDAP, PTR & Approximate Geo CLI

Usage:
  checkip.sh [options] <ip-or-domain>
  checkip.sh --my-ip [-o table|json|csv]

Options:
  -i, -m, --my-ip        Inspect the current host's public egress IP
  --no-rdap              Skip RDAP IP ownership lookup (faster)
  -o, --output <fmt>     Output format: table (default), json, csv
  -q, --quiet            Suppress banner header and precision note
  --no-color             Disable ANSI colors
  -V, --version          Show version and exit
  -h, --help             Show this help and exit

Environment Variables:
  IPINFO_TOKEN           Optional ipinfo.io API token for higher rate limits

Note on Geolocation Accuracy:
  IP geolocation maps an IP to its ISP/datacenter/RIR allocation (city/region
  level), not street-level GPS coordinates of an end user or office.

Examples:
  checkip.sh 1.1.1.1
  checkip.sh perciocastelo.com.br
  checkip.sh --my-ip -o json
  checkip.sh -o csv 8.8.8.8
USAGE
}

need_cmd() {
  local missing=0 cmd
  for cmd in "$@"; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      printf '[ERR] Missing required command: %s\n' "$cmd" >&2
      missing=1
    fi
  done
  [[ "$missing" -eq 0 ]] || exit 1
}

is_ipv4() {
  [[ "$1" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]
}

is_ipv6() {
  [[ "$1" == *:* && "$1" =~ ^[0-9a-fA-F:]+$ ]]
}

is_private_ip() {
  local ip="$1"
  if [[ "$ip" =~ ^(10\.|127\.|0\.|169\.254\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[01])\.|100\.(6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7])\.) ]]; then
    return 0
  fi
  if [[ "$ip" =~ ^(::1|fe80:|fc|fd) ]]; then
    return 0
  fi
  return 1
}

resolve_target() {
  if [[ "$MY_IP" -eq 1 ]]; then
    INPUT_RAW="self"
    RESOLVED_IP="$(curl -fsS --connect-timeout 4 --max-time 8 https://api.ipify.org 2>/dev/null || \
                   curl -fsS --connect-timeout 4 --max-time 8 https://ifconfig.me 2>/dev/null || true)"
    RESOLVED_IP="$(printf '%s' "$RESOLVED_IP" | tr -d '[:space:]')"
    if [[ -z "$RESOLVED_IP" ]]; then
      printf '%s Could not determine public egress IP.\n' "$FAIL" >&2
      exit 1
    fi
    return 0
  fi

  local clean="$TARGET"
  clean="${clean#http://}"
  clean="${clean#https://}"
  clean="${clean%%/*}"
  clean="${clean%.}"
  INPUT_RAW="$clean"

  if is_ipv4 "$clean" || is_ipv6 "$clean"; then
    RESOLVED_IP="$clean"
    return 0
  fi

  if ! printf '%s' "${clean,,}" | grep -Eq '^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?(\.[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)*\.[a-z]{2,}$'; then
    printf '%s Invalid IP or domain: %s\n' "$FAIL" "$clean" >&2
    exit 1
  fi

  if command -v dig >/dev/null 2>&1; then
    RESOLVED_IP="$(dig +time=3 +tries=1 +short A "$clean" 2>/dev/null | grep -E '^[0-9.]+$' | head -n1 || true)"
    [[ -z "$RESOLVED_IP" ]] && RESOLVED_IP="$(dig +time=3 +tries=1 +short AAAA "$clean" 2>/dev/null | grep -E '^[0-9a-fA-F:]+$' | head -n1 || true)"
  elif command -v getent >/dev/null 2>&1; then
    RESOLVED_IP="$(getent ahosts "$clean" 2>/dev/null | awk '{print $1; exit}' || true)"
  fi

  if [[ -z "$RESOLVED_IP" ]]; then
    printf '%s Could not resolve domain: %s\n' "$FAIL" "$clean" >&2
    exit 1
  fi
}

query_ptr() {
  if command -v dig >/dev/null 2>&1; then
    PTR_RECORD="$(dig +time=3 +tries=1 +short -x "$RESOLVED_IP" 2>/dev/null | sed 's/\.$//' | paste -sd ',' - || true)"
  fi
}

query_geo() {
  local body="" url="https://ipinfo.io/${RESOLVED_IP}/json"
  local -a auth_hdr=()
  [[ -n "${IPINFO_TOKEN:-}" ]] && auth_hdr=(-H "Authorization: Bearer ${IPINFO_TOKEN}")

  body="$(curl -fsS --connect-timeout 4 --max-time 8 "${auth_hdr[@]}" "$url" 2>/dev/null || true)"
  if [[ -n "$body" ]] && printf '%s' "$body" | grep -q '"ip"'; then
    GEO_SOURCE="ipinfo.io"
    local parsed=""
    if [[ "$HAVE_JQ" -eq 1 ]]; then
      parsed="$(jq -r '[(.city // ""), (.region // ""), (.country // ""), (.postal // ""), (.timezone // ""), (.loc // ""), (.org // ""), ((.anycast // false) | tostring)] | join("\u001f")' 2>/dev/null <<<"$body" || true)"
    elif [[ "$HAVE_PY3" -eq 1 ]]; then
      parsed="$(python3 -c '
import json, sys
d = json.loads(sys.stdin.read())
vals = [d.get("city",""), d.get("region",""), d.get("country",""), d.get("postal",""), d.get("timezone",""), d.get("loc",""), d.get("org",""), str(bool(d.get("anycast", False))).lower()]
print("\x1f".join(str(v or "") for v in vals))
' 2>/dev/null <<<"$body" || true)"
    fi
    if [[ -n "$parsed" ]]; then
      local loc=""
      IFS=$'\x1f' read -r CITY REGION COUNTRY POSTAL TIMEZONE loc ASN_ORG ANYCAST <<<"$parsed"
      if [[ "$loc" == *,* ]]; then
        LAT="${loc%%,*}"
        LON="${loc#*,}"
      fi
    fi
  fi

  # Fallback to ipwho.is if ipinfo failed or returned empty
  if [[ -z "$GEO_SOURCE" ]]; then
    body="$(curl -fsS --connect-timeout 4 --max-time 8 "https://ipwho.is/${RESOLVED_IP}" 2>/dev/null || true)"
    if [[ -n "$body" ]] && printf '%s' "$body" | grep -q '"success":true'; then
      GEO_SOURCE="ipwho.is"
      if [[ "$HAVE_PY3" -eq 1 ]]; then
        local parsed
        parsed="$(python3 -c '
import json, sys
d = json.loads(sys.stdin.read())
conn = d.get("connection") or {}
tz = (d.get("timezone") or {}).get("id", "")
asn = conn.get("asn", "")
oname = conn.get("org") or conn.get("isp") or ""
org = ("AS%s %s" % (asn, oname)).strip() if asn else oname
vals = [d.get("city",""), d.get("region",""), d.get("country_code",""), d.get("postal",""), tz, d.get("latitude",""), d.get("longitude",""), org]
print("\x1f".join(str(v or "") for v in vals))
' 2>/dev/null <<<"$body" || true)"
        IFS=$'\x1f' read -r CITY REGION COUNTRY POSTAL TIMEZONE LAT LON ASN_ORG <<<"$parsed"
      fi
    fi
  fi

  if [[ -n "$LAT" && -n "$LON" ]]; then
    MAPS_OSM="https://www.openstreetmap.org/?mlat=${LAT}&mlon=${LON}#map=11/${LAT}/${LON}"
    MAPS_GOOGLE="https://www.google.com/maps?q=${LAT},${LON}"
  fi
}

query_rdap_ip() {
  [[ "$SKIP_RDAP" -eq 1 ]] && return 0
  local body=""
  body="$(curl -fsS -L --connect-timeout 4 --max-time 8 -H 'Accept: application/rdap+json, application/json' "https://rdap.org/ip/${RESOLVED_IP}" 2>/dev/null || true)"
  [[ -z "$body" ]] && return 0

  local parsed=""
  if [[ "$HAVE_JQ" -eq 1 ]]; then
    parsed="$(jq -r '[(.name // ""), (.handle // ""), (.country // ""), (if .cidr0_cidrs then ([.cidr0_cidrs[] | "\(.v4prefix // .v6prefix)/\(.length)"] | join(", ")) else (if .startAddress and .endAddress then "\(.startAddress) - \(.endAddress)" else "" end) end)] | join("\u001f")' 2>/dev/null <<<"$body" || true)"
  elif [[ "$HAVE_PY3" -eq 1 ]]; then
    parsed="$(python3 -c '
import json, sys
d = json.loads(sys.stdin.read())
cidrs = d.get("cidr0_cidrs") or []
if cidrs:
    parts = []
    for c in cidrs:
        pfx = c.get("v4prefix") or c.get("v6prefix") or ""
        ln = c.get("length", "")
        if pfx:
            parts.append("%s/%s" % (pfx, ln))
    cidr = ", ".join(parts)
elif d.get("startAddress") and d.get("endAddress"):
    cidr = "%s - %s" % (d["startAddress"], d["endAddress"])
else:
    cidr = ""
print("\x1f".join(str(x or "") for x in [d.get("name",""), d.get("handle",""), d.get("country",""), cidr]))
' 2>/dev/null <<<"$body" || true)"
  fi
  if [[ -n "$parsed" ]]; then
    IFS=$'\x1f' read -r RDAP_NET_NAME RDAP_HANDLE RDAP_COUNTRY RDAP_CIDR <<<"$parsed"
  fi
}

json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\r'/}"
  printf '%s' "$s"
}

csv_escape() {
  local s="$1"
  s="${s//$'\n'/ ; }"
  s="${s//$'\r'/}"
  s="${s//\"/\"\"}"
  printf '"%s"' "$s"
}

render_output() {
  case "$FORMAT" in
    json)
      cat <<EOF
{
  "tool": "${SCRIPT_NAME}",
  "version": "${SCRIPT_VERSION}",
  "timestamp": "$(json_escape "$TIMESTAMP_UTC")",
  "input": "$(json_escape "$INPUT_RAW")",
  "ip": "$(json_escape "$RESOLVED_IP")",
  "scope": "$(json_escape "$IP_SCOPE")",
  "ptr": "$(json_escape "$PTR_RECORD")",
  "geo": {
    "source": "$(json_escape "$GEO_SOURCE")",
    "precision": "approximate_city_or_isp",
    "city": "$(json_escape "$CITY")",
    "region": "$(json_escape "$REGION")",
    "country": "$(json_escape "$COUNTRY")",
    "postal": "$(json_escape "$POSTAL")",
    "timezone": "$(json_escape "$TIMEZONE")",
    "latitude": "$(json_escape "$LAT")",
    "longitude": "$(json_escape "$LON")",
    "asn_org": "$(json_escape "$ASN_ORG")",
    "anycast": ${ANYCAST:-false},
    "map_osm": "$(json_escape "$MAPS_OSM")",
    "map_google": "$(json_escape "$MAPS_GOOGLE")"
  },
  "rdap": {
    "network_name": "$(json_escape "$RDAP_NET_NAME")",
    "handle": "$(json_escape "$RDAP_HANDLE")",
    "country": "$(json_escape "$RDAP_COUNTRY")",
    "range_or_cidr": "$(json_escape "$RDAP_CIDR")"
  }
}
EOF
      ;;
    csv)
      printf 'input,ip,scope,ptr,asn_org,city,region,country,timezone,lat,lon,anycast,rdap_net,rdap_cidr\n'
      printf '%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n' \
        "$(csv_escape "$INPUT_RAW")" "$(csv_escape "$RESOLVED_IP")" "$(csv_escape "$IP_SCOPE")" \
        "$(csv_escape "$PTR_RECORD")" "$(csv_escape "$ASN_ORG")" "$(csv_escape "$CITY")" \
        "$(csv_escape "$REGION")" "$(csv_escape "$COUNTRY")" "$(csv_escape "$TIMEZONE")" \
        "$(csv_escape "$LAT")" "$(csv_escape "$LON")" "$(csv_escape "$ANYCAST")" \
        "$(csv_escape "$RDAP_NET_NAME")" "$(csv_escape "$RDAP_CIDR")"
      ;;
    table)
      if [[ "$QUIET" -eq 0 ]]; then
        printf '%s=====================================================================%s\n' "$CYAN" "$RESET"
        printf ' %s%s v%s%s | Target: %s -> %s | %s\n' "$BOLD" "$SCRIPT_NAME" "$SCRIPT_VERSION" "$RESET" "$INPUT_RAW" "$RESOLVED_IP" "$TIMESTAMP_UTC"
        printf '%s=====================================================================%s\n' "$CYAN" "$RESET"
      fi
      printf '  IP / Scope   : %s (%s)\n' "$RESOLVED_IP" "$IP_SCOPE"
      printf '  Reverse PTR  : %s\n' "${PTR_RECORD:-none}"
      if [[ "$IP_SCOPE" == "private" ]]; then
        printf '  %s Private/RFC1918/reserved IP — external Geo/RDAP lookup skipped.\n' "$ATT"
        return 0
      fi
      printf '  ASN / Org    : %s\n' "${ASN_ORG:-unknown}"
      printf '  Anycast      : %s\n' "${ANYCAST:-false}"
      printf '  Location     : %s, %s, %s (postal: %s | tz: %s)\n' "${CITY:-?}" "${REGION:-?}" "${COUNTRY:-?}" "${POSTAL:-n/a}" "${TIMEZONE:-n/a}"
      printf '  Coords (aprox): %s, %s (source: %s)\n' "${LAT:-?}" "${LON:-?}" "${GEO_SOURCE:-none}"
      [[ -n "$MAPS_OSM" ]]    && printf '  OpenStreetMap: %s\n' "$MAPS_OSM"
      [[ -n "$MAPS_GOOGLE" ]] && printf '  Google Maps  : %s\n' "$MAPS_GOOGLE"
      if [[ -n "$RDAP_NET_NAME" || -n "$RDAP_CIDR" ]]; then
        printf '  RDAP Block   : %s (%s) | Handle: %s | Country: %s\n' "${RDAP_NET_NAME:-?}" "${RDAP_CIDR:-?}" "${RDAP_HANDLE:-?}" "${RDAP_COUNTRY:-?}"
      fi
      if [[ "$QUIET" -eq 0 ]]; then
        printf '\n%s Note: IP coordinates are approximate (ISP/datacenter/city level), never street-level GPS.\n' "$ATT"
      fi
      ;;
  esac
}

main() {
  need_cmd curl awk sed grep
  command -v jq >/dev/null 2>&1 && HAVE_JQ=1
  command -v python3 >/dev/null 2>&1 && HAVE_PY3=1

  [[ "$#" -eq 0 ]] && { show_help; exit 1; }

  while [[ "$#" -gt 0 ]]; do
    case "$1" in
      -h|--help)        show_help; exit 0 ;;
      -V|--version)     printf '%s %s\n' "$SCRIPT_NAME" "$SCRIPT_VERSION"; exit 0 ;;
      -i|-m|--my-ip)    MY_IP=1; shift ;;
      --no-rdap)        SKIP_RDAP=1; shift ;;
      -q|--quiet)       QUIET=1; shift ;;
      --no-color)       NO_COLOR=1; shift ;;
      -o|--output)      FORMAT="${2:-table}"; shift 2 ;;
      --output=*)       FORMAT="${1#*=}"; shift ;;
      --*)              printf '[ERR] Unknown option: %s (use -h for help)\n' "$1" >&2; exit 1 ;;
      *)                TARGET="$1"; shift ;;
    esac
  done

  case "$FORMAT" in
    table|json|csv) ;;
    *) printf '[ERR] Invalid output format: %s (expected table, json, or csv)\n' "$FORMAT" >&2; exit 1 ;;
  esac

  init_colors

  if [[ "$MY_IP" -eq 0 && -z "$TARGET" ]]; then
    printf '%s Please specify an IP/domain or --my-ip.\n' "$FAIL" >&2
    exit 1
  fi

  resolve_target
  query_ptr

  if is_private_ip "$RESOLVED_IP"; then
    IP_SCOPE="private"
  else
    query_geo
    query_rdap_ip
  fi

  render_output
}

main "$@"
