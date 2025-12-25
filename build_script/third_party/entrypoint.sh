#!/bin/bash

# entrypoint.sh - openGauss 三方库自动构建脚本

set -e

WORKSPACE=/usr1/build/workspace
DEPS_DIR=$WORKSPACE/dependency/
JDK17_BIN="${DEPS_DIR}/bisheng-jdk-17.0.10-linux-x64.tar.gz"

# 日志
function log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a $WORKSPACE/build.log
}

# 下载源码
function download_from_gitcode() {
    log "步骤1: 下载 openGauss-third_party 源码..."
    cd $WORKSPACE
    if [ ! -d "openGauss-third_party" ]; then
        git clone https://gitcode.com/opengauss/openGauss-third_party.git
        log "源码下载完成"
    else
        log "源码已存在，跳过下载"
    fi
}

# 准备构建环境
function prepare_env() {
    log "步骤2: 准备构建环境..."
    
    cd $WORKSPACE
    
    # 解压现有的二进制库
    if [ -f "openGauss-third_party_binarylibs.tar.gz" ]; then
        mkdir -p openGauss-third_party_binarylibs
        tar -zxf openGauss-third_party_binarylibs.tar.gz -C openGauss-third_party_binarylibs --strip-components 1
        log "已解压现有二进制库"
    else
        log "未找到现有二进制库，将创建新的"
        mkdir -p openGauss-third_party_binarylibs
    fi

    # 检测平台架构
    if [ "$(uname -p)" == "x86_64" ]; then
        os_plat=openeuler_x86_64
        gcc_version=gcc10.3
    else
        os_plat=openeuler_aarch64
        gcc_version=gcc10.3
    fi

    log "检测到平台: $os_plat, 使用 GCC: $gcc_version"

    # 设置 GCC 环境
    export os_platform=$os_plat
    export GCC_PATH=$WORKSPACE/openGauss-third_party_binarylibs/buildtools/$gcc_version/
    if [ -d "$GCC_PATH" ]; then
        export CC=$GCC_PATH/gcc/bin/gcc
        export CXX=$GCC_PATH/gcc/bin/g++
        export LD_LIBRARY_PATH=$GCC_PATH/gcc/lib64:$GCC_PATH/isl/lib:$GCC_PATH/mpc/lib/:$GCC_PATH/mpfr/lib/:$GCC_PATH/gmp/lib/:$LD_LIBRARY_PATH
        export PATH=$GCC_PATH/gcc/bin:$PATH
        log "GCC 环境已设置: $GCC_PATH"
    else
        log "警告: GCC 路径不存在，使用系统 GCC"
    fi

    # 设置 CMake 环境
    cd $WORKSPACE/dependency
    if [ -f "cmake-3.19.5-Linux.tar.gz" ]; then
        mkdir -p cmake
        tar -xf cmake-3.19.5-Linux.tar.gz -C cmake --strip-components 1
        export CMAKEHOME=$WORKSPACE/dependency/cmake
        export LD_LIBRARY_PATH=$CMAKEHOME/lib:$LD_LIBRARY_PATH
        export PATH=$CMAKEHOME/bin:$PATH
        log "CMake 环境已设置: $CMAKEHOME"
    fi

    # 设置 Java 环境
    if [ -f "$JDK17_BIN" ]; then
        THIRD_DIR=$WORKSPACE/buildtools/
        mkdir -p $THIRD_DIR
        tar -zxvf $JDK17_BIN -C $THIRD_DIR > /dev/null
        export JAVA_HOME=$THIRD_DIR/bisheng-jdk-17.0.10
        export LD_LIBRARY_PATH=$JAVA_HOME/lib/:$LD_LIBRARY_PATH
        export PATH=$JAVA_HOME/bin:$PATH
        JAVA_VERSION=$(java -version 2>&1 | head -1)
        log "Java 环境已设置: $JAVA_VERSION"
    fi

    log "环境准备完成"
}

