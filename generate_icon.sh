#!/bin/bash
# Generate Masker app icon
cd "$(dirname "$0")"
export OPENAI_BASE_URL="http://127.0.0.1:23010/v1"
export OPENAI_API_KEY="sk-Hn4niJi0xHDhg4UuJ0VzoSU0vD5jyExHAoFzciTtxVH3Jzl5"
export NO_PROXY="127.0.0.1,localhost"

gpt-image \
  -p "macOS app icon for Masker - a privacy text desensitization tool. A sleek modern shield icon with a subtle lock symbol in its center, made of overlapping translucent paper fragments suggesting text processing. Deep navy blue to purple gradient background. A small shimmering sparkle above the shield suggesting automatic AI detection. Clean rounded-square mac app icon shape, no text, no letters. Professional Apple-style design, high-end minimalism, glossy highlights. Minimalist, elegant, trustworthy feeling." \
  --model gpt-image-2 \
  --size 1024x1024 \
  --quality high \
  --format png \
  -f masker-icon/master.png
