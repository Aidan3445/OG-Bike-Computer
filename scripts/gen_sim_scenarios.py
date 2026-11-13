"""Writes route and ride GPX pairs for replaying nav edge cases in the watch sim.

Run from the repo root:  python3 -I scripts/gen_sim_scenarios.py

Everything goes to the watch app's SimulatedRides/ folder, which gets bundled.
Files ending in _route.gpx show up as nav routes in the sim picker, the rest as
rides to replay.
"""

import math
import os
from datetime import datetime, timedelta, timezone

ORIGIN = (41.90, -87.70)
SPEED = 6.7  # m/s, about 15 mph
ELE = 180.0
START = datetime(2026, 11, 12, 15, 0, 0, tzinfo=timezone.utc)

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SIM_DIR = os.path.join(ROOT, "OG Bike Computer Watch App", "SimulatedRides")


def to_latlon(east, north):
    lat0, lon0 = ORIGIN
    lat = lat0 + north / 111_320.0
    lon = lon0 + east / (111_320.0 * math.cos(math.radians(lat0)))
    return lat, lon


def densify(vertices, spacing):
    """Points every `spacing` meters along each leg, keeping every vertex."""
    out = [vertices[0]]
    for (x0, y0), (x1, y1) in zip(vertices, vertices[1:]):
        length = math.hypot(x1 - x0, y1 - y0)
        steps = max(1, int(round(length / spacing)))
        for i in range(1, steps + 1):
            t = i / steps
            out.append((x0 + (x1 - x0) * t, y0 + (y1 - y0) * t))
    return out


def walk(vertices):
    """One point per second at SPEED along the polyline."""
    out = [vertices[0]]
    carry = 0.0
    for (x0, y0), (x1, y1) in zip(vertices, vertices[1:]):
        length = math.hypot(x1 - x0, y1 - y0)
        d = SPEED - carry
        while d <= length:
            t = d / length
            out.append((x0 + (x1 - x0) * t, y0 + (y1 - y0) * t))
            d += SPEED
        carry = length - (d - SPEED)
    if out[-1] != vertices[-1]:
        out.append(vertices[-1])
    return out


def along(vertices, distance):
    """The point `distance` meters along the polyline."""
    for (x0, y0), (x1, y1) in zip(vertices, vertices[1:]):
        length = math.hypot(x1 - x0, y1 - y0)
        if length == 0:
            continue
        if distance <= length:
            t = distance / length
            return (x0 + (x1 - x0) * t, y0 + (y1 - y0) * t)
        distance -= length
    return vertices[-1]


def from_along(vertices, distance):
    """The rest of the polyline from `distance` meters along it."""
    rest = [along(vertices, distance)]
    covered = 0.0
    for (x0, y0), (x1, y1) in zip(vertices, vertices[1:]):
        covered += math.hypot(x1 - x0, y1 - y0)
        if covered > distance:
            rest.append((x1, y1))
    return rest


def until_along(vertices, distance):
    """The polyline up to `distance` meters along it."""
    head = [vertices[0]]
    covered = 0.0
    for (x0, y0), (x1, y1) in zip(vertices, vertices[1:]):
        length = math.hypot(x1 - x0, y1 - y0)
        if covered + length >= distance:
            head.append(along(vertices, distance))
            return head
        covered += length
        head.append((x1, y1))
    return head


def write_gpx(path, name, points, timed):
    lines = [
        '<?xml version="1.0" encoding="UTF-8"?>',
        '<gpx version="1.1" creator="Computa sim scenarios" xmlns="http://www.topografix.com/GPX/1/1">',
        f"  <metadata><name>{name}</name></metadata>",
        f"  <trk><name>{name}</name><trkseg>",
    ]
    for i, (x, y) in enumerate(points):
        lat, lon = to_latlon(x, y)
        time = ""
        if timed:
            stamp = (START + timedelta(seconds=i)).strftime("%Y-%m-%dT%H:%M:%SZ")
            time = f"<time>{stamp}</time>"
        lines.append(f'    <trkpt lat="{lat:.7f}" lon="{lon:.7f}"><ele>{ELE}</ele>{time}</trkpt>')
    lines += ["  </trkseg></trk>", "</gpx>", ""]
    with open(path, "w") as f:
        f.write("\n".join(lines))


def route(file_name, name, points):
    write_gpx(os.path.join(SIM_DIR, file_name), name, points, timed=False)


def ride(file_name, name, vertices):
    write_gpx(os.path.join(SIM_DIR, file_name), name, walk(vertices), timed=True)


def main():
    # Straight: a sparse 6 km out leg, then a dense return leg 150 m north.
    out_leg = [(x, 0.0) for x in range(0, 6001, 1500)]
    back_leg = densify([(6000.0, 150.0), (0.0, 150.0)], 20)
    straight = out_leg + back_leg
    route("sim_straight_route.gpx", "Sim Straight", straight)
    ride("sim_straight_exact.gpx", "Sim Straight exact", straight)
    ride("sim_straight_veer.gpx", "Sim Straight veer", [
        (0.0, 0.0), (2000.0, 0.0), (2000.0, -300.0), (3000.0, -300.0), (3000.0, 0.0),
    ] + straight[3:])

    # Near turn: an L, the ride starts 100 m before the corner.
    near_turn = densify([(0.0, 0.0), (1500.0, 0.0), (1500.0, 1500.0)], 25)
    route("sim_near_turn_route.gpx", "Sim Near Turn", near_turn)
    ride("sim_near_turn.gpx", "Sim Near Turn", [(1400.0, 0.0), (1500.0, 0.0), (1500.0, 1500.0)])

    # Ten miles: 8 km east, then north. Halfway is 46 m past the corner.
    total = 16_093.0
    ten_vertices = [(0.0, 0.0), (8000.0, 0.0), (8000.0, total - 8000.0)]
    route("sim_ten_mile_route.gpx", "Sim Ten Mile", densify(ten_vertices, 25))

    def detour(leave_at, rejoin_at):
        rejoin_y = rejoin_at - 8000.0
        return until_along(ten_vertices, leave_at) + [
            (leave_at, -300.0), (8300.0, -300.0), (8300.0, rejoin_y),
        ] + from_along(ten_vertices, rejoin_at)

    ride("sim_ten_rejoin_late.gpx", "Sim Ten rejoin at 70%",
         detour(total * 0.3, total * 0.7))
    ride("sim_ten_rejoin_past_half.gpx", "Sim Ten rejoin half + 0.5 mi",
         detour(total * 0.3, total * 0.5 + 804.67))
    rejoin_y = total * 0.7 - 8000.0
    ride("sim_ten_offroute_start.gpx", "Sim Ten off-route start", [
        (0.0, -150.0), (8150.0, -150.0), (8150.0, rejoin_y),
    ] + from_along(ten_vertices, total * 0.7))


if __name__ == "__main__":
    main()
