#!/usr/bin/env python3

import requests
import json
import sys

def get_public_ip():
    """
    Fetch the public IP address of the machine.
    We use a simple service that returns just the IP.
    """
    services = [
        "https://api.ipify.org",        # Returns plain text IP
        "https://ifconfig.me/ip",       # Fallback service
        "https://icanhazip.com",        # Another fallback
    ]

    for service in services:
        try:
            response = requests.get(service, timeout=5)
            response.raise_for_status()
            return response.text.strip()
        except requests.RequestException as e:
            print(f"[!] Failed to reach {service}: {e}")
            continue

    return None


def geolocate_ip(ip: str):
    """
    Use ip-api.com (free, no API key needed) to geolocate an IP.
    Documentation: http://ip-api.com/docs/api:json
    """
    url = f"http://ip-api.com/json/{ip}"

    # Fields we want to retrieve
    params = {
        "fields": "status,message,country,regionName,city,zip,lat,lon,isp,org,as,query"
    }

    try:
        response = requests.get(url, params=params, timeout=5)
        response.raise_for_status()
        return response.json()
    except requests.RequestException as e:
        print(f"[!] Geolocation request failed: {e}")
        return None


def display_results(data: dict):
    """
    Pretty print the geolocation results.
    """
    if data.get("status") != "success":
        print(f"[!] API Error: {data.get('message', 'Unknown error')}")
        return

    print("\n" + "="*45)
    print("       PUBLIC IP GEOLOCATION RESULTS")
    print("="*45)
    print(f"  IP Address   : {data.get('query')}")
    print(f"  Country      : {data.get('country')}")
    print(f"  Region       : {data.get('regionName')}")
    print(f"  City         : {data.get('city')}")
    print(f"  ZIP Code     : {data.get('zip')}")
    print(f"  Latitude     : {data.get('lat')}")
    print(f"  Longitude    : {data.get('lon')}")
    print(f"  ISP          : {data.get('isp')}")
    print(f"  Organization : {data.get('org')}")
    print(f"  AS Number    : {data.get('as')}")
    print("="*45)
    print(f"\n  Google Maps  : https://www.google.com/maps?q={data.get('lat')},{data.get('lon')}")
    print()


def main():
    # Allow passing a custom IP as argument for testing
    if len(sys.argv) > 1:
        ip = sys.argv[1]
        print(f"[*] Using provided IP: {ip}")
    else:
        print("[*] Fetching your public IP address...")
        ip = get_public_ip()

        if not ip:
            print("[!] Could not retrieve public IP. Check your connection.")
            sys.exit(1)

        print(f"[+] Public IP found: {ip}")

    print(f"[*] Geolocating {ip}...")
    geo_data = geolocate_ip(ip)

    if geo_data:
        display_results(geo_data)
    else:
        print("[!] Could not geolocate the IP.")
        sys.exit(1)


if __name__ == "__main__":
    main()

