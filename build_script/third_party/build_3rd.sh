#!/bin/bash

# build_3rd.sh - openGauss 三方库一键构建脚本

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOCKER_IMAGE_NAME="opengauss-thirdparty-builder:latest"
DOCKER_CONTAINER_NAME="opengauss-build-container-$(date +%Y%m%d%H%M%S)"
VOLUME_DIR="$SCRIPT_DIR/volume"
OUTPUT_DIR="$SCRIPT_DIR/output"
BUILD_LOG="$SCRIPT_DIR/build.log"

echo "================================================"
echo "=== openGauss 三方库一键构建脚本 ==="
echo "================================================"

mkdir -p "$VOLUME_DIR"
mkdir -p "$OUTPUT_DIR"
touch "$BUILD_LOG"

echo "工作目录: $SCRIPT_DIR"
echo "输出目录: $OUTPUT_DIR"
echo "日志文件: $BUILD_LOG"

# 检查 Docker 是否可用
if ! command -v docker &> /dev/null; then
    echo "错误: 未找到 Docker，请先安装 Docker"
    exit 1
fi

echo ""
echo "1. 构建 Docker 镜像..."
if docker build -t "$DOCKER_IMAGE_NAME" .; then
    echo "Docker 镜像构建成功: $DOCKER_IMAGE_NAME"
else
    echo "错误: Docker 镜像构建失败"
    exit 1
fi

echo ""
echo "2. 启动构建容器..."
container_id=$(docker run --privileged=true -d \
  -v "$VOLUME_DIR:/usr1/build/workspace/volume" \
  -v "$OUTPUT_DIR:/usr1/build/workspace/output" \
  -v "$BUILD_LOG:/usr1/build/workspace/build.log" \
  --name "$DOCKER_CONTAINER_NAME" \
  "$DOCKER_IMAGE_NAME")

if [ -n "$container_id" ]; then
    echo "容器已启动: $container_id"
    echo "容器名称: $DOCKER_CONTAINER_NAME"
else
    echo "错误: 容器启动失败"
    exit 1
fi

echo ""
echo "3. 开始构建第三方库..."
echo "构建日志:"
echo "----------------------------------------"

# 实时显示日志
docker logs -f "$DOCKER_CONTAINER_NAME" &
LOG_PID=$!

# 等待容器完成（超时时间设为2小时）
if timeout 7200 docker wait "$DOCKER_CONTAINER_NAME"; then
    wait $LOG_PID 2>/dev/null
else
    echo "警告: 构建超时，强制停止容器..."
    docker stop "$DOCKER_CONTAINER_NAME" >/dev/null 2>&1
    wait $LOG_PID 2>/dev/null
fi

echo "----------------------------------------"

# 检查容器退出状态
exit_code=$(docker inspect "$DOCKER_CONTAINER_NAME" --format='{{.State.ExitCode}}')

echo ""
if [ "$exit_code" -eq 0 ]; then
    echo "构建成功完成！"
    echo ""
    
    # 显示构建结果
    if [ -f "$OUTPUT_DIR/openGauss-third_party_binarylibs.tar.gz" ]; then
        echo "生成的文件:"
        ls -lh "$OUTPUT_DIR"/
        echo ""
        echo "新的三方包: $OUTPUT_DIR/openGauss-third_party_binarylibs.tar.gz"
        
        # 显示文件大小
        file_size=$(ls -lh "$OUTPUT_DIR/openGauss-third_party_binarylibs.tar.gz" | awk '{print $5}')
        echo "📏 文件大小: $file_size"
    fi
    
    # 显示备份信息
    echo ""
    echo "📋 构建日志: $BUILD_LOG"
    
else
    echo "构建失败，退出码: $exit_code"
    echo ""
    echo "请检查日志文件: $BUILD_LOG"
    echo "最后50行日志:"
    tail -50 "$BUILD_LOG"
fi

echo ""
echo "4. 清理容器..."
if docker rm -f "$DOCKER_CONTAINER_NAME" >/dev/null 2>&1; then
    echo "容器已清理: $DOCKER_CONTAINER_NAME"
else
    echo "警告: 容器清理失败"
fi

echo ""
echo "================================================"
echo "=== 构建流程结束 ==="
echo "================================================"

# 返回构建状态
exit $exit_code
