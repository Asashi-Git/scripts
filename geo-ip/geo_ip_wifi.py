#!/usr/bin/env python3

"""
geo_ip_wifi.py — Enhanced IP + WiFi geolocation tool

Positioning API priority:
  1. mylnikov.org  — open MIT API, no key required
  2. Unwired Labs  — free tier 100 req/day, key required (no billing)
  3. Google        — best accuracy, key + billing required
  4. WiGLE         — last resort, crowdsourced, often inaccurate

Sanity check:
  WiFi result is validated against IP geolocation.
  If distance > 500km → result rejected as garbage.
"""

import requests
import sys
import subprocess
import json
import re
import os
import math
import argparse
from pathlib import Path
from dataclasses import dataclass
from typing import Optional


# ─────────────────────────────────────────────────────────────────────────────
#  CONFIGURATION
# ─────────────────────────────────────────────────────────────────────────────

CONFIG_PATH = Path.home() / ".config" / "geo_ip" / "config.json"

DEFAULT_CONFIG = {
    "google_api_key":       "",
    "wigle_api_name":       "",
    "wigle_api_token":      "",
    "unwiredlabs_api_key":  "",
}


def load_config() -> dict:
    if not CONFIG_PATH.exists():
        return DEFAULT_CONFIG.copy()
    try:
        with open(CONFIG_PATH) as f:
            return {**DEFAULT_CONFIG, **json.load(f)}
    except (json.JSONDecodeError, IOError):
        return DEFAULT_CONFIG.copy()


def save_config(config: dict):
    CONFIG_PATH.parent.mkdir(parents=True, exist_ok=True)
    with open(CONFIG_PATH, "w") as f:
        json.dump(config, f, indent=2)
    os.chmod(CONFIG_PATH, 0o600)
    print(f"  [+] Config saved to {CONFIG_PATH}")


def setup_wizard():
    print("\n" + "="*58)
    print("           API CONFIGURATION SETUP")
    print("="*58)
    print("""
  [1] mylnikov.org  → FREE, no key, open MIT license  ✓ auto
  [2] Unwired Labs  → free tier, create account:
                      https://unwiredlabs.com/api#documentation
  [3] Google        → best accuracy, needs billing info:
                      https://console.cloud.google.com/
  [4] WiGLE         → crowdsourced fallback:
                      https://wigle.net/account
    """)

    config = load_config()

    print("─" * 40)
    val = input(f"  Unwired Labs API key [{config['unwiredlabs_api_key'] or 'not set'}]: ").strip()
    if val: config["unwiredlabs_api_key"] = val

    val = input(f"  Google API key       [{config['google_api_key'] or 'not set'}]: ").strip()
    if val: config["google_api_key"] = val

    print("\n  WiGLE credentials (Account → Show API Token):")
    val = input(f"  WiGLE API Name  [{config['wigle_api_name'] or 'not set'}]: ").strip()
    if val: config["wigle_api_name"] = val

    val = input(f"  WiGLE API Token [{config['wigle_api_token'] or 'not set'}]: ").strip()
    if val: config["wigle_api_token"] = val

    save_config(config)
    print(f"\n[+] Setup complete! Run with --wifi to test.\n")
    sys.exit(0)


# ─────────────────────────────────────────────────────────────────────────────
#  DATA STRUCTURES
# ─────────────────────────────────────────────────────────────────────────────

@dataclass
class AccessPoint:
    bssid:    str
    ssid:     str  = ""
    rssi:     int  = -100
    channel:  int  = 0
    mac_type: str  = "unknown"
    vendor:   str  = ""


@dataclass
class GeoLocation:
    latitude:  float
    longitude: float
    accuracy:  Optional[float] = None
    source:    str = "unknown"


# ─────────────────────────────────────────────────────────────────────────────
#  SANITY CHECK — Haversine distance
# ─────────────────────────────────────────────────────────────────────────────

