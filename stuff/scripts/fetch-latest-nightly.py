import urllib.request
import urllib.parse
import re
import datetime
import json
import subprocess
import sys

BASE_URL = "https://ftp.mozilla.org/pub/fenix/nightly"


def fetch_index(year, month):
    url = f"{BASE_URL}/{year}/{month:02d}/"
    try:
        with urllib.request.urlopen(url) as res:
            return url, res.read().decode("utf-8")
    except Exception:
        return url, ""


def main():
    now = datetime.datetime.now()
    # Check current month first, then drop back to last month if needed
    periods = [now, now - datetime.timedelta(days=28)]

    latest_dir = None
    month_url = ""

    for dt in periods:
        url, html = fetch_index(dt.year, dt.month)
        dirs = re.findall(r'href="([^"]+-android-x86_64/)"', html)
        if dirs:
            dirs.sort()
            latest_dir = dirs[-1]
            month_url = url
            break

    if not latest_dir:
        print(
            "Error: Could not locate any x86_64 nightly directories.",
            file=sys.stderr,
        )
        sys.exit(1)

    # urljoin handles root-relative paths like /pub/... automatically
    dir_url = urllib.parse.urljoin(month_url, latest_dir)
    print(f"Target Directory: {dir_url}", file=sys.stderr)

    # Fetch directory to find the exact APK filename
    with urllib.request.urlopen(dir_url) as res:
        dir_html = res.read().decode("utf-8")

    apk_matches = re.findall(r'href="([^"]+\.apk)"', dir_html)
    if not apk_matches:
        print(f"Error: No APK found inside {dir_url}", file=sys.stderr)
        sys.exit(1)

    # Safely merge file name or full path into the folder base URL
    apk_url = urllib.parse.urljoin(dir_url, apk_matches[0])
    print(f"Found APK: {apk_url}", file=sys.stderr)

    # Calculate store hash natively via Nix
    res = subprocess.run(
        ["nix", "store", "prefetch-file", "--json", apk_url],
        capture_output=True,
        text=True,
        check=True,
    )
    sri_hash = json.loads(res.stdout)["hash"]

    # Output to the JSON target
    output_data = {"url": apk_url, "hash": sri_hash}
    with open("firefox-nightly.json", "w") as f:
        json.dump(output_data, f, indent=2)

    print("Successfully generated firefox-nightly.json", file=sys.stderr)


if __name__ == "__main__":
    main()
