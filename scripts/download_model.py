#!/usr/bin/env python3
"""Download Privacy Filter model from HuggingFace"""
import sys, os

try:
    from huggingface_hub import snapshot_download, __version__
except ImportError:
    print("Installing huggingface-hub...", file=sys.stderr)
    os.system("pip3 install huggingface-hub -q")
    from huggingface_hub import snapshot_download, __version__

print(f"huggingface_hub v{__version__}", file=sys.stderr)

model = sys.argv[1] if len(sys.argv) > 1 else "openai/privacy-filter"
out = sys.argv[2] if len(sys.argv) > 2 else "ai-model"

print(f"Downloading {model} to {out} ...", file=sys.stderr)
snapshot_download(model, local_dir=out, local_dir_use_symlinks=False)
print(f"Done. Files:", file=sys.stderr)
for f in os.listdir(out):
    size = os.path.getsize(os.path.join(out, f))
    print(f"  {f} ({size/1024/1024:.1f} MB)", file=sys.stderr)
