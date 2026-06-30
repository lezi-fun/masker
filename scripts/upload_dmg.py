#!/usr/bin/env python3
"""Upload Masker DMG to OpenList and get download URL"""
import sys, json, os

try:
    import urllib.request
except ImportError:
    import requests as urllib_request

BASE = "http://45.207.215.85:5244"

# Login
req = urllib.request.Request(
    f"{BASE}/api/auth/login",
    data=json.dumps({"username": "admin", "password": "1234abcd"}).encode(),
    headers={"Content-Type": "application/json"}
)
resp = urllib.request.urlopen(req, timeout=30)
token = json.loads(resp.read())["data"]["token"]
print(f"Token: {token[:20]}...")

# Upload
dmg_path = "/tmp/masker-dmg/Masker-轻量版.dmg"
with open(dmg_path, "rb") as f:
    data = f.read()
print(f"DMG: {len(data)} bytes")

req = urllib.request.Request(
    f"{BASE}/api/fs/put",
    data=data,
    headers={
        "Authorization": token,
        "File-Path": "/Masker-轻量版.dmg",
        "Content-Type": "application/octet-stream",
    },
    method="PUT"
)
resp = urllib.request.urlopen(req, timeout=60)
print(f"Upload: {resp.status} {resp.read().decode()}")

# Get download URL
req = urllib.request.Request(
    f"{BASE}/api/fs/get",
    data=json.dumps({"path": "/Masker-轻量版.dmg"}).encode(),
    headers={"Content-Type": "application/json"},
)
resp = urllib.request.urlopen(req, timeout=30)
result = json.loads(resp.read())
raw_url = result["data"]["raw_url"]
print(f"\nDownload URL:\n{raw_url}")
