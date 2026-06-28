#!/bin/bash
# ============================================================
# Masker Build Script
# 用法:
#   ./build.sh           # 构建完整版（内置 AI 模型）
#   ./build.sh light     # 构建轻量版（不含 AI）
#   ./build.sh both      # 构建两个版本
# ============================================================
set -e

cd "$(dirname "$0")"
PROJECT="Masker"

build_version() {
    local variant=$1
    local flavor=$2
    local extra_flag=$3

    echo "========================================"
    echo "构建: $variant"
    echo "========================================"

    swift build -c release $extra_flag

    local dest="${PROJECT}.app"
    [ "$flavor" = "light" ] && dest="Masker-轻量版.app"

    mkdir -p "${dest}/Contents/MacOS" "${dest}/Contents/Resources"

    # 1. 可执行文件
    cp ".build/release/${PROJECT}" "${dest}/Contents/MacOS/"

    # 2. Info.plist
    cat > "${dest}/Contents/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>${PROJECT}</string>
    <key>CFBundleIdentifier</key>
    <string>com.lezi.masker${flavor:+.${flavor}}</string>
    <key>CFBundleName</key>
    <string>Masker${flavor:+ ($variant)}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>2.0</string>
    <key>CFBundleVersion</key>
    <string>2</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
PLIST

    # 2.5 嵌入图标
    ICON_SRC="masker-icon/Masker.icns"
    if [ -f "$ICON_SRC" ]; then
        cp "$ICON_SRC" "${dest}/Contents/Resources/"
        # Ensure Info.plist references the icon
        if ! grep -q "CFBundleIconFile" "${dest}/Contents/Info.plist" 2>/dev/null; then
            sed -i '' 's|</dict>|  <key>CFBundleIconFile</key>\n  <string>Masker</string>\n</dict>|' "${dest}/Contents/Info.plist"
        fi
    fi

    # 3. 完整版：打包 AI 模型 + Python 环境 + 脚本
    if [ "$flavor" != "light" ]; then
        echo "打包 AI 模型..."
        local model_dest="${dest}/Contents/Resources/ai-model"
        mkdir -p "$model_dest"
        cp ai-model/config.json "$model_dest/"
        cp ai-model/model.safetensors "$model_dest/"
        cp ai-model/tokenizer_config.json "$model_dest/"
        cp ai-model/tokenizer.json "$model_dest/"

        echo "打包 Python 环境..."
        # 复制 .venv（保留 Python 解释器和依赖库）
        rsync -a --delete .venv/ "${dest}/Contents/Resources/.venv/" --exclude='pip' --exclude='__pycache__'

        echo "打包 Python 脚本..."
        cp privacy_filter.py "${dest}/Contents/Resources/"
        cp extract_text.py "${dest}/Contents/Resources/"
    fi

    echo "✅ ${dest} 构建完成"
    du -sh "${dest}"
}

case "${1:-full}" in
    light)
        build_version "轻量版" "light" "-Xswiftc -DNO_AI"
        ;;
    both)
        build_version "完整版 (AI)" "" ""
        build_version "轻量版" "light" "-Xswiftc -DNO_AI"
        echo ""
        echo "✅ 两个版本都已构建:"
        du -sh "Masker.app" "Masker-轻量版.app"
        ;;
    *)
        build_version "完整版 (AI)" "" ""
        ;;
esac
