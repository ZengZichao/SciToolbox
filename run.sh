#!/bin/bash
# SciToolbox 构建与运行脚本
# 用法：./run.sh [run|build|release|app|install]

cd "$(dirname "$0")"

MODE=${1:-run}

case "$MODE" in
  build)
    echo "🔨 构建中..."
    swift build
    ;;
  run)
    echo "🚀 启动 SciToolbox..."
    swift run SciToolbox
    ;;
  release)
    echo "📦 构建发布版本..."
    swift build -c release
    echo "✅ 发布版本已构建：.build/release/SciToolbox"
    ;;
  app)
    echo "📦 构建 .app 包..."
    ./build-app.sh
    ;;
  install)
    echo "📦 构建 .app 并安装到 /Applications..."
    ./build-app.sh
    cp -R build/SciToolbox.app /Applications/
    echo "✅ 已安装到 /Applications/SciToolbox.app"
    ;;
  *)
    echo "用法: $0 [run|build|release|app|install]"
    echo ""
    echo "  run      - 开发模式运行（默认）"
    echo "  build    - 编译 debug 版本"
    echo "  release  - 编译 release 版本"
    echo "  app      - 打包为 .app 应用"
    echo "  install  - 打包并安装到 /Applications"
    exit 1
    ;;
esac
