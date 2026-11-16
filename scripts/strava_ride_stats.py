#!/usr/bin/env python3
"""Print spreadsheet-ready ride stats for a list of Strava activity URLs.

Usage:
    pbpaste | ./strava_ride_stats.py | pbcopy
    ./strava_ride_stats.py https://www.strava.com/activities/18204298188 ...

Output is one tab-separated row per input line, in the same order:
    54mi	+1,954 ft / -1,939 ft	2:45:32

Auth: set STRAVA_CLIENT_ID and STRAVA_CLIENT_SECRET (environment, or a .env file
next to this script). On the first run it opens Strava's authorization page to grant
activity:read_all, then saves the resulting refresh token to .env as
STRAVA_READ_ALL_REFRESH_TOKEN. Your Strava app's "Authorization Callback Domain"
must be `localhost`.
"""

import csv
import http.server
import io
import json
import os
import re
import sys
import urllib.error
import urllib.parse
import urllib.request
import webbrowser
from pathlib import Path

API = "https://www.strava.com/api/v3"
METERS_PER_MILE = 1609.344
FEET_PER_METER = 3.28084
REFRESH_VAR = "STRAVA_READ_ALL_REFRESH_TOKEN"


def load_dotenv():
    path = Path(__file__).resolve().parent / ".env"
    if not path.exists():
        return
    for line in path.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        key = key.removeprefix("export ").strip()
        os.environ.setdefault(key, value.strip().strip("'\""))


def save_to_dotenv(key, value):
    path = Path(__file__).resolve().parent / ".env"
    lines = path.read_text().splitlines() if path.exists() else []
    lines = [l for l in lines if l.removeprefix("export ").split("=", 1)[0].strip() != key]
    lines.append(f"{key}={value}")
    path.write_text("\n".join(lines) + "\n")
    os.environ[key] = value


def token_request(client_id, client_secret, **params):
    body = urllib.parse.urlencode({"client_id": client_id, "client_secret": client_secret, **params}).encode()
    with urllib.request.urlopen(f"{API}/oauth/token", data=body) as resp:
        return json.load(resp)


def authorize(client_id, client_secret):
    port = 8765
    received = {}

    class Handler(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            received.update(urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query))
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b"Done - you can close this tab.")

        def log_message(self, *args):
            pass

    params = urllib.parse.urlencode({
        "client_id": client_id,
        "redirect_uri": f"http://localhost:{port}",
        "response_type": "code",
        "approval_prompt": "force",
        "scope": "read,activity:read_all",
    })
    url = f"https://www.strava.com/oauth/authorize?{params}"
    with http.server.HTTPServer(("localhost", port), Handler) as server:
        print(f"Authorize in your browser (opening {url})", file=sys.stderr)
        webbrowser.open(url)
        while "code" not in received and "error" not in received:
            server.handle_request()
    if "error" in received:
        sys.exit(f"Authorization failed: {received['error'][0]}")
    if "activity:read" not in received.get("scope", [""])[0]:
        sys.exit("Authorization didn't grant activity access - leave the activity checkbox ticked.")

    tokens = token_request(client_id, client_secret, code=received["code"][0], grant_type="authorization_code")
    save_to_dotenv(REFRESH_VAR, tokens["refresh_token"])
    print(f"Saved {REFRESH_VAR} to .env", file=sys.stderr)
    return tokens["access_token"]


def access_token():
    client_id = os.environ.get("STRAVA_CLIENT_ID")
    client_secret = os.environ.get("STRAVA_CLIENT_SECRET")
    if not (client_id and client_secret):
        sys.exit("Set STRAVA_CLIENT_ID and STRAVA_CLIENT_SECRET.")

    refresh = os.environ.get(REFRESH_VAR)
    if not refresh:
        return authorize(client_id, client_secret)
    tokens = token_request(client_id, client_secret, refresh_token=refresh, grant_type="refresh_token")
    if tokens["refresh_token"] != refresh:
        save_to_dotenv(REFRESH_VAR, tokens["refresh_token"])
    return tokens["access_token"]


def get(path, token):
    req = urllib.request.Request(f"{API}{path}", headers={"Authorization": f"Bearer {token}"})
    with urllib.request.urlopen(req) as resp:
        return json.load(resp)


def ride_stats(activity_id, token):
    """Returns (distance m, gain m, loss m, moving s)."""
    activity = get(f"/activities/{activity_id}", token)
    gain_m = activity.get("total_elevation_gain") or 0.0

    # Strava only reports gain; derive loss from net altitude change so it stays
    # consistent with Strava's smoothed gain figure.
    loss_m = gain_m
    try:
        streams = get(f"/activities/{activity_id}/streams?keys=altitude&key_by_type=true", token)
        altitude = streams.get("altitude", {}).get("data") or []
        if altitude:
            loss_m = max(gain_m - (altitude[-1] - altitude[0]), 0.0)
    except urllib.error.HTTPError:
        pass
    return activity["distance"], gain_m, loss_m, activity["moving_time"]


def format_row(distance_m, gain_m, loss_m, moving_s):
    miles = round(distance_m / METERS_PER_MILE)
    gain_ft = round(gain_m * FEET_PER_METER)
    loss_ft = round(loss_m * FEET_PER_METER)
    h, rem = divmod(moving_s, 3600)
    m, s = divmod(rem, 60)
    return f"{miles}mi\t=\"+{gain_ft:,} ft / -{loss_ft:,} ft\"\t{h}:{m:02d}:{s:02d}"


def main():
    load_dotenv()
    # Parsed as TSV so a multi-line cell (pasted as one quoted field) stays one row.
    rows = sys.argv[1:] or ["\t".join(r) for r in csv.reader(io.StringIO(sys.stdin.read()), delimiter="\t")]
    token = access_token()
    for row in rows:
        ids = re.findall(r"activities/(\d+)", row)
        if not ids:
            print()  # keep rows aligned with the input column
            continue
        try:
            # A cell with several rides is summed into one row.
            totals = [sum(col) for col in zip(*(ride_stats(i, token) for i in ids))]
            format = format_row(*totals)
            print(format)
            print(f"SUCCESS {row} -> {format}", file=sys.stderr)
        except urllib.error.HTTPError as e:
            print(f"ERROR {e.code}")
            print(f"{e.url}: {e.code} {e.read().decode(errors='replace')}", file=sys.stderr)


if __name__ == "__main__":
    main()
