<#
.SYNOPSIS
    checkip.ps1 — IP Intelligence, ASN, RDAP, PTR & Approximate Geo CLI (PowerShell)

.DESCRIPTION
    Audits one or more IPv4/IPv6 addresses (or the host's public IP via -MyIp),
    gathering Reverse DNS (PTR), official RDAP network ownership, ASN/ISP, and
    approximate geolocation, with RFC1918/private IP guard and table/json/csv outputs.

    Author  : Percio Castelo (Percio Andrade) <percio@perciocastelo.com.br>
    Website : https://perciocastelo.com.br
    Project : https://perciocastelo.com.br/projetos/en/checkip.html
    Repo    : https://github.com/sr00t3d/checkip
    License : Apache-2.0
    Version : 2.1.0

.EXAMPLE
    .\checkip.ps1 1.1.1.1
    .\checkip.ps1 1.1.1.1 8.8.8.8 -Output csv
    .\checkip.ps1 -MyIp -Output json
#>

[CmdletBinding()]
param(
    [Parameter(Position = 0, ValueFromRemainingArguments = $true)]
    [string[]]$Targets,

    [Alias('f')]
    [string]$File,

    [Alias('m')]
    [switch]$MyIp,

    [switch]$NoGeo,
    [switch]$NoRdap,

    [Alias('o')]
    [ValidateSet('table', 'json', 'csv')]
    [string]$Output = 'table',

    [int]$Timeout = 8,

    [Alias('q')]
    [switch]$Quiet,

    [switch]$NoColor,

    [Alias('V')]
    [switch]$Version,

    [Alias('h')]
    [switch]$Help
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ScriptName = 'checkip.ps1'
$ScriptVersion = '2.1.0'
$TimestampUtc = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
$HasResolveDnsName = [bool](Get-Command -Name Resolve-DnsName -ErrorAction SilentlyContinue)

function Show-Help {
@"
$ScriptName v$ScriptVersion — IP Intelligence, ASN, RDAP, PTR & Geo CLI (PowerShell)

Usage:
  .\checkip.ps1 <ip-or-host> [ip2 ...] [options]
  .\checkip.ps1 -MyIp [options]
  .\checkip.ps1 -File <ips.txt> [options]

Options:
  -MyIp, -m                  Inspect current host's public egress IP
  -File, -f <path>           Read IPs/hostnames from a file (one per line)
  -NoGeo                     Skip approximate geolocation lookup
  -NoRdap                    Skip official RDAP lookup
  -Output, -o <fmt>          Output format: table (default), json, csv
  -Timeout <sec>             HTTP timeout in seconds (default: 8)
  -Quiet, -q                 Suppress banner header
  -NoColor                   Disable colored output
  -Version, -V               Show version and exit
  -Help, -h                  Show this help and exit
"@ | Write-Output
}

function Write-ColorLine {
    param([string]$Text, [ConsoleColor]$Color = [ConsoleColor]::Gray)
    if ($NoColor -or $env:NO_COLOR -or $Output -ne 'table') {
        Write-Output $Text
    } else {
        Write-Host $Text -ForegroundColor $Color
    }
}

function Test-PrivateIP {
    param([string]$Ip)
    if ($Ip -match '^(10\.|127\.|169\.254\.|192\.168\.|0\.|100\.(6[4-9]|[7-9][0-9]|1[0-1][0-9]|12[0-7])\.|172\.(1[6-9]|2[0-9]|3[0-1])\.)') {
        return $true
    }
    if ($Ip -match '^(::1|fe80:|fc|fd)') { return $true }
    return $false
}

function Resolve-TargetToIP {
    param([string]$InputVal)
    $parsed = $null
    if ([System.Net.IPAddress]::TryParse($InputVal, [ref]$parsed)) {
        return $parsed.IPAddressToString
    }
    try {
        $addrs = [System.Net.Dns]::GetHostAddresses($InputVal)
        foreach ($a in $addrs) {
            if ($a.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork) {
                return $a.IPAddressToString
            }
        }
        if ($addrs.Count -gt 0) { return $addrs[0].IPAddressToString }
    } catch { }
    return ''
}

function Get-PtrRecord {
    param([string]$Ip)
    if ($HasResolveDnsName) {
        try {
            $r = Resolve-DnsName -Name $Ip -Type PTR -ErrorAction Stop | Select-Object -First 1
            if ($r.PSObject.Properties['NameHost'] -and $r.NameHost) { return $r.NameHost.TrimEnd('.') }
        } catch { }
    }
    try {
        $entry = [System.Net.Dns]::GetHostEntry($Ip)
        if ($entry.HostName -and $entry.HostName -ne $Ip) { return $entry.HostName.TrimEnd('.') }
    } catch { }
    return ''
}

function Get-Prop {
    param($Obj, [string]$Name)
    if ($null -eq $Obj) { return '' }
    if ($Obj.PSObject.Properties[$Name] -and $null -ne $Obj.$Name) { return [string]$Obj.$Name }
    return ''
}

function Get-PublicIP {
    foreach ($ep in @('https://api.ipify.org', 'https://ifconfig.me')) {
        try {
            $r = (Invoke-RestMethod -Uri $ep -TimeoutSec $Timeout -ErrorAction Stop).ToString().Trim()
            $p = $null
            if ([System.Net.IPAddress]::TryParse($r, [ref]$p)) { return $r }
        } catch { }
    }
    throw 'Could not determine public IP.'
}

if ($Help) { Show-Help; exit 0 }
if ($Version) { Write-Output "$ScriptName $ScriptVersion"; exit 0 }

$Inputs = New-Object System.Collections.Generic.List[string]
if ($MyIp) { $Inputs.Add((Get-PublicIP)) }
if ($Targets) {
    foreach ($t in $Targets) {
        if (-not [string]::IsNullOrWhiteSpace($t)) { $Inputs.Add($t.Trim()) }
    }
}
if ($File) {
    if (-not (Test-Path -LiteralPath $File)) { Write-Error "[ERR] File not found: $File"; exit 1 }
    foreach ($raw in (Get-Content -LiteralPath $File -Encoding UTF8)) {
        $line = ($raw -replace '#.*$', '').Trim()
        if ($line) { $Inputs.Add($line) }
    }
}

if ($Inputs.Count -eq 0) { Show-Help; exit 1 }

$Headers = @{ 'User-Agent' = "checkip/$ScriptVersion (+https://github.com/sr00t3d/checkip)" }
$Results = New-Object System.Collections.Generic.List[object]

foreach ($rawTarget in $Inputs) {
    $ip = Resolve-TargetToIP $rawTarget
    if (-not $ip) {
        Write-Warning "Could not resolve: $rawTarget"
        continue
    }
    $isPriv = Test-PrivateIP $ip
    $ptr = Get-PtrRecord $ip
    $rdapName = ''; $rdapRange = ''; $rdapCountry = ''
    $asn = ''; $org = ''; $city = ''; $region = ''; $country = ''; $tz = ''

    if (-not $isPriv) {
        if (-not $NoRdap) {
            try {
                $rd = Invoke-RestMethod -Uri "https://rdap.org/ip/$ip" -Headers $Headers -TimeoutSec $Timeout -ErrorAction Stop
                $rdapName = Get-Prop $rd 'name'
                $rdapCountry = Get-Prop $rd 'country'
                $start = Get-Prop $rd 'startAddress'
                $end = Get-Prop $rd 'endAddress'
                if ($start -and $end) { $rdapRange = "$start - $end" }
                elseif ($rd.PSObject.Properties['cidr0_cidrs'] -and $rd.cidr0_cidrs) {
                    $c0 = $rd.cidr0_cidrs[0]
                    $v4p = Get-Prop $c0 'v4prefix'
                    $len = Get-Prop $c0 'length'
                    if ($v4p -and $len) { $rdapRange = "$v4p/$len" }
                }
            } catch { }
        }
        if (-not $NoGeo) {
            try {
                $g = Invoke-RestMethod -Uri "https://ipinfo.io/$ip/json" -Headers $Headers -TimeoutSec $Timeout -ErrorAction Stop
                $orgFull = Get-Prop $g 'org'
                if ($orgFull -match '^(AS\d+)\s+(.*)$') {
                    $asn = $Matches[1]; $org = $Matches[2]
                } else {
                    $org = $orgFull
                }
                $city = Get-Prop $g 'city'
                $region = Get-Prop $g 'region'
                $country = Get-Prop $g 'country'
                $tz = Get-Prop $g 'timezone'
            } catch { }
        }
    }

    $Results.Add([PSCustomObject]@{
        target       = $rawTarget
        ip           = $ip
        scope        = if ($isPriv) { 'private' } else { 'public' }
        ptr          = $ptr
        asn          = $asn
        org          = $org
        rdap_name    = $rdapName
        rdap_range   = $rdapRange
        rdap_country = $rdapCountry
        city         = $city
        region       = $region
        country      = $country
        timezone     = $tz
    })
}

switch ($Output) {
    'json' {
        [PSCustomObject]@{
            tool      = $ScriptName
            version   = $ScriptVersion
            timestamp = $TimestampUtc
            total     = $Results.Count
            results   = $Results
        } | ConvertTo-Json -Depth 5 | Write-Output
    }
    'csv' {
        Write-Output 'target,ip,scope,ptr,asn,org,rdap_name,rdap_range,country,region,city,timezone'
        foreach ($r in $Results) {
            $vals = @($r.target, $r.ip, $r.scope, $r.ptr, $r.asn, $r.org, $r.rdap_name, $r.rdap_range, $r.country, $r.region, $r.city, $r.timezone) |
                ForEach-Object { '"' + ([string]$_ -replace '"', '""') + '"' }
            Write-Output ($vals -join ',')
        }
    }
    default {
        if (-not $Quiet) {
            Write-ColorLine ('=' * 74) ([ConsoleColor]::Cyan)
            Write-Output (" {0} v{1} | IP Intelligence & RDAP Audit | {2}" -f $ScriptName, $ScriptVersion, $TimestampUtc)
            Write-ColorLine ('=' * 74) ([ConsoleColor]::Cyan)
            Write-Output ''
        }
        foreach ($r in $Results) {
            $tag = if ($r.scope -eq 'private') { '[PRIV]' } else { '[OK]  ' }
            $col = if ($r.scope -eq 'private') { [ConsoleColor]::Yellow } else { [ConsoleColor]::Green }
            Write-ColorLine ("{0} {1,-11} : {2} (target: {3})" -f $tag, 'IP', $r.ip, $r.target) $col
            if ($r.ptr)        { Write-Output ("       {0,-11} : {1}" -f 'PTR', $r.ptr) }
            if ($r.asn -or $r.org) { Write-Output ("       {0,-11} : {1} {2}" -f 'ASN / Org', $r.asn, $r.org) }
            if ($r.rdap_name -or $r.rdap_range) {
                Write-Output ("       {0,-11} : {1} ({2})" -f 'RDAP Net', $r.rdap_name, $r.rdap_range)
            }
            if ($r.city -or $r.country) {
                $loc = (@($r.city, $r.region, $r.country) | Where-Object { $_ }) -join ', '
                Write-Output ("       {0,-11} : {1}" -f 'Approx Geo', $loc)
            }
            if ($r.timezone)   { Write-Output ("       {0,-11} : {1}" -f 'Timezone', $r.timezone) }
            Write-Output ''
        }
    }
}
exit 0