def haversine_km(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    """
    Calculate great-circle distance between two GPS points.
    Used to validate that WiFi result isn't garbage (e.g., New York when in Paris).

    Formula:
      a = sin²(Δlat/2) + cos(lat1) × cos(lat2) × sin²(Δlon/2)
      c = 2 × atan2(√a, √(1−a))
      d = R × c   where R = 6371 km
    """
    R    = 6371
    dlat = math.radians(lat2 - lat1)
    dlon = math.radians(lon2 - lon1)
    a    = (math.sin(dlat/2)**2 +
            math.cos(math.radians(lat1)) *
            math.cos(math.radians(lat2)) *
            math.sin(dlon/2)**2)
    return R * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))


def sanity_check(
    wifi_loc: GeoLocation,
    ip_data:  Optional[dict],
    max_km:   float = 500.0
) -> bool:
    """
    Reject WiFi positioning result if it's more than max_km
    away from IP geolocation. IP geo is ~50km accurate at worst,
    so 500km threshold catches obvious garbage (e.g., New York vs Paris = 5800km).
    """
    if not ip_data or ip_data.get("status") != "success":
        return True  # Can't verify, trust the result

    ip_lat = ip_data.get("lat")
    ip_lon = ip_data.get("lon")

    if ip_lat is None or ip_lon is None:
        return True

    distance = haversine_km(ip_lat, ip_lon, wifi_loc.latitude, wifi_loc.longitude)

    if distance > max_km:
        print(f"  [!] SANITY CHECK FAILED: WiFi result is {distance:.0f}km from IP location")
        print(f"      IP  location : {ip_lat:.4f}, {ip_lon:.4f} ({ip_data.get('city')})")
        print(f"      WiFi location: {wifi_loc.latitude:.4f}, {wifi_loc.longitude:.4f}")
        print(f"      This is likely garbage data from {wifi_loc.source}")
        return False

    print(f"  [+] Sanity check passed: WiFi result is {distance:.1f}km from IP location")
    return True


# ─────────────────────────────────────────────────────────────────────────────
#  MAC ANALYSIS
# ─────────────────────────────────────────────────────────────────────────────

def is_real_mac(bssid: str) -> bool:
    """Bit1 of first byte = 0 means universally administered (real hardware MAC)."""
    try:
        return not bool(int(bssid.split(":")[0], 16) & 0x02)
    except (ValueError, IndexError):
        return False


def filter_usable_aps(aps: list) -> tuple:
    usable, randomized = [], []
    for ap in aps:
        if is_real_mac(ap.bssid):
            ap.mac_type = "real"
            usable.append(ap)
        else:
            ap.mac_type = "randomized"
            randomized.append(ap)
    return usable, randomized


# ─────────────────────────────────────────────────────────────────────────────
#  PUBLIC IP
# ─────────────────────────────────────────────────────────────────────────────

def get_public_ip() -> Optional[str]:
    for url in ["https://api.ipify.org", "https://ifconfig.me/ip", "https://icanhazip.com"]:
        try:
            r = requests.get(url, timeout=5)
            r.raise_for_status()
            return r.text.strip()
        except requests.RequestException:
            continue
    return None


def geolocate_ip(ip: str) -> Optional[dict]:
    try:
        r = requests.get(
            f"http://ip-api.com/json/{ip}",
            params={"fields": "status,message,country,regionName,city,zip,lat,lon,isp,org,as,query"},
            timeout=5
        )
        r.raise_for_status()
        return r.json()
    except requests.RequestException as e:
        print(f"  [!] IP geolocation failed: {e}")
        return None


# ─────────────────────────────────────────────────────────────────────────────
#  WIFI SCANNING
# ─────────────────────────────────────────────────────────────────────────────

def detect_interfaces() -> list:
    try:
        result = subprocess.run(["iw", "dev"], capture_output=True, text=True, timeout=5)
        ifaces = re.findall(r"Interface\s+(\w+)", result.stdout)
        if ifaces:
            return ifaces
    except FileNotFoundError:
        pass
    # Fallback: /sys/class/net
    return [i for i in os.listdir("/sys/class/net")
            if i.startswith(("wlan", "wlp", "wlx", "ath"))]


