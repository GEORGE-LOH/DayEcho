"""Select an available iPhone from the active Xcode's installed iOS runtimes."""
import json
import re
import sys


def select(devices):
    candidates = []
    for runtime, entries in devices.items():
        match = re.search(r"\.iOS-(\d+)-(\d+)(?:-(\d+))?$", runtime)
        if not match:
            continue
        version = tuple(int(part or 0) for part in match.groups())
        for device in entries:
            if device.get("isAvailable") and device.get("name", "").startswith("iPhone"):
                candidates.append((version, device["name"], device["udid"]))
    if not candidates:
        raise ValueError("No available iPhone simulator in this Xcode installation")
    return max(candidates)[2]


if __name__ == "__main__":
    with open(sys.argv[1], encoding="utf-8") as source:
        print("SIMULATOR_ID=" + select(json.load(source)["devices"]))
