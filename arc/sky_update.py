#!/usr/bin/env python3
# sky_update.py - Compute planet and moon positions and write sky.vars
# Portions of this code adapted from gtex62-clean-suite/weather.conky.conf widget by @gtex62, with modifications.
# Requires: pip3 install --user ephem; reads LAT/LON from .conky/alien/.env
# v1.1 2026-04-09 @rew62
"""
sky_update.py – compute planet + moon positions and write sky.vars.
Requires: pip3 install --user ephem
Reads location from: Environment variables LAT and LON in .conky/alien/.env
Writes to: CONKY_CACHE_DIR/sky.vars  (default: /dev/shm/sky.vars)

Keys written:
  MOON_AZ, MOON_ALT, MOON_THETA, MOON_RISE_TS, MOON_SET_TS
  VENUS_AZ,   VENUS_ALT,   VENUS_THETA
  MARS_AZ,    MARS_ALT,    MARS_THETA
  JUPITER_AZ, JUPITER_ALT, JUPITER_THETA
  SATURN_AZ,  SATURN_ALT,  SATURN_THETA
  MERCURY_AZ, MERCURY_ALT, MERCURY_THETA
"""
import math
import os
import sys
import time

try:
    import ephem
except ImportError:
    print("ERROR: PyEphem not installed.  Run:  pip3 install --user ephem", file=sys.stderr)
    sys.exit(1)

from datetime import datetime, timezone

HOME     = os.path.expanduser("~")
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))

# XDG_CACHE = os.environ.get("XDG_CACHE_HOME") or os.path.join(HOME, ".cache")
XDG_CACHE = os.environ.get("XDG_CACHE_HOME") or "/dev/shm"
CACHE_DIR = os.environ.get("CONKY_CACHE_DIR") or os.path.join(XDG_CACHE, "conky")
OUT       = os.path.join(CACHE_DIR, "sky.vars")


def read_vars_file(path):
    """Parse KEY=value lines; returns dict of str→str."""
    result = {}
    try:
        with open(path, encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith("#"):
                    continue
                if "=" in line:
                    k, _, v = line.partition("=")
                    result[k.strip()] = v.strip()
    except OSError:
        pass
    return result


def get_latlon():
    """Return (lat, lon) floats or raise SystemExit."""
    # 1) owm.vars next to this script
    vars_path = os.path.join(SCRIPT_DIR, "owm.vars")
    kv = read_vars_file(vars_path)
    try:
        lat = float(kv["LAT"])
        lon = float(kv["LON"])
        return lat, lon
    except (KeyError, ValueError):
        pass

    # 2) ~/.conky/alien/.env (unified credentials file)
    alien_dir = os.environ.get("ALIEN_DIR") or os.path.join(HOME, ".conky", "alien")
    env_path = os.path.join(alien_dir, ".env")
    kv = read_vars_file(env_path)
    try:
        lat = float(kv.get("LAT") or kv.get("lat", ""))
        lon = float(kv.get("LON") or kv.get("lon", ""))
        return lat, lon
    except (KeyError, ValueError):
        pass

    # 3) environment variables
    try:
        lat = float(os.environ["LAT"])
        lon = float(os.environ["LON"])
        return lat, lon
    except (KeyError, ValueError):
        pass

    print("ERROR: LAT/LON not found.  Set them in owm.vars or as env vars.", file=sys.stderr)
    sys.exit(2)


def deg(rad_val):
    return float(rad_val) * 180.0 / math.pi


def az_to_theta(az_deg):
    """Map azimuth (0=N,90=E,180=S,270=W) to arc-angle (90=0,180=90,270=180)."""
    t = az_deg - 90.0
    return t % 360.0


def ephem_ts(ephem_date):
    """Convert ephem.Date to a Unix timestamp (int)."""
    return int(ephem_date.datetime().replace(tzinfo=timezone.utc).timestamp())


def write_vars(lat, lon):
    obs = ephem.Observer()
    obs.lat       = str(lat)
    obs.lon       = str(lon)
    obs.elevation = 0
    obs.date      = ephem.now()

    bodies = {
        "MOON":    ephem.Moon(),
        "VENUS":   ephem.Venus(),
        "MARS":    ephem.Mars(),
        "JUPITER": ephem.Jupiter(),
        "SATURN":  ephem.Saturn(),
        "MERCURY": ephem.Mercury(),
    }

    lines = [
        f"LAT={lat}",
        f"LON={lon}",
        f"TS={int(time.time())}",
    ]

    for name, body in bodies.items():
        body.compute(obs)
        az_d  = deg(body.az)
        alt_d = deg(body.alt)
        th    = az_to_theta(az_d)

        lines.append(f"{name}_AZ={az_d:.3f}")
        lines.append(f"{name}_ALT={alt_d:.3f}")
        # Only write THETA when body is above the horizon so arc2.lua
        # never draws a planet/moon that is actually below the horizon.
        if alt_d > 0:
            lines.append(f"{name}_THETA={th:.3f}")

        if name == "MOON":
            try:
                # Use previous_rising so the timestamp is in the past when
                # the moon is currently up; next_setting gives the upcoming
                # set time.  Together, now >= rise_ts and now <= set_ts
                # correctly evaluates to True while the moon is above the horizon.
                mr = obs.previous_rising(ephem.Moon())
                ms = obs.next_setting(ephem.Moon())
                lines.append(f"MOON_RISE_TS={ephem_ts(mr)}")
                lines.append(f"MOON_SET_TS={ephem_ts(ms)}")
            except Exception:
                pass

    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    tmp = OUT + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")
    os.replace(tmp, OUT)
    return OUT


if __name__ == "__main__":
    lat, lon = get_latlon()
    out = write_vars(lat, lon)
    # print(out)  # uncomment to debug: prints sky.vars path to stdout