def scan_iw(interface: str) -> list:
    aps = []
    try:
        r = subprocess.run(
            ["iw", "dev", interface, "scan"],
            capture_output=True, text=True, timeout=20
        )
        if r.returncode != 0:
            return []

        for block in re.split(r"(?=^BSS )", r.stdout, flags=re.MULTILINE):
            bssid_m = re.search(r"BSS\s+([0-9a-f:]{17})", block, re.IGNORECASE)
            if not bssid_m:
                continue
            sig_m  = re.search(r"signal:\s*([-\d.]+)\s*dBm", block)
            ssid_m = re.search(r"SSID:\s*(.+)", block)
            chan_m  = (re.search(r"DS Parameter set: channel\s+(\d+)", block) or
                       re.search(r"\*\s+primary channel:\s+(\d+)", block))
            aps.append(AccessPoint(
                bssid   = bssid_m.group(1).upper(),
                ssid    = ssid_m.group(1).strip() if ssid_m else "",
                rssi    = int(float(sig_m.group(1))) if sig_m else -100,
                channel = int(chan_m.group(1)) if chan_m else 0
            ))
    except (FileNotFoundError, subprocess.TimeoutExpired):
        pass
    return aps


def scan_nmcli() -> list:
    aps = []
    try:
        subprocess.run(["nmcli", "device", "wifi", "rescan"],
                       capture_output=True, timeout=8)
        r = subprocess.run(
            ["nmcli", "-t", "-f", "BSSID,SSID,CHAN,SIGNAL", "device", "wifi", "list"],
            capture_output=True, text=True, timeout=12
        )
        for line in r.stdout.strip().splitlines():
            safe  = line.replace("\\:", "§")
            parts = safe.split(":")
            if len(parts) < 4:
                continue
            bssid = parts[0].replace("§", ":").upper().strip()
            if not re.match(r"([0-9A-F]{2}:){5}[0-9A-F]{2}$", bssid):
                continue
            try:
                rssi = (int(parts[3].strip()) // 2) - 100
                chan = int(parts[2]) if parts[2].strip() else 0
            except ValueError:
                rssi, chan = -100, 0
            aps.append(AccessPoint(
                bssid=bssid, ssid=parts[1].replace("§", ":").strip(),
                rssi=rssi, channel=chan
            ))
    except (FileNotFoundError, subprocess.TimeoutExpired):
        pass
    return aps


def scan_wifi(interface: Optional[str] = None) -> list:
    """Scan all interfaces, merge and deduplicate results."""
    all_aps = []
    interfaces = [interface] if interface else detect_interfaces()

    print(f"  [*] Interfaces: {', '.join(interfaces) if interfaces else 'none found'}")

    for iface in interfaces:
        if os.geteuid() == 0:
            aps = scan_iw(iface)
            if aps:
                print(f"  [+] iw scan on {iface}: {len(aps)} APs")
                all_aps.extend(aps)

    # Always supplement with nmcli
    nmcli_aps = scan_nmcli()
    if nmcli_aps:
        print(f"  [+] nmcli cache: {len(nmcli_aps)} APs")
        all_aps.extend(nmcli_aps)

    # Deduplicate — keep strongest RSSI per BSSID
    seen = {}
    for ap in all_aps:
        if ap.bssid not in seen or ap.rssi > seen[ap.bssid].rssi:
            seen[ap.bssid] = ap

    return sorted(seen.values(), key=lambda x: x.rssi, reverse=True)


# ─────────────────────────────────────────────────────────────────────────────
#  POSITIONING APIs
# ─────────────────────────────────────────────────────────────────────────────

def locate_via_mylnikov(access_points: list) -> Optional[GeoLocation]:
    """
    mylnikov.org open WiFi geolocation API.
    MIT licensed, no key required, crowdsourced data.

    Endpoint: GET https://api.mylnikov.org/geolocation/wifi
    Params:
      v=1.1       — API version
      data=open   — required for open data access (MANDATORY)
      bssid=<MAC> — one BSSID per request

    Strategy: query each AP individually, collect found positions,
    compute RSSI-weighted centroid. Reject outliers > 50km from median.

    Docs: https://www.mylnikov.org/archives/1170
    """
    found = []

    print(f"  [*] Querying mylnikov.org for {len(access_points)} APs...")

    for ap in access_points[:10]:
        try:
            r = requests.get(
                "https://api.mylnikov.org/geolocation/wifi",
                params={"v": "1.1", "data": "open", "bssid": ap.bssid},
                timeout=8
            )
            data = r.json()

            # Response format:
            # {"result": 200, "data": {"lat": 48.85, "lon": 2.35, "range": 50}}
            # {"result": 404}  → not in database
            if data.get("result") == 200 and "data" in data:
                lat = data["data"].get("lat")
                lon = data["data"].get("lon")
                if lat and lon:
                    weight = 10 ** ((ap.rssi + 100) / 10)
                    found.append((lat, lon, weight))
                    print(f"  [+] {ap.bssid} → {lat:.4f}, {lon:.4f}")
            else:
                print(f"  [-] {ap.bssid} → not in mylnikov database")

        except requests.RequestException as e:
            print(f"  [!] mylnikov error: {e}")

    if not found:
        return None

    # Compute weighted centroid
    total_w = sum(w for _, _, w in found)
    lat = sum(la * w for la, _, w in found) / total_w
    lon = sum(lo * w for _, lo, w in found) / total_w

    return GeoLocation(
        latitude=round(lat, 6),
        longitude=round(lon, 6),
        source=f"mylnikov.org ({len(found)} APs)"
    )


def locate_via_unwiredlabs(access_points: list, api_key: str) -> Optional[GeoLocation]:
    """
    Unwired Labs Location API.
    Free tier: 100 requests/day, no billing info needed.
    Register at: https://unwiredlabs.com/api#documentation

    Sends all APs in one POST request — server-side triangulation.
    Much more accurate than our manual centroid calculation.
    """
    if not api_key:
        print("  [!] Unwired Labs key not set. Run --setup")
        return None

    payload = {
        "token": api_key,
        "wifi": [
            {"bssid": ap.bssid, "signal": ap.rssi}
            for ap in access_points[:20]
        ]
    }

    try:
        r = requests.post(
            "https://us1.unwiredlabs.com/v2/process.php",
            json=payload, timeout=10
        )
        data = r.json()

        if data.get("status") == "ok":
            return GeoLocation(
                latitude  = data["lat"],
                longitude = data["lon"],
                accuracy  = data.get("accuracy"),
                source    = "Unwired Labs"
            )
        else:
            print(f"  [!] Unwired Labs: {data.get('message', 'unknown error')}")
            return None

    except requests.RequestException as e:
        print(f"  [!] Unwired Labs error: {e}")
        return None


def locate_via_google(access_points: list, api_key: str) -> Optional[GeoLocation]:
    """Google Geolocation API — best accuracy, returns meter-level radius."""
    if not api_key:
        print("  [!] Google API key not set. Run --setup")
        return None

    payload = {
        "wifiAccessPoints": [
            {"macAddress": ap.bssid, "signalStrength": ap.rssi, "channel": ap.channel}
            for ap in access_points[:20]
        ]
    }

    try:
        r = requests.post(
            f"https://www.googleapis.com/geolocation/v1/geolocate?key={api_key}",
            json=payload, timeout=10
        )
        if r.status_code != 200:
            msg = r.json().get("error", {}).get("message", "")
            print(f"  [!] Google API HTTP {r.status_code}: {msg}")
            return None

        data = r.json()
        return GeoLocation(
            latitude  = data["location"]["lat"],
            longitude = data["location"]["lng"],
            accuracy  = data.get("accuracy"),
            source    = "Google Geolocation API"
        )
    except requests.RequestException as e:
        print(f"  [!] Google API error: {e}")
        return None


def locate_via_wigle(access_points: list, api_name: str, api_token: str) -> Optional[GeoLocation]:
    """WiGLE — last resort, crowdsourced, often inaccurate."""
    if not api_name or not api_token:
        return None

    found = []
    for ap in access_points[:5]:
        try:
            r = requests.get(
                "https://api.wigle.net/api/v2/network/search",
                params={"netid": ap.bssid, "resultsPerPage": 1},
                auth=(api_name, api_token), timeout=10
            )
            if r.status_code != 200:
                continue
            results = r.json().get("results", [])
            if results and results[0].get("trilat"):
                w = 10 ** ((ap.rssi + 100) / 10)
                found.append((results[0]["trilat"], results[0]["trilong"], w))
                print(f"  [+] WiGLE: {ap.bssid} → found")
            else:
                print(f"  [-] WiGLE: {ap.bssid} → not found")
        except requests.RequestException:
            pass

    if not found:
        return None

    total_w = sum(w for _, _, w in found)
    return GeoLocation(
        latitude  = round(sum(la * w for la, _, w in found) / total_w, 6),
        longitude = round(sum(lo * w for _, lo, w in found) / total_w, 6),
        source    = f"WiGLE ({len(found)} APs)"
    )


def wifi_positioning(
    access_points: list,
    config: dict,
    ip_data: Optional[dict] = None
) -> Optional[GeoLocation]:
    """
    Try each positioning API in priority order.
    Validate each result with sanity check before returning.
    """
    apis = [
        ("mylnikov.org (no key)",
         lambda: locate_via_mylnikov(access_points)),

        ("Unwired Labs",
         lambda: locate_via_unwiredlabs(
             access_points, config.get("unwiredlabs_api_key", ""))),

        ("Google Geolocation",
         lambda: locate_via_google(
             access_points, config.get("google_api_key", ""))),

        ("WiGLE (last resort)",
         lambda: locate_via_wigle(
             access_points,
             config.get("wigle_api_name", ""),
             config.get("wigle_api_token", ""))),
    ]

    for name, fn in apis:
        print(f"\n  ── Trying {name}...")
        loc = fn()
        if loc:
            if sanity_check(loc, ip_data):
                return loc
            else:
                print(f"  [!] {name} result rejected by sanity check")
        else:
            print(f"  [-] {name}: no result")

    return None


# ─────────────────────────────────────────────────────────────────────────────
#  DISPLAY
# ─────────────────────────────────────────────────────────────────────────────

def display_ip_results(data: dict):
    if data.get("status") != "success":
        print(f"  [!] {data.get('message', 'API error')}")
        return
    print("\n" + "="*52)
    print("         IP GEOLOCATION RESULTS")
    print("="*52)
    print(f"  IP           : {data.get('query')}")
    print(f"  Location     : {data.get('city')}, {data.get('regionName')}, {data.get('country')}")
    print(f"  ZIP          : {data.get('zip')}")
    print(f"  Coordinates  : {data.get('lat')}, {data.get('lon')}")
    print(f"  ISP          : {data.get('isp')}")
    print(f"  AS           : {data.get('as')}")
    print(f"  Accuracy     : ~5-500km")
    print("="*52)
    print(f"  Maps: https://www.google.com/maps?q={data.get('lat')},{data.get('lon')}")


def display_scan_results(usable: list, randomized: list):
    total = len(usable) + len(randomized)
    print(f"\n{'='*60}")
    print(f"  WIFI SCAN — {total} APs found ({len(usable)} usable, {len(randomized)} randomized)")
    print(f"{'='*60}")

    if usable:
        print(f"\n  ✓ Real MACs (usable for positioning):")
        print(f"  {'BSSID':<20} {'RSSI':>6}  {'CH':>3}  SSID")
        print(f"  {'-'*18:<20} {'-'*5:>6}  {'-'*3:>3}  ----")
        for ap in usable:
            print(f"  {ap.bssid:<20} {ap.rssi:>5}dBm {ap.channel:>4}  {ap.ssid}")

    if randomized:
        print(f"\n  ✗ Randomized MACs (unusable):")
        for ap in randomized:
            byte0 = format(int(ap.bssid.split(":")[0], 16), "08b")
            print(f"  {ap.bssid}  {ap.rssi:>5}dBm  {ap.ssid}  [byte0={byte0}, bit1=1]")

    print(f"{'='*60}")


def display_wifi_location(loc: GeoLocation, ip_data: Optional[dict]):
    print(f"\n{'='*52}")
    print(f"  WIFI POSITIONING RESULT")
    print(f"{'='*52}")
    print(f"  Source       : {loc.source}")
    print(f"  Coordinates  : {loc.latitude}, {loc.longitude}")
    if loc.accuracy:
        print(f"  Accuracy     : ±{loc.accuracy:.0f} meters")
    print(f"{'='*52}")
    print(f"  Maps: https://www.google.com/maps?q={loc.latitude},{loc.longitude}")

    if ip_data and ip_data.get("status") == "success":
        dist = haversine_km(
            ip_data["lat"], ip_data["lon"],
            loc.latitude, loc.longitude
        )
        acc_str = f"±{loc.accuracy:.0f}m" if loc.accuracy else "unknown"
        print(f"\n  vs IP geolocation: {dist:.1f}km apart")
        print(f"  IP  → {ip_data.get('city')} (~50km radius)")
        print(f"  WiFi→ {acc_str} radius")


# ─────────────────────────────────────────────────────────────────────────────
#  MAIN
# ─────────────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(description="Enhanced IP + WiFi geolocation")
    parser.add_argument("ip",          nargs="?",       help="Target IP")
    parser.add_argument("--wifi",      action="store_true")
    parser.add_argument("--wifi-only", action="store_true")
    parser.add_argument("--scan-only", action="store_true")
    parser.add_argument("--interface", "-i",            help="Force interface")
    parser.add_argument("--setup",     action="store_true")
    args = parser.parse_args()

    if args.setup:
        setup_wizard()
        return

    config   = load_config()
    geo_data = None

    print("\n[*] Enhanced Geo-IP Tool")
    print("=" * 52)

    # IP Geolocation
    if not args.wifi_only and not args.scan_only:
        ip = args.ip
        if not ip:
            print("[*] Fetching public IP...")
            ip = get_public_ip()
        if not ip:
            print("[!] Could not get public IP.")
            sys.exit(1)
        print(f"[*] Geolocating {ip}...")
        geo_data = geolocate_ip(ip)
        if geo_data:
            display_ip_results(geo_data)

    # WiFi
    if args.wifi or args.wifi_only or args.scan_only:
        print("\n[*] Scanning WiFi...")
        if os.geteuid() != 0:
            print("  [!] Not root — active scan unavailable, using nmcli cache only")

        all_aps = scan_wifi(interface=args.interface)

        if not all_aps:
            print("[!] No APs found.")
            sys.exit(1)

        usable, randomized = filter_usable_aps(all_aps)
        display_scan_results(usable, randomized)

        if args.scan_only:
            return

        if not usable:
            print("\n[!] No real-MAC APs found.")
            print("    If you're only seeing your own Freebox randomized MAC,")
            print("    try from a location with more visible networks.")
            sys.exit(1)

        print(f"\n[*] Attempting WiFi positioning with {len(usable)} AP(s)...")
        loc = wifi_positioning(usable, config, ip_data=geo_data)

        if loc:
            display_wifi_location(loc, geo_data)
        else:
            print("\n[!] All positioning APIs failed or returned garbage.")
            print("    This usually means your APs are not in any database.")
            print(f"\n    Check manually on WiGLE:")
            for ap in usable[:3]:
                print(f"      https://wigle.net/search#fullSearch?netid={ap.bssid}")

    print()


if __name__ == "__main__":
    main()