# 编译三方库
function compile_3rd() {
    log "步骤3: 开始编译三方库..."
    
    cd $WORKSPACE/openGauss-third_party/build
    #cd $WORKSPACE/openGauss-third_party/dependency/text-splitter
    log "执行 build_all.sh 编译脚本..."
    log "编译开始时间: $(date '+%Y-%m-%d %H:%M:%S')"
    
    # 执行编译并记录日志
    if sh build_all.sh 2>&1 | tee -a $WORKSPACE/build.log; then
        log "编译成功完成"
        log "编译结束时间: $(date '+%Y-%m-%d %H:%M:%S')"
        return 0
    else
        log "编译失败，请检查日志"
        return 1
    fi
}

# 打包和备份
function package_and_backup() {
    log "步骤4: 打包和备份..."
    cd $WORKSPACE
    
    # 备份旧的压缩包
    if [ -f "openGauss-third_party_binarylibs.tar.gz" ]; then
        backup_name="openGauss-third_party_binarylibs_backup_$(date +%Y%m%d_%H%M%S).tar.gz"
        cp openGauss-third_party_binarylibs.tar.gz "$backup_name"
        log "已备份旧二进制库: $backup_name"
    fi
    
    # 复制编译结果到二进制库目录
    if [ -d "openGauss-third_party/output" ]; then
        log "复制编译结果到三方库目录..."
        cp -rf openGauss-third_party/output/* openGauss-third_party_binarylibs/
        log "编译结果复制完成"
    else
        log "错误: 未找到编译结果目录"
        return 1
    fi
    
    # 创建新的压缩包
    log "创建新的三方包..."
    mv openGauss-third_party_binarylibs/ openGauss-third_party_binarylibs_openEuler_arm/
    tar -czf openGauss-third_party_binarylibs_openEuler_arm.tar.gz openGauss-third_party_binarylibs_openEuler_arm/
    
    # 复制到输出目录供宿主机访问
    mkdir -p $WORKSPACE/output
    cp openGauss-third_party_binarylibs.tar.gz $WORKSPACE/output/
    
    # 显示文件信息
    file_size=$(ls -lh $WORKSPACE/output/openGauss-third_party_binarylibs.tar.gz | awk '{print $5}')
    log "新的三方包已创建: openGauss-third_party_binarylibs_openEuler_arm.tar.gz (大小: $file_size)"
    log "文件已复制到输出目录: $WORKSPACE/output/"
}

# 安装系统依赖
function install_dependencies() {
    log "安装系统依赖包..."
    
    yum install -y \
        bzip2 bzip2-devel curl libaio libaio-devel flex bison ncurses-devel libffi \
        glibc-devel patch dkms readline-devel which git libtool-ltdl-devel \
        autoconf libtool python3 python3-devel python openssl-devel gcc-c++ \
        make hostname iproute dos2unix libzstd xerces-c xerces-c-devel \
        openblas lapack openblas-devel jemalloc-devel libcgroup-devel \
        libcurl-devel libedit-devel libxml2-devel lz4-devel numactl-devel \
        unixODBC-devel zstd zstd-devel java-1.8.0-openjdk-devel openssl-devel \
	    libffi-devel openssl-devel python3-devel zip unzip bzip2 gzip tar \
        --nogpgcheck
    
    log "开始安装py依赖"
    pip3 install pyyaml
    log "yanzhenghuanjing"
    python3 -c "import _ctypes; print('_ctypes module is available')"
    unlink /usr/bin/python
    ln -s /usr/bin/python3 /usr/bin/python
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    source ~/.cargo/env
    pip3 install --upgrade setuptools==46.4.0
    pip3 install setuptools-rust==0.11.4
    log "系统依赖安装完成"
    log "验证依赖"
    python3 -c "import _ctypes; print('_ctypes module is available')"
}

function main() {
    log "================================================"
    log "=== openGauss 三方库自动构建开始 ==="
    log "================================================"
    log "工作目录: $WORKSPACE"
    log "开始时间: $(date '+%Y-%m-%d %H:%M:%S')"
    
    # 安装系统依赖
    install_dependencies
    
    # 执行构建流程
    download_from_gitcode
    prepare_env
    compile_3rd
    package_and_backup
    
    log "================================================"
    log "=== openGauss 三方库自动构建完成 ==="
    log "完成时间: $(date '+%Y-%m-%d %H:%M:%S')"
    log "构建结果: $WORKSPACE/output/openGauss-third_party_binarylibs.tar.gz"
    log "================================================"
}

# 执行主函数
main "$@"
