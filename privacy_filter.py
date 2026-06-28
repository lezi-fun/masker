#!/usr/bin/env python3
"""
OpenAI Privacy Filter — 封装脚本（内置模型版）
用法: python3 privacy_filter.py --model-dir <path> "文本"
      echo "文本" | python3 privacy_filter.py --model-dir <path>
输出: JSON
"""

import sys
import json
import os

# ── 标签映射 ──
LABEL_MAP = {
    "private_person": "👤 姓名",
    "private_address": "📍 地址",
    "private_email": "📧 邮箱",
    "private_phone": "📞 手机号",
    "private_url": "🔗 URL",
    "private_date": "📅 日期",
    "private_account": "🔑 账号",
    "private_key": "🗝️ 密钥",
}

_model_pipe = None

def load_model(model_dir: str):
    global _model_pipe
    if _model_pipe is not None:
        return _model_pipe

    from transformers import pipeline
    device = "mps" if __import__("torch").backends.mps.is_available() else "cpu"
    _model_pipe = pipeline(
        "token-classification",
        model=model_dir,
        device=device,
        aggregation_strategy="none",
    )
    return _model_pipe


def merge_spans(token_results, original_text=""):
    """Merge consecutive token-level spans with same label into full words."""
    if not token_results:
        return []

    merged = []
    current = None

    for r in token_results:
        label = r.get("entity", "O")
        if label == "O":
            if current:
                merged.append(current)
                current = None
            continue

        base_type = label.lstrip("BIES-")
        score = float(r["score"])
        start = int(r["start"])
        end = int(r["end"])
        word = original_text[start:end] if original_text else r["word"]

        if current is None or current["label"] != base_type:
            if current:
                merged.append(current)
            current = {
                "text": word,
                "label": base_type,
                "type": LABEL_MAP.get(base_type, base_type),
                "score": score,
                "start": start,
                "end": end,
            }
        else:
            if start == current["end"]:
                current["text"] = original_text[current["start"]:end] if original_text else current["text"] + r["word"]
                current["end"] = end
                current["score"] = max(current["score"], score)
            else:
                merged.append(current)
                current = {
                    "text": word,
                    "label": base_type,
                    "type": LABEL_MAP.get(base_type, base_type),
                    "score": score,
                    "start": start,
                    "end": end,
                }

    if current:
        merged.append(current)
    return merged


def detect(text: str, model_dir: str):
    pipe = load_model(model_dir)
    raw = pipe(text)
    spans = merge_spans(raw, original_text=text)

    seen = set()
    output = []
    for s in spans:
        key = (s["start"], s["end"], s["label"])
        if key not in seen:
            seen.add(key)
            output.append(s)
    return output


def main():
    # Parse args: --model-dir <path> [text]
    model_dir = None
    text = None

    args = sys.argv[1:]
    i = 0
    while i < len(args):
        if args[i] == "--model-dir" and i + 1 < len(args):
            model_dir = args[i + 1]
            i += 2
        else:
            # Remaining args are the text
            text_parts = args[i:]
            text = " ".join(text_parts)
            break

    if model_dir is None:
        # Fallback: check env var or default cache location
        model_dir = os.environ.get("MASKER_AI_MODEL_DIR")
        if model_dir is None:
            # Last resort: use bundled path relative to script location
            script_dir = os.path.dirname(os.path.abspath(__file__))
            bundled = os.path.join(script_dir, "ai-model")
            if os.path.isdir(bundled):
                model_dir = bundled

    if model_dir is None or not os.path.isdir(model_dir):
        print(json.dumps({
            "error": f"Model directory not found. Use --model-dir or set MASKER_AI_MODEL_DIR",
            "spans": []
        }, ensure_ascii=False))
        sys.exit(1)

    if text is None:
        text = sys.stdin.read()

    if not text.strip():
        print(json.dumps({"error": "No input text", "spans": []}, ensure_ascii=False))
        return

    spans = detect(text, model_dir)
    result = {
        "text_length": len(text),
        "spans_count": len(spans),
        "spans": spans,
    }
    print(json.dumps(result, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
