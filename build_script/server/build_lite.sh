#!/bin/bash

cd $WORKSPACE

export CODE_BASE=${WORKSPACE}/openGauss/server_lite
export LOG_FILE=openGauss-lite.log
export VERSION=${PKG_VERSION}

function log() {
    local level="$1"
    local msg_cont="$2"
    date_time=$(date +'%F %H:%M:%S')

    log_format="${date_time} [${level^^}] funcname: ${FUNCNAME[1]} line:$(caller 0 | awk '{print$1}') ${msg_cont}"
    case "${level}" in
        debug)
            echo -e "${log_format}"
            ;;
        info)
            echo -e "${log_format}"
            ;;
        warn)
            echo -e "${log_format}"
            ;;
        error)
            echo -e "${log_format}"
            ;;
    esac
}

function package_lite_server()
{
    cd ${CODE_BASE}/build/script
    chmod +x cmake_package_mini.sh
    sh cmake_package_mini.sh -3rd ${WORKSPACE}/openGauss-third_party_binarylibs -pkg server

    if [ $? -ne 0 ]; then
        die "make install failed."
    fi
}

function main()
{
    echo "====================== start to build lite package ======================="
    package_lite_server
    echo "====================== end to build lite package ======================="

}

main