#!/usr/bin/env python3
"""uiautomator dump -> okunabilir eleman listesi / koordinat bulucu.

Kullanim:
  ui.py dump                 # ekrandaki tum etkilesimli elemanlar
  ui.py find "Ayarlar"       # metne gore merkez koordinat
  ui.py all                  # metni olan her sey (debug)
"""
import os
import re
import subprocess
import sys
import xml.etree.ElementTree as ET

SERIAL = os.environ.get("SC_SERIAL") or subprocess.run(
    ["adb", "devices"], capture_output=True, text=True
).stdout.splitlines()[1].split()[0]


def adb(*args, binary=False):
    cmd = ["adb", "-s", SERIAL, *args]
    result = subprocess.run(cmd, capture_output=True)
    return result.stdout if binary else result.stdout.decode("utf-8", "replace")


def grab():
    """uiautomator dump cikisini al. Flutter semantics agaci gerekir."""
    for _ in range(3):
        adb("shell", "uiautomator", "dump", "/sdcard/qa_ui.xml")
        xml = adb("shell", "cat", "/sdcard/qa_ui.xml")
        start = xml.find("<?xml")
        if start >= 0 and "</hierarchy>" in xml:
            return xml[start:xml.rindex("</hierarchy>") + len("</hierarchy>")]
    return ""


def center(bounds):
    m = re.match(r"\[(\d+),(\d+)\]\[(\d+),(\d+)\]", bounds)
    if not m:
        return None
    x1, y1, x2, y2 = map(int, m.groups())
    return (x1 + x2) // 2, (y1 + y2) // 2


def nodes(xml):
    try:
        root = ET.fromstring(xml)
    except ET.ParseError as exc:
        print(f"parse error: {exc}", file=sys.stderr)
        return []
    out = []
    for node in root.iter("node"):
        text = (node.get("text") or "").strip()
        desc = (node.get("content-desc") or "").strip()
        label = text or desc
        if not label:
            continue
        pos = center(node.get("bounds", ""))
        if not pos:
            continue
        out.append({
            "label": label,
            "x": pos[0],
            "y": pos[1],
            "class": (node.get("class") or "").split(".")[-1],
            "clickable": node.get("clickable") == "true",
            "enabled": node.get("enabled") == "true",
            "focused": node.get("focused") == "true",
            "bounds": node.get("bounds"),
        })
    return out


def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else "dump"
    xml = grab()
    if not xml:
        print("UI DUMP FAILED (ekran hiyerarsisi alinamadi)")
        return 2
    items = nodes(xml)
    if mode == "find":
        needle = sys.argv[2].lower()
        hits = [i for i in items if needle in i["label"].lower()]
        if not hits:
            print("NOT_FOUND")
            return 1
        for hit in hits:
            print(f"{hit['x']} {hit['y']}  {hit['label']}")
        return 0
    for item in items:
        if mode == "dump" and not item["clickable"]:
            continue
        flags = "".join([
            "C" if item["clickable"] else "-",
            "E" if item["enabled"] else "-",
            "F" if item["focused"] else "-",
        ])
        print(f"{flags} ({item['x']:>4},{item['y']:>4}) {item['class']:<16} {item['label'][:70]}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
